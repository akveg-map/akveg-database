# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Query data from AKVEG Database
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-13
# Usage: Script should be executed in Python 3.12+. Requires psycopg2.
# Description: This example script shows users how to connect to the AKVEG Database, read and execute queries,
# and perform simple spatial analyses (i.e., subset the data to a specific study area, extract raster values to
# surveyed plots). The outputs are an ESRI shapefile and a series of CSV files whose results are restricted to the
# study area in the script. Download links to the spatial files used in this script can be found in the Getting
# Started section of the AKVEG Docs: https://docs.akveg.org. Database credentials can be requested from:
# https://www.akveg.org
# ---------------------------------------------------------------------------

# --- Import packages ---
# user_tools utility functions are in the AKVEG Database GitHub repo:
# https://github.com/akveg-map/akveg-database/tree/main/user_tools
from pathlib import Path
import pandas as pd
import geopandas as gpd
import rasterio
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql, query_to_dataframe

# --- Define directories and files ---
paths = load_system_paths()

# Define input folders (modify to your folder structure)
database_repository = paths.repository
input_folder = Path(paths.root / 'Example' / 'Data_Input')
output_folder = Path(paths.root / 'Example' / 'Data_Output')

# Define input files
# region_input can be downloaded from: https://doi.org/10.18739/A2NP1WM5K
# fireyear_input can be downloaded from "Getting Started" of the database docs: https://docs.akveg.org
# Database credentials can be requested from: https://www.akveg.org
region_input = Path(input_folder / 'data' / 'AlaskaYukon_USNVC_ZonesRegions_v2p1_3338.gpkg')
fireyear_input = Path(input_folder / 'AlaskaYukon_FireYear_10m_3338.tif')
credentials_file = paths.cloud_assets.credentials

# Define output files
taxa_output = Path(output_folder, '00_taxonomy.csv')
project_output = Path(output_folder, '01_project.csv')
site_visit_output = Path(output_folder, '03_site_visit.csv')
site_point_output = Path(output_folder, '02_site_point_3338.shp')
vegetation_output = Path(output_folder, '05_vegetation.csv')

# Define queries (modify to include other queries)
taxa_file = Path(database_repository / 'user_tools' / 'queries' / '00_taxonomy.sql')
project_file = Path(database_repository / 'user_tools' / 'queries' / '01_project.sql')
site_file = Path(database_repository / 'user_tools' / 'queries' / '02_site.sql')
site_visit_file = Path(database_repository / 'user_tools' / 'queries' / '03_site_visit.sql')
vegetation_file = Path(database_repository / 'user_tools' / 'queries' / '05_vegetation.sql')

# Read spatial data
region_shape = gpd.read_file(region_input)

# --- Query AKVEG Database ---

# Connect to the AKVEG PostgreSQL database
database_connection = connect_database_postgresql(credentials_file)

# Define named keys for query files
query_files = {
    "taxonomy": taxa_file,
    "project": project_file,
    "site": site_file,
    "site_visit": site_visit_file,
    "vegetation": vegetation_file
}

# Execute queries and load into a dictionary
query_dict = {
    key: query_to_dataframe(database_connection, Path(f).read_text())
    for key, f in query_files.items()
}

# Format Site Visit date fields
query_dict["site_visit"]['obs_datetime'] = pd.to_datetime(query_dict["site_visit"]['observe_date'])
query_dict["site_visit"]['obs_year'] = query_dict["site_visit"]['obs_datetime'].dt.year

# Example filter by project code (uncomment line below)
# site_visit_nelchina = query_dict["site_visit"][query_dict["site_visit"]['project_code'] == 'accs_nelchina_2023']

# Example filter by observation year (uncomment line below)
# site_visit_recent = query_dict["site_visit"][query_dict["site_visit"]['obs_year'] >= 2000]

# --- Restrict Site table to Arctic region ---

# Subset region geodataframe to Arctic zone
intersect_arctic = region_shape[region_shape['zone'] == "Arctic"]

