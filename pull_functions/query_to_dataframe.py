# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Query PostgreSQL database to return data frame
# Author: Timm Nawrocki, Alaska Center for Conservation Science
# Last Updated: 2026-08-24
# Usage: Can be executed in a Python 3.9+ distribution.
# Description: "Query PostgreSQL database to return data frame" is a function that queries a PostgreSQL connection and returns the query results as a Pandas dataframe.
# ---------------------------------------------------------------------------

# Define a function to query a PostgreSQL database and return that results as a Pandas dataframe
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
