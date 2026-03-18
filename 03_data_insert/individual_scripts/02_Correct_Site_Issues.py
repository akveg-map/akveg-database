# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Perform QC checks for Site and Site Visit tables
# Author: Amanda Droghini
# Last Updated: 2026-03-18
# Usage: Execute in Python 3.13+.
# Description: "Perform QC checks for Site and Site Visit tables" identifies and corrects
# data entry errors in the Site and Site Visit tables of the AKVEG Database.
# ---------------------------------------------------------------------------

# Import packages
import os
import numpy as np
import pandas as pd
import geopandas as gpd
import datetime
from shapely.geometry import box

# Set options
pd.set_option("display.max_columns", 10)

# Set root directory
drive = "C:/"
root_folder = (
    "ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"
)

# Define folder structure
data_folder = os.path.join(drive, root_folder, "Data", "Data_Plots", "processed")
spatial_folder = os.path.join(
    drive, "ACCS_Work", "Projects", "AKVEG_Map", "Data", "region_data"
)
issues_folder = os.path.join(data_folder, "quality_check_issues")
corrected_folder = os.path.join(data_folder, "corrected")

# Define input files
boundary_input = os.path.join(spatial_folder, "AlaskaYukon_100_Tiles_3338.shp")
site_file = os.path.join(data_folder, "sites.csv")
visit_file = os.path.join(data_folder, "site_visits.csv")
vegetation_file = os.path.join(data_folder, "vegetation_cover.csv")
abiotic_file = os.path.join(data_folder, "abiotic_top_cover.csv")
tussock_file = os.path.join(data_folder, "whole_tussock_cover.csv")
ground_file = os.path.join(data_folder, "ground_cover.csv")
struct_file = os.path.join(data_folder, "structural_group_cover.csv")
shrub_file = os.path.join(data_folder, "shrub_structure.csv")
envr_file = os.path.join(data_folder, "environment.csv")
soil_file = os.path.join(data_folder, "soil_metrics.csv")
horizons_file = os.path.join(data_folder, "soil_horizons.csv")

# Define export files
date_today = datetime.date.today().strftime("%Y%m%d")
issues_filename = "issues_" + date_today + ".csv"
issues_output = os.path.join(issues_folder, issues_filename)

site_output = os.path.join(corrected_folder, "sites.csv")
visit_output = os.path.join(corrected_folder, "site_visits.csv")
vegetation_output = os.path.join(corrected_folder, "vegetation_cover.csv")
abiotic_output = os.path.join(corrected_folder, "abiotic_top_cover.csv")
ground_output = os.path.join(corrected_folder, "ground_cover.csv")
tussock_output = os.path.join(corrected_folder, "whole_tussock_cover.csv")
struct_output = os.path.join(corrected_folder, "structural_group_cover.csv")
shrub_output = os.path.join(corrected_folder, "shrub_structure.csv")
envr_output = os.path.join(corrected_folder, "environment.csv")
soil_output = os.path.join(corrected_folder, "soil_metrics.csv")
horizons_output = os.path.join(corrected_folder, "soil_horizons.csv")

# Read spatial data
region_boundary = gpd.read_file(boundary_input)

# Read in processed files
site_data = pd.read_csv(site_file)
visit_data = pd.read_csv(visit_file, parse_dates=["observe_date"])
vegetation_data = pd.read_csv(vegetation_file)
abiotic_data = pd.read_csv(abiotic_file)
ground_data = pd.read_csv(ground_file)
tussock_data = pd.read_csv(tussock_file)
struct_data = pd.read_csv(struct_file)
shrub_data = pd.read_csv(shrub_file)
envr_data = pd.read_csv(envr_file)
soil_data = pd.read_csv(soil_file)
horizons_data = pd.read_csv(horizons_file)

# Link site visit code to project code
visit_simple = visit_data.filter(items=["site_code", "site_visit_code"])
site_simple = site_data.filter(items=["site_code", "establishing_project_code"])
lookup_table = pd.merge(
    site_simple, visit_simple, how="left", left_on="site_code", right_on="site_code"
)