# Convert Site table to geodataframe
site_gpd = gpd.GeoDataFrame(
    query_dict["site"],
    geometry=gpd.points_from_xy(query_dict["site"].longitude_dd,
                                query_dict["site"].latitude_dd),
    crs='EPSG:4269')

# Project site geodataframe to EPSG:3338 to match region gdf
site_gpd = site_gpd.to_crs(crs=intersect_arctic.crs)

# Extract coordinates in EPSG:3338
site_gpd['cent_x'] = site_gpd.geometry.x
site_gpd['cent_y'] = site_gpd.geometry.y

# Subset points to those within Arctic region
site_arctic_gpd = gpd.clip(site_gpd, intersect_arctic)

# Example filter by perspective (uncomment line below)
# site_arctic_ground = site_arctic[site_arctic['perspective'] == 'ground']

# Convert coordinates of Arctic sites to list for raster extraction step
coord_list = [(x, y) for x, y in zip(site_arctic_gpd['cent_x'], site_arctic_gpd["cent_y"])]

# Extract raster values to points
with rasterio.open(fireyear_input) as fire:
    # Single-band raster, use [0] to extract the value of the first band
    site_arctic_gpd["fire_year"] = [x[0] for x in fire.sample(coord_list)]

# Drop geometry column and convert to Pandas DataFrame
site_arctic_df = pd.DataFrame(site_arctic_gpd.drop(columns=["geometry"]))

# Rename fields for export as shapefile to meet 10 character length constraint
export_point_data = site_arctic_df.rename(columns={'site_code': 'site_cd',
                                                   'establishing_project_code': 'project_cd',
                                                   'perspective': 'prspective',
                                                   'cover_method': 'cover_mthd',
                                                   'fire_year': 'fire_year',
                                                   'plot_dimensions_m': 'plt_dim_m',
                                                   'h_datum': 'h_datum',
                                                   'latitude_dd': 'lat_dd',
                                                   'longitude_dd': 'long_dd',
                                                   'h_error_m': 'h_error_m',
                                                   'positional_accuracy': 'pos_accur',
                                                   'location_type': 'loc_type'
                                                   })

# Export site data to shapefile
site_point_data = gpd.GeoDataFrame(
    export_point_data,
    geometry=gpd.points_from_xy(site_arctic_gpd.cent_x,
                                site_arctic_gpd.cent_y),
    crs='EPSG:3338')
site_point_data.to_file(site_point_output)

# --- Filter Project & Vegetation tables for selected Arctic sites ---
project_arctic = query_dict["project"][query_dict["project"]["project_code"].isin(site_arctic_df[
                                                                                'establishing_project_code'])]
# For Vegetation table, use site_visit_code in the Site Visit table as a bridge
visit_arctic = query_dict["site_visit"][query_dict["site_visit"]["site_code"].isin(site_arctic_df[
                                                                                'site_code'])]
visit_arctic = visit_arctic[['site_code', "site_visit_code"]]
vegetation_arctic = query_dict["vegetation"][query_dict["vegetation"]["site_visit_code"].isin(visit_arctic[
                                                                                                  'site_visit_code'])]
# Explore number of cover observations per project
project_check = pd.merge(vegetation_arctic,
                         visit_arctic, on='site_visit_code', how='left')[['project_code',
                                                                          'site_visit_code']]
project_check = project_check.groupby(['project_code']).count().rename(columns={'site_visit_code': 'obs_n'})
project_check['project_code'] = project_check.index
project_check = project_check.reset_index(drop=True)[['project_code', 'obs_n']]

# --- Extract taxonomy list for Arctic sites ---
taxa_arctic = query_dict["taxonomy"][query_dict["taxonomy"]["taxon_name"].isin(vegetation_arctic[
                                                                                   "name_adjudicated"].unique())]

# --- Export tables to CSV files ---
taxa_arctic.to_csv(taxa_output, index=False, encoding='utf-8')
project_arctic.to_csv(project_output, index=False, encoding='utf-8')
visit_arctic.to_csv(site_visit_output, index=False, encoding='utf-8')
vegetation_arctic.to_csv(vegetation_output, index=False, encoding='utf-8')

# --- Close database connection ---
database_connection.close()
