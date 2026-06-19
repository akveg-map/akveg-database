# -*- coding: utf-8 -*-
#' @title Helper Functions for Combining Individual Project Tables Into Aggregate Tables For SQL Ingestion
#' @description
#' This script provides cleaning, standardization, and join logic to correct erroneous entries and
#' transition datasets from the v1.0 to v2.0 AKVEG database schema. It is designed to be sourced
#' by `01_Combine_Tables.R` and used within a `pmap` workflow.
#' @author Amanda Droghini
#' @date 2026-06-19
#
# ===========================================================================
# GLOBAL HELPERS ----
# ===========================================================================

#' Find Files And Warn If Missing
#' @description Find pattern-matching files in multiple folders with an optional warning if the file is missing
#' @param folders Vector of directory paths
#' @param pattern Regex string to match file names
#' @param show_warning Logical; if TRUE, produces a warning if a folder is empty
find_files_warning <- function(folders, pattern, show_warning = FALSE) {
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


#' Standardize Field Names
#' @description Renames fields to ensure consistent names across all tables, consistent with the AKVEG Database schema 2.0
rename_columns <- function(df) {
  df |>
    rename(any_of(c(
      site_visit_code = "site_visit_id",
      establishing_project_code = "establishing_project",
      homogeneous = "homogenous",
      horizon_primary_code = "horizon_primary",
      horizon_suffix_1_code = "horizon_suffix_1",
      horizon_suffix_2_code = "horizon_suffix_2",
      horizon_secondary_code = "horizon_secondary",
      horizon_suffix_3_code = "horizon_suffix_3",
      horizon_suffix_4_code = "horizon_suffix_4",
      matrix_hue_code = "matrix_hue",
      nonmatrix_hue_code = "nonmatrix_hue"
    )))
}

# ===========================================================================
# 00. METADATA ----
# ===========================================================================
#' Clean Metadata
#' @description Removes duplicate values and arranges column alphabetically.
#' @param df A data frame of pre-processed taxonomy data.
clean_metadata <- function(df, value_name) {
  df |>
    distinct(.data[[value_name]]) |> 
    arrange(.data[[value_name]])
}

#' Join Taxon Source Table
join_source_table <- function(df, value_name, join_table) {
df |> 
  left_join(join_table, by = value_name)
}

# ===========================================================================
# 01. PROJECT ----
# ===========================================================================

#' Join Project Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Returns foreign keys (for constrained fields), numeric fields, and unconstrained character fields.
join_project_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$completion, by = "completion") |>
    left_join(lookup$organization, by = c("originator" = "organization")) |>
    rename(originator_id = organization_id) |>
    left_join(lookup$organization, by = c("funder" = "organization")) |>
    rename(funder_id = organization_id) |>
    left_join(lookup$personnel, by = c("manager" = "personnel")) |>
    rename(manager_id = personnel_id)
}

#' Join Project Source table
#' #' @description Converts source type to lowercase for consistency with constrained values. Returns foreign key values for constrained fields.
join_source_metadata <- function(df, lookup) {
  df |>
    mutate(source_type = str_to_lower(source_type),
           source_date = na_if(source_date, "NULL"),
           acquisition_date = na_if(acquisition_date, "NULL")
           ) |>
    mutate(source_date = as.Date(source_date),
           acquisition_date = as.Date(acquisition_date)
           ) |> 
    left_join(lookup_data$source_type, by = "source_type")
}
# ===========================================================================
# 02. SITE ----
# ===========================================================================
#' Clean Site Data
#' @description Renames multi-year projects that should be treated as a single project.
#' @param df A data frame of pre-processed data.
clean_site_data <- function(df) {
  df |>
    rename_columns() |>
    mutate(
      establishing_project_code = if_else(
        establishing_project_code == "accs_nelchina_2022",
        "accs_nelchina_2023",
        establishing_project_code
      ),
      across(c(latitude_dd, longitude_dd), ~ round(.x, digits = 9))
    )
}

