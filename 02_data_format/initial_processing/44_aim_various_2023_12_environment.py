# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Extract environment data from features in BLM AIM Wetlands geodatabase
# Author: Amanda Droghini, Alaska Center for Conservation
# Last Updated: 2024-10-26
# Usage: Must be executed in an ArcGIS Pro Python 3.9+ distribution.
# Description: "Extract environment data from features in BLM AIM Wetlands geodatabase" selects columns that contain information relevant to the AKVEG Database 'Environment' table, joins shapefiles, selects only those sites that are in Alaska, and exports the attribute table as CSV. The output is used to ingest the 44_aim_various_2022 dataset into the AKVEG database.
# ---------------------------------------------------------------------------

# Import packges
import os.path
import arcpy
from akutils import *
import pandas as pd
import numpy as np

# Define directories

## Define root directories
drive = 'C:/'
root_folder = 'ACCS_Work'

## Define folder structure
project_folder = os.path.join(drive, root_folder, 'OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database')
plot_folder = os.path.join(project_folder, 'Data', 'Data_Plots', '44_aim_various_2022')
source_folder = os.path.join(plot_folder, 'source')

# Set workspace
workspace_geodatabase = os.path.join(drive, root_folder, 'Projects', 'AKVEG_Map', 'Data', 'AKVEG_Workspace.gdb')
arcpy.env.workspace = workspace_geodatabase

# Define files

## Define inputs
source_geodatabase = os.path.join(source_folder, 'AIMWetlandPub6-22-23_clean.gdb')
site_input = os.path.join(source_geodatabase, 'F_PlotCharacterization')
soil_input = os.path.join(source_geodatabase, 'F_Soils')
disturb_input = os.path.join(source_geodatabase, 'F_NaturalAndHumanDisturbances')
disturb_detail_input = os.path.join(source_geodatabase, 'F_DisturbancesDetail')
hydrology_input = os.path.join(source_geodatabase, 'F_Hydrology')
site_visit_input = os.path.join(plot_folder, '03_sitevisit_aimvarious2022.csv')
horizons_input = os.path.join(plot_folder, '14_soilhorizons_aimvarious2022.csv')
template_input = os.path.join(project_folder, 'Data', 'Data_Entry', '12_environment.xlsx')

## Define intermediate datasets
site_clean = os.path.join(workspace_geodatabase, 'AIM_Wetlands_PlotChar_Envr')
soil_clean = os.path.join(workspace_geodatabase, 'AIM_Wetlands_Soils_Envr')
disturb_clean = os.path.join(workspace_geodatabase, 'AIM_Wetlands_Disturb')
disturb_detail_clean = os.path.join(workspace_geodatabase, 'AIM_Wetlands_Disturb_Detail')
hydrology_clean = os.path.join(workspace_geodatabase, 'AIM_Wetlands_Hydro_Envr')

## Define output
environment_feature_output = os.path.join(workspace_geodatabase, 'AIM_Wetlands_Environment_Alaska')
environment_table_output = os.path.join(plot_folder, '12_environment_aimvarious2022.csv')

# Set environment options

## Set overwrite option
arcpy.env.overwriteOutput = True

## Set output coordinate system to NAD 83
arcpy.env.outputCoordinateSystem = arcpy.SpatialReference(4269)

## Do not include table name in join field names
arcpy.env.qualifiedFieldNames = False

## Read in CSV files
site_visit = pd.read_csv(site_visit_input)
soil_horizons = pd.read_csv(horizons_input, usecols=['site_visit_code', 'horizon_order', 'depth_upper', 'depth_lower', 'total_coarse_fragment_percent', 'texture'])
template = pd.read_excel(template_input)

# Clean up input files: Drop unnecessary or redundant columns

## Create FieldMappings object to manage output fields
field_map_site = arcpy.FieldMappings()
field_map_soil = arcpy.FieldMappings()
field_map_disturb = arcpy.FieldMappings()
field_map_disturb_detail = arcpy.FieldMappings()
field_map_hydrology = arcpy.FieldMappings()

