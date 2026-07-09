# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create EML XML file for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-07-08
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

# Define SQL query
schema_file = path(repository_folder, 'user_tools', 'queries', '00_database_schema.sql')

# Connect to the AKVEG Database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)

# Read in schema table ----
schema_query = read_file(schema_file)
schema_table_db = as_tibble(dbGetQuery(database_connection, schema_query))

# Restrict schema to core tables ----
# Use compiled tables (from extract_schema script) to determine what fields to extract from the database dictionary
# Lookup tables will not be uploaded to the data archive, compiled tables already resolve foreign key ids into values

# Get file paths and file stems of compiled tables
table_paths <- dir_ls(compiled_folder)
table_stems <- path_file(table_paths) |> 
  path_ext_remove()

# Loop across the file paths of the compiled tables and extract their column names
all_cols = c() # Initialize empty character vector

for (path in table_paths) {
  cols = colnames(read_csv(path, n_max = 0, show_col_types = FALSE))
  all_cols = c(all_cols, cols) # Add result to vector
}

# Remove duplicates
unique_cols = unique(all_cols)

core_schema <- schema_table_db |> filter(field %in% unique_cols)

# Format schema table into attributes ----
attribute_table <- core_schema |> 
  rename(attributeName = field,
         attributeDefinition = field_description) |> 
  # Populate EML domain based on data type and attribute name
  # Handle exceptions before applying general rules
  mutate(domain = case_when(attributeName %in% c('year_start', 
                                                 'year_end') ~ 'dateTimeDomain',
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
                            data_type == 'boolean' ~ 'enumeratedDomain',
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
                                      domain == 'dateTimeDomain' ~ 'dateTime',
                                      domain == 'enumeratedDomain' ~ 'nominal',
                                      domain == 'textDomain' ~ 'nominal',
                                      domain == 'numericDomain' ~ 'ratio',
                                      .default = NA
                                      )
         ) |> 
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
                          attributeName == 'temperature_deg_c' ~ 'celsius',
                          attributeName == 'disturbance_time_y' ~ 'nominalYear',
                          grepl(pattern='_percent|_chroma|_value|number_', attributeName)  ~ 'dimensionless',
                          attributeName == 'ph' ~ 'dimensionless',
                          .default = NA)) |> 
  mutate(numberType = case_when(data_type == "decimal" ~ "real",
                                grepl(pattern="_chroma", attributeName) ~ "real",
                                attributeName == "number_stems" ~ "natural",
                                attributeName == "disturbance_time_y" ~ "integer",
                                .default = NA)) |> 
  # Select desired columns
  select(attributeName, data_type, unit, numberType, domain, attributeDefinition, schema_table, definition,  measurementScale, formatString)

# Quality checks
## Check that nothing is NA
## Check for consistency between domain, mscale, etc.
## Create factors and missingValues tables
