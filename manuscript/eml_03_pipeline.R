# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create EML XML file for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-08-02
# Usage: Script should be executed in R 4.6.1+.
# Description: "Create EML XML file for data archive" parses AKVEG's database schema and dictionary into an EML XML metadata file.
# ---------------------------------------------------------------------------

# Load required packages ----
library(dplyr, warn.conflicts = FALSE)
library(here)
library(EML)
library(fs)
library(lubridate)
library(purrr)
library(RPostgres)
library(readr)
library(stringr)
library(tibble)
library(tidyr)
library(yaml)

# Source utility functions ----
source(here("user_tools", "utils_init.R"))
source(here("user_tools", "utils_database.R"))
source(here("manuscript", "utils.R"))

# Define directories ----
local_paths <- load_system_paths("paths.yaml")

# Connect to the AKVEG Database ----
database_connection <- connect_database_postgresql(local_paths$credentials)
dbExecute(database_connection, "SET search_path TO public;") ## Define default schema

# Define folder path using latest database version ----
full_version_string <- get_latest_version(db_conn = database_connection)
compiled_folder <- path(local_paths$archive, full_version_string)

# Define metadata files ----
abstract_path <- path(here("manuscript", "deposit_metadata", "abstract.md"))
methods_path <- path(here("manuscript", "deposit_metadata", "methods.md"))
keywords_path <- path(here("manuscript", "deposit_metadata", "keywords.csv"))
akveg_creators <- read_yaml(here("manuscript", "deposit_metadata", "creators.yaml"))
taxonomic_creators <- read_yaml(here("manuscript", "deposit_metadata", "taxonomic_creators.yaml"))

# Define documentation files ----
custom_overrides_path <- path(here("manuscript", "config", "eml_overrides.csv"))
schema_compiled_path <- path(compiled_folder, "data_package", "database_schema.csv")
dictionary_compiled_path <- path(compiled_folder, "data_package", "database_dictionary.csv")
dictionary_full_path <- path(compiled_folder, "full_documentation", "database_dictionary.csv")
standards_path <- path(compiled_folder, "VWG_2022_Minimum_Standards_v1_1.pdf")

# Define output ----
eml_xml_output <- path(compiled_folder, "akveg_metadata.xml")

# Read in files ----
custom_overrides <- read_csv(custom_overrides_path, show_col_types = FALSE)
schema_compiled <- read_csv(schema_compiled_path, show_col_types = FALSE)
dictionary_compiled <- read_csv(dictionary_compiled_path, show_col_types = FALSE)
dictionary_full <- read_csv(dictionary_full_path, show_col_types = FALSE)

# Create EML attributes list ----
# Assume all character fields are enumeratedDomain unless custom override exists
# Populate measurementScale based on domain
# Nominal and Ordinal: require definition
# Date: Require FormatString
# Numeric Fields: Populate unit and numberType
# Add primary keys only for tables with fields that serve as foreign keys for other tables

# Define columns of final attribute table
attribute_full_columns <- c(
  "schema_table", "attributeName", "attributeDefinition", "domain", "measurementScale",
  "unit", "numberType", "definition", "formatString", "schema_table", "primary_key_constraint",
  "data_type"
)

# Define fields requiring custom classification
text_tables <- c("database_dictionary", "database_schema", "taxonomy")

