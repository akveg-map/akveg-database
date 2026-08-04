# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Export database tables
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-08-04
# Usage: Execute in Python 3.13+.
# Description: "Export database tables" verifies completeness of the database schema metadata, creates a set of
# compiled database tables by resolving references to lookup tables, and exports the compiled tables to
# CSVs for upload to a data repository.
# ---------------------------------------------------------------------------

# Import libraries
import polars as pl
import sqlalchemy as sa
import urllib.parse
from pathlib import Path
from utils import *

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
credential_folder = (root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database' /
                     "Credentials")
repository_folder = root / 'Repositories' / 'akveg-database'
sql_build_folder = repository_folder / '01_database_build'
query_folder = repository_folder / 'user_tools' / 'queries'
output_root = root / 'Projects' / 'AKVEG_Database' / 'Data_Deposit'

# Define inputs
credential_file = (credential_folder / "akveg_public_read" / "authentication_akveg_public_read.csv")

# Read in data
db_credentials = pl.read_csv(credential_file)

# --- Connect to the AKVEG Database ---

# Extract values from credentials file
db_host = db_credentials.filter(pl.col("parameter") == "host").select(pl.col("value")).item()
db_port = db_credentials.filter(pl.col("parameter") == "port").select(pl.col("value")).item()
db_user = db_credentials.filter(pl.col("parameter") == "user").select(pl.col("value")).item()
db_password = db_credentials.filter(pl.col("parameter") == "password").select(pl.col("value")).item()
db_name = db_credentials.filter(pl.col("parameter") == "dbname").select(pl.col("value")).item()

## Encode password string to handle special characters
encoded_password = urllib.parse.quote_plus(db_password)

## Extract SSL parameters
ssl_rootcert = db_credentials.filter(pl.col("parameter") == "sslrootcert").select(pl.col("value")).item()
ssl_cert = db_credentials.filter(pl.col("parameter") == "sslcert").select(pl.col("value")).item()
ssl_key = db_credentials.filter(pl.col("parameter") == "sslkey").select(pl.col("value")).item()

# Create URL from extracted values
db_url = f"postgresql+psycopg2://{db_user}:{encoded_password}@{db_host}:{db_port}/{db_name}"

# Define connection parameters to pass to connect_args
connect_args = {
    "sslmode": "verify-ca",
    "sslrootcert": ssl_rootcert,
    "sslcert": ssl_cert,
    "sslkey": ssl_key
}

# Create database engine
engine = sa.create_engine(db_url, connect_args=connect_args)

# --- Dynamically create output folder ---
## Using latest database version
query_version = f"""
SELECT major_version, minor_version, patch_version
FROM database_version
WHERE version_id = (
    SELECT
      MAX (version_id)
    FROM
      database_version
);
"""

version_df = pl.read_database(query=query_version, connection=engine)

# Concatenate version numbers into single version string
version_string = (version_df.with_columns(pl.concat_str([pl.lit("v"),
                                                         pl.col("major_version")],
                                                        separator="")
.alias("major_version")
                                          )
                  .with_columns(
    pl.concat_str(
        [pl.col("major_version"),
         pl.col("minor_version"),
         pl.col("patch_version")
         ],
        separator="_").alias("full_version")
)
                  .select("full_version")
                  .to_series()
                  .item()
                  )

# Establish output folder path
output_folder = output_root / version_string

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

# --- Export compiled database tables ---

# Create output folder
docs_dir = output_folder / 'full_documentation'
docs_dir.mkdir(parents=True, exist_ok=True)

# Create compiled tables using SQL query files
with engine.connect() as conn:
    compiled_dict = compile_sql_tables(folder_path=query_folder, conn=conn)

# Loop over dictionary items and export as CSV
for table_name, table_df in compiled_dict.items():
    # Update name for taxonomy table
    if table_name == 'taxon_all':
        file_name = 'taxonomy.csv'
    else:
        file_name = table_name + ".csv"

    # Define output file paths
    if table_name in ('database_dictionary', 'database_schema'):
        output_path = docs_dir / file_name
    else:
        output_path = output_folder / file_name

    # Export as CSV
    table_df.write_csv(output_path)

# Close engine connection
engine.dispose()
