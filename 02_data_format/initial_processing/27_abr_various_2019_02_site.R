# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# "Format Site Table for ABR Various 2019 data"
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2024-10-04
# Usage: Must be executed in R version 4.4.1+.
# Description: "Format Site Table for ABR Various 2019 data" formats site-level information for ingestion into the AKVEG Database. The script standardizes site codes and plot dimensions, projects coordinates to NAD83, and adds required metadata fields. The output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Load packages ----
library(dplyr)
library(fs)
library(ggplot2)
library(readr)
library(readxl)
library(sf)
library(stringr)

# Define directories ----

# Set root directory
drive = 'C:'
root_folder = 'ACCS_Work'

# Define input folders
project_folder = path(drive, root_folder, 'OneDrive - University of Alaska', 'ACCS_Teams', 'Vegetation', 'AKVEG_Database')
plot_folder = path(project_folder, 'Data', 'Data_Plots', '27_abr_various_2019')
source_folder = path(project_folder, 'Data', 'Data_Plots', '27_abr_various_2019', 'source')
template_folder = path(project_folder, 'Data', 'Data_Entry')
repository_folder = path(drive,root_folder,'Repositories', 'akveg-database')

# Define datasets ----

# Define inputs
site_input = path(source_folder, 'deliverable_tnawrocki_plot.xlsx')
site_visit_input = path(source_folder, 'deliverable_tnawrocki_els.xlsx')
project_input = path(plot_folder, 'working', 'xwalk_projectid_akvegcode.csv')
template_input = path(template_folder, "02_site.xlsx")

# Define outputs
site_output = path(plot_folder, '02_site_abrvarious2019.csv')

# Define functions ----
plotting_script = path(repository_folder,
                       '02_data_format', 'utils', 'plot_site_coordinates.R')
source(plotting_script)

# Read in data ----
site_original = read_xlsx(site_input)
site_visit_original = read_xlsx(site_visit_input)
project_original = read_csv(project_input)
template = colnames(read_xlsx(path=template_input))

# Standardize site codes ----
# Drop year suffix 
site = site_original %>% 
  mutate(plot_id = str_remove(plot_id, "_\\d+$|-\\d+$"))
  
# Explore data ----

# Ensure sites are included in both datasets
nrow(site) == nrow(site_visit_original)
which(!(site$plot_id %in% site_visit_original$plot_id))
which(!(site_visit_original$plot_id %in% site$plot_id))

# Join datasets ----
site_join = site_visit_original %>% 
  select(plot_id, plot_dimensions, els_plot_type) %>% 
  left_join(site, by='plot_id') %>%
  left_join(project_original, by='project_id') %>% 
  rename(site_code = plot_id,
         establishing_project_code = project_code)

# Format site code ----
# Capitalize all site codes for consistency
# Convert dashes to underscores
site_join = site_join %>% 
  mutate(site_code = str_to_upper(site_code),
         site_code = str_replace_all(site_code, "-", "_"))

# Ensure prefixes for site codes are consistent
site_join %>% 
  mutate(site_prefix = str_split_i(`site_code`, "_", 1)) %>% 
  distinct(site_prefix) %>% 
  arrange(site_prefix)

# Drop sites with missing coordinates ----
site_join = site_join %>% 
  filter(!(is.na(latitude) | is.na(longitude)))

# Drop sites with errors in the cover data ----
# These are sites that have % cover values > 100% for a single species
error_sites = c("CHBA_T1_400", "CHBA_T1_646", "CHBA_T2_025", "CHBA_T2_155", "CHBA_T2_300", "CHBA_T4_300", "HABA_T1_060", "HABA_T1_300", "HABA_T1_304", "HABA_T1_700", "HABA_T2_1012", "HABA_T2_1388", "HABA_T2_400", "HABA_T2_500", "HABA_T2_833", "HABA_T3_060", "HABA_T3_708", "SISA_T1_138", "SISA_T1_700", "SISA_T1_847", "SISA_T2_417", "SISA_T3_100", "SISA_T4_037", "SISA_T4_171", "SISA_T4_300")

site_join = site_join %>% 
  filter(!(site_code %in% error_sites))

