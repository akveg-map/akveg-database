# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# "Format Site Table for USFWS Unalaska 2007 data"
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2024-07-25
# Usage: Must be executed in R version 4.4.1+.
# Description: "Format Site Table for USFWS Unalaska 2007 data" formats site-level information for ingestion into the AKVEG Database. The script formats site codes, projects coordinates to NAD83, looks for spatial outliers, standardizes plot dimension values, adds required metadata fields, and performs QA/QC checks. The output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Load packages ----
library(dplyr)
library(fs)
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
project_folder <- path(drive, root_folder, "OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database")
plot_folder <- path(project_folder, "Data/Data_Plots/40_fws_unalaska_2007")
source_folder <- path(plot_folder, "source", "modified_source_data")
template_folder <- path(project_folder, "Data/Data_Entry")
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")

# Define datasets ----
# Define input datasets
site_input <- path(source_folder, "aava_unalaska_stalbot_2010_allenv_modrc.xlsx")
veg_cover_input <- path(source_folder, "aava_unalaska_stalbot_2010_spp_modsrc.xlsx")
template_input <- path(template_folder, "02_site.xlsx")

# Define output datasets
site_output <- path(plot_folder, "02_site_fwsunalaska2007.csv")

# Define functions ----
# Import database connection function
plotting_script <- path(
  repository_folder,
  "02_data_format", "utils", "plot_site_coordinates.R"
)
source(plotting_script)

# Define mini function to remove special characters from string of degree minute seconds coordinates
remove_dms_chars <- function(x) {
  x <- str_remove(x, "^[A-Z]")
  x <- str_remove(x, "°")
  x <- str_remove(x, "'")
  x <- str_remove(x, "\"")
}

# Read in data ----
site_original <- read_xlsx(site_input, skip = 7)
veg_cover_original <- read_xlsx(veg_cover_input, skip = 7)
template <- colnames(read_xlsx(path = template_input))

# Explore data ----

# Ensure that each site code is unique
length(unique(site_original$`FIELD RELEVE NUMBER (PROVIDED BY AUTHOR)`)) == nrow(site_original)
length(unique(site_original$`PUBLISHED RELEVE NUMBER`)) == nrow(site_original)

# Are any sites missing coordinates?
site_original %>%
  filter(is.na(`LATITUDE (DMS, WGS 84)`) | is.na(`LONGITUDE (DMS, WGS 84)`))

# Ensure all sites have vegetation data
# Visual check to confirm that there are 70 site columns in the veg cover spreadsheet

# Ensure prefixes for site codes are consistent
site_original %>%
  mutate(site_prefix = str_split_i(`FIELD RELEVE NUMBER (PROVIDED BY AUTHOR)`, "0", 1)) %>%
  distinct(site_prefix)

# Format site codes ----
# Add FWS as a prefix in case there are sites from other projects that start with 'DUT' or 'AKK'
site_data <- site_original %>%
  mutate(site_code = str_c("FWS", `FIELD RELEVE NUMBER (PROVIDED BY AUTHOR)`, sep = "_"))

# Re-project coordinates ----

# Convert coordinates from degrees minutes seconds to decimal degrees
# Solution adapted from user C8H10N4O2 on StackExchange: https://stackoverflow.com/questions/30879429/how-can-i-convert-degree-minute-sec-to-decimal-in-r

site_data <- site_data %>%
  rename(
    coords_lat = `LATITUDE (DMS, WGS 84)`,
    coords_lon = `LONGITUDE (DMS, WGS 84)`
  ) %>% # Can use mutate rather than rename to check output
  mutate(across(starts_with("coords"), remove_dms_chars)) %>%
  separate_wider_delim(
    cols = c(coords_lat, coords_lon),
    delim = " ", names = c("d", "m", "s"), names_sep = "_"
  ) %>%
  mutate(across(starts_with("coords"), as.numeric)) %>%
  mutate(
    lat_dd84 = coords_lat_d + coords_lat_m / 60 + coords_lat_s / 60^2,
    long_dd84 = -1 * (coords_lon_d + coords_lon_m / 60 + coords_lon_s / 60^2)
  ) %>% # Add negative sign to longitude for Western Hemisphere
  select(-starts_with("coords"))

# Coordinates for Unalaska: 53.873° N, 166.538° W
summary(site_data$lat_dd84) # Y-axis, positive values
summary(site_data$long_dd84) # X-axis, negative values

# Convert to sf object
# Datum is WGS 84
site_sf <- st_as_sf(site_data,
  coords = c("long_dd84", "lat_dd84"),
  crs = 4326
)

# Re-project to NAD 83 (EPSG 4269)
site_sf_project <- st_transform(x = site_sf, crs = 4269)
st_crs(site_sf_project) # Ensure correct EPSG is listed

# Extract coordinates back into df
# Drop old coordinates to avoid confusion
site_data <- site_data %>%
  bind_cols(st_coordinates(site_sf_project)) %>%
  select(-c(long_dd84, lat_dd84))

# Look for spatial outliers ----

plot_display <- "FALSE"

if (plot_display == "TRUE") {
  plot_outliers(site_sf_project, api_key, 12)
}

# Format plot dimensions ----
unique(site_data$`PLOT SIZE`)

site_data <- site_data %>%
  mutate(
    plot_dimensions_m = str_c(str_flatten(str_split(`PLOT SIZE`, " x ")[[1]], collapse = "×")),
    plot_dimensions_m = str_remove(plot_dimensions_m, " m")
  )

# Populate remaining columns ----
site_data_final <- site_data %>%
  mutate(
    establishing_project_code = "fws_unalaska_2007",
    perspective = "ground",
    cover_method = "braun-blanquet visual estimate",
    h_datum = "NAD83",
    longitude_dd = round(X, digits = 5),
    latitude_dd = round(Y, digits = 5),
    h_error_m = -999,
    positional_accuracy = "consumer grade GPS",
    location_type = "targeted"
  ) %>%
  select(all_of(template))

# QA/QC -----

# Do any of the columns have null values that need to be addressed?
cbind(
  lapply(
    lapply(site_data_final, is.na),
    sum
  )
)

# Export as CSV ----
write_csv(site_data_final, site_output)

# Clear workspace ----
rm(list = ls())
