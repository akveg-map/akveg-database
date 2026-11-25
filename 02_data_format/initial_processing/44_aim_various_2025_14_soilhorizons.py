# -*- coding: utf-8 -*-
"""Process Soil Horizozons Table for BLM AIM 2022–2025 data

Combines data from tables in the BLM Riparian AIM GeoDatabase. Appends unique site identifiers, re-classifies
categorical values, converts missing values to designated missing value codes, and performs quality control checks
before exporting to CSV for ingestion into the AKVEG Database.

Author: Amanda Droghini, Alaska Center for Conservation
Last Updated: 2026-11-25
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
from functools import reduce

import polars as pl
import polars.selectors as cs
from pyogrio import read_dataframe

from user_tools.utils_database import connect_database_postgresql, query_to_dataframe
from user_tools.utils_init import load_system_paths
from utils.utils import clean_aim_table, get_template, get_valid_values

# -------- Set Up Environment ------------------------------------------
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"
COLUMNS_RENAME_MAP = {"horizon": "horizon_order",
                      "HorizonDepthUpper": "depth_upper_cm",
                      "HorizonDepthLower": "depth_lower_cm",
                      "Texture": "soil_texture_code",
                      "MatrixHue": "matrix_hue",
                      "MatrixValue": "matrix_value",
                      "MatrixChroma": "matrix_chroma",
                      "GravelFragVolPct": "gravel_percent",
                      "CobblesFragVolPct2": "cobble_percent",
                      "StonesFragVolPct3": "stone_percent"
                      }

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'

# Define output
horizons_output = plot_folder / '14_soilhorizons_aimvarious2025.csv'

# Connect to AKVEG Database
db_conn = connect_database_postgresql(paths.cloud_assets.credentials)

# -------- Load CSV Files -----------------------------------------
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = get_template("soil_horizons")

# -------- Load GeoDatabase Tables -------------------------------------
gdb_dict = {
    "AIM_Wetland__F_SoilPitHorizons": ["EvaluationID", "horizon", "HorizonDepthUpper", "HorizonDepthLower",
                                       "MatrixHue", "MatrixValue", "MatrixChroma", "Texture", "GravelFragVolPct",
                                       "CobblesFragVolPct2", "StonesFragVolPct3", "HorizonComments"],
    "AIM_Wetland__F_Soils": ["EvaluationID", "PitImpenetrable"]
}

gdb_tables = {
    layer_name: pl.DataFrame(read_dataframe(gdb_input, layer=layer_name, columns=cols,
                                            read_geometry=False, use_arrow=True))
    for layer_name, cols in gdb_dict.items()
}

# Join tables using "left" join to keep only entries with horizons data
horizons_original = reduce(lambda left, right: left.join(right, on="EvaluationID", how="left"),
                           gdb_tables.values())

# Lightly clean table & append site visit code
horizons = clean_aim_table(horizons_original, site_visit_table=visit_original,
                           exclude_cols=["MatrixHue"]).rename(COLUMNS_RENAME_MAP, strict=False)

# -------- Prepare Input Data ------------------------------------------

# Explore range of numeric values
horizons.select(cs.numeric()).describe()

# Evaluate depth extend
# depth_extend is True if 'PitImpenetrable' is Yes
# Can only be True for the deepest horizon (highest number); all other horizons are False
print(horizons.select("PitImpenetrable").unique())  # Ensure no null values
horizons = (horizons.with_columns(pl.col("horizon_order").max().over("site_visit_code").alias("max_horizon"))
            .with_columns(pl.when((pl.col("PitImpenetrable") == "yes") &
                                  (pl.col("horizon_order") == pl.col("max_horizon")))
                          .then(pl.lit("TRUE"))
                          .otherwise(pl.lit("FALSE"))
                          .alias("depth_extend")
                          ))

# Calculate horizon thickness
# Thickness is -999 is depth_extend is TRUE (measurement hindered by presence of restrictive layer)
horizons = horizons.with_columns(pl.when(pl.col("depth_extend") == "FALSE")
                                 .then((pl.col("depth_lower_cm") - pl.col("depth_upper_cm")))
                                 .otherwise(pl.lit(-999))
                                 .alias("thickness_cm"))

# Re-classify texture
soil_texture = pl.from_pandas(query_to_dataframe(db_conn, """SELECT * FROM soil_texture"""))
horizons = (horizons.join(soil_texture, on="soil_texture_code", how="left")
            .rename({"soil_texture": "texture"}))

# Ensure all null values make sense
# FO, HO, and SO are organic horizons; in AKVEG, these horizons cannot have a texture
print(horizons.filter(pl.col("texture").is_null()).select("soil_texture_code").unique())

# Convert matrix value and matrix chroma to numeric
horizons = horizons.with_columns(pl.col("matrix_value").cast(pl.Decimal(3, 1)),
                                 pl.col("matrix_chroma").cast(pl.Int16))

# Ensure all matrix hue values exist in the AKVEG Database Dictionary
valid_hue_values = get_valid_values(db_conn, "soil_hue", "soil_hue")
dataset_hue_values = set(horizons.get_column("matrix_hue").unique().to_list())
invalid_hue_values = dataset_hue_values - valid_hue_values
print(invalid_hue_values)

# -------- Add Missing Columns -----------------------------------------

horizons = (horizons.with_columns(horizon_primary=pl.lit("NULL"),
                                  horizon_suffix_1=pl.lit("NULL"),
                                  horizon_suffix_2=pl.lit("NULL"),
                                  horizon_secondary=pl.lit("NULL"),
                                  horizon_suffix_3=pl.lit("NULL"),
                                  horizon_suffix_4=pl.lit("NULL"),
                                  structure=pl.lit("NULL"),
                                  clay_percent=pl.lit(-999),
                                  boulder_percent=pl.lit(-999),
                                  total_coarse_fragment_percent=pl.lit(-999),
                                  nonmatrix_feature=pl.lit("NULL"),
                                  nonmatrix_hue=pl.lit("NULL"),
                                  nonmatrix_value=pl.lit(-999),
                                  nonmatrix_chroma=pl.lit(-999)
                                  )
            .select(template.columns)
            # Replace nulls with appropriate missing value codes
            .with_columns(cs.string().fill_null(value="NULL"),
                          cs.numeric().fill_null(value=-999))
            )

# -------- Perform Quality Checks --------------------------------------

# Identify visit codes that are missing from the Soil Horizons table
set_horizons = set(horizons.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_original.get_column("site_visit_code").unique().to_list())
print(set_visit - set_horizons)

# Ensure no null values
print(horizons.select(cs.numeric()).null_count())
print(horizons.select(cs.numeric()).describe())

## Ensure that categorical variables match constrained values in database dictionary
horizons_final.texture.unique()
horizons_final.structure.unique()
horizons_final.matrix_hue.unique()

## Verify that range of values are reasonable i.e., bounded between 0-100
horizons_table.gravel_percent.describe()
horizons_table.cobble_percent.describe()
horizons_table.stone_percent.describe()
horizons_table.total_coarse_fragment_percent.describe()

# Check matrix
horizons_table.MatrixHue.unique()
horizons_table.MatrixChroma.unique()
horizons_table.MatrixValue.unique()
horizons_table[['MatrixHue', 'MatrixChroma', 'MatrixValue']].isnull().sum()

## Replace null values with -999
horizons_table.update(horizons_table[['gravel_percent', 'cobble_percent', 'total_coarse_fragment_percent',
                                      'stone_percent']].fillna(-999))

# -------- Export Data -------------------------------------------------
horizons_final.to_csv(horizons_table_output, index=False, encoding='UTF-8')

# -------- Close Database Connection -----------------------------------
db_conn.close()