# Re-project coordinates ----
# Most data are in WGS 84
table(site_join$h_datum)

summary(site_join$latitude) # Y-axis, positive values
summary(site_join$longitude) # X-axis, negative values

# Convert WGS 84 plots to sf object
site_wgs84 = site_join %>% 
  filter(h_datum == '4326')

site_sf = st_as_sf(site_wgs84, 
                   coords = c("longitude", "latitude"),
                   crs = 4326)

# Re-project to NAD 83 (EPSG 4269)
site_sf_project = st_transform(x=site_sf, crs=4269)
st_crs(site_sf_project) # Ensure correct EPSG is listed

# Extract coordinates back into df
site_wgs84 = site_wgs84 %>% 
  bind_cols(st_coordinates(site_sf_project))
  
# Re-join with NAD83 sites
site_nad83 = site_join %>% 
  filter(h_datum == '4269') %>% 
  bind_rows(site_wgs84) %>% 
  mutate(latitude_dd = case_when(is.na(Y) ~ latitude,
                                 .default = Y),
         longitude_dd = case_when(is.na(X) ~ longitude,
                                  .default = X)) %>% 
  select(-c(X, Y, longitude, latitude)) %>% 
  mutate(h_datum = 'NAD83')

rm(site_wgs84, site_sf, site_sf_project)

# Look for spatial outliers ----

# Convert to sf object
site_sf = st_as_sf(site_nad83, 
                   coords = c("longitude_dd", "latitude_dd"),
                   crs = 4269)

# Plot points
plot_display = "FALSE"

if (plot_display == "TRUE"){
  plot_outliers(site_sf, api_key, 4)
}

# Format plot dimensions ----
table(site_nad83$plot_dimensions)

# 60 sites without a listed plot dimension (either Not Assessed or No Data)
# For now, for sites with missing plot dimensions, assign them the most common plot size recorded at sites with the same site code prefix

site_nad83$new_dimensions = 'NA'

for (i in 1:nrow(site_nad83)) {
  plot_size = site_nad83$plot_dimensions[i]
  site_name = site_nad83$site_code[i]
  area_name = str_remove(site_name, '_\\d+$')
  if (plot_size == 'No Data'|plot_size=='Not Assessed'|is.na(plot_size)) {
    area_sites = site_nad83 %>% 
      filter(str_starts(site_code, area_name)) %>% 
      filter(plot_dimensions != 'No Data' & 
               plot_dimensions != 'Not Assessed' & 
               !is.na(plot_dimensions))
    new_size = names(which.max(table(area_sites$plot_dimensions)))
  }
  else{
    new_size = plot_size
  }
  site_nad83$new_dimensions[i] = new_size
}

table(site_nad83$plot_dimensions) # Old values
table(site_nad83$new_dimensions) # New values. With the exception of one site, all sites were assigned a plot dimension of 10m radius - I think that makes sense

# Re-classify plot dimensions to match constrained values in AKVEG database
site_nad83 = site_nad83 %>% 
  mutate(plot_dimensions_m = str_remove(new_dimensions, 'm'),
         plot_dimensions_m = str_replace(plot_dimensions_m, 'x', '×'))

unique(site_nad83$plot_dimensions_m)

# Format perspective
unique(site_nad83$els_plot_type)

site_nad83 = site_nad83 %>% 
  mutate(perspective = case_when(els_plot_type == 'Aerial Plot' ~ 'aerial',
                                 .default = 'ground'))

# Populate remaining columns ----
site_final = site_nad83 %>%
  mutate(cover_method = "semi-quantitative visual estimate", # Review
         longitude_dd = round(longitude_dd, digits = 5),
         latitude_dd = round(latitude_dd, digits = 5),
         h_error_m = -999,
         positional_accuracy = case_when(perspective == 'aerial' ~ 'image interpretation',
                                         .default = 'consumer grade GPS'), # Review
         location_type = "targeted") %>%  # Review  
  select(all_of(template))

# QA/QC -----
  
# Do any of the columns have null values that need to be addressed?
cbind(
  lapply(
    lapply(site_final, is.na)
    , sum))

# Export CSV ----
write_csv(site_final, site_output)

# Clear workspace ----
rm(list=ls())
