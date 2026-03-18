# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Vegetation Cover Table for USFWS Yukon Flats 2025 data
# Author: Amanda Droghini
# Last Updated: 2026-03-11
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Vegetation Cover Table for USFWS Yukon Flats 2025 data" uses data from line-point intercept surveys
# to calculate site-level percent foliar cover for each recorded species. It appends unique site visit
# identifiers, corrects taxonomic names using the AKVEG taxonomic standard,
# populates required metadata fields, and performs QC checks. The output is a CSV table that can be converted and included in a
# SQL INSERT statement.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
from pathlib import Path
from utils import get_taxonomy, get_template

# Define directories
drive = Path('C:/')
root_folder = drive / 'ACCS_Work'

# Define folders
project_folder = root_folder / 'OneDrive - University of Alaska' / 'ACCS_Teams' / 'Vegetation' / 'AKVEG_Database' / 'Data'
plot_folder = project_folder / 'Data_Plots' / '55_fws_yukonflats_2025'

# Define inputs
lpi_input = plot_folder / 'source' / '05_usfws_yukonflats_2025_LPI.xlsx'
trace_input = plot_folder / 'source' / '05_usfws_yukonflats_2025_trace.xlsx'
visit_input = plot_folder / '03_sitevisit_fwsyukonflats2025.csv'

# Define output
veg_output = plot_folder / '05_vegetationcover_fwsyukonflats2025.csv'

# Define taxon mapping dictionary
## Used to correct field identifications (misspellings or misidentifications)
taxon_mapping = {
    "carath": "carathe",
    "caratr": "carutr",
    "trimar": "trimara",
    "salsim": "solsim",
    "parpan": "parpal",
    "galtri": "galtristri",
    "salpsema": "salpsea",
    "salpse": "salpsea",
    "sciacu": "schacu",
    "scaacu": "schacu",
    "epipul": "epipal",
    "camang": "chaang",
    "horbra": "×elmac",
    "junarc": "junbalsate",
    "antfre": "antros",
    "pedfri": "petfri",
    "brachy": "brachyt",
    "callie": "calliergn",
    "vaclug": "vaculi",
    "vaclig": "vaculi",
    "paltig": "peltig",
    "sclfes": "scofes",
    "achpta": "achsib",
    "salnic": "salnip",
    "erytra": "elytra",
    "eutmin": "utrmin",
    "glymax": "pucbor",
    "panpal": "parpal",
    "barbal": "parpal",
    "tripol": "tripal",
    "zygela": "zygele",
    "wetmos": "fgmosbro",
    "scnoug": "uforb",
    "leurot": "uforb",
    "pamnit": "tomnit",
    "equstr": "equise",
    "camcal": "chacal"
}

# Define abiotic element codes to drop
abiotic_elements = ["l", "s", "o", "wl", "w", "bc"]

# Define function to correct taxonomic codes and obtain taxonomic name from AKVEG checklist
def get_taxon_names(lf: pl.LazyFrame, checklist: pl.LazyFrame) -> pl.LazyFrame:
    """Applies taxonomic corrections and joins with AKVEG checklist."""
    return(
        lf.with_columns(
            pl.col("taxon_code")
            .replace_strict(taxon_mapping, default=pl.col("taxon_code"))
        )
        .join(checklist, how="left", on="taxon_code")
        .rename({"taxon_name":"name_original"})
    )

# Read in data
lpi_original = pl.read_excel(lpi_input)
trace_original = pl.read_excel(trace_input)
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = get_template("vegetation_cover")

# Obtain taxonomy checklist from the AKVEG Database
taxonomy_checklist = get_taxonomy(simple=True).lazy()

# Load and format trace data
trace = (trace_original.lazy()
         # Format site and taxon codes
         .with_columns(pl.col("site_code").str.replace_all("_", ""),
                       pl.col("taxon_code").str.to_lowercase(),
                       pl.lit("FALSE").alias("dead_status"))
         # Append site visit code using inner join to drop plots excluded from site visit table
         .join(visit_original.lazy(), on="site_code", how="inner")
         .drop("site_code")
         )

# Load and format LPI data
vegcover = (
    lpi_original.lazy()
    # Format site code
    .with_columns(pl.col("site_code").str.replace_all("_", ""))
    # Append site visit code
    .join(visit_original.lazy(), on="site_code", how="inner")
    # Create a sequential row number for each site visit
    .sort(by=["site_visit_code", "line", "point"])
    .with_columns(pl.int_range(1, pl.len() + 1).alias("point_number")
                  .over("site_visit_code"))
    .collect()
)

