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
    left_join(lookup$method, by = 'cover_method') %>%
    left_join(lookup$dimensions, by = 'plot_dimensions_m') %>%
    left_join(lookup$datum, by = 'h_datum') %>%
    left_join(lookup$accuracy, by = 'positional_accuracy') %>%
    left_join(lookup$location, by = 'location_type') %>%
    select(site_code, establishing_project_code, perspective_id, cover_method_id,
           h_datum_epsg, latitude_dd, longitude_dd, h_error_m, positional_accuracy_id,
           plot_dimensions_id, location_type_id)
}

