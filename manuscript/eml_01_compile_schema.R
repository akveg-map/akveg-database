# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create compiled schema for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-07-14
# Usage: Script should be executed in R 4.6.1+.
# Description: "Create compiled schema for data archive" aligns the AKVEG Database schema with the tables and fields included in the data package.
# ---------------------------------------------------------------------------

# Load required packages ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(RPostgres)
library(readr)
library(tibble)
library(yaml)

# Define files and directories ----
drive <- "C:"
root_folder <- "ACCS_Work"
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")
archive_folder <- path(drive, root_folder, "Projects", "AKVEG_Database", "Data_Deposit")

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

# Define config files
field_map_path <- path(repository_folder, "manuscript", "config", "map_compiled_fields.yaml")

# Read in files & functions ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
source(path(repository_folder, "manuscript", "utils.R"))

field_map <- read_yaml(field_map_path)

# Connect to the AKVEG Database ----
database_connection <- connect_database_postgresql(authentication)
dbExecute(database_connection, "SET search_path TO public;") ## Define default schema

# Dynamically set folder path ----
## Using latest database version
full_version_string <- get_latest_version(db_conn = database_connection)
compiled_folder <- path(archive_folder, full_version_string, "data_package")

# Query metadata tables from database ----
schema_query <- read_file(schema_file)
dictionary_query <- read_file(dictionary_file)

schema_full <- as_tibble(dbGetQuery(database_connection, schema_query))
dictionary_full <- as_tibble(dbGetQuery(database_connection, dictionary_query))

# Get fields from compiled tables ----

# Define file paths and stems
table_paths <- dir_ls(compiled_folder, 
                      glob="*.csv")
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
  
  # Append table name to list
  names(compiled_fields_list)[[i]] <- stem
}

# Add schema and dictionary fields if not already in data package
documentation_tables <- list(
  database_schema = colnames(schema_full),
  database_dictionary = colnames(dictionary_full)
)


for (table_name in names(documentation_tables)) {
  
  if (!table_name %in% names(compiled_fields_list)) {
    cols <- documentation_tables[[table_name]]
    new_index <- length(compiled_fields_list) + 1
    compiled_fields_list[[new_index]] <- tibble(
      compiled_table = table_name,
      field = cols
    )
    
    # Append table name to list
    names(compiled_fields_list)[[new_index]] <- table_name
  }
}

# Flatten into single data frame
compiled_fields_df <- bind_rows(compiled_fields_list)

# Resolve fields with no match in schema ----
## Some fields in the compiled tables do not exist in the database schema table because they were renamed or brought in from lookup tables during the compilation step
unmatched_fields <- compiled_fields_df |>
  anti_join(schema_full, by = join_by(
    compiled_table == schema_table,
    field == field
  ))

# Map unmatched fields to existing schema entries
healed_fields <- map_to_schema_fields(
  unmatched_fields,
  schema_full,
  field_map
  )

## Ensure that all fields were matched
print(anti_join(unmatched_fields,
                healed_fields,
                join_by(compiled_table == schema_table,
                        field == field)
                )
      )

# Create compiled data schema ----
## Restrict database schema to only fields in compiled tables
schema_compiled <- schema_full |>
  semi_join(compiled_fields_df,
            by = join_by(schema_table == compiled_table,
                         field == field
                         )
            ) |>
  bind_rows(healed_fields) # Add 'unmatched' fields

# Export as CSV ----
write_csv(schema_compiled, 
          file = path(compiled_folder, "database_schema.csv"), 
          na = "")

# Clean up workspace ----
dbDisconnect(database_connection)
rm(list = ls())
