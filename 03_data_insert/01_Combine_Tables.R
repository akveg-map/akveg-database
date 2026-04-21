# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Combine data tables
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-02-09
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

# Define functions ----

# --- Function 1: find_files_warning ---
# Iterate over plot folders to find files matching pattern and print a warning if any folder is missing a file
find_files_warning <- function(folders, pattern) {
  # Create a named list where each element is the result of dir_ls
  search_results <- folders |> 
    set_names() |> # Attach folder name to the result
    map(\(dir) dir_ls(dir, regexp = pattern))
  
  # Identify folders where the length of the result is 0
  missing_folders <- search_results |> 
    keep(\(x) length(x) == 0) |> 
    names()
  
  # Issue a warning if a file is missing
  if (length(missing_folders) > 0) {
    warning(paste(
      "The following folders are missing a file for pattern [", pattern, "]:\n",
      paste("-", missing_folders, collapse = "\n")
    ))
  }
  
  # Return vector of file paths
  return(list_c(search_results))
}

# --- Function 2: clean_site_data ---
clean_site_data <- function(df) {
  df |>
    rename(any_of(c('establishing_project_code' = 'establishing_project'))) |>
    mutate(establishing_project_code = if_else(
      establishing_project_code == 'accs_nelchina_2022', 
      'accs_nelchina_2023', 
      establishing_project_code
    ))
}

# --- Function 3: join_site_metadata ---
join_site_metadata <- function(df, lookup) {
  df %>%
  left_join(lookup$perspective, by = 'perspective') %>%
  left_join(lookupa$method, by = 'cover_method') %>%
  left_join(lookup$dimensions, by = 'plot_dimensions_m') %>%
  left_join(lookup$datum, by = 'h_datum') %>%
  left_join(lookup$accuracy, by = 'positional_accuracy') %>%
  left_join(lookup$location, by = 'location_type') %>%
  select(site_code, establishing_project_code, perspective_id, cover_method_id,
         h_datum_epsg, latitude_dd, longitude_dd, h_error_m, positional_accuracy_id,
         plot_dimensions_id, location_type_id)
}


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

# Define files ----

# Define input files
project_list = path(repository_folder, 
                         '03_data_insert', 
                         'List_Included_Projects.json')
queries_input = path(repository_folder, 
                     '03_data_insert', 
                     'queries_lookup.yaml')

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

# Define plot folders ----
target_paths = fromJSON(file = project_list)$projects
all_folders = path(data_folder, target_paths)

# Create tibble specifying input file pattern and output file name
config_table = tribble(
  ~ table_name,
  ~ input_pattern,
  ~ output_path,
  ~ clean_function,
  ~ join_function,
  #---------|---------|---------|---------
  "project",
  '01_project.*csv',
  "projects.csv",
  identity,
  join_project_metadata,
  "site",
  "02_site.*csv",
  "sites.csv",
  clean_site_data,
  join_site_metadata
)

# Create project table ----

# Iterate through target paths and read in project files
project_files = find_files_warning(all_folders, config_table$input_pattern[1])
data_combine = project_files |> 
  map(\(f) read_csv(f, show_col_types = FALSE)) |> 
  list_rbind()  # Convert to data frame

# Join look-up tables to project table
project_table = data_combine %>%
  left_join(lookup_data$completion, by = 'completion') %>%
  left_join(lookup_data$organization, by = c('originator' = 'organization')) %>%
  rename(originator_id = organization_id) %>%
  left_join(lookup_data$organization, by = c('funder' = 'organization')) %>%
  rename(funder_id = organization_id) %>%
  left_join(lookup_data$personnel, by = c('manager' = 'personnel')) %>%
  rename(manager_id = personnel_id) %>%
  select(project_code, project_name, originator_id, funder_id, manager_id,
         completion_id, year_start, year_end, project_description, private)

# Create site table ----
print(str_c('Processing...', config_table$table_name[2], sep = " "))

site_files = find_files_warning(all_folders, config_table$input_pattern[2])
data_combine = site_files |> 
  map(\(f) read_csv(f, show_col_types = FALSE)) |> 
  map(clean_site_data) |>  # Apply corrections to `establishing_project_code` field
  list_rbind()  |> # Convert to data frame
  join_site_metadata(lookup_data)

# Create site visit table ----

