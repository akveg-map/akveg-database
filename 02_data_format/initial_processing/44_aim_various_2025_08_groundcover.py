# -*- coding: utf-8 -*-
"""Format Ground Cover Table for BLM AIM 2022–2025 data

Processes data from line-point intercept surveys to calculate percent ground cover for each site visit and ground
element. Appends unique site visit identifiers, populates metadata fields, and performs quality control
checks before exporting to CSV for ingestion into the AKVEG Database.

Author: Amanda Droghini, Alaska Center for Conservation Science
Last Updated: 2026-10-24
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
import geopandas as gpd
from pathlib import Path
import polars as pl
import polars.selectors as cs
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql
from utils.utils import *

# -------- Set Up Environment ------------------------------------------
# Load absolute file paths
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"
LITTER_CODES = ["HL", "DL", "TH"]
WOOD_CODES = ["WL", "EL"]
SOIL_ROCK_CODES = dict(S="mineral soil", OM="organic soil", R="rock fragments", GR="gravel", CB="cobble",
                       ST="stone", BY="boulder", BR="bedrock (exposed)")
# Assume "NL" (non-vegetative litter) is animal litter since plastic/human litter is rare in Alaska.
BIOTIC_CODES = ["NL", "LI", "VL", "LC", "M", "MO", "HW"]

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'
credentials_input = paths.cloud_assets.credentials

# Define output
ground_output = plot_folder / '08_groundcover_aimvarious2025.csv'

# Connect to AKVEG Database
db_conn = connect_database_postgresql(credentials_input)

# -------- Load Data ---------------------------------------------------
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
template = get_template("ground_cover")

# Get USDA plant codes
usda_codes = get_usda_codes()

# Get taxonomy checklist from AKVEG Database
taxonomy_checklist = get_taxonomy(db_conn, simple=False)

# Get abiotic elements from the AKVEG Database
ground_query = get_abiotic_elements(db_conn, element_type="ground")

# -------- Prepare Cover Data ------------------------------------------
ground_cover = (
    cover_original
    .join(cover_metadata, how="left", left_on="RecKey", right_on="LineKey")
    .select(
        pl.col(["EvaluationID", "LineLength", "LineNumber", "PointNbr"]),
        pl.col("TopCanopy"),
        pl.col("^Lower.*$"),  # Use regex to select multiple columns
        pl.col(["codebasal", "SoilSurface"])
    )
    # Replace whitespaces with nulls
    .with_columns(cs.string().str.strip_chars().replace("", None))
    # Format site code
    .with_columns(pl.col("EvaluationID")
                  .str.extract(r"^(.*)_")
                  .alias("site_code"))
    # Append site visit code using right join to drop any plots not in site visit table
    .join(visit_original.lazy(), on="site_code", how="right")
    # Classify ground elements
    .with_columns(
        # Classify water hits first: if water occurs anywhere on the line, ground cover is water
        pl.when(pl.any_horizontal(cs.matches("^Lower.*$|SoilSurface") == "W"))
        .then(pl.lit("water"))
        # Classify biotic hits
        .when(pl.any_horizontal(cs.matches("codebasal|SoilSurface").str.contains(r"^[a-zA-Z]{4,}"),
                                cs.string().is_in(BIOTIC_CODES)))
        .then(pl.lit("biotic"))
        # Classify woody litter
        .when(pl.any_horizontal(cs.matches("^Lower.*$|SoilSurface").is_in(WOOD_CODES)))
        .then(pl.lit("dead down wood (≥ 2 mm)"))
        # Classify herbaceous litter
        .when(pl.any_horizontal(cs.matches("^Lower.*$|SoilSurface").is_in(LITTER_CODES)))
        .then(pl.lit("litter (< 2 mm)"))
        # If none of these conditions are satisified, classify as soil or rock
        .when(pl.col("SoilSurface").is_in(SOIL_ROCK_CODES))
        .then(pl.col("SoilSurface").replace_strict(SOIL_ROCK_CODES,
                                                   default=None))
        # If all columns are null, classify as mineral soil
        .when(pl.all_horizontal(cs.matches("TopCanopy|^Lower.*$|codebasal|SoilSurface").is_null()))
        .then(pl.lit("mineral soil"))
        .otherwise(None)
        .alias("ground_element"))
    .collect()
)

# Ensure every site code matched to a visit code
print(ground_cover.select(["site_code", "site_visit_code"]).null_count().glimpse())

# Explore ground elements
# Ensure no nulls
with pl.Config(tbl_rows=-1):
    print(ground_cover["ground_element"].value_counts())

# Ensure TopCanopy column does not contain any ground element codes besides "N" (indicating a non-vascular top hit)
# Logic above assumes TopCanopy column can be ignored (consistent with field protocols)
print(ground_cover
      .select(pl.col("TopCanopy"))
      .unique()
      .filter((pl.col("TopCanopy").str.contains(r"^[a-zA-Z]{0,3}$")) &
              (pl.col("TopCanopy") != "N"))
      .item()
      )  # Only 3-letter code is POA, can ignore

# -------- Calculate Number of Hits per Visit --------------------------
# Plots should have 150 points (3 transects * 50 points per transects), though plots occasionally have slightly less
# Perform this step on full dataframe to ensure all rows are included
max_hits = max_hits_per_visit(ground_cover)
print(max_hits.select("max_hits").unique())

# -------- Calculate Percent Cover -------------------------------------

# Define grouping columns
group_columns = ["site_visit_code", "ground_element"]

ground_percent = (ground_cover
                  # Calculate total number of hits per element per site visit
                  .group_by(group_columns).agg(pl.len().alias("total_hits"))
                  # Get maximum number of points per plot
                  .join(max_hits, how="left", on="site_visit_code")
                  # Calculate percent cover
                  .with_columns((pl.col("total_hits") / pl.col("max_hits") * 100)
                                .round(3)
                                .alias("ground_cover_percent"))
                  )

# Add missing elements & select only relevant columns
# Use visit codes from Site Visit table to ensure all site visits are represented
ground_final = add_missing_elements(visit_df=visit_original,
                                    percent_df=ground_percent,
                                    elements_df=ground_query,
                                    elements_col="ground_element",
                                    percent_col="ground_cover_percent")

# -------- Perform Quality Checks --------------------------------------
# No null values
print(ground_final.null_count().glimpse())

# Cover percent is between 0% and 100%
print(ground_final.select(pl.col("ground_cover_percent")).describe())

# All site visit codes are included
set_cover = set(ground_final.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_original.get_column("site_visit_code").unique().to_list())
print(set_cover ^ set_visit)  # Test for symmetric difference (i.e., difference in either direction)

# Every site visit has an entry for each element
# Resulting dataframe should be empty
print(ground_final.group_by("site_visit_code")
      .agg(pl.col("ground_element").count())
      .filter(pl.col("ground_element") != ground_query.shape[0])
      )

# Sum of ground cover does not exceed 100%
# Resulting dataframe should be empty
print(ground_final.group_by("site_visit_code")
      .agg(pl.col("ground_cover_percent").sum())
      .filter(pl.col("ground_cover_percent") > 100)
      .select("ground_cover_percent")
      .unique()
      )  # Decimal dust from rounding, OK to ignore

# -------- Export Data -------------------------------------------------
ground_final.write_csv(ground_output)

# -------- Close Database Connection -----------------------------------
db_conn.close()
