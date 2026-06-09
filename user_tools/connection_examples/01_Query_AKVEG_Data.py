# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Query data from AKVEG Database
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-05-06
# Usage: Script should be executed in Python 3.12+. Requires psycopg2.
# Description: "Compile data views" provides an example of compiling a set of data views for a user-specified region from the AKVEG Database.
# ---------------------------------------------------------------------------

# Import packages
import os
import pandas as pd
import geopandas as gpd
from akutils import connect_database_postgresql  # Optional (see below)
from akutils import query_to_dataframe  # Optional (see below)

# IF NOT USING AKUTILS, UNCOMMENT LINES BELOW (FOR IDE THAT AUTO-RECOGNIZES INIT FILE)
# from pull_functions import connect_database_postgresql
# from pull_functions import query_to_dataframe

#### SET UP DIRECTORIES AND FILES
####------------------------------

# Set root directory (modify to your folder structure)
drive = 'C:/'
root_folder = 'ACCS_Work'

# Define input folders (modify to your folder structure)
database_repository = os.path.join(drive, root_folder, 'Repositories/akveg-database')
credentials_folder = os.path.join(drive, root_folder, 'Example/Credentials/akveg_public_read')
input_folder = os.path.join(drive, root_folder, 'Example/Data_Input')
output_folder = os.path.join(input_folder, 'plot_data')

# Define input files
domain_input = os.path.join(input_folder, 'region_data/AlaskaYukon_ProjectDomain_v2.0_3338.shp')
region_input = os.path.join(input_folder, 'region_data/AlaskaYukon_Regions_v2.0_3338.shp')
fireyear_input = os.path.join(input_folder, 'ancillary_data/AlaskaYukon_FireYear_10m_3338.tif')

# Define output files
taxa_output = os.path.join(output_folder, '00_taxonomy.csv')
project_output = os.path.join(output_folder, '01_project.csv')
site_visit_output = os.path.join(output_folder, '03_site_visit.csv')
site_point_output = os.path.join(output_folder, '03_site_point_3338.shp')
vegetation_output = os.path.join(output_folder, '05_vegetation.csv')
abiotic_output = os.path.join(output_folder, '06_abiotic_top_cover.csv')
tussock_output = os.path.join(output_folder, '07_whole_tussock_cover.csv')
ground_output = os.path.join(output_folder, '08_ground_cover.csv')
structural_output = os.path.join(output_folder, '09_structural_group_cover.csv')
shrub_output = os.path.join(output_folder, '11_shrub_structure.csv')
environment_output = os.path.join(output_folder, '12_environment.csv')
soilmetrics_output = os.path.join(output_folder, '13_soil_metrics.csv')
soilhorizons_output = os.path.join(output_folder, '14_soil_horizons.csv')

# Define queries
taxa_file = os.path.join(database_repository, 'queries/00_taxonomy.sql')
project_file = os.path.join(database_repository, 'queries/01_project.sql')
site_visit_file = os.path.join(database_repository, 'queries/03_site_visit.sql')
vegetation_file = os.path.join(database_repository, 'queries/05_vegetation.sql')
abiotic_file = os.path.join(database_repository, 'queries/06_abiotic_top_cover.sql')
tussock_file = os.path.join(database_repository, 'queries/07_whole_tussock_cover.sql')
ground_file = os.path.join(database_repository, 'queries/08_ground_cover.sql')
structural_file = os.path.join(database_repository, 'queries/09_structural_group_cover.sql')
shrub_file = os.path.join(database_repository, 'queries/11_shrub_structure.sql')
environment_file = os.path.join(database_repository, 'queries/12_environment.sql')
soilmetrics_file = os.path.join(database_repository, 'queries/13_soil_metrics.sql')
soilhorizons_file = os.path.join(database_repository, 'queries/14_soil_horizons.sql')

# Read local data
domain_shape = gpd.read_file(domain_input)
region_shape = gpd.read_file(region_input)

# Get geometry for intersection (example to subset data by Boreal)
#intersect_geometry = region_shape[region_shape['region'].isin(
#    ['Alaska-Yukon Southern',
#     'Alaska-Yukon Central',
#     'Alaska-Yukon Northern',
#     'Alaska Western',
#     'Alaska Southwest']
#)]

