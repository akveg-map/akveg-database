# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Map spatial distribution of sites
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-26
# Usage: Must be executed in a R 4.6.0+ installation.
# Description: "Map spatial distribution of sites" creates a map figure for publication that shows the spatial distribution of sites in AKVEG, inclusive of private data, classified according to cover method.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(ggplot2)
library(RPostgres)
library(readr)
library(sf)
library(stringr)
library(tibble)
library(tidyr)

# Define file paths and directories ----

# Set root directory
drive = 'C:'
root_folder = 'ACCS_Work'

# Define folder structure
project_folder = path(drive, root_folder, 'Projects')
spatial_folder = path(project_folder, 'AKVEG_Map/Data')
output_folder = path(project_folder, 'AKVEG_Database/Manuscript/Figures')
credentials_folder = path(drive, root_folder, "OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database", "Credentials", "akveg_private_read")
repository_folder = path(drive, root_folder, 'Repositories/akveg-database')

# Define input files
ocean_input = path(spatial_folder, 'basemap', 'Basemap_Ocean_3338.shp')
russia_input = path(spatial_folder, 'basemap', 'Russia_Coastline_BeringProjection.shp')
na_input = path(spatial_folder, 'basemap', 'NorthAmerica_NAD83.shp')
river_input = path(spatial_folder, 'basemap', 'NaturalEarth_10m_Rivers_Centerlines.shp')
alaska_input = path(spatial_folder, 'region_data', 'Alaska_MajorLandResourceArea_v2022_3338.shp')
credentials_input = path(credentials_folder, 'authentication_akveg_private_read.csv')
query_input = path(repository_folder, "queries", "02_site.sql")

# Define output files
figure_output = path(output_folder, 'figure_spatial_distribution.jpg')

# Connect to database
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(credentials_input)

# Query site data ----
query_file <- read_file(query_input)
site_data = dbGetQuery(database_connection, query_file)

# Re-classify cover methods
site_data <- site_data |> 
  mutate(cover_method_reclass = case_when(cover_method %in% c("braun-blanquet visual estimate", 
                                                              "custom classification visual estimate") ~ "Cover Class",
                                          cover_method %in% c("line-point intercept", 
                                                              "grid-point intercept") ~ "Point Intercept",
                                          cover_method %in% c("semi-quantitative visual estimate", 
                                                              "subplot transect visual estimate") ~ "Visual Estimate"))
# Create map plot ----

# Read input data
site_data_sf = site_data |> 
  # Convert geometries to points with EPSG:6318 (NAD83 2011)
  st_as_sf(coords = c('longitude_dd', 'latitude_dd'), crs = 6318, remove = FALSE) %>%
  # Reproject coordinates to EPSG 3338
  st_transform(crs = st_crs(3338))
  
# Add EPSG:3338 coordinates
site_data_sf <- cbind(site_data_sf, st_coordinates(site_data_sf))

# Read shapes
ocean_data = st_read(ocean_input)
russia_data = st_read(russia_input) %>% st_transform(., crs = 3338)
na_data = st_read(na_input) %>% st_transform(., crs = 3338)
river_data = st_read(river_input) %>% st_transform(., crs = 3338)
alaska_data = st_read(alaska_input) |> st_union()  # Dissolve into a single polygon

# Define custom fill colors
custom_colors = c(
  'Visual Estimate' = '#0072B2',
  'Point Intercept' = '#E69F00',
  'Cover Class' = '#D81B60'
)

# Define bounding box polygons
## Use both site data and Alaska boundary to ensure entirety of Alaska is shown in the map
bbox_alaska = st_bbox(alaska_data)
bbox_sites  = st_bbox(site_data_sf)

# Extract the absolute minimums and maximums and combine them
x_limits = c(min(bbox_alaska["xmin"], bbox_sites["xmin"]), 
             max(bbox_alaska["xmax"], bbox_sites["xmax"]))

y_limits = c(min(bbox_alaska["ymin"], bbox_sites["ymin"]), 
             max(bbox_alaska["ymax"], bbox_sites["ymax"]))

# Add a buffer to prevent edge points from being cut off
buffer_dist = 50000

x_limits = x_limits + c(-buffer_dist, buffer_dist)
y_limits = y_limits + c(-buffer_dist, buffer_dist)

# Create map of AKVEG plot data
map_plot = ggplot() +
  geom_sf(data = ocean_data, color = NA, fill = '#BEE8FF', alpha = 0.3) +
  geom_sf(data = russia_data, color = 'black', 
          fill = 'lightgray', linewidth = 0.2, alpha = 0.5) +
  geom_sf(data = na_data, color = 'black', 
          fill = 'lightgray', linewidth = 0.2, alpha = 0.5) +
  geom_sf(data = alaska_data, color = 'black', 
          fill = 'white', linewidth = 0) +
  geom_sf(data = river_data, color = '#BFD9F2', linewidth = 1) +
  geom_sf(data = russia_data, color = 'white', 
          fill = NA, linewidth = 1.2) +
  geom_sf(data = russia_data, color = 'black', 
          fill = NA, linewidth = 0.2) +
  geom_sf(data = na_data, color = 'white', 
          fill = NA, linewidth = 1.2) +
  geom_sf(data = na_data, color = 'black', 
          fill = NA, linewidth = 0.2) +
  geom_sf(data = site_data_sf,
          aes(fill = cover_method_reclass),
          color = 'black',
          linewidth = 0.3,
          pch = 21,
          size = 1.8) +
  scale_fill_manual(values = custom_colors) +
  coord_sf(
    crs = st_crs(3338),
    xlim = x_limits,
    ylim = y_limits,
    expand = FALSE
  ) +
  scale_x_continuous(breaks = seq(-180, 180, by = 20))+
  scale_y_continuous(breaks = seq(50,70, by = 5)) +
  theme_minimal() +
  theme(
    axis.title = element_blank(),
    axis.text = element_text(size = 14),
    panel.grid.major = element_line(colour = 'gray'),
    legend.text = element_text(size = 18),
    legend.title = element_blank(),
    legend.position = 'top',
    legend.margin = margin(t = 10),
    plot.title = element_text(size = 20),
    text = element_text(family="sans")
  ) +
  guides(
    fill = guide_legend(direction = "horizontal",
                        override.aes = list(size = 5))
    )

# Obtain summary statistics ----

# Calculate percentage of sites that are in Alaska
sites_in_alaska = lengths(st_intersects(site_data_sf, alaska_data)) > 0
pct_in_alaska = mean(sites_in_alaska) * 100

# Calculate number of sites by survey method
sites_by_method = table(site_data_sf$cover_method)

# Export plot ----
ggsave(figure_output,
       plot = map_plot,
       device = 'jpeg',
       path = NULL,
       scale = 2,
       width = 6.5,
       height = 4,
       units = 'in',
       dpi = 300,
       limitsize = TRUE)
