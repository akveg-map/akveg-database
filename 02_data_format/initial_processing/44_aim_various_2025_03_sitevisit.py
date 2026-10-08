# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site Visit Table for BLM AIM 2022–2025 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-08
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: Formats site visit data by parsing dates, creating site visit codes, re-classifying ecotypes
# into structural classes, and populating missing values with appropriate null values. The script ends by performing
# quality control checks and exporting the dataframe as a CSV file.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import polars as pl
import plotly.io as pio
from pathlib import Path
from utils.utils import get_template, plot_survey_dates, get_valid_values
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql

# Set default plot renderer
pio.renderers.default = 'browser'

# Load absolute file paths
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
observer_input = plot_folder / "archive" / "44_aim_various_2023" / "source" / "RW_AKSDEExport_20241021clean.gdb"
site_input = plot_folder / '02_site_aimvarious2025.csv'
ecotype_input = paths.repository / "02_data_format" / "crosswalks" / '44_aim_various_2025_ecotype_structural_class.csv'
credentials_input = paths.cloud_assets.credentials

# Define output
visit_output = plot_folder / '03_sitevisit_aimvarious2025.csv'

# Connect to AKVEG Database
db_conn = connect_database_postgresql(credentials_input)

# Get template file
template = get_template("site_visit")

# Read in data
site_original = pl.read_csv(site_input, columns=["establishing_project_code", "site_code"]).lazy()
ecotype_lookup = pl.read_csv(ecotype_input, null_values="null").lazy()
visit_lazy = pl.from_pandas(gpd.read_file(gdb_input,
                                        layer="AIM_Wetland__F_PlotCharacterization",
                                        columns=["EvaluationID", "AlaskaEcotypeClassification"],
                                        ignore_geometry=True)
                          ).lazy()
observer_lazy = pl.from_pandas(gpd.read_file(observer_input,
                                           layer="F_PlotCharacterization",
                                           ## "AdditionalObservers" column is all null and therefore ignored
                                           columns=["EvaluationID", "Observer"],
                                           ignore_geometry=True)
                             ).lazy()

# Format observer names
observer_lazy = (observer_lazy.with_columns(pl.when(pl.col("Observer") == "Gerald V Frost")
                           .then(pl.lit("Gerald Frost"))
                           .when(pl.col("Observer") == "Robert W McNown")
                           .then(pl.lit("Robert McNown"))
                           .when(pl.col("Observer") == "Sue L Ives")
                           .then(pl.lit("Susan Ives"))
                           .otherwise(pl.col("Observer"))
                           .alias("veg_observer")
                           ).drop("Observer"))

# Format site visit table
visit = (visit_lazy
         # Obtain observer names by joining with observer_df
         .join(observer_lazy, how="left", on="EvaluationID")
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
         .with_columns(pl.col("observe_date").cast(pl.Date).alias("observe_date"),
                       # Remove whitespaces from ecotype strings
                       pl.col("AlaskaEcotypeClassification").str.strip_chars())
         # Join with site code to obtain project code
         # Will drop any site code that isn't in Site table
         .join(site_original, how='right', on="site_code")
         # Join with Alaska Ecotype lookup table to map to structural class
         .join(ecotype_lookup, how="left", left_on="AlaskaEcotypeClassification", right_on="alaska_ecotype")
         # Populate remaining columns
         .with_columns(pl.lit("map development & verification").alias("data_tier"),
                       pl.col("veg_observer").fill_null(pl.lit("unknown")).alias("veg_observer"),
                       pl.col("structural_class").fill_null(pl.lit("no data")).alias("structural_class"),
                       pl.lit("unknown").alias("veg_recorder"),
                       pl.lit("unknown").alias("env_observer"),
                       pl.lit("unknown").alias("soils_observer"),
                       pl.lit("exhaustive").alias("scope_vascular"),
                       pl.lit("common species").alias("scope_bryophyte"),
                       pl.lit("common species").alias("scope_lichen"),
                       pl.lit("TRUE").alias("homogeneous"))
         # Rename columns
         .rename({"establishing_project_code": "project_code"})
         .collect()
         )

# Quality checks

# Review entries with missing values for structural class
missing_classes = (
    visit
    .select("AlaskaEcotypeClassification", "structural_class")
    .unique()
    .filter((pl.col("structural_class") == "not available") |
            (pl.col("structural_class") == "no data") |
            pl.col("structural_class").is_null())
)
print(missing_classes)

# Match template formatting
visit = visit.select(template.columns)

# Check for date outliers
print(visit["observe_date"].describe())
print(visit['observe_date'].dt.month().unique())  # Date range is reasonable
hist_date = plot_survey_dates(visit)
# print(hist_date.show())

# Check for null values
print(visit.null_count().glimpse())

# Verify constrained values
## Personnel
personnel_full = get_valid_values(db_conn, table_name="personnel", field_name="personnel")
personnel_visit = set(visit.select("veg_observer").unique().to_series())
print(personnel_visit.difference(personnel_full)) ## Should be empty

## Structural class
structural_class_full = get_valid_values(db_conn, table_name="structural_class", field_name="structural_class")
structural_class_visit = set(visit.select("structural_class").unique().to_series())
print(structural_class_visit.difference(structural_class_full)) ## Should be empty

# Export as CSV
visit.write_csv(visit_output)

# Close database connection
db_conn.close()
