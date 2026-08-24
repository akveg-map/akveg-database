# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# utils_database.py
# Author: Timm Nawrocki, Alaska Center for Conservation Science
# Last Updated: 2026-08-24
# Usage: Can be executed in a Python 3.9+ distribution.
# ---------------------------------------------------------------------------

"""
This module provides utility functions for connecting to and querying the live version of the AKVEG Database.

Functions include:
1. connect_database_postgresql: Creates a PostgreSQL connection using credentials stored in a CSV file, and returns that connection as a variable.
2. query_to_dataframe: Queries a PostgreSQL connection and returns the results as a Pandas dataframe.

"""

# --- Function 1 ---

# Define a function to create a connection to a PostgreSQL database
def connect_database_postgresql(authentication):
    """
    Description: creates a connection to a PostgreSQL database.
    Inputs: authentication -- a csv file containing the connection and authentication parameters
    Returned Value: function returns connection to PostgreSQL database.
    Preconditions: requires an existing PostgreSQL database with proper authentication by SSL set up and authentication files with the client
    """

    # Import packages
    import psycopg2
    import pandas as pd

    # Parse authentication parameters from csv
    parameters = pd.read_csv(authentication)
    parameter_dictionary = {
        'hostaddr': parameters.at[parameters.index[parameters['parameter'] == 'host'][0], 'value'],
        'port': parameters.at[parameters.index[parameters['parameter'] == 'port'][0], 'value'],
        'user': parameters.at[parameters.index[parameters['parameter'] == 'user'][0], 'value'],
        'password': parameters.at[parameters.index[parameters['parameter'] == 'password'][0], 'value'],
        'dbname': parameters.at[parameters.index[parameters['parameter'] == 'dbname'][0], 'value'],
        'sslmode': parameters.at[parameters.index[parameters['parameter'] == 'sslmode'][0], 'value'],
        'sslrootcert': parameters.at[parameters.index[parameters['parameter'] == 'sslrootcert'][0], 'value'],
        'sslcert': parameters.at[parameters.index[parameters['parameter'] == 'sslcert'][0], 'value'],
        'sslkey': parameters.at[parameters.index[parameters['parameter'] == 'sslkey'][0], 'value'],
    }

    # Establish database connection using authentication parameters
    try:
        print('Connecting to the PostgreSQL database...')
        connection = psycopg2.connect(**parameter_dictionary)
    # Return error if connection fails
    except (Exception, psycopg2.DatabaseError) as error:
        print("Error: %s" % error)
        return None
    print("Connection successful")
    # Return the database connection
    return connection


# --- Function 2 ---

# Define a function to create a connection to a PostgreSQL database
def query_to_dataframe(connection, query):
    """
    Description: queries a PostgreSQL connection and returns results as a dataframe.
    Inputs: connection -- an existing Python connection to the PostgreSQL database
            query -- a SQL query to execute on the database
    Returned Value: Function returns connection to PostgreSQL database.
    Preconditions: requires an existing PostgreSQL connection created with the create_connection_postgresql function
    """

    # Import packages
    import psycopg2
    import pandas as pd

    # Create a cursor object to execute the query
    cursor = connection.cursor()
    # Execute the query and define column names
    try:
        cursor.execute(query)
        column_names = [desc[0] for desc in cursor.description]
    # Return error if query fails
    except (Exception, psycopg2.DatabaseError) as error:
        print("Error: %s" % error)
        cursor.close()
        return 1

    # Store query results as pandas dataframe
    query_result = pd.DataFrame(cursor.fetchall(), columns=column_names)
    cursor.close()

    # Return dataframe
    return query_result
