# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create EML XML file for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-07-13
# Usage: Script should be executed in R 4.6.1+.
# Description: "Create EML XML file for data archive" parses AKVEG's database schema and dictionary into an EML XML metadata file.
# ---------------------------------------------------------------------------

# Load required packages ----
library(dplyr, warn.conflicts = FALSE)
library(EML)
library(fs)
library(lubridate)
library(purrr)
library(RPostgres)
library(readr)
library(stringr)
library(tibble)
library(tidyr)
library(yaml)

# Define files and directories ----
drive <- "C:"
root_folder <- "ACCS_Work"
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")

# Define SQL authentication file
authentication <- path(
  drive, root_folder, "OneDrive - University of Alaska",
  "ACCS_Teams", "Vegetation", "AKVEG_Database", "Credentials",
  "akveg_private_build",
  "authentication_akveg_private_build.csv"
)

# Define SQL queries
schema_file <- path(repository_folder, "user_tools", "queries", "00_database_schema.sql")
dictionary_file <- path(repository_folder, "user_tools", "queries", "00_database_dictionary.sql")

# Define and read in config files
field_map_path <- path(repository_folder, "manuscript", "map_compiled_fields.yaml")
custom_overrides_path <- path(repository_folder, "manuscript", "eml_overrides.csv")

field_map <- read_yaml(field_map_path)
custom_overrides <- read_csv(custom_overrides_path,
  show_col_types = FALSE
)

# Source in functions ----
source(path(repository_folder, "manuscript", "utils.R"))

# Connect to the AKVEG Database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)
dbExecute(database_connection, "SET search_path TO public;") ## Define default schema

# Read in database queries ----
schema_query <- read_file(schema_file)
dictionary_query <- read_file(dictionary_file)

schema_full <- as_tibble(dbGetQuery(database_connection, schema_query))
dictionary_full <- as_tibble(dbGetQuery(database_connection, dictionary_query))

# Dynamically set compiled folder path ----
## Use latest database version as it appears in the `database_version` table of the database

version_query <- "
SELECT major_version, minor_version, patch_version
FROM database_version
WHERE version_id = (
    SELECT
      MAX (version_id)
    FROM
      database_version
);
"
latest_version <- as_tibble(dbGetQuery(database_connection, version_query))

## Parse version number into string
major_version_string <- str_c("v", latest_version$major_version, sep = "")
full_version_string <- str_c(major_version_string,
  latest_version$minor_version,
  latest_version$patch_version,
  sep = "_"
)

## Define folder path using version string
compiled_folder <- path(
  drive, root_folder, "Projects", "AKVEG_Database",
  "Data_Deposit", full_version_string, "compiled"
)

# Identify columns in compiled tables ----

# Get file paths and file stems of compiled tables
table_paths <- dir_ls(compiled_folder)
table_stems <- path_file(table_paths) |>
  path_ext_remove()

# Loop across files and extract column names from each table
compiled_fields_list <- list() # Initialize empty list

for (i in 1:length(table_paths)) {
  path <- table_paths[i]
  stem <- table_stems[i]

  # Get column names
  cols <- colnames(read_csv(path, n_max = 0, show_col_types = FALSE))

  compiled_fields_list[[i]] <- tibble(
    compiled_table = stem,
    field = cols
  )
}

# Flatten into single dataframe
compiled_fields_df <- bind_rows(compiled_fields_list)

# Resolve fields with no match in schema ----
# Some fields in the compiled tables do not exist in the database schema table because they were renamed or brought in from lookup tables during the compilation step

unmatched_fields <- compiled_fields_df |>
  anti_join(schema_full, by = join_by(
    compiled_table == schema_table,
    field == field
  ))

# Address unmatched fields by mapping them to existing entries in the schema
healed_fields <- map_to_schema_fields(
  unmatched_fields,
  schema_full,
  field_map
)

## Ensure that all fields were matched
print(anti_join(
  unmatched_fields,
  healed_fields,
  join_by(
    compiled_table == schema_table,
    field == field
  )
))

