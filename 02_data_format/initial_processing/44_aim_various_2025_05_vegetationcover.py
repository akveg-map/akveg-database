# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Vegetation Cover Table for BLM AIM 2022–2025 data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-10-08
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
codes_input = paths.cloud_assets.taxonomy / 'USDA_Plants' / '2021_AK_AIM_SpeciesList_AKVEG_Formatted.xlsx'
resolved_names_input = (paths.repository / "02_data_format" / "crosswalks" /
                        "44_aim_various_2025_name_original_adjudicated.csv")

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
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])

# Read in crosswalk files
codes_original = pl.read_excel(codes_input, columns=["name", "scientific_akveg"])
resolved_names_original = pl.read_csv(resolved_names_input)

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
cover_long = (species_long.join(dead_long,
                                on=id_cols + ["strata"],
                                how="left")
              .sort(["site_visit_code", "point_number"])
              )

# --- Obtain accepted taxonomic names ----

# Obtain taxonomy checklist from the AKVEG Database
taxonomy_checklist = get_taxonomy(simple=True)

# Extract unknown codes (ending in '86') or functional group codes (two letters) from AIM species list
unknown_codes = (codes_original
                 .filter((pl.col("name").str.contains(r"86$")) | (pl.col("name").str.contains(r"^[A-Z]{2}$")))
                 .rename({"name": "usda_code",
                          "scientific_akveg": "name_original"}))

# Get USDA plant codes
usda_codes = get_usda_codes()

# Add unknown codes to USDA df
usda_codes = pl.concat([usda_codes, unknown_codes])

# Convert mapping CSV to dictionary
resolved_names_dict = dict(
    zip(
        resolved_names_original["name_original"],
        resolved_names_original["name_adjudicated"],
    )
)

# Translate USDA codes to accepted scientific names
cover_taxa = (cover_long.lazy()
              # Join cover df to USDA plant codes to obtain scientific names
              .join(usda_codes.lazy(), how="left", on="usda_code")
              # Fill in names for unknown functional types
              .with_columns(pl.when(pl.col("usda_code") == "M")  # Unresolvable (moss, hornwort, or liverwort)
                            .then(pl.lit("unknown"))
                            .when(pl.col("usda_code") == "POACEA")
                            .then(pl.lit("grass (Poaceae)"))
                            .otherwise("name_original")
                            .alias("name_original")
                            )
              # Join with AKVEG taxonomy table to obtain accepted names
              .join(taxonomy_checklist.lazy(), how="left", left_on="name_original", right_on="taxon_name")
              # Resolve remaining names with no matches in taxonomy table
              .with_columns(pl.col("name_original").replace(resolved_names_dict)
                            .alias("name_resolved")
                            )
              .with_columns(pl.when(pl.col("name_adjudicated").is_null())
                            .then(pl.col("name_resolved"))
                            .otherwise("name_adjudicated")
                            .alias("name_adjudicated")
                            )
              .collect()
              )

# Explore USDA codes that did not return a match when joined with taxonomy table
unmatched_codes = (cover_taxa
                   .filter(pl.col("name_original").is_null())
                   .select(["usda_code"])
                   .to_series()
                   .value_counts()
                   .sort("count", descending=True)
                   )

# Reconcile entries to unknown for now (n=228)
cover_taxa = (cover_taxa.with_columns(pl.when(pl.col("name_original").is_null())
                                      .then(pl.lit("unknown"))
                                      .otherwise(pl.col("name_original"))
                                      .alias("name_original"))
              .with_columns(pl.when(pl.col("name_original") == "unknown")
                            .then(pl.lit("unknown"))
                            .otherwise(pl.col("name_adjudicated"))
                            .alias("name_adjudicated")
                            )
              )

# Ensure all nulls have been resolved
print(cover_taxa.select(["name_original", "name_adjudicated"]).null_count().glimpse())

# --- Calculate percent cover ---

# Define grouping columns
## group_columns_points: Used to count the number of unique species observed at each point number. Ensures that if
# the same species with the same dead status is recorded twice on the same point (e.g., in Lower1 and Basal),
# it only gets counted once for that point.
## group_columns_plots: Used to summarize the total number of hits per species per plot (site visit)
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
cover_final = (cover_taxa
               .lazy()
               # Get list of unique species per point
               .unique(subset=group_columns_points)

               # Create constant column with value of 1 to calculate number of times the species was observed
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
               .select(template.columns)

               .collect()
               )

# Quality checks

# Ensure no null values
print(cover_final.null_count().glimpse())

# Ensure cover percent is between 0% and 100%
print(cover_final.select(pl.col("cover_percent")).describe())

# Ensure the correct number of sites are included
set_cover = set(cover_final.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_original.get_column("site_visit_code").unique().to_list())
print(set_cover ^ set_visit)  # Test for symmetric difference (i.e., difference in either direction)

# Export data
cover_final.write_csv(cover_output)

# Close database connection
db_conn.close()
