# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format NRCS Alaska 2024 Project
# Author: Amanda Droghini
# Last Updated: 2025-11-05
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format NRCS Alaska 2024 Project Data" identifies, classifies, and ultimately excludes duplicate site
# visits. Duplicates are defined as site visits that have the same coordinates and the same observation dates. The
# script defines and executes a function, classify_duplicates(), to classify duplicates into three types: true
# duplicates, duplicates with minor differences, and duplicates with major differences. The script excludes
# duplicates with major differences from the Site, Site Visit, and Vegetation Cover tables. It depends upon the
# outputs from 34_nrcs_02_03_site.py and 34_nrcs_05_vegetationcover.py.
# ------

# Import packages
import polars as pl
from pathlib import Path
from typing import List

# ----------------------------------------------------------------------
# Define function for classifying duplicates
def classify_duplicates(
    plot_ids: List[str],
    duplicate_df: pl.DataFrame,
    cover_original: pl.DataFrame):
    """
    Compares vegetation cover data for duplicate site pairs and classifies them into three groups:
    Type 1: True duplicates with identical cover data.
    Type 2: Duplicates with only one minor difference in the cover data (one non-matching entry with <1% cover).
    Type 3: Duplicates with more than one difference or one difference with cover >= 1%.

    Args:
        plot_ids: List of unique duplicate IDs to iterate over.
        duplicate_df: DataFrame linking duplicate_id to site_visit_code.
        cover_original: DataFrame containing the vegetation cover data.
    """

    # Create empty lists for saving results
    identical_pairs = []
    different_pairs = []

    for plot in plot_ids:
        # Isolate the two site visit codes for the current duplicate plot
        duplicate_group = duplicate_df.filter(pl.col("duplicate_id") == plot)
        visit_code = duplicate_group["site_visit_code"].unique().to_list()

        # Ensure we have exactly two site codes to compare
        if len(visit_code) != 2:
            print(f"Skipping plot {plot}: Found {len(visit_code)} site codes instead of 2.")
            continue

        vc_1, vc_2 = visit_code[0], visit_code[1]

        # Prepare the data subsets for comparison
        ## Ensure subsets have the same sort order
        base_processing = lambda df: (
            df
            .drop("site_visit_code")
            .sort(by=["name_original"])
        )

        site_1 = base_processing(cover_original.filter(pl.col("site_visit_code") == vc_1))
        site_2 = base_processing(cover_original.filter(pl.col("site_visit_code") == vc_2))

        # Check 1: Rows in site_1 NOT in site_2
        diff_1_not_2 = site_1.join(site_2, on=site_1.columns, how="anti")
        # Check 2: Rows in site_2 NOT in site_1
        diff_2_not_1 = site_2.join(site_1, on=site_2.columns, how="anti")

        # Combine the differences to get the total number of non-matching rows
        combined_diff = pl.concat([diff_1_not_2, diff_2_not_1])

        if combined_diff.shape[0] == 0:
            print(f"IDENTICAL: {plot} (Visits: {vc_1} vs {vc_2}) - Cover data matches.")
            identical_pairs.append((plot, vc_1, vc_2, "keep_one"))
        elif combined_diff.shape[0] == 1 and combined_diff.item(0, 'cover_percent') < 1:
            print(f"MINOR DIFF: {plot} (Visits: {vc_1} vs {vc_2}) - Found {combined_diff.shape[0]} difference.")
            identical_pairs.append((plot, vc_1, vc_2, "one_difference"))
        else:
            different_pairs.append((plot, vc_1, vc_2, "drop_sites"))

    return identical_pairs, different_pairs
# ----------------------------------------------------------------------

# Define directories
drive = Path('C:/')
root_folder = drive / 'ACCS_Work'

