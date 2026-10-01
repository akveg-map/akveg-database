# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site Table for BLM AIM 2022-2025 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-01
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: Formats site-level metadata for ingestion into the AKVEG Database and exports the resulting dataframe
# to a CSV file. The script standardizes project and site codes, checks for spatial outliers, formats plot dimension
# values, and aligns data with the AKVEG schema.
# Notes: For plot dimensions, we assumed all plots that used a spoke layout had a plot dimension of 30 m radius (Page
# 24 of Protocols).
# Bureau of Land Management. 2024. AIM National Aquatic Monitoring Framework: Field Protocol for Lentic Riparian and
# Wetland Systems. Tech Reference 1735-3. U.S. Department of the Interior, Bureau of Land Management, National
# Operations Center, Denver, CO.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
from pathlib import Path
from user_tools.utils_init import load_system_paths
from utils.utils import get_template, filter_sites_in_alaska

# Load absolute file paths
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
project_input = plot_folder / "01_project_aimvarious2025.csv"

# Define output
project_output = plot_folder / '02_site_aimvarious2025.csv'

# Get template file
template = get_template("site")

# Read in data
site_original = gpd.read_file(gdb_input, layer="AIM_Wetland__F_PlotCharacterization",
                              columns=["Project", "EvaluationID",
                                       "GPSAccuracy", "SamplingApproach",
                                       "AvgWidthArea", "PlotLayout",
                                       "ActualPlotLength"])
project_original = pl.read_csv(project_input)

# Project coordinates & filter sites that aren't in Alaska
## No changes made since CRS was already 4269
site_filtered = filter_sites_in_alaska(site_original)

# Format site table
site = (
    site_filtered.lazy()
    # Format project code
    .with_columns(
        pl.when(pl.col("Project") == "UnspecifiedBLM")
        .then(pl.lit("AK_CentralYukonFO_2022"))
        .otherwise(pl.col("Project"))
        .alias("Project"))
    .with_columns(pl.col("Project").str.replace_many(["AK", "-"], ["AIM", "_"]))
    .with_columns(pl.col("Project")
                  .str.replace_all(r"([a-z])([A-Z])", r"${1}_${2}", literal=False)
                  .str.to_lowercase()
                  .alias("project_code")
                  )
    # Remove date from EvaluationID
    .with_columns(pl.col("EvaluationID").str.split_exact("_", 1)
                  .struct.rename_fields(["site_code", "observe_date"])
                  .alias("fields")
                  )
    .unnest("fields")
    # Format plot dimensions (see Notes in script header)
    .with_columns(pl.when(pl.col("PlotLayout") == "Spoke")
                  .then(pl.lit("30 radius"))
                  .when((pl.col("PlotLayout") == "Transverse")
                  .then(pl.lit("30×100")) ## Update this to concatenate AvgWidthArea x ActualPlotLength, add to plot
                        # dimensions
                  .otherwise(pl.lit("unknown"))
                  .alias("plot_dimensions_m"))

    # Populate remaining columns
    .with_columns(pl.lit("ground").alias("perspective"),
                  pl.lit("line-point intercept").alias("cover_method"),
                  pl.lit("NAD83").alias("h_datum"),
                  pl.col("SamplingApproach").str.to_lowercase().alias("location_type"),
                  pl.when(pl.col("GPSAccuracy").is_not_null())
                  .then(pl.col("GPSAccuracy").round(decimals=2))
                  .otherwise(-999)
                  .alias("h_error_m"))
    .with_columns(pl.when(pl.col("h_error_m") < 2)
                  .then(pl.lit("mapping grade GPS"))
                  .otherwise(pl.lit("consumer grade GPS"))
                  .alias("positional_accuracy"))
)
             # Match template columns
             .select(template.columns)
             .collect())

# Ensure site code prefixes are consistent
site_filtered = site_filtered.with_columns(pl.col("PlotID")
                                  .str.extract(pattern=r"(^[a-zA-Z]*-[a-zA-z]*)")
                                  .alias("site_prefix"))
print(site['site_prefix'].unique())


# QC
with pl.Config(tbl_cols=12):
   print(site_final.describe())

## Ensure that project codes match with those listed in the Project table
print(site_final["establishing_project_code"].unique().sort().equals(project_original["project_code"].sort()))

## Ensure that all site codes are unique (false indicates all codes are unique)
print(site_final['site_code'].is_duplicated().value_counts())

## Verify values
print(site_final["plot_dimensions_m"].value_counts())  # None with 'unknown'

# Export as CSV
site_final.write_csv(site_output)
