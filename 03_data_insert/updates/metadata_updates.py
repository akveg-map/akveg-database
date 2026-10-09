# Import packages
import polars as pl
import polars.selectors as cs
from pathlib import PureWindowsPath
from user_tools.utils_init import load_system_paths
from user_tools.utils_database import connect_database_postgresql

# Load file paths
paths = load_system_paths()

# Define inputs
metadata_folder = paths.cloud_assets.metadata
credentials = paths.cloud_assets.credentials
query_dict = paths.repository / "user_tools" / "queries" / "00_database_dictionary.sql"
query_schema = paths.repository / "user_tools" / "queries" / "00_database_schema.sql"
dict_input = metadata_folder / "database_dictionary.xlsx"

# List all Excel files in metadata directory
file_paths = [f for f in metadata_folder.glob("*.xlsx") if f.is_file()]
file_paths = [p for p in file_paths if not PureWindowsPath(p).name.endswith("project_status.xlsx")]

# Connect to AKVEG
db_connection = connect_database_postgresql(credentials)

# Read and execute SQL queries
query_files = [query_dict, query_schema]
queries = dict()

for query in query_files:
    with open(query, 'r', encoding='utf-8') as sql_file:
        sql_query = sql_file.read()
    query_sql = pl.read_database(query=sql_query, connection=db_connection)

    # Extract table name
    table_name = query.stem[3:]
    # Add query results to dictionary
    queries[table_name] = query_sql

# Read and format Excel tables
for xlsx in file_paths:
    table_name = xlsx.stem
    if table_name == "database_dictionary":
        metadata_df = pl.read_excel(xlsx, schema_overrides={"data_attribute_id": pl.String})
    elif table_name == "project_source":
        metadata_df = pl.read_excel(xlsx, sheet_name="project_citations")
    else:
        metadata_df = pl.read_excel(xlsx)

    # Enforce standard whitespaces
    metadata_df = metadata_df.with_columns(cs.string().str.replace_all(r"[^\S ]", value=" ").str.strip_chars())

    # Identify differences
    metadata_diff = metadata_df.join(queries[table_name], how="anti",
                                     on=metadata_df.columns)

# Align with schema
# Convert field to numeric id
# Create sequential primary key (update build script to auto-generate)

# Insert into lookup tables
# Use UPSERT

# Close database connection
db_connection.close()