# Set target pattern
target_pattern = '^03_sitevisit.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id', homogeneous = 'homogenous')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields)) %>%
    mutate(veg_observer = case_when(veg_observer == 'Jess Grunblatt' ~ 'Jesse Grunblatt',
    veg_observer == 'Robert Lieberman' ~ 'Robert Liebermann',
                                    veg_observer == 'NULL' ~ 'none',
                                    veg_observer == 'Unknown' ~ 'unknown',
                                    veg_observer == 'None' ~  'none',
                                    .default = veg_observer)) %>%
    mutate(veg_recorder = case_when(veg_recorder == 'Jess Grunblatt' ~ 'Jesse Grunblatt',
    veg_recorder == 'Robert Lieberman' ~ 'Robert Liebermann',
                                    veg_recorder == 'NULL' ~ 'none',
                                    veg_recorder == 'Unknown' ~ 'unknown',
                                    veg_recorder == 'None' ~  'none',
                                    project_code == 'accs_ribdon_2019' & is.na(veg_recorder) ~ 'Timm Nawrocki',
                                    .default = veg_recorder)) %>%
    mutate(env_observer = case_when(env_observer == 'Jess Grunblatt' ~ 'Jesse Grunblatt',
    env_observer == 'Robert Lieberman' ~ 'Robert Liebermann',
                                    env_observer == 'NULL' ~ 'none',
                                    env_observer == 'Unknown' ~ 'unknown',
                                    env_observer == 'None' ~  'none',
                                    .default = env_observer)) %>%
    mutate(soils_observer = case_when(soils_observer == 'Jess Grunblatt' ~ 'Jesse Grunblatt',
        soils_observer == 'Robert Lieberman' ~ 'Robert Liebermann',
                                      soils_observer == 'NULL' ~ 'none',
                                      soils_observer == 'Unknown' ~ 'unknown',
                                      soils_observer == 'None' ~  'none',
                                      .default = soils_observer)) %>%
    mutate(project_code = case_when(project_code == 'accs_nelchina_2022' ~ 'accs_nelchina_2023',
                                    TRUE ~ project_code))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to site table
site_visit_table = data_combine %>%
  # Correct erroneous data
  mutate(structural_class = case_when(structural_class == 'n/assess' ~ 'not assessed',
                                      is.na(structural_class) ~ 'not assessed',
                                      TRUE ~ structural_class)) %>%
  mutate(structural_class = tolower(structural_class)) %>%
  # Join attribute tables
  left_join(tier_data, by = 'data_tier') %>%
  left_join(personnel_data, by = c('veg_observer'= 'personnel')) %>%
  rename(veg_observer_id = personnel_id) %>%
  left_join(personnel_data, by = c('veg_recorder' = 'personnel')) %>%
  rename(veg_recorder_id = personnel_id) %>%
  left_join(personnel_data, by = c('env_observer'= 'personnel')) %>%
  rename(env_observer_id = personnel_id) %>%
  left_join(personnel_data, by = c('soils_observer' = 'personnel')) %>%
  rename(soils_observer_id = personnel_id) %>%
  left_join(struct_class_data, by = 'structural_class') %>%
  left_join(scope_data, by = c('scope_vascular'= 'scope')) %>%
  rename(scope_vascular_id = scope_id) %>%
  left_join(scope_data, by = c('scope_bryophyte' = 'scope')) %>%
  rename(scope_bryophyte_id = scope_id) %>%
  left_join(scope_data, by = c('scope_lichen' = 'scope')) %>%
  rename(scope_lichen_id = scope_id) %>%
  # Select final fields
  select(site_visit_code, project_code, site_code, data_tier_id, observe_date,
         veg_observer_id, veg_recorder_id, env_observer_id, soils_observer_id, structural_class_code,
         scope_vascular_id, scope_bryophyte_id, scope_lichen_id, homogeneous)

# Create vegetation cover table ----

# Set target pattern
target_pattern = '^05_vegetationcover.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to cover table
cover_table = data_combine %>%
  # Correct cover attribute
  mutate(cover_type = case_when(cover_type == 'absolute cover' ~ 'absolute foliar cover',
                                cover_type == 'top cover' ~ 'top foliar cover',
                                .default = cover_type)) %>%
  left_join(type_data, by = 'cover_type') %>%
  left_join(taxa_data, by = c('name_adjudicated' = 'taxon_name')) %>%
  rename(code_adjudicated = taxon_code) %>%
  select(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status, cover_percent) %>%
  # Correct code adjudicated for removed taxa
  mutate(code_adjudicated = case_when(
    name_original == 'Castilleja caudata var. caudata' ~ 'cascau',
    name_original == 'Lysimachia europaea ssp. europaea' ~ 'lyseur',
    name_original == 'Montia fontana ssp. fontana' ~ 'monfon',
    name_original == 'Montia vassilievii ssp. vassilievii' ~ 'monbos',
    name_original == 'Trientalis europaea ssp. europaea' ~ 'trieur',
    .default = code_adjudicated)) %>% 
  # Drop duplicates (same name, same % cover)
  distinct(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status, cover_percent) %>% 
  # Add cover percent for 'duplicates' with different cover values (n=4)
  group_by(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status) %>% 
  summarize(cover_percent = sum(cover_percent)) %>% 
  ungroup()

