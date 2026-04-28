# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Correct errors in Environment table
# Author: Amanda Droghini
# Last Updated: 2026-04-27
# Usage: Execute in Python 3.13+.
# Description: "Correct errors in Environment table" identifies and corrects
# data entry errors in the Environment table of the AKVEG Database.
# ---------------------------------------------------------------------------

# Import packages
from pathlib import Path
import pandas as pd
import numpy as np

# Set root directory
drive = Path("C:/")
root_folder = (
    drive
    / "ACCS_Work"
    / "OneDrive - University of Alaska"
    / "ACCS_Teams"
    / "Vegetation"
    / "AKVEG_Database"
)

# Define folder structure
data_folder = drive / root_folder / "Data" / "Data_Plots" / "processed"
corrected_folder = data_folder / "corrected"

# Define input files
## Use corrected version
environment_file = corrected_folder / "environment.csv"

# Define export file
environment_output = corrected_folder / "environment.csv"

# Read in data
environment_data = pd.read_csv(environment_file)

# Coerce 'number_stems' column to integer by rounding
corrected_environment = environment_data.round({"disturbance_time_y": 0})

# Export corrected table
corrected_environment.to_csv(environment_output, index=False)
