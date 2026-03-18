# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Perform QC checks for Project table
# Author: Amanda Droghini
# Last Updated: 2026-02-18
# Usage: Execute in Python 3.13+.
# Description: "Perform QC checks for Project table" queries the AKVEG database to identify
# data entry errors in the Project table of the AKVEG Database. The output is a CSV file that lists site codes that
# should be dropped from the database because they are lacking cover data or because their coordinate or date values
# are out of bounds.
# ---------------------------------------------------------------------------

# Import packages
import os
import numpy as np
import pandas as pd

# Set options
pd.set_option("display.max_columns", 8)

# Set root directory
drive = "C:/"
root_folder = (
    "ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"
)

# Define folder structure
data_folder = os.path.join(drive, root_folder, "Data", "Data_Plots", "processed")
output_folder = os.path.join(data_folder, "corrected")

# Define input file
project_file = os.path.join(data_folder, "projects.csv")

# Define export file
output_csv = os.path.join(output_folder, "projects.csv")

# Read in processed files
project_data = pd.read_csv(project_file)

# Perform Quality Control checks

# Check for null values
print(project_data.isna().sum())

## Projects listed as 'finished' (completion id = 1) should have a year_end date that is not -999
## Projects listed as 'ongoing' (completion id = 2) should have a year_end date of -999
project_errors = project_data.loc[
    (project_data.completion_id == 1) & (project_data.year_end == -999)
    | (project_data.completion_id == 2) & (project_data.year_end != -999)
]

# Correct errors in Project table
project_correct = project_data.assign(
    completion_id=np.where(
        (project_data["project_code"] == "accs_nelchina_2023"),
        1,
        project_data["completion_id"],
    ),
)

# Repeat Quality Control checks
print(
    project_correct.loc[
        (project_correct.completion_id == 1) & (project_correct.year_end == -999)
        | (project_correct.completion_id == 2) & (project_correct.year_end != -999)
    ]
)

# Export correct table
project_correct.to_csv(output_csv, index=False)
