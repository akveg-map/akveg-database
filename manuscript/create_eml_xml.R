# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Create EML XML file for data archive
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-07-13
# Usage: Script should be executed in R 4.6.1+.
# Description: "Create EML XML file for data archive" parses AKVEG's database schema and dictionary into an EML XML metadata file.
# ---------------------------------------------------------------------------

# Load required packages ----
library(dplyr, warn.conflicts = FALSE)
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

# Define files and directories ----
drive <- "C:"
root_folder <- "ACCS_Work"
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")

# Define SQL authentication file
authentication <- path(
  drive, root_folder, "OneDrive - University of Alaska",
  "ACCS_Teams", "Vegetation", "AKVEG_Database", "Credentials",
  "akveg_private_build",
  "authentication_akveg_private_build.csv"
)

# Define SQL queries
schema_file <- path(repository_folder, "user_tools", "queries", "00_database_schema.sql")
dictionary_file <- path(repository_folder, "user_tools", "queries", "00_database_dictionary.sql")

# Define config files
field_map_path <- path(repository_folder, "manuscript", "config", "map_compiled_fields.yaml")
custom_overrides_path <- path(repository_folder, "manuscript", "config", "eml_overrides.csv")
boolean_dictionary_path <- path(repository_folder, "manuscript", "config", "dictionary_boolean.csv")

# Define data package metadata files 
abstract_path <- path(repository_folder, "manuscript", "deposit_metadata", "abstract.md")
methods_path <- path(repository_folder, "manuscript", "deposit_metadata", "methods.md")
keywords_path <- path(repository_folder, "manuscript", "deposit_metadata", "keywords.csv")

# Connect to the AKVEG Database ----
source(path(repository_folder, "pull_functions", "connect_database_postgresql.R"))
database_connection <- connect_database_postgresql(authentication)
dbExecute(database_connection, "SET search_path TO public;") ## Define default schema

# Read in files ----

## Read functions and config files
source(path(repository_folder, "manuscript", "utils.R"))
field_map <- read_yaml(field_map_path)
custom_overrides <- read_csv(custom_overrides_path,
                             show_col_types = FALSE
)
boolean_dictionary <- read_csv(boolean_dictionary_path,
                               col_types = cols(.default = "c"),  # Force boolean column to be read as character
                             show_col_types = FALSE
)

## Read metadata files
keywords <- read_csv(keywords_path,
                     show_col_types = FALSE)

## Read queries
schema_query <- read_file(schema_file)
dictionary_query <- read_file(dictionary_file)

schema_full <- as_tibble(dbGetQuery(database_connection, schema_query))
dictionary_full <- as_tibble(dbGetQuery(database_connection, dictionary_query))

# Dynamically set folder path ----
## Use latest database version as it appears in the `database_version` table of the database

version_query <- "
SELECT major_version, minor_version, patch_version
FROM database_version
WHERE version_id = (
    SELECT
      MAX (version_id)
    FROM
      database_version
);
"
latest_version <- as_tibble(dbGetQuery(database_connection, version_query))

## Parse version number into string
major_version_string <- str_c("v", latest_version$major_version, sep = "")
full_version_string <- str_c(major_version_string,
  latest_version$minor_version,
  latest_version$patch_version,
  sep = "_"
)

## Define folder path using version string
compiled_folder <- path(
  drive, root_folder, "Projects", "AKVEG_Database",
  "Data_Deposit", full_version_string, "data_package"
)

## Remove intermediate products
rm(latest_version, major_version_string)

# Resolve fields with no match in schema ----
# Some fields in the compiled tables do not exist in the database schema table because they were renamed or brought in from lookup tables during the compilation step

# Get file paths and file stems of compiled tables
table_paths <- dir_ls(compiled_folder, 
                      glob="*.csv")
table_stems <- path_file(table_paths) |>
  path_ext_remove()

# Loop across files and extract column names from each table
compiled_fields_list <- list() # Initialize empty list

for (i in 1:length(table_paths)) {
  path <- table_paths[i]
  stem <- table_stems[i]

  # Get column names
  cols <- colnames(read_csv(path, n_max = 0, show_col_types = FALSE))

  compiled_fields_list[[i]] <- tibble(
    compiled_table = stem,
    field = cols
  )
  
  # Append table name to list
  names(compiled_fields_list)[[i]] <- stem
}

# Add schema and dictionary fields if not already in data package
documentation_tables <- list(
  database_schema = colnames(schema_full),
  database_dictionary = colnames(dictionary_full)
)


for (table_name in names(documentation_tables)) {
  
  if (!table_name %in% names(compiled_fields_list)) {
  cols <- documentation_tables[[table_name]]
  new_index <- length(compiled_fields_list) + 1
  compiled_fields_list[[new_index]] <- tibble(
    compiled_table = table_name,
    field = cols
  )
  
  # Append table name to list
  names(compiled_fields_list)[[new_index]] <- table_name
  }
}

