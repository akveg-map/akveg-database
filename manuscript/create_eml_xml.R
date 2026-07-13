# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create EML XML file for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-07-12
# Usage: Script should be executed in R 4.6.0+.
# Description: "Create EML XML file for data archive" parses AKVEG's database schema and dictionary into an EML XML metadata file.
# ---------------------------------------------------------------------------

# Load required packages ----
library(dplyr, warn.conflicts = FALSE)
library(EML)
library(fs)
library(purrr)
library(RPostgres)
library(readr)
library(stringr)
library(tibble)
library(tidyr)
library(yaml)

# Define files and directories ----
drive = 'C:'
root_folder = 'ACCS_Work'
repository_folder = path(drive, root_folder, 'Repositories', 'akveg-database')

# Define SQL authentication file
authentication <- path(drive, root_folder, 'OneDrive - University of Alaska', 
                       'ACCS_Teams', 'Vegetation', 'AKVEG_Database', "Credentials",
                       "akveg_private_build",
                       "authentication_akveg_private_build.csv")

# Define SQL queries
schema_file = path(repository_folder, 'user_tools', 'queries', '00_database_schema.sql')
dictionary_file = path(repository_folder, 'user_tools', 'queries', '00_database_dictionary.sql')

# Define YAML mapping file
field_map_path <- path(repository_folder, 'manuscript', 'map_compiled_fields.yaml')
field_map <- read_yaml(field_map_path)

# Source in functions ----
source(path(repository_folder, 'manuscript', 'utils.R'))

# Connect to the AKVEG Database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)
dbExecute(database_connection, "SET search_path TO public;") ## Define default schema

# Read in database queries ----
schema_query = read_file(schema_file)
dictionary_query = read_file(dictionary_file)

schema_full = as_tibble(dbGetQuery(database_connection, schema_query))
dictionary_full = as_tibble(dbGetQuery(database_connection, dictionary_query))

# Dynamically set compiled folder path ----
## Use latest database version as it appears in the `database_version` table of the database

version_query = "
SELECT major_version, minor_version, patch_version
FROM database_version
WHERE version_id = (
    SELECT
      MAX (version_id)
    FROM
      database_version
);
"
latest_version = as_tibble(dbGetQuery(database_connection, version_query))

## Parse version number into string
major_version_string = str_c("v", latest_version$major_version, sep="")
full_version_string = str_c(major_version_string, 
                     latest_version$minor_version, 
                     latest_version$patch_version, 
                     sep="_")

## Define folder path using version string
compiled_folder = path(drive, root_folder, 'Projects', 'AKVEG_Database', 
                       'Data_Deposit', full_version_string, 'compiled')

# Identify columns in compiled tables ----

# Get file paths and file stems of compiled tables
table_paths <- dir_ls(compiled_folder)
table_stems <- path_file(table_paths) |> 
  path_ext_remove()

# Loop across files and extract column names from each table
compiled_fields_list = list() # Initialize empty list

for (i in 1:length(table_paths)) {
  path = table_paths[i]
  stem = table_stems[i]
  
  # Get column names
  cols = colnames(read_csv(path, n_max = 0, show_col_types = FALSE))
  
  compiled_fields_list[[i]] <- tibble(compiled_table = stem, 
                               field = cols)
}

# Flatten into single dataframe
compiled_fields_df = bind_rows(compiled_fields_list)

# Resolve fields with no match in schema ----
# Some fields in the compiled tables do not exist in the database schema table because they were renamed or brought in from lookup tables during the compilation step

unmatched_fields <- compiled_fields_df |> 
  anti_join(schema_full, by = join_by(compiled_table == schema_table,
                                    field == field)
            )

# Address unmatched fields by mapping them to existing entries in the schema
healed_fields <- map_to_schema_fields(unmatched_fields,
                             schema_full,
                             field_map)

## Ensure that all fields were matched
print(anti_join(unmatched_fields, 
                healed_fields, 
                join_by(compiled_table == schema_table,
                        field == field)
                )
      )

# Restrict database schema to only fields in compiled tables
schema_compiled <- schema_full  |> 
  semi_join(compiled_fields_df, 
            by = join_by(schema_table == compiled_table,
                         field == field)
  )  |> # Restrict full schema to fields in compiled table with a direct match in the schema
  bind_rows(healed_fields) # Add 'unmatched' fields

