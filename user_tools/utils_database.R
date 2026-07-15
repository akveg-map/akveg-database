# ===========================================================================
# CONNECT TO DATABASE ----
# ===========================================================================
#'
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

# ===========================================================================
# QUERY DATABASE ----
# ===========================================================================
#' Get latest database version
#'
#' Retrieves the highest version identifier from the `database_version` table
#' and formats it into a standardized semantic version string.
#'
#' @param db_conn A valid `DBIConnection` object.
#' @param separate_by A character string used to separate major, minor, and patch version numbers. Defaults to an underscore (`"_"`).
#' @param prefix A logical value. If TRUE, the major version number is prefixed with the letter "v".
#'
#' @return A character string of the latest database version, formatted as "v2_11_0".

get_latest_version <- function(db_conn, separate_by = "_", prefix = TRUE) {
  # Ensure connection is valid
  if (!inherits(db_conn, "DBIConnection") || !DBI::dbIsValid(db_conn)) {
    stop("Database connection is invalid.")
  }

  # Define SQL query
  version_query <- "
  SELECT major_version, minor_version, patch_version
  FROM database_version
  WHERE version_id = (SELECT MAX (version_id) FROM database_version
  );
  "
  # Execute query
  latest_version <- DBI::dbGetQuery(db_conn, version_query)

  # Parse version number into individual strings
  major_v <- latest_version$major_version[1]
  minor_v <- latest_version$minor_version[1]
  patch_v <- latest_version$patch_version[1]

  # Define prefix
  v_prefix <- if (prefix) "v" else ""

  # Concatenate full version string
  major_v_prefix <- stringr::str_c("v", major_v)
  full_version_string <- stringr::str_c(major_v_prefix,
    minor_v,
    patch_v,
    sep = separate_by
  )

  return(full_version_string)
}
