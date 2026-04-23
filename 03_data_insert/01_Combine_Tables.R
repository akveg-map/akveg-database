# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Combine data tables
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-21
# Usage: Script should be executed in R 4.5.1+.
# Description: "Combine data tables" combines data from processed datasets into single CSV files. The CSV files can then be converted into a SQL statement for upload to the AKVEG database. The script requires metadata tables to be inserted into the AKVEG Database.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(purrr)
library(readr)
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
data_folder <- path(
  drive,
  root_folder,
  "Data/Data_Plots"
)
repository_folder <- path(
  drive,
  "ACCS_Work/Repositories/akveg-database"
)
credential_folder <- path(drive, root_folder, "Credentials")

# Define input files ----
project_list <- path(
  repository_folder,
  "03_data_insert",
  "List_Included_Projects.json"
)
queries_input <- path(
  repository_folder,
  "03_data_insert",
  "queries_lookup.yaml"
)

# Define functions ----
source(path(
  repository_folder,
  "03_data_insert",
  "helper_functions_combine.R"
))

# Connect to AKVEG database ----

# Import database connection function
connection_script <- path(
  repository_folder,
  "pull_functions",
  "connect_database_postgresql.R"
)
source(connection_script)

# Create a connection to the AKVEG PostgreSQL database
authentication <- path(
  credential_folder,
  "akveg_private_build", "authentication_akveg_private_build.csv"
)
database_connection <- connect_database_postgresql(authentication)

# Read in queries ----
queries_lookup <- read_yaml(queries_input)
lookup_data <- map(queries_lookup$queries, \(q) dbGetQuery(database_connection, q))

# Define vegetation plot folders ----
target_paths <- fromJSON(file = project_list)$projects
all_folders <- path(data_folder, target_paths)

# Create config table to hold table-specific values and functions
config_table <- tribble(
  ~table_name,
  ~input_pattern,
  ~warn_if_missing,
  ~output_path,
  ~clean_function,
  ~join_function,
  ~serial_key_id,
  #---------|---------|---------|---------
  "project", "01_project.*csv", TRUE, "projects.csv", identity, join_project_metadata, NA,
  "site", "02_site.*csv", TRUE, "sites.csv", clean_site_data, join_site_metadata, NA,
  "site_visit", "03_sitevisit.*csv", TRUE, "site_visits.csv", clean_visit_data, join_visit_metadata, NA,
  "vegetation_cover", "05_vegetationcover.*csv", TRUE, "vegetation_cover.csv", clean_vegetation_data,
  join_vegetation_metadata, "vegetation_cover_id",
  "abiotic_top_cover", "06_abiotictopcover.*csv", FALSE, "abiotic_top_cover.csv",
  clean_abiotic_data, join_abiotic_metadata, "abiotic_cover_id",
  "whole_tussock_cover", "07_wholetussockcover.*csv", FALSE, "whole_tussock_cover.csv",
  clean_tussock_data, join_tussock_metadata, "tussock_id",
  "ground_cover", "08_groundcover.*csv", FALSE, "ground_cover.csv",
  rename_columns, join_ground_metadata, "ground_cover_id",
  "structural_group_cover", "09_structuralgroupcover.*csv", FALSE, "structural_group_cover.csv",
  clean_structural_data, join_structural_metadata, "structural_cover_id",
  "shrub_structure", "11_shrubstructure.*csv", FALSE, "shrub_structure.csv", rename_columns,
  join_shrub_metadata, "shrub_structure_id",
  "environment", "12_environment.*csv", FALSE, "environment.csv",
  clean_environment_data, join_environment_metadata, "environment_id",
  "soil_metrics", "13_soilmetrics.*csv", FALSE, "soil_metrics.csv",
  clean_soil_metrics_data, join_soil_metrics_metadata, "soil_metrics_id",
  "soil_horizons", "14_soilhorizons.*csv", FALSE, "soil_horizons.csv",
  clean_soil_horizons_data, join_soil_horizons_metadata, "soil_horizons_id"
)

# Create function for table processing
process_tables <- function(input_pattern, table_name, warn_if_missing, clean_function,
                           join_function, serial_key_id,
                           database_connection, ...) {
  message(paste0("Processing table... ", table_name))

  # Get table schema from AKVEG database
  column_names <- dbListFields(database_connection, table_name)

  # Remove auto-incrementing ID field for tables that use it
  if (!is.na(serial_key_id)) {
    column_names <- column_names[column_names != serial_key_id]
  }

  # Process and combine individual tables
  find_files_warning(all_folders, input_pattern, show_warning = warn_if_missing) |>
    map(\(f) read_csv(f, show_col_types = FALSE)) |>
    map(clean_function) |>
    list_rbind() |>
    join_function(lookup_data) |>
    select(all_of(column_names))
}

# Iterate through every row in the config table and apply process_tables function
final_results_list <- pmap(config_table, ~ process_tables(
  table_name          = ..1,
  input_pattern       = ..2,
  warn_if_missing     = ..3,
  clean_function      = ..5,
  join_function       = ..6,
  serial_key_id       = ..7,
  database_connection = database_connection
))

# Export combined data ----
## One table for each list item
pwalk(
  list(final_results_list, config_table$output_path),
  \(data, name) {
    write_csv(data, path(data_folder, "processed", name))
  }
)

# Close database connection ----
dbDisconnect(database_connection)

# Clear workspace ----
rm(list = ls())
