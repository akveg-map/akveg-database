# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create project table
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-07
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
manuscript_folder = root / 'Projects' / 'AKVEG_Database' / 'Manuscript' / 'Tables'

# Define inputs
akveg_credentials = (credential_folder / "akveg_private_read" / "authentication_akveg_private_read.csv")
project_input = repository_folder / "queries" / "01_project.sql"

# Define outputs
project_output =  manuscript_folder / 'table_projects.csv'
source_output = manuscript_folder / 'table_project_citations.csv'

# Connect to the AKVEG Database
akveg_db_connection = connect_database_postgresql(akveg_credentials)

# Read in queries
with open(project_input, 'r') as file:
    project_query = file.read()

# Query project table
project_table = query_to_dataframe(akveg_db_connection, project_query)
project_table = pl.from_pandas(project_table)

# --- Get Table 1 references ---
source_final = (project_table
                  .select("citation_short", "citation_long", "citation_url")
                  .filter(pl.col("citation_short").is_not_null())
                  .unique()
                .with_columns(pl.concat_str(pl.col("citation_long"),
                                            pl.col("citation_url"),
                                            separator=" ")
                              .alias("citation_full"))
                .sort(by="citation_short")
                .select("citation_short", "citation_full")
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
    .then(pl.concat_str(pl.col("project_name"), pl.lit("(private dataset)"),
                                                   separator=" "))
    .otherwise(pl.col("project_name"))
    .alias("project_name"),
    # Combine source_type and Author-Year citation columns
    pl.when(pl.col("citation_short").is_null())
    .then(pl.col("source_type"))
    # Add "partially published" caveat for ACCS Nuyakuk 2019 project
    .when(pl.col("project_code") == "accs_nuyakuk_2019")
    .then(pl.concat_str(pl.col("citation_short"),
                        pl.lit("(partially published)"),
                        separator=" "))
    .otherwise(pl.col("citation_short"))
    .alias("citation_short")
)
                 # Select final columns
                 .select(["project_code", "project_name", "temporal_extent", "citation_short"])

                 .collect()
                 )

# --- Export Tables ---
project_final.write_csv(project_output)
source_final.write_csv(source_output)

# Close the database connection
akveg_db_connection.close()
