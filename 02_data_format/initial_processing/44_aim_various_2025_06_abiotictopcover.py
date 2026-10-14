# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Abiotic Top Cover Table for BLM AIM Various 2023 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2025-11-03
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Abiotic Top Cover Table for BLM AIM Various 2023 data" uses data from line-point intercept surveys
# to calculate site-level percent abiotic top cover for each abiotic element. It appends unique site visit
# identifiers, populates required metadata fields, and performs QC checks. The script depends on the output from the
# 44_aim_various_2023_00_extract_data.py script. The output is a CSV table that can be converted and included in a
# SQL INSERT statement.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
from pathlib import Path
from utils import get_abiotic_elements
from utils import add_missing_elements

# Define directories
drive = Path('C:/')
root_folder = drive / 'ACCS_Work'

# Define folders
project_folder = root_folder / 'OneDrive - University of Alaska' / 'ACCS_Teams' / 'Vegetation' / 'AKVEG_Database' / 'Data'
plot_folder = project_folder / 'Data_Plots' / '44_aim_various_2023'
template_folder = project_folder / 'Data_Entry'

# Define inputs
cover_input = plot_folder / 'working' / '44_aim_2023_veg_export.csv'
visit_input = plot_folder / '03_sitevisit_aimvarious2023.csv'
template_input = template_folder / '06_abiotic_top_cover.xlsx'

# Define output
abiotic_output = plot_folder / '06_abiotictopcover_aimvarious2023.csv'

# Read in data
lazy_abiotic = pl.scan_csv(cover_input)
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = pl.read_excel(template_input)

# Obtain abiotic elements from the AKVEG Database
abiotic_query = get_abiotic_elements(element_type="abiotic")

# Load and format abiotic top cover data
all_cover = (
    lazy_abiotic
    .select(
        pl.col(["EvaluationID", "LineLength", "LineNumber", "PointNbr",
                "TopCanopy", "Lower1", "SoilSurface"])
    )
    # Format site code
    .with_columns(pl.col("EvaluationID")
                  .str.extract(r"^(.*)_")
                  .alias("site_code"))
    # Append site visit code using right join to drop any plots that were excluded from site visit table
    .join(visit_original.lazy(), on="site_code", how="right")

    .collect()
)

# Calculate number of points per plot
# Plots should have 150 points (3 transects * 50 points per transects), but that is not always the case
number_of_points = (
    all_cover.lazy()
    # Create a sequential row number for each site visit
    ## Solution from Ritchie Vink: https://github.com/pola-rs/polars/issues/2542
    .sort(by=["site_visit_code", "LineNumber", "PointNbr"])
    .with_columns(pl.first()
                  .cum_count()
                  .alias("point_number")
                  .over("site_visit_code")
                  .flatten())

    # Calculate maximum number of points per line
    .group_by("site_visit_code")
    .agg(pl.col("point_number")
         .max())
    .rename({"point_number": "max_hits"})

    .collect()
)

print(number_of_points.describe())

# Obtain abiotic cover elements only
abiotic_cover = (
    all_cover.lazy()
    # Exclude points with vascular species hit in the top canopy
    .filter(pl.col("TopCanopy") == "N")

    # Exclude points with non-vascular species hit in the first lower layer
    ## Species codes typically have at least four letters
    .filter((pl.col("Lower1").str.contains(r"^[a-zA-Z]{0,3}$")) & (pl.col("Lower1") != "LI"))  # LI = lichen (not
    # abiotic)

    # Re-classify abiotic elements
    .with_columns(pl.when((pl.col("Lower1").str.contains("^WL$|^TH$")))
                  .then(pl.lit("dead down wood (≥ 2 mm)"))
                  .when(pl.col("Lower1").str.contains("^DL$|^HL$|^NL$|^HW$"))  # HW not listed in BLM manual,
                          # possibly a type. Only one entry, litter type listed as "DL". Assume litter.
                  .then(pl.lit("litter (< 2 mm)"))
                  .when(pl.col("Lower1") == "W")
                  .then(pl.lit("water"))
                  .otherwise(pl.lit("Error"))
                  .alias("abiotic_element")
                  )

    .select(pl.col(["site_visit_code", "abiotic_element"]))

    .collect()
)

## Explore abiotic elements
print(abiotic_cover["abiotic_element"].value_counts())
print(abiotic_cover["abiotic_element"].null_count())

# --- Calculate percent cover ---

# Define grouping columns
group_columns = [
    "site_visit_code",
    "abiotic_element"
]

# Calculate cover percent for each abiotic element and site visit
abiotic_percent = (abiotic_cover
                    .lazy()
                    ## Create constant column with value of 1 to calculate number of times the species was observed
                    # across all points
                    .with_columns(pl.lit(1).alias("observation_marker"))

                    # Calculate total number of hits per species per site visit
                    .group_by(group_columns).agg(pl.col("observation_marker").sum())

                    # Get maximum number of points per plot
                    .join(number_of_points.lazy(), how="left", on="site_visit_code")

                    # Calculate percent cover
                    .with_columns((pl.col("observation_marker") / pl.col("max_hits") * 100)
                                  .round(3)
                                  .alias("abiotic_top_cover_percent"))

                   .collect()
                   )

# Add missing elements & select only relevant columns
## Define visit codes based on Site Visit table
visit_codes = visit_original["site_visit_code"].unique().to_list()
abiotic_final = add_missing_elements(visit_codes,
                                     abiotic_percent,
                                     abiotic_query)

# QC
print(abiotic_final.describe())  ## Ensure no null values, range of % cover between 0-100%

# Ensure that all site visit codes are included
set_cover = set(abiotic_final.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_original.get_column("site_visit_code").unique().to_list())
print(set_cover == set_visit)

# Ensure every site visit has an entry for each abiotic element
print(abiotic_final.group_by("site_visit_code")
      .agg(pl.col("abiotic_element").count())
      .filter(pl.col("abiotic_element") != abiotic_query.shape[0])
      )  ## Resulting df should be empty

# Ensure that sum of abiotic top cover does not exceed 100%
print(abiotic_final.group_by("site_visit_code")
      .agg(pl.col("abiotic_top_cover_percent").sum())
      .filter(pl.col("abiotic_top_cover_percent") > 100)
      ) ## Resulting df should be empty

# Export as CSV
abiotic_final.write_csv(abiotic_output)
