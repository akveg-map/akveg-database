# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create EML XML file for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-07-09
# Usage: Script should be executed in R 4.6.0+.
# Description: "Create EML XML file for data archive" parses AKVEG's database schema and dictionary into an EML XML metadata file.
# ---------------------------------------------------------------------------

# Load required packages ----
library(dplyr, warn.conflicts = FALSE)
library(EML)
library(fs)
library(RPostgres)
library(readr)
library(tibble)

# Define files and directories ----
drive = 'C:'
root_folder = 'ACCS_Work'
repository_folder = path(drive, root_folder, 'Repositories', 'akveg-database')
compiled_folder = path(drive, root_folder, 'Projects', 'AKVEG_Database', 
                       'Data_Deposit', 'v2_10_0', 'compiled')

# Define SQL authentication file
authentication <- path(drive, root_folder, 'OneDrive - University of Alaska', 
                       'ACCS_Teams', 'Vegetation', 'AKVEG_Database', "Credentials",
                       "akveg_public_read",
                       "authentication_akveg_public_read.csv")

# Define SQL queries
schema_file = path(repository_folder, 'user_tools', 'queries', '00_database_schema.sql')
dictionary_file = path(repository_folder, 'user_tools', 'queries', '00_database_dictionary.sql')

# Connect to the AKVEG Database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)

# Read in database tables ----
schema_query = read_file(schema_file)
schema_db = as_tibble(dbGetQuery(database_connection, schema_query))

dictionary_query = read_file(dictionary_file)
dictionary_db = as_tibble(dbGetQuery(database_connection, dictionary_query))

# Identify columns in compiled tables ----
# Some fields in the compiled tables do not exist in the database schema table, nature of compilation step meant fields were renamed or brought in from lookup tables

# Get file paths and file stems of compiled tables
table_paths <- dir_ls(compiled_folder)
table_stems <- path_file(table_paths) |> 
  path_ext_remove()

# Loop across files and extract column names from each table
all_fields_list = list() # Initialize empty list

for (i in 1:length(table_paths)) {
  path = table_paths[i]
  stem = table_stems[i]
  
  # Get column names
  cols = colnames(read_csv(path, n_max = 0, show_col_types = FALSE))
  
  all_fields_list[[i]] <- tibble(compiled_table = stem, 
                               field = cols)
}

# Flatten into single dataframe
all_fields_df = bind_rows(all_fields_list)

