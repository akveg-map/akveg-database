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
library(RPostgres)
library(stringr)
library(tidyr)

# Define files & directories ----
drive <- "C:"
root_folder <- "ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"
data_folder <- path(drive, root_folder, "Data", "Data_Plots")
repository_folder <- path(drive, "ACCS_Work/Repositories/akveg-database")

## Database credential file
authentication <- path(
  drive, root_folder, "Credentials", "akveg_private_build",
  "authentication_akveg_private_build.csv"
)

## Metadata for tables
metadata_input <- path(repository_folder, "03_data_insert", "config", "tables_metadata.csv")
config_table <- read_csv(metadata_input,
  col_select = c("table_name", "combined_table_csv", "output_sql", "serial_key_id")
)

# Connect to AKVEG database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)

# Define core logic ----
build_insert_statement <- function(table_name, combined_table_csv,
                                   output_sql, serial_key_id, database_connection) {
  # Get table schema from AKVEG database
  column_names <- dbListFields(database_connection, table_name)
  # Remove auto-incrementing ID field for tables that use it
  if (!is.na(serial_key_id)) {
    column_names <- column_names[column_names != serial_key_id]
  }
  sql_columns <- paste(column_names, collapse = ", ")

  # Define I/O paths
  corrected_path <- path(data_folder, "processed", "corrected", combined_table_csv)
  processed_path <- path(data_folder, "processed", combined_table_csv)
  output_path <- path(data_folder, "sql_statements", output_sql)

  # Read corrected table if it exists
  if (file_exists(corrected_path)) {
    message(paste("Reading in corrected file for", table_name))
    df <- read_csv(corrected_path, show_col_types = FALSE)
  } else {
    df <- read_csv(processed_path, show_col_types = FALSE)
  }

  # Format table for as SQL string
  input_sql <- df %>%
    # Escape single quotes, and wrap characters and dates in quotes
    mutate(across(where(~ is.character(.) | is.Date(.)), ~ str_replace_all(., "'", "''"))) %>%
    mutate(across(where(~ is.character(.) | is.Date(.)), ~ paste0("'", ., "'"))) %>%
    # Convert all columns to character
    mutate(across(everything(), as.character)) |>
    # Replace true NA with 'NULL' (numeric columns)
    mutate(across(everything(), ~ if_else(is.na(.), "NULL", as.character(.)))) |>
    # Replace 'NA' with 'NULL' (character columns)
    mutate(across(everything(), ~ str_replace(., "^'NA'$", "NULL"))) %>%
    # Combine all columns and values into a single row
    unite(sql_row, everything(), sep = ", ") %>%
    mutate(sql_row = paste0("(", sql_row, "),"))

  # Fix the last comma to a semicolon
  last_row <- nrow(input_sql)
  input_sql$sql_row[last_row] <- str_replace(input_sql$sql_row[last_row], ",$", ";")

  # Construct the full file
  header <- c(
    "-- -*- coding: utf-8 -*-",
    "-- ---------------------------------------------------------------------------",
    glue("-- Insert data for {table_name} table"),
    "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
    glue("-- Last Updated: {Sys.Date()}"),
    "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
    "-- ---------------------------------------------------------------------------",
    "",
    "-- Initialize transaction",
    "START TRANSACTION;",
    paste0("INSERT INTO ", table_name, " (", sql_columns, ") VALUES")
  )

  footer <- c("", "COMMIT TRANSACTION;")

  full_statement <- c(header, input_sql$sql_row, footer)

  # Replace NA with NULL
  full_statement <- full_statement %>%
    str_replace_all(", NA,", ", NULL,") %>%
    str_replace_all(", 'NA'", ", NULL") %>%
    str_replace_all(", 'NULL'", ", NULL")

  # Write to SQL file
  write_lines(full_statement, output_path)
}

# Execute logic ----
# Iterate through every row in the config table
pwalk(config_table, build_insert_statement, database_connection = database_connection)

# Close database connection
dbDisconnect(database_connection)

# Clear workspace
rm(list = ls())
