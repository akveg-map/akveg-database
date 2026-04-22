# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Helper functions for 01_Combine_Tables.R
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-20
# Usage: Script should be executed in R 4.5.1+.
# ---------------------------------------------------------------------------

# --- Function 1: find_files_warning ---
# Iterate over plot folders to find files matching a pattern. Optionally print a warning if a folder is missing a file
find_files_warning <- function(folders, pattern, show_warning = TRUE) {
  # Create a named list where each element is the result of dir_ls
  search_results <- folders |>
    set_names() |> # Attach folder name to the result
    map(\(dir) dir_ls(dir, regexp = pattern))
  
  if (show_warning) {
    # Identify folders where the length of the result is 0
    missing_folders <- search_results |>
      keep(\(x) length(x) == 0) |>
      names()
    
    # Issue a warning if a file is missing
    if (length(missing_folders) > 0) {
      warning(
        paste(
          "The following folders are missing a file for pattern [",
          pattern,
          "]:\n",
          paste("-", missing_folders, collapse = "\n")
        )
      )
    }
  }
  
  # Return vector of file paths
  return(list_c(search_results))
}


# --- Data cleaning/correction functions ---

# Global renaming function
## Handles renaming of fields where the renaming is consistent across all tables in which it appears (e.g., 'site_visit_id' column to 'site_visit_code')
rename_columns = function (df) {
  df |> 
    rename(any_of(c(site_visit_code = 'site_visit_id',
                    establishing_project_code = 'establishing_project',
                    homogeneous = 'homogenous')))
}

# Site table (clean_site_data)
clean_site_data <- function(df) {
  df |>
    rename_columns() |>
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
    # Correct field names
    rename_columns() |> 
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
    rename_columns() |> 
    # Correct cover type
    mutate(cover_type = case_when(cover_type == 'absolute cover' ~ 'absolute foliar cover',
                                  cover_type == 'top cover' ~ 'top foliar cover',
                                  .default = cover_type))
}

# Abiotic Top Cover table (clean_abiotic_data)
clean_abiotic_data = function (df) {
  df |> 
    rename_columns() |> 
    rename(any_of(c(abiotic_element = 'ground_element')))
}

# Whole Tussock Cover table (clean_tussock_data)
clean_tussock_data = function (df) {
  df |> 
    rename_columns() |> 
    rename(any_of(c(cover_percent = 'tussock_percent_cover')))
}

# Structural Group Cover table (clean_structural_data)
clean_structural_data = function (df) {
  df |> 
    rename_columns() |> 
    rename(any_of(c(cover_percent = 'structural_cover_percent',
                    cover_type = 'structural_cover_type')))
}

# Environment table (clean_environment_data)
clean_environment_data = function (df) {
  df |> 
    # Enforce empty columns being read as character rather than boolean
    mutate(across(any_of(c("cryoturbation", "surface_water")), as.character)) |>
    rename_columns() |>
    # Correct names that are no longer in database dictionary
    mutate(geomorphology = case_when(geomorphology == 'glaciofluvial outwash' ~ 'glaciofluvial deposit',
                                     .default = geomorphology),
           # Pluralize soil classes that aren't plural
           soil_class = case_when(is.na(soil_class) | soil_class %in% c("NULL", "not available") ~ soil_class,
                                  str_detect(soil_class, "s$") ~ soil_class,
                                  .default = str_c(soil_class, "s")),
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
           ))
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

# Vegetation Cover table (join_vegetation_metadata)
join_vegetation_metadata = function(df, lookup) {
  df |> 
    left_join(lookup$cover_type, by = 'cover_type') %>%
    left_join(lookup$taxa, by = c('name_adjudicated' = 'taxon_name')) %>%
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
    # Group 'duplicates' (different cover values) by summing cover percent (n=4)
    group_by(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status) %>% 
    summarize(cover_percent = sum(cover_percent)) %>% 
    ungroup()
}

# Abiotic Top Cover table (join_abiotic_metadata)
join_abiotic_metadata = function(df, lookup) {
  df |> 
    left_join(lookup$element, by = c('abiotic_element' = 'ground_element')) %>%
    rename(abiotic_element_code = ground_element_code) %>%
    select(site_visit_code, abiotic_element_code, abiotic_top_cover_percent)
}

# Whole Tussock Cover table (join_tussock_metadata)
join_tussock_metadata = function(df, lookup) {
  df |> 
  left_join(lookup$cover_type, by = 'cover_type') %>%
  select(site_visit_code, cover_type_id, cover_percent)
}

# Ground Cover table (join_ground_metadata)
join_ground_metadata = function(df, lookup) {
  df |> 
  left_join(lookup$element, by = 'ground_element') %>%
  select(site_visit_code, ground_element_code, ground_cover_percent)
}

# Structural Group Cover table (join_structural_metadata)
join_structural_metadata = function(df, lookup) {
  df |> 
  left_join(lookup$structural_group, by = 'structural_group') %>%
  left_join(lookup$cover_type, by = 'cover_type') %>%
  select(site_visit_code, cover_type_id, structural_group_id, cover_percent)
}

# Shrub Structure table (join_shrub_metadata)
join_shrub_metadata = function(df, lookup) {
  df |>
    left_join(lookup$taxa, by = c('name_adjudicated' = 'taxon_name')) %>%
    left_join(lookup$cover_type, by = 'cover_type') %>%
    left_join(lookup$class, by = 'shrub_class') %>%
    left_join(lookup$height, by = 'height_type') %>%
    rename(code_adjudicated = taxon_code) %>%
    select(
      site_visit_code,
      name_original,
      code_adjudicated,
      shrub_class_id,
      height_type_id,
      height_cm,
      cover_type_id,
      cover_percent,
      mean_diameter_cm,
      number_stems,
      shrub_subplot_area_m2
    )
}

# Environment table (join_environment_metadata)
join_environment_metadata = function(df, lookup) {
  df |>
  left_join(lookup$physiography, by = 'physiography') %>%
  left_join(lookup$geomorphology, by = 'geomorphology') %>%
  left_join(lookup$macrotopography, by = 'macrotopography') %>%
  left_join(lookup$microtopography, by = 'microtopography') %>%
  left_join(lookup$moisture, by = c('moisture_regime' = 'moisture')) %>%
  left_join(lookup$drainage, by = 'drainage') %>%
  left_join(lookup$disturbance, by = 'disturbance') %>%
  left_join(lookup$severity, by = 'disturbance_severity') %>%
  left_join(lookup$restrictive, by = 'restrictive_type') %>%
  left_join(lookup$texture, by = c('dominant_texture_40_cm' = 'soil_texture')) %>%
  left_join(lookup$soil_class, by = 'soil_class') %>%
  rename(dominant_texture_40_cm_code = soil_texture_code) %>%
  select(site_visit_code, physiography_id, geomorphology_id, macrotopography_id,
         microtopography_id, moisture_id, drainage_id, disturbance_id,
         disturbance_severity_id, disturbance_time_y, depth_water_cm,
         depth_moss_duff_cm, depth_restrictive_layer_cm, restrictive_type_id,
         microrelief_cm, surface_water, soil_class_id, cryoturbation,
         dominant_texture_40_cm_code, depth_15_percent_coarse_fragments_cm)
}