#' Join Site Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys (for constrained fields), numeric fields, and unconstrained character fields.
#' @param df A data frame of processed data.
#' @param lookup A named list containing constrained values in the database.
join_site_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$perspective, by = "perspective") |>
    left_join(lookup$method, by = "cover_method") |>
    left_join(lookup$dimensions, by = "plot_dimensions_m") |>
    left_join(lookup$datum, by = "h_datum") |>
    left_join(lookup$accuracy, by = "positional_accuracy") |>
    left_join(lookup$location, by = "location_type")
}

# ===========================================================================
# 03. SITE VISIT ----
# ===========================================================================

#' Clean Site Visit Data
#' @description Renames multi-year projects that should be treated as a single project, corrects typos and missing values in personnel field, and corrects and formats to lowercase structural class field .
#' @param df A data frame of pre-processed data.
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
    # Standardize column names names
    rename_columns() |>
    # Correct project code
    mutate(
      project_code = if_else(project_code == "accs_nelchina_2022",
        "accs_nelchina_2023",
        project_code
      ),
      # Correct personnel names
      across(
        c(veg_observer, veg_recorder, env_observer, soils_observer),
        \(x) replace_values(x, !!!name_fixes)
      ),
      veg_recorder = if_else(project_code == "accs_ribdon_2019" &
        is.na(veg_recorder), "Timm Nawrocki",
      veg_recorder
      ),
      # Correct structural class and format as lowercase
      structural_class = case_when(structural_class == "n/assess" ~ "not assessed",
        is.na(structural_class) ~ "not assessed",
        .default = str_to_lower(structural_class)
      )
    )
}

#' Join Site Visit Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys (for constrained fields), numeric fields, and unconstrained character fields.
#' @param df A data frame of processed data.
#' @param lookup A named list containing constrained values in the database.
join_visit_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$tier, by = "data_tier") |>
    left_join(lookup$personnel, by = c("veg_observer" = "personnel")) |>
    rename(veg_observer_id = personnel_id) |>
    left_join(lookup$personnel, by = c("veg_recorder" = "personnel")) |>
    rename(veg_recorder_id = personnel_id) |>
    left_join(lookup$personnel, by = c("env_observer" = "personnel")) |>
    rename(env_observer_id = personnel_id) |>
    left_join(lookup$personnel, by = c("soils_observer" = "personnel")) |>
    rename(soils_observer_id = personnel_id) |>
    left_join(lookup$structural_class, by = "structural_class") |>
    left_join(lookup$scope, by = c("scope_vascular" = "scope")) |>
    rename(scope_vascular_id = scope_id) |>
    left_join(lookup$scope, by = c("scope_bryophyte" = "scope")) |>
    rename(scope_bryophyte_id = scope_id) |>
    left_join(lookup$scope, by = c("scope_lichen" = "scope")) |>
    rename(scope_lichen_id = scope_id)
}

# ===========================================================================
# 04. VEGETATION COVER ----
# ===========================================================================

# Clean Vegetation Cover Data
#' @description Standardizes column names and corrects cover type values to match constrained values.
#' @param df A data frame of pre-processed data.
clean_vegetation_data <- function(df) {
  df |>
    # Correct column names
    rename_columns() |>
    # Correct cover type
    mutate(cover_type = case_when(cover_type == "absolute cover" ~ "absolute foliar cover",
      cover_type == "top cover" ~ "top foliar cover",
      .default = cover_type
    ))
}

# Join Vegetation Cover Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Corrects taxonomic codes, drops true duplicate records, and aggregates "near-duplicates" (duplicates in all fields except cover percent) by summing cover percent. Selects and orders columns to match the database schema. Returns foreign keys (for constrained fields), numeric fields, and unconstrained character fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_vegetation_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$cover_type, by = "cover_type") |>
    left_join(lookup$taxa, by = c("name_adjudicated" = "taxon_name")) |>
    rename(code_adjudicated = taxon_code) |>
    select(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status, cover_percent) |>
    # Correct code adjudicated for removed taxa
    mutate(code_adjudicated = case_when(
      name_original == "Castilleja caudata var. caudata" ~ "cascau",
      name_original == "Lysimachia europaea ssp. europaea" ~ "lyseur",
      name_original == "Montia fontana ssp. fontana" ~ "monfon",
      name_original == "Montia vassilievii ssp. vassilievii" ~ "monbos",
      name_original == "Trientalis europaea ssp. europaea" ~ "trieur",
      .default = code_adjudicated
    )) |>
    # Drop duplicates (same name, same % cover)
    distinct(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status, cover_percent) |>
    # Group 'duplicates' (different cover values) by summing cover percent (n=4)
    group_by(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status) |>
    summarize(cover_percent = sum(cover_percent)) |>
    ungroup()
}

