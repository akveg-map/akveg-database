# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Vegetation Cover Table for BLM AIM 2022–2025 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-07
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: This script summarizes data from line-point intercept surveys as site-level percent foliar
# cover for each recorded species. It also appends unique site visit identifiers, resolves taxonomic names,
# populates required metadata fields, and performs quality control checks before exporting the dataframe as a CSV file.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import polars as pl
from pathlib import Path
from utils.utils import get_template, get_taxonomy, get_usda_codes
from user_tools.utils_init import load_system_paths

# Load absolute file paths
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'
codes_input = plot_folder / 'working' / '2021_AK_AIM_SpeciesList_AKVEG_Formatted 1.xlsx'

# Define output
cover_output = plot_folder / '05_vegetationcover_aimvarious2025.csv'

# Read in data
cover_original = pl.from_pandas(gpd.read_file(gdb_input,
                                              layer="AIM_Wetland__F_LPIDetail")
                                ).lazy()
cover_metadata = (pl.from_pandas(gpd.read_file(gdb_input,
                                               layer="AIM_Wetland__F_LPI",
                                               columns=["LineKey", "LineLength", "LineNumber"],
                                               ignore_geometry=True))
                  .lazy())
codes_original = pl.read_excel(codes_input, columns=["name", "scientific_akveg"])
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])

# Get template file
template = get_template("vegetation_cover")