# Manually review any sites that don't have LPI data
missing_lpi_sites = (
    visit_original.lazy()
    .join(lpi_original.lazy().with_columns(pl.col("site_code").str.replace_all("_", "")),
          on="site_code",
          how="anti")
    .collect()
)
print(missing_lpi_sites.height)  ## Nothing to review

# --- Calculate number of points per plot ---
## Plots should have 120 points
number_of_points = (vegcover
                    .group_by("site_visit_code")
                    .agg(pl.col("point_number")
                         .max())
                    .rename({"point_number": "max_hits"})
                    )
print(number_of_points.describe())

# --- Convert to long format ---

# Identify groups of columns
species_cols = vegcover.select(pl.col(["^layer_\\d$"])).columns
id_cols = ["site_visit_code", "point_number"]

# Melt species codes columns
species_long = (
    vegcover.lazy()
    .unpivot(
        on=species_cols,
        index=id_cols,
        variable_name="strata",
        value_name="taxon_code",
    )
    # Format dead status
    .with_columns(pl.when(pl.col("taxon_code").str.ends_with("-D"))
                  .then(pl.lit("TRUE"))
                  .otherwise(pl.lit("FALSE"))
                  .alias("dead_status"))
    # Join with trace species

    # Remove basal & dead code, convert to lowercase
    .with_columns(pl.col("taxon_code").str.replace(pattern=r"-[BD]", value="").str.to_lowercase())
    # Drop nulls and abiotic elements
    .filter(pl.col("taxon_code").is_not_null()
            .and_(~pl.col("taxon_code").is_in(abiotic_elements))
            )
    # Sort by site visit code
    .sort(by=["site_visit_code", "point_number"])
    .drop("strata")
)

# --- Obtain accepted taxonomic names ----

vegcover_taxa = get_taxon_names(species_long, taxonomy_checklist)
trace_taxa = get_taxon_names(trace, taxonomy_checklist)

# Explore taxon codes that did not match with an AKVEG code
unmatched_taxa = (pl.concat([vegcover_taxa.select(["taxon_code", "name_original"]),
                             trace_taxa.select(["taxon_code", "name_original"])])
                  .filter(pl.col("name_original").is_null())
                  .select("taxon_code")
                  .unique()
                  .sort("taxon_code")
                  .collect()
                  )

## Reconcile unmatched LPI entries to unknown for now (n=22)
vegcover_taxa = (vegcover_taxa.with_columns(pl.col("name_original").fill_null("unknown"),
                                            pl.col("name_adjudicated").fill_null("unknown"))
                 )

# Drop unmatched code (n=1) in trace
trace_taxa = (trace_taxa.filter(pl.col("name_original").is_not_null())
              .with_columns(pl.col("name_original").alias("name_adjudicated"))
              .drop("taxon_code")
              .collect()
              )

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
                  .select(trace_taxa.columns)
                  .collect()
                  )

# --- Combine with trace data ---
# If entries exist in both LPI and trace dfs, prioritize the one with the highest cover
combined_df = pl.concat([vegcover_final, trace_taxa])

# Prioritize by sorting and remove duplicates
merged_df = (
    combined_df
    .sort("cover_percent", descending=True)
    .unique(subset=["site_visit_code", "name_original", "dead_status"], keep="first")
    # Populate remaining columns
    .with_columns(pl.lit("absolute foliar cover").alias("cover_type"))
    # Sort and select columns
    .sort(["site_visit_code", "name_original"])
    .select(template.columns)
)

# Verify that estimates of non-vascular survey at B06-05 were correctly included
nv_survey_check = merged_df.filter(pl.col("site_visit_code").str.contains("YKF25B0605"))

# --- Quality checks ---
## Ensure no null values, range of % cover between 0-100%
print(merged_df.describe())
print(merged_df
      .select(["site_visit_code", "name_original", "dead_status"])
      .is_duplicated()
      .sum())
# Are the correct number of sites included?
set_cover = set(merged_df.get_column("site_visit_code").unique().to_list())
set_visit = set(merged_df.get_column("site_visit_code").unique().to_list())
print(set_cover == set_visit)

# Export data
vegcover_final.write_csv(veg_output)
