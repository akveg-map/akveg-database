# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create compiled dictionary for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-07-14
# Usage: Script should be executed in R 4.6.1+.
# Description: "Create compiled dictionary for data archive" aligns the AKVEG Database dictionary with the tables and fields included in the data package.
# ---------------------------------------------------------------------------

# Load required packages ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(RPostgres)
library(readr)
library(tidyr)

# Define files and directories ----
drive <- "C:"
root_folder <- "ACCS_Work"
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")
archive_folder <- path(drive, root_folder, "Projects", "AKVEG_Database", "Data_Deposit")

## SQL authentication file
authentication <- path(drive, root_folder, "OneDrive - University of Alaska",
                       "ACCS_Teams", "Vegetation", "AKVEG_Database", "Credentials",
                       "akveg_private_build", "authentication_akveg_private_build.csv")

## Dictionary query
dictionary_file <- path(repository_folder, "user_tools", "queries", "00_database_dictionary.sql")

## Dictionary mapping for boolean fields
boolean_dictionary_path <- path(repository_folder, "manuscript", "config", "dictionary_boolean.csv")

# Source in functions
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
source(path(repository_folder, "manuscript", "utils.R"))

# Connect to the AKVEG Database ----
database_connection <- connect_database_postgresql(authentication)
dbExecute(database_connection, "SET search_path TO public;") ## Define default schema

# Dynamically set folder path ----
## Using latest database version
full_version_string <- get_latest_version(db_conn = database_connection)
compiled_folder <- path(archive_folder, full_version_string, "data_package")

# Read in files ----
boolean_dictionary <- read_csv(boolean_dictionary_path,
                               col_types = cols(.default = "c"),  # Force boolean column to be read as character
                               show_col_types = FALSE)

## Execute query
dictionary_query <- read_file(dictionary_file)
dictionary_full <- dbGetQuery(database_connection, dictionary_query)

# Define lookup list ----
## For fields that do not have a match in the database dictionary
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

# Resolve missing fields ----
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
  # Bring in custom boolean dictionary
  bind_rows(boolean_dictionary) |> 
  # Restrict dictionary to enumeratedDomain attributes
  semi_join(attribute_table |> filter(domain == "enumeratedDomain"),
            by = join_by(field == attributeName)
  ) |>
  arrange(field) 

# Export as CSV ----
write_csv(dictionary_compiled, 
          file = path(compiled_folder, "database_dictionary.csv"),
          na = "")
