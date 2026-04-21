# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Helper functions for 01_Combine_Tables.R
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-20
# Usage: Script should be executed in R 4.5.1+.
# ---------------------------------------------------------------------------

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


# --- Data cleaning/correction functions ---

# Site table (clean_site_data)
clean_site_data <- function(df) {
  df |>
    rename(any_of(c('establishing_project_code' = 'establishing_project'))) |>
    mutate(establishing_project_code = if_else(
      establishing_project_code == 'accs_nelchina_2022', 
      'accs_nelchina_2023', 
      establishing_project_code
    ))
}


# Site Visit table (clean_visit_data)
clean_visit_data <- function(df) {
  
  # Define personnel name corrections
  name_fixes <- list(
    "Jess Grunblatt" ~ "Jesse Grunblatt",
    "Robert Lieberman" ~ "Robert Liebermann",
    "NULL" ~ "none",
    "Unknown" ~ "unknown",
    "None" ~ "none"
  )
  
  df |>
    # Correct column names
    rename(any_of(c(site_visit_code = 'site_visit_id',
                    homogeneous = 'homogenous'))) |>
    # Correct project code
    mutate(project_code = if_else(project_code == 'accs_nelchina_2022', 
                                             'accs_nelchina_2023', 
                                             project_code),
           # Correct personnel names
           across(c(veg_observer, veg_recorder, env_observer, soils_observer), 
                  \(x) case_match(x, !!!name_fixes, .default = x)),
           veg_recorder = if_else(project_code == 'accs_ribdon_2019' & 
                                    is.na(veg_recorder), 'Timm Nawrocki', 
                                  veg_recorder),
           # Correct structural class formatting
           structural_class = case_when(structural_class == 'n/assess' ~ 'not assessed',
                                        is.na(structural_class) ~ 'not assessed',
                                        .default = str_to_lower(structural_class))
                                        )
}

# Vegetation Cover table (clean_vegetation_data)
clean_vegetation_data <- function(df) {
  df |>
    # Correct column names
    rename(any_of(c(site_visit_code = 'site_visit_id'))) |> 
    # Correct cover type
    mutate(cover_type = case_when(cover_type == 'absolute cover' ~ 'absolute foliar cover',
                                  cover_type == 'top cover' ~ 'top foliar cover',
                                  .default = cover_type))
}
  
# --- Join functions ---

# Project table (join_project_metadata)
join_project_metadata <- function(df, lookup) {
  df |> 
    left_join(lookup$completion, by = 'completion') %>%
    left_join(lookup$organization, by = c('originator' = 'organization')) %>%
    rename(originator_id = organization_id) %>%
    left_join(lookup$organization, by = c('funder' = 'organization')) %>%
    rename(funder_id = organization_id) %>%
    left_join(lookup$personnel, by = c('manager' = 'personnel')) %>%
    rename(manager_id = personnel_id) %>%
    select(project_code, project_name, originator_id, funder_id, manager_id,
           completion_id, year_start, year_end, project_description, private)
}

# Site table (join_site_metadata)
join_site_metadata <- function(df, lookup) {
  df %>%
    left_join(lookup$perspective, by = 'perspective') %>%
    left_join(lookup$method, by = 'cover_method') %>%
    left_join(lookup$dimensions, by = 'plot_dimensions_m') %>%
    left_join(lookup$datum, by = 'h_datum') %>%
    left_join(lookup$accuracy, by = 'positional_accuracy') %>%
    left_join(lookup$location, by = 'location_type') %>%
    select(site_code, establishing_project_code, perspective_id, cover_method_id,
           h_datum_epsg, latitude_dd, longitude_dd, h_error_m, positional_accuracy_id,
           plot_dimensions_id, location_type_id)
}

# Site Visit table (join_visit_metadata)
join_visit_metadata = function(df, lookup) {
  df |> 
  left_join(lookup$tier, by = 'data_tier') %>%
  left_join(lookup$personnel, by = c('veg_observer'= 'personnel')) %>%
  rename(veg_observer_id = personnel_id) %>%
  left_join(lookup$personnel, by = c('veg_recorder' = 'personnel')) %>%
  rename(veg_recorder_id = personnel_id) %>%
  left_join(lookup$personnel, by = c('env_observer'= 'personnel')) %>%
  rename(env_observer_id = personnel_id) %>%
  left_join(lookup$personnel, by = c('soils_observer' = 'personnel')) %>%
  rename(soils_observer_id = personnel_id) %>%
  left_join(lookup$structural_class, by = 'structural_class') %>%
  left_join(lookup$scope, by = c('scope_vascular'= 'scope')) %>%
  rename(scope_vascular_id = scope_id) %>%
  left_join(lookup$scope, by = c('scope_bryophyte' = 'scope')) %>%
  rename(scope_bryophyte_id = scope_id) %>%
  left_join(lookup$scope, by = c('scope_lichen' = 'scope')) %>%
  rename(scope_lichen_id = scope_id) %>%
  # Select final fields
  select(site_visit_code, project_code, site_code, data_tier_id, observe_date,
         veg_observer_id, veg_recorder_id, env_observer_id, soils_observer_id, structural_class_code,
         scope_vascular_id, scope_bryophyte_id, scope_lichen_id, homogeneous)
}
