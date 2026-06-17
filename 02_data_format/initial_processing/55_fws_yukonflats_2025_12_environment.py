# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Environment Table for USFWS Yukon Flats 2025 data
# Author: Amanda Droghini
# Last Updated: 2026-06-16
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Environment for USFWS Yukon Flats 2025 data" formats the project's environment data by
# populating required metadata fields and re-classifying categorical values to adhere to the AKVEG Data Dictionary. The
# output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import polars as pl
from pathlib import Path
from akutils import connect_database_postgresql
from utils import get_template, get_valid_values, fill_missing_columns, AKVEG_FIELD_ALIASES

# Define directories
drive = Path('C:/')
root_folder = drive / 'ACCS_Work'

# Define folders
project_folder = (root_folder / 'OneDrive - University of Alaska' / 'ACCS_Teams' / 'Vegetation' /
                  'AKVEG_Database')
plot_folder = project_folder / 'Data' / 'Data_Plots' / '55_fws_yukonflats_2025'

# Define inputs
site_input = plot_folder / 'source' / 'YKF25_biomass_sites' / 'YKF25_biomass_sites.shp'
envr_input = plot_folder / 'source' / '12_usfws_yukonflats_2025_environment.xlsx'
visit_input = plot_folder / '03_sitevisit_fwsyukonflats2025.csv'
credential_file = project_folder / 'Credentials' / 'akveg_public_read' / 'authentication_akveg_public_read.csv'

# Define output
envr_output = plot_folder / '12_environment_fwsyukonflats2025.csv'

# Establish connection to AKVEG Database
akveg_db_connection = connect_database_postgresql(credential_file)

# Read in data
site_original = gpd.read_file(site_input, columns=['plotID', 'Topographi', 'Microtopog'])  # Can ignore
# warning
envr_original = pl.read_excel(envr_input, columns=["site_code","moisture_regime","drainage", "disturbance",
                                                   "disturbance_severity","disturbance_time_y", "depth_water_cm",
                                                   "depth_moss_duff_cm", "microrelief_cm", "surface_water"])
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = get_template("environment")

# --- Format site table ---
site_df = pl.from_pandas(site_original.drop(columns=['geometry']))

site_df = (site_df.rename({"plotID": "site_code"})
           .with_columns(pl.col("Topographi").str.replace_many(["flat", "closed depression"],
                                                           ["plane", "depression"])
                         .alias("macrotopography"),
                         pl.col("Microtopog").str.replace_many(["Minor depressions", "Tussucks"],
                                                           ["NULL", "tussocks"])
                         .alias("microtopography")
                         )
           .drop(["Topographi", "Microtopog"])
           )

# --- Join & format tables ---
envr_processed = (envr_original.with_columns(pl.col("site_code").str.replace_all("_", "").alias("site_code"),
                                             pl.lit(0).cast(pl.Boolean).alias("cryoturbation"),  # Confirmed with data
                                             # manager
                                             pl.when(pl.col("disturbance") == "riparian")
                                             .then(pl.lit("riverine"))  # Confirmed with data manager
                                             .otherwise(pl.lit("NULL"))
                                             .alias("physiography")
                                             )
                  .join(site_df, how="full", on="site_code")
                  .join(visit_original, how="right", on="site_code")
                  .drop("site_code_right")
                  .sort(by=["site_visit_code"])
                  )

## Populate missing columns
envr_final = fill_missing_columns(envr_processed, template)

# --- Quality checks ---

## Ensure no null values
envr_final.null_count().sum_horizontal().item()

## Verify that numeric values are within a reasonable range
envr_numeric = envr_final.select(
    pl.col(pl.Int64, pl.Decimal).replace(-999, None)
)
print(envr_numeric.describe())

## Verify that constrained values exist in the database dictionary
errors_found = False  # Initialize a flag to track any errors

for col in envr_final:
    if col.dtype == pl.String:
        field_name = col.name
        values_set = get_valid_values(db_connection=akveg_db_connection,
                                      table_name='database_dictionary',
                                      field_name=field_name,
                                      field_mapping=AKVEG_FIELD_ALIASES)
        if len(values_set) == 0:
            print(f"Set is empty for {field_name}")
        else:
            # Generate list of existing values in df but remove "NULL"
            existing_values = set(envr_final[field_name].unique()) - {"NULL"}
            # Compare with values in data dictionary
            if not existing_values.issubset(values_set):
                invalid_values = existing_values - values_set
                errors_found = True
                print(f"Column {field_name} contains invalid values: {invalid_values}")

if not errors_found:
    print("All values exist in database dictionary.")  # Print final success message

# Export data
envr_final.write_csv(envr_output)

# Close database connection
akveg_db_connection.close()
