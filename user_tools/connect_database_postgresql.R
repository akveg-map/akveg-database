# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create connection to PostgreSQL database
# Author: Timm Nawrocki, Alaska Center for Conservation Science
# Last Updated: 2020-11-10
# Usage: Script should be executed in R 4.0.0+.
# Description: "Create connection to PostgreSQL database" is a function that loads a PostgreSQL connection and returns that connection to a variable. The connection function requires that the RPostgres library be loaded in the calling script.
# ---------------------------------------------------------------------------

# Define a function to create a connection to a PostgreSQL database
connect_database_postgresql = function(authentication) {
  # Description: creates a connection to a PostgreSQL database.
  # Inputs: authentication -- a csv file containing the connection and authentication parameters
  # Returned Value: function returns connection to PostgreSQL database.
  # Preconditions: requires an existing PostgreSQL database with proper authentication by SSL set up and authentication files with the client
  
  # Parse authentication parameters from csv
  parameters = read.csv(authentication, fileEncoding = 'UTF-8')
  host = parameters[which(parameters$parameter == 'host'), 'value']
  port = parameters[which(parameters$parameter == 'port'), 'value']
  user = parameters[which(parameters$parameter == 'user'), 'value']
  password = parameters[which(parameters$parameter == 'password'), 'value']
  dbname = parameters[which(parameters$parameter == 'dbname'), 'value']
  sslmode = parameters[which(parameters$parameter == 'sslmode'), 'value']
  sslfactory = parameters[which(parameters$parameter == 'sslfactory'), 'value']
  sslrootcert = parameters[which(parameters$parameter == 'sslrootcert'), 'value']
  sslcert = parameters[which(parameters$parameter == 'sslcert'), 'value']
  sslkey = parameters[which(parameters$parameter == 'sslkey'), 'value']
  
  # Read connection based on parameters
  connection = dbConnect(
    RPostgres::Postgres(),
    host = host,
    port = port,
    user = user,
    password = password,
    dbname = dbname,
    sslmode = sslmode,
    sslfactory = sslfactory,
    sslrootcert = sslrootcert,
    sslcert = sslcert,
    sslkey = sslkey
    )
  
  # Return database connection
  return(connection)
}