# ===========================================================================
# 05. ABIOTIC TOP COVER ----
# ===========================================================================

#' Clean Abiotic Top Cover Data
#' @description Standardizes column names and renames 'ground_element' to 'abiotic_element'.
#' @param df A data frame of pre-processed data.
clean_abiotic_data <- function(df) {
  df |>
    rename_columns() |>
    rename(any_of(c(abiotic_element = "ground_element")))
}

#' Join Abiotic Top Cover Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys and essential linking fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_abiotic_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$element, by = c("abiotic_element" = "ground_element")) |>
    rename(abiotic_element_code = ground_element_code)
}

# ===========================================================================
# 06. WHOLE TUSSOCK COVER ----
# ===========================================================================

#' Clean Whole Tussock Cover Data
#' @description Standardizes column names and renames 'tussock_percent_cover' to 'cover_percent'.
#' @param df A data frame of pre-processed data.
clean_tussock_data <- function(df) {
  df |>
    rename_columns() |>
    rename(any_of(c(cover_percent = "tussock_percent_cover")))
}

#' Join Whole Tussock Cover Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys and essential linking fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_tussock_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$cover_type, by = "cover_type")
}

# ===========================================================================
# 07. GROUND COVER ----
# ===========================================================================

#' Join Ground Cover Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys and essential linking fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_ground_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$element, by = "ground_element")
}

# ===========================================================================
# 08. STRUCTURAL GROUP COVER ----
# ===========================================================================

#' Clean Structural Group Cover Data
#' @description Standardizes column names, renames 'structural_cover_percent' to 'cover_percent', and renames 'structural_cover_type' to 'cover_type'.
#' @param df A data frame of pre-processed data.
clean_structural_data <- function(df) {
  df |>
    rename_columns() |>
    rename(any_of(c(
      cover_percent = "structural_cover_percent",
      cover_type = "structural_cover_type"
    )))
}

#' Join Structural Group Cover Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys and essential linking fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_structural_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$structural_group, by = "structural_group") |>
    left_join(lookup$cover_type, by = "cover_type")
}

# ===========================================================================
# 09. SHRUB STRUCTURE ----
# ===========================================================================

#' Join Shrub Structure Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys and essential linking fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_shrub_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$taxa, by = c("name_adjudicated" = "taxon_name")) |>
    left_join(lookup$cover_type, by = "cover_type") |>
    left_join(lookup$class, by = "shrub_class") |>
    left_join(lookup$height, by = "height_type") |>
    rename(code_adjudicated = taxon_code)
}

# ===========================================================================
# 10. ENVIRONMENT ----
# ===========================================================================

