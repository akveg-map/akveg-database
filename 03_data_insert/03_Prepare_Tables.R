# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Prepare data for upload
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-05-28
# Usage: Script should be executed in R 4.4.3+.
# Description: "Prepare data for upload" parses the combined tables into SQL INSERT statements that can be used to add data to the AKVEG database.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(readr)
library(stringr)
library(tidyr)

# Define directories ----
drive <- "C:"
root_folder <- "ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"
data_folder <- path(drive, root_folder, "Data", "Data_Plots")

# Output files to `sql_statements`

# Create config table to hold table-specific values and functions
config_table <- tribble(
  ~table_name, ~input_path, ~output_path,
  #--------------------------|------------|-----------
  "project", "projects.csv", "01a_Insert_Project.sql",
  "site", "sites.csv", "02_Insert_Site.sql",
  "site_visit", "site_visits.csv", "03_Insert_SiteVisit.sql",
  "vegetation_cover", "vegetation_cover.csv", "05_Insert_VegetationCover.sql",
  "abiotic_top_cover", "abiotic_top_cover.csv", "06_Insert_AbioticTopCover.sql",
  "whole_tussock_cover", "whole_tussock_cover.csv", "07_Insert_WholeTussockCover.sql",
  "ground_cover", "ground_cover.csv", "08_Insert_GroundCover.sql",
  "structural_group_cover", "structural_group_cover.csv", "09_Insert_StructuralGroupCover.sql",
  "shrub_structure", "shrub_structure.csv", "11_Insert_ShrubStructure.sql",
  "environment", "environment.csv", "12_Insert_Environment.sql",
  "soil_metrics", "soil_metrics.csv", "13_Insert_SoilMetrics.sql",
  "soil_horizons", "soil_horizons.csv", "14_Insert_SoilHorizons.sql",
  "citations", "citations.csv", "01b_Insert_Citations.sql",
  "project_source", "project_source.csv", "01c_Insert_Source.sql",
  "project_citations", "project_citations.csv", "01d_Insert_Project_Citations.sql"
)

# Prepare project table ----

