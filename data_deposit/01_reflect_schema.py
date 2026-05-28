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

# Create database engine and Metadata
engine = sa.create_engine(db_url, connect_args=connect_args)
metadata = sa.MetaData()

# --- Get schema ---
# Reflect schema and get table names
insp = sa.inspect(engine)
table_names = insp.get_table_names()

metadata.reflect(bind=engine)

