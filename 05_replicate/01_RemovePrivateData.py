# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Remove private data from AKVEG Database
# Author: Timm Nawrocki
# Last Updated: 2026-04-28
# Usage: Execute in Python 3.13+.
# Description: "Remove private data from AKVEG Database" retracts private data from all data tables to create a fully public version of the database.
# ---------------------------------------------------------------------------

# Import packages
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

# Define table list
table_list = ['soil_horizons', 'soil_metrics', 'environment', 'shrub_structure', 'tree_structure',
              'structural_group_cover', 'whole_tussock_cover',
              'ground_cover', 'abiotic_top_cover', 'vegetation_cover', 'site_visit']

# Create initial database connection
database_connection = connect_database_postgresql(authentication_file)

#### IDENTIFY PRIVATE SITES AND SITE VISITS
####------------------------------

# Create site and site visit queries
site_query = '''SELECT site_code FROM site
    LEFT JOIN project ON site.establishing_project_code = project.project_code
WHERE project.private IS TRUE'''
site_visit_query = '''SELECT site_visit_code FROM site_visit
    LEFT JOIN project ON site_visit.project_code = project.project_code
WHERE project.private IS TRUE'''

# Query database for private sites and site visits
site_remove = query_to_dataframe(database_connection, site_query)
site_visit_remove = query_to_dataframe(database_connection, site_visit_query)

# Convert query results to lists
site_list = site_remove['site_code'].tolist()
site_visit_list = site_visit_remove['site_visit_code'].tolist()

# Create cursor
cursor = database_connection.cursor()

#### REMOVE DATA FROM CORE TABLES
####------------------------------

# Remove private data from each table
for table in table_list:
    iteration_start = time.time()
    print(f'Removing private data from {table}...')

    # Execute deletion
    delete_private_data = f"DELETE FROM {table} WHERE site_visit_code IN ({str(site_visit_list)[1:-1]});"
    cursor.execute(delete_private_data)
    end_timing(iteration_start)

# Commit all deletes
database_connection.commit()

#### REMOVE DATA FROM SITE TABLE
####------------------------------

iteration_start = time.time()
print(f'Removing private data from site...')

delete_private_data = f"DELETE FROM site WHERE site_code IN ({str(site_list)[1:-1]});"
cursor.execute(delete_private_data)

end_timing(iteration_start)

# Commit deletes
database_connection.commit()

#### REMOVE DATA FROM PROJECT TABLE
####------------------------------

# Obtain private project codes
project_query = '''SELECT project_code FROM project
WHERE project.private IS TRUE'''

# Query database for private codes
project_remove = query_to_dataframe(database_connection, project_query)
project_list = project_remove['project_code'].tolist()

# Remove private data from project tables
print(f'Removing private data from project citations and project tables...')
iteration_start = time.time()

# Delete private data from project_citations table
delete_private_data = f"DELETE FROM project_citations WHERE project_code IN ({str(project_list)[1:-1]});"
cursor.execute(delete_private_data)

# Delete private data from project table
delete_private_data = f"DELETE FROM project WHERE private IS TRUE;"
cursor.execute(delete_private_data)

# Commit deletions
database_connection.commit()
end_timing(iteration_start)

# Close connection
cursor.close()
database_connection.close()