# Parse SQL schema into EML attributes ----
attribute_table <- schema_compiled |> 
  rename(attributeName = field,
         attributeDefinition = field_description) |> 
  # Populate EML domain based on data type and attribute name
  # Handle exceptions before applying general rules
  mutate(domain = case_when(attributeName %in% c('year_start', 
                                                 'year_end') ~ 'dateTimeDomain',
                            attributeName %in% c('code_akveg', 'definition', 'name_original', 'originator', 'funder', 'manager', 'env_observer', 'soils_observer', 'veg_recorder', 'veg_observer', 'project_name') ~ 'textDomain',
                            attributeName == 'standards_section' ~ 'enumeratedDomain',
                            data_type == 'varchar' & schema_table %in% c('database_dictionary', 'database_schema', 'taxonomy') ~ 'textDomain',
                            (data_type %in% c('smallint', 'integer', 'varchar')) & 
                              grepl(pattern='_id|_code|_description', attributeName) ~ 'textDomain',
                            grepl(pattern='_version', attributeName) ~ 'numericDomain', 
                            attributeName == 'h_datum_epsg' ~ 'textDomain',
                            attributeName == 'plot_dimensions_m' ~ 'textDomain',
                            attributeName == 'horizon_order' ~ 'textDomain',
                            attributeName == 'citation_short' ~ 'textDomain',
                            # Re-classify unambiguous data types
                            data_type == 'boolean' ~ 'textDomain',
                            data_type == 'date' ~ 'dateTimeDomain',
                            data_type == 'text' ~ 'textDomain',
                            data_type == 'serial' ~ 'textDomain',
                            data_type == 'decimal' ~ 'numericDomain',
                            data_type == 'varchar' ~ 'enumeratedDomain',
                            data_type == 'smallint' ~ 'numericDomain',
                            .default = NA
                            )
         ) |> 
  # Populate measurementScale based on domain
  mutate(measurementScale = case_when(attributeName == 'horizon_order' ~ 'ordinal',
                                      grepl("_dd$", attributeName) ~ 'interval', # Define coordinates as interval, not ratio
                                      domain == 'dateTimeDomain' ~ 'dateTime',
                                      domain == 'enumeratedDomain' ~ 'nominal',
                                      domain == 'textDomain' ~ 'nominal',
                                      domain == 'numericDomain' ~ 'ratio',
                                      .default = NA
                                      )
         ) |> 
  # Nominal Fields: Populate definition
  mutate(definition = case_when(measurementScale == 'nominal' ~ attributeDefinition,
                                .default = NA)) |> 
  # dateTime Fields:
  mutate(formatString = case_when(data_type == 'date' ~ 'YYYY-mm-dd',
                                  attributeName %in% c('year_start', 
                                                       'year_end') ~ 'YYYY',
                                  .default = NA)) |>
  # Numeric Fields: Populate unit and numberType
  mutate(unit = case_when(grepl(pattern="_m$", attributeName) 
                          & domain == "numericDomain" ~ 'meter',
                          grepl(pattern="_cm$", attributeName) 
                           & domain == "numericDomain" ~ 'centimeter',
                          grepl(pattern="_m2$", attributeName) 
                           & domain == "numericDomain" ~ 'squareMeter',
                          grepl("_dd$", attributeName) 
                           & domain == "numericDomain" ~ 'degree',
                          grepl(pattern='_percent$|_chroma$|_value$|^number_', attributeName)  ~ 'dimensionless',
                          attributeName %in% c('ph', 'conductivity_mus') ~ 'dimensionless',
                          attributeName == 'temperature_deg_c' ~ 'celsius',
                          attributeName == 'disturbance_time_y' ~ 'nominalYear',
                          .default = NA)
) |> 
  mutate(numberType = case_when(data_type == "decimal" ~ "real",
                                grepl(pattern="_chroma", attributeName) ~ "real",
                                attributeName == "number_stems" ~ "natural",
                                attributeName == "disturbance_time_y" ~ "integer",
                                .default = NA)) |> 
  # Select desired columns
  select(schema_table, attributeName, attributeDefinition, domain, measurementScale, 
         unit, numberType, definition, formatString, schema_table, 
         )

# Quality checks

## Ensure required fields have no nulls
print(attribute_table %>% 
        select(attributeName, attributeDefinition, domain, measurementScale) |> 
  summarise(across(everything(), ~ sum(is.na(.x)))
            )
  )

## Verify consistency between domain and measurement scale
## dateTimeDomain -> dateTime only
## enumeratedDomain and textDomain -> nominal or ordinal
## numericDomain -> interval or ratio
table(attribute_table$domain, 
      attribute_table$measurementScale)