#' Clean Environment Data
#' @description Enforces empty columns to be read in as character, standardizes column names, and corrects constrained values tomatch values in the most recent version of the data dictionary.
#' @param df A data frame of pre-processed data.
clean_environment_data <- function(df) {
  df |>
    # Enforce empty columns as character rather than boolean
    mutate(across(any_of(c("cryoturbation", "surface_water")), as.character)) |>
    rename_columns() |>
    # Correct names that are no longer in database dictionary
    mutate(
      geomorphology = case_when(geomorphology == "glaciofluvial outwash" ~ "glaciofluvial deposit",
        .default = geomorphology
      ),
      # Pluralize soil classes that aren't plural
      soil_class = case_when(is.na(soil_class) | soil_class %in% c("NULL", "not available", "not determined") ~ soil_class,
        str_detect(soil_class, "s$") ~ soil_class,
        .default = str_c(soil_class, "s")
      ),
      disturbance = case_when(disturbance == "wildlife grazing" ~ "wildlife foraging",
        .default = disturbance
      ),
      moisture_regime = case_when(moisture_regime == "xeric-mesic" | moisture_regime == "mesic-xeric heterogeneous" ~ "mesic-xeric heterogenous",
        moisture_regime == "mesic-hygric" | moisture_regime == "hygric-mesic" | moisture_regime == "hygric-mesic heterogeneous" ~ "hygric-mesic heterogenous",
        moisture_regime == "hygric-hydric" | moisture_regime == "hydric-hygric" ~ "hydric-hygric heterogenous",
        moisture_regime == "hydric-aquatic" ~ "aquatic-hydric heterogenous",
        moisture_regime == "hydric-mesic" | moisture_regime == "mesic-hydric" ~ "hydric-mesic heterogenous",
        .default = moisture_regime
      ),
      microtopography = case_when(microtopography == "tussock" ~ "tussocks",
        microtopography == "channelled" ~ "channeled",
        .default = microtopography
      ),
      macrotopography = case_when(macrotopography == "lakebed" ~ "lake bed",
        macrotopography == "mountain bench" ~ "bench",
        is.na(macrotopography) & geomorphology == "low center polygons" ~ "polygons low-center",
        .default = macrotopography
      ),
      geomorphology = case_when(geomorphology == "ocean shore" ~ "marine, shore",
        geomorphology == "low center polygons" ~ "NULL",
        geomorphology == "peninsula" ~ "NULL",
        geomorphology == "stream" ~ "aquatic, river",
        geomorphology == "lake" | geomorphology == "aquatic lake" ~ "aquatic, lake",
        geomorphology == "estuary" ~ "NULL",
        geomorphology == "valley lowland" ~ "valley, lowland",
        .default = geomorphology
      )
    )
}

#' Join Environment Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys, essential linking fields, and numeric fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_environment_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$physiography, by = "physiography") |>
    left_join(lookup$geomorphology, by = "geomorphology") |>
    left_join(lookup$macrotopography, by = "macrotopography") |>
    left_join(lookup$microtopography, by = "microtopography") |>
    left_join(lookup$moisture, by = c("moisture_regime" = "moisture")) |>
    left_join(lookup$drainage, by = "drainage") |>
    left_join(lookup$disturbance, by = "disturbance") |>
    left_join(lookup$severity, by = "disturbance_severity") |>
    left_join(lookup$restrictive, by = "restrictive_type") |>
    left_join(lookup$texture, by = c("dominant_texture_40_cm" = "soil_texture")) |>
    left_join(lookup$soil_class, by = "soil_class") |>
    rename(dominant_texture_40_cm_code = soil_texture_code)
}

# ===========================================================================
# 11. SOIL METRICS ----
# ===========================================================================

#' Clean Soil Metrics Data
#' @description Standardizes column names, converts logical fields to character, and corrects null values to boolean FALSE.
#' @param df A data frame of pre-processed data.
clean_soil_metrics_data <- function(df) {
  df |>
    rename_columns() |>
    mutate_if(is.logical, as.character) |>
    mutate(water_measurement = case_when(water_measurement == "NULL" ~ "FALSE",
      .default = water_measurement
    ))
}


#' Join Soil Metrics Table
#' @description Empty function to conform with lookup argument requirement
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_soil_metrics_metadata <- function(df, lookup) {
  return(df)
}

# ===========================================================================
# 12. SOIL HORIZONS ----
# ===========================================================================

#' Clean Soil Horizons Data
#' @description Standardizes column names, and renames 'depth_upper' and 'depth_lower' fields to append measurement units.
#' @param df A data frame of pre-processed data.
clean_soil_horizons_data <- function(df) {
  df |>
    rename_columns() |>
    rename(any_of(c(
      depth_upper_cm = "depth_upper",
      depth_lower_cm = "depth_lower"
    )))
}