print(
    lookup_table.site_visit_code.isna().sum()
)  # n = 124. Should be zero; this issue is addressed later in
# script

# QC Abiotic Top Cover
# Check for null values
print(abiotic_data.isna().sum())

# Check for duplicate abiotic elements (each abiotic element should only occur 1x per site visit)
duplicate_check = (
    abiotic_data.groupby(["site_visit_code", "abiotic_element_code"])
    .size()
    .reset_index(name="count")
)
duplicate_check = duplicate_check.loc[(duplicate_check["count"] > 1)]
print(
    duplicate_check.shape[0]
)  # No issues

# Drop sites with duplicates
# Does not drop any sites if there are no duplicate issues
corrected_abiotic = abiotic_data[
    ~abiotic_data["site_visit_code"].isin(duplicate_check["site_visit_code"])
]

# QC Vegetation Cover

# Check for null values
print(vegetation_data.isna().sum())

# Ensure that sites that have been dropped from the abiotic top cover table have entries in the vegetation
# cover table. Otherwise, these sites will need to be dropped from the Site and Site Visit tables.
temp = duplicate_check["site_visit_code"].isin(vegetation_data["site_visit_code"])
print(
    temp.value_counts()
)  # Should all be true; sites dropped from abiotic cover table can be kept in the Site and
# Site Visit table (no rows if no issues)

# QC Site table

# Check for null values
print(site_data.isna().sum())

## Ensure that all plot points are in Alaska or northwestern Canada
## Obtain rough bounding box for study area
bbox = box(*region_boundary.to_crs("EPSG:4269").total_bounds)
print(bbox.bounds)

## Explore descriptive statistics for lat/long
coordinates = pd.DataFrame()
coordinates = coordinates.assign(
    latitude_dd=site_data.latitude_dd.astype(float),
    longitude_dd=site_data.longitude_dd.astype(float),
)
print(coordinates.describe())

## Create geodataframe
site_spatial = gpd.GeoDataFrame(
    site_data,
    geometry=gpd.points_from_xy(site_data.longitude_dd, site_data.latitude_dd),
    crs="EPSG:4269",
)

## Convert site data to EPSG:3338
site_spatial = site_spatial.to_crs(crs="EPSG:3338")
print(region_boundary.crs)  # Ensure projection is also EPSG 3338

## List points that intersect with the area of interest
sites_inside = region_boundary.sindex.query(
    geometry=site_spatial.geometry, predicate="intersects"
)[0]

## Investigate points that are outside study area
sites_outside = site_spatial.loc[~site_spatial.index.isin(sites_inside)]
print(
    sites_outside.filter(items={"site_code", "latitude_dd", "longitude_dd"})
)  # n = 3,084. Two sites from breen_poplar_2006, the remaining are from the Govt. of Yukon dataset. All
# points
# are OK to
# retain (sites in
# Canada)

del bbox, region_boundary, sites_inside, sites_outside

# QC Site Visit

# Check for null values
print(visit_data.isna().sum())

## Explore dates
print(visit_data.observe_date.describe())  # Dates range from 1975 to 2024

## Ensure that month range is reasonable i.e., between May and October
errors_winter = visit_data.assign(month=visit_data["observe_date"].dt.month)
errors_winter = errors_winter.loc[
    (errors_winter.month > 10) | (errors_winter.month < 5)
]

print(errors_winter.shape[0])  # No sites to address
del errors_winter

# QC Sites not in Site Visit Table
## Reverse does not need to be checked: 'site code' in Site Visit table references Site table
errors_sites_empty = site_data[~site_data["site_code"].isin(visit_data["site_code"])]
print(errors_sites_empty.establishing_project_code.value_counts())  # n = 124

# QC Site Visit codes not in Cover Tables
visit_array = visit_data.site_visit_code.to_numpy()

