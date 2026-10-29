# -*- coding: utf-8 -*-
"""Process Ground Cover Table for BLM AIM 2022–2025 data

Processes data from various tables in the BLM AIM Lotic Geodatabase for ingestion into the AKVEG Database. Joins
shapefiles, re-classifies categorical values, appends unique site identifiers, and performs quality control checks
before exporting to CSV.

Author: Amanda Droghini, Alaska Center for Conservation
Last Updated: 2026-10-27
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
import geopandas as gpd
from pathlib import Path
import polars as pl
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql
from utils.utils import get_template, get_valid_values

# -------- Set Up Environment ------------------------------------------
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"

# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'
credentials_input = paths.cloud_assets.credentials

# Define output
envr_output = plot_folder / '12_environment_aimvarious2025.csv'

# Connect to AKVEG Database
db_conn = connect_database_postgresql(credentials_input)

# -------- Load Data ---------------------------------------------------
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = get_template("environment")
site_original = (pl.from_pandas(gpd.read_file(gdb_input,
                                              layer="AIM_Wetland__F_PlotCharacterization",
                                              columns=['PlotID', 'Elevation_m', 'Slope',
                                                       'AlaskaEcotypeClassification', 'LandscapeType',
                                                       'LandscapeTypeSecondary', 'VerticalSlopeShape',
                                                       'PlotDescription'],
                                              ignore_geometry=True))
                 .lazy())
soil_original = (pl.from_pandas(gpd.read_file(gdb_input,
                                              layer="AIM_Wetland__F_Soils",
                                              columns=['PlotID', 'PitImpenetrable',
                                                       'ImpenetrableDescrip', 'WaterObserved', 'WaterDepth',
                                                       'PitSaturated', 'DepthToSatSoil', 'HydricIndicatorPrimary',
                                                       'HydricIndicatorSecondary'],
                                              ignore_geometry=True))
                 .lazy())
disturb_original = (pl.from_pandas(gpd.read_file(gdb_input,
                                                 layer="AIM_Wetland__F_NaturalandHumanDisturbances",
                                                 columns=['EvaluationID', 'PlotID',
                                                          'DisturbancesObserved'],
                                                 ignore_geometry=True)).lazy())
disturb_detail_original = (pl.from_pandas(gpd.read_file(gdb_input,
                                                        layer="AIM_Wetland__F_DisturbancesDetail",
                                                        columns=['EvaluationID', 'Disturbance', 'OtherDisturbance',
                                                                 'MonitoringPlotScope', 'MonitoringPlotDegree',
                                                                 'DisturbanceComment'],
                                                        ignore_geometry=True)).lazy())
hydrology_original = (pl.from_pandas(gpd.read_file(gdb_input,
                                                   layer="AIM_Wetland__F_Hydrology",
                                                   columns=['EvaluationID', 'PermafrostInfluence',
                                                            'DepthActiveLayer', 'SurfaceWaterPresent',
                                                            'SurfaceWaterDepth'],
                                                   ignore_geometry=True)).lazy())

# -------- Prepare Input Data ------------------------------------------

# Join input files
site_soil_join = arcpy.management.AddJoin(in_layer_or_view=site_clean, in_field='PlotID', join_table=soil_clean,
                                          join_field='PlotID', join_type='KEEP_ALL')

disturb_join = arcpy.management.AddJoin(in_layer_or_view=site_soil_join, in_field='PlotID',
                                        join_table=disturb_clean, join_field='PlotID',
                                        join_type='KEEP_ALL')

disturb_detail_join = arcpy.management.AddJoin(in_layer_or_view=disturb_join, in_field='EvaluationID',
                                               join_table=disturb_detail_clean, join_field='EvaluationID',
                                               join_type='KEEP_ALL')

hydrology_join = arcpy.management.AddJoin(in_layer_or_view=disturb_detail_join, in_field='EvaluationID',
                                          join_table=hydrology_clean, join_field='EvaluationID',
                                          join_type='KEEP_ALL')

## Copy layer to a new feature class
arcpy.management.CopyFeatures(hydrology_join, environment_feature_output)

# Delete unnecessary fields
arcpy.management.DeleteField(environment_feature_output,
                             ['PlotID_1', 'PlotID_12',
                              'OBJECTID_1', 'OBJECTID_12', 'OBJECTID_12_13', 'OBJECTID_12_13_14'
                                                                             'EvaluationID', 'EvaluationID_1',
                              'EvaluationID_12',
                              'AdminState', 'AdminState_1', 'AdminState_12'])

# Convert to dataframe
environment_table = geodatabase_to_dataframe(environment_feature_output)

## Format site code
environment_table['site_code'] = environment_table.PlotID.str.removeprefix('AK-')
environment_table['site_code'] = environment_table.site_code.str.removeprefix('EIFO-')
environment_table['site_code'] = environment_table.site_code.str.removeprefix('CYFO-')
environment_table['site_code'] = environment_table.site_code.str.replace('-', '_')

## Obtain site visit code
site_visit = site_visit[['site_code', 'site_visit_code']]
environment_table = pd.merge(environment_table, site_visit, 'left', on='site_code')
# Ensure all site codes are associated with a site visit code
environment_table.site_visit_code.isna().sum()

# -------- Classify Geomorphology --------------------------------------
environment_table.LandscapeType.unique()

conditions = [(environment_table['LandscapeType'] == 'Hill Mountain') & (environment_table['Elevation_m'] <= 300),
              (environment_table['LandscapeType'] == 'Hill Mountain') & (environment_table['Elevation_m'] > 300),
              environment_table['LandscapeType'] == 'Floodplain Basin',
              (environment_table['LandscapeType'] == 'Flat Plain') & (
                  environment_table['AlaskaEcotypeClassification'].str.contains('Lowland')),
              (environment_table['LandscapeType'] == 'Flat Plain') & (
                  environment_table['AlaskaEcotypeClassification'].str.contains('Upland')),
              environment_table['LandscapeType'] == 'Terrace',
              (environment_table['LandscapeType'] == 'Alluvial Fan') & (
                  environment_table['AlaskaEcotypeClassification'].str.contains('Upland')),
              (environment_table['LandscapeType'] == 'Alluvial Fan') & (
                  environment_table['AlaskaEcotypeClassification'].str.contains('Alpine'))]
choices = ['hill', 'mountain', 'floodplain', 'plain', 'valley, lowland', 'valley, lowland',
           'valley, lowland', 'valley, alpine']
environment_table['geomorphology'] = np.select(conditions, choices, default='NULL')

environment_table.geomorphology.value_counts()

# -------- Classify Physiography ---------------------------------------
# Ecotype does not differentiate between 'upland' and 'subalpine'
# Re-classification likely misattributes subalpine plots to upland
environment_table.AlaskaEcotypeClassification.unique()

conditions = [environment_table['geomorphology'] == 'floodplain',
              environment_table['AlaskaEcotypeClassification'].str.contains('Lowland'),
              environment_table['PlotDescription'].str.contains('above treeline'),
              environment_table['PlotDescription'].str.contains('ecotone'),
              environment_table['AlaskaEcotypeClassification'].str.contains('Upland'),
              environment_table['AlaskaEcotypeClassification'].str.contains('Alpine'), ]
choices = ['riverine', 'lowland', 'subalpine', 'subalpine', 'upland', 'alpine']
environment_table['physiography'] = np.select(conditions, choices, default='NULL')

environment_table.physiography.value_counts()

# -------- Classify Macrotopography ------------------------------------
environment_table.LandscapeTypeSecondary.value_counts()

conditions = [environment_table['LandscapeType'] == 'Alluvial Fan',
              environment_table['LandscapeType'] == 'Terrace',
              environment_table['LandscapeTypeSecondary'] == 'Shoulder',
              environment_table['LandscapeTypeSecondary'] == 'Summit',
              (environment_table['LandscapeTypeSecondary'] == 'Backslope') & (
                      environment_table['VerticalSlopeShape'] == 'linear'),
              (environment_table['LandscapeTypeSecondary'] == 'Backslope') & (
                      environment_table['VerticalSlopeShape'] == 'concave'),
              (environment_table['LandscapeTypeSecondary'] == 'Backslope') & (
                      environment_table['VerticalSlopeShape'] == 'convex')]
choices = ['alluvial fan', 'terrace', 'ridge', 'summit', 'slope planar', 'slope concave', 'slope convex']
environment_table['macrotopography'] = np.select(conditions, choices, default='NULL')

freq_table = pd.crosstab(environment_table['LandscapeTypeSecondary'], environment_table['macrotopography'])

# -------- Classify Microtopography ------------------------------------
# Relevant information was interpreted from plot description narrative; likely to be some errors.

conditions = [environment_table['site_code'] == 'RW_22098',
              environment_table['site_code'] == 'WNTR_205',
              environment_table['site_code'] == 'WNTR_208',
              environment_table['site_code'] == 'SMR_005',
              environment_table['site_code'] == 'RW_22473',
              environment_table['site_code'] == 'WNTR_204',
              environment_table['site_code'] == 'SMR_001',
              environment_table['site_code'] == 'WNTR_215',
              environment_table['site_code'] == 'SMR_008',
              environment_table['site_code'] == 'SMR_002',
              environment_table['site_code'] == 'WNTR_213',
              environment_table['site_code'] == 'RW_22136',
              environment_table['site_code'] == 'RW_22072',
              environment_table['site_code'] == 'RW_22477',
              environment_table['site_code'] == 'West_SMR_010',
              environment_table['site_code'] == 'SMR_007',
              environment_table['site_code'] == 'WNTR_212',
              environment_table['site_code'] == 'West_WNTR_194',
              environment_table['site_code'] == 'TW_22964',
              environment_table['site_code'] == 'RW_22484',
              environment_table['site_code'] == 'RW_22102',
              environment_table['site_code'] == 'RW_22489',
              environment_table['site_code'] == 'WNTR_209',
              environment_table['site_code'] == 'West_SMR_013',
              environment_table['site_code'] == 'SMR_003']

choices = ['hummocks', 'boulder field', 'talus', 'mounds', 'solifluction lobes', 'ice-cored mounds', 'mounds', 'mounds',
           'polygonal', 'polygonal', 'talus', 'boulder field', 'channeled', 'channeled', 'tussocks', 'talus',
           'boulder field', 'boulder field', 'tussocks', 'talus', 'tussocks', 'hummocks', 'water tracks', 'tussocks',
           'ponds']

environment_table['microtopography'] = np.select(conditions, choices, default='NULL')
environment_table.microtopography.unique()

# -------- Classify Drainage -------------------------------------------
conditions = [environment_table['PlotDescription'].str.contains('saturated'),
              environment_table['PlotDescription'].str.contains('poorly drained'),
              environment_table['PlotDescription'].str.contains('very well drained'),
              environment_table['PlotDescription'].str.contains('excessively drained'),
              (environment_table['PlotDescription'].str.contains('well drained')) &
              (environment_table['PitSaturated'] == 'No'),
              (environment_table['PlotDescription'].str.contains('well-drained')) &
              (environment_table['PitSaturated'] == 'No'),
              (environment_table['WaterObserved'] == 'No') &
              (environment_table['PitSaturated'] == 'No')]
choices = ['poorly drained', 'poorly drained', 'well drained', 'well drained', 'moderately drained',
           'moderately drained', 'moderately drained']
environment_table['drainage'] = np.select(conditions, choices, default='NULL')

environment_table.drainage.value_counts()

# -------- Classify Moisture Regime ------------------------------------
conditions = [environment_table['HydricIndicatorPrimary'].str.contains('^A\d') == True,
              environment_table['site_code'] == 'RW_22104']
choices = ['hydric', 'hydric']
environment_table['moisture_regime'] = np.select(conditions, choices, default='NULL')

## Classify disturbance
environment_table.Disturbance.value_counts()

conditions = [environment_table['DisturbancesObserved'] == 'No',
              environment_table['site_code'] == 'RW_22481',
              environment_table['Disturbance'] == 'Recent Fire',
              environment_table['Disturbance'] == 'Grazing',
              environment_table['Disturbance'] == 'Erosion',
              environment_table['Disturbance'] == 'Recent Flood',
              environment_table['site_code'] == 'SMR_004',
              environment_table['site_code'] == 'RW_22136',
              environment_table['Disturbance'] == 'Soil Disturbance Animals',
              environment_table['OtherDisturbance'].str.contains('thermokarst|frost|cryoturbation') == True,
              environment_table['OtherDisturbance'].str.contains('colluvium') == True,
              environment_table['site_code'] == 'West_WNTR_194',
              environment_table['OtherDisturbance'].str.contains('burrow|warren') == True]
choices = ['none', 'none', 'fire', 'wildlife foraging', 'aeolian process', 'riparian', 'none',
           'wildlife trails', 'wildlife trampling', 'permafrost dynamics', 'geomorphic process', 'wildlife digging',
           'wildlife digging']
environment_table['disturbance'] = np.select(conditions, choices, default='NULL')

# 25 sites should have 'none' listed; no null values
environment_table['disturbance'].value_counts()
freq_table = pd.crosstab(environment_table['Disturbance'], environment_table['disturbance'])

## Classify disturbance severity
environment_table.MonitoringPlotDegree.value_counts()
environment_table.MonitoringPlotDegree.isna().sum()
conditions = [environment_table['MonitoringPlotDegree'] == '4_Extreme',
              environment_table['MonitoringPlotDegree'] == '3_Serious',
              environment_table['MonitoringPlotDegree'] == '2_Moderate',
              environment_table['MonitoringPlotDegree'] == '1_Slight',
              environment_table['site_code'] == 'West_WNTR_194',
              environment_table['MonitoringPlotDegree'] == '0_Absent']
choices = ['high', 'high', 'moderate', 'low', 'low', 'NULL']
environment_table['disturbance_severity'] = np.select(conditions, choices, default='NULL')

# 25 sites should have a null value (no disturbance observed)
environment_table['disturbance_severity'].value_counts()

## Classify time since disturbance
# Fire and flooding sites indicated as 'recent', consider all other disturbances as recent
environment_table['disturbance_time_y'] = np.where(environment_table['disturbance'] == 'none', -999, 0)

# 25 sites should have a value of -999 (no disturbance observed)
environment_table['disturbance_time_y'].value_counts()

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

# -------- Export Data -------------------------------------------------
environment_final.to_csv(environment_table_output, index=False, encoding='UTF-8')

# -------- Close Database Connection -----------------------------------
db_conn.close()