# Get geometry for intersection (example to subset data by Arctic)
intersect_geometry = region_shape[region_shape['region'].isin(
    ['Arctic Northern',
     'Arctic Western']
)]

#### QUERY AKVEG DATABASE
####------------------------------

# Create a connection to the AKVEG PostgreSQL database
authentication_file = os.path.join(credentials_folder, 'authentication_akveg_public_read.csv')
database_connection = connect_database_postgresql(authentication_file)

# Read taxonomy standard from AKVEG Database
taxa_read = open(taxa_file, 'r')
taxa_query = taxa_read.read()
taxa_read.close()
taxa_data = query_to_dataframe(database_connection, taxa_query)

# Read site visit data from AKVEG Database
site_visit_read = open(site_visit_file, 'r')
site_visit_query = site_visit_read.read()
site_visit_read.close()
site_visit_data = query_to_dataframe(database_connection, site_visit_query)
site_visit_data['obs_datetime'] = pd.to_datetime(site_visit_data['observe_date'])
site_visit_data['obs_year'] = site_visit_data['obs_datetime'].dt.year

# Create geodataframe
site_visit_data = gpd.GeoDataFrame(
    site_visit_data,
    geometry=gpd.points_from_xy(site_visit_data.longitude_dd,
                                site_visit_data.latitude_dd),
    crs='EPSG:4269')

# Convert geodataframe to EPSG:3338
site_visit_data = site_visit_data.to_crs(crs='EPSG:3338')

# Extract coordinates in EPSG:3338
site_visit_data['cent_x'] = site_visit_data.geometry.x
site_visit_data['cent_y'] = site_visit_data.geometry.y

# Subset points to map domain (example to subset using a feature class)
site_visit_data = gpd.clip(site_visit_data, domain_shape)

# Subset points to those within the target zone (example to subset using a feature class selection)
site_visit_data = gpd.clip(site_visit_data, intersect_geometry)

# Example filter by project code (uncomment line below)
# site_visit_data = site_visit_data[site_visit_data['project_code'] == 'accs_nelchina_2023']

# Example filter by observation year (uncomment line below)
# site_visit_data = site_visit_data[site_visit_data['obs_year'] >= 2000]

# Example filter by perspective (uncomment line below)
# site_visit_data = site_visit_data[site_visit_data['perspective'] == 'ground']

# Select columns
site_visit_data = site_visit_data[['site_visit_code', 'project_code', 'site_code', 'data_tier',
                                   'observe_date', 'scope_vascular', 'scope_bryophyte', 'scope_lichen',
                                   'perspective', 'cover_method', 'structural_class', 'homogeneous',
                                   'plot_dimensions_m', 'latitude_dd', 'longitude_dd',
                                   'cent_x', 'cent_y']]

# Rename fields for export as shapefile to meet shapefile field character length constraint
export_point_data = site_visit_data.rename(columns={'site_visit_code': 'st_vst',
                                                    'project_code': 'prjct_cd',
                                                    'site_code': 'st_code',
                                                    'observe_date': 'obs_date',
                                                    'scope_vascular': 'scp_vasc',
                                                    'scope_bryophyte': 'scp_bryo',
                                                    'scope_lichen': 'scp_lich',
                                                    'perspective': 'perspect',
                                                    'cover_method': 'cvr_mthd',
                                                    'structural_class': 'strc_class',
                                                    'homogeneous': 'hmgneous',
                                                    'plot_dimensions_m': 'plt_dim_m',
                                                    'latitude_dd': 'lat_dd',
                                                    'longitude_dd': 'long_dd'
                                                    })

# Export site visit data to shapefile
site_point_data = gpd.GeoDataFrame(
    export_point_data,
    geometry=gpd.points_from_xy(site_visit_data.cent_x,
                                site_visit_data.cent_y),
    crs='EPSG:3338')
site_point_data.to_file(site_point_output)  # Optional to check point selection in a GIS

# Write where statement for site visits
input_sql = '\r\nWHERE site_visit.site_visit_code IN ('
for site_visit in site_visit_data['site_visit_code']:
    input_sql = input_sql + r"'" + site_visit + r"', "
input_sql = input_sql[:-2] + r');'

# Read project data from AKVEG Database for selected site visits
project_read = open(project_file, 'r')
project_query = project_read.read()
project_read.close()
project_query = project_query.replace(';', input_sql)
project_data = query_to_dataframe(database_connection, project_query).sort_values('project_code')

