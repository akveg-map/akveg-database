"""
Taxonomy Utilities Module

A collection of Polars-based tools for processing and validating taxonomic data.

Functions:
1. generate_taxon_codes: Standardizes taxonomic short codes into 6+ character codes.
2. fix_duplicate_codes: Resolves duplicate taxonomic codes by adding sequential numbers to the end of duplicate
codes.
3. final_cleanup: Normalizes whitespaces, including NBSP spaces, and checks for null values.

Note: This module assumes a unique 'taxon_name' column exists.
"""

import polars as pl

# Define columns for final output
FINAL_SCHEMA = ['taxon_code',
                'code_manual',
                'taxon_name',
                'taxon_author',
                'taxon_status',
                'taxon_accepted',
                'taxon_author_accepted',
                'taxon_family',
                'taxon_source',
                'taxon_link',
                'taxon_level',
                'taxon_category',
                'taxon_habit',
                'taxon_native',
                'taxon_non_native',
                'org']

# ---- Function 1 ----
def generate_taxon_codes(taxon_df: pl.DataFrame) -> pl.DataFrame:
    """
    Takes a dataframe with a 'taxon_name' column and generates
    a 'taxon_code' based on hierarchical taxonomic rules.
    """

    # Ensure 'taxon_name' column exists
    if "taxon_name" not in taxon_df.columns:
        raise ValueError("Input DataFrame must contain a 'taxon_name' column.")

    # Ensure there are no nulls in the 'taxon_name' column
    if taxon_df.select(pl.col("taxon_name")).null_count().item() > 0:
        raise ValueError("Null values found in 'taxon_name' column.")

    processed_df = (taxon_df.with_columns(
        pl.col('taxon_name')
        .str.to_lowercase()
        .str.splitn(by=" ", n=4)
        .struct.rename_fields(["genus", "species", "infratype", "infraspecies"])
        .alias("taxon_split")
    )
    .with_columns(
        genus6 = pl.col("taxon_split").struct.field("genus").str.slice(0, 6),
        genus3 = pl.col("taxon_split").struct.field("genus").str.slice(0, 3),
        species3 = pl.col("taxon_split").struct.field("species").str.slice(0, 3),
        infratype1 = pl.col("taxon_split").struct.field("infratype").str.slice(0, 1),
        infraspecies3 = pl.col("taxon_split").struct.field("infraspecies").str.slice(0, 3)
    )
    .with_columns(pl.when(pl.col('species3').is_null())
                  .then(pl.col('genus6'))
                  .otherwise(pl.coalesce(pl.concat_str(['genus3', 'species3','infratype1','infraspecies3']),
                                         pl.concat_str(['genus3', 'species3']))).alias('taxon_code'))
    .drop(["taxon_split", "genus6", "genus3", "species3", "infratype1", "infraspecies3"])
                    )

    return processed_df


# ---- Function 2 ----
def fix_duplicate_codes(taxon_df: pl.DataFrame) -> pl.DataFrame:
    """
    Corrects duplicate entries in a 'taxon_code' column.
    If duplicate codes exist, the function:
    1. Adds a sequential number to both codes (for genus and species).
    2. Adds an additional letter to the end of the code (for infraspecies).
    """

    # Ensure 'taxon_name' column is unique
    if taxon_df.select(pl.col('taxon_name').is_duplicated().sum()).item() > 0:
        raise ValueError("Duplicate values found in 'taxon_name' column.")

    # Fix duplicate codes
    processed_df = (taxon_df
                    .sort("taxon_name")
                    ## Create a counter for taxon codes
                    .with_columns(pl.col('taxon_code')
                                  .cum_count()
                                  .over("taxon_code")
                                  .cast(pl.String)
                                  .alias('counter'),
                                  pl.col("taxon_code")
                                  .str.len_chars()
                                  .alias('code_length'))
                    ## Identify duplicate codes
                    .with_columns(pl.col('taxon_code').len().over("taxon_code").alias('group_length'))
                    ## Append counter to taxon code for duplicate codes only
                    .with_columns(pl.when((pl.col('group_length') > 1) & (pl.col('code_length') <= 6))
                                  .then(pl.concat_str([pl.col("taxon_code"),
                                                       pl.col('counter')]))
                                  .when((pl.col('group_length') > 1) & (pl.col('code_length') > 6))
                                  ## Placeholder for infraspecies error
                                  .then(pl.lit("MANUAL_REVIEW"))
                                  .otherwise(pl.col('taxon_code'))
                                  .alias("taxon_code"))
                    ## Populate 'code_manual' column
                    .with_columns(pl.when(pl.col('taxon_code') == "MANUAL_REVIEW")
                                  .then(pl.lit(1))
                                  .otherwise(pl.lit(0))
                                  .alias('code_manual'))
                    .drop(['counter', 'code_length', 'group_length'])
                    )
    # Report any infraspecies duplicate for which the logic still needs to be coded
    review_needed_infra = processed_df.filter(pl.col("taxon_code") == "MANUAL_REVIEW")

    if not review_needed_infra.is_empty():
        print("Infraspecies duplicates detected; logic undefined.")
        print(review_needed_infra.select(["taxon_name", "taxon_code"]))
    else:
        print("No infraspecies duplicates found.")

    # Report any codes that are still duplicated (internal trouble-shooting)
    review_needed_code = processed_df.filter(pl.col("taxon_code").is_duplicated())

    if not review_needed_code.is_empty():
        print("Duplicate values found in 'taxon_code' column.")
        print(review_needed_code.select(["taxon_name", "taxon_code"]))

    return processed_df

# ---- Function 3 ----
def final_cleanup(taxon_df: pl.DataFrame) -> pl.DataFrame:
    """
    Cleans string data across all columns in the DataFrame.

    Removes non-standard spaces, multiple consecutive spaces, and leading and trailing spaces, and drops empty rows.
    """

    cleaned_df = (taxon_df.with_columns(
            pl.col(pl.String)
            # Convert NBSP to standard whitespace
            .str.replace_all(r"\u00A0", " ")
            # Collapse multiple spaces into one
            .str.replace_all(r"\s+", " ")
            # Remove leading and trailing whitespaces
            .str.strip_chars()
        )
        # Drop entirely empty rows
        .filter(~pl.all_horizontal(pl.all().is_null()))
        # Sort by taxon name
        .sort("taxon_name")
        # Select template columns
        .select(FINAL_SCHEMA)
    )

    # Ensure there are no null values in the df
    total_nulls = cleaned_df.null_count().sum_horizontal().item()

    if total_nulls > 0:
        print(f"WARNING: {total_nulls} Null values detected in the dataset.")
        # Print which columns have the nulls
        null_cols = cleaned_df.null_count()
        with pl.Config() as cfg:
            cfg.set_tbl_cols(16)
            print(null_cols.null_count())

    # Ensure taxon_name and taxon_code columns are unique
    duplicate_mask = pl.col('taxon_code').is_duplicated() | pl.col('taxon_name').is_duplicated()
    duplicates_df = cleaned_df.filter(duplicate_mask).select(['taxon_code', 'taxon_name'])
    total_duplicates = duplicates_df.height

    if total_duplicates > 0:
        print(f"WARNING: {total_duplicates} rows with duplicate values detected.")
        print(duplicates_df)

    return cleaned_df

