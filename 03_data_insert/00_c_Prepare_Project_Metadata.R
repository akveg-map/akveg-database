# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Prepare project metadata tables
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-22
# Usage: Script should be executed in R 4.5.1+.
# Description: "Prepare project metadatat tables" parses citations and project source tables into separate citations, project_source, and project_citations tables for ingestion into the AKVEG database. The script joins the tables with lookup tables to extract foreign key values, select columns to mirror database schema, and performs simple quality checks to ensure data integrity. Because the script reads in project codes from individual project tables, it does not require the project table to exist in AKVEG.
# ---------------------------------------------------------------------------

# Import required libraries ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(purrr)
library(readr)
library(readxl)
library(rjson)
library(RPostgres)
library(stringr)
library(tibble)
library(yaml)

# Define folder structure ----
drive <- "C:"
root_folder <- "ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database"
repository_folder <- path(drive, "ACCS_Work/Repositories/akveg-database")
plot_folders <- path(drive, root_folder, "Data", "Data_Plots", "")

# Define input files ----
source_input <- path(drive, root_folder, "Data", "Tables_Metadata", "project_source.xlsx")
citations_input <- path(drive, root_folder, "Data", "Tables_Metadata", "project_citations.xlsx")
queries_input <- path(repository_folder, "03_data_insert", "queries_lookup.yaml")
project_list_input <- path(repository_folder, "03_data_insert", "List_Included_Projects.json")
authentication <- path(
  drive, root_folder, "Credentials", "akveg_private_build",
  "authentication_akveg_private_build.csv"
)

# Source functions ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
source(path(repository_folder, "03_data_insert", "helper_functions_combine.R"))

# Connect to AKVEG database ----
database_connection <- connect_database_postgresql(authentication)

# Read in project metadata files ----
source_original <- read_excel(source_input)
citations_original <- read_excel(citations_input)

# Read in queries ----
queries_lookup <- read_yaml(queries_input)
lookup_data <- map(queries_lookup$queries, \(q) dbGetQuery(database_connection, q))
source_template <- dbListFields(database_connection, "project_source")

# Read in project list ----
target_paths <- fromJSON(file = project_list_input)$projects
project_folders <- path(drive, root_folder, "Data", "Data_Plots", target_paths)

# Create project code list ----
## Iterate over individual project folders and extract project codes
## Allows project metadata to be prepared even if no aggregate project table exists
project_codes <- find_files_warning(project_folders, "01_project.*csv", show_warning = FALSE) |>
  map(\(f) read_csv(f, show_col_types = FALSE, col_select = "project_code")) |>
  list_rbind() |>
  pull(project_code)

# Create citations table ----
citations <- citations_original |>
  select(citation_short, citation_long, citation_url) |>
  distinct() |> # Remove duplicates
  arrange(citation_short) |>
  rowid_to_column(var = "citation_id")

# Create project citations table ----
project_citations <- citations_original |>
  left_join(citations, by = "citation_short") |>
  select(project_code, citation_id)

# Create project source table ----
project_source <- source_original |>
  mutate(source_type = str_to_lower(source_type)) |>
  left_join(lookup_data$source_type, by = "source_type") |>
  left_join(lookup_data$personnel, by = c("source_contact" = "personnel")) |>
  left_join(lookup_data$source_collection, by = "source_collection") |>
  rename(source_contact_id = personnel_id) |>
  rowid_to_column(var = "project_source_id") |>
  select(all_of(source_template))

# Quality checks ----

## Ensure all codes in source/citations table are in the original project tables, and vice-versa
setdiff(project_citations$project_code, project_codes) # project citations -> project codes
setdiff(project_codes, project_citations$project_code) # project codes -> project citations
setdiff(project_source$project_code, project_codes) # project source -> project codes
setdiff(project_codes, project_source$project_code) # project codes -> project source

# Examine summary statistics for data types and NAs
print(summary(citations)) # No NAs allowed
print(summary(project_source)) # published should be logical, NAs allowed only for source_contact_id and source_collection_id
print(summary(project_citations)) # No NAs allowed
table(project_source$source_type_id, project_source$source_contact_id)

## Ensure that projects with source type 'AKVEG Origin' or 'Direct Transfer' are associated with a personnel id
print(project_source |> filter(source_type_id %in% c(1, 2) & is.na(source_contact_id)) |> nrow())

## Ensure published projects have a URL
print(project_source |> filter(published & is.na(download_url)))

# Export tables to CSV ----
results_list <- list(citations, project_source, project_citations)
output_paths <- c("citations.csv", "project_source.csv", "project_citations.csv")

pwalk(
  list(results_list, output_paths),
  \(data, name) {
    write_csv(data, path(drive, root_folder, "Data", "Data_Plots", "processed", name))
  }
)

# Close database connection
dbDisconnect(database_connection)

# Clear workspace
rm(list = ls())
