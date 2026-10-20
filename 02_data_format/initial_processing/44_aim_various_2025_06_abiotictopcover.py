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
from utils.utils import get_template, get_usda_codes, get_taxonomy, get_abiotic_elements, add_missing_elements
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql

# Load absolute file paths
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"
# Abiotic code "HW" is not listed in BLM field manual, possibly a typo. Only one entry, assume litter.
# Abiotic code "NL" is for "non-vegetative litter". Assume animal litter since plastic/human litter is rare in Alaska.
ABIOTIC_CODES = dict(NL="animal litter", W="water", S="soil", OM="soil", HL="litter (< 2 mm)", DL="litter (< 2 mm)",
                     TH="litter (< 2 mm)", HW="litter (< 2 mm)", WL="dead down wood (≥ 2 mm)",
                     EL="dead down wood (≥ 2 mm)", R="rock fragments", GR="rock fragments", CB="rock fragments",
                     ST="rock fragments", BY="rock fragments", BR="bedrock (exposed)")
NONVASC_CODES = ["LI", "VL", "LC", "M"]  # lichen and moss codes (excluded from abiotic top cover)

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'
credentials_input = paths.cloud_assets.credentials

# Define output
cover_output = plot_folder / '06_abiotictopcover_aimvarious2025.csv'

# Connect to AKVEG Database
db_conn = connect_database_postgresql(credentials_input)

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

# Get USDA plant codes
usda_codes = get_usda_codes()

# Obtain taxonomy checklist from the AKVEG Database
taxonomy_checklist = get_taxonomy(db_conn, simple=False).select(['taxon_name', 'taxon_habit'])

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

    # Exclude points with non-vascular or lichens in the first lower layer
    # Must explicitly keep nulls otherwise they will get dropped by filter
    .filter(pl.col("Lower1").is_null() | ((pl.col("Lower1").str.contains(r"^[a-zA-Z]{0,3}$")) & (~pl.col(
        "Lower1").is_in(NONVASC_CODES))))
    # Exclude points with no plant hits and only non-vasculars/lichens as soil surface
    .filter(~((pl.col("TopCanopy") == "N") & (pl.col("Lower1").is_null()) & (pl.col("SoilSurface").is_in(
        NONVASC_CODES))))

    # Join with USDA plant codes to obtain scientific names for top cover hits
    .join(usda_codes.lazy(), how="left", left_on="TopCanopy", right_on="usda_code")

    # Join with AKVEG taxonomy to obtain functional group
    .join(taxonomy_checklist.lazy(), how="left", left_on="name_original", right_on="taxon_name")

    # Resolve Dryas octopetala non-match
    .with_columns(pl.when(pl.col("TopCanopy") == "DROC")
                  .then(pl.lit("dwarf shrub"))
                  .otherwise(pl.col("taxon_habit"))
                  .alias("taxon_habit"))

    # Classify abiotic elements
    .with_columns(pl.when(pl.col("taxon_habit").str.contains(pattern=r"shrub|tree"))
                  .then(pl.lit("dead standing woody vegetation"))  # Classify dead standing wood first
                  .when(pl.col("taxon_habit").is_not_null())  # Remaining dead top cover hits (forb, graminoid,
                  # spore-bearing) get classified as litter
                  .then(pl.lit("litter (< 2 mm)"))
                  .when((pl.col("Lower1").is_null()) & (pl.col("Lower2").is_in(ABIOTIC_CODES)))  # One entry does not
                  # have anything in TopCanopy or Lower1, but has an abiotic code in Lower2
                  .then(pl.col("Lower2").replace_strict(ABIOTIC_CODES, default=pl.col("Lower2")))
                  .when(pl.col("Lower1").is_in(ABIOTIC_CODES))
                  .then(pl.col("Lower1").replace_strict(ABIOTIC_CODES, default=pl.col("Lower1")))
                  .when(pl.all_horizontal(pl.col("^Lower.*$").is_null()))  # If all "Lower" columns are null,
                  # then look at SoilSurface
                  .then(pl.col("SoilSurface").replace_strict(ABIOTIC_CODES, default=pl.col("SoilSurface")))
                  .otherwise(pl.lit("ERROR"))
                  .alias("abiotic_element")
                  )
    .select(pl.col(["site_visit_code", "abiotic_element"]))
    .collect()
)

# Explore abiotic elements
print(abiotic_cover["abiotic_element"].value_counts())  # Should not be any "ERROR" codes
print(abiotic_cover["abiotic_element"].null_count())

# --- Calculate percent cover ---

# Define grouping columns
GROUP_COLUMNS = [
    "site_visit_code",
    "abiotic_element"
]

# Calculate cover percent for each abiotic element and site visit
abiotic_percent = (abiotic_cover
                   .lazy()
                   #  Create counter column with value of 1 to calculate number of times the abiotic element was
                   #  observed
                   .with_columns(pl.lit(1).alias("observation_marker"))

                   # Calculate total number of hits per element per site visit
                   .group_by(GROUP_COLUMNS).agg(pl.col("observation_marker").sum())

                   # Get maximum number of points per plot
                   .join(number_of_points.lazy(), how="left", on="site_visit_code")

                   # Calculate percent cover
                   .with_columns((pl.col("observation_marker") / pl.col("max_hits") * 100)
                                 .round(3)
                                 .alias("abiotic_top_cover_percent"))

                   .collect()
                   )

# Add missing elements & select only relevant columns
## Use visit codes from Site Visit table (some site visits may not have any abiotic top hits)
visit_codes = visit_original["site_visit_code"].unique().to_list()
abiotic_final = add_missing_elements(visit_codes,
                                     abiotic_percent,
                                     abiotic_query)

# --- Quality checks ---

# Ensure no null values
print(abiotic_final.null_count().glimpse())

# Ensure cover percent is between 0% and 100%
print(abiotic_final.select(pl.col("abiotic_top_cover_percent")).describe())

# Ensure all site visit codes are included
set_cover = set(abiotic_final.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_codes)
print(set_cover ^ set_visit)  # Test for symmetric difference (i.e., difference in either direction)

# Ensure every site visit has an entry for each abiotic element
# Resulting dataframe should be empty
print(abiotic_final.group_by("site_visit_code")
      .agg(pl.col("abiotic_element").count())
      .filter(pl.col("abiotic_element") != abiotic_query.shape[0])
      )

# Ensure that sum of abiotic top cover does not exceed 100%
# Resulting dataframe should be empty
print(abiotic_final.group_by("site_visit_code")
      .agg(pl.col("abiotic_top_cover_percent").sum())
      .filter(pl.col("abiotic_top_cover_percent") > 100)
      )

# Export as CSV
abiotic_final.write_csv(abiotic_output)

# Close database connection
db_conn.close()
