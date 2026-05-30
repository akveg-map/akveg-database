# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Extract database tables
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-29
# Usage: Execute in Python 3.13+.
# Description: "Extract database tables" verifies completeness of the database schema metadata, and extracts all
# tables in the AKVEG Database.
# ---------------------------------------------------------------------------

# Import libraries
import polars as pl
import sqlalchemy as sa
from collections import Counter, defaultdict
from pathlib import Path
from utils import *


# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
credential_folder = (root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database' /
                     "Credentials")
sql_build_folder = root / 'Repositories' / 'akveg-database' / '01_database_build'

# Define inputs
credential_file = (credential_folder / "akveg_public_read" / "authentication_akveg_public_read.csv")

# Define outputs
###

# Read in data
db_credentials = pl.read_csv(credential_file)

# --- Connect to the AKVEG Database ---

# Extract values from credentials file
db_host = db_credentials.filter(pl.col("parameter") == "host").select(pl.col("value")).item()
db_port = db_credentials.filter(pl.col("parameter") == "port").select(pl.col("value")).item()
db_user = db_credentials.filter(pl.col("parameter") == "user").select(pl.col("value")).item()
db_password = db_credentials.filter(pl.col("parameter") == "password").select(pl.col("value")).item()
db_name = db_credentials.filter(pl.col("parameter") == "dbname").select(pl.col("value")).item()

## Extract SSL parameters
ssl_rootcert = db_credentials.filter(pl.col("parameter") == "sslrootcert").select(pl.col("value")).item()
ssl_cert = db_credentials.filter(pl.col("parameter") == "sslcert").select(pl.col("value")).item()
ssl_key = db_credentials.filter(pl.col("parameter") == "sslkey").select(pl.col("value")).item()

# Create URL from extracted values
db_url = f"postgresql+psycopg2://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"

# Define connection parameters to pass to connect_args
connect_args = {
    "sslmode": "verify-ca",
    "sslrootcert": ssl_rootcert,
    "sslcert": ssl_cert,
    "sslkey": ssl_key
}

# Create database engine
engine = sa.create_engine(db_url, connect_args=connect_args)

# --- Verify schema ---
insp = sa.inspect(engine)

# Extract schema metadata from all tables
schema_columns = insp.get_multi_columns()

# Read in database_schema table
query_schema = f"""
SELECT database_schema.*, schema_table.schema_table, data_type.data_type
FROM database_schema
LEFT JOIN schema_table on schema_table.schema_table_id = database_schema.schema_table_id
LEFT JOIN data_type on data_type.data_type_id = database_schema.data_type_id
"""

schema_df = pl.read_database(query=query_schema, connection=engine)

# Verify completeness of database_schema table
check_schema_fields(schema_df, schema_columns)

# --- Export database tables ---

# Map each SQL table to the name of the folder it will be exported to
folder_dictionary = map_sql_tables(sql_build_folder)

# Ensure number of files in which folder matches expectations.
folder_counts = Counter(folder_dictionary.values())
print(folder_counts)

# Close database connection