# Create abiotic top cover table ----

# Set target pattern
target_pattern = '^06_abiotictopcover.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id', abiotic_element = 'ground_element')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to abiotic table
abiotic_table = data_combine %>%
  left_join(element_data, by = c('abiotic_element' = 'ground_element')) %>%
  rename(abiotic_element_code = ground_element_code) %>%
  select(site_visit_code, abiotic_element_code, abiotic_top_cover_percent)

# Create whole tussock cover table ----

# Set target pattern
target_pattern = '^07_wholetussockcover.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id', cover_percent = 'tussock_percent_cover')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to tussock table
tussock_table = data_combine %>%
  left_join(type_data, by = 'cover_type') %>%
  select(site_visit_code, cover_type_id, cover_percent)

# Create ground cover table ----

# Set target pattern
target_pattern = '^08_groundcover.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to ground cover table
ground_table = data_combine %>%
  left_join(element_data, by = 'ground_element') %>%
  select(site_visit_code, ground_element_code, ground_cover_percent)

# Create structural group cover table ----

# Set target pattern
target_pattern = '^09_structuralgroupcover.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to structural group cover table
structural_table = data_combine %>%
  rename(cover_percent = structural_cover_percent,
         cover_type = structural_cover_type) %>%
  left_join(struct_group_data, by = 'structural_group') %>%
  left_join(type_data, by = 'cover_type') %>%
  select(site_visit_code, cover_type_id, structural_group_id, cover_percent)

# Create shrub structure table ----

# Set target pattern
target_pattern = '^11_shrubstructure.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to shrub structure table
shrub_table = data_combine %>%
  left_join(taxa_data, by = c('name_adjudicated' = 'taxon_name')) %>%
  left_join(type_data, by = 'cover_type') %>%
  left_join(class_data, by = 'shrub_class') %>%
  left_join(height_data, by = 'height_type') %>%
  rename(code_adjudicated = taxon_code) %>%
  select(site_visit_code, name_original, code_adjudicated, shrub_class_id,
         height_type_id, height_cm, cover_type_id, cover_percent,
         mean_diameter_cm, number_stems, shrub_subplot_area_m2)

# Create environment table ----

# Set target pattern
target_pattern = '^12_environment.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id')
  input_data = read_csv(data_file, show_col_types=FALSE) %>%
    rename(any_of(rename_fields))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to input table
