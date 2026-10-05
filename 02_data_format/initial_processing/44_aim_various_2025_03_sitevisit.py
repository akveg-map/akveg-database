# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site Table for BLM AIM Various 2023 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-10-29
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Site Visit Table for BLM AIM Various 2023 data" formats information about site visits for
# ingestion into the AKVEG Database. The script depends on the output from the 44_aim_various_2023_00_extract_data.py
# script. The script formats dates, creates site visit codes, re-classifies structural class data, and populates
# required metadata. The output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
import plotly.io as pio
from pathlib import Path
from utils import plot_survey_dates

# Set default plot renderer
pio.renderers.default = 'browser'

# Define directories
drive = Path('C:/')
root_folder = drive / 'ACCS_Work'

# Define folders
project_folder = root_folder / 'OneDrive - University of Alaska/ACCS_Teams' / 'Vegetation' / 'AKVEG_Database' / 'Data'
plot_folder = project_folder / 'Data_Plots' / '44_aim_various_2023'
template_folder = project_folder / 'Data_Entry'

# Define inputs
visit_input = plot_folder / 'working' / '44_aim_2023_site_export.csv'
site_input = plot_folder / '02_site_aimvarious2023.csv'
template_input = template_folder / '03_site_visit.xlsx'

# Define output
visit_output = plot_folder / '03_sitevisit_aimvarious2023.csv'

# Read in data
visit_original = pl.read_csv(visit_input, try_parse_dates=True, columns=["PlotID", "EstablishmentDate",
                                                                       "Observer", "AdditionalObservers",
                                                                         "WetlandType",
                                                                         "AlaskaEcotypeClassification"])
site_original = pl.read_csv(site_input, columns=["establishing_project_code", "site_code"])
template = pl.read_excel(template_input)

# Obtain project code by joining with site data
visit = visit_original.join(site_original, how='right', left_on="PlotID", right_on="site_code")

# Format date and check for outliers
visit = visit.with_columns(pl.col("EstablishmentDate").dt.date().alias("observe_date"))
print(visit["observe_date"].describe())
print(visit['observe_date'].dt.month().unique())  # Date range is reasonable
hist_date = plot_survey_dates(visit)
# print(hist_date.show())

# Create site visit code
visit = visit.with_columns(pl.col("observe_date").cast(pl.String).str.replace_all(pattern="-", value="").alias(
    "date_string"))
visit = visit.with_columns((pl.col("site_code") + "_" + pl.col("date_string")).alias("site_visit_code"))

# Format structural class
## Unable to determine whether 'post-fire scrub' refers to 'low' or 'tall' shrub
visit = visit.with_columns(pl.when(pl.col("AlaskaEcotypeClassification").str.contains(r"Tall S[a-z]rub"))
                           .then(pl.lit("tall shrub"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Low and Tall Shrub"))
                           .then(pl.lit("tall shrub"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Low S[a-z]rub"))  # Prioritize
                           # low shrub even if original classification mentions dwarf shrub
                           .then(pl.lit("low shrub"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Spruce (Forest|Woodland)"))
                           .then(pl.lit("needleleaf forest"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Aspen (Forest|Woodland)"))
                           .then(pl.lit("broadleaf forest"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Spruce-Birch Forest"))
                           .then(pl.lit("mixed forest"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Barrens"))
                           .then(pl.lit("barrens or partially vegetated"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Dwarf"))
                           .then(pl.lit("dwarf shrub"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Bluejoint"))
                           .then(pl.lit("grass meadow"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Lichen Tundra"))
                           .then(pl.lit("lichen tundra"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Wet Sedge"))
                           .then(pl.lit("sedge emergent"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Spruce-Birch Woodland"))
                           .then(pl.lit("mixed forest"))

                           .when(pl.col("AlaskaEcotypeClassification").str.contains(r"Moist Tussock Meadow"))
                           .then(pl.lit("tussock meadow"))

                           .otherwise(pl.lit("not available"))

                           .alias("structural_class")
                           )

## Review classification scheme
contingency_table = (
    visit
    .group_by("AlaskaEcotypeClassification", "structural_class")
    .agg(pl.len().alias("Count"))
)

## Explore entries listed as "not available"
missing_class = visit.filter(pl.col("structural_class") == "not available")

# Format observer names
print(visit["AdditionalObservers"].unique())  # All null
visit = visit.with_columns(pl.when(pl.col("Observer") == "Gerald V Frost")
                           .then(pl.lit("Gerald Frost"))
                           .when(pl.col("Observer") == "Robert W McNown")
                           .then(pl.lit("Robert McNown"))
                           .when(pl.col("Observer") == "Sue L Ives")
                           .then(pl.lit("Susan Ives"))
                           .otherwise(pl.col("Observer"))
                           .alias("veg_observer")
                           )

# Populate remaining columns
visit = (visit.with_columns(pl.lit("map development & verification").alias("data_tier"),
                           pl.lit("unknown").alias("veg_recorder"),
                           pl.lit("unknown").alias("env_observer"),
                           pl.lit("unknown").alias("soils_observer"),
                           pl.lit("exhaustive").alias("scope_vascular"),
                           pl.lit("common species").alias("scope_bryophyte"),
                           pl.lit("common species").alias("scope_lichen"),
                           pl.lit("TRUE").alias("homogeneous"))
         .rename({"establishing_project_code": "project_code"})
         )

# Match template formatting
visit_final = visit[template.columns]

# QC
missing_values = visit_final.null_count()  # Review null counts

# Verify personnel names
print(visit_final["veg_observer"].unique().sort())

# Verify that all structural class values match a constrained value
struct_classes = visit_final["structural_class"].value_counts().sort(by="structural_class")

# Export as CSV
visit_final.write_csv(visit_output)