# Restrict database schema to only fields in compiled tables
schema_compiled <- schema_full |>
  semi_join(compiled_fields_df,
    by = join_by(
      schema_table == compiled_table,
      field == field
    )
  ) |> # Restrict full schema to fields in compiled table with a direct match in the schema
  bind_rows(healed_fields) # Add 'unmatched' fields

# Parse SQL schema into EML attributes ----

# Define fields requiring custom classification
text_domain_fields <- c(
  "originator", "funder", "manager", "h_datum_epsg",
  "plot_dimensions_m", "horizon_order", "citation_short",
  "standards_section"
)
text_tables <- c("database_dictionary", "database_schema", "taxonomy")
year_fields <- c("year_start", "year_end")

attribute_table <- schema_compiled |>
  rename(
    attributeName = field,
    attributeDefinition = field_description
  ) |>
  left_join(custom_overrides, by = join_by("attributeName")) |>
  # If specified, overwrite schema definitions with custom ones
  mutate(attributeDefinition = coalesce(customDefinition, attributeDefinition)) |>
  # Populate EML domain based on data type and attribute name
  mutate(domain = case_when(attributeName %in% year_fields ~ "dateTimeDomain",
    attributeName %in% text_domain_fields ~ "textDomain",
    data_type == "varchar" & schema_table %in% text_tables ~ "textDomain",
    grepl(pattern = "_id|_code|_description|name|observer|recorder", attributeName) ~ "textDomain",
    grepl(pattern = "_version", attributeName) ~ "numericDomain",
    # Re-classify unambiguous data types
    data_type == "date" ~ "dateTimeDomain",
    data_type %in% c("boolean", "text", "serial") ~ "textDomain",
    data_type %in% c("smallint", "decimal") ~ "numericDomain",
    data_type == "varchar" ~ "enumeratedDomain", # Assume all character fields are enumeratedDomain unless custom override exists
    .default = NA
  )) |>
  # Populate measurementScale based on domain
  mutate(measurementScale = case_when(attributeName == "horizon_order" ~ "ordinal",
    grepl("_dd$", attributeName) ~ "interval", # For coordinate fields
    domain == "dateTimeDomain" ~ "dateTime",
    domain == "enumeratedDomain" ~ "nominal",
    domain == "textDomain" ~ "nominal",
    domain == "numericDomain" ~ "ratio",
    .default = NA
  )) |>
  # Nominal Fields: Populate definition
  mutate(definition = case_when(measurementScale == "nominal" ~ attributeDefinition,
    .default = NA
  )) |>
  # dateTime Fields: Populate formatString
  mutate(formatString = case_when(data_type == "date" ~ "YYYY-mm-dd",
    attributeName %in% year_fields ~ "YYYY",
    .default = NA
  )) |>
  # Numeric Fields: Populate unit and numberType
  mutate(
    unit = coalesce(
      customUnit,
      case_when(
        grepl(pattern = "_percent$|_chroma$|_value$|^number_", attributeName) ~ "dimensionless",
        grepl(pattern = "_cm$", attributeName) &
          domain == "numericDomain" ~ "centimeter",
        .default = NA
      )
    ),
    numberType = case_when(data_type == "decimal" ~ "real",
      grepl(pattern = "_chroma", attributeName) ~ "real",
      attributeName == "number_stems" ~ "natural",
      attributeName == "disturbance_time_y" ~ "integer",
      .default = NA
    )
  ) |>
  # Select desired columns
  select(
    schema_table, attributeName, attributeDefinition, domain, measurementScale,
    unit, numberType, definition, formatString, schema_table
  )

# Quality checks ----

## Ensure required fields have no nulls
print(attribute_table %>%
  select(attributeName, attributeDefinition, domain, measurementScale) |>
  summarise(across(everything(), ~ sum(is.na(.x)))))

## Verify consistency between domain and measurement scale
## dateTimeDomain -> dateTime only
## enumeratedDomain and textDomain -> nominal or ordinal
## numericDomain -> interval or ratio
table(
  attribute_table$domain,
  attribute_table$measurementScale
)

