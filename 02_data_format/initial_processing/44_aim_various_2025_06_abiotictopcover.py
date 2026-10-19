# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Abiotic Top Cover Table for BLM AIM 2022–2025 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-19
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: This script processes data from line-point intercept surveys to calculate percent abiotic top cover
# for each site visit and abiotic element. It also appends unique site visit identifiers, populates required metadata
# fields, and performs quality control checks. The resulting dataframe is exported to a CSV file for ingestion into
# the AKVEG Database.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import polars as pl
from pathlib import Path
from utils.utils import get_template, get_abiotic_elements, add_missing_elements
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql

# Load absolute file paths
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"
# Abiotic code "HW" is not listed in BLM field manual, possibly a typo. Only one entry, assume litter.
# Abiotic code "NL" is for "non-vegetative litter". Assume animal litter since plastic/human litter is rare in Alaska.
ABIOTIC_CODES = dict(NL="animal litter", W="water", S="soil", HL="litter (< 2 mm)", DL="litter (< 2 mm)",
                     TH="litter (< 2 mm)", HW="litter (< 2 mm)", WL="dead down wood (≥ 2 mm)",
                     EL="dead down wood (≥ 2 mm)", R="rock fragments", GR="rock fragments", CB="rock fragments",
                     ST="rock fragments", BY="rock fragments", BR="bedrock (exposed)")
# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'
credentials_input = paths.cloud_assets.credentials

# Define output
cover_output = plot_folder / '06_abiotictopcover_aimvarious2025.csv'

# Read in data
cover_original = pl.from_pandas(gpd.read_file(gdb_input,
                                              layer="AIM_Wetland__F_LPIDetail")
                                ).lazy()
cover_metadata = (pl.from_pandas(gpd.read_file(gdb_input,
                                               layer="AIM_Wetland__F_LPI",
                                               columns=["LineKey", "LineLength", "LineNumber"],
                                               ignore_geometry=True))
                  .lazy())
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])

# Get template file
template = get_template("abiotic_top_cover")

# Connect to AKVEG Database
db_conn = connect_database_postgresql(credentials_input)

# Obtain abiotic elements from the AKVEG Database
abiotic_query = get_abiotic_elements(db_conn, element_type="abiotic")

# --- Perform initial formatting ---
all_cover = (
    cover_original
    .join(cover_metadata, how="left", left_on="RecKey", right_on="LineKey")
    .select(
        pl.col(["EvaluationID", "LineLength", "LineNumber", "PointNbr", "ChkboxTop"]),
        pl.col("TopCanopy"),
        pl.col("^Lower.*$"),  # Use regex to select multiple columns
        pl.col("SoilSurface")
    )
    # Format site code
    .with_columns(pl.col("EvaluationID")
                  .str.extract(r"^(.*)_")
                  .alias("site_code"))
    # Append site visit code using right join to drop any plots not in site visit table
    .join(visit_original.lazy(), on="site_code", how="right")
    # Create a sequential row number for each site visit
    ## Solution from Ritchie Vink: https://github.com/pola-rs/polars/issues/2542
    .sort(by=["site_visit_code", "LineNumber", "PointNbr"])
    .with_columns(pl.first()
                  .cum_count()
                  .alias("point_number")
                  .over("site_visit_code")
                  .explode(keep_nulls=False, empty_as_null=False)
                  )
    .collect()
)

# Ensure every site code matched to a visit code
print(all_cover["site_code", "site_visit_code"].null_count().glimpse())

# Ensure all lines are the standard 25m length
print(all_cover["LineLength"].unique())

# --- Calculate number of points per plot ---
## Plots should have 150 points (3 transects * 50 points per transects), though plots occasionally have slightly less
## Perform this step prior to any filtering/excluding to ensure all rows are included
number_of_points = (all_cover
                    .group_by("site_visit_code")
                    .agg(pl.col("point_number")
                         .max())
                    .rename({"point_number": "max_hits"})
                    )
print(number_of_points.select("max_hits").unique())

# --- Filter only abiotic cover elements ---
abiotic_cover = (
    all_cover.lazy()
    # Exclude points with vascular species hit in the top canopy, unless the species is dead
    .filter((pl.col("TopCanopy") == "N") | (pl.col("ChkboxTop") == "D"))

    # Exclude points with non-vascular species hit in the first lower layer
    ## Species codes have at least four letters
    .filter((pl.col("Lower1").str.contains(r"^[a-zA-Z]{0,3}$")) & (pl.col("Lower1") != "LI"))  # LI = lichen (not
    # abiotic)

    # Re-classify abiotic elements
    .with_columns(pl.when((pl.col("Lower1").is_in(WOODY_CODES)))
                  .then(pl.lit("dead down wood (≥ 2 mm)"))
                  .when(pl.col("Lower1").is_in(LITTER_CODES))
                  .then(pl.lit("litter (< 2 mm)"))
                  .when(pl.col("Lower1").is_in(WATER_CODES))
                  .then(pl.lit("water"))
                  .when(pl.col("Lower1").is_in(OTHER_LITTER_CODES))
                  .then(pl.lit("animal litter"))
                  .when(pl.col("Lower1").is_in(SOIL_CODES))
                  .then(pl.lit("soil"))
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

# Close database connection
db_conn.close()