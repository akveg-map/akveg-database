# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# utils.py
# Author: Amanda Droghini
# Last Updated: 2026-05-29
# ---------------------------------------------------------------------------

"""
This module provides utility functions for preparing the depositing of the AKVEG Database into a data repository.

Functions include:
1. check_schema_fields: Verify that all fields exist in the database_schema table.
"""

# Import packages
from typing import Tuple, List
import polars as pl

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
        if col not in ['field_length', 'link_table_id']
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
            is_key_true = row.get("is_key")
            is_foreign_key = "Foreign key" in str(row.get("field_description"))
            if is_key_true and is_foreign_key and row.get("link_table_id") is None:
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
