# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format soil horizons data for BLM AIM Wetlands data
# Author: Amanda Droghini, Alaska Center for Conservation
# Last Updated: 2024-10-26
# Usage: Must be executed in an ArcGIS Pro Python 3.9+ distribution.
# Description: "Format soil horizons data for BLM AIM Wetlands data" merges a soil horizons ArcGIS table with feature
# classes to obtain plot IDs, restrict to sites that are in Alaska, and obtain information on soil restrictive layer.
# The script then standardizes formatting to match requirements of the AKVEG database, including adding appropriate
# null values, populating required fields, and ensuring all values match constrained values. The output is a CSV file
# that is ready to be ingested in the AKVEG database.
# ---------------------------------------------------------------------------

# Import packges
import os.path
import arcpy
from akutils import *
import numpy as np
import pandas as pd

# Define directories

## Define root directories
drive = 'C:/'
root_folder = 'ACCS_Work'

## Define folder structure
project_folder = os.path.join(drive, root_folder,
                              'OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database')
plot_folder = os.path.join(project_folder, 'Data', 'Data_Plots', '44_aim_various_2022')
source_folder = os.path.join(plot_folder, 'source')
workspace_folder = os.path.join(plot_folder, 'working')

# Set workspace
workspace_geodatabase = os.path.join(drive, root_folder, 'Projects', 'AKVEG_Map', 'Data', 'AKVEG_Workspace.gdb')
arcpy.env.workspace = workspace_geodatabase

# Define files

## Define inputs
source_geodatabase = os.path.join(source_folder, 'AIMWetlandPub6-22-23_clean.gdb')
sites_input = os.path.join(workspace_geodatabase, 'AIM_Wetlands_SiteEval') # From previous script
soil_horizons_input = os.path.join(source_geodatabase, 'F_SoilPitHorizons')
soils_input = os.path.join(source_geodatabase, 'F_Soils')
template_input = os.path.join(project_folder, 'Data', 'Data_Entry', '14_soil_horizons.xlsx')
site_visit_input = os.path.join(plot_folder, '03_sitevisit_aimvarious2022.csv')

## Define intermediate datasets
soil_horizons_copy = os.path.join(workspace_geodatabase, 'AIM_Wetlands_SoilHorizons_Original')
soils_copy = os.path.join(workspace_geodatabase, 'AIM_Wetlands_Soils_Alaska')
sites_minimal = os.path.join(workspace_geodatabase, 'AIM_Wetlands_Sites_Minimal')

## Define output
horizons_feature_output = os.path.join(workspace_geodatabase, 'AIM_Wetlands_SoilHorizons_Alaska')
horizons_table_output = os.path.join(plot_folder, '14_soilhorizons_aimvarious2022.csv')

# Set environment options
arcpy.env.overwriteOutput = True
arcpy.env.outputCoordinateSystem = arcpy.SpatialReference(4269) # NAD 83
arcpy.env.qualifiedFieldNames = False # Do not include table name in join field names

# Read inputs
template = pd.read_excel(template_input)
site_visit_table = pd.read_csv(site_visit_input)

# Clean up input files: Drop unnecessary or redundant columns

## Create FieldMappings object to manage output fields
field_map_sites = arcpy.FieldMappings()
field_map_soils = arcpy.FieldMappings()

## Add all fields to field map objects
field_map_sites.addTable(sites_input)
field_map_soils.addTable(soils_input)

## Specify desired output columns
columns_sites = ["EvaluationID", "PlotID", "AdminState"]
columns_soils = ["EvaluationID", "PlotID", "AdminState", 'PitImpenetrable', 'ImpenetrableDescrip', 'WaterObserved',
                 'WaterDepth', 'PitSaturated', 'DepthToSatSoil', 'Comments']

## Remove extraneous columns in field map objects
for field in field_map_sites.fields:
    if field.name not in columns_sites:
        field_map_sites.removeFieldMap(field_map_sites.findFieldMapIndex(field.name))

for field in field_map_soils.fields:
    if field.name not in columns_soils:
        field_map_soils.removeFieldMap(field_map_soils.findFieldMapIndex(field.name))

## Create new feature classes with fewer columns
arcpy.conversion.ExportFeatures(sites_input, sites_minimal, field_mapping=field_map_sites)

## Copy soil horizons to environment geodatabase
arcpy.conversion.ExportTable(soil_horizons_input, soil_horizons_copy)
arcpy.conversion.ExportFeatures(soils_input, soils_copy, where_clause="AdminState='AK'", field_mapping=field_map_soils)

