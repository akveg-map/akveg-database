# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# "Format Project Table for BLM AIM Various 2023 data"
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-01
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Project Table for BLM AIM Various 2023 data" enters and formats project-level information for
# ingestion into the AKVEG Database. The script depends on the output from the 44_aim_various_2023_00_extract_data.py
# script. The output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
from pathlib import Path

# Define directories
drive = Path('C:/')
root_folder = drive / 'ACCS_Work'

# Define folders
project_folder = (root_folder / 'OneDrive - University of Alaska' / 'ACCS_Teams' / 'Vegetation' / 'AKVEG_Database' /
                  'Data')
plot_folder = project_folder / 'Data_Plots' / '44_aim_various_2023'
template_folder = project_folder / 'Data_Entry'

# Define inputs
site_input = plot_folder / 'working' / '44_aim_2023_site_export.csv'
template_input = template_folder / '01_project.xlsx'

# Define output
project_output = plot_folder / '01_project_aimvarious2023.csv'

# Read in data
site_original = pl.read_csv(site_input, columns=["Project", "Observer","EstablishmentDate"], try_parse_dates=True)
template = pl.read_excel(template_input)

# Parse project name, project code, and start/end years
lazy_project = (
    site_original.lazy()
    .with_columns([
        # Correct name of "unspecified" project
        pl.when(pl.col("Project") == "UnspecifiedBLM")
        .then(pl.lit("AK_CentralYukonFO_2022"))
        .otherwise(pl.col("Project"))
        .alias("project_name"),
        # Extract year from date
        pl.col("EstablishmentDate").dt.year().alias("year")
    ])

# Drop duplicate entries
    .unique(subset=["project_name", "year"])

# Because every project only spans a single year, use the same year for both start & end dates
    .with_columns(pl.col("year").alias("year_start"),
                  pl.col("year").alias("year_end"))

# Format project code
    .with_columns(pl.col("project_name").str.replace_many(["AK", "-"], ["AIM", "_"]))
    .with_columns(pl.col("project_name")
                  .str.replace_all(r"([a-z])([A-Z])", r"${1}_${2}", literal=False)
                  .str.to_lowercase()
                  .alias("project_code")
                  )

# Create project name
    .with_columns(pl.col("Project")
                  .str.strip_prefix("AK_")
                  .str.replace(r"_\d{4}$", "")
                  .str.replace("FO", "Field Office")
                  .str.replace_all(r"([a-z])([A-Z])",
                                   r"${1} ${2}", literal=False)
                  .alias("cleaned_name")
                  )
    .with_columns(
        (
                pl.col("cleaned_name")
                + pl.lit(" ")
                + pl.col("year").cast(pl.String)
                + pl.lit(" ")
                + pl.lit("Assessment, Inventory, and Monitoring")
        )
        .alias("project_name")
    )
# Populate remaining fields
    .with_columns([
        pl.lit("ABR")
        .alias("originator"),
        pl.lit("Gerald Frost")
        .alias("manager"),
        pl.when(pl.col("Project") == "AK_CentralYukonFO_2022")
                  .then(pl.lit("Vegetation plots data collected as part of the BLM AIM program. Plots "
                               "AK-CYFO-TW-22961 through AK-CYFO-TW-22964 were collected by the Salcha-Delta Soil and Water Conservation District."))
                  .otherwise(pl.lit("Vegetation plots data collected as part of the BLM AIM program."))
                  .alias("project_description"),
        pl.lit("BLM")
        .alias("funder"),
        pl.lit("finished")
        .alias("completion"),
        pl.lit("FALSE")
        .alias("private")
    ])
)

# Execute lazy frame operations
project_data = lazy_project.collect()

# Select columns to match data entry template
project_data = project_data[template.columns]

# Ensure all rows have a value
with pl.Config(tbl_cols=10):
    print(project_data.null_count())

# Export as CSV
project_data.write_csv(project_output)