attribute_table <- schema_compiled |>
  rename(
    attributeName = field,
    attributeDefinition = field_description
  ) |>
  left_join(custom_overrides, by = join_by("attributeName")) |>
  mutate(
    attributeDefinition = coalesce(customDefinition, attributeDefinition),
    domain = coalesce(
      customDomain,
      case_when(
        data_type == "varchar" & schema_table %in% text_tables ~ "textDomain",
        grepl(pattern = "name|observer", attributeName) ~ "textDomain",
        data_type == "date" ~ "dateTimeDomain",
        data_type %in% c("text", "serial") ~ "textDomain",
        data_type %in% c("smallint", "decimal") ~ "numericDomain",
        data_type %in% c("boolean", "varchar") ~ "enumeratedDomain",
        .default = NA
      )
    ),
    measurementScale = coalesce(
      customScale,
      case_when(
        domain == "dateTimeDomain" ~ "dateTime",
        domain == "enumeratedDomain" ~ "nominal",
        domain == "textDomain" ~ "nominal",
        domain == "numericDomain" ~ "ratio",
        .default = NA
      )
    ),
    definition = case_when(
      measurementScale %in% c("nominal", "ordinal") ~ attributeDefinition,
      .default = NA
    ),
    formatString = coalesce(
      customFormat,
      case_when(
        data_type == "date" ~ "YYYY-mm-dd",
        .default = NA
      )
    ),
    unit = coalesce(
      customUnit,
      case_when(
        grepl(pattern = "_percent$|_value$", attributeName) ~ "dimensionless",
        grepl(pattern = "_cm$", attributeName) & domain == "numericDomain" ~ "centimeter",
        .default = NA
      )
    ),
    numberType = coalesce(
      customNumType,
      case_when(
        data_type == "decimal" ~ "real",
        .default = NA
      )
    ),
    primary_key_constraint = case_when(
      schema_table == "database_schema" & attributeName %in% c("schema_table", "field") ~ TRUE,
      .default = is_primary_key
    )
  ) |>
  select(all_of(attribute_full_columns))

## Validate attribute list

## Ensure required fields have no nulls
print(attribute_table %>%
  select(attributeName, attributeDefinition, domain, measurementScale) |>
  summarise(across(everything(), ~ sum(is.na(.x)))))

## Verify consistency between domain and measurement scale
## dateTimeDomain -> dateTime only
## enumeratedDomain and textDomain -> nominal or ordinal
## numericDomain -> interval or ratio
table(
  attribute_table$domain,
  attribute_table$measurementScale
)

## Verify consistency between domain and domain-specific fields
## Ensure unit_sum and numberType_sum are equal
## dateTimeDomain -> format_sum only
## enumerated and textDomain -> def_sum only
attribute_table |>
  mutate(
    def_exists = case_when(is.na(definition) ~ 0,
      .default = 1
    ),
    unit_exists = case_when(is.na(unit) ~ 0,
      .default = 1
    ),
    numberType_exists = case_when(is.na(numberType) ~ 0,
      .default = 1
    ),
    format_exists = case_when(is.na(formatString) ~ 0,
      .default = 1
    )
  ) |>
  group_by(domain) |>
  summarise(
    def_sum = sum(def_exists),
    format_sum = sum(format_exists),
    unit_sum = sum(unit_exists),
    numberType_sum = sum(numberType_exists)
  )

# Create EML factors list ----

# Rename columns to match EML schema
factors_table <- dictionary_compiled |>
  rename(
    attributeName = field,
    code = data_attribute
  )

# Verify if any fields in the compiled table don't have a match in the dictionary
print(attribute_table |>
  filter(domain == "enumeratedDomain") |>
  anti_join(factors_table,
    by = join_by(attributeName)
  ))

# Create EML missing values list ----
missing_values <- schema_compiled |>
  # Add missing value codes
  mutate(
    missing_value_code = case_when(field %in% c("env_observer", "soils_observer") ~ "none",
      .default = missing_value_code
    ),
    missing_value_description = case_when(field %in% c("env_observer", "soils_observer") ~ "Observer name not recorded because corresponding data were not collected.",
      .default = missing_value_description
    )
  ) |>
  filter(!is.na(missing_value_code)) |>
  select(schema_table, field, missing_value_code, missing_value_description) |>
  rename(
    attributeName = field,
    code = missing_value_code,
    definition = missing_value_description
  )

# Create EML data tables ----
all_data_tables <- list() # Initialize empty list for storing results

attribute_final_columns <- c(
  "attributeName", "attributeDefinition", "domain",
  "measurementScale", "unit", "numberType", "definition",
  "formatString"
)
# Define primary key constraints
constraints_mapping <- list(
  name_adjudicated = list(
    primary_key = "taxon_name",
    entity = "entity_taxonomy"
  ),
  name_accepted = list(
    primary_key = "taxon_accepted",
    entity = "entity_taxonomy"
  ),
  field = list(
    primary_key = "field",
    entity = "entity_database_schema"
  )
)

