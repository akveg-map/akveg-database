# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Query data from AKVEG Database
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-05-06
# Usage: Script should be executed in R 4.4.3+.
# Description: "Query data from AKVEG Database" is an example script to pull data from the AKVEG Database for all available, non-metadata tables. The script connects to the AKVEG database, executes queries, and performs simple spatial analyses (i.e., subset the data to specific study areas, extract raster values to surveyed plots). The outputs are a series of CSV files (one for each non-metadata table in the database) whose results are restricted to the study area in the script.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr)
library(fs)
library(janitor)
library(lubridate)
library(readr)
library(readxl)
library(RPostgres)
library(sf)
library(stringr)
library(terra)
library(tibble)
library(tidyr)

#### Set up directories and files ------------------------------

# Set root directory (modify to your folder structure)
drive = 'C:'
root_folder = 'ACCS_Work'

# Define input folders (modify to your folder structure)
database_repository = path(drive, root_folder, 'Repositories/akveg-database-public')
credentials_folder = path(drive, root_folder, 'Example/Credentials/akveg_public_read')
input_folder = path(drive, root_folder, 'Example/Data_Input')
output_folder = path(drive, root_folder, 'Example/Data_Input', 'plot_data')

# Define input files
domain_input = path(input_folder, 'region_data/AlaskaYukon_ProjectDomain_v2.0_3338.shp')
region_input = path(input_folder, 'region_data/AlaskaYukon_Regions_v2.0_3338.shp')
fireyear_input = path(input_folder, 'ancillary_data/AlaskaYukon_FireYear_10m_3338.tif')

# Define output files
taxa_output = path(output_folder, '00_taxonomy.csv')
project_output = path(output_folder, '01_project.csv')
site_visit_output = path(output_folder, '03_site_visit.csv')
site_point_output = path(output_folder, '03_site_point_3338.shp')
vegetation_output = path(output_folder, '05_vegetation.csv')
abiotic_output = path(output_folder, '06_abiotic_top_cover.csv')
tussock_output = path(output_folder, '07_whole_tussock_cover.csv')
ground_output = path(output_folder, '08_ground_cover.csv')
structural_output = path(output_folder, '09_structural_group_cover.csv')
shrub_output = path(output_folder, '11_shrub_structure.csv')
environment_output = path(output_folder, '12_environment.csv')
soilmetrics_output = path(output_folder, '13_soil_metrics.csv')
soilhorizons_output = path(output_folder, '14_soil_horizons.csv')

# Define queries
taxa_file = path(database_repository, 'queries/00_taxonomy.sql')
project_file = path(database_repository, 'queries/01_project.sql')
site_visit_file = path(database_repository, 'queries/03_site_visit.sql')
vegetation_file = path(database_repository, 'queries/05_vegetation.sql')
abiotic_file = path(database_repository, 'queries/06_abiotic_top_cover.sql')
tussock_file = path(database_repository, 'queries/07_whole_tussock_cover.sql')
ground_file = path(database_repository, 'queries/08_ground_cover.sql')
structural_file = path(database_repository, 'queries/09_structural_group_cover.sql')
shrub_file = path(database_repository, 'queries/11_shrub_structure.sql')
environment_file = path(database_repository, 'queries/12_environment.sql')
soilmetrics_file = path(database_repository, 'queries/13_soil_metrics.sql')
soilhorizons_file = path(database_repository, 'queries/14_soil_horizons.sql')

# Read local data ----
domain_shape = st_read(domain_input)
region_shape = st_read(region_input)
fireyear_raster = rast(fireyear_input)

# Get geometry for intersection (example to subset data by Boreal)
#intersect_geometry = st_geometry(region_shape[region_shape$region == 'Alaska-Yukon Southern'
#                                              | region_shape$region == 'Alaska-Yukon Central'
#                                              | region_shape$region == 'Alaska-Yukon Northern'
#                                              | region_shape$region == 'Alaska Western'
#                                              | region_shape$region == 'Alaska Southwest',])

# Get geometry for intersection (example to subset data by Arctic)
intersect_geometry = st_geometry(region_shape[region_shape$region == 'Arctic Northern'
                                              | region_shape$region == 'Arctic Western',])

#### Query AKVEG database ------------------------------

# Import database connection function
connection_script = path(database_repository, 'pull_functions', 'connect_database_postgresql.R')
source(connection_script)

# Create a connection to the AKVEG PostgreSQL database
authentication = path(credentials_folder, 'authentication_akveg_public_read.csv')
database_connection = connect_database_postgresql(authentication)

# Read taxonomy standard from AKVEG Database
taxa_query = read_file(taxa_file)
taxa_data = as_tibble(dbGetQuery(database_connection, taxa_query))

