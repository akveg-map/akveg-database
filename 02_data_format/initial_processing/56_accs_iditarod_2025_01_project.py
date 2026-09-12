# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Project table for ACCS Iditarod Trail 2025 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-09-12
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: This script formats project-level metadata for the ACCS Iditarod Trail 2025 dataset for ingestion into
# the AKVEG Database Project table. It reads a source Excel file and aligns the file to the AKVEG schema by populating required fields and correcting existing values. The resulting dataframe is exported to a CSV.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
from user_tools.utils_init import load_system_paths
from initial_processing.utils import get_template

# Load absolute file paths
paths = load_system_paths()

# Define dataset identifier
FOLDER_ID = "56_accs_iditarod_2025"

# Define input paths
plot_folder = paths.cloud_assets.plots / FOLDER_ID
project_input = plot_folder / "source"/ "01_project.xlsx"
template_input = paths.cloud_assets.templates / "01_project.xlsx"

# Define output
project_output = paths.cloud_assets.plots / FOLDER_ID / "01_project_accsiditarod2025.csv"

# Read in data
template = get_template("project")
project_original = pl.read_excel(project_input)

# Format project table
project = (
    project_original.lazy()
    # Correct existing values
    .with_columns(
        pl.lit("accs_iditarod_2025").alias("project_code"),
        pl.lit("Invasive Species Inventory along BLM's Iditarod National Historic Trail").alias("project_name"),
        pl.lit("ACCS").alias("originator"),
        pl.col("manager").str.split(by=",").list.get(0).str.strip_chars(),
        pl.lit("finished").alias("completion"),
        pl.lit("FALSE").alias("private")
    )
    # Add missing columns
    .with_columns(
        pl.lit(
            "Vegetation survey along the Iditarod National Historic Trail to inventory invasive plant species."
        ).alias("project_description"),
        pl.lit("akveg origin").alias("source_type"),
        pl.lit("2025-09-25").alias("source_date"),
        pl.lit("2025-09-25").alias("acquisition_date"),
    )
    # Match template column order
    .select(template.columns)
    .collect()
)

# Export as CSV
project.write_csv(project_output)