#' Join Soil Horizons Table
#' @description Maps cleaned values to their corresponding database IDs using a lookup list. Selects and orders columns to match the database schema. Returns foreign keys, essential linking fields, and numeric fields.
#' @param df A data frame of processed data.
#' @param lookup A named list of constrained values in the database.
join_soil_horizons_metadata <- function(df, lookup) {
  df |>
    left_join(lookup$texture, by = c("texture" = "soil_texture")) |>
    left_join(lookup$structure, by = c("structure" = "soil_structure")) |>
    left_join(lookup$nonmatrix, by = "nonmatrix_feature") |>
    left_join(lookup$hue, by = c("matrix_hue_code" = "soil_hue")) |>
    select(-matrix_hue_code) |>
    rename(
      texture_code = soil_texture_code,
      structure_code = soil_structure_code,
      matrix_hue_code = soil_hue_code
    ) |>
    left_join(lookup$hue, by = c("nonmatrix_hue_code" = "soil_hue")) |>
    select(-nonmatrix_hue_code) |>
    rename(nonmatrix_hue_code = soil_hue_code)
}

# ===========================================================================
# SQL INGESTION ----
# ===========================================================================


#' Build SQL Tables
#' @description Creates database reference tables by splitting a SQL file into its individual statements and executing those statements. Running this function will potentially drop existing tables and replace them with empty ones.
execute_sql_build <- function(database_connection, repository_folder, script_name) {
  
  # Close any open transactions (e.g., resulting from transaction failures)
  try(DBI::dbExecute(database_connection, "ROLLBACK;"), silent = TRUE)
  
  message(paste("Executing build script:", script_name))
  
  # Define file path
  build_path <- fs::path(repository_folder, "01_database_build", script_name)
  
  # Read in full SQL statement
  full_sql <- readr::read_file(build_path)
  
  # Chunk the file into separate CREATE statements
  # Split by semicolon only if the semicolon is followed by a newline and a major SQL keyword
  sql_commands <- stringr::str_split(
    full_sql, 
    ";\\s*\\n(?=\\s*(CREATE|ALTER|START|COMMIT|DROP|INSERT|DELETE|UPDATE|--))"
  ) %>%
    purrr::flatten_chr() %>%
    stringr::str_trim() %>%
    purrr::keep(~ .x != "") |> 
    paste0(";") # Re-add the semicolon to the end of each chunk
  
  total_chunks <- length(sql_commands)
  
  # Execute each command individually
  # Use iwalk to produce visual counter message in console
  # Wrap in tryCatch to initiate rollback if any part of the transaction fails
  tryCatch({
    purrr::iwalk(sql_commands, function(cmd, i) {
      message(paste0("Chunk ", i, " of ", total_chunks, ": ", substr(cmd, 1, 40), "..."))
      DBI::dbExecute(database_connection, cmd)
      })
    message(paste("Finished script:", script_name))
}, error = function(e) {
    dbExecute(database_connection, "ROLLBACK;")
    message("--- DATA INSERT FAILURE")
    message(e$message)
    # Stop the script
    stop("Migration failed. Database has been rolled back to empty tables.")
  })
}


#' Insert Data into Tables
#' @description Inserts data into individual tables. Uses atomic loading to prevent partial data upload. This function assumes that the list element names match the database table names.
upload_to_database <- function(database_connection, final_tables) {
  
  # Close any open transactions (e.g., resulting from transaction failures)
  try(DBI::dbExecute(database_connection, "ROLLBACK;"), silent = TRUE)
  
  # Begin transaction
  DBI::dbExecute(database_connection, "BEGIN;")
  
  tryCatch({
    
    # Obtain table names
    table_list <- names(final_tables)
    
    # Iterate over tables in list and insert data in database
    for (i in seq_along(table_list)) {
      target_table <- table_list[i]
      message(paste0("Step ", i, " of ", length(table_list), ": Inserting into ", target_table, "..."))
      
      DBI::dbWriteTable(
        conn = database_connection,
        name = target_table,
        value = final_tables[[target_table]],
        append = TRUE,
        row.names = FALSE
      )
    }
    
    # Commit to database if no errors were encountered
    DBI::dbExecute(database_connection, "COMMIT;")
    message("--- Success! Data successfully migrated to the database. ---")
  }, ## If one of the insertions failed, rollback changes (revert to original state)  and print out error message
  error = function(e) {
    dbExecute(database_connection, "ROLLBACK;")
    message("--- DATA INSERT FAILURE")
    message(e$message)
    # Stop the script
    stop("Migration failed. Database has been rolled back to empty tables.")
  })
}
