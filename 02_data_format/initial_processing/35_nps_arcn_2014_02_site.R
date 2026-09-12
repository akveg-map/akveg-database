# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# "Format Site Table for NPS Arctic Network 2014 data"
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-04-08
# Usage: Must be executed in R version 4.4.3+.
# Description: "Format Site Table for NPS Arctic Network 2014 data" reads in CSV tables exported from the NPS ARCN SQL database and formats site-level information for ingestion into the AKVEG Database. The script standardizes site codes, addresses null coordinates values, projects coordinates to NAD83, and adds required metadata fields. The output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Load packages ----
library(dplyr)
library(fs)
library(ggmap)
library(readr)
library(readxl)
library(sf)
library(stringr)
library(tidyr)

# Define directories ----

# Set root directory
drive <- "C:"
root_folder <- "ACCS_Work"

# Define input folders
project_folder <- path(drive, root_folder, "OneDrive - University of Alaska", "ACCS_Teams", "Vegetation", "AKVEG_Database", "Data")
plot_folder <- path(project_folder, "Data_Plots", "35_nps_arcn_2014")
source_folder <- path(plot_folder, "source")
workspace_folder <- path(plot_folder, "working")
template_folder <- path(project_folder, "Data_Entry")
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")

# Define datasets ----

# Define inputs
coordinates_input <- path(source_folder, "dbo_gps.csv")
plot_input <- path(source_folder, "dbo_plot.csv")
template_input <- path(template_folder, "02_site.xlsx")

# Define outputs
site_output <- path(plot_folder, "02_site_npsarcn2014.csv")
lookup_output <- path(workspace_folder, "lookup_site_codes.csv")

# Define functions ----
# Import database connection function
plotting_script <- path(
  repository_folder,
  "02_data_format", "utils", "plot_site_coordinates.R"
)
source(plotting_script)

# Read in data ----
coordinates_original <- read_csv(coordinates_input)
plot_original <- read_csv(plot_input, col_select = c(Node, Plot, PlotSelection))
template <- colnames(read_xlsx(path = template_input))

# Drop site with incomplete data ----
# Site does not have vegetation cover data, and incomplete ground cover data
coordinates <- coordinates_original %>%
  filter(!(Node == "CKR" & Plot == 8))

# Explore coordinates ----
# Convert coordinate fields to numeric
# Prioritize using corrected GPS coordinates. When those (and by default trimble cols) are null, default to recreational GPS coordinates
# Populate horizontal error and positional accuracy fields based on which cols was selected
coordinates <- coordinates %>%
  mutate(across(matches("DD84|Prec"), ~ as.numeric(.))) %>% # Introduces NA when coordinates are "NULL"
  mutate(
    lat_dd84 = case_when(!is.na(GPScorDD84lat) ~ GPScorDD84lat,
      .default = GPSrecDD84lat
    ),
    long_dd84 = case_when(!is.na(GPScorDD84lon) ~ GPScorDD84lon,
      .default = GPSrecDD84lon
    ),
    h_error_m = case_when(!is.na(GPScorHorzPrec) ~ GPScorHorzPrec,
      .default = -999
    ),
    positional_accuracy = case_when(!is.na(GPScorDD84lat) ~ "mapping grade GPS",
      .default = "consumer grade GPS"
    )
  ) %>%
  select(
    Node, Plot,
    lat_dd84, long_dd84, h_error_m, positional_accuracy
  )

# Re-project coordinates ----
summary(coordinates$lat_dd84) # Y-axis, positive values
summary(coordinates$long_dd84) # X-axis, negative values

# Convert to sf object
# Datum is WGS 84
coordinates_sf <- st_as_sf(coordinates,
  coords = c("long_dd84", "lat_dd84"),
  crs = 4326
)

# Re-project to NAD 83 (EPSG 4269)
coordinates_sf_project <- st_transform(x = coordinates_sf, crs = 4269)
st_crs(coordinates_sf_project) # Ensure correct EPSG is listed

# Look for spatial outliers ----
plot_display <- "FALSE"

if (plot_display == "TRUE") {
  plot_outliers(coordinates_sf_project, api_key, 5)
}

# No spatial outliers detected

# Extract coordinates back into df
# Drop old coordinates to avoid confusion
coordinates <- coordinates %>%
  bind_cols(st_coordinates(coordinates_sf_project)) %>%
  select(-c(long_dd84, lat_dd84))

# Populate remaining columns ----
site_final <- coordinates %>%
  left_join(plot_original, by = c("Node", "Plot")) %>% # Obtain 'PlotSelection' column
  mutate(
    establishing_project_code = "nps_arcn_2014",
    location_type = if_else(PlotSelection == "deliberate",
      "targeted", "random"
    ),
    longitude_dd = round(X, digits = 5),
    latitude_dd = round(Y, digits = 5),
    h_datum = "NAD83",
    perspective = "ground",
    cover_method = "line-point intercept",
    plot_dimensions_m = "8 radius",
    new_plot_id = case_when(Plot < 10 ~ str_c("0", as.character(Plot)),
      .default = as.character(Plot)
    ),
    site_code = str_c(Node, new_plot_id, sep = "_")
  )

# Create look-up table for old-new site codes
lookup_table <- coordinates_original %>%
  select(Node, Plot) %>%
  right_join(site_final, by = c("Node", "Plot")) %>% # Drop CKR-08
  select(Node, Plot, site_code)

# Select only relevant columns
site_final <- site_final %>%
  select(all_of(template))

# QA/QC -----

# Do any of the columns have null values that need to be addressed?
cbind(
  lapply(
    lapply(site_final, is.na),
    sum
  )
)

# Ensure that each site code is unique
length(unique(site_final$site_code)) == nrow(site_final)

# Are any sites missing coordinates?
site_final %>%
  filter(is.na(latitude_dd) | is.na(longitude_dd))

# Export CSV ----
write_csv(site_final, site_output)
write_csv(lookup_table, lookup_output)

# Clear workspace ----
rm(list = ls())
