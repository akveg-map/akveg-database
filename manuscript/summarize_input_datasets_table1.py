# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create project table
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-06-17
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
project_input = repository_folder / "user_tools" / "queries" / "01_project.sql"

# Define outputs
project_output =  manuscript_folder / 'table_projects.csv'
source_output = manuscript_folder / 'table_project_citations.csv'

# Define Unicode numbers in superscript
UNICODE_SUPERSCRIPTS = {"0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
                        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
                        }

# Connect to the AKVEG Database
akveg_db_connection = connect_database_postgresql(akveg_credentials)

# Read in queries
with open(project_input, 'r') as file:
    project_query = file.read()

# Query project table
project_table = query_to_dataframe(akveg_db_connection, project_query)
project_table = pl.from_pandas(project_table)

# Query project citations table
source_query = """
SELECT project_code, citation_short, citation_long, citation_url FROM project_citations
LEFT JOIN citations ON citations.citation_id = project_citations.citation_id
"""
source_table = query_to_dataframe(akveg_db_connection, source_query)
source_table = pl.from_pandas(source_table)

# --- Create bibliography for Table 1 ---
source_final = (source_table
                .unique()
                .sort("project_code")
                .with_columns(pl.concat_str(pl.col("citation_long"),
                                            pl.col("citation_url"),
                                            separator=" ")
                              .alias("citation_full"),
                              pl.int_range(pl.len()).over(pl.col("project_code")).alias("group_index")
                              )
                .with_row_index(name="citation_index", offset=1)  # Change offset to reflect citation order in MS
                .with_columns(pl.col("citation_index").cast(pl.String).alias("citation_index"))
                .with_columns(pl.col("citation_index").str.replace_many(UNICODE_SUPERSCRIPTS)
                              .alias("citation_index")
                              )
                .with_columns(pl.concat_str(pl.col("citation_short"),
                                            pl.col("citation_index"),
                                            separator=""
                                            ).alias("citation_superscript")
                              )
                .select("citation_index", "group_index", "project_code", "citation_superscript", "citation_full")
                )

# --- Create Table 1 --- #

# Pivot source table to wide format for superscript indices
citation_superscript = (source_final
        .pivot("group_index",
               index=["project_code"],
               values="citation_superscript")
        .sort("project_code")
                     )

# Combine citation index columns and format project table
project_final = (citation_superscript.lazy()
        .fill_null("")
        # Combine citation indices into a single string
        .with_columns(pl.concat_str(pl.all().exclude("project_code"),
                                    separator=", ")
                      .alias("citation_superscript")
                      )
        # Remove trailing comma and convert to Unicode superscript number
        .with_columns(pl.col("citation_superscript").str.strip_chars(", ").alias("citation_superscript")
                      )
        # Join with project table
        .join(project_table.lazy(), on="project_code")
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
                             separator="–"))
    .alias("temporal_extent"),
    # Add private caveat to NRCS project
    pl.when(pl.col("private"))
    .then(pl.concat_str(pl.col("project_name"), pl.lit("(private dataset)"),
                        separator=" "))
    .otherwise(pl.col("project_name"))
    .alias("project_name")
)
        # Select final columns and sort by project code
        .select(["project_code", "project_name", "temporal_extent", "source_type", "citation_superscript"])
        .sort("project_code")

        .collect()
        )

# --- Export Tables ---
project_final.write_csv(project_output)
source_final.write_csv(source_output)

# Close the database connection
akveg_db_connection.close()
