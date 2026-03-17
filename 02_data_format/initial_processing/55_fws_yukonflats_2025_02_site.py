# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site table for USFWS Yukon Flats data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-03-17
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Site table for USFWS Yukon Flats data" extracts site data from an Esri
# shapefile. The script verifies that all plots are in Alaska, re-projects coordinates to NAD83, populates missing
# fields, and drops extraneous columns. The output is a CSV file that can be used for upload to the AKVEG database.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import polars as pl
from pathlib import Path
from utils import get_template, filter_sites_in_alaska

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
project_folder = root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database' / 'Data'
plot_folder = project_folder / 'Data_Plots' / '55_fws_yukonflats_2025'

# Define inputs
site_input = plot_folder / 'source' / 'YKF25_biomass_sites' / 'YKF25_biomass_sites.shp'
template_input = project_folder / 'Data_Entry' / '02_site.xlsx'

# Define output
site_output = plot_folder / '02_site_fwsyukonflats2025.csv'

# Read in data
site_original = gpd.read_file(site_input)  # Can ignore warning
template = get_template("site")

# Ensure that all site codes are unique
print(site_original['plotID'].is_unique)

# Ensure that all sites are in Alaska
site = filter_sites_in_alaska(site_original)

# Populate missing columns
site = (site.with_columns(
    pl.lit('fws_yukonflats_2025').alias('establishing_project_code'),
    pl.lit('ground').alias('perspective'),
    pl.lit('line-point intercept').alias('cover_method'),
    pl.lit('NAD83').alias('h_datum'),
    pl.lit('1.5').cast(pl.Float32).alias('h_error_m'),
    pl.lit('mapping grade GPS').alias('positional_accuracy'),
    pl.lit('12.5 radius').alias('plot_dimensions_m'),
    pl.lit('targeted').alias('location_type')
)
        .rename({"plotID": "site_code"})
        .select(template.columns))

# Export as CSV
site.write_csv(site_output)