# Join soil horizons table with site features
# 'Keep common' ensures only sites in Alaska are kept
horizons_sites_join = arcpy.management.AddJoin(in_layer_or_view=sites_minimal, in_field='EvaluationID',
                                               join_table=soil_horizons_copy, join_field='EvaluationID',
                                               join_type='KEEP_COMMON', join_operation='JOIN_ONE_TO_MANY',
                                               rebuild_index='TRUE')

horizons_soils_join = arcpy.management.AddJoin(in_layer_or_view=horizons_sites_join, in_field='EvaluationID',
                                               join_table=soils_copy, join_field='EvaluationID',
                                               join_type='KEEP_COMMON')

## Copy layer to a new feature class
arcpy.management.CopyFeatures(horizons_soils_join, horizons_feature_output)

## Convert to dataframe
horizons_table = geodatabase_to_dataframe(horizons_feature_output)

## Drop superfluous columns

# Replace empty values with na and drop columns for which all values are null
horizons_table.replace(["", "<NULL>"], np.nan, inplace=True)
horizons_table.dropna(how='all', axis=1, inplace=True)

horizons_table = horizons_table.drop(columns=['EvaluationID', 'EvaluationID_1', 'EvaluationID_12', 'AdminState',
                                              'AdminState_1', 'OBJECTID', 'OBJECTID_1', 'OBJECTID_12', 'PitKey',
                                              'last_edited_user', 'last_edited_date', 'GlobalID', 'PlotID_1',
                                              'PrimaryRedoxFeatures', 'PrimaryRedoxHue','PrimaryRedoxValue',
                                              'PrimaryRedoxChroma', 'PrimaryRedoxPercent', 'SecondaryRedoxFeatures',
                                              'SecondaryRedoxHue', 'SecondaryRedoxValue', 'SecondaryRedoxChroma',
                                              'SecondaryRedoxPercent', 'pH'])

## Obtain site visit code
# Format PlotID to match site code
# Remove 'AK-', 'CYFO-', and 'EIFO-'; convert dashes to underscores
horizons_table['site_code'] = horizons_table['PlotID']
horizons_table['site_code'].replace('AK-|CYFO-|EIFO-', '', inplace=True, regex=True)
horizons_table['site_code'].replace('-', '_', inplace=True, regex=True)

# Join with site_visit_table to obtain site_visit_code
site_visit_table = site_visit_table[['site_code', 'site_visit_code']]
horizons_table = horizons_table.set_index('site_code').join(site_visit_table.set_index('site_code'),
                                           how='left', validate='many_to_one')
horizons_table.reset_index(inplace=True)
horizons_table.site_visit_code.isnull().sum() # Ensure there are no null values

# Format horizon order
horizons_table.horizon.value_counts()
horizons_table.horizon.isnull().sum() # Ensure there are no null values
horizons_table.rename(columns={'horizon': 'horizon_order'}, inplace=True)

# Format upper and lower depth
horizons_table[['HorizonDepthUpper', 'HorizonDepthLower']].describe()
horizons_table[['HorizonDepthUpper', 'HorizonDepthLower']].isnull().sum() # Ensure there are no null values
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
horizons_table[['MatrixHue','MatrixChroma', 'MatrixValue']].isnull().sum()

## Convert chroma and value to appropriate data type
horizons_table[["matrix_value", "matrix_chroma"]] = horizons_table[["MatrixValue", "MatrixChroma"]].apply(pd.to_numeric)

## Rename matrix hue column
horizons_table.rename(columns={'MatrixHue': 'matrix_hue'}, inplace=True)

# Populate values for missing columns
horizons_final = horizons_table.assign(horizon_primary='NULL', horizon_suffix_1='NULL', horizon_suffix_2='NULL',
                                       horizon_secondary='NULL', horizon_suffix_3='NULL', horizon_suffix_4='NULL',
                                       structure='NULL',
                                       clay_percent = -999,
                                       boulder_percent=-999,
                                       nonmatrix_feature ='NULL',
                                       nonmatrix_hue='NULL', nonmatrix_value=-999, nonmatrix_chroma=-999)

# Final formatting
## Drop all columns that aren't in the template and reorder them to match data entry template
horizons_final = horizons_final[template.columns]

# QA/QC
temp = horizons_final.describe(include='all')

## Ensure that categorical variables match constrained values in database dictionary
horizons_final.texture.unique()
horizons_final.structure.unique()
horizons_final.matrix_hue.unique()

# Export dataframe
horizons_final.to_csv(horizons_table_output, index=False, encoding='UTF-8')