# Define folders
project_folder = root_folder / 'OneDrive - University of Alaska' / 'ACCS_Teams' / 'Vegetation' / 'AKVEG_Database' / 'Data'
plot_folder = project_folder / 'Data_Plots' / '34_nrcs_soils_2024'
workspace_folder = plot_folder / 'working'

# Define inputs
site_input = workspace_folder / '02_site_nrcssoils2024.csv'
visit_input = workspace_folder / '03_sitevisit_nrcssoils2024.csv'
cover_input = workspace_folder / '05_vegetationcover_nrcssoils2024.csv'

# Define outputs
site_output = plot_folder / '02_site_nrcssoils2024.csv'
visit_output = plot_folder / '03_sitevisit_nrcssoils2024.csv'
cover_output = plot_folder / '05_vegetationcover_nrcssoils2024.csv'

# Read in data
site_original = pl.read_csv(site_input)
visit_original = pl.read_csv(visit_input)
cover_original = pl.read_csv(cover_input)

# Join site and site visit tables
visit = visit_original.join(site_original, on="site_code", how="inner")
print(visit.shape[0] == visit_original.shape[0] == site_original.shape[0])

# Define subset of columns on which to evaluate duplicates
duplicate_cols = ["latitude_dd", "longitude_dd", "observe_date"]

# Identify duplicate sites
duplicate_df = (visit.lazy()
                # Group by the key columns
                .group_by(duplicate_cols)
                # Count the number of rows in each group, renaming the new column to 'count'
                .agg(pl.len().alias("count"))
                # Filter to keep only the groups where the count is greater than 1
                .filter(pl.col("count") > 1)
                # Create unique identifier to identify duplicate pairs
                ## Do not use vegplotid b/c in some cases the vegplotids are different
                .with_columns(pl.int_range(pl.len(), dtype=pl.UInt32).alias("index"))
                .with_columns((pl.lit("plot_") + pl.col("index").cast(pl.String))
                              .alias("duplicate_id"))
                # Re-join with visit df to obtain site_code and other columns that were dropped in the .group_by() process
                .join(
    visit.lazy(),
    on=duplicate_cols,
    how="inner"
)
                .sort(pl.col("duplicate_id"))
                .collect()
                )

# Determine whether duplicate sites have the same species list + cover
plot_ids = duplicate_df["duplicate_id"].unique().to_list()

# Classify duplicate types
identical_pairs, different_pairs = classify_duplicates(plot_ids, duplicate_df, cover_original)

# Define desired columns in combined dataframe
columns_pairs = ["plot_id", "visit_code_1", "visit_code_2", "action"]

# Convert lists to dataframes
identical_df = pl.DataFrame(identical_pairs, schema=columns_pairs, orient="row")
different_df = pl.DataFrame(different_pairs, schema=columns_pairs, orient="row")

# For identical sites, drop one of each pair
## Replace site codes that we are keeping with 'null', allowing us to easily filter out those entries when combining
# the results with different_df
identical_df = identical_df.with_columns(pl.lit("null")
                                         .alias("visit_code_1")
                                         )

# Generate complete list of site visits to exclude in long format to match formatting of input dataframes
site_exclude = (pl.concat(
    [identical_df, different_df])
.unpivot(on=["visit_code_1", "visit_code_2"],
         index=["plot_id", "action"],
         value_name="site_visit_code")
.filter(pl.col("site_visit_code") != "null")
.with_columns(pl.col("site_visit_code").str.extract(r"([a-z]{4}_\d*)(_)").alias("site_code"))
.select(
    ['site_visit_code', 'site_code'])
)

# Drop sites from Site, Site Visit, and Cover tables
site_unique = site_original.join(site_exclude, on="site_code", how="anti")
visit_unique = visit_original.join(site_exclude, on="site_visit_code", how="anti")
cover_unique = cover_original.join(site_exclude, on="site_visit_code", how="anti")

# Export as CSV
site_unique.write_csv(site_output)
visit_unique.write_csv(visit_output)
cover_unique.write_csv(cover_output)
