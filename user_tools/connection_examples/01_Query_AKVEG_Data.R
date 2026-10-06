# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Query data from AKVEG Database
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-06
# Usage: Script should be executed in R 4.6.1+.
# Description: Example script to pull data from the AKVEG Database for all available, non-metadata tables. The script connects to the AKVEG database, executes queries, and performs simple spatial analyses (i.e., subset the data to specific study areas, extract raster values to surveyed plots). The outputs are a series of CSV files (one for each non-metadata table in the database) whose results are restricted to the study area in the script.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr)
library(here)
library(fs)
# library(janitor)
# library(lubridate)
library(readr)
# library(readxl)
library(RPostgres)
library(sf)
library(stringr)
# library(terra)
library(tibble)
# library(tidyr)
library(yaml)

# Source utility functions ----
source(here("user_tools", "utils_init.R"))
source(path("user_tools", "utils_database.R"))
source(path("manuscript", "utils.R"))

# Define directories & files ----
## Modify to your folder structure
## In this example, here() points to the akveg-database GitHub repository, and local file paths are specified in a "paths.yaml" file
local_paths <- load_system_paths("paths.yaml")

# Define input folders
query_folder <- here("user_tools", "queries")
input_folder <- path(local_paths$root, "Example/Data_Input")
output_folder <- path(local_paths$root, "Example/Data_Output")

# Define input files
region_input <- path(input_folder, "AlaskaYukon_Regions_v2.0_3338.shp")
fireyear_input <- path(input_folder, "AlaskaYukon_FireYear_10m_3338.tif")

# Define queries
## Can be modified or expanded to include other queries
taxa_file <- path(query_folder, "00_taxonomy.sql")
project_file <- path(query_folder, "01_project.sql")
site_visit_file <- path(query_folder, "03_site_visit.sql")
vegetation_file <- path(query_folder, "05_vegetation.sql")

# Define output files
taxa_output <- path(output_folder, "00_taxonomy.csv")
project_output <- path(output_folder, "01_project.csv")
site_visit_output <- path(output_folder, "03_site_visit.csv")
site_point_output <- path(output_folder, "03_site_point_3338.shp")
vegetation_output <- path(output_folder, "05_vegetation.csv")

# Read local data ----
region_shape <- st_read(region_input)
fireyear_raster <- rast(fireyear_input)

# Connect to AKVEG PostgreSQL database ----
database_connection <- connect_database_postgresql(local_paths$credentials)

# Get geometry for intersection (example to subset data by Boreal)
# intersect_geometry = st_geometry(region_shape[region_shape$region == 'Alaska-Yukon Southern'
#                                              | region_shape$region == 'Alaska-Yukon Central'
#                                              | region_shape$region == 'Alaska-Yukon Northern'
#                                              | region_shape$region == 'Alaska Western'
#                                              | region_shape$region == 'Alaska Southwest',])

# Get geometry for intersection (example to subset data by Arctic)
intersect_geometry <- st_geometry(region_shape[region_shape$region == "Arctic Northern" |
  region_shape$region == "Arctic Western", ])

#### Query AKVEG database ------------------------------

# Read taxonomy standard from AKVEG Database
taxa_query <- read_file(taxa_file)
taxa_data <- as_tibble(dbGetQuery(database_connection, taxa_query))

# Read site visit data from AKVEG Database
site_visit_query <- read_file(site_visit_file)
site_visit_data <- as_tibble(dbGetQuery(database_connection, site_visit_query)) %>%
  # Convert geometries to points with EPSG:4269
  st_as_sf(x = ., coords = c("longitude_dd", "latitude_dd"), crs = 4269, remove = FALSE) %>%
  # Reproject coordinates to EPSG 3338
  st_transform(crs = st_crs(3338)) %>%
  # Add EPSG:3338 centroid coordinates
  mutate(
    cent_x = st_coordinates(.$geometry)[, 1],
    cent_y = st_coordinates(.$geometry)[, 2]
  ) %>%
  # Subset points to those within the target zone (example to subset using a feature class selection)
  st_intersection(intersect_geometry) %>%
  # Extract raster data to points
  mutate(fire_year = terra::extract(fireyear_raster, ., raw = TRUE)[, 2]) %>%
  # Drop geometry
  st_zm(drop = TRUE, what = "ZM") %>%
  # Example filter by project code (uncomment line below)
  # filter(project_code == 'accs_nelchina_2023') %>%
  # Example filter by observation year (uncomment line below)
  # filter(year(observe_date) >= 2000) %>%
  # Example filter by perspective (uncomment line below)
  # filter(perspective == 'ground') %>%
  # Select columns
  dplyr::select(
    site_visit_code, project_code, site_code, data_tier, observe_date, scope_vascular, scope_bryophyte, scope_lichen,
    perspective, cover_method, structural_class, fire_year, homogeneous, plot_dimensions_m,
    latitude_dd, longitude_dd, cent_x, cent_y, geometry
  )

# Export site visit data to shapefile
site_visit_data %>%
  # Rename fields so that they are within the character length limits
  rename(
    st_vst = site_visit_code,
    prjct_cd = project_code,
    st_code = site_code,
    obs_date = observe_date,
    scp_vasc = scope_vascular,
    scp_bryo = scope_bryophyte,
    scp_lich = scope_lichen,
    perspect = perspective,
    cvr_mthd = cover_method,
    strc_class = structural_class,
    hmgneous = homogeneous,
    plt_dim_m = plot_dimensions_m,
    lat_dd = latitude_dd,
    long_dd = longitude_dd
  ) %>%
  st_write(site_point_output, append = FALSE) # Optional to check point selection in a GIS

# Write where statement for site visits to apply site visit codes obtained in the spatial intersection above to the SQL queries to restrict data from other tables to only those sites that are within the area of interest
input_sql <- site_visit_data %>%
  # Drop geometry
  st_drop_geometry() %>%
  select(site_visit_code) %>%
  # Format site visit codes
  mutate(site_visit_code = paste("'", site_visit_code, "'", sep = "")) %>%
  # Collapse rows
  summarize(site_visit_code = paste(site_visit_code, collapse = ", ")) %>%
  # Pull result out of dataframe
  pull(site_visit_code)
where_statement <- paste("\r\nWHERE site_visit.site_visit_code IN (",
  input_sql,
  ");",
  sep = ""
)

# Read project data from AKVEG Database for selected site visits
project_query <- read_file(project_file) %>%
  # Modify query with where statement
  str_replace(., ";", where_statement)
project_data <- as_tibble(dbGetQuery(database_connection, project_query)) %>%
  arrange(project_code)

# Read vegetation cover data from AKVEG Database for selected site visits
vegetation_query <- read_file(vegetation_file) %>%
  # Modify query with where statement
  str_replace(., ";", where_statement)
vegetation_data <- as_tibble(dbGetQuery(database_connection, vegetation_query))

# Check number of cover observations per project
project_check <- vegetation_data %>%
  left_join(site_visit_data, join_by("site_visit_code")) %>%
  group_by(project_code) %>%
  summarize(obs_n = n())

# Export data to csv files ----
taxa_data %>%
  write_csv(., file = taxa_output)
project_data %>%
  write_csv(., file = project_output)
site_visit_data %>%
  st_drop_geometry() %>%
  write_csv(., file = site_visit_output)
vegetation_data %>%
  write_csv(., file = vegetation_output)
