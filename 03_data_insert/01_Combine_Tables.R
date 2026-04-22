# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Combine data tables
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-20
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
drive = 'C:'
root_folder = 'ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database'

# Define input folders
data_folder = path(drive,
                   root_folder,
                   'Data/Data_Plots')
repository_folder = path(drive,
                         'ACCS_Work/Repositories/akveg-database')
credential_folder = path(drive, root_folder, 'Credentials')

# Define input files ----
project_list = path(repository_folder, 
                         '03_data_insert', 
                         'List_Included_Projects.json')
queries_input = path(repository_folder, 
                     '03_data_insert', 
                     'queries_lookup.yaml')

# Define functions ----
source(path(repository_folder, 
          '03_data_insert', 
          'helper_functions_combine.R'))

# Connect to AKVEG database ----

# Import database connection function
connection_script = path(repository_folder,
                         'pull_functions',
                         'connect_database_postgresql.R')
source(connection_script)

# Create a connection to the AKVEG PostgreSQL database
authentication = path(credential_folder,
                      'akveg_private_build', 'authentication_akveg_private_build.csv')
database_connection = connect_database_postgresql(authentication)

# Read in queries ----
queries_lookup = read_yaml(queries_input)
lookup_data = map(queries_lookup$queries, \(q) dbGetQuery(database_connection, q))

# Define vegetation plot folders ----
target_paths = fromJSON(file = project_list)$projects
all_folders = path(data_folder, target_paths)

# Create tibble specifying input file pattern and output file name
config_table = tribble(
  ~ table_name,
  ~ input_pattern,
  ~ warn_if_missing,
  ~ output_path,
  ~ clean_function,
  ~ join_function,
  #---------|---------|---------|---------
  "project",
  '01_project.*csv',
  TRUE,
  "projects.csv",
  identity,
  join_project_metadata,
  "site",
  "02_site.*csv",
  TRUE,
  "sites.csv",
  clean_site_data,
  join_site_metadata,
  "site_visit",
  '03_sitevisit.*csv',
  TRUE,
  "site_visits.csv",
  clean_visit_data,
  join_visit_metadata,
  "vegetation",
  "05_vegetationcover.*csv",
  TRUE,
  "vegetation_cover.csv",
  clean_vegetation_data,
  join_vegetation_metadata,
  "abiotic",
  '06_abiotictopcover.*csv',
  FALSE,
  "abiotic_top_cover.csv",
  clean_abiotic_data,
  join_abiotic_metadata,
  "whole_tussock",
  "07_wholetussockcover.*csv",
  FALSE,
  "whole_tussock_cover.csv",
  clean_tussock_data,
  join_tussock_metadata,
  "ground_cover",
  "08_groundcover.*csv",
  FALSE,
  "ground_cover.csv",
  rename_columns,
  join_ground_metadata,
  "structural_group",
  "09_structuralgroupcover.*csv",
  FALSE,
  'structural_group_cover.csv',
  clean_structural_data,
  join_structural_metadata,
  "shrub_structure",
  "11_shrubstructure.*csv",
  FALSE,
  'shrub_structure.csv',
  rename_columns,
  join_shrub_metadata,
  "environment",
  "12_environment.*csv",
  FALSE,
  'environment.csv',
  clean_environment_data,
  join_environment_metadata,
  "soil_metrics",
  "13_soilmetrics.*csv",
  FALSE,
  'soil_metrics.csv',
  clean_soil_metrics_data,
  join_soil_metrics_metadata
  
)
  "soil_horizons",
  'soil_horizons.csv'
  

# Create function for table processing
process_tables <- function(input_pattern, warn_if_missing, clean_function, join_function, ...) {
  find_files_warning(all_folders, input_pattern, show_warning = warn_if_missing) |> 
    map(\(f) read_csv(f, show_col_types = FALSE)) |> 
    map(clean_function) |> 
    list_rbind() |> 
    join_function(lookup_data)
}

# Run every job in the table at once
final_results_list <- pmap(config_table, process_tables)


# Create soil horizons table ----

# Set target pattern
target_pattern = '^14_soilhorizons.*csv'

print(str_c('Processing...', target_pattern, sep = " "))

# Create empty list to store files
files_list = list()

# Iterate through target paths and create file list
for (target_path in target_paths) {
  # Create full path
  full_path = paste(data_folder, target_path, sep = '/')
  # Find file and append to file list
  files = list.files(full_path, pattern = target_pattern)
  if (!is.na(files[1])) {
    files_list = append(files_list, paste(full_path, files[1], sep = '/'))
  }
}

# Create read function
read_data_site_visit_rename = function (data_file) {
  rename_fields = c(site_visit_code = 'site_visit_id',
                    depth_upper_cm = 'depth_upper',
                    depth_lower_cm = 'depth_lower',
                    horizon_primary_code = 'horizon_primary', 
                    horizon_suffix_1_code = 'horizon_suffix_1',
                    horizon_suffix_2_code = 'horizon_suffix_2', 
                    horizon_secondary_code = 'horizon_secondary',
                    horizon_suffix_3_code = 'horizon_suffix_3', 
                    horizon_suffix_4_code = 'horizon_suffix_4',
                    matrix_hue_code = 'matrix_hue',
                    nonmatrix_hue_code = 'nonmatrix_hue')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to input table
horizons_table = data_combine %>%
  left_join(texture_data, by = c('texture' = 'soil_texture')) %>%
  left_join(structure_data, by = c('structure' = 'soil_structure')) %>%
  left_join(nonmatrix_data, by = 'nonmatrix_feature') %>%
  rename(texture_code = soil_texture_code,
         structure_code = soil_structure_code) %>%
  select(site_visit_code, horizon_order, thickness_cm, depth_upper_cm, depth_lower_cm,
         depth_extend, horizon_primary_code, horizon_suffix_1_code,
         horizon_suffix_2_code, horizon_secondary_code,
         horizon_suffix_3_code, horizon_suffix_4_code, texture_code,
         clay_percent, total_coarse_fragment_percent,
         gravel_percent, cobble_percent, stone_percent, boulder_percent,
         structure_code, matrix_hue_code, matrix_value, matrix_chroma,
         nonmatrix_feature_code, nonmatrix_hue_code, nonmatrix_value, nonmatrix_chroma)

# Export combined data ----
write_csv(path(data_folder, 'processed', config_table$output_path))

# Close database connection ----
dbDisconnect(database_connection)

# Clear workspace ----
rm(list=ls())