# Format schema table into attributes ----
full_attribute_table <- schema_db |> 
  rename(attributeName = field,
         attributeDefinition = field_description) |> 
  # Populate EML domain based on data type and attribute name
  # Handle exceptions before applying general rules
  mutate(domain = case_when(attributeName %in% c('year_start', 
                                                 'year_end') ~ 'dateTimeDomain',
                            attributeName %in% c('project_code', 'establishing_project_code', 'site_code', 'site_visit_code', 'taxon_author', 'taxon_source') ~ 'textDomain',
                            (data_type == 'varchar') & (!is.na(link_table)) ~ 'enumeratedDomain',
                            (data_type %in% c('smallint', 'integer', 'varchar')) & 
                              grepl(pattern='_id|_code', attributeName) ~ 'textDomain',
                            grepl(pattern='_version', attributeName) ~ 'numericDomain', 
                            attributeName == 'h_datum_epsg' ~ 'textDomain',
                            attributeName == 'standards_section' ~ 'enumeratedDomain',
                            attributeName == 'element_type' ~ 'enumeratedDomain',
                            attributeName == 'nonmatrix_feature' ~ 'enumeratedDomain',
                            attributeName == 'plot_dimensions_m' ~ 'enumeratedDomain',
                            attributeName == 'horizon_order' ~ 'textDomain',
                            attributeName == 'citation_short' ~ 'textDomain',
                            attributeName == schema_table ~ 'enumeratedDomain',
                            # Re-classify unambiguous data types
                            data_type == 'boolean' ~ 'textDomain',
                            data_type == 'date' ~ 'dateTimeDomain',
                            data_type == 'text' ~ 'textDomain',
                            data_type == 'serial' ~ 'textDomain',
                            data_type == 'decimal' ~ 'numericDomain',
                            data_type == 'varchar' ~ 'textDomain',
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
  # Populate missingValueCode
  mutate(missingValueCode = case_when(grepl("_chroma$", attributeName) ~ "-1 | -999",
                                      attributeName %in% c('source_date', 'acquisition_date', 'citation_url') ~ "empty",
                                      attributeName == 'cover_percent' ~ NA,
                                      (schema_table %in% c('environment', 'soil_horizons')) & (required == FALSE) ~ "empty",
                                      grepl("-999", attributeDefinition) ~ "-999",
                                      .default = NA)) |>
  mutate(missingValueExplanation = case_when(attributeName == 'source_date' ~ "Date is unknown or dataset was digitized from physical sources",
                                             attributeName == 'acquisition_date' ~ 'Date is unknown, only allowed for datasets acquired before tracking began on 2026-06-19',
                                             attributeName == 'year_end' ~ 'Project is ongoing (end date has not yet occurred)',
                                             attributeName == 'citation_url' ~ 'Citation is unavailable online',
                                             ## Define missing values for environment and soil horizons table
                                             attributeName %in% c("physiography", "geomorphology", "macrotopography", "microtopography") ~ "Not recorded, or could not be resolved to an existing database constraint",
                                             attributeName %in% c("disturbance", "surface_water") ~ "Not recorded",
                                             attributeName == 'disturbance_severity' ~ 'Disturbance is none, or disturbance severity was not recorded',
                                             attributeName == 'disturbance_time_y' ~ 'Disturbance is none, or time since disturbance cannot be determined',
                                             attributeName == 'total_coarse_fragment_percent' ~ 'Not measured, or could not be derived from other measurements',
                                             attributeName == "horizon_texture" ~ "Not recorded, could not be determined due to environmental conditions, or not applicable for the specific horizon (organic horizons cannot have a soil texture)",
                                             grepl("_chroma$", attributeName) ~ "Neutral hue recorded, chroma is null | Not measured",
                                             (schema_table == 'soil_horizons') & 
                                               grepl ("_percent$|_value$", attributeName) ~ 'Not measured',
                                             ## Define missing values for all remaining varchar fields in environment and soil horizons tables
                                             (schema_table %in% c('environment', 'soil_horizons')) & (missingValueCode == 'empty') ~ 'Not recorded, or could not be measured due to environmental conditions',
                                             missingValueCode == "-999" ~ "Not recorded, or could not be measured due to environmental conditions",
                                             .default = NA)) |> 
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
                          & (domain == "numericDomain") ~ 'meter',
                          grepl(pattern="_cm$", attributeName) ~ 'centimeter',
                          grepl(pattern="_m2$", attributeName) ~ 'squareMeter',
                          grepl("_dd$", attributeName) ~ 'degree',
                          grepl(pattern='_percent$|_chroma$|_value$|^number_', attributeName)  ~ 'dimensionless',
                          attributeName %in% c('ph', 'conductivity_mus') ~ 'dimensionless',
                          attributeName == 'temperature_deg_c' ~ 'celsius',
                          attributeName == 'disturbance_time_y' ~ 'nominalYear',
                          .default = NA)) |> 
  mutate(numberType = case_when(data_type == "decimal" ~ "real",
                                grepl(pattern="_chroma", attributeName) ~ "real",
                                attributeName == "number_stems" ~ "natural",
                                attributeName == "disturbance_time_y" ~ "integer",
                                .default = NA)) |> 
  # Select desired columns
  select(attributeName, attributeDefinition, domain, measurementScale, missingValueCode,
         missingValueExplanation, unit, numberType, definition, formatString, schema_table, 
         data_type) |> 
  # Join with columns in core data tables to see what is missing
  right_join(all_fields_df, by = join_by(schema_table == compiled_table,
                                       attributeName == field))

# Quality checks

## Ensure required fields have no nulls
print(full_attribute_table %>% 
        select(attributeName, attributeDefinition, domain, measurementScale) |> 
  summarise(across(everything(), ~ sum(is.na(.x)))
            )
  )

## Verify consistency between domain and measurement scale
table(full_attribute_table$domain, 
      full_attribute_table$measurementScale)

## Verify consistency between missingValueCode and explanation
full_attribute_table |> mutate(code_exists = case_when(is.na(missingValueCode) ~ 0,
                                                  .default = 1),
                          explanation_exists = case_when(is.na(missingValueExplanation) ~ 0,
                                                         .default = 1)) |> 
  mutate(both_exist = code_exists + explanation_exists) |> 
  filter(both_exist == 1)  ## Should not be any rows

## Verify consistency between domain and domain-specific fields
## Ensure unit_sum and numberType_sum are equal
full_attribute_table |> 
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

# Parse full attribute table into nested list
attribute_list <- vector(mode = "list", length = length(table_paths))  # Initialize empty list


for (i in 1:length(table_paths)) {
  path = table_paths[i]
  cols = colnames(read_csv(path, n_max = 0, show_col_types = FALSE))
  attribute_list[[i]] = cols 
}

# Remove duplicates
unique_cols = unique(all_cols)






# Format dictionary table into factors ----

# Rename columns
factors_table <- dictionary_db |> 
  rename(attributeName = field,
         code = data_attribute)









# Set attributes ----

# Create missing values table
missingvalues_table = full_attribute_table |> 
  select(attributeName, missingValueCode, missingValueExplanation) |> 
  rename(code = missingValueCode,
         definition = missingValueExplanation)

# create 1 attribute list per data table
attribute_table <- full_attribute_table |> 
  select(-c(missingValueCode, missingValueExplanation))

set_attributes(
  attribute_table,
  factors_table,
  col_classes = NULL,
  missingvalues_table
)


# Close database connection
