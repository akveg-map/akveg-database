# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Prepare metadata and constraints for upload
# Authors: Timm Nawrocki, Amanda Droghini, ACCS
# Last Updated: 2026-03-26
# Usage: Script should be executed in R 4.5.1+.
# Description: Dynamically parses metadata and constraints from Excel into a SQL query for upload into empty tables. Developed using Gemini 3 Flash (Google AI), March 2026.
# ---------------------------------------------------------------------------

# Import required libraries
library(dplyr)
library(fs)
library(readr)
library(readxl)
library(stringr)
library(purrr)
library(tidyr)
library(tibble)

# Set directories
root_folder <- "C:/ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database/Data"
data_folder <- path(root_folder, "Tables_Metadata")

# Define output
sql_metadata <- path(root_folder, "Data_Plots/sql_statements/00_b_Insert_Metadata.sql")

# Define naming exceptions for ID columns
suffix_exceptions <- c(
  "ground_element"      = "_code",
  "h_datum"             = "_epsg",
  "soil_texture"        = "_code",
  "soil_horizon_type"   = "_code",
  "soil_horizon_suffix" = "_code",
  "soil_hue"            = "_code",
  "structural_class"    = "_code",
  "nonmatrix_feature" = "_code",
  "soil_structure"      = "_code"
)

# Read in data
dictionary_data <- read_excel(path(data_folder, "database_dictionary.xlsx"), sheet = "dictionary")
schema_data <- read_excel(path(data_folder, "database_schema.xlsx"), sheet = "schema")
org_data <- read_excel(path(data_folder, "organization.xlsx"), sheet = "organization")

# Parse constraints
constraint_tables <- dictionary_data %>%
  arrange(field) %>% 
  split(.$field) %>% 
  imap(function(df, field_name) {
    
    # Create suffix for id column (end in "_id" or "_code" for most exceptions)
    suffix <- ifelse(field_name %in% names(suffix_exceptions), suffix_exceptions[field_name], "_id")
    
    # Handle plot_dimensions exception
    if (field_name == "plot_dimensions_m") {
      id_col    <- "plot_dimensions_id"  # Drop the "_m" from the id field
      value_col <- "plot_dimensions_m"   # Keep the "_m" for the values field
    } else {
      # Create column names using field_name and suffix
      id_col    <- paste0(field_name, suffix)
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
  left_join(constraint_tables$schema_table %>% 
              rename(link_table_id = schema_table_id), 
            by = c("link_table" = "schema_table")) %>%
  left_join(constraint_tables$schema_table, by = "schema_table") %>%
  left_join(constraint_tables$data_type, by = "data_type") %>%
  rowid_to_column("field_id") %>%
  select(field_id, standards_section, schema_category_id, schema_table_id, field, data_type_id, 
         field_length, is_unique, is_key, required, link_table_id, field_description)

# Parse dictionary table
database_dictionary_table <- dictionary_data %>%
  left_join(database_schema_table, by = "field") %>%
  rowid_to_column("dictionary_id") %>%
  select(dictionary_id, field_id, data_attribute_id, data_attribute, definition)


# Remove organization table in constraint_tables
## Use new organization_table instead
constraint_tables$organization <- NULL

# Rename specific tables
names(constraint_tables)[names(constraint_tables) == "plot_dimensions_m"] <- "plot_dimensions"
names(constraint_tables)[names(constraint_tables) == "nonmatrix_feature"] <- "soil_nonmatrix_features"

# Compile list of all metadata tables
final_tables <- c(
  constraint_tables, 
  list(organization = organization_table, 
       database_schema = database_schema_table,
       database_dictionary = database_dictionary_table)
)

# Write data to SQL file
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert metadata and constraints",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated: ", Sys.Date()),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert metadata and constraints" pushes data from the database dictionary and schema into the database server. The script "Build metadata and constraint tables" should be run prior to this script to start with empty, properly formatted tables.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  "",
  "-- Insert data into constraint tables",
  ""
)

# Loop through all metadata tables
for (table_name in names(final_tables)) {
  df <- final_tables[[table_name]]
  
  # Add apostrophes, coerce to string, and format NULL
  df_sql <- df %>%
    mutate(across(where(is.character), ~ paste0("'", str_replace_all(.x, "'", "''"), "'"))) %>% # Format character columns by adding apostrophes at the start/end of the string, convert single apostrophes to double apostrophes for SQL
    mutate(across(everything(), ~ replace_na(as.character(.x), "NULL"))) %>%  # Coerce all columns to string and replace NA with "NULL"
    mutate(across(everything(), ~ ifelse(.x == "'NA'" | .x == "''", "NULL", .x)))
  
  # Add header
  cols <- paste(names(df), collapse = ", ")
  statement <- c(statement,
                 paste0("INSERT INTO ", table_name, " (", cols, ") VALUES"))
  
  # Collapse data into character vector
  rows <- df_sql %>%
    unite("row", everything(), sep = ", ") %>%
    mutate(row = paste0("  (", row, "),")) %>%
    pull(row)
  
  # Replace final comma with semicolon
  rows[length(rows)] <- str_replace(rows[length(rows)], ",$", ";")
  
  statement <- c(statement, rows, "") # Add rows and a blank line for readability
}

statement <- c(
  statement,
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, sql_metadata)