# Read in data
if (file_exists(corrected_path)) {
  project_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  project_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

## Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert project metadata",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert project metadata" pushes the metadata for all projects into the project table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

## Add data insert statement
statement <- c(
  statement,
  "-- Insert project data into project table",
  "INSERT INTO project (project_code, project_name, originator_id, funder_id, manager_id,
  completion_id, year_start, year_end, project_description, private) VALUES"
)
input_sql <- project_table %>%
  mutate_if(is.character,
    str_replace_all,
    pattern = "'", replacement = "''"
  ) %>%
  mutate(project_code = paste("'", project_code, "'", sep = "")) %>%
  mutate(project_name = paste("'", project_name, "'", sep = "")) %>%
  mutate(project_description = paste("'", project_description, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <- paste(
  str_sub(input_sql[nrow(input_sql), ],
    start = 1,
    end = -2
  ),
  ";",
  sep = ""
)
for (line in input_sql) {
  statement <- c(statement, line)
}

## Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Replace NA values in statement
statement <- str_replace(statement, ", NA,", ", NULL,")

# Write statement to SQL file
write_lines(statement, output_project)

# Prepare site table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in table
if (file_exists(corrected_path)) {
  site_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  site_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

## Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert site data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert site data" pushes all site data into the site table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

## Add data insert statement
statement <- c(
  statement,
  "-- Insert site data into site table",
  "INSERT INTO site (site_code, establishing_project_code, perspective_id, cover_method_id,
  h_datum_epsg, latitude_dd, longitude_dd, h_error_m, positional_accuracy_id,
  plot_dimensions_id, location_type_id) VALUES"
)
input_sql <- site_table %>%
  mutate_if(is.character,
    str_replace_all,
    pattern = "'", replacement = "''"
  ) %>%
  mutate(site_code = paste("'", site_code, "'", sep = "")) %>%
  mutate(establishing_project_code = paste("'", establishing_project_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <- paste(
  str_sub(input_sql[nrow(input_sql), ],
    start = 1,
    end = -2
  ),
  ";",
  sep = ""
)
for (line in input_sql) {
  statement <- c(statement, line)
}

## Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, output_sites)

# Prepare site visit table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in table
if (file_exists(corrected_path)) {
  site_visit_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  site_visit_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert site visit data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert site visit data" pushes all site visit data into the site visit table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert site visit data into site_visit table",
  "INSERT INTO site_visit (site_visit_code, project_code, site_code, data_tier_id, observe_date, veg_observer_id, veg_recorder_id, env_observer_id, soils_observer_id, structural_class_code, scope_vascular_id, scope_bryophyte_id, scope_lichen_id, homogeneous) VALUES"
)
input_sql <- site_visit_table %>%
  mutate_if(is.character,
    str_replace_all,
    pattern = "'", replacement = "''"
  ) %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  mutate(project_code = paste("'", project_code, "'", sep = "")) %>%
  mutate(observe_date = paste("'", observe_date, "'", sep = "")) %>%
  mutate(site_code = paste("'", site_code, "'", sep = "")) %>%
  mutate(structural_class_code = paste("'", structural_class_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, output_visit)

# Prepare vegetation cover table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  cover_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  cover_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert vegetation cover data",
  "-- Author: Timm Nawrocki, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 14+ database.",
  '-- Description: "Insert vegetation cover data" pushes all vegetation cover data into the vegetation cover table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert vegetation cover data into vegetation_cover table",
  "INSERT INTO vegetation_cover (site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status, cover_percent) VALUES"
)
input_sql <- cover_table %>%
  mutate_if(is.character,
    str_replace_all,
    pattern = "'", replacement = "''"
  ) %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  mutate(name_original = paste("'", name_original, "'", sep = "")) %>%
  mutate(code_adjudicated = paste("'", code_adjudicated, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, output_vegetation)

# Prepare abiotic cover table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  abiotic_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  abiotic_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert abiotic top cover data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert abiotic top cover data" pushes all abiotic top cover data into the abiotic top cover table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert abiotic top cover data into abiotic_top_cover table",
  "INSERT INTO abiotic_top_cover (site_visit_code, abiotic_element_code, abiotic_top_cover_percent) VALUES"
)
input_sql <- abiotic_table %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  mutate(abiotic_element_code = paste("'", abiotic_element_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, output_abiotic)

# Prepare whole tussock table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in file
if (file_exists(corrected_path)) {
  tussock_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  tussock_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert whole tussock cover data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert whole tussock cover data" pushes all whole tussock cover data into the whole tussock cover table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert whole tussock cover data into whole_tussock_cover table",
  "INSERT INTO whole_tussock_cover (site_visit_code, cover_type_id, cover_percent) VALUES"
)
input_sql <- tussock_table %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, output_tussock)

# Prepare ground cover table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  ground_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  ground_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert ground cover data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert ground cover data" pushes all ground cover data into the ground cover table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert ground cover data into ground_cover table",
  "INSERT INTO ground_cover (site_visit_code, ground_element_code, ground_cover_percent) VALUES"
)
input_sql <- ground_table %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  mutate(ground_element_code = paste("'", ground_element_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, output_ground)

# Prepare structural group cover table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  structural_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  structural_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert structural group cover data",
  "-- Author: Timm Nawrocki, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert structural group cover data" pushes all structural group cover data into the structural group cover table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert structural group cover data into ground_cover table",
  "INSERT INTO structural_group_cover (site_visit_code, cover_type_id, structural_group_id, cover_percent) VALUES"
)
input_sql <- structural_table %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Write statement to SQL file
write_lines(statement, output_structural)

# Prepare shrub structure table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  shrub_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  shrub_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert shrub structure data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert shrub structure data" pushes all shrub structure data into the shrub structure table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert shrub structure data into shrub_structure table",
  "INSERT INTO shrub_structure (site_visit_code, name_original, code_adjudicated, shrub_class_id, height_type_id, height_cm, cover_type_id, cover_percent, mean_diameter_cm, number_stems, shrub_subplot_area_m2) VALUES"
)
input_sql <- shrub_table %>%
  mutate_if(is.character,
    str_replace_all,
    pattern = "'", replacement = "''"
  ) %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  mutate(name_original = paste("'", name_original, "'", sep = "")) %>%
  mutate(code_adjudicated = paste("'", code_adjudicated, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Replace NA values in statement
statement <- str_replace_all(statement, ", NA", ", NULL")
statement <- str_replace_all(statement, ", 'NA'", ", NULL")

# Write statement to SQL file
write_lines(statement, output_shrub)

# Prepare environment table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  environment_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  environment_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert environment data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert environment data" pushes all environment data into the environment table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert environment data into environment table",
  "INSERT INTO environment (site_visit_code, physiography_id, geomorphology_id, macrotopography_id, microtopography_id, moisture_id, drainage_id, disturbance_id, disturbance_severity_id, disturbance_time_y, depth_water_cm, depth_moss_duff_cm, depth_restrictive_layer_cm, restrictive_type_id, microrelief_cm, surface_water, soil_class_id, cryoturbation, dominant_texture_40_cm_code, depth_15_percent_coarse_fragments_cm) VALUES"
)
input_sql <- environment_table %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  mutate(
    dominant_texture_40_cm_code =
      paste("'", dominant_texture_40_cm_code, "'", sep = "")
  ) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Replace NA values in statement
statement <- str_replace_all(statement, ", NA", ", NULL")
statement <- str_replace_all(statement, ", 'NA'", ", NULL")

# Write statement to SQL file
write_lines(statement, output_environment)

# Prepare soil metrics table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  soils_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  soils_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert soil metrics data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert soil metrics data" pushes all soil metrics data into the soil metrics table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert soil metrics data into soil_metrics table",
  "INSERT INTO soil_metrics (site_visit_code, water_measurement, measure_depth_cm, ph, conductivity_mus, temperature_deg_c) VALUES"
)
input_sql <- soils_table %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Replace NA values in statement
statement <- str_replace_all(statement, ", NA", ", NULL")

# Write statement to SQL file
write_lines(statement, output_soil)

# Prepare soil horizons table ----

# Define input file
corrected_path <- path(data_folder, "processed", "corrected", target_pattern)
processed_path <- path(
  data_folder,
  "processed",
  target_pattern
)

# Read in data
if (file_exists(corrected_path)) {
  horizons_table <- read_csv(corrected_path, show_col_types = FALSE)
  print(str_c("Reading in corrected file for", target_pattern, sep = " "))
} else {
  horizons_table <- read_csv(processed_path, show_col_types = FALSE)
}

# Write data to SQL file

# Write statement header
statement <- c(
  "-- -*- coding: utf-8 -*-",
  "-- ---------------------------------------------------------------------------",
  "-- Insert soil horizons data",
  "-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science",
  paste("-- Last Updated:", Sys.Date(), sep = " "),
  "-- Usage: Script should be executed in a PostgreSQL 16+ database.",
  '-- Description: "Insert soil horizons data" pushes all soil horizons data into the soil horizons table of the database.',
  "-- ---------------------------------------------------------------------------",
  "",
  "-- Initialize transaction",
  "START TRANSACTION;",
  ""
)

# Add data insert statement
statement <- c(
  statement,
  "-- Insert soil horizons data into soil horizons table",
  "INSERT INTO soil_horizons (site_visit_code, horizon_order, thickness_cm, depth_upper_cm, depth_lower_cm, depth_extend, horizon_primary_code, horizon_suffix_1_code, horizon_suffix_2_code, horizon_secondary_code, horizon_suffix_3_code, horizon_suffix_4_code, texture_code, clay_percent, total_coarse_fragment_percent, gravel_percent, cobble_percent, stone_percent, boulder_percent, structure_code, matrix_hue_code, matrix_value, matrix_chroma, nonmatrix_feature_code, nonmatrix_hue_code, nonmatrix_value, nonmatrix_chroma) VALUES"
)
input_sql <- horizons_table %>%
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  mutate(horizon_primary_code = paste("'", horizon_primary_code, "'", sep = "")) %>%
  mutate(horizon_suffix_1_code = paste("'", horizon_suffix_1_code, "'", sep = "")) %>%
  mutate(horizon_suffix_2_code = paste("'", horizon_suffix_2_code, "'", sep = "")) %>%
  mutate(horizon_secondary_code = paste("'", horizon_secondary_code, "'", sep = "")) %>%
  mutate(horizon_suffix_3_code = paste("'", horizon_suffix_3_code, "'", sep = "")) %>%
  mutate(horizon_suffix_4_code = paste("'", horizon_suffix_4_code, "'", sep = "")) %>%
  mutate(texture_code = paste("'", texture_code, "'", sep = "")) %>%
  mutate(structure_code = paste("'", structure_code, "'", sep = "")) %>%
  mutate(matrix_hue_code = paste("'", matrix_hue_code, "'", sep = "")) %>%
  mutate(nonmatrix_feature_code = paste("'", nonmatrix_feature_code, "'", sep = "")) %>%
  mutate(nonmatrix_hue_code = paste("'", nonmatrix_hue_code, "'", sep = "")) %>%
  unite(sql, sep = ", ", remove = TRUE) %>%
  mutate(sql = paste("(", sql, "),", sep = ""))
input_sql[nrow(input_sql), ] <-
  paste(str_sub(input_sql[nrow(input_sql), ],
    start = 1, end = -2
  ), ";", sep = "")
for (line in input_sql) {
  statement <- c(statement, line)
}

# Finalize statement
statement <- c(
  statement,
  "",
  "-- Commit transaction",
  "COMMIT TRANSACTION;"
)

# Replace NA values in statement
statement <- str_replace_all(statement, ", NA", ", NULL")
statement <- str_replace_all(statement, ", 'NA'", ", NULL")
statement <- str_replace_all(statement, ", 'NULL'", ", NULL")

# Write statement to SQL file
write_lines(statement, output_horizons)

# Clear workspace ----
rm(list = ls())
