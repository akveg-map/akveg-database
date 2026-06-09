# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Add Yukon taxa to taxonomy table
# Author: Amanda Droghini
# Last Updated: 2026-02-11
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Add Yukon taxa to taxonomy table" appends taxa to be added to the taxonomy table and creates unique
# taxon short codes for the new taxa. The output is a .xlsx table that can be ingested in the AKVEG Database.
# ---------------------------------------------------------------------------

# Import libraries
import polars as pl
import taxonomy_utils as tx
from pathlib import Path

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
project_folder = root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database'
updates_folder = project_folder / 'Taxonomy_Updates' / '20260211_add_yukon_taxa'
output_folder = project_folder / 'Data' / 'Tables_Taxonomy'

# Define input
taxonomy_input = updates_folder / 'taxonomy_20260201.xlsx'

# Define output
taxonomy_output = output_folder / 'taxonomy.xlsx'

# Read in data
taxonomy_original = pl.read_excel(taxonomy_input,
                                  sheet_name='taxonomy',
                                  schema_overrides={'code_manual': pl.Int32}
                                  )
taxonomy_yukon = pl.read_excel(taxonomy_input,
                               sheet_name='yukon_to_add',
                               schema_overrides={'taxon_code': pl.String,
                                                 'code_manual': pl.Int32}
                               )

# Obtain taxon short code
## Function raises an error if there is a null value in the `taxon_name` column
yukon_codes = tx.generate_taxon_codes(taxonomy_yukon)

# Append Yukon taxa to existing taxonomy table
taxonomy_original.extend(yukon_codes)

# Correct duplicate codes
taxonomy_unique = tx.fix_duplicate_codes(taxonomy_original)

# Manually fix remaining duplicate codes
## Need to write a function to re-populate taxon code for all taxa
taxonomy_unique = (taxonomy_unique.with_columns(pl.col('taxon_name').str.to_lowercase()
                                                .str.slice(offset=0, length=7).alias('temp_code'))
                   .with_columns(pl.when(pl.col('taxon_code')
                                         .str.starts_with('hesper'))
                                 .then(pl.lit(1))
                                 .otherwise(pl.col('code_manual'))
                                 .alias('code_manual'),
                                 pl.when(pl.col('taxon_code')
                                         .str.starts_with('hesper'))
                                 .then(pl.col('temp_code'))
                                 .otherwise('taxon_code')
                                 .alias('taxon_code'))
                   .drop(pl.col('temp_code'))
                   )

# Perform final clean-up + null check
taxonomy_final = tx.final_cleanup(taxonomy_unique)

# Export as .xlsx
taxonomy_final.write_excel(taxonomy_output, worksheet="taxonomy")