# Read vegetation cover data from AKVEG Database for selected site visits
vegetation_read = open(vegetation_file, 'r')
vegetation_query = vegetation_read.read()
vegetation_read.close()
vegetation_query = vegetation_query.replace(';', input_sql)
vegetation_data = query_to_dataframe(database_connection, vegetation_query)

# Read abiotic top cover data from AKVEG Database for selected site visits
abiotic_read = open(abiotic_file, 'r')
abiotic_query = abiotic_read.read()
abiotic_read.close()
abiotic_query = abiotic_query.replace(';', input_sql)
abiotic_data = query_to_dataframe(database_connection, abiotic_query)

# Read whole tussock cover data from AKVEG Database for selected site visits
tussock_read = open(tussock_file, 'r')
tussock_query = tussock_read.read()
tussock_read.close()
tussock_query = tussock_query.replace(';', input_sql)
tussock_data = query_to_dataframe(database_connection, tussock_query)

# Read ground cover data from AKVEG Database for selected site visits
ground_read = open(ground_file, 'r')
ground_query = ground_read.read()
ground_read.close()
ground_query = ground_query.replace(';', input_sql)
ground_data = query_to_dataframe(database_connection, ground_query)

# Read structural group cover data from AKVEG Database for selected site visits
structural_read = open(structural_file, 'r')
structural_query = structural_read.read()
structural_read.close()
structural_query = structural_query.replace(';', input_sql)
structural_data = query_to_dataframe(database_connection, structural_query)

# Read shrub structure data from AKVEG Database for selected site visits
shrub_read = open(shrub_file, 'r')
shrub_query = shrub_read.read()
shrub_read.close()
shrub_query = shrub_query.replace(';', input_sql)
shrub_data = query_to_dataframe(database_connection, shrub_query)

# Read environment data from AKVEG Database for selected site visits
environment_read = open(environment_file, 'r')
environment_query = environment_read.read()
environment_read.close()
environment_query = environment_query.replace(';', input_sql)
environment_data = query_to_dataframe(database_connection, environment_query)

# Read soil metrics data from AKVEG Database for selected site visits
soilmetrics_read = open(soilmetrics_file, 'r')
soilmetrics_query = soilmetrics_read.read()
soilmetrics_read.close()
soilmetrics_query = soilmetrics_query.replace(';', input_sql)
soilmetrics_data = query_to_dataframe(database_connection, soilmetrics_query)

# Read soil horizons data from AKVEG Database for selected site visits
soilhorizons_read = open(soilhorizons_file, 'r')
soilhorizons_query = soilhorizons_read.read()
soilhorizons_read.close()
soilhorizons_query = soilhorizons_query.replace(';', input_sql)
soilhorizons_data = query_to_dataframe(database_connection, soilhorizons_query)

# Check number of cover observations per project
project_check = pd.merge(vegetation_data, site_visit_data, on='site_visit_code', how='left')[['project_code',
                                                                                              'site_visit_code']]
project_check = project_check.groupby(['project_code']).count().rename(columns={'site_visit_code': 'obs_n'})
project_check['project_code'] = project_check.index
project_check = project_check.reset_index(drop=True)[['project_code', 'obs_n']]

# Export data to csv files
taxa_data.to_csv(taxa_output, index=False, encoding='utf-8')
project_data.to_csv(project_output, index=False, encoding='utf-8')
site_visit_data.to_csv(site_visit_output, index=False, encoding='utf-8')
vegetation_data.to_csv(vegetation_output, index=False, encoding='utf-8')
abiotic_data.to_csv(abiotic_output, index=False, encoding='utf-8')
tussock_data.to_csv(tussock_output, index=False, encoding='utf-8')
ground_data.to_csv(ground_output, index=False, encoding='utf-8')
structural_data.to_csv(structural_output, index=False, encoding='utf-8')
shrub_data.to_csv(shrub_output, index=False, encoding='utf-8')
environment_data.to_csv(environment_output, index=False, encoding='utf-8')
soilmetrics_data.to_csv(soilmetrics_output, index=False, encoding='utf-8')
soilhorizons_data.to_csv(soilhorizons_output, index=False, encoding='utf-8')