## Verify consistency between domain and domain-specific fields
## Ensure unit_sum and numberType_sum are equal
## dateTimeDomain -> format_sum only
## enumerated and textDomain -> def_sum only
attribute_table |>
  mutate(
    def_exists = case_when(is.na(definition) ~ 0,
      .default = 1
    ),
    unit_exists = case_when(is.na(unit) ~ 0,
      .default = 1
    ),
    numberType_exists = case_when(is.na(numberType) ~ 0,
      .default = 1
    ),
    format_exists = case_when(is.na(formatString) ~ 0,
      .default = 1
    )
  ) |>
  group_by(domain) |>
  summarise(
    def_sum = sum(def_exists),
    format_sum = sum(format_exists),
    unit_sum = sum(unit_exists),
    numberType_sum = sum(numberType_exists)
  )

# Parse dictionary table into factor list ----

# Define a lookup list for fields that do not have a match in the database dictionary
dictionary_mapping <- list(
  "ground_element" = c("abiotic_element", "ground_element"),
  "scope" = c("scope_vascular", "scope_bryophyte", "scope_lichen"),
  "soil_hue" = c("matrix_hue_code", "nonmatrix_hue_code"),
  "soil_horizon_suffix" = c(
    "horizon_suffix_1_code", "horizon_suffix_2_code",
    "horizon_suffix_3_code", "horizon_suffix_4_code"
  ),
  "soil_horizon_type" = c("horizon_primary_code", "horizon_secondary_code"),
  "soil_texture" = c("dominant_texture_40_cm", "horizon_texture")
)

# Resolve missing dictionary entries using mapping
factors_table <- dictionary_full |>
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
      field == "ground_element" ~ dictionary_mapping[["ground_element"]][duplicate_id],
      field == "scope" ~ dictionary_mapping[["scope"]][duplicate_id],
      field == "soil_hue" ~ dictionary_mapping[["soil_hue"]][duplicate_id],
      field == "soil_horizon_suffix" ~ dictionary_mapping[["soil_horizon_suffix"]][duplicate_id],
      field == "soil_horizon_type" ~ dictionary_mapping[["soil_horizon_type"]][duplicate_id],
      field == "soil_texture" ~ dictionary_mapping[["soil_texture"]][duplicate_id],
      field == "completion" ~ "project_status",
      field == "soil_structure" ~ "horizon_structure",
      field == "moisture" ~ "moisture_regime",
      .default = field
    )
  ) |>
  select(-duplicate_id) |>
  # Restrict dictionary to enumeratedDomain attributes
  semi_join(attribute_table |> filter(domain == "enumeratedDomain"),
    by = join_by(field == attributeName)
  ) |>
  arrange(field) |>
  rename(
    attributeName = field,
    code = data_attribute
  ) # Rename columns to match EML schema

# Verify if any fields in the compiled table don't have a match in the dictionary
print(attribute_table |>
  filter(domain == "enumeratedDomain") |>
  anti_join(factors_table,
    by = join_by(attributeName)
  ))

# Create missing values list ----
missing_values <- schema_compiled |>
  # Add missing value codes
  mutate(
    missing_value_code = case_when(field %in% c("env_observer", "soils_observer") ~ "none",
      .default = missing_value_code
    ),
    missing_value_description = case_when(field %in% c("env_observer", "soils_observer") ~ "Observer name not recorded because corresponding data were not collected.",
      .default = missing_value_description
    )
  ) |>
  filter(!is.na(missing_value_code)) |>
  select(schema_table, field, missing_value_code, missing_value_description) |>
  rename(
    attributeName = field,
    code = missing_value_code,
    definition = missing_value_description
  )

# Create EML data table for each attribute ----
all_data_tables <- list() # Initialize empty list for storing results