## Generate all site visit codes included in Vegetation Cover and Abiotic Top Cover tables
vegetation_unique = vegetation_data.site_visit_code.unique()
abiotic_unique = abiotic_data.site_visit_code.unique()
cover_site_visits = np.concatenate((vegetation_unique, abiotic_unique))
cover_site_visits = np.unique(cover_site_visits)  # Drop duplicates

# Determine which sites are missing from the cover tables (n=187)
## Includes sites from yukon_biophysical_2020 and fws_pribilof_2022 that should not be dropped; addressed later
errors_cover = np.setdiff1d(visit_array, cover_site_visits, assume_unique=True)

# Create list of sites to be dropped

## Format tables that use site codes
## These sites won't have a site visit code
## Sites with erroneous coordinates would go here
errors_sites_empty = errors_sites_empty.filter(items={"site_code"})
errors_sites_empty = errors_sites_empty.assign(issue="not in site visit table")

errors_sites_empty = pd.merge(
    errors_sites_empty, lookup_table, how="left", on="site_code"
)

## Format tables based on site visit codes
## Sites with erroneous dates would go here
errors_cover = pd.DataFrame(errors_cover, columns=["site_visit_code"])
errors_cover = errors_cover.assign(issue="no cover data")

errors_cover = pd.merge(errors_cover, lookup_table, how="left", on="site_visit_code")

## Combine error sites into a single dataframe
errors_all = pd.concat([errors_sites_empty, errors_cover])
## Exclude 18 yukon_biophysical_2020 sites and 10 fws_pribilof_2022 sites. Sites should not be dropped - abiotic cover
# only, but abiotic table has not yet been processed
errors_all = errors_all.loc[~errors_all['establishing_project_code'].isin(['yukon_biophysical_2020',
                                                                           'fws_pribilof_2022'])]
print(
    errors_all.isna().sum()
)  # Sites that are missing site visit codes are sites that do not exist in the Site
# Visit table and that only need to be dropped from Table 2
print(errors_all.establishing_project_code.value_counts())

## Format errors dataframe for export
errors_all = errors_all.loc[
    :, ["establishing_project_code", "site_code", "site_visit_code", "issue"]
]
errors_all = errors_all.sort_values(by=["establishing_project_code"])

# Drop errors from Site Visit table
corrected_visit = visit_data[
    ~visit_data["site_visit_code"].isin(errors_all["site_visit_code"])
]  # Use site visit
# code not to drop sites that have repeated visits

# Drop errors from Site table
corrected_sites = site_data[
    site_data["site_code"].isin(corrected_visit["site_code"])
]  # Also drops sites that only
# exist in Table 2

# Ensure total number of sites are the same
print(
    corrected_sites["site_code"].unique().shape[0]
    == corrected_visit["site_code"].unique().shape[0]
)

# Remove dropped sites from all other tables
corrected_vegetation = vegetation_data[
    vegetation_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_abiotic = corrected_abiotic[
    corrected_abiotic["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_tussock = tussock_data[
    tussock_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_ground = ground_data[
    ground_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_struct = struct_data[
    struct_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_shrub = shrub_data[
    shrub_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_envr = envr_data[
    envr_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_soil = soil_data[
    soil_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]
corrected_horizons = horizons_data[
    horizons_data["site_visit_code"].isin(corrected_visit["site_visit_code"])
]

# Export corrected tables
corrected_sites.to_csv(site_output, index=False)
corrected_visit.to_csv(visit_output, index=False)
corrected_vegetation.to_csv(vegetation_output, index=False)
corrected_abiotic.to_csv(abiotic_output, index=False)
corrected_tussock.to_csv(tussock_output, index=False)
corrected_ground.to_csv(ground_output, index=False)
corrected_struct.to_csv(struct_output, index=False)
corrected_shrub.to_csv(shrub_output, index=False)
corrected_envr.to_csv(envr_output, index=False)
corrected_soil.to_csv(soil_output, index=False)
corrected_horizons.to_csv(horizons_output, index=False)
errors_all.to_csv(
    issues_output, index=False, na_rep="NA"
)  # To have record of sites that were dropped
