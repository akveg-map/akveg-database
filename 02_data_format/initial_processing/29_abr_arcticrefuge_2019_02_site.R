# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# "Format Site Table for 2019 ABR Arctic Refuge data"
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-04-25
# Usage: Must be executed in R version 4.4.2+.
# Description: "Format Site Table for 2019 ABR Arctic Refuge data" formats site-level information for ingestion into the AKVEG Database. The script excludes irrelevant sites, looks for spatial outliers, standardizes columns to conform to the AKVEG data dictionary, and adds required metadata fields. The output is a CSV table that can be converted and included in a SQL INSERT statement.
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
plot_folder <- path(project_folder, "Data_Plots", "29_abr_arcticrefuge_2019")
template_folder <- path(project_folder, "Data_Entry")
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")

# Define datasets ----

# Define inputs
site_input <- path(plot_folder, "source", "abr_anwr_ns_lc_plot_deliverable.csv")
template_input <- path(template_folder, "02_site.xlsx")

# Define outputs
site_output <- path(plot_folder, "02_site_abrarcticrefuge2019.csv")

# Define functions ----
# Import database connection function
plotting_script <- path(
  repository_folder,
  "02_data_format", "utils", "plot_site_coordinates.R"
)
source(plotting_script)

# Read in data ----
site_original <- read_csv(site_input)
template <- colnames(read_xlsx(path = template_input))

# Exclude irrelevant sites ----
# Keep only "ABR 2019 Aerial Plot" and "ABR 2019 Ground Plot"
# Exclude plots with no cover data or with data issues (anwrlc_4900_2019).
site_data <- site_original %>%
  filter(str_detect(description, "ABR 2019 Aerial Plot|ABR 2019 Ground Plot")) %>%
  filter(!(plot_id %in% c(
    "anwrlc_4900_2019", "anwrlc_2010-30-FP_2019", "anwrlc_2055-02-UP_2019",
    "anwrlc_2501-01-CO_2019", "anwrlc_4286-37-CO_2019", "anwrlc_4288-21-CO_2019"
  )))

# Explore data ----

# Ensure that each site code is unique
length(unique(site_data$plot_id)) == nrow(site_data)

# Are any sites missing coordinates?
site_data %>%
  filter(is.na(latitude) | is.na(longitude))

# Ensure prefixes for site codes are consistent
site_data %>%
  mutate(site_prefix = str_split_i(`plot_id`, "_", 1)) %>%
  distinct(site_prefix)

# Look for spatial outliers ----

# Coordinates for Kaktovik: 70.12°N, 143.63°W
summary(site_data$latitude) # Y-axis, positive values
summary(site_data$longitude) # X-axis, negative values

# Convert to sf object
site_sf <- st_as_sf(site_data,
  coords = c("longitude", "latitude"),
  crs = 4269
)

plot_display <- "FALSE"

if (plot_display == "TRUE") {
  plot_outliers(site_sf, api_key, 7)
} # No spatial outliers detected

# Populate remaining columns ----
site_final <- site_data %>%
  rename(
    latitude_dd = latitude,
    longitude_dd = longitude,
    site_code = plot_id
  ) %>%
  mutate(
    positional_accuracy = case_when(
      loc_origin == "Recreation grade GPS point" ~ "consumer grade GPS",
      grepl("tablet", loc_origin, ignore.case = TRUE) ~ "consumer grade GPS",
      loc_origin == "Geotagged Photo" ~ "image interpretation",
      loc_origin == "Digitized on Imagery" ~ "image interpretation"
    ),
    perspective = if_else(description == "ABR 2019 Aerial Plot", "aerial", "ground"),
    location_type = "random",
    longitude_dd = round(longitude_dd, digits = 5),
    latitude_dd = round(latitude_dd, digits = 5),
    h_error_m = -999,
    h_datum = "NAD83",
    cover_method = "semi-quantitative visual estimate",
    plot_dimensions_m = if_else(description == "ABR 2019 Aerial Plot",
      "unknown",
      "10 radius"
    ),
    establishing_project_code = "abr_arcticrefuge_2019",
    site_code = str_remove(site_code, pattern = "_2019")
  ) %>% # Remove "2019" from site codes; date string will be added to site visit code
  select(all_of(template))

# QA/QC -----

# Do any of the columns have null values that need to be addressed?
cbind(
  lapply(
    lapply(site_final, is.na),
    sum
  )
)

# Export as CSV ----
write_csv(site_final, site_output)

# Clear workspace ----
rm(list = ls())