# Iterate over each compiled table
for (i in 1:length(unique(attribute_table$schema_table))) {
  current_table <- unique(attribute_table$schema_table)[i]
  current_filename <- str_c(current_table, ".csv")

  # Get attribute table
  current_schema <- attribute_table |>
    filter(schema_table == current_table)

  # Restrict to valid EML columns
  current_attributes <- current_schema |>
    select(all_of(attribute_final_columns))

  # Get factors table
  current_fields <- current_attributes |>
    select(attributeName) |>
    pull() # Extract field names
  current_factors <- factors_table |>
    filter(attributeName %in% current_fields)

  # Get missing values table
  current_missing <- missing_values |>
    filter(schema_table == current_table) |>
    select(-schema_table)

  # Create attributeList
  if (nrow(current_missing) == 0) {
    attributeList <- set_attributes(
      attributes = current_attributes,
      factors = current_factors
    )
  } else {
    attributeList <- set_attributes(
      attributes = current_attributes,
      factors = current_factors,
      missingValues = current_missing # Add missing values if they exist
    )
  }

  # Define constraints
  current_constraints <- list()

  ## Add constraints for foreign key/primary key relationships

  existing_constraints <- intersect(names(constraints_mapping), current_fields)

  for (foreign_key in existing_constraints) {
    specific_mapping <- constraints_mapping[[foreign_key]]

    constraint_name <- str_c(current_table, foreign_key, "link", sep = "_")

    # Append constraints to list
    current_constraints[[length(current_constraints) + 1]] <- create_key_constraint(
      constraint_name = constraint_name,
      foreign_key_name = foreign_key,
      entity_name = specific_mapping$entity
    )
  }

  ## Add primary key constraints
  primary_key_fields <- current_schema |>
    filter(primary_key_constraint == TRUE) |>
    arrange(match(attributeName, current_fields)) |> # Ensure primary keys are listed in the order that they appear in the physical file
    pull(attributeName)

  if (length(primary_key_fields) > 0) {
    pk_constraint_name <- str_c(current_table, "primary_key", sep = "_")

    current_constraints[[length(current_constraints) + 1]] <- eml$constraint(
      primaryKey = list(
        constraintName = pk_constraint_name,
        key = list(
          attributeReference = primary_key_fields
        )
      )
    )
  }

  # Define file name and format
  current_physical <- set_physical(current_filename,
    encoding = "UTF-8"
  )

  # Define entity description
  filtered_dictionary <- dictionary_full |>
    filter(field == "schema_table" & data_attribute == current_table)

  if (current_table == "taxonomy") {
    current_entity_description <- "Comprehensive taxonomic checklist table of accepted names, synonyms, authorities, and unknown/functional group codes for Alaska and adjacent Canadian. Covers vascular plants, bryophytes, and lichens ranging from genus to infraspecies."
  } else if (nrow(filtered_dictionary) == 0) {
    warning(str_c("Table ", current_table, " was not found in the data dictionary"))
    clean_table_name <- str_replace_all(current_table, "_", " ")
    current_entity_description <- str_c("Table containing observations for ",
      clean_table_name, ".",
      sep = ""
    )
  } else {
    current_entity_description <- filtered_dictionary |>
      pull(definition) |>
      as.character()
  }

  # Read in CSV to obtain row count
  row_count <- as.character(nrow(read_csv(path(compiled_folder, "data_package", current_filename),
    show_col_types = FALSE
  )))

  # Assemble EML data table
  current_data_table <- eml$dataTable(
    entityName = current_filename,
    entityDescription = current_entity_description,
    physical = current_physical,
    attributeList = attributeList,
    numberOfRecords = row_count,
    id = str_c("entity", current_table, sep = "_"),
    constraint = current_constraints
  )

  # Append to all tables list
  all_data_tables[[i]] <- current_data_table
}

# Define taxonomic coverage ----
taxonomic_classification_list <- list(
  # Vascular plants & bryophytes
  list(
    taxonRankName = "Kingdom",
    taxonRankValue = "Plantae",
    taxonomicClassification = list(
      list(taxonRankName = "Phylum", taxonRankValue = "Tracheophyta"),
      list(taxonRankName = "Phylum", taxonRankValue = "Bryophyta")
    )
  ),
  # Lichens
  list(
    taxonRankName = "Kingdom",
    taxonRankValue = "Fungi",
    taxonomicClassification = list(
      list(taxonRankName = "Phylum", taxonRankValue = "Ascomycota"),
      list(taxonRankName = "Phylum", taxonRankValue = "Basidiomycota") # e.g., Lichenomphalia
    )
  )
)

