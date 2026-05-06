# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Remove private data from AKVEG Database
# Author: Timm Nawrocki, Amanda Droghini
# Last Updated: 2026-05-06
# Usage: Execute in Python 3.13+.
# Description: "Remove private data from AKVEG Database" retracts private data from all data tables to create a public version of the database.
# ---------------------------------------------------------------------------

# Import packages
import polars as pl
import os
import time
from akutils import connect_database_postgresql
from akutils import query_to_dataframe
from akutils import end_timing

# Set root directory
drive = 'C:/'
root_folder = 'ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database'

# Define folder structure
credential_folder = os.path.join(drive, root_folder, 'Credentials')
repository_folder = os.path.join(drive, 'ACCS_Work', 'Repositories', 'akveg-database')

# Define input files
authentication_file = os.path.join(credential_folder, 'akveg_public_build/authentication_akveg_public_build.csv')
sensitive_file = os.path.join(drive, root_folder, 'Data', 'Tables_Taxonomy', 'sensitive_species',
                              'RarePlant_Dataset_Apr2026.xlsx')

# Create initial database connection
database_connection = connect_database_postgresql(authentication_file)

# Create cursor
cursor = database_connection.cursor()

# ---------------------------------- #
# --- IDENTIFY SENSITIVE SPECIES --- #
# ---------------------------------- #

# Obtain taxon code from database
taxonomy_query = '''
SELECT taxon_all.taxon_name as taxon_name
, taxon_all.taxon_code as taxon_code
, taxon_all.taxon_accepted_code as taxon_accepted_code
, taxon_category.taxon_category as taxon_category
, taxon_habit.taxon_habit as taxon_habit
FROM taxon_all
LEFT JOIN taxon_accepted ON taxon_all.taxon_accepted_code = taxon_accepted.taxon_accepted_code
LEFT JOIN taxon_all taxon_genus_name ON taxon_accepted.taxon_genus_code = taxon_genus_name.taxon_code
LEFT JOIN taxon_hierarchy ON taxon_accepted.taxon_genus_code = taxon_hierarchy.taxon_genus_code
LEFT JOIN taxon_category ON taxon_hierarchy.taxon_category_id = taxon_category.taxon_category_id
LEFT JOIN taxon_habit ON taxon_accepted.taxon_habit_id = taxon_habit.taxon_habit_id
'''

taxonomy_akveg = query_to_dataframe(database_connection, taxonomy_query)

# Join complete taxonomy table with sensitive species list to obtain code adjudicated
sensitive_species = ((pl.read_excel(sensitive_file, sheet_name="Species", columns="TAXON")
                      .lazy()
                     .with_columns(pl.when(pl.col("TAXON") == "Zannichellia palustris ssp. palustris")
                                   .then(pl.lit("Zannichellia palustris"))
                                   .when(pl.col("TAXON") == "Corallorhiza maculata var. maculata")
                                   .then(pl.lit("Corallorhiza maculata"))
                                   .otherwise(pl.col("TAXON")).alias("TAXON"))
                     .join(pl.DataFrame(taxonomy_akveg).lazy(), how="left", left_on="TAXON", right_on="taxon_name"))
                     .filter(~pl.col("taxon_accepted_code").is_null())
                     .select(pl.concat_list(["taxon_code", "taxon_accepted_code"]).list.explode().unique())
                     .collect())

sensitive_list = sensitive_species["taxon_code"].to_list()

# -------------------------------- #
# --- IDENTIFY SITES TO REDACT --- #
# -------------------------------- #

# Extract identifiers associated with private projects
site_query = '''
SELECT site_code FROM site 
LEFT JOIN project ON site.establishing_project_code = project.project_code
WHERE project.private IS TRUE
'''

site_visit_query = '''
SELECT site_visit_code FROM site_visit 
LEFT JOIN project ON site_visit.project_code = project.project_code
WHERE project.private IS TRUE
'''

project_query = '''
SELECT project_code FROM project
WHERE project.private IS TRUE
'''

# Identify site visits belonging to BLM AIM projects
## These site visits will have sensitive species redacted from the vegetation cover table
## At the request of the BLM National Office

sensitive_query = '''
SELECT site_visit_code FROM site_visit 
LEFT JOIN project ON site_visit.project_code = project.project_code 
WHERE project.project_code LIKE 'aim%'
'''

# Combine queries in a dictionary
queries_dict = {
    "sensitive_visit_codes": sensitive_query,
    "site_visit_codes": site_visit_query,
    "site_codes": site_query,
    "project_codes": project_query
}

# Create empty dictionary for storing query results
query_results = {}

# Query database for private sites and site visits
for name, query in queries_dict.items():
        cursor.execute(query)
        records = cursor.fetchall()
        query_list = [row[0] for row in records]

        # Store in the dictionary
        query_results[name] = query_list

# Define tables on which to apply deletions
tables_to_clean = {
    "sensitive_visit_codes": [
        "vegetation_cover"
    ],
    "site_visit_codes": [
        'soil_horizons', 'soil_metrics', 'environment', 'shrub_structure', 'tree_structure',
        'structural_group_cover', 'whole_tussock_cover',
        'ground_cover', 'abiotic_top_cover', 'vegetation_cover', 'site_visit'
    ],
    "site_codes": [
        "site",
    ],
    "project_codes": [
        "project_citations",
        "project"
    ]
}

# Define column to use as ID column
key_to_column = {
    "sensitive_visit_codes": "site_visit_code",
    "site_visit_codes": "site_visit_code",
    "site_codes": "site_code",
    "project_codes": "project_code",
}

# ------------------------------- #
# --- REMOVE DATA FROM TABLES --- #
# ------------------------------- #

try:
    # Iterate through the tables to clean
    for key, tables in tables_to_clean.items():

        # Skip empty query results
        if not query_results[key]:
            print(f"No records to redact for {key}, skipping...")
            continue

        # Generate placeholders once for the current list length
        placeholders = ",".join(["%s"] * len(query_results[key]))

        for table in tables:
            iteration_start = time.time()
            print(f"Removing private data from {table}...")

            # Define the column name based on key type
            id_column = key_to_column[key]

            if key == "sensitive_visit_codes":
                # Generate placeholders for sensitive species list
                species_placeholders = ",".join(["%s"] * len(sensitive_list))

                # Define query to delete only sensitive species
                redact_species_data = f"""
                DELETE FROM {table} 
                WHERE site_visit_code IN ({placeholders}) 
                AND code_adjudicated IN ({species_placeholders});
                """

                # Flatten parameters into a single tuple/list
                params = query_results[key] + sensitive_list
                cursor.execute(redact_species_data, params)
                end_timing(iteration_start)

            else:
                delete_private_data = f"DELETE FROM {table} WHERE {id_column} IN ({placeholders});"
                cursor.execute(delete_private_data, query_results[key])
                end_timing(iteration_start)

    # Commit deletions
    database_connection.commit()
    print("All deletions have been committed successfully.")

except Exception as e:
    # Roll back changes if an error occurs
    database_connection.rollback()
    print(f"An error occurred: {e}. Changes have been rolled back.")

finally:
    # Close connection
    cursor.close()
    database_connection.close()
    print("Database connection closed.")
