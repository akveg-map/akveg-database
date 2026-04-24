# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Combine data tables
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-22
# Usage: Script should be executed in R 4.5.1+.
# Description: "Combine data tables" combines data from processed datasets into single CSV files. The CSV files can then be converted into a SQL statement for upload to the AKVEG database. The script requires metadata tables to be inserted into the AKVEG Database.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(purrr)
library(readr)
library(readxl)
library(rjson)
library(RPostgres)
library(stringr)
library(tibble)
library(yaml)

# Define folder structure ----

# Set root directory
drive <- "C:"
root_folder <- "ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"

# Define input folders
data_folder <- path(drive, root_folder, "Data/Data_Plots")
repository_folder <- path(drive, "ACCS_Work/Repositories/akveg-database")
credential_folder <- path(drive, root_folder, "Credentials")

# Define input files ----
project_list <- path(repository_folder, "03_data_insert", "config", "List_Included_Projects.json")
queries_input <- path(repository_folder, "03_data_insert", "config", "queries_lookup.yaml")
metadata_input <- path(repository_folder, "03_data_insert", "config", "tables_metadata.csv")
source_input <- path(drive, root_folder, "Data", "Tables_Metadata", "project_source.xlsx")

# Define functions ----
source(path(repository_folder, "03_data_insert", "helper_functions.R"))

# Connect to AKVEG database ----

# Import database connection function
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))

# Create a connection to the AKVEG PostgreSQL database
authentication <- path(
  credential_folder, "akveg_private_build",
  "authentication_akveg_private_build.csv"
)
database_connection <- connect_database_postgresql(authentication)

# Read in files ----
# 1. Read and execute SQL queries
queries_lookup <- read_yaml(queries_input)
lookup_data <- map(queries_lookup$queries, \(q) dbGetQuery(database_connection, q))
# 2. Read plot folder paths
target_paths <- fromJSON(file = project_list)$projects
all_folders <- path(data_folder, target_paths)
# 3. Read control table file
config_table <- read_csv(metadata_input,
  col_select = c(
    "table_name", "input_pattern", "combined_table_csv", "warn_if_missing",
    "clean_function", "join_function", "serial_key_id",
    "include_combine"
  )
) |>
  filter(include_combine) # Drop files that aren't used in this script
# 4. Read project source data
source_original <- read_excel(source_input)

# Process project source table
source_processed <- join_source_metadata(source_original, lookup_data)

# Create function for table processing
process_tables <- function(input_pattern, table_name, warn_if_missing, clean_function,
                           join_function, serial_key_id,
                           database_connection, ...) {
  message(paste0("Processing table... ", table_name))

  # Convert strings to functions
  clean_logic <- match.fun(clean_function)
  join_logic <- match.fun(join_function)

  # Get table schema from AKVEG database
  column_names <- dbListFields(database_connection, table_name)

  # Remove auto-incrementing ID field for tables that use it
  if (!is.na(serial_key_id)) {
    column_names <- column_names[column_names != serial_key_id]
  }

  # Process and combine individual tables
  df_join <- find_files_warning(all_folders, input_pattern, show_warning = warn_if_missing) |>
    map(\(f) read_csv(f, show_col_types = FALSE)) |>
    map(clean_logic) |>
    list_rbind() |>
    join_logic(lookup_data)

  # Add source metadata to project table
  if (table_name == "project") {
    source_columns <- setdiff(names(source_processed), "project_code")

    # This part will have to be modified once we have project tables that reflect the new schema
    df_join <- df_join |>
      left_join(source_processed, by = "project_code")
  }

  df_join |>
    select(all_of(column_names))
}

# Iterate through every row in the config table and apply process_tables function
final_results_list <- pmap(config_table, process_tables,
  database_connection = database_connection
)

# Export combined data ----
## One table for each list item
pwalk(
  list(final_results_list, config_table$combined_table_csv),
  \(data, name) {
    write_csv(data, path(data_folder, "processed", name))
  }
)

# Close database connection ----
dbDisconnect(database_connection)

# Clear workspace ----
rm(list = ls())