## Add all fields to field map objects
field_map_site.addTable(site_input)
field_map_soil.addTable(soil_input)
field_map_disturb.addTable(disturb_input)
field_map_disturb_detail.addTable(disturb_detail_input)
field_map_hydrology.addTable(hydrology_input)

## Specify desired output columns
columns_site = ['PlotID', 'AdminState', 'Elevation_m', 'Slope', 'AlaskaEcotypeClassification', 'LandscapeType', 'LandscapeTypeSecondary', 'VerticalSlopeShape',
                'PlotDescription']
columns_soil = ['PlotID', 'AdminState', 'PitImpenetrable', 'ImpenetrableDescrip', 'WaterObserved', 'WaterDepth', 'PitSaturated',
                'DepthToSatSoil', 'HydricIndicatorPrimary', 'HydricIndicatorSecondary']
columns_disturb = ['EvaluationID', 'AdminState', 'PlotID', 'DisturbancesObserved']
columns_disturb_detail = ['EvaluationID', 'Disturbance', 'OtherDisturbance', 'MonitoringPlotScope',
                          'MonitoringPlotDegree', 'DisturbanceComment']
columns_hydrology = ['EvaluationID', 'PermafrostInfluence', 'DepthActiveLayer', 'SurfaceWaterPresent',
                     'SurfaceWaterDepth']

## Remove extraneous columns in field map objects
for field in field_map_site.fields:
    if field.name not in columns_site:
        field_map_site.removeFieldMap(field_map_site.findFieldMapIndex(field.name))

for field in field_map_soil.fields:
    if field.name not in columns_soil:
        field_map_soil.removeFieldMap(field_map_soil.findFieldMapIndex(field.name))

for field in field_map_disturb.fields:
    if field.name not in columns_disturb:
        field_map_disturb.removeFieldMap(field_map_disturb.findFieldMapIndex(field.name))

for field in field_map_disturb_detail.fields:
    if field.name not in columns_disturb_detail:
        field_map_disturb_detail.removeFieldMap(field_map_disturb_detail.findFieldMapIndex(field.name))

for field in field_map_hydrology.fields:
    if field.name not in columns_hydrology:
        field_map_hydrology.removeFieldMap(field_map_hydrology.findFieldMapIndex(field.name))

## Select only plots in Alaska
select_expression = "AdminState = 'AK'"

## Create new feature classes with fewer columns and apply selection
arcpy.conversion.ExportFeatures(site_input, site_clean, where_clause=select_expression, field_mapping=field_map_site)
arcpy.conversion.ExportFeatures(soil_input, soil_clean, where_clause=select_expression, field_mapping=field_map_soil)
arcpy.conversion.ExportTable(disturb_input, disturb_clean, where_clause=select_expression, field_mapping=field_map_disturb)
arcpy.conversion.ExportTable(disturb_detail_input, disturb_detail_clean, field_mapping=field_map_disturb_detail)
arcpy.conversion.ExportTable(hydrology_input, hydrology_clean, field_mapping=field_map_hydrology)

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
                              'EvaluationID', 'EvaluationID_1', 'EvaluationID_12',
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

## Re-classify geomorphology
environment_table.LandscapeType.unique()

conditions = [(environment_table['LandscapeType'] == 'Hill Mountain') & (environment_table['Elevation_m'] <= 300),
              (environment_table['LandscapeType'] == 'Hill Mountain') & (environment_table['Elevation_m'] > 300),
              environment_table['LandscapeType'] == 'Floodplain Basin',
              (environment_table['LandscapeType'] == 'Flat Plain') & (environment_table['AlaskaEcotypeClassification'].str.contains('Lowland')),
              (environment_table['LandscapeType'] == 'Flat Plain') & (environment_table['AlaskaEcotypeClassification'].str.contains('Upland')),
              environment_table['LandscapeType'] == 'Terrace',
              (environment_table['LandscapeType'] == 'Alluvial Fan') & (environment_table['AlaskaEcotypeClassification'].str.contains('Upland')),
              (environment_table['LandscapeType'] == 'Alluvial Fan') & (environment_table['AlaskaEcotypeClassification'].str.contains('Alpine'))]
