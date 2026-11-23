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
import polars as pl
from pyogrio import read_dataframe

from user_tools.utils_init import load_system_paths
from utils.utils import clean_aim_table, get_template

# -------- Set Up Environment ------------------------------------------
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"

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
                                       "CobblesFragVolPct3", "StonesFragVolPct4", "HorizonComments"]
}

gdb_tables = {
    layer_name: pl.DataFrame(read_dataframe(gdb_input, layer=layer_name, columns=cols,
                                            read_geometry=False, use_arrow=True))
    for layer_name, cols in gdb_dict.items()
}

horizons_original = gdb_tables["AIM_Wetland__F_SoilPitHorizons"]

# Lightly clean table & append site visit code
horizons = clean_aim_table(horizons_original, site_visit_table=visit_original, exclude_cols=["MatrixHue"])

# -------- Prepare Input Data ------------------------------------------
# Format horizon order
horizons_table.horizon.value_counts()
horizons_table.horizon.isnull().sum()  # Ensure there are no null values
horizons_table.rename(columns={'horizon': 'horizon_order'}, inplace=True)

# Format upper and lower depth
horizons_table[['HorizonDepthUpper', 'HorizonDepthLower']].describe()
horizons_table[['HorizonDepthUpper', 'HorizonDepthLower']].isnull().sum()  # Ensure there are no null values
horizons_table.rename(columns={'HorizonDepthUpper': 'depth_upper',
                               'HorizonDepthLower': 'depth_lower'},
                      inplace=True)

# Calculate depth extend
## Find max horizon order for each plot
horizons_table['max_horizon'] = horizons_table.groupby('PlotID')['horizon_order'].transform('max')

## Set depth_extend as TRUE is 'PitImpenetrable' is Yes
## The value can only be TRUE for the lowest measured horizon; all other horizons are FALSE.
horizons_table['depth_extend'] = 'FALSE'
horizons_table['depth_extend'] = np.where(
    (horizons_table['horizon_order'] == horizons_table['max_horizon'])
    & (horizons_table['PitImpenetrable'] == 'Yes'),
    'TRUE',
    horizons_table['depth_extend'])

# Calculate horizon thickness
## Thickness is -999 is depth_extend is TRUE (measurement hindered by presence of restrictive layer)
horizons_table['thickness_cm'] = horizons_table['depth_lower'] - horizons_table['depth_upper']
horizons_table['thickness_cm'] = np.where(
    (horizons_table['depth_extend'] == 'TRUE'), -999,
    horizons_table['thickness_cm'])

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

temp = horizons_final.describe(include='all')

## Ensure that categorical variables match constrained values in database dictionary
horizons_final.texture.unique()
horizons_final.structure.unique()
horizons_final.matrix_hue.unique()

# -------- Export Data -------------------------------------------------
horizons_final.to_csv(horizons_table_output, index=False, encoding='UTF-8')
