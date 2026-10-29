# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Extract soil metrics data from features in BLM AIM Wetlands geodatabase
# Author: Amanda Droghini, Alaska Center for Conservation
# Last Updated: 2024-09-06
# Usage: Must be executed in an ArcGIS Pro Python 3.9+ distribution.
# Description: "Extract soil metrics data from features in BLM AIM Wetlands geodatabase" joins two shapefiles, selects only those sites that are in Alaska, and exports the attribute table as CSV. The output is used to ingest the 44_aim_various_2022 dataset into the AKVEG database.
# ---------------------------------------------------------------------------

# Import packges
import os.path
import arcpy
from akutils import *

# Define directories

## Define root directories
drive = 'C:/'
root_folder = 'ACCS_Work'

## Define folder structure
project_folder = os.path.join(drive, root_folder, 'OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database')
plot_folder = os.path.join(project_folder, 'Data', 'Data_Plots', '44_aim_various_2022')
source_folder = os.path.join(plot_folder, 'source')
workspace_folder = os.path.join(plot_folder, 'working')

# Set workspace
workspace_geodatabase = os.path.join(drive, root_folder, 'Projects', 'AKVEG_Map', 'Data', 'AKVEG_Workspace.gdb')
arcpy.env.workspace = workspace_geodatabase

# Define files

## Define inputs
source_geodatabase = os.path.join(source_folder, 'AIMWetlandPub6-22-23_clean.gdb')
site_data_input = os.path.join(workspace_geodatabase, 'AIM_Wetlands_SiteEval') # From previous script
soil_metrics_input = os.path.join(source_geodatabase, 'F_WaterQualityDetail')

## Define intermediate datasets
soil_metrics_clean = os.path.join(workspace_geodatabase, 'AIM_Wetlands_SoilMetrics_All')
soil_metrics_join = os.path.join(workspace_geodatabase, 'AIM_Wetlands_SoilMetrics_Join')

## Define output
soil_feature_output = os.path.join(workspace_geodatabase, 'AIM_Wetlands_SoilMetrics_Alaska')
soil_table_output = os.path.join(workspace_folder, 'soil_metrics_export.csv')

# Set environment options

## Set overwrite option
arcpy.env.overwriteOutput = True

## Set output coordinate system to NAD 83
arcpy.env.outputCoordinateSystem = arcpy.SpatialReference(4269)

## Do not include table name in join field names
arcpy.env.qualifiedFieldNames = False

# Clean up input files: Drop unnecessary or redundant columns

## Create FieldMappings object to manage output fields
field_map_soil = arcpy.FieldMappings()

## Add all fields to field map objects
field_map_soil.addTable(soil_metrics_input)

## Specify desired output columns
columns_soil = ["EvaluationID", "ChemistrySampleFrom", "Location", "Depth", "StandFlow", "Temp", "TemperatureFlag", "pH", "phFlag", "EC", "ConductivityFlag"]

## Remove extraneous columns in field map objects
for field in field_map_soil.fields:
    if field.name not in columns_soil:
        field_map_soil.removeFieldMap(field_map_soil.findFieldMapIndex(field.name))

## Create new feature classes with fewer columns
arcpy.conversion.ExportFeatures(soil_metrics_input, soil_metrics_clean, field_mapping=field_map_soil)

# Join input files
soil_metrics_join = arcpy.management.AddJoin(in_layer_or_view=site_data_input, in_field='EvaluationID',
                                             join_table=soil_metrics_clean, join_field='EvaluationID',
                                             join_type='KEEP_COMMON',
                                             rebuild_index='REBUILD_INDEX')

## Select only plots in Alaska
select_expression = "AdminState = 'AK'"
arcpy.management.SelectLayerByAttribute(soil_metrics_join, "NEW_SELECTION","AdminState = 'AK'")

## Copy layer to a new feature class
arcpy.management.CopyFeatures(soil_metrics_join, soil_feature_output)

# Delete unnecessary fields
arcpy.management.DeleteField(soil_feature_output,
                             ["EvaluationID", "OBJECTID_1", "EvaluationID_1", 'GPSAccuracy', 'EstablishmentDate', 'AdminState'])

# Convert to dataframe
soil_metrics_table = geodatabase_to_dataframe(soil_feature_output)

# Export dataframe
soil_metrics_table.to_csv(soil_table_output, index=False, encoding='UTF-8')
