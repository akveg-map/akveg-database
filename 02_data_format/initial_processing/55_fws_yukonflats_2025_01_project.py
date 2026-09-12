# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Project table for USFWS Yukon Flats data
# Author: Amanda Droghini, Alaska Center for Conservation
# Last Updated: 2026-09-12
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Project table for USFWS Yukon Flats data" populates required fields for the AKVEG project table.
# The output is a CSV file that can be used for upload to the AKVEG database.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
from pathlib import Path
from utils.utils import get_template

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
project_folder = root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database' / 'Data'
plot_folder = project_folder / 'Data_Plots' / '55_fws_yukonflats_2025'

# Define output
project_output = plot_folder / '01_project_fwsyukonflats2025.csv'

# Read template file
template = get_template("project")

# Populate template with data
project = (pl.DataFrame({"project_code": ['fws_yukonflats_2025'],
                         "project_name": ['Yukon Flats Wildlife Refuge Bison Habitat Survey'],
                         "originator": ['USFWS'],
                         "funder": ['USFWS'],
                         "manager": ['Hunter Gravley'],
                         "completion": ['finished'],
                         "year_start": [2025],
                         "year_end": [2025],
                         "project_description": ['Line-point intercept plots to quantify and describe '
                                                 'potential habitat for wood bison on the Yukon Flats '
                                                 'National Wildlife Refuge.'],
                         "private": ["FALSE"]
                         }
                        )
           .select(template.columns)
           )

# Export as CSV
project.write_csv(project_output)
