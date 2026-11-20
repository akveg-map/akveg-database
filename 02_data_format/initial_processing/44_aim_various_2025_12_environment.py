# -*- coding: utf-8 -*-
"""Process Environment Table for BLM AIM 2022–2025 data

Combines data from the BLM Riparian AIM GeoDatabase and from individual CSVs of "supplemental indicators" provided
by BLM Alaska. Appends unique site identifiers, re-classifies categorical values, converts missing values to
designated missing value codes, and performs quality control checks before exporting to CSV for ingestion into the
AKVEG Database.

Author: Amanda Droghini, Alaska Center for Conservation
Last Updated: 2026-11-20
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
from collections import defaultdict
from functools import reduce

import geopandas as gpd
import polars as pl
import polars.selectors as cs

from user_tools.utils_database import connect_database_postgresql
from user_tools.utils_init import load_system_paths
from utils.utils import get_template

# -------- Set Up Environment ------------------------------------------
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"
INDICATORS_RENAME_MAP = {"Overall Site Moisture Regime": "moisture_regime",
                         "Depth of Water (cm)": "depth_water_cm",
                         "Moss/Duff Thickness (cm)": "depth_moss_duff_cm",
                         "Depth Soil to ActiveLayer (cm)": "depth_restrictive_layer_cm",
                         "parentglobalid": "GlobalID"
                         }
SEVERITY_MAPPING = {0: None,
                    1: "low",
                    2: "moderate",
                    3: "high",
                    4: "high"
                    }

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
indicators_input = plot_folder / "source" / "AK_Moss_and_Active_Layer_23Jan2026.xlsx"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'
credentials_input = paths.cloud_assets.credentials

# Define crosswalk inputs
moisture_input = paths.repository / "02_data_format" / "crosswalks" / "44_aim_various_2025_moisture_regime.csv"
disturbance_input = paths.repository / "02_data_format" / "crosswalks" / "44_aim_various_2025_disturbance.csv"

# Define output
envr_output = plot_folder / '12_environment_aimvarious2025.csv'

# Connect to AKVEG Database
db_conn = connect_database_postgresql(credentials_input)

# -------- Load Shapefiles ---------------------------------------------

# Define dictionary (key: layer name, values: column names) for shapefiles in GeoDatabase
gdb_dict = {
    # Site metadata
    "AIM_Wetland__F_PlotCharacterization": ['EvaluationID', 'Elevation_m', 'Slope', 'AlaskaEcotypeClassification',
                                            'LandscapeType', 'LandscapeTypeSecondary', 'VerticalSlopeShape',
                                            'PlotDescription'],
    # Soil horizons
    "AIM_Wetland__F_Soils": ['EvaluationID', 'PitImpenetrable', 'ImpenetrableDescrip', 'WaterObserved', 'WaterDepth',
                             'PitSaturated', 'DepthToSatSoil', 'HydricIndicatorPrimary', 'HydricIndicatorSecondary'],
    # Disturbance metadata
    "AIM_Wetland__F_NaturalandHumanDisturbances": ['EvaluationID', 'DisturbancesObserved'],
    # Disturbance data
    "AIM_Wetland__F_DisturbancesDetail": ['EvaluationID', 'Disturbance', 'OtherDisturbance',
                                          'MonitoringPlotScope', 'MonitoringPlotDegree', 'DisturbanceComment'],
    # Hydrology data
    "AIM_Wetland__F_Hydrology": ['EvaluationID', 'PermafrostInfluence', 'DepthActiveLayer', 'SurfaceWaterPresent',
                                 'SurfaceWaterDepth']
}

# Use dictionary comprehension to iteratively load shapefiles as DataFrames
environment_layers = {
    layer_name: pl.from_pandas(gpd.read_file(gdb_input, layer=layer_name, columns=cols, ignore_geometry=True))
    for layer_name, cols in gdb_dict.items()
}

# Use reduce to sequentially join DataFrames across the list
# AIM_Wetland__F_PlotCharacterization must be the first DataFrame in the list for left join to work (otherwise a full
# join is needed)
environment_original = reduce(
    lambda left, right: left.join(right, on="EvaluationID", how="left"),
    list(environment_layers.values())
)

del gdb_dict, environment_layers

# -------- Load Excel Sheets -------------------------------------------
excel_dict = {"MossActiveLayer 2021": {"cols": ["Office", "Plot ID", "Plot Key", "Overall Site Moisture Regime"],
                                       "year_end": "2021"},
              "MossActiveLayer_Details 2021": {"cols": ["Plot Key",
                                                        "Moss/Duff Thickness (cm)", "Depth of Water (cm)",
                                                        "Depth Soil to ActiveLayer (cm)", "Notes"],
                                               "year_end": "2021"},
              "MossActiveLayer 2022-25": {"cols": ["Plot ID", "Evaluation ID", "GlobalID"],
                                          "year_end": "2025"},
              "MossActiveLayer_Details 2023-25": {"cols": ["parentglobalid", "Moss/Duff Thickness (cm)",
                                                           "Depth of Water (cm)", "Depth Soil to ActiveLayer (cm)",
                                                           "Notes"],
                                                  "year_end": "2025"}
              }

# Read Excel sheets
excel_sheets = pl.read_excel(source=indicators_input, sheet_name=list(excel_dict.keys()))

# Select & rename columns, group sheets by year
subsets_by_year = defaultdict(list)
for sheet, attribute in excel_dict.items():
    year = attribute["year_end"]
    df = excel_sheets[sheet].select(attribute["cols"]).rename(INDICATORS_RENAME_MAP, strict=False)
    # Drop rows without a Plot Key (2 site visits) in 2021 data
    if year == "2021":
        df = df.remove(pl.col("Plot Key") == "<Null>")
    # Combine multiple moisture regime entries into a single row per site visit (moisture regime was taken at each
    # line in 2021)
    if sheet == "MossActiveLayer 2021":
        df = (df.group_by(pl.col("Plot Key"))
              .agg(pl.col("moisture_regime").drop_nulls().unique().str.join(delimiter=", ")))
    # Drop site visits with same Evaluation ID (but different Global ID); measurements cannot be reconciled to unique ID
    if sheet == "MossActiveLayer 2022-25":
        df = df.unique(subset=pl.col("Evaluation ID"), keep="none")
    subsets_by_year[year].append(df)

# Join dataframes of the same year
year_join_keys = {"2021": "Plot Key",
                  "2025": "GlobalID"}

# Use left join to drop measurements associated with duplicate Evaluation ID
indicators_merged_dfs = [
    reduce(lambda left, right: left.join(right, on=year_join_keys[year], how="left"),
           df_list)
    for year, df_list in subsets_by_year.items()
]

# Concatenate joined tables using "diagonal_relaxed" to combine common columns and coerce mismatched types
indicators_original = (pl.concat(indicators_merged_dfs, how="diagonal_relaxed")
                       # Replace string literal <Null> with null
                       .with_columns(cs.string().replace(old="<Null>", new=None))
                       # Cast numeric columns to appropriate data type
                       .with_columns(pl.col("depth_water_cm").cast(pl.Float64)
                                     .alias("depth_water_cm"))
                       )

del excel_dict, excel_sheets, subsets_by_year, year_join_keys, indicators_merged_dfs

# -------- Load Remaining Data -----------------------------------------
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = get_template("environment")
moisture_crosswalk = pl.read_csv(moisture_input)
disturbance_crosswalk = pl.read_csv(disturbance_input)

# -------- Prepare Environment Data ------------------------------------

print(environment_original.select("LandscapeType").unique())
print(environment_original.select("AlaskaEcotypeClassification").unique())

environment_df = (environment_original
                  # Replace whitespaces with nulls
                  .with_columns(cs.string().str.strip_chars().replace("", None))
                  # Convert string columns to lowercase (except for Evaluation ID
                  .with_columns(cs.string().exclude("EvaluationID").str.to_lowercase())
                  # Format site code
                  .with_columns(pl.col("EvaluationID")
                                .str.extract(r"^(.*)_")
                                .alias("site_code"))
                  # Append site visit code using right join to drop any plots not in site visit table
                  .join(visit_original, on="site_code", how="right"))

# -------- Classify Disturbance ------------------------------------

# Begin with disturbance because the disturbance table introduces duplicates in the merged environment table (can
# have >1 disturbance entry per site visit)

# Examine Scope values to ensure that 5_Present is absent
print(environment_df.select("MonitoringPlotScope").unique())

environment_df = (environment_df
                  # Extract numeric part of the severity scale
                  .with_columns(pl.col("MonitoringPlotScope", "MonitoringPlotDegree").str.extract(r"(^\d)")
                                .cast(pl.Int64)
                                )
                  # Calculate total disturbance score (scope + degree)
                  .with_columns(
    pl.when(pl.all_horizontal(pl.col("MonitoringPlotScope", "MonitoringPlotDegree").is_null()))
    .then(None)
    .otherwise(pl.sum_horizontal("MonitoringPlotScope", "MonitoringPlotDegree"))
    .alias("total_severity")
    )
                  # Keep the entry associated with the largest total severity (highest score)
                  .sort(by=["site_visit_code", "total_severity"], descending=[False, True], nulls_last=True)
                  .unique(subset=["site_visit_code"], keep="first")
                  # Classify severity
                  .with_columns(
    pl.col("MonitoringPlotDegree").replace_strict(SEVERITY_MAPPING).alias("disturbance_severity"))
                  # Combine Disturbance and OtherDisturbance values into a single column
                  .with_columns(pl.col("Disturbance").replace(old="other", new=None).alias("Disturbance")
                                )
                  .with_columns(pl.coalesce("Disturbance", "OtherDisturbance").str.strip_suffix(".")
                                .alias("original_disturbance"))
                  # Join with disturbance crosswalk to map original disturbance values onto AKVEG Database Dictionary
                  .join(disturbance_crosswalk, how="left", on="original_disturbance")
                  # Fill in ambiguous values
                  .with_columns(pl.when(pl.col("DisturbanceComment").str.contains("historical winter trail"))
                                .then(pl.lit("historic anthropogenic"))
                                .when((pl.col("Disturbance") == "recreation") &
                                      (pl.col("DisturbanceComment").str.contains("apparent winter trail|hiking trail")))
                                .then(pl.lit("trail"))
                                .when((pl.col("Disturbance") == "recreation") &
                                      (pl.col("DisturbanceComment").str.contains("atv trail")))
                                .then(pl.lit("ATV use"))
                                .when(pl.col("original_disturbance") == "snow/ice road/pad disturbance")
                                .then(pl.lit("ATV use"))  # Based on DisturbanceComment
                                # Re-classify "soil disturbance animals"
                                .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                      (pl.col("DisturbanceComment").str.contains("trail")))
                                .then(pl.lit("wildlife trails"))
                                .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                      (pl.col("DisturbanceComment").str.contains("burrow|digging")))
                                .then(pl.lit("wildlife digging"))
                                .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                      (pl.col("DisturbanceComment").str.contains(r"caribou|forage")))
                                .then(pl.lit("wildlife foraging"))
                                .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                      (pl.col("DisturbanceComment").str.contains(
                                          r"trample|moose tracks and disturbed soil")))
                                .then(pl.lit("wildlife trampling"))
                                .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                      (pl.col("total_severity") <= 2))
                                .then(pl.lit("none"))
                                .otherwise(pl.col("disturbance"))
                                .alias("disturbance")
                                )
                  # Assign "none" when no disturbance was observed or when total severity is 0 (disturbances were
                  # outside plot)
                  .with_columns(pl.when((pl.col("total_severity") == 0) | (pl.col("DisturbancesObserved") == "no"))
                                .then(pl.lit("none"))
                                .otherwise(pl.col("disturbance"))
                                .alias("disturbance")
                                )
                  )

# Explore any remaining null values
print(environment_df.select("disturbance").null_count())

# -------- Classify Landforms ------------------------------------

environment_df = (environment_df
                  # Classify geomorphology
                  .with_columns(pl.when(pl.col("PlotDescription").str.contains("coastal plain", literal=True))
                                .then(pl.lit("coastal plain"))
                                .when((pl.col("Elevation_m") <= 300) & (pl.col("LandscapeType") == 'hill mountain'))
                                .then(pl.lit("hill"))
                                .when(pl.col("LandscapeType") == 'floodplain basin')
                                .then(pl.lit("floodplain"))
                                .when((pl.col("LandscapeType") == 'flat plain') & (pl.col("Slope") <= 8))
                                .then(pl.lit("plain"))
                                .otherwise(None)
                                .alias("geomorphology")
                                )

                  # Classify physiography
                  # Likely misattributes subalpine plots to upland because ecotype does not differentiate between
                  # upland and subapline
                  .with_columns(pl.col("AlaskaEcotypeClassification").str.replace("riverine", "riparian", literal=True)
                                .str.extract(r"(^[a-z]+\b)")
                                .alias("physiography")
                                )
                  .with_columns(
    pl.when(pl.col("PlotDescription").str.contains(r"(at|near)\streeline|near upland-alpine transition"))
    .then(pl.lit("subalpine"))
    .otherwise(pl.col("physiography"))
    .alias("physiography"))

                  # Classify macrotopography (no changes made to alluvial fan or terrace)
                  .with_columns(pl.col("LandscapeTypeSecondary").replace(["tread", "riser", "backslope"],
                                                                         [None, None, "slope"])
                                .alias("macrotopography"))
                  .with_columns(pl.col("VerticalSlopeShape").replace(old="linear", new="planar")
                                .alias("VerticalSlopeShape"))
                  .with_columns(pl.when(pl.col("macrotopography") == "slope")
                                .then(pl.concat_str([pl.col("macrotopography"), pl.col("VerticalSlopeShape")],
                                                    separator=" "))
                                .otherwise(pl.col("macrotopography"))
                                .alias("macrotopography")
                                )

                  # Classify disturbance

                  # Create columns for missing data
                  # Microtopography and drainage would have to be parsed from notes (PlotDescription column)
                  .with_columns(pl.lit(None).cast(pl.String).alias("microtopography"),
                                pl.lit(None).cast(pl.String).alias("drainage"),
                                pl.lit("-999").cast(pl.Int16).alias("disturbance_time_y"))
                  # Replace nulls with string literal "NULL" for SQL compatibility
                  .with_columns(cs.string().replace(None, "NULL"))
                  )

# -------- Prepare Indicator Data (Depths & Moisture) ------------------

# Ensure Plot Key and Evaluation ID are mutually exclusive (they should be, because the 2021 data used "Plot Key" as
# a unique site visit identifier, while the 2025 data used "Evaluation ID")
print(indicators_original.select(["Plot Key", "Evaluation ID"]).count(),
      indicators_original.select(["Plot Key", "Evaluation ID"]).null_count())

indicators_df = (indicators_original
                 # Coalesce Plot Key and Evaluation ID
                 .with_columns(pl.coalesce(pl.col(["Plot Key", "Evaluation ID"])
                                           .alias("plot_key")),
                               # Convert Notes to lowercase
                               pl.col("Notes").str.to_lowercase().alias("Notes"))
                 # Convert "unmeasurable" depth values to null to exclude them from mean calculation
                 .with_columns(pl.when(pl.col("Notes").str.contains(r"greater.*100"))
                               .then(None)
                               .otherwise(pl.col("depth_restrictive_layer_cm"))
                               .alias("depth_restrictive_layer_cm"))
                 .with_columns(cs.numeric().replace([-999, 999, 9999], None))
                 .drop(pl.col(["Plot Key", "Evaluation ID", "GlobalID", "Notes"]))
                 )

# Ensure that only one moisture regime value exists per site visit
print(indicators_df.group_by("plot_key").agg(pl.col("moisture_regime").n_unique())
      .filter(pl.col("moisture_regime") > 1))

# Calculate mean depths and grab first moisture regime value (all values at a site visit are the same)
indicators_df = (indicators_df.group_by("plot_key").agg(cs.numeric().mean(),
                                                        cs.string().first())
                 .rename({"moisture_regime": "original_values"})
                 .join(moisture_crosswalk, how="left", on="original_values"))

# Ensure that original and re-class moisture columns have the same number of nulls
print(indicators_df.select(["original_values", "moisture_regime"]).null_count())

## Format surface water
environment_table['surface_water'] = np.where(environment_table['SurfaceWaterPresent'] == 'Yes', 'TRUE',
                                              'FALSE')

## Format water depth
# If surface water is present, note surface water depth. Take average of range listed on page 50 of the BLM's Wetland
# Field Protocols.
# Otherwise, note groundwater depth
# -999 for null values
environment_table['WaterDepth'].describe()
environment_table['SurfaceWaterDepth'].unique()

conditions = [environment_table['SurfaceWaterDepth'] == '2_10',
              environment_table['SurfaceWaterDepth'] == '10_20',
              environment_table['SurfaceWaterDepth'] == '0_1',
              environment_table['SurfaceWaterDepth'] == '20_30',
              (pd.isna(environment_table['SurfaceWaterDepth']) == True) &
              (pd.isna(environment_table['WaterDepth']) == True)]
choices = [6, 15, 1, 25, -999]
environment_table['depth_water_cm'] = np.select(conditions, choices,
                                                default=environment_table['WaterDepth'])

## Format restrictive type
environment_table['ImpenetrableDescrip'].value_counts()

conditions = [environment_table['ImpenetrableDescrip'] == 'Permafrost',
              environment_table['ImpenetrableDescrip'] == 'Bedrock',
              (environment_table['PermafrostInfluence'] == 'Yes') &
              (pd.isna(environment_table['DepthActiveLayer']) == False)]
choices = ['permafrost', 'bedrock', 'permafrost']
environment_table['restrictive_type'] = np.select(conditions, choices, default='NULL')

environment_table['restrictive_type'].value_counts()

## Format depth restrictive layer
# 'DepthActiveLayer' column from BLM database lists upper depth of restrictive horizon, but it seems to me that we
# would want lower (maximum) depth instead.
depth_active_layer = environment_table[['site_visit_code', 'DepthActiveLayer']]
horizon_depths = soil_horizons[['site_visit_code', 'depth_upper', 'depth_lower']]
depth_active_layer = pd.merge(depth_active_layer, horizon_depths, 'left',
                              left_on=['site_visit_code', 'DepthActiveLayer'],
                              right_on=['site_visit_code', 'depth_upper'])

# Replace restrictive depth with lower horizon depth value if it's available
depth_active_layer['depth_restrictive_layer_cm'] = np.where(
    depth_active_layer['depth_lower'] > depth_active_layer['DepthActiveLayer'], depth_active_layer['depth_lower'],
    depth_active_layer['DepthActiveLayer'])

# Replace null values with -999
depth_active_layer.depth_restrictive_layer_cm.fillna(value=-999, inplace=True)

# Drop superfluous columns
depth_active_layer.drop(columns=['DepthActiveLayer', 'depth_upper', 'depth_lower'], inplace=True)

# Merge back into environment_table
environment_table = pd.merge(environment_table, depth_active_layer, how='left', on='site_visit_code')

## Format microrelief
# No information except for one site (mentioned in plot description)
environment_table['microrelief_cm'] = np.where(environment_table['site_code'] == 'SMR_006', 50, -999)
environment_table['microrelief_cm'].describe()

## Format cryoturbation
environment_table['cryoturbation'] = np.where(environment_table['OtherDisturbance'] == 'cryoturbation', 'TRUE', 'NULL')

# Should only be one site that is not null
environment_table['cryoturbation'].value_counts()

## Format depth at 15% coarse fragments
# Use information from soil horizons table

# For each site, find the first instance where total_coarse_fragments = 15
coarse_fragments_15 = soil_horizons[soil_horizons['total_coarse_fragment_percent'] >= 15].copy()
coarse_fragments_15['min_horizon'] = coarse_fragments_15.groupby('site_visit_code')['horizon_order'].transform('min')
coarse_fragments_15['keep_row'] = coarse_fragments_15['horizon_order'].eq(coarse_fragments_15['min_horizon'])
coarse_fragments_15 = coarse_fragments_15[coarse_fragments_15['keep_row'] == True]
coarse_fragments_15.drop(columns=['horizon_order', 'depth_lower', 'texture',
                                  'total_coarse_fragment_percent', 'min_horizon', 'keep_row'],
                         inplace=True)
coarse_fragments_15.rename(columns={'depth_upper': 'depth_15_percent_coarse_fragments_cm'}, inplace=True)

environment_table = pd.merge(environment_table, coarse_fragments_15, 'left', on='site_visit_code')

# Replace NaN with appropriate null value
environment_table.depth_15_percent_coarse_fragments_cm.fillna(value=-999, inplace=True)

## Format dominant texture at 40 cm
# Use information from soil horizons table
texture_40cm = soil_horizons[soil_horizons['depth_lower'] >= 40].copy()
texture_40cm['min_horizon'] = texture_40cm.groupby('site_visit_code')['horizon_order'].transform('min')
texture_40cm['max_horizon'] = texture_40cm.groupby('site_visit_code')['horizon_order'].transform('max')

# Create conditions: If transition from one horizon to the other is at 40cm, choose the lower horizon
conditions = [(texture_40cm['horizon_order'].eq(texture_40cm['min_horizon'])) & (texture_40cm['depth_lower'] != 40),
              (texture_40cm['min_horizon'].eq(texture_40cm['max_horizon'])) & (texture_40cm['depth_lower'] == 40),
              (texture_40cm['max_horizon'].eq(texture_40cm['horizon_order'])) & (texture_40cm['depth_upper'] == 40)]
choices = [True, True, True]
texture_40cm['keep_row'] = np.select(conditions, choices, default=False)

texture_40cm = texture_40cm[texture_40cm['keep_row'] == True]

# Join with environment table
texture_40cm.drop(columns=['horizon_order', 'depth_upper', 'depth_lower',
                           'total_coarse_fragment_percent', 'min_horizon', 'keep_row'],
                  inplace=True)
texture_40cm.rename(columns={'texture': 'dominant_texture_40_cm'}, inplace=True)
environment_table = pd.merge(environment_table, texture_40cm, 'left', on='site_visit_code')

# Replace NaN with appropriate null value
environment_table.dominant_texture_40_cm.fillna(value='NULL', inplace=True)

## Populate remaining columns with appropriate null values
environment_final = environment_table.assign(depth_moss_duff_cm=-999,
                                             soil_class='NULL')

## Drop all columns that aren't in the template and reorder them to match data entry template
environment_final = environment_final[template.columns]

# -------- Perform Quality Checks --------------------------------------

# Ensure all site codes are associated with a site visit code
environment_table.site_visit_code.isna().sum()

# -------- Export Data -------------------------------------------------
environment_final.to_csv(environment_table_output, index=False, encoding='UTF-8')

# -------- Close Database Connection -----------------------------------
db_conn.close()