choices = ['hill', 'mountain', 'floodplain', 'plain', 'valley, lowland', 'valley, lowland',
           'valley, lowland', 'valley, alpine']
environment_table['geomorphology'] = np.select(conditions, choices, default='NULL')

environment_table.geomorphology.value_counts()

## Re-classify physiography
# Ecotype does not differentiate between 'upland' and 'subalpine'
# Re-classification likely misattributes subalpine plots to upland
environment_table.AlaskaEcotypeClassification.unique()

conditions = [environment_table['geomorphology'] == 'floodplain',
              environment_table['AlaskaEcotypeClassification'].str.contains('Lowland'),
              environment_table['PlotDescription'].str.contains('above treeline'),
              environment_table['PlotDescription'].str.contains('ecotone'),
              environment_table['AlaskaEcotypeClassification'].str.contains('Upland'),
              environment_table['AlaskaEcotypeClassification'].str.contains('Alpine'),]
choices = ['riverine', 'lowland', 'subalpine', 'subalpine', 'upland', 'alpine']
environment_table['physiography'] = np.select(conditions, choices, default='NULL')

environment_table.physiography.value_counts()

## Classify macrotopography
environment_table.LandscapeTypeSecondary.value_counts()

conditions = [environment_table['LandscapeType'] == 'Alluvial Fan',
              environment_table['LandscapeType'] == 'Terrace',
              environment_table['LandscapeTypeSecondary'] == 'Shoulder',
              environment_table['LandscapeTypeSecondary'] == 'Summit',
              (environment_table['LandscapeTypeSecondary'] == 'Backslope') & (environment_table['VerticalSlopeShape'] == 'linear'),
              (environment_table['LandscapeTypeSecondary'] == 'Backslope') & (environment_table['VerticalSlopeShape'] == 'concave'),
              (environment_table['LandscapeTypeSecondary'] == 'Backslope') & (environment_table['VerticalSlopeShape'] == 'convex')]
choices = ['alluvial fan', 'terrace', 'ridge', 'summit', 'slope planar', 'slope concave', 'slope convex']
environment_table['macrotopography'] = np.select(conditions, choices, default='NULL')

freq_table = pd.crosstab(environment_table['LandscapeTypeSecondary'], environment_table['macrotopography'])

## Classify microtopography
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

choices = ['hummocks', 'boulder field', 'talus', 'mounds', 'solifluction lobes', 'ice-cored mounds', 'mounds', 'mounds', 'polygonal', 'polygonal', 'talus', 'boulder field', 'channeled', 'channeled', 'tussocks', 'talus', 'boulder field', 'boulder field', 'tussocks', 'talus', 'tussocks', 'hummocks', 'water tracks', 'tussocks', 'ponds']

environment_table['microtopography'] = np.select(conditions, choices, default='NULL')
environment_table.microtopography.unique()

## Classify drainage
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

## Classify moisture regime
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
'wildlife trails', 'wildlife trampling', 'permafrost dynamics', 'geomorphic process', 'wildlife digging', 'wildlife digging']
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
# If surface water is present, note surface water depth. Take average of range listed on page 50 of the BLM's Wetland Field Protocols.
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
# 'DepthActiveLayer' column from BLM database lists upper depth of restrictive horizon, but it seems to me that we would want lower (maximum) depth instead.
depth_active_layer = environment_table[['site_visit_code', 'DepthActiveLayer']]
horizon_depths = soil_horizons[['site_visit_code', 'depth_upper', 'depth_lower']]
depth_active_layer = pd.merge(depth_active_layer, horizon_depths, 'left', left_on=['site_visit_code', 'DepthActiveLayer'], right_on=['site_visit_code', 'depth_upper'])

# Replace restrictive depth with lower horizon depth value if it's available
depth_active_layer['depth_restrictive_layer_cm'] = np.where(depth_active_layer['depth_lower'] > depth_active_layer['DepthActiveLayer'], depth_active_layer['depth_lower'], depth_active_layer['DepthActiveLayer'])

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

## Export dataframe
environment_final.to_csv(environment_table_output, index=False, encoding='UTF-8')