for (i in 1:length(compiled_fields_list)) {
  current_table <- unique(compiled_fields_list[[i]]$compiled_table)
  current_filename <- str_c(current_table, ".csv")
  current_fields <- compiled_fields_list[[i]]$field

  # Filter master EML tables for the specific compiled table
  current_attributes <- attribute_table |>
    filter(schema_table == current_table) |>
    select(-schema_table)
  current_factors <- factors_table |> filter(attributeName %in% current_fields)
  current_missing <- missing_values |>
    filter(schema_table == current_table) |>
    select(-schema_table)

  if (nrow(current_missing) == 0) {
    attributeList <- set_attributes(
      attributes = current_attributes,
      factors = current_factors
    )
  } else {
    attributeList <- set_attributes(
      attributes = current_attributes,
      factors = current_factors,
      missingValues = current_missing
    )
  }

  # Define constraints
  current_constraints <- list()
  constraints_mapping <- list(
    name_adjudicated = "taxon_name",
    name_accepted    = "taxon_accepted"
  )
  
  existing_constraints <- intersect(names(constraints_mapping), current_fields)
  
  for (foreign_key in existing_constraints){
    constraint_name = str_c(current_table,
                            foreign_key,
                            "link", 
                            sep="_")
    
    current_constraints[[length(current_constraints) + 1]] = create_taxonomy_constraint(
      constraint_name = constraint_name,
      foreign_key_name = foreign_key,
      primary_key_name = constraints_mapping[[foreign_key]]
      )
  
  }
  
  # Define file name and format
  current_physical <- set_physical(current_filename,
    encoding = "UTF-8"
  )

  # Define entity description
  filtered_dictionary <- dictionary_full |>
    filter(field == "schema_table" & data_attribute == current_table)

  if (current_table == "taxonomy") {
    current_entity_description <- "Comprehensive taxonomic checklist table of accepted names, synonyms, authorities, and unknown/functional group codes for Alaska and adjacent Canadian. Covers vascular plants, bryophytes, and lichens ranging from genus to infraspecies."
  } else if (nrow(filtered_dictionary) == 0) {
    warning(str_c("Table ", current_table, " was not found in the data dictionary"))
    clean_table_name <- str_replace_all(current_table, "_", " ")
    current_entity_description <- str_c("Table containing observations for ",
      clean_table_name, ".",
      sep = ""
    )
  } else {
    current_entity_description <- filtered_dictionary |>
      pull(definition) |>
      as.character()
  }

  # Read in CSV to obtain row count
  row_count <- as.character(nrow(read_csv(path(compiled_folder, current_filename),
    show_col_types = FALSE
  )))

  # Assemble EML data table
  current_data_table <- eml$dataTable(
    entityName = current_filename,
    entityDescription = current_entity_description,
    physical = current_physical,
    attributeList = attributeList,
    numberOfRecords = row_count,
    id = str_c("entity", current_table, sep = "_"),
    constraint = current_constraints
  )

  # Append to all tables list
  all_data_tables[[i]] <- current_data_table
  names(all_data_tables)[[i]] <- current_table
}

# Define taxonomic coverage ----
taxonomic_classification_list <- list(
  # Vascular plants & bryophytes
  list(
    taxonRankName = "Kingdom",
    taxonRankValue = "Plantae",
    taxonClassification = list(
      list(taxonRankName = "Phylum", taxonRankValue = "Tracheophyta"),
      list(taxonRankName = "Phylum", taxonRankValue = "Bryophyta")
    )
  ),
  # Lichens
  list(
    taxonRankName = "Kingdom",
    taxonRankValue = "Fungi",
    taxonClassification = list(
      list(taxonRankName = "Phylum", taxonRankValue = "Ascomycota"),
      list(taxonRankName = "Phylum", taxonRankValue = "Basidiomycota")  # e.g., Lichenomphalia
    )
  )
)

# Define checklist authors
checklist_creators = list(
  list(individualName = list(givenName = "Timm", surName = "Nawrocki")),
  list(individualName = list(givenName = "Caroline", surName = "Parker")),
  list(individualName = list(givenName = "James", surName = "Walton")),
  list(individualName = list(givenName = "Preston", surName = "Villumsen")),
  list(individualName = list(givenName = "Bruce", surName = "Bennett")),
  list(individualName = list(givenName = "Matthew", surName = "Carlson")),
  list(individualName = list(givenName = "John", surName = "DeLapp")),
  list(individualName = list(givenName = "Justin", surName = "Fulkerson")),
  list(individualName = list(givenName = "Martin", surName = "Hutten")), 
  list(individualName = list(givenName = "Brian", surName = "Heitz")), 
  list(individualName = list(givenName = "Stefanie", surName = "Ickert-Bond")), 
  list(individualName = list(givenName = "Mary", surName = "Stensvold")), 
  list(individualName = list(givenName = "Campbell", surName = "Webb"))
)