# Assemble taxonomic coverage
taxonomic_coverage <- eml$taxonomicCoverage(
  generalTaxonomicCoverage = "Taxonomic coverage includes vascular plants, bryophytes, and lichens, but varies by project and individual site visit. Among the 44,324 unique site visits in the AKVEG Database, 65% recorded exhaustive, species-level data of vascular plants. In contrast, bryophyte and lichen records are generally limited to dominant species (55% of site visits) or absent (29% of visits). Taxonomic coverage of individual site visits is documented in this data package's `site_visit` table with separate fields for vascular plants, bryophytes, and lichens.",
  taxonomicSystem = list(
    classificationSystem = list(
      classificationSystemCitation = list(
        title = "Checklist of Vascular Plants, Bryophytes, Lichens, and Lichenicolous Fungi of Alaska",
        creator = taxonomic_creators,
        pubDate = "2024",
        distribution = list(
          online = list(
            onlineDescription = "Online interface for browsing the taxonomic checklist; the version in this data package contains minor updates and was the version used to standardize taxonomy across datasets.",
            url = list(
              "https://akveg.org/taxonomic-standard/",
              `function` = "information"
            )
          )
        ),
        generic = list(
          publisher = list(
            organizationName = "Alaska Vegetation (AKVEG) Database"
          ),
          referenceType = "dataset"
        )
      )
    ),
    identifierName = list(organizationName = "AKVEG Database Contributing Botanists and Vegetation Ecologists"),
    taxonomicProcedures = "Taxonomic names recorded in the field were standardized programmatically by matching exact names against the Checklist of Vascular Plants, Bryophytes, Lichens, and Lichenicolous Fungi of Alaska, followed by manual review of all unresolved records."
  ),
  taxonomicClassification = taxonomic_classification_list
)

# Define geographic coverage ----
## Create two separate bounding boxes to handle the international date line

# Bounding Box 1: Western Hemisphere
bbox_west <- eml$geographicCoverage(
  geographicDescription = "Western Hemisphere component of the AKVEG Database from the 180th Meridian eastward to the easternmost plot in the Northwest Territories, Canada.",
  boundingCoordinates = list(
    westBoundingCoordinate = "-180.00000",
    eastBoundingCoordinate = "-123.00000",
    northBoundingCoordinate = "71.27648",
    southBoundingCoordinate = "52.70761"
  )
)

# Bounding Box 2: Eastern Hemisphere (Aleutian Islands)
bbox_east <- eml$geographicCoverage(
  geographicDescription = "Eastern Hemisphere component of the AKVEG Database from the westernmost plot in the western Aleutian Islands eastward to the 180th Meridian.",
  boundingCoordinates = list(
    westBoundingCoordinate = "174.15216",
    eastBoundingCoordinate = "180.00000",
    northBoundingCoordinate = "71.27648",
    southBoundingCoordinate = "52.70761"
  )
)

# Combine both bounding boxes to create overall geographic coverage
geographic_coverage <- list(bbox_west, bbox_east)

# Define temporal coverage ----

# Get min/max dates from compiled table
site_visit_dates <- read_csv(path(compiled_folder, "data_package", "site_visit.csv"),
  col_select = "observe_date",
  col_types = "D"
) |> # Set to Date
  summarize(
    min_date = min(observe_date),
    max_date = max(observe_date)
  ) |>
  mutate(across(where(is.Date), as.character))

temporal_coverage <- eml$temporalCoverage(
  rangeOfDates = eml$rangeOfDates(
    beginDate = eml$beginDate(calendarDate = site_visit_dates$min_date),
    endDate = eml$endDate(calendarDate = site_visit_dates$max_date)
  )
)

# Set global coverage object
global_coverage <- eml$coverage(
  geographicCoverage = geographic_coverage,
  temporalCoverage = temporal_coverage,
  taxonomicCoverage = taxonomic_coverage
)

# Create EML keywords set ----
keyword_sets <- create_keyword_set(keywords_path)
print(keyword_sets) ## Verify results

# Parse EML abstract ----
abstract_eml <- set_TextType(abstract_path)

# Parse EML methods ----