## Verify consistency between domain and domain-specific fields
## Ensure unit_sum and numberType_sum are equal
## dateTimeDomain -> format_sum only
## enumerated and textDomain -> def_sum only
attribute_table |> 
  mutate(def_exists = case_when(is.na(definition) ~ 0,
                                .default = 1),
         unit_exists = case_when(is.na(unit) ~ 0,
                                 .default = 1),
         numberType_exists = case_when(is.na(numberType) ~ 0,
                                       .default = 1),
         format_exists = case_when(is.na(formatString) ~ 0,
                                   .default = 1)
         )|> 
  group_by(domain) |> 
  summarise(def_sum = sum(def_exists),
            format_sum = sum(format_exists),
            unit_sum = sum(unit_exists),
            numberType_sum = sum(numberType_exists)
            )

# Format dictionary table into factors ----

# Define a lookup list for fields that do not have a match in the database dictionary
dictionary_mapping <- list(
  "ground_element" = c("abiotic_element", "ground_element"),
  "scope" = c("scope_vascular", "scope_bryophyte", "scope_lichen"),
  "soil_hue"            = c("matrix_hue_code", "nonmatrix_hue_code"),
  "soil_horizon_suffix" = c("horizon_suffix_1_code", "horizon_suffix_2_code", 
                            "horizon_suffix_3_code", "horizon_suffix_4_code"),
  "soil_horizon_type" = c("horizon_primary_code", "horizon_secondary_code"),
  "soil_texture" = c("dominant_texture_40_cm", "horizon_texture")
)

# Use mapping to resolve missing dictionary entries
dictionary_compiled <- dictionary_full |>
  # Create duplicate_count field based on number of values associated with each key
  mutate(
    duplicate_count = case_when(
      field %in% names(dictionary_mapping) ~ lengths(dictionary_mapping)[field],
      .default = 1
    )
  ) |>
  # Duplicate fields
  uncount(duplicate_count, .id = "duplicate_id") |>
  # Rename fields using names defined in dictionary map
  mutate(
    field = case_when(
      field == 'ground_element' ~ dictionary_mapping[["ground_element"]][duplicate_id],
      field == "scope" ~ dictionary_mapping[["scope"]][duplicate_id],
      field == "soil_hue" ~ dictionary_mapping[["soil_hue"]][duplicate_id],
      field == "soil_horizon_suffix" ~ dictionary_mapping[["soil_horizon_suffix"]][duplicate_id],
      field == "soil_horizon_type" ~ dictionary_mapping[["soil_horizon_type"]][duplicate_id],
      field == "soil_texture" ~ dictionary_mapping[["soil_texture"]][duplicate_id],
      field == "completion" ~ "project_status",
      field == "soil_structure" ~ 'horizon_structure',
      field == 'moisture' ~ 'moisture_regime',
      .default                           = field
    )
  ) |>
  select(-duplicate_id) |>
  # Restrict dictionary to enumeratedDomain attributes
  semi_join(attribute_table |> filter(domain == "enumeratedDomain"), 
            by = join_by(field == attributeName)) |> 
  arrange(field)

# Identify fields in the compiled table that don't have a match in the dictionary
dictionary_missing <- attribute_table |> 
  filter(domain == 'enumeratedDomain') |> 
  anti_join(dictionary_compiled, 
            by = join_by(attributeName == field)
  )



# Rename columns
factors_table <- dictionary_compiled |> 
  rename(attributeName = field,
         code = data_attribute)





# Parse attribute table into nested list
attribute_list <- vector(mode = "list", length = length(table_paths))  # Initialize empty list


for (i in 1:length(table_paths)) {
  path = table_paths[i]
  cols = colnames(read_csv(path, n_max = 0, show_col_types = FALSE))
  attribute_list[[i]] = cols 
}









# Set attributes ----

# Create missing values table
missingvalues_table = attribute_table |> 
  select(attributeName, missingValueCode, missingValueExplanation) |> 
  rename(code = missingValueCode,
         definition = missingValueExplanation)

## Verify consistency between missingValueCode and explanation
attribute_table |> mutate(code_exists = case_when(is.na(missingValueCode) ~ 0,
                                                  .default = 1),
                          explanation_exists = case_when(is.na(missingValueExplanation) ~ 0,
                                                         .default = 1)) |> 
  mutate(both_exist = code_exists + explanation_exists) |> 
  filter(both_exist == 1)  ## Should not be any rows


# create 1 attribute list per data table
attribute_table <- attribute_table |> 
  select(-c(missingValueCode, missingValueExplanation))

set_attributes(
  attribute_table,
  factors_table,
  col_classes = NULL,
  missingvalues_table
)


# Close database connection