# Assemble taxonomic coverage
taxonomic_coverage <- eml$taxonomicCoverage(
  generalTaxonomicCoverage = "Taxonomic coverage includes vascular plants, bryophytes, and lichens, but varies by project and individual site visit. Among the 44,324 unique site visits in the AKVEG Database, 65% recorded exhaustive, species-level data of vascular plants. In contrast, bryophyte and lichen records are generally limited to dominant species (55% of site visits) or absent (29% of visits). Taxonomic coverage of individual site visits is documented in this data package's `site_visit` table with separate fields for vascular plants, bryophytes, and lichens.",
  taxonomicSystem = list(
    classificationSystem = "Checklist of Vascular Plants, Bryophytes, Lichens, and Lichenicolous Fungi of Alaska",
      classificationSystemCitation = list(
        title = "Checklist of Vascular Plants, Bryophytes, Lichens, and Lichenicolous Fungi of Alaska",
        creator = checklist_creators,
        pubDate = "2024",
        
        distribution = list(
          online = list(
            onlineDescription = "Online interface for browsing the taxonomic checklist; the version in this data package contains minor updates and was the version used to standardize taxonomy across datasets.",
            url = list(
              "https://akveg.org/taxonomic-standard/", 
              `function` = "information"
      )
    )
    ),
  taxonomicClassification = taxonomic_classification_list
  )
  )
)

# Define geographic coverage ----
## Create two separate bounding boxes to handle the international date line

# Bounding Box 1: Western Hemisphere
bbox_west <- eml$geographicCoverage(
  geographicDescription = "Western Hemisphere component of the AKVEG Database from the 180th Meridian eastward to the easternmost plot in the Northwest Territories, Canada.",
  boundingCoordinates = list(
    westBoundingCoordinate = "-180.00000",
    eastBoundingCoordinate = "-123.00000",
    northBoundingCoordinate = "71.27648",
    southBoundingCoordinate = "52.70761"
  )
)

# Bounding Box 2: Eastern Hemisphere (Aleutian Islands)
bbox_east <- eml$geographicCoverage(
  geographicDescription = "Eastern Hemisphere component of the AKVEG Database from the westernmost plot in the western Aleutian Islands eastward to the 180th Meridian.",
  boundingCoordinates = list(
    westBoundingCoordinate = "174.15216",
    eastBoundingCoordinate = "180.00000",
    northBoundingCoordinate = "71.27648",
    southBoundingCoordinate = "52.70761"
  )
)

# Combine both bounding boxes to create overall geographic coverage
geographic_coverage <- list(bbox_west, bbox_east)

# Define temporal coverage ----

# Get min/max dates from compiled table
site_visit_dates = read_csv(path(compiled_folder, "site_visit.csv"),
                      col_select = "observe_date",
                      col_types = "D") |>  # Set to Date
  summarize(min_date = min(observe_date),
            max_date = max(observe_date)) |> 
  mutate(across(where(is.Date), as.character))

temporal_coverage <- eml$temporalCoverage(
  rangeOfDates = eml$rangeOfDates(
    beginDate = eml$beginDate(calendarDate = site_visit_dates$min_date),
    endDate = eml$endDate(calendarDate = site_visit_dates$max_date)
  )
)

# Set global coverage object
global_coverage <- eml$coverage(
  geographicCoverage = geographic_coverage,
  temporalCoverage = temporal_coverage,
  taxonomicCoverage = taxonomic_coverage
)

# Delete intermediate products
rm(geographic_coverage, temporal_coverage, taxonomic_coverage, taxonomic_classification_list, 
   bbox_west, bbox_east, site_visit_dates)

# Clean up workspace ----
dbDisconnect(database_connection)
rm(list = ls())