# Correct old names that are no longer in database dictionary
environment_table = data_combine %>%
  mutate(geomorphology = case_when(geomorphology == 'glaciofluvial outwash' ~ 'glaciofluvial deposit',
                                   .default = geomorphology),
         soil_class = case_when(soil_class == 'typic haplorthel' ~ 'typic haplorthels',
                                soil_class == 'aquic haplorthel' ~ 'aquic haplorthels',
                                soil_class == 'folistic histoturbel' ~ 'folistic histoturbels',
                                soil_class == 'glacic umbriturbel' ~ 'glacic umbriturbels',
                                soil_class == 'oxyaquic gelorthent' ~ 'oxyaquic gelorthents',
                                soil_class == 'ruptic-histic aquorthel' ~ 'ruptic-histic aquorthels',
                                soil_class == 'ruptic histoturbel' ~ 'ruptic histoturbels',
                                soil_class == 'salic aquorthel' ~ 'salic aquorthels',
                                soil_class == 'typic aquiturbel' ~ 'typic aquiturbels',
                                soil_class == 'typic cryopsamment' ~ 'typic cryopsamments',
                                soil_class == 'typic fibristel' ~ 'typic fibristels',
                                soil_class == 'typic gelorthent' ~ 'typic gelorthents',
                                soil_class == 'typic gelpsamment' ~ 'typic gelpsamments',
                                soil_class == 'typic haploturbel' ~ 'typic haploturbels',
                                soil_class == 'typic hemistel' ~ 'typic hemistels',
                                soil_class == 'typic historthel' ~ 'typic historthels',
                                soil_class == 'typic histoturbel' ~ 'typic histoturbels',
                                soil_class == 'typic mollorthel' ~ 'typic mollorthels',
                                soil_class == 'typic psammorthel' ~ 'typic psammorthels',
                                soil_class == 'typic sapristel' ~ 'typic sapristels',
                                soil_class == 'typic umbriturbel' ~ 'typic umbriturbels',
                                .default = soil_class),
         disturbance = case_when(disturbance == 'wildlife grazing' ~ 'wildlife foraging',
                                 .default = disturbance),
         moisture_regime = case_when(moisture_regime == 'xeric-mesic' | moisture_regime == 'mesic-xeric heterogeneous' ~ 'mesic-xeric heterogenous',
                                     moisture_regime == 'mesic-hygric' | moisture_regime == 'hygric-mesic' | moisture_regime == 'hygric-mesic heterogeneous' ~ 'hygric-mesic heterogenous',
                                     moisture_regime == 'hygric-hydric' | moisture_regime == 'hydric-hygric' ~ 'hydric-hygric heterogenous',
                                     moisture_regime == 'hydric-aquatic' ~ 'aquatic-hydric heterogenous',
                                     moisture_regime == 'hydric-mesic' | moisture_regime == 'mesic-hydric' ~ 'hydric-mesic heterogenous',
                                     .default = moisture_regime
         ),
         microtopography = case_when(microtopography == 'tussock' ~ 'tussocks',
                                     microtopography == 'channelled' ~ 'channeled',
                                     .default = microtopography),
         macrotopography = case_when(macrotopography == 'lakebed' ~ 'lake bed',
                                     macrotopography == 'mountain bench' ~ 'bench',
                                     is.na(macrotopography) & geomorphology == 'low center polygons' ~ 'polygons low-center',
                                     .default = macrotopography),
         geomorphology = case_when(geomorphology == 'ocean shore' ~ 'marine, shore',
                                   geomorphology == 'low center polygons' ~ 'NULL',
                                   geomorphology == 'peninsula' ~ 'NULL',
                                   geomorphology == 'stream' ~ 'aquatic, river',
                                   geomorphology == 'lake' | geomorphology == 'aquatic lake' ~ 'aquatic, lake',
                                   geomorphology == 'estuary' ~ 'NULL',
                                   geomorphology == 'valley lowland' ~ 'valley, lowland',
                                   .default = geomorphology
         )) %>%
  left_join(physiography_data, by = 'physiography') %>%
  left_join(geomorphology_data, by = 'geomorphology') %>%
  left_join(macrotopography_data, by = 'macrotopography') %>%
  left_join(microtopography_data, by = 'microtopography') %>%
  left_join(moisture_data, by = c('moisture_regime' = 'moisture')) %>%
  left_join(drainage_data, by = 'drainage') %>%
  left_join(disturbance_data, by = 'disturbance') %>%
  left_join(severity_data, by = 'disturbance_severity') %>%
  left_join(restrictive_data, by = 'restrictive_type') %>%
  left_join(texture_data, by = c('dominant_texture_40_cm' = 'soil_texture')) %>%
  left_join(soil_data, by = 'soil_class') %>%
  rename(dominant_texture_40_cm_code = soil_texture_code) %>%
  select(site_visit_code, physiography_id, geomorphology_id, macrotopography_id,
         microtopography_id, moisture_id, drainage_id, disturbance_id,
         disturbance_severity_id, disturbance_time_y, depth_water_cm,
         depth_moss_duff_cm, depth_restrictive_layer_cm, restrictive_type_id,
         microrelief_cm, surface_water, soil_class_id, cryoturbation,
         dominant_texture_40_cm_code, depth_15_percent_coarse_fragments_cm)

# Create soil metrics table ----

# Set target pattern
target_pattern = '^13_soilmetrics.*csv'

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
  rename_fields = c(site_visit_code = 'site_visit_id')
  input_data = read_csv(data_file, show_col_types = FALSE) %>%
    rename(any_of(rename_fields)) %>%
    mutate_if(is.logical, as.character) %>%
    mutate(water_measurement = case_when(water_measurement == 'NULL' ~ 'FALSE',
                                         .default = water_measurement))
  return(input_data)
}

# Read files into list
data_list = lapply(files_list, read_data_site_visit_rename)

# Combine list into data frame
data_combine = do.call(rbind, data_list)

# Join metadata tables to input table
soils_table = data_combine %>%
  select(site_visit_code, water_measurement, measure_depth_cm, ph,
         conductivity_mus, temperature_deg_c)

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
write_csv(project_table, file = output_project)
write_csv(site_table, file = output_sites)
write_csv(site_visit_table, file = output_visit)
write_csv(cover_table, file = output_vegetation)
write_csv(abiotic_table, file = output_abiotic)
write_csv(tussock_table, file = output_tussock)
write_csv(ground_table, file = output_ground)
write_csv(structural_table, file = output_structure)
write_csv(shrub_table, file = output_shrub)
write_csv(environment_table, file = output_environment)
write_csv(soils_table, file = output_soils)
write_csv(horizons_table, file = output_horizons)

# Close database connection ----
dbDisconnect(database_connection)

# Clear workspace ----
rm(list=ls())