# Flatten into single data frame
compiled_fields_df <- bind_rows(compiled_fields_list)

# Find unmatched fields
## Fields in compiled tables that do not exist in the database schema
unmatched_fields <- compiled_fields_df |>
  anti_join(schema_full, by = join_by(
    compiled_table == schema_table,
    field == field
  ))

# Map unmatched fields to existing schema entries
healed_fields <- map_to_schema_fields(
  unmatched_fields,
  schema_full,
  field_map
)

## Ensure that all fields were matched
print(anti_join(
  unmatched_fields,
  healed_fields,
  join_by(
    compiled_table == schema_table,
    field == field
  )
))

# Restrict database schema to only fields in compiled tables
schema_compiled <- schema_full |>
  semi_join(compiled_fields_df,
    by = join_by(
      schema_table == compiled_table,
      field == field
    )
  ) |> # Restrict full schema to fields in compiled table with a direct match in the schema
  bind_rows(healed_fields) # Add 'unmatched' fields

# Create EML attributes list ----

# Define fields requiring custom classification
text_domain_fields <- c(
  "originator", "funder", "manager", "h_datum_epsg",
  "plot_dimensions_m", "horizon_order", "citation_short",
  "standards_section"
)
text_tables <- c("database_dictionary", "database_schema", "taxonomy")
year_fields <- c("year_start", "year_end")

attribute_table <- schema_compiled |>
  rename(
    attributeName = field,
    attributeDefinition = field_description
  ) |>
  left_join(custom_overrides, by = join_by("attributeName")) |>
  # If specified, overwrite schema definitions with custom ones
  mutate(attributeDefinition = coalesce(customDefinition, attributeDefinition)) |>
  # Populate EML domain based on data type and attribute name
  mutate(domain = case_when(attributeName %in% year_fields ~ "dateTimeDomain",
    attributeName %in% text_domain_fields ~ "textDomain",
    data_type == "varchar" & schema_table %in% text_tables ~ "textDomain",
    grepl(pattern = "_id|_code|_description|name|observer|recorder", attributeName) ~ "textDomain",
    grepl(pattern = "_version", attributeName) ~ "numericDomain",
    # Re-classify unambiguous data types
    data_type == "date" ~ "dateTimeDomain",
    data_type %in% c("text", "serial") ~ "textDomain",
    data_type %in% c("smallint", "decimal") ~ "numericDomain",
    data_type %in% c("boolean", "varchar") ~ "enumeratedDomain", # Assume all character fields are enumeratedDomain unless custom override exists
    .default = NA
  )) |>
  # Populate measurementScale based on domain
  mutate(measurementScale = case_when(attributeName == "horizon_order" ~ "ordinal",
    grepl("_dd$", attributeName) ~ "interval", # For coordinate fields
    domain == "dateTimeDomain" ~ "dateTime",
    domain == "enumeratedDomain" ~ "nominal",
    domain == "textDomain" ~ "nominal",
    domain == "numericDomain" ~ "ratio",
    .default = NA
  )) |>
  # Nominal Fields: Populate definition
  mutate(definition = case_when(measurementScale == "nominal" ~ attributeDefinition,
    .default = NA
  )) |>
  # dateTime Fields: Populate formatString
  mutate(formatString = case_when(data_type == "date" ~ "YYYY-mm-dd",
    attributeName %in% year_fields ~ "YYYY",
    .default = NA
  )) |>
  # Numeric Fields: Populate unit and numberType
  mutate(
    unit = coalesce(
      customUnit,
      case_when(
        grepl(pattern = "_percent$|_chroma$|_value$|^number_", attributeName) ~ "dimensionless",
        grepl(pattern = "_cm$", attributeName) &
          domain == "numericDomain" ~ "centimeter",
        .default = NA
      )
    ),
    numberType = case_when(data_type == "decimal" ~ "real",
      grepl(pattern = "_chroma", attributeName) ~ "real",
      attributeName == "number_stems" ~ "natural",
      attributeName == "disturbance_time_y" ~ "integer",
      .default = NA
    )
  ) |>
  # Add primary keys only for tables with fields that serve as foreign keys for other tables
  mutate(
    primary_key_constraint = 
      case_when(schema_table == 'database_schema' & attributeName %in% c('schema_table',
                                                                         'field') ~ TRUE,
        .default = is_primary_key
      )
    ) |> 
  # Select desired columns
  select(
    schema_table, attributeName, attributeDefinition, domain, measurementScale,
    unit, numberType, definition, formatString, schema_table, primary_key_constraint, data_type
  )

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

