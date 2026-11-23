# -*- coding: utf-8 -*-
"""Process Soil Horizozons Table for BLM AIM 2022–2025 data

Combines data from tables in the BLM Riparian AIM GeoDatabase. Appends unique site identifiers, re-classifies
categorical values, converts missing values to designated missing value codes, and performs quality control checks
before exporting to CSV for ingestion into the AKVEG Database.

Author: Amanda Droghini, Alaska Center for Conservation
Last Updated: 2026-11-23
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
from functools import reduce

import polars as pl
import polars.selectors as cs
from pyogrio import read_dataframe

from user_tools.utils_init import load_system_paths
from utils.utils import clean_aim_table, get_template

# -------- Set Up Environment ------------------------------------------
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"
COLUMNS_RENAME_MAP = {"horizon": "horizon_order",
                      "HorizonDepthUpper": "depth_upper",
                      "HorizonDepthLower": "depth_lower",
                      "Texture": "texture",
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
                                 .then((pl.col("depth_lower") - pl.col("depth_upper")))
                                 .otherwise(pl.lit(-999))
                                 .alias("thickness_cm"))

## Format soil texture
# Replace values that aren't present in the data dictionary (FO, HO, and SO) with NULL
# Replace texture codes with values
horizons_table.Texture.value_counts()

conditions = [horizons_table['Texture'] == 'SIL',
              horizons_table['Texture'] == 'SL',
              horizons_table['Texture'] == 'LS',
              horizons_table['Texture'] == 'SICL',
              horizons_table['Texture'] == 'SCL',
              horizons_table['Texture'] == 'S']
choices = ['silt loam', 'sandy loam', 'loamy sand', 'silty clay loam', 'sandy clay loam', 'sand']
horizons_table['texture'] = np.select(conditions, choices, default='NULL')

# Format rock fragments

## Rename columns
horizons_table.rename(columns={"GravelFragVolPct": "gravel_percent", "CobblesFragVolPct2": "cobble_percent",
                               'RockFragments': 'total_coarse_fragment_percent', 'StonesFragVolPct3': 'stone_percent'},
                      inplace=True)

## Verify that range of values are reasonable i.e., bounded between 0-100
horizons_table.gravel_percent.describe()
horizons_table.cobble_percent.describe()
horizons_table.stone_percent.describe()
horizons_table.total_coarse_fragment_percent.describe()

## Replace null values with -999
horizons_table.update(horizons_table[['gravel_percent', 'cobble_percent', 'total_coarse_fragment_percent',
                                      'stone_percent']].fillna(-999))

# Format matrix characteristics
## No reclassification needed. Chroma: integer between 0 and 8, Value: between 0 and 10
horizons_table.MatrixHue.unique()
horizons_table.MatrixChroma.unique()
horizons_table.MatrixValue.unique()
horizons_table[['MatrixHue', 'MatrixChroma', 'MatrixValue']].isnull().sum()

## Convert chroma and value to appropriate data type
horizons_table[["matrix_value", "matrix_chroma"]] = horizons_table[["MatrixValue", "MatrixChroma"]].apply(pd.to_numeric)

## Rename matrix hue column
horizons_table.rename(columns={'MatrixHue': 'matrix_hue'}, inplace=True)

# Populate values for missing columns
horizons_final = horizons_table.assign(horizon_primary='NULL', horizon_suffix_1='NULL', horizon_suffix_2='NULL',
                                       horizon_secondary='NULL', horizon_suffix_3='NULL', horizon_suffix_4='NULL',
                                       structure='NULL',
                                       clay_percent=-999,
                                       boulder_percent=-999,
                                       nonmatrix_feature='NULL',
                                       nonmatrix_hue='NULL', nonmatrix_value=-999, nonmatrix_chroma=-999)

# Final formatting
## Drop all columns that aren't in the template and reorder them to match data entry template
horizons = horizons[template.columns]

# -------- Perform Quality Checks --------------------------------------

# Identify visit codes that are missing from the Soil Horizons table
set_horizons = set(horizons.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_original.get_column("site_visit_code").unique().to_list())
print(set_visit - set_horizons)

# Ensure no null values
print(horizons.select(cs.numeric()).null_count())

temp = horizons_final.describe(include='all')

## Ensure that categorical variables match constrained values in database dictionary
horizons_final.texture.unique()
horizons_final.structure.unique()
horizons_final.matrix_hue.unique()

# -------- Export Data -------------------------------------------------
horizons_final.to_csv(horizons_table_output, index=False, encoding='UTF-8')
