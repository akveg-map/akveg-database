# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Correct errors in Shrub Structure table
# Author: Amanda Droghini
# Last Updated: 2026-04-27
# Usage: Execute in Python 3.13+.
# Description: "Correct errors in Shrub Structure table" identifies and corrects
# data entry errors in the Shrub Structure table of the AKVEG Database.
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
shrub_file = corrected_folder / "shrub_structure.csv"

# Define export file
shrub_output = corrected_folder / "shrub_structure.csv"

# Read in data
shrub_data = pd.read_csv(shrub_file)

# Coerce 'number_stems' column to integer by rounding
corrected_shrub = shrub_data.round({"number_stems": 0})

# Export corrected table
corrected_shrub.to_csv(shrub_output, index=False)
