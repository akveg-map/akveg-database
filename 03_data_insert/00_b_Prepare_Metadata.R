# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Prepare metadata and constraints for upload
# Authors: Timm Nawrocki, Amanda Droghini, ACCS
# Last Updated: 2026-04-23
# Usage: Script should be executed in R 4.5.1+.
# Description: Dynamically parses metadata and constraints from Excel into a SQL query for upload into empty tables.
# ---------------------------------------------------------------------------

# Import required libraries
library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(readr)
library(readxl)
library(RPostgres)
library(stringr)
library(purrr)
library(tidyr)
library(tibble)

# Set file and directory paths ----
root_folder <- "C:/ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"
data_folder <- path(root_folder, "Data", "Tables_Metadata")
repository_folder = path(drive, 'ACCS_Work/Repositories/akveg-database')
authentication <- path(root_folder, "Credentials", "akveg_private_build", "authentication_akveg_private_build.csv")

# Connect to the AKVEG Database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)

# Define naming exceptions for ID columns
suffix_exceptions <- c(
  "ground_element" = "_code",
  "h_datum" = "_epsg",
  "soil_texture" = "_code",
  "soil_horizon_type" = "_code",
  "soil_horizon_suffix" = "_code",
  "soil_hue" = "_code",
  "structural_class" = "_code",
  "nonmatrix_feature" = "_code",
  "soil_structure" = "_code"
)

# Read in data
dictionary_data <- read_excel(path(data_folder, "database_dictionary.xlsx"), sheet = "dictionary")
schema_data <- read_excel(path(data_folder, "database_schema.xlsx"), sheet = "schema")
org_data <- read_excel(path(data_folder, "organization.xlsx"), sheet = "organization")
citations_data <- read_excel(path(data_folder, "project_citations.xlsx"))

# Parse constraints
constraint_tables <- dictionary_data %>%
  arrange(field) %>%
  split(.$field) %>%
  imap(function(df, field_name) {
    # Create suffix for id column (end in "_id" or "_code" for most exceptions)
    suffix <- ifelse(field_name %in% names(suffix_exceptions), suffix_exceptions[field_name], "_id")

    # Handle plot_dimensions exception
    if (field_name == "plot_dimensions_m") {
      id_col <- "plot_dimensions_id" # Drop the "_m" from the id field
      value_col <- "plot_dimensions_m" # Keep the "_m" for the values field
    } else {
      # Create column names using field_name and suffix
      id_col <- paste0(field_name, suffix)
      value_col <- field_name
    }

    # Rename columns
    df %>%
      select(data_attribute_id, data_attribute) %>%
      rename(!!id_col := 1, !!value_col := 2)
  })

# Add element_type to ground_element
constraint_tables$ground_element <- constraint_tables$ground_element %>%
  mutate(element_type = case_when(
    ground_element %in% c("rock fragments", "soil") ~ "abiotic",
    ground_element %in% c("animal litter", "biotic", "gravel", "cobble", "stone", "boulder", "mineral soil", "organic soil") ~ "ground",
    .default = "both"
  ))

# Parse organization table
organization_table <- org_data %>%
  left_join(constraint_tables$organization_type, by = "organization_type") %>%
  select(organization_id, organization, organization_type_id)

# Parse schema table
database_schema_table <- schema_data %>%
  left_join(constraint_tables$schema_category, by = "schema_category") %>%
  left_join(
    constraint_tables$schema_table %>%
      rename(link_table_id = schema_table_id),
    by = c("link_table" = "schema_table")
  ) %>%
  left_join(constraint_tables$schema_table, by = "schema_table") %>%
  left_join(constraint_tables$data_type, by = "data_type") %>%
  rowid_to_column("field_id") %>%
  select(
    field_id, standards_section, schema_category_id, schema_table_id, field, data_type_id,
    field_length, is_unique, is_key, required, link_table_id, field_description
  )

# Parse dictionary table
database_dictionary_table <- dictionary_data %>%
  left_join(database_schema_table, by = "field") %>%
  rowid_to_column("dictionary_id") %>%
  select(dictionary_id, field_id, data_attribute_id, data_attribute, definition)

# Parse citations table
citations_table <- citations_data |>
  select(citation_short, citation_long, citation_url) |>
  distinct() |> # Remove duplicates
  arrange(citation_short)

# Remove organization table in constraint_tables
## Use new organization_table instead
constraint_tables$organization <- NULL

# Rename specific tables
names(constraint_tables)[names(constraint_tables) == "plot_dimensions_m"] <- "plot_dimensions"
names(constraint_tables)[names(constraint_tables) == "nonmatrix_feature"] <- "soil_nonmatrix_features"

# Compile list of all metadata tables
## Schema table must be ordered before database dictionary
final_tables <- c(
  constraint_tables,
  list(
    organization = organization_table,
    citations = citations_table,
    database_schema = database_schema_table,
    database_dictionary = database_dictionary_table
  )
)

# Execute SQL build and ingestion ----

# 1. Run database build scripts
## This will drop existing metadata tables and create new (empty) ones
build_scripts <- "02_Metadata.sql"

for (script in build_scripts) {
  message(paste("Executing build script:", script))
  build_path <- path(repository_folder, "01_database_build", script)

  # Read in full file
  full_sql <- read_file(build_path)

  # Chunk the file into separate CREATE statements
  ## Split by semicolon
  sql_commands <- str_split(full_sql, ";(\\s*\\n|$)") %>%
    flatten_chr() %>%
    str_trim() %>% ## Remove whitespaces
    keep(~ grepl("CREATE|INSERT|COMMIT|DROP", .x, ignore.case = TRUE)) ## Ignore comments and non-commands

  total_chunks <- length(sql_commands)

  # Execute each command individually
  # Use iwalk to produce visual counter message in console
  iwalk(sql_commands, function(cmd, i) {
    message(paste0("Chunk ", i, " of ", total_chunks, ": ", substr(cmd, 1, 40), "..."))
    dbExecute(database_connection, cmd)
  })

  message(paste("Finished script:", script))
}

# 2. Upload metadata tables to database
## All warnings about transactions being in progress (or not) can be safely ignored

# Close any open transactions (e.g., from transaction failure)
try(dbExecute(database_connection, "ROLLBACK;"))

# Begin transaction
dbExecute(database_connection, "BEGIN;")

tryCatch(
  {
    # Obtain table names
    table_list <- names(final_tables)

    for (i in seq_along(table_list)) {
      target_table <- table_list[i]

      message(paste0("Step ", i, " of ", length(table_list), ": Inserting into ", target_table, "..."))

      dbWriteTable(
        conn = database_connection,
        name = target_table,
        value = final_tables[[target_table]],
        append = TRUE,
        row.names = FALSE
      )
    }

    # Commit to database if error-free
    dbExecute(database_connection, "COMMIT;")
    message("--- Success! All metadata successfully migrated to the database. ---")
  },
  error = function(e) {
    # If a table fails, undo the entire transaction
    dbExecute(database_connection, "ROLLBACK;")
    message("--- DATA INSERT FAILURE")
    message(e$message)
    # Stop the script
    stop("Migration failed. Database has been rolled back to empty tables.")
  }
)

# Close database connection ----
dbDisconnect(database_connection)
message("Metadata build and migration complete.")

# Clear workspace
rm(list = ls())
