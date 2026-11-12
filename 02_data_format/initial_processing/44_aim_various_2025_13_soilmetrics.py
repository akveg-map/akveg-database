# -*- coding: utf-8 -*-
"""Process Soil Metrics Table for BLM AIM 2022–2025 Data

Appends unique site visit identifiers, performs quality control checks, and exports the resulting table to CSV. Per
the AIM protocols, multiple ph, temperature, and EC measurements can be taken at a single site visit: typically,
one set of measurements for surface water and another for groundwater. The AKVEG Database allows for multiple water
measurements per site visit, provided they are taken at different depths.

Author: Amanda Droghini, Alaska Center for Conservation
Last Updated: 2026-11-10
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
import geopandas as gpd
import polars as pl
import polars.selectors as cs

from user_tools.utils_database import connect_database_postgresql
from user_tools.utils_init import load_system_paths
from utils.utils import check_conductivity_values, check_ph_values, get_template

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
soil_original = (pl.from_pandas(gpd.read_file(gdb_input,
                                              layer="AIM_Wetland__F_WaterQualityDetail",
                                              columns=["EvaluationID", "ChemistrySampleFrom", "Location", "WaterDepth",
                                                       "Temp", "TemperatureFlag", "pH", "phFlag", "EC",
                                                       "ConductivityFlag", "TempCorrected", "SampleType"],
                                              ignore_geometry=True)))

# -------- Prepare Input Data ------------------------------------------
soil_metrics = (soil_original.with_columns(
    # Replace whitespaces with nulls
    cs.string().str.strip_chars().replace("", None),
    # Extract site code
    pl.col("EvaluationID")
    .str.extract(r"^(.*)_")
    .alias("site_code"))
                # Append site visit code
                .join(visit_original, on="site_code", how="left")
                # Rename columns
                .rename({"WaterDepth": "measure_depth_cm",
                         "pH": "ph",
                         "Temp": "temperature_deg_c",
                         "EC": "conductivity_mus"})
                # Create Boolean column indicating whether measurement was taken from water or soil
                .with_columns(pl.when(pl.col("ChemistrySampleFrom").str.contains("[wW]ater"))
                              .then(pl.lit("TRUE"))
                              .otherwise(pl.lit("FALSE"))  # Should not be any FALSE entries; measurements only taken
                              # in water
                              .alias("water_measurement")
                              )
                # Convert temperature entries with "suspect" flag to missing value code (-999)
                .with_columns(pl.when(pl.col("TemperatureFlag").str.contains("Suspect"))
                              .then(pl.lit("-999").cast(pl.Int32))
                              .otherwise(pl.col("temperature_deg_c"))
                              .alias("temperature_deg_c")
                              )
                # Fill null values in numeric columns to missing value code (-999)
                .with_columns(cs.numeric().fill_null(-999))
                )

# -------- Perform Quality Checks --------------------------------------

# All sites have a visit code
print(soil_metrics.select(pl.col("site_visit_code")).null_count())

# All visits in Soil Metrics table appear in Site Visit table
# Only need to test in a single direction (not all site visits need to have soil metrics)
set_soil = set(soil_metrics.get_column("site_visit_code").unique().to_list())
set_visit = set(visit_original.get_column("site_visit_code").unique().to_list())
print(set_soil - set_visit)

# All samples from a Soil Pit have negative water depth value (resulting df should be empty)
# WaterDepth follows same convention as AKVEG: positive if above soil surface, negative if below
print(soil_metrics.filter((pl.col("Location") == "Soil Pit") & (pl.col("measure_depth_cm") > 0))
      .select(pl.col("site_visit_code")))

# Conductivity and pH flags do not include "Suspect" entries
print(pl.concat(soil_metrics.select(["ConductivityFlag", "phFlag"])).unique())

# Numeric values are within reasonable range
invalid_ph = check_ph_values(soil_metrics)  # No outliers
invalid_conductivity = check_conductivity_values(soil_metrics)  # OK to keep in dataset

# Temperature check - Remove missing value code (-999) before calculating summary statistics
print(soil_metrics.select(pl.col("temperature_deg_c")).filter(pl.col("temperature_deg_c") > -999).describe())

# Measurement depth
print(soil_metrics.select(pl.col("measure_depth_cm")).describe())
invalid_depth = soil_metrics.filter(pl.col("measure_depth_cm") > 30)  # Keep for now

# -------- Export Data -------------------------------------------------
soil_metrics.select(template.columns).write_csv(soil_metrics_output)

# -------- Close Database Connection -----------------------------------
db_conn.close()
