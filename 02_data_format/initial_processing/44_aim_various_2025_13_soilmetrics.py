# -*- coding: utf-8 -*-
"""Process Soil Metrics Table for BLM AIM 2022–2025 Data

Joins shapefiles and exports the resulting table to CSV.

Author: Amanda Droghini, Alaska Center for Conservation
Last Updated: 2026-10-29
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
import geopandas as gpd
from pathlib import Path
import polars as pl
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql
from utils.utils import get_template

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
soil_metrics_output = plot_folder / '13_soilmetrics_aimvarious2025.csv'

# Connect to AKVEG Database
db_conn = connect_database_postgresql(credentials_input)

# -------- Load Data ---------------------------------------------------
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = get_template("soil_metrics")
water_original = (pl.from_pandas(gpd.read_file(gdb_input,
                                              layer="AIM_Wetland__F_WaterQualityDetail",
                                              columns=["EvaluationID", "ChemistrySampleFrom", "Location", "Depth",
                                                       "StandFlow", "Temp", "TemperatureFlag", "pH", "phFlag", "EC",
                                                       "ConductivityFlag"],
                                              ignore_geometry=True))
                  .lazy())


# Join input files
soil_metrics_join = arcpy.management.AddJoin(in_layer_or_view=site_data_input, in_field='EvaluationID',
                                             join_table=soil_metrics_clean, join_field='EvaluationID',
                                             join_type='KEEP_COMMON',
                                             rebuild_index='REBUILD_INDEX')

# Convert to dataframe
soil_metrics_table = geodatabase_to_dataframe(soil_feature_output)

# Export dataframe
soil_metrics_table.to_csv(soil_table_output, index=False, encoding='UTF-8')
