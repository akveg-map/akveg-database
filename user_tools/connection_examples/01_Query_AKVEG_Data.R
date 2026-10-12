# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Query data from AKVEG Database
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-12
# Usage: Script should be executed in R 4.6.1+.
# Description: Example script to pull data from the AKVEG Database for all available, non-metadata tables. The script connects to the AKVEG database, executes queries, and performs simple spatial analyses (i.e., subset the data to specific study areas, extract raster values to surveyed plots). The outputs are a series of CSV files (one for each non-metadata table in the database) whose results are restricted to the study area in the script.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr)
library(here)
library(fs)
library(lubridate)
library(readr)
library(RPostgres)
library(sf)
library(stringr)
library(terra)
library(tibble)
library(yaml)

# Source utility functions ----
source(here("user_tools", "utils_init.R"))
source(path("user_tools", "utils_database.R"))

# Define directories & files ----
## Modify to your folder structure
## In this example, here() points to the akveg-database GitHub repository, and local file paths are specified in a "paths.yaml" file
local_paths <- load_system_paths("paths.yaml")

# Define input folders
query_folder <- here("user_tools", "queries")
input_folder <- path(local_paths$root, "Example/Data_Input")
output_folder <- path(local_paths$root, "Example/Data_Output")

# Define input files
region_input <- path(input_folder, "data", "AlaskaYukon_USNVC_ZonesRegions_v2p1_3338.gpkg")
fireyear_input <- path(input_folder, "AlaskaYukon_FireYear_10m_3338.tif")

# Define queries
## Can be modified or expanded to include other queries
taxa_file <- path(query_folder, "00_taxonomy.sql")
project_file <- path(query_folder, "01_project.sql")
site_file <- path(query_folder, "02_site.sql")
site_visit_file <- path(query_folder, "03_site_visit.sql")
vegetation_file <- path(query_folder, "05_vegetation.sql")

# Define output files
taxa_output <- path(output_folder, "00_taxonomy.csv")
project_output <- path(output_folder, "01_project.csv")
site_point_output <- path(output_folder, "02_site_point_3338.shp")
vegetation_output <- path(output_folder, "05_vegetation.csv")

# Read local data ----
region_shape <- st_read(region_input)
fireyear_raster <- rast(fireyear_input)

# Connect to AKVEG PostgreSQL database ----
database_connection <- connect_database_postgresql(local_paths$credentials)

# Read queries
site_query <- read_file(site_file)


# Restrict Site table to Arctic zone ----

# Subset region polygon to Arctic zone
intersect_arctic <- st_geometry(region_shape[region_shape$zone == "Arctic", ])

# Read Site table from AKVEG Database
arctic_sites <- as_tibble(dbGetQuery(database_connection, site_query)) %>%
  # Convert geometries to points with EPSG:4269
  st_as_sf(x = ., coords = c("longitude_dd", "latitude_dd"), crs = 4269, remove = FALSE) %>%
  # Re-project coordinates to match CRS of region polygon (EPSG:3338)
  st_transform(crs = st_crs(intersect_arctic)) %>%
  # Add EPSG:3338 centroid coordinates
  mutate(
    cent_x = st_coordinates(.$geometry)[, 1],
    cent_y = st_coordinates(.$geometry)[, 2]
  ) %>%
  # Subset points to those within the Arctic zone
  st_intersection(intersect_arctic) %>%
  # Extract raster data to points
  mutate(fire_year = terra::extract(fireyear_raster, ., raw = TRUE)[, 2]) %>%
  # Drop geometry
  st_zm(drop = TRUE, what = "ZM") %>%
  # Example filter by project code (uncomment line below)
  # filter(project_code == 'aim_kobuknortheast_2021') %>%
  # Example filter by observation year (uncomment line below)
  # filter(year(observe_date) >= 2000) %>%
  # Example filter by perspective (uncomment line below)
  # filter(perspective == 'ground') %>%
  # Select columns
  dplyr::select(
    establishing_project_code, site_code,
    perspective, cover_method, fire_year, plot_dimensions_m, h_error_m, positional_accuracy, location_type,
    latitude_dd, longitude_dd, cent_x, cent_y, geometry
  )

# Export Arctic site data to shapefile
arctic_sites %>%
  # Rename fields so that they are within ESRI's 10-character length limit
  rename(
    site_cd = site_code,
    project_cd = establishing_project_code,
    prspective = perspective,
    cover_mthd = cover_method,
    fire_year = fire_year,
    plt_dim_m = plot_dimensions_m,
    lat_dd = latitude_dd,
    long_dd = longitude_dd,
    h_error_m = h_error_m,
    pos_accur = positional_accuracy,
    loc_type = location_type
  ) %>%
  st_write(site_point_output, append = FALSE)

# Filter other data tables by selected Arctic sites ----

project_query <- read_file(project_file)
arctic_projects <- as_tibble(dbGetQuery(database_connection, project_query)) %>%
  filter(project_code %in% arctic_sites$establishing_project_code) |>
  arrange(project_code)

# For Vegetation table, use site_visit_code in the Site Visit table as a bridge
visit_query <- read_file(site_visit_file)
vegetation_query <- read_file(vegetation_file)

arctic_visits <- as_tibble(dbGetQuery(database_connection, visit_query)) |>
  select(project_code, site_code, site_visit_code) |>
  filter(site_code %in% arctic_sites$site_code)

arctic_vegetation <- as_tibble(dbGetQuery(database_connection, vegetation_query)) |>
  filter(site_visit_code %in% arctic_visits$site_visit_code)

# Summarize number of cover observations per project
obs_by_project <- arctic_vegetation %>%
  left_join(arctic_visits, by = "site_visit_code") %>%
  group_by(project_code) %>%
  summarize(obs_n = n()) |>
  arrange(-obs_n)

# Filter taxonomy by selected Arctic sites ----

# Read taxonomy query
taxa_query <- read_file(taxa_file)

# Execute query and restrict to vegetation identified in Arctic surveys
# Resulting table will only include currently accepted scientific names; filter by name_adjudicated to include synonyms and spelling variants
arctic_taxa <- as_tibble(dbGetQuery(database_connection, taxa_query)) |>
  filter(taxon_name %in% arctic_vegetation$name_accepted)

# Export data to csv files ----
arctic_taxa %>%
  write_csv(., file = taxa_output)
arctic_projects %>%
  write_csv(., file = project_output)
arctic_vegetation %>%
  write_csv(., file = vegetation_output)

# Close database connection ----
dbDisconnect(database_connection)