# Define a lookup list for fields that do not have a match in the database dictionary
dictionary_mapping <- list(
  "ground_element" = c("abiotic_element", "ground_element"),
  "scope" = c("scope_vascular", "scope_bryophyte", "scope_lichen"),
  "soil_hue" = c("matrix_hue_code", "nonmatrix_hue_code"),
  "soil_horizon_suffix" = c(
    "horizon_suffix_1_code", "horizon_suffix_2_code",
    "horizon_suffix_3_code", "horizon_suffix_4_code"
  ),
  "soil_horizon_type" = c("horizon_primary_code", "horizon_secondary_code"),
  "soil_texture" = c("dominant_texture_40_cm", "horizon_texture")
)

# Resolve missing dictionary entries using mapping
dictionary_compiled <- dictionary_full |>
  # Create duplicate_count field based on number of values associated with each key
  mutate(
    duplicate_count = case_when(
      field %in% names(dictionary_mapping) ~ lengths(dictionary_mapping)[field],
      .default = 1
    )
  ) |>
  # Duplicate fields
  uncount(duplicate_count, .id = "duplicate_id") |>
  # Rename fields using names defined in dictionary map
  mutate(
    field = case_when(
      field == "ground_element" ~ dictionary_mapping[["ground_element"]][duplicate_id],
      field == "scope" ~ dictionary_mapping[["scope"]][duplicate_id],
      field == "soil_hue" ~ dictionary_mapping[["soil_hue"]][duplicate_id],
      field == "soil_horizon_suffix" ~ dictionary_mapping[["soil_horizon_suffix"]][duplicate_id],
      field == "soil_horizon_type" ~ dictionary_mapping[["soil_horizon_type"]][duplicate_id],
      field == "soil_texture" ~ dictionary_mapping[["soil_texture"]][duplicate_id],
      field == "completion" ~ "project_status",
      field == "soil_structure" ~ "horizon_structure",
      field == "moisture" ~ "moisture_regime",
      .default = field
    )
  ) |>
  select(-duplicate_id) |>
  # Bring in custom boolean dictionary
  bind_rows(boolean_dictionary) |> 
  # Restrict dictionary to enumeratedDomain attributes
  semi_join(attribute_table |> filter(domain == "enumeratedDomain"),
    by = join_by(field == attributeName)
  ) |>
  arrange(field) 

# Rename columns to match EML schema
factors_table = dictionary_compiled |>
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

# Export compiled documentation tables as CSVs ----
## Will be included in data package
write_csv(schema_compiled, 
          file = path(compiled_folder, "database_schema.csv"), 
          na = "")
write_csv(dictionary_compiled, 
          file = path(compiled_folder, "database_dictionary.csv"),
          na = "")

# Create EML data tables ----
all_data_tables <- list() # Initialize empty list for storing results

attribute_table_columns <- c("attributeName", "attributeDefinition", "domain", 
                             "measurementScale", "unit", "numberType", "definition", 
                             "formatString")
# Define primary key constraints
constraints_mapping <- list(
  name_adjudicated = list(primary_key = "taxon_name",     
                          entity = "entity_taxonomy"),
  name_accepted = list(primary_key = "taxon_accepted", 
                       entity = "entity_taxonomy"),
  field = list(primary_key = "field",
               entity = "entity_database_schema")
)

