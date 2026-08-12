# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Upload data package to Arctic Data Center
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-08-11
# Usage: Script should be executed in R 4.6.1+.
# Description: "Upload data package to Arctic Data Center" prepares and upload a data package to the Arctic Data Center.
# ---------------------------------------------------------------------------

# Verify that OpenSSL is active (should be outside parentheses)
# writeLines('CURL_SSL_BACKEND="openssl"', ".Renviron")
curl::curl_version()$ssl_version

library(dataone)
library(datapack)
library(EML)
library(uuid)
library(fs)
library(here)

# Set token
# options(dataone_token = "...")

# Source utility functions ----
source(here("user_tools", "utils_init.R"))
source(path("user_tools", "utils_database.R"))
source(path("manuscript", "utils.R"))

# Define directories & files ----
local_paths <- load_system_paths("paths.yaml")

# Dynamically set folder path
## Connect to the AKVEG Database to obtain latest database version
database_connection <- connect_database_postgresql(local_paths$credentials)
full_version_string <- get_latest_version(db_conn = database_connection)
deposit_dir <- path(local_paths$archive, full_version_string)

print(deposit_dir) # Ensure file path matches expectations

# Create data package that includes metadata and source objects
akveg_data_package <- create_data_package(deposit_dir)
print(length(akveg_data_package@objects))

# Connect to ADC production node
d1c <- D1Client("PROD", "urn:node:ARCTIC")

# Grant access privileges to ADC admins
access_rules <- data.frame(
  subject = "CN=arctic-data-admins,
                           DC=dataone,
                           DC=org",
  permission = "changePermission"
)

# Upload data package
resourceMapId <- uploadDataPackage(
  x           = d1c,
  dp          = akveg_data_package,
  public      = FALSE, # Keep submission private for review
  accessRules = access_rules,
  quiet       = FALSE
)
