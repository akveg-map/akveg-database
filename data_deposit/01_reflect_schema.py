# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Write README for data deposit
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-27
# Usage: Execute in Python 3.13+.
# Description: "Write README for data deposit" extracts data and schema from the AKVEG Database, and formats it into
# a README file to accompany a deposit in a data repository.
# ---------------------------------------------------------------------------

# Import libraries
import polars as pl
import sqlalchemy as sa
from pathlib import Path

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
credential_folder = (root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database' /
                     "Credentials")
repository_folder = root / 'Repositories' / 'akveg-database'

# Define input
credential_file = (credential_folder / "akveg_private_read" / "authentication_akveg_private_read.csv")

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

# --- Get schema ---
insp = sa.inspect(engine)

# Extract schema metadata from all tables
all_columns = insp.get_multi_columns()
all_pks = insp.get_multi_pk_constraint()
all_fks = insp.get_multi_foreign_keys()

# --- Get column descriptions ---
# Info is stored in the database_schema table
query_schema = f"""
SELECT schema_table.schema_table, field, field_description
FROM database_schema
LEFT JOIN schema_table on schema_table.schema_table_id = database_schema.schema_table_id
"""

# Pass the engine directly to the connection parameter
schema_df = pl.read_database(query=query_schema, connection=engine)

# --- Create README tables ---
# Loop through all tables and columns
for table_key, columns in all_columns.items():
    # Unpack tuple (schema_name is 'None' - public - for akveg)
    schema_name, table_name = table_key
    # Extract primary key data and column name
    pk_data = all_pks.get(table_key, {})
    pk_cols = pk_data.get('constrained_columns', [])

    # Extract foreign key data and column names
    fk_data = all_fks.get(table_key, [])
    fk_cols = [col for fk in fk_data for col in fk['referred_columns']]

    print(f"### Table: {table_name}")
    print("| Column Name | Description | Type | Primary Key | Foreign Key |")
    print("| --- | --- | --- | --- | --- |")

    for col in columns:
        print(f"Looking up: Table={table_name}, Column={col_name}")
        col_name = col['name']
        col_type = str(col['type'])
        is_pk = "Yes" if col_name in pk_cols else "No"
        is_fk = "Yes" if col_name in fk_cols else "No"
        col_desc = (schema_df.filter(
            (pl.col("schema_table") == table_name) &
            (pl.col("field") == col_name)
        ).select(pl.col("field_description"))
                    .item()
                    )

        print(f"| {col_name} | {col_desc} | {col_type} | {is_pk} | {is_fk} |")

