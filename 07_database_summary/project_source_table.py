# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create project table
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-05
# Usage: Execute in Python 3.13+.
# Description: "Create project source table" formats the project and citations tables in the AKVEG Database to
# produce Table 1 (Droghini et al., in prep.) and associated bibliographic references.
# ---------------------------------------------------------------------------

# Import libraries
import polars as pl
from pathlib import Path
from akutils import connect_database_postgresql
from akutils import query_to_dataframe

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
project_folder = root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database'
repository_folder = root / 'Repositories' / 'akveg-database'
credential_folder = project_folder / "Credentials"

# Define inputs
akveg_credentials = (credential_folder / "akveg_private_read" / "authentication_akveg_private_read.csv")
project_input = repository_folder / "queries" / "01_project.sql"

# Define outputs
project_output = root / 'Projects' / 'AKVEG_Database' / 'Manuscript' / 'Tables' / 'project_source.csv'

# Read in queries
with open(project_input, 'r') as file:
    project_query = file.read()

# Connect to the AKVEG Database
akveg_db_connection = connect_database_postgresql(akveg_credentials)

# Create cursor
cursor = akveg_db_connection.cursor()

# Query project table
project_table = query_to_dataframe(akveg_db_connection, project_query)
project_table = pl.from_pandas(project_table)

# --- Get Table 1 references ---
unique_sources = (project_table
                  .select("source_citation")
                  .filter(pl.col("source_citation").is_not_null())
                  .unique()
                  .to_series()
                  .to_list())

# Create placeholders for SQL query
query_placeholders = ",".join(["%s"] * len(unique_sources))

# Construct the query string
query_sources = (f"SELECT citation_short, citation_long, citation_url FROM citations WHERE citation_short IN "
                 f"({query_placeholders})")

# Execute query
cursor.execute(query_sources, unique_sources)
records = cursor.fetchall()
column_names = [desc[0] for desc in cursor.description]
source_table = pl.DataFrame(records, schema=column_names, orient="row")

# Update URL for LANDFIRE reference (use web page instead of direct download link)
source_final = source_table.with_columns(pl.when(pl.col("citation_short") == "LANDFIRE 2016")
                                         .then(pl.lit(
                                               "https://landfire.gov/reference/lfrdb/lfrdb_data"))
                                         .otherwise(pl.col("citation_url"))
                                         .alias("citation_url")
                                         )

# --- Create Table 1 --- #
project_final = (project_table.lazy()
                 .with_columns(
                               # Change year end for ongoing projects to reflect last year of data in AKVEG
                               pl.when(pl.col("project_code") == "yukon_biophysical_2020")
                               .then(pl.lit("2020"))
                               .when(pl.col("project_code") == "nrcs_soils_2024")
                               .then(pl.lit("2024"))
                               .otherwise(pl.col("year_end").cast(pl.String))
                               .alias("year_end"),
                               pl.col("year_start").cast(pl.String))
                 .with_columns(
    # Concatenate year_start and year_end into a range of years
    pl.when(pl.col("year_start") == pl.col("year_end"))
    .then(pl.col("year_start"))
    .otherwise(pl.concat_str(pl.col("year_start"),
                             pl.col("year_end"),
                             separator="-"))
    .alias("temporal_extent"),
    # Add private caveat to NRCS project
    pl.when(pl.col("private"))
    .then(pl.concat_str(pl.col("project_code"), pl.lit("(private dataset)"),
                                                   separator=" "))
    .otherwise(pl.col("project_code"))
    .alias("project_code"),
    # Combine source_type and source_citation columns
    pl.when(pl.col("source_citation").is_null())
    .then(pl.col("source_type"))
    # Add "partially published" caveat for ACCS Nuyakuk 2019 project
    .when(pl.col("project_code") == "accs_nuyakuk_2019")
    .then(pl.concat_str(pl.col("source_citation"),
                        pl.lit("(partially published)"),
                        separator=" "))
    .otherwise(pl.col("source_citation"))
    .alias("source_citation")
)
                 # Select final columns
                 .select(["project_code", "project_name", "temporal_extent", "source_citation"])

                 .collect()
                 )


# Export table
project_final.write_csv(project_output)

# Close the database connection
cursor.close()
akveg_db_connection.close()