# Read site visit data from AKVEG Database
site_visit_query = read_file(site_visit_file)
site_visit_data = as_tibble(dbGetQuery(database_connection, site_visit_query)) %>%
  # Convert geometries to points with EPSG:4269
  st_as_sf(x = ., coords = c('longitude_dd', 'latitude_dd'), crs = 4269, remove = FALSE) %>%
  # Reproject coordinates to EPSG 3338
  st_transform(crs = st_crs(3338)) %>%
  # Add EPSG:3338 centroid coordinates
  mutate(cent_x = st_coordinates(.$geometry)[,1],
         cent_y = st_coordinates(.$geometry)[,2]) %>%
  # Subset points to map domain (example to subset using a feature class)
  st_intersection(st_geometry(domain_shape)) %>%
  # Subset points to those within the target zone (example to subset using a feature class selection)
  st_intersection(intersect_geometry) %>%
  # Extract raster data to points
  mutate(fire_year = terra::extract(fireyear_raster, ., raw=TRUE)[,2]) %>%
  # Drop geometry
  st_zm(drop = TRUE, what = "ZM") %>%
  # Example filter by project code (uncomment line below)
  #filter(project_code == 'accs_nelchina_2023') %>%
  # Example filter by observation year (uncomment line below)
  #filter(year(observe_date) >= 2000) %>%
  # Example filter by perspective (uncomment line below)
  #filter(perspective == 'ground') %>%
  # Select columns
  dplyr::select(site_visit_code, project_code, site_code, data_tier, observe_date, scope_vascular, scope_bryophyte, scope_lichen,
                perspective, cover_method, structural_class, fire_year, homogeneous, plot_dimensions_m,
                latitude_dd, longitude_dd, cent_x, cent_y, geometry)

# Export site visit data to shapefile
site_visit_data %>%
  # Rename fields so that they are within the character length limits
  rename(st_vst = site_visit_code,
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
         long_dd = longitude_dd) %>%
  st_write(site_point_output, append = FALSE) # Optional to check point selection in a GIS

# Write where statement for site visits to apply site visit codes obtained in the spatial intersection above to the SQL queries to restrict data from other tables to only those sites that are within the area of interest 
input_sql = site_visit_data %>%
  # Drop geometry
  st_drop_geometry() %>%
  select(site_visit_code) %>%
  # Format site visit codes
  mutate(site_visit_code = paste('\'', site_visit_code, '\'', sep = '')) %>%
  # Collapse rows
  summarize(site_visit_code = paste(site_visit_code, collapse=", ")) %>%
  # Pull result out of dataframe
  pull(site_visit_code)
where_statement = paste('\r\nWHERE site_visit.site_visit_code IN (',
                        input_sql,
                        ');',
                        sep = '')

# Read project data from AKVEG Database for selected site visits
project_query = read_file(project_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
project_data = as_tibble(dbGetQuery(database_connection, project_query)) %>%
  arrange(project_code)

# Read vegetation cover data from AKVEG Database for selected site visits
vegetation_query = read_file(vegetation_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
vegetation_data = as_tibble(dbGetQuery(database_connection, vegetation_query))

# Read abiotic top cover data from AKVEG Database for selected site visits
abiotic_query = read_file(abiotic_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
abiotic_data = as_tibble(dbGetQuery(database_connection, abiotic_query))

# Read whole tussock cover data from AKVEG Database for selected site visits
tussock_query = read_file(tussock_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
tussock_data = as_tibble(dbGetQuery(database_connection, tussock_query))

# Read ground cover data from AKVEG Database for selected site visits
ground_query = read_file(ground_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
ground_data = as_tibble(dbGetQuery(database_connection, ground_query))

# Read structural group cover data from AKVEG Database for selected site visits
structural_query = read_file(structural_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
structural_data = as_tibble(dbGetQuery(database_connection, structural_query))

# Read shrub structure data from AKVEG Database for selected site visits
shrub_query = read_file(shrub_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
shrub_data = as_tibble(dbGetQuery(database_connection, shrub_query))

# Read environment data from AKVEG Database for selected site visits
environment_query = read_file(environment_file) %>%
  # Modify query with where statement
  str_replace(., ';', where_statement)
environment_data = as_tibble(dbGetQuery(database_connection, environment_query))

# Read soil metrics data from AKVEG Database for selected site visits
soilmetrics_query = read_file(soilmetrics_file) %>%
  str_replace(., ';', where_statement)
soilmetrics_data = as_tibble(dbGetQuery(database_connection, soilmetrics_query))

# Read soil horizons data from AKVEG Database for selected site visits
soilhorizons_query = read_file(soilhorizons_file) %>%
  str_replace(., ';', where_statement)
soilhorizons_data = as_tibble(dbGetQuery(database_connection, soilhorizons_query))

# Check number of cover observations per project
project_check = vegetation_data %>%
  left_join(site_visit_data, join_by('site_visit_code')) %>%
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
abiotic_data %>%
  write_csv(., file = abiotic_output)
tussock_data %>%
  write_csv(., file = tussock_output)
ground_data %>%
  write_csv(., file = ground_output)
structural_data %>%
  write_csv(., file = structural_output)
shrub_data %>%
  write_csv(., file = shrub_output)
environment_data %>%
  write_csv(., file = environment_output)
soilmetrics_data %>%
  write_csv(., file = soilmetrics_output)
soilhorizons_data %>%
  write_csv(., file = soilhorizons_output)
