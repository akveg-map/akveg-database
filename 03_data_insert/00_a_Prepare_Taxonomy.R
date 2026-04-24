# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Prepare taxonomic data for upload
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-23
# Usage: Script should be executed in R 4.5.1+.
# Description: "Prepare taxonomic data for upload" parses taxonomy data into a SQL query for upload into empty tables.
# ---------------------------------------------------------------------------

# Import required libraries
library(dplyr)
library(fs)
library(purrr)
library(readr)
library(readxl)
library(RPostgres)
library(stringr)
library(tibble)
library(tidyr)

# Define file and directory paths ----
drive = 'C:'
root_folder = 'ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database'

# Define input folders
data_folder = path(drive, root_folder, 'Data', 'Tables_Taxonomy')
repository_folder = path(drive, 'ACCS_Work/Repositories/akveg-database')

# Define SQL authentication file
authentication <- path(drive, root_folder, "Credentials", "akveg_private_build",
                       "authentication_akveg_private_build.csv")

# Identify taxonomy tables
taxonomy_file = path(data_folder, 'taxonomy.xlsx')
unknown_file = path(data_folder, 'unknowns.xlsx')
citation_file = path(data_folder, 'citations.xlsx')

# Source functions ----
helpers <- new.env()
source(path(repository_folder, "03_data_insert", "helper_functions.R"), local = helpers)
clean_metadata <- helpers$clean_metadata
join_source_table <- helpers$join_source_table
execute_sql_build <- helpers$execute_sql_build
upload_to_database <- helpers$upload_to_database

# Connect to the AKVEG Database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)

# Read and merge taxonomy tables ----
taxonomy_data = read_excel(taxonomy_file, sheet = 'taxonomy') %>%
  select(-code_manual, -org)
unknown_data = read_excel(unknown_file, sheet = 'taxonomy')
citation_data = read_excel(citation_file, sheet = 'citations')

# Merge taxonomy tables to single dataframe
taxonomy_data = bind_rows(taxonomy_data, unknown_data)

# Define accepted taxon status codes ----
accepted_status = c('accepted', 'historical', 'taxonomy unresolved', 
  'location unresolved', 'adjacent Yukon', 'adjacent BC', 
  'adjacent Canada', 'ephemeral non-native')

# Parse simple metadata tables ----

# Create tribble to hold table information
config_table <- tribble(
  ~table_name, ~primary_key_id, ~join_function, ~join_table,
  "taxon_author", "taxon_author_id", identity, NA,
  "taxon_category", "taxon_category_id", identity, NA,
  "taxon_family", "taxon_family_id", identity, NA,
  "taxon_habit", "taxon_habit_id", identity, NA,
  "taxon_status", "taxon_status_id", identity, NA,
  "taxon_level", "taxon_level_id", identity, NA,
  "taxon_source", "taxon_source_id", join_source_table, citation_data
)
# Create function for table processing
process_tables <- function(taxonomy_table, 
                           table_name,
                           primary_key_id,
                           clean_function,
                           join_function,
                           join_table,
                           database_connection, ...) {
  
  message(paste0("Processing table... ", table_name))
  
  # Get table schema from AKVEG database
  column_names <- dbListFields(database_connection, table_name)
  
  # Process individual tables
  df_processed <- 
    clean_function(
      df = taxonomy_table, 
      value_name = table_name
    )
  
  # Handle tables with single join statement
  if(is.data.frame(join_table)){
    df_processed <- 
      join_function(df = df_processed,
                    value_name = table_name,
                    join_table = join_table)
  }
  
  df_processed = df_processed |> 
    # Create sequential primary key (used later in the script)
    rowid_to_column(primary_key_id) |> 
    # Ensure column names match database schema
    select(all_of(column_names))
}

# Iterate through every row in the config table and apply process_tables function
final_tables <- pmap(config_table, 
                           ~process_tables (table_name = ..1,
                                            primary_key_id = ..2,
                                            join_function = ..3,
                                            join_table = ..4,
                                            database_connection = database_connection,
                                            taxonomy_table = taxonomy_data,
                                            clean_function = clean_metadata)) |> 
  set_names(config_table$table_name)

# Parse complex tables ----

# Parse hierarchy table
final_tables$taxon_hierarchy <- taxonomy_data %>%
  filter(taxon_level %in% c('genus', 'unknown', 'functional group')) %>%
  filter(taxon_status %in% accepted_status) %>%
  distinct(taxon_accepted, .keep_all = TRUE) %>%
  left_join(final_tables$taxon_family, by = 'taxon_family') %>%
  left_join(final_tables$taxon_category, by = 'taxon_category') %>%
  rename(taxon_genus = taxon_accepted) %>%
  rename(taxon_genus_code = taxon_code) %>%
  arrange(taxon_genus_code) %>%
  select(taxon_genus_code, taxon_genus, taxon_family_id, taxon_category_id)

# Parse taxon accepted table
final_tables$taxon_accepted <- taxonomy_data %>%
  filter(taxon_status %in% accepted_status) %>%
  separate(taxon_accepted, c('taxon_genus'), extra = 'drop', sep = '([ ])', remove = FALSE) %>%
  mutate(join_name = case_when(taxon_level == 'functional group' |
                                 taxon_level == 'unknown' ~ taxon_accepted,
                               TRUE ~ taxon_genus)) %>%
  left_join(final_tables$taxon_hierarchy, by = c('join_name' = 'taxon_genus')) %>%
  left_join(final_tables$taxon_source, by = 'taxon_source') %>%
  left_join(final_tables$taxon_level, by = 'taxon_level') %>%
  left_join(final_tables$taxon_habit, by = 'taxon_habit') %>%
  arrange(taxon_accepted) %>%
  rename(taxon_accepted_code = taxon_code) %>%
  select(-taxon_name) |> 
  select(taxon_accepted_code, taxon_accepted, taxon_genus_code, taxon_source_id, taxon_link,
         taxon_level_id, taxon_habit_id, taxon_native, taxon_non_native)

# Parse taxon all table
final_tables$taxon_all = taxonomy_data %>%
  left_join(final_tables$taxon_author, by = 'taxon_author') %>%
  left_join(final_tables$taxon_status, by = 'taxon_status') %>%
  left_join(final_tables$taxon_accepted, by = 'taxon_accepted') |> 
  select(taxon_code, taxon_name, taxon_author_id, taxon_status_id, taxon_accepted_code)

# Remove extra fields
## Script will break without these omissions
final_tables$taxon_accepted = final_tables$taxon_accepted %>%
  select(-taxon_accepted)
final_tables$taxon_hierarchy = final_tables$taxon_hierarchy %>%
  select(-taxon_genus)

# Execute SQL build and ingestion ----

# Run database build scripts
## This will drop existing metadata tables and create new (empty) ones
execute_sql_build(database_connection, repository_folder, "01_Taxonomy.sql")

# Upload metadata tables to database
upload_to_database(database_connection, final_tables)

# Close database connection ----
dbDisconnect(database_connection)
message("Taxonomy build and migration complete.")

# Clear workspace
rm(list=ls())
