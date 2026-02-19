# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Perform QC check for Vegetation Cover table
# Author: Amanda Droghini
# Last Updated: 2026-01-24
# Usage: Execute in Python 3.13+.
# Description: "Perform QC check for Vegetation Cover table" identifies and corrects
# data entry errors in the Vegetation Cover of the AKVEG Database.
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
## Use corrected versions
site_file = corrected_folder / "sites.csv"
visit_file = corrected_folder / "site_visits.csv"
vegetation_file = corrected_folder / "vegetation_cover.csv"

# Define export file
vegetation_output = corrected_folder / "vegetation_cover.csv"

# Read in data
site_data = pd.read_csv(site_file)
visit_data = pd.read_csv(visit_file, parse_dates=["observe_date"])
vegetation_data = pd.read_csv(vegetation_file)

# Create lookup table to link site visit code to project code
visit_simple = visit_data.filter(items=["site_code", "site_visit_code"])
site_simple = site_data.filter(items=["site_code", "establishing_project_code"])
lookup_table = pd.merge(
    site_simple, visit_simple, how="left", left_on="site_code", right_on="site_code"
)

# Check for null values
print(vegetation_data.isna().sum())

# Explore range of cover percent values are reasonable
vegetation_data = vegetation_data.assign(
    cover_percent=vegetation_data.cover_percent.astype(float)
)
print(vegetation_data.cover_percent.describe())

## Investigate sites that have cover values of -999
negative_cover = vegetation_data[vegetation_data.cover_percent < 0]
print(negative_cover.shape[0])  # Number of rows affected
print(negative_cover["cover_percent"].unique())  # All values that are less than 0 are -999

negative_cover = pd.merge(
    negative_cover,
    lookup_table,
    how="left",
    left_on="site_visit_code",
    right_on="site_visit_code",
)
negative_cover.establishing_project_code.unique()  # 1150 entries from two projects (accs_alphabethills_2021 and
# harvard_alder_2023). Both projects make sense - Intentionally
# coded as such to
# represent absences.

# If cover type is 'top foliar cover', sum of cover for that site visit should not exceed 100%
top_foliar_cover = vegetation_data.loc[vegetation_data.cover_type_id == 2]
top_cover_sum = top_foliar_cover.groupby("site_visit_code").cover_percent.sum()
top_cover_sum = pd.merge(
    top_cover_sum,
    lookup_table,
    how="left",
    left_on="site_visit_code",
    right_on="site_visit_code",
)
top_cover_sum = top_cover_sum[top_cover_sum.cover_percent > 110]
top_cover_sum.establishing_project_code.unique()

# Do not address for now. Need to discuss with TWN

# Correct erroneous plant identifications
print(
    vegetation_data.loc[
        (vegetation_data["name_original"] == "Salix planifolia")
        & (vegetation_data["code_adjudicated"] != "salpul")
    ]
)  ## Affects 232 sites

corrected_vegetation = vegetation_data.assign(
    code_adjudicated=np.where(
        vegetation_data["name_original"] == "Salix planifolia",
        "salpul",
        vegetation_data["code_adjudicated"],
    )
)

# Export corrected table
corrected_vegetation.to_csv(vegetation_output, index=False)
