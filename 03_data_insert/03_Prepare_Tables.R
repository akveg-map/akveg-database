# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Prepare data for upload
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-22
# Usage: Script should be executed in R 4.5.1+.
# Description: "Prepare data for upload" parses the aggregate tables into SQL INSERT statements that can be used to add data to the AKVEG database.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(glue)
library(lubridate)
library(purrr)
library(readr)
library(readxl)
library(RPostgres)
library(stringr)
library(tidyr)

# Define directories ----
drive <- "C:"
root_folder <- "ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"
data_folder <- path(drive, root_folder, "Data", "Data_Plots")
repository_folder <- path(drive, "ACCS_Work/Repositories/akveg-database")

# Define files ----
authentication <- path(drive, root_folder, "Credentials", "akveg_private_build",
                       "authentication_akveg_private_build.csv")
metadata_input <- path(repository_folder, "03_data_insert", "config", "tables_metadata.csv")
citations_input <- path(drive, root_folder, "Data", "Tables_Metadata", "project_citations.xlsx")

# Source functions ----
helpers <- new.env()
source(path(repository_folder, "03_data_insert", "helper_functions.R"), local = helpers)
execute_sql_build <- helpers$execute_sql_build
upload_to_database <- helpers$upload_to_database

# Connect to AKVEG database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)

# Read in data ----
config_table <- read_csv(metadata_input, col_select = c("table_name", 
                                                        "combined_table_csv", "serial_key_id"))
citations_original <- read_excel(citations_input) |> select(project_code, citation_short)

# Prepare individual tables ---
build_list <- function(table_name, combined_table_csv,
                                   serial_key_id, database_connection) {
  # Get table schema from AKVEG database
  column_names <- dbListFields(database_connection, table_name)
  
  # Remove auto-incrementing ID field for tables that use it
  if (!is.na(serial_key_id)) {
    column_names <- column_names[column_names != serial_key_id]
  }

  # Define input paths
  corrected_path <- path(data_folder, "processed", "corrected", combined_table_csv)
  processed_path <- path(data_folder, "processed", combined_table_csv)

  # Read corrected table if it exists
  if (file_exists(corrected_path)) {
    message(paste("Reading in corrected file for", table_name))
    df <- read_csv(corrected_path, show_col_types = FALSE)
  } else {
    df <- read_csv(processed_path, show_col_types = FALSE)
  }

  # Ensure the dataframe only contains the columns in the database
  df |> 
    select(all_of(column_names))
}

# Combine tables into list ----
final_tables <- pmap(config_table, build_list, 
                     database_connection = database_connection) |> 
  set_names(config_table$table_name)

# Execute SQL build ----
## This will drop existing metadata tables and create new (empty) ones

# Close any open transactions (e.g., resulting from transaction failures)
try(DBI::dbExecute(database_connection, "ROLLBACK;"), silent = TRUE)

# Define build scripts
build_scripts <- c("03_Project.sql", "04_Site.sql", "05_Vegetation.sql", "06_Abiotic.sql", "07_Environment.sql")

# Execute each build script in turn
walk(build_scripts, execute_sql_build, 
     database_connection = database_connection, 
     repository_folder = repository_folder)

# Prepare project_citations junction table ----

# Get citations table
db_citations <- dbGetQuery(database_connection, "SELECT citation_id, citation_short FROM citations")

# Retrieve citation id
citations_junction <- citations_original |> 
  left_join(db_citations, by="citation_short") |> 
  select(project_code, citation_id) |> 
  distinct()

# Ensure there are no null values
print(colSums(is.na(citations_junction))) 

# Add to data tables list
final_tables$project_citations <- citations_junction

# Upload data to SQL database ---
upload_to_database(database_connection, final_tables)

# Close database connection
dbDisconnect(database_connection)

# Clear workspace
rm(list = ls())