## Define sampling citation
methods_citation <- list(
  title = "Minimum Standards for Field Observation of Vegetation and Related Properties",
  creator = list(
    organizationName = "Vegetation Working Group"
  ),
  pubDate = "2022",
  distribution = list(
    online = list(
      url = "https://doi.org/10.xxxx/placeholder-doi" ## Need to update
    )
  ),
  generic = list(
    publisher = list(
      organizationName = "Alaska Geospatial Council"
    ),
    edition = "Version 1.1 (August 2022)"
  )
)

## Wrap inside "sampling" element. studyExtent and samplingDescription is required if a citation is provided
sampling_element <- list(
  studyExtent = list(
    description = "The AKVEG Database includes field datasets from Alaska and adjacent Canada."
  ),
  samplingDescription = "Datasets integrated in the AKVEG Database reflect a variety of field sampling designs and protocols. Methodological metadata is provided in the SITE and SITE_VISIT tables. References to specific field protocols can be found in the PROJECT_CITATIONS table.",
  citation = list(methods_citation)
)

## Define software
software_postgres <- list(
  title = "PostgreSQL",
  creator = list(organizationName = "PostgreSQL Global Development Group"),
  pubDate = "2026",
  implementation = list(
    distribution = list(
      online = list(
        url = "https://www.postgresql.org/"
      )
    )
  ),
  version = "17.9"
)

software_r <- list(
  title = "R",
  creator = list(organizationName = "R Core Team"),
  pubDate = "2026",
  implementation = list(
    distribution = list(
      online = list(
        url = "https://www.r-project.org/"
      )
    )
  ),
  version = "4.6.1"
)

software_python <- list(
  title = "Python",
  creator = list(organizationName = "Python Software Foundation"),
  pubDate = "2024",
  implementation = list(
    distribution = list(
      online = list(
        url = "https://www.python.org/"
      )
    )
  ),
  version = "3.13.12"
)

# Group into a single list
software_list <- list(
  software_postgres,
  software_r,
  software_python
)

## Create methods list
methods_eml <- set_methods(
  methods_file = methods_path,
  software = software_list
)
methods_eml$sampling <- sampling_element ## Add sampling element

# Define primary contact ----
primary_contact <- detect(
  akveg_creators,
  \(person) person$individualName$surName == "Droghini"
)

# Define metadata for Minimum Standards PDF ----
standards_entity <- list(
  entityName = path_file(standards_path),
  entityDescription = "Minimum Standards for Field Observation of Vegetation and Related Properties Version 1.1 (August 2022). Establishes minimum field data collection standards for vegetation mapping and classification in Alaska, and serves as the foundational schema for the AKVEG Database.",
  entityType = "application/pdf"
)
# Compile final EML file ----
akveg_metadata <- eml$dataset(
  title = "Alaska Vegetation (AKVEG) Database (Version 2.11.0): Harmonized plot-level vegetation observations for Alaska and adjacent Canada, 1975–2025",
  pubDate = "2026",
  creator = akveg_creators,
  contact = primary_contact,
  abstract = abstract_eml,
  keywordSet = keyword_sets,
  coverage = global_coverage,
  methods = methods_eml,
  otherEntity = list(standards_entity),

  # Define license
  intellectualRights = "This data package is released to the public domain under the Creative Commons CC0 1.0 Universal public domain dedication (https://creativecommons.org/publicdomain/zero/1.0/). It may be freely copied, modified, distributed, or used for any purpose without explicit permission.",

  # Define maintenance block
  maintenance = list(
    description = "The AKVEG Database is actively maintained. Users who wish to access the live database can consult the project website at https://akveg.org.",
    maintenanceUpdateFrequency = "asNeeded"
  ),

  # Add project website URL
  distribution = list(
    online = list(
      url = list("https://akveg.org", `function` = "information")
    )
  ),
  dataTable = all_data_tables
)

# Compile EML document structure
eml_doc <- eml$eml(
  packageId = "urn:uuid:9b07dc26-594c-4bbe-aef5-3f766d5e8edd",
  system = "knb",
  dataset = akveg_metadata
)

# Write EML XML to disk
write_eml(eml_doc, eml_xml_output)

# Fix foreignKey ordering
fix_foreign_keys(eml_xml_output) ## Overwrites existing file

# Validate EML file
validation_result <- eml_validate(eml_xml_output)

# Look at errors
print(attr(validation_result, "errors")) # If TRUE, no validation errors

# Clean up workspace ----
dbDisconnect(database_connection)
rm(list = ls())