# Iterate over each compiled table
for (i in 1:length(compiled_fields_list)) {
  current_table <- unique(compiled_fields_list[[i]]$compiled_table)
  current_filename <- str_c(current_table, ".csv")
  current_fields <- compiled_fields_list[[i]]$field

  # Get attribute table
  current_schema <- attribute_table |>
    filter(schema_table == current_table) 
  
  current_attributes <- current_schema |>
    select(all_of(attribute_table_columns))
  
  # Get factors table
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
      missingValues = current_missing  # Add missing values if they exist
    )
  }

  # Define constraints
  current_constraints <- list()
  
  ## Add constraints for foreign key/primary key relationships
  
  existing_constraints <- intersect(names(constraints_mapping), current_fields)
  
  for (foreign_key in existing_constraints){
    specific_mapping = constraints_mapping[[foreign_key]]
    
    constraint_name = str_c(current_table,
                            foreign_key,
                            "link", 
                            sep="_")
    
    current_constraints[[length(current_constraints) + 1]] = create_key_constraint(
      constraint_name = constraint_name,
      foreign_key_name = foreign_key,
      primary_key_name = specific_mapping$primary_key,
      entity_name = specific_mapping$entity
      )
  
  }
  
  ## Add primary key constraints
  primary_key_fields <- current_schema |> 
    filter(primary_key_constraint == TRUE) |> 
    arrange(match(attributeName, current_fields)) |>  # Ensure primary keys are listed in the order that they appear in the physical file
    pull(attributeName)
  
  if (length(primary_key_fields) > 0) {
    pk_constraint_name <- str_c(current_table, "primary_key", sep = "_")
    
    # Append to constraints list
    current_constraints[[length(current_constraints) + 1]] <- list(
      constraintName = pk_constraint_name,
      primaryKey = list(
        key = primary_key_fields
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
  row_count <- as.character(nrow(read_csv(path(compiled_folder, current_filename),
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
      list(taxonRankName = "Phylum", taxonRankValue = "Basidiomycota")  # e.g., Lichenomphalia
    )
  )
)

# Define checklist authors
checklist_creators = list(
  list(individualName = list(givenName = "Timm", surName = "Nawrocki")),
  list(individualName = list(givenName = "Caroline", surName = "Parker")),
  list(individualName = list(givenName = "James", surName = "Walton")),
  list(individualName = list(givenName = "Preston", surName = "Villumsen")),
  list(individualName = list(givenName = "Bruce", surName = "Bennett")),
  list(individualName = list(givenName = "Matthew", surName = "Carlson")),
  list(individualName = list(givenName = "John", surName = "DeLapp")),
  list(individualName = list(givenName = "Justin", surName = "Fulkerson")),
  list(individualName = list(givenName = "Martin", surName = "Hutten")), 
  list(individualName = list(givenName = "Brian", surName = "Heitz")), 
  list(individualName = list(givenName = "Stefanie", surName = "Ickert-Bond")), 
  list(individualName = list(givenName = "Mary", surName = "Stensvold")), 
  list(individualName = list(givenName = "Campbell", surName = "Webb"))
)

# Assemble taxonomic coverage
taxonomic_coverage <- eml$taxonomicCoverage(
  generalTaxonomicCoverage = "Taxonomic coverage includes vascular plants, bryophytes, and lichens, but varies by project and individual site visit. Among the 44,324 unique site visits in the AKVEG Database, 65% recorded exhaustive, species-level data of vascular plants. In contrast, bryophyte and lichen records are generally limited to dominant species (55% of site visits) or absent (29% of visits). Taxonomic coverage of individual site visits is documented in this data package's `site_visit` table with separate fields for vascular plants, bryophytes, and lichens.",
  taxonomicSystem = list(
    classificationSystem = list(
      classificationSystemCitation = list(
          title = "Checklist of Vascular Plants, Bryophytes, Lichens, and Lichenicolous Fungi of Alaska",
          creator = checklist_creators,
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
site_visit_dates = read_csv(path(compiled_folder, "site_visit.csv"),
                      col_select = "observe_date",
                      col_types = "D") |>  # Set to Date
  summarize(min_date = min(observe_date),
            max_date = max(observe_date)) |> 
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

## Group by thesaurus
grouped_keywords <- keywords %>% 
  group_by(Thesaurus) %>% 
  summarize(keywords_list = list(Keyword), .groups = 'drop')

# Construct EML keywordSet for each thesaurus group
keyword_sets <- map(1:nrow(grouped_keywords), function(i) {
  thesaurus <- grouped_keywords$Thesaurus[i]
  words <- grouped_keywords$keywords_list[[i]]
  
  # Leave thesaurus undefined for local vocabularies
  if (thesaurus == "None") {
    eml$keywordSet(
      keyword = words
    )
  } else {
    eml$keywordSet(
      keyword = words,
      keywordThesaurus = thesaurus
    )
  }
})

## Verify that keywords were correctly parsed
print(keyword_sets)

# Parse EML abstract ----

# Parse Markdown metadata files
abstract_eml <- set_TextType(abstract_path)

# Clean abstract formatting
abstract_eml$para <- map(abstract_eml$para, function(p) {
  para_clean <- str_replace_all(p, "\\n", " ")
  para_clean <- str_squish(para_clean) # Strip extra whitespaces
  return(para_clean)
})

# Parse EML methods ----
## set_methods() does not parse Markdown file as expected
## Need to add samplingCitation and software

# Compile final EML file
akveg_metadata <- eml$dataset(
  title = "Alaska Vegetation (AKVEG) Database (Version 2.11.0): Harmonized plot-level vegetation observations for Alaska and adjacent Canada, 1975–2025",
  pubDate = "2026",
  creator = emld::as_emld(list(
    individualName = list(givenName = "Amanda",
                          surName = "Droghini"), 
    organizationName = "University of Alaska Anchorage"
  )),
  contact = list(
    individualName = list(givenName = "Amanda",
                          surName = "Droghini"),
    organizationName = "University of Alaska Anchorage",
    electronicMailAddress = "adroghini@alaska.edu"
  ),
  abstract = abstract_eml,
  keywordSet = keyword_sets,
  coverage = global_coverage,
  methods = "",
  
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

# Validate EML file
validation_result <- eml_validate(eml_doc)

print(validation_result)

# Write EML XML to disk
write_eml(eml_doc, "compiled_folder/akveg_metadata.xml")

# Clean up workspace ----
dbDisconnect(database_connection)
rm(list = ls())
