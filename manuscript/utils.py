# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# utils.py
# Author: Amanda Droghini
# Last Updated: 2026-06-25
# ---------------------------------------------------------------------------

"""
This module provides utility functions for preparing the depositing of the AKVEG Database into a data repository.

Functions include:
1. check_schema_fields: Verify that all fields exist in the database_schema table.
2. map_sql_tables: Maps all tables created in SQL build scripts to the names of folders they will be exported to.
3. compile_sql_tables: Batch executes SQL queries to obtain a dictionary of flattened tables.
"""

# Import packages
import polars as pl
import re as re
import psycopg2.extensions
from typing import Tuple, List, Dict
from pathlib import WindowsPath

# --- Function 1 ---
def check_schema_fields(
        schema_df: pl.DataFrame,
        schema_columns: dict
) -> List[Tuple[str, str, str]]:
    """
    Compares the schema columns with a human-generated database schema table.
    Checks that every database field exists in the schema table, that all
    required fields are populated, and that conditional validation rules are met.

    Returns:
        A list of tuples: (table_name, column_name, error_reason)
    """

    # Create empty list for storing results
    missing_fields = []

    # Define required fields that can never be null
    required_fields = [
        col for col in schema_df.columns
        if col not in ['field_length', 'link_table_id',
                       'missing_value_code_id', 'missing_value_description']
    ]

    for table_key, columns in schema_columns.items():
        _, table_name = table_key

        for col in columns:
            col_name = col['name']

            # Extract column row from database schema table
            col_entry = schema_df.filter(
                (pl.col("schema_table") == table_name) &
                (pl.col("field") == col_name)
            )

            # --- Check #1: Is the field missing from the database schema table? ---
            if col_entry.is_empty():
                missing_fields.append((table_name, col_name, "Field missing from schema table"))
                continue

            # Convert to dictionary for conditional validation checks
            ## Needs to be placed after check #1 to prevent error if col_entry is empty
            row = col_entry.to_dicts()[0]

            # --- Check 2: Are any required fields null? ---
            has_nulls = any(row[field] is None for field in required_fields)
            if has_nulls:
                missing_fields.append((table_name, col_name, "One or more required fields are NULL"))
                continue   # Prevent loop from crashing or next checks from behaving unexpectedly if field needed for
                # following checks are missing

            # --- Check 3: Are foreign key fields linked to another table? ---
            is_foreign_key = row.get("is_foreign_key")
            if is_foreign_key and row.get("link_table_id") is None:
                missing_fields.append((table_name, col_name, "is_foreign_key is true, but link_table_id is NULL"))

            # --- Check 4: Do varchars fields have a field_length? ---
            data_type_value = row.get("data_type")
            if "varchar" in data_type_value and row.get("field_length") is None:
                missing_fields.append((table_name, col_name, "data_type is varchar, but field_length is NULL"))

    # --- Report results of quality checks ---
    if not missing_fields:
        print("All fields are valid.")
    else:
        print(f"Found {len(missing_fields)} validation errors:\n")
        for table, column, reason in missing_fields:
            print(f"| {table} | {column} | {reason} |")

    return missing_fields


# --- Function 2 ---
def map_sql_tables(
        folder_path: WindowsPath,
) -> Dict[str, str]:
    """
    Scans a directory for SQL files, extracts the names of all tables being created, and maps them to the name of the
    folder they will be exported to.

    Args: The path to the directory containing the SQL build files.

    Returns: A dictionary where the keys are the extracted table names and the values are the relative folder paths
    that the tables will be exported to.
    """

    # Create empty dictionary for storing results
    folder_dictionary = dict()

    # List all SQL files in directory
    file_list = [f for f in folder_path.glob("*.sql") if f.is_file()]

    # Loop through each SQL file
    for file in file_list:

        file_stem = file.stem.lower()

        with open(file, 'r', encoding='utf-8') as sql_file:
            sql_query = sql_file.read()

        # Define regex pattern for CREATE TABLE
        ## Couch table name ([a-z_]+ in parentheses to create capture
        regex_pattern = r'\nCREATE TABLE ([a-z_]+) \(\n'

        # Extract table names from SQL script
        table_names = re.findall(regex_pattern, sql_query)

        # Skip SQL files that do not create any tables (e.g., files that create roles)
        if len(table_names) == 0:
            continue

        # Create key-value pair for each table
        for table in table_names:
            if "taxon" in table:
                folder_dictionary[table] = "reference_tables/taxonomy"
            elif "schema" in table or "dictionary" in table or "data_type" in table:
                folder_dictionary[table] = "documentation"
            elif "metadata" in file_stem:
                folder_dictionary[table] = "reference_tables/field_lookups"
            elif "project_citations" in table:
                folder_dictionary[table] = "reference_tables/field_lookups"
            else:
                folder_dictionary[table] = "data_tables"

    return folder_dictionary


# --- Function 3 ---
def compile_sql_tables(folder_path: WindowsPath,
                       conn: psycopg2.extensions.connection
                       ) -> Dict[str, pl.DataFrame]:
    """
    Batch executes SQL queries and compiles the resulting flattened tables into Polars DataFrames.

    Args:
    folder_path: The path to the directory containing the SQL query files.
    conn: An active database connection used to execute the queries.

    Returns: A dictionary where the keys are the extracted table names and the values are the flattened Polars
    DataFrames.
    """

    # Create empty dictionary for storing results
    compiled_dictionary = dict()

    # List all SQL files in directory
    file_list = [f for f in folder_path.glob("*.sql") if f.is_file()]

    # Loop through each SQL file
    for file in file_list:

        with open(file, 'r', encoding='utf-8') as sql_file:
            # Read and execute SQL query
            sql_query = sql_file.read()

        # Extract table name from SQL query
        regex_pattern = r'\nFROM ([a-z_]+)\n'
        table_name = re.search(regex_pattern, sql_query).group(1)

        print(f"Compiling {table_name}...")

        if table_name == 'environment':
            compiled_df = pl.read_database(query=sql_query, connection=conn, infer_schema_length=None)
        else:
            compiled_df = pl.read_database(query=sql_query, connection=conn, infer_schema_length=5000)

        compiled_dictionary[table_name] = compiled_df

    return compiled_dictionary

