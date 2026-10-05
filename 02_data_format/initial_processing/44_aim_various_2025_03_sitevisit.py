# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site Visit Table for BLM AIM 2022–2025 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-05
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Site Visit Table for BLM AIM 2022–2025 data" formats site visit metadata for
# ingestion into the AKVEG Database. The script aligns the dataframe to the AKVEG schema by parsing dates,
# creating site visit codes, re-classifying structural classes, and populating missing values with appropriate null
# values. The script ends by performing quality control checks and exporting the dataframe as a CSV file.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import polars as pl
import plotly.io as pio
from pathlib import Path
from utils.utils import get_template, plot_survey_dates
from user_tools.utils_init import load_system_paths

# Set default plot renderer
pio.renderers.default = 'browser'

# Load absolute file paths
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
site_input = plot_folder / '02_site_aimvarious2025.csv'
ecotype_input = plot_folder / working / 'ecotype_class_mapping.csv'

# Define output
visit_output = plot_folder / '03_sitevisit_aimvarious2025.csv'

# Get template file
template = get_template("site_visit")

# Read in data
site_original = pl.read_csv(site_input, columns=["establishing_project_code", "site_code"]).lazy()
ecotype_lookup = pl.read_csv(ecotype_input)
visit_original = gpd.read_file(gdb_input, layer="AIM_Wetland__F_PlotCharacterization",
                               columns=["EvaluationID",
                                        "AlaskaEcotypeClassification"])

# Convert gpd to Polars DataFrame
visit_df = pl.from_pandas(visit_original.drop(columns=['geometry']))

# Explore structural class categories
struct_class_groups = (
    visit_df
    .group_by("AlaskaEcotypeClassification")
    .len(name="count")
    .sort("count", descending=True)
)

# Format site visit table
visit = (visit_df
         .lazy()
         # Parse site code and observation date from Evaluation ID
         .with_columns(pl.col("EvaluationID").str.split_exact("_", 1)
              .struct.rename_fields(["site_code", "observe_date"])
              .alias("fields")
              )
         .unnest("fields")
         # Concatenate site code and observe date to create site visit code
         .with_columns(pl.col("observe_date").str.replace_all(pattern="-", value="").alias("date_string"))
         .with_columns((pl.col("site_code") + "_" + pl.col("date_string")).alias("site_visit_code"))
         # Cast date field
         .with_columns(pl.col("observe_date").cast(pl.Date).alias("observe_date"))
         # Join with site code to obtain project code
         .join(site_original, how='right', on="site_code")
         # Join with Alaska Ecotype lookup table to map to structural class
         .join(wetland_lookup, how="left", left_on="AlaskaEcotypeClassification", right_on="alaska_ecotype")
         .collect()
         )


# Check for date outliers
print(visit["observe_date"].describe())
print(visit['observe_date'].dt.month().unique())  # Date range is reasonable
hist_date = plot_survey_dates(visit)
# print(hist_date.show())

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
