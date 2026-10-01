# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Project table for BLM AIM data
# Author: Amanda Droghini, Alaska Center for Conservation
# Last Updated: 2026-10-01
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: This script formats project-level metadata for the BLM AIM 2022-2025 dataset for ingestion into the
# AKVEG Database Project table. It populates required fields and exports the resulting dataframe to a CSV file.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import polars as pl
from pathlib import Path
from user_tools.utils_init import load_system_paths
from utils.utils import get_template

# Load absolute file paths
paths = load_system_paths()

# Define constant values
FOLDER_ID = "44_aim_various_2025"

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"

# Define output
project_output = plot_folder / '01_project_aimvarious2025.csv'

# Get template file
template = get_template("project")

# Read in plot table
## Restrict to column that has project code
plots = gpd.read_file(gdb_input, layer='AIM_Wetland__F_PlotCharacterization',
                      columns=["Project"], ignore_geometry=True)

# Parse project name
project = ((
    pl.from_pandas(plots)
    .lazy()
    # Drop duplicate entries
    .unique(subset=["Project"])
    # Drop "UnspecifiedBLM" project (should be AK_CentralYukonFO_2022)
    .filter(pl.col("Project") != "UnspecifiedBLM")
    # Extract date from project name
    # Use the same year for both start & end dates (every project spans only one year)
    .with_columns(pl.col("Project").str.extract(r"(\d{4}$)").alias("year_start"))
    .with_columns(pl.col("year_start").alias("year_end"))
    # Format project code
    .with_columns(pl.col("Project").str.replace_many(["AK", "-"], ["AIM", "_"]))
    .with_columns(pl.col("Project")
                  .str.replace_all(r"([a-z])([A-Z])", r"${1}_${2}", literal=False)
                  .str.to_lowercase()
                  .alias("project_code")
                  )
    # Create project name
    .with_columns(pl.col("Project")
                  .str.strip_prefix("AIM_")
                  .str.replace(r"_\d{4}$", "")
                  .str.replace_many(["FO", "DO", "BSWI", "_"], ["Field Office", "District Office",
                                                                "Bering Straits Western Interior", " "])
                  .str.replace_all(r"([a-z])([A-Z])",
                                   r"${1} ${2}", literal=False)
                  .alias("cleaned_name")
                  )
    .with_columns(
        (
                pl.col("cleaned_name")
                + pl.lit(" ")
                + pl.col("year_start").cast(pl.String)
                + pl.lit(" ")
                + pl.lit("Assessment, Inventory, and Monitoring")
        )
        .alias("project_name")
    )
    # Convert years to integer
    .with_columns([
        pl.col("year_start").cast(pl.Int16),
        pl.col("year_end").cast(pl.Int16)
    ])
    # Populate remaining fields
    .with_columns([
        pl.when(pl.col.year_end < 2024)
        .then(pl.lit("ABR"))
        .when(pl.col.project_name.str.contains(r"Kobuk|Eastern|Central"))
        .then(pl.lit("ABR"))
        .when(pl.col.project_name.str.contains("Glennallen"))
        .then(pl.lit("ACCS"))
        .when(pl.col.project_name.str.contains("Bering Straits"))
        .then(pl.lit("ACCS"))
        .when(pl.col.project_name.str.contains("Arctic District Office"))
        .then(pl.lit("BLM"))
        .alias("originator")
        ])
    .with_columns([
        pl.when(pl.col.originator == "ABR")
        .then(pl.lit("Gerald Frost"))
        .when(pl.col.originator == "ACCS")
        .then(pl.lit("Anjanette Steer"))
        .when(pl.col.originator == "BLM")
        .then(pl.lit("Aliza Segal"))
        .alias("manager"),
        pl.when(pl.col("project_name") == "AIM_CentralYukonFO_2022")
                  .then(pl.lit("Data collected as part of the BLM AIM program. Sites "
                               "AK-CYFO-TW-22961 through AK-CYFO-TW-22964 were collected by the Salcha-Delta Soil and Water Conservation District."))
                  .otherwise(pl.lit("Data collected as part of the BLM AIM program."))
                  .alias("project_description"),
        pl.lit("BLM")
        .alias("funder"),
        pl.lit("finished")
        .alias("completion"),
        pl.lit("FALSE")
        .alias("private"),
        pl.lit("direct transfer").alias("source_type"),
        pl.lit("2026-04-22").alias("source_date").cast(pl.Date),
        pl.lit("2026-05-06").alias("acquisition_date").cast(pl.Date)
    ])
)
           # Select columns to match data entry template
           .select(template.columns)
           .collect())

# Check for null values
print(project.null_count().glimpse())

# Export as CSV
project.write_csv(project_output)
