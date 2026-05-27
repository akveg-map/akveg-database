# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Summarize records in tables
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-27
# Usage: Execute in Python 3.13+.
# Description: "Summarize records in tables" outputs a table with the number of records in each of AKVEG's 13 data tables.
# ---------------------------------------------------------------------------

# Import libraries
import polars as pl
from pathlib import Path
from akutils import connect_database_postgresql

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
credential_folder = (root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database' /
                     "Credentials")
repository_folder = root / 'Repositories' / 'akveg-database'
manuscript_folder = root / 'Projects' / 'AKVEG_Database' / 'Manuscript'

# Define inputs
akveg_credentials = (credential_folder / "akveg_private_read" / "authentication_akveg_private_read.csv")

# Define outputs
counts_output =  manuscript_folder / 'Tables' / 'table_record_counts.csv'

# Connect to the AKVEG Database
akveg_db_connection = connect_database_postgresql(akveg_credentials)

# Create cursor
cursor = akveg_db_connection.cursor()

# --- Get number of records for all data tables ---

# Define data tables
table_list = ['project', 'site', 'site_visit', 'vegetation_cover', 'abiotic_top_cover', 'ground_cover',
                'structural_group_cover', 'shrub_structure',
                'tree_structure',
                'environment', 'soil_metrics', 'soil_horizons']

# Build query segments
queries = [f"SELECT '{t}' as table_name, COUNT(*) FROM {t}" for t in table_list]

# Join segments with UNION ALL
full_query = "\nUNION ALL\n".join(queries)

# Execute query and store results in a dataframe
cursor.execute(full_query)
records = cursor.fetchall()
counts_df = pl.DataFrame(records, schema=["table_name", "row_count"], orient="row")

# --- Export output ---
counts_df.write_csv(counts_output)

# --- Close DB connection ---
cursor.close()
akveg_db_connection.close()
