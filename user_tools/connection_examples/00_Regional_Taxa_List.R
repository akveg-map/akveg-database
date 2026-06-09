# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Query regional taxa list from AKVEG Database
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-05-19
# Usage: Script should be executed in R 4.4.3+.
# Description: "Query regional taxa list from AKVEG Database" is an example script to generate a list of known taxa from previous survey efforts from a user-specified feature polygon.
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
library(writexl)

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
region_input = path(input_folder, 'region_data/AlaskaYukon_Regions_v2.0_3338.shp')

# Define output files
taxa_output = path(output_folder, 'westernak_species_list.xlsx')

# Define queries
taxa_file = path(database_repository, 'queries/00_taxonomy.sql')
project_file = path(database_repository, 'queries/01_project.sql')
site_visit_file = path(database_repository, 'queries/03_site_visit.sql')
vegetation_file = path(database_repository, 'queries/05_vegetation.sql')

# Read local data ----
region_shape = st_read(region_input)

# Get geometry for intersection (example to subset data by Arctic)
intersect_geometry = st_geometry(region_shape[region_shape$region == 'Alaska Western'
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
  # Subset points to those within the target zone (example to subset using a feature class selection)
  st_intersection(intersect_geometry) %>%
  # Drop geometry
  st_zm(drop = TRUE, what = "ZM") %>%
  # Select columns
  dplyr::select(site_visit_code, project_code, site_code, data_tier, observe_date, scope_vascular, scope_bryophyte, scope_lichen,
                perspective, cover_method, structural_class, homogeneous, plot_dimensions_m,
                latitude_dd, longitude_dd, cent_x, cent_y, geometry)

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

# Check number of cover observations per project
project_check = vegetation_data %>%
  left_join(site_visit_data, join_by('site_visit_code')) %>%
  group_by(project_code) %>%
  summarize(obs_n = n())

# Create regional taxa table
site_number = nrow(site_visit_data)
code_dictionary = taxa_data %>%
  select(code_akveg, taxon_name)
regional_taxa = vegetation_data %>%
  filter(dead_status == FALSE) %>%
  group_by(name_accepted) %>%
  summarize(site_n = n(),
            prevalence = round((n()/site_number) * 100, 1),
            mean_cover_pct = round(mean(cover_percent), 1)) %>%
  left_join(taxa_data, by = join_by('name_accepted' == 'taxon_accepted')) %>%
  filter(taxon_level != 'genus' &
           taxon_level != 'unknown' &
           taxon_level != 'functional group') %>%
  rename(taxon_accepted = name_accepted) %>%
  distinct(taxon_accepted, taxon_genus, taxon_family, taxon_level, taxon_category,
           taxon_habit, site_n, prevalence, mean_cover_pct) %>%
  mutate(species_accepted = case_when(grepl('ssp.', taxon_accepted) ~ str_replace(taxon_accepted, " ssp..*", ""),
                                      grepl('var.', taxon_accepted) ~ str_replace(taxon_accepted, ' var..*', ''),
                                      TRUE ~ taxon_accepted)) %>%
  left_join(code_dictionary, by = join_by('taxon_accepted' == 'taxon_name')) %>%
  select(code_akveg, taxon_accepted, species_accepted, taxon_genus, taxon_family, taxon_level, taxon_category,
         taxon_habit, site_n, prevalence, mean_cover_pct) %>%
  arrange(desc(prevalence), desc(mean_cover_pct))

# Write data to excel
write_xlsx(regional_taxa,
           path = taxa_output,
           col_names=TRUE,
           format_headers = FALSE)