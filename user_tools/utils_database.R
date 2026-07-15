#' Create connection to PostgreSQL database
#'
#' Loads a PostgreSQL connection and returns that connection to a variable. The connection function requires an existing PostgreSQL database with proper authentication by SSL set up and authentication files with the client.
#'
#' @author Timm Nawrocki
#'
#' @param authentication A csv file containing the connection and authentication parameters
#'
#' @returns Connection to PostgreSQL database
#'

connect_database_postgresql <- function(authentication) {
  # Parse authentication parameters from csv
  parameters <- read.csv(authentication, fileEncoding = "UTF-8")
  host <- parameters[which(parameters$parameter == "host"), "value"]
  port <- parameters[which(parameters$parameter == "port"), "value"]
  user <- parameters[which(parameters$parameter == "user"), "value"]
  password <- parameters[which(parameters$parameter == "password"), "value"]
  dbname <- parameters[which(parameters$parameter == "dbname"), "value"]
  sslmode <- parameters[which(parameters$parameter == "sslmode"), "value"]
  sslfactory <- parameters[which(parameters$parameter == "sslfactory"), "value"]
  sslrootcert <- parameters[which(parameters$parameter == "sslrootcert"), "value"]
  sslcert <- parameters[which(parameters$parameter == "sslcert"), "value"]
  sslkey <- parameters[which(parameters$parameter == "sslkey"), "value"]

  # Read connection based on parameters
  connection <- DBI::dbConnect(
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