# --- Perform initial formatting ---
vegetation_cover = (
    cover_original
    .join(cover_metadata, how="left", left_on="RecKey", right_on="LineKey")
    .select(
        pl.col(["EvaluationID", "LineLength", "LineNumber", "PointNbr", "ChkboxTop"]),
        pl.col("^ChkboxLower.*$"),  # Use regex to select multiple columns
        pl.col("ChkboxBasal"),
        pl.col("TopCanopy"),
        pl.col("^Lower.*$"),
        pl.col("codebasal")
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
print(vegetation_cover["site_code", "site_visit_code"].null_count().glimpse())

# Ensure all lines are the standard 25m length
print(vegetation_cover["LineLength"].unique())

# --- Calculate number of points per plot ---
## Plots should have 150 points (3 transects * 50 points per transects), though plots occasionally have slightly less
## Perform this step prior to any filtering/excluding to ensure no rows are dropped
number_of_points = (vegetation_cover
                    .group_by("site_visit_code")
                    .agg(pl.col("point_number")
                         .max())
                    .rename({"point_number": "max_hits"})
                    )
print(number_of_points.describe())

# --- Convert to long format ---

# Identify abiotic element codes (to be excluded from species list)
abiotic_elements = ["HL", "N", "DL", "NL", "WL", "W", "TH"]

# Identify groups of columns
species_cols = vegetation_cover.select(pl.col(["TopCanopy", "^Lower.*$", "codebasal"])).columns
chkbox_cols = vegetation_cover.select(pl.col("^Chkbox.*$")).columns  # Indicates dead status
id_cols = ["site_visit_code", "point_number"]

# Melt species codes columns
species_long = (
    vegetation_cover
    .unpivot(
        on=species_cols,
        index=id_cols,
        variable_name="strata",
        value_name="usda_code",
    )
    # Drop abiotic codes, null and empty cells
    .filter(pl.col("usda_code").is_not_null()
            .and_(~pl.col("usda_code").is_in(abiotic_elements))
            .and_(pl.col("usda_code") != "")
            )
    # Create common key to join with dead status
    .with_columns(pl.col("strata")
                  .str.replace_many(["TopCanopy", "codebasal"], ["Top", "Basal"])
                  .alias("strata")
                  )
)

# Melt dead status columns
dead_long = (
    vegetation_cover
    .unpivot(
        on=chkbox_cols,
        index=id_cols,
        variable_name="strata",
        value_name="dead_status",
    )
    # Convert Live and Dead codes to Boolean
    ## Assume empty and null cells are supposed to be alive (FALSE)
    .with_columns(pl.when(pl.col("dead_status") == "D")
                  .then(pl.lit("TRUE"))
                  .otherwise(pl.lit("FALSE"))
                  .alias("dead_status"))
    # Create common key to join with species codes
    .with_columns(pl.col("strata")
                  .str.strip_prefix("Chkbox")
                  .alias("strata")
                  )
)

# Ensure dead_status has been correctly re-classified
print(dead_long.select(pl.col("dead_status")).to_series().value_counts())

# Join tables using left join to keep only valid species rows
vegetation_cover_long = (species_long.join(dead_long,
                                           on=id_cols + ["strata"],
                                           how="left")
                         .sort(["site_visit_code", "point_number"])
                         )

# --- Obtain accepted taxonomic names ----

# Obtain taxonomy checklist from the AKVEG Database
taxonomy_checklist = get_taxonomy(simple=True)

# Extract unknown codes (ending in '86') from AIM species list
unknown_codes = (codes_original
                 .filter(pl.col("name").str.contains(r"86$"))
                 .rename({"name": "usda_code",
                          "scientific_akveg": "name_original"}))

# Get USDA plant codes
usda_codes = get_usda_codes()

# Add unknown codes to USDA df
usda_codes = pl.concat([usda_codes, unknown_codes])

# Translate USDA codes to accepted scientific names
cover_taxa = (vegetation_cover_long.lazy()
              # Join cover df to USDA plant codes to obtain scientific names
              .join(usda_codes.lazy(), how="left", on="usda_code")
              # Fill in names for unknown functional types
              .with_columns(pl.when(pl.col("usda_code") == "AE")
                            .then(pl.lit("algae"))
                            .when(pl.col("usda_code") == "LI")
                            .then(pl.lit("lichen"))
                            .when(pl.col("usda_code") == "PF")
                            .then(pl.lit("forb"))
                            .otherwise(pl.col("name_original"))
                            .alias("name_original")
                            )
              # Join with AKVEG taxonomy table to obtain accepted names
              .join(taxonomy_checklist.lazy(), how="left", left_on="name_original", right_on="taxon_name")
              # Manually resolve names with no matches in taxonomy table
              .with_columns(pl.when(pl.col("name_original") == "Cephalozia loitlesbergeri")
                            .then(pl.lit("Cephalozia"))
                            .when(pl.col("name_original") == "Vaccinium oxycoccos")
                            .then(pl.lit("Oxycoccus microcarpus"))
                            .when(pl.col("name_original") == "Betula ×dugleana")
                            .then(pl.lit("Betula cf. occidentalis"))
                            .when(pl.col("name_original") == "Betula ×eastwoodiae")
                            .then(pl.lit("Betula cf. occidentalis"))
                            .when(pl.col("name_original") == "Polygonum bistorta")
                            .then(pl.lit("Bistorta plumosa"))
                            .when(pl.col("name_original") == "Dryas octopetala")
                            .then(pl.lit("Dryas ajanensis ssp. beringensis"))
                            .when(pl.col("name_original") == "Saxifraga bronchialis")
                            .then(pl.lit("Saxifraga funstonii"))
                            .when(pl.col("name_original") == "Carex pyrenaica")
                            .then(pl.lit("Carex micropoda"))
                            .otherwise(pl.col("name_adjudicated"))
                            .alias("name_adjudicated")
                            )
              .collect()
              )

# Explore USDA codes that did not return a match when joined with taxonomy table
## One 2-letter code (HW, n=4 hits) and several codes that end in '86'. Not sure what those might be?
unmatched_codes = (cover_taxa
                   .filter(pl.col("name_original").is_null())
                   .select(["usda_code"])
                   .to_series()
                   .value_counts()
                   .sort("count", descending=True)
                   )

## Reconcile entries to unknown for now (n=370)
vegcover_taxa = (vegcover_taxa.with_columns(pl.when(pl.col("name_original").is_null())
                                            .then(pl.lit("unknown"))
                                            .otherwise(pl.col("name_original"))
                                            .alias("name_original"))
                 .with_columns(pl.when(pl.col("name_original") == "unknown")
                               .then(pl.lit("unknown"))
                               .otherwise(pl.col("name_adjudicated"))
                               .alias("name_adjudicated")
                               )
                 )

## Explore USDA scientific names that did not match with AKVEG Checklist
unmatched_sci_names = (vegcover_taxa
                       .filter(pl.col("name_adjudicated").is_null())
                       .unique(subset="name_original")
                       .select("name_original")
                       )  ## All names have been corrected

# --- Calculate percent cover ---

# Define grouping columns
## group_columns_points is used to count the number of unique species observed at each point number
## group_columns_plots is used to summarize the total number of hits per species per plot/site visit
group_columns_points = [
    "site_visit_code",
    "point_number",
    "name_original",
    "name_adjudicated",
    "dead_status"
]

group_columns_plots = [
    "site_visit_code",
    "name_original",
    "name_adjudicated",
    "dead_status"
]

# Calculate cover percent for each species and site visit
vegcover_final = (vegcover_taxa
                  .lazy()
                  ## Get list of unique species per point
                  .unique(subset=group_columns_points)

                  ## Create constant column with value of 1 to calculate number of times the species was observed
                  # across all points
                  .with_columns(pl.lit(1).alias("observation_marker"))

                  # Calculate total number of hits per species per site visit
                  .group_by(group_columns_plots).agg(pl.col("observation_marker").sum())

                  # Get maximum number of points per plot
                  .join(number_of_points.lazy(), how="left", on="site_visit_code")

                  # Calculate percent cover
                  .with_columns((pl.col("observation_marker") / pl.col("max_hits") * 100)
                                .round(3)
                                .alias("cover_percent"))

                  # Populate remaining columns
                  .with_columns(pl.lit("absolute foliar cover").alias("cover_type"))

                  # Sort and select columns
                  .sort(["site_visit_code", "name_original"])
                  .select(template.columns)

                  .collect()
                  )

# QC
print(vegcover_final.describe())  ## Ensure no null values, range of % cover between 0-100%

# Are the correct number of sites included?
set_cover = set(vegcover_final.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_original.get_column("site_visit_code").unique().to_list())
print(set_cover == set_visit)

# Export data
vegcover_final.write_csv(vegcover_output)

# Close database connection
db_conn.close()
