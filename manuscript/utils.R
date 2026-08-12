# ===========================================================================
# PARSE SCHEMA TO EML ----
# ===========================================================================
#' Map unmatched columns to database schema table
#'
#' @param unmatched_fields_df Data frame containing the unmatched fields. Must include the following columns: compiled_table (name of the compiled table with the unmatch field) and field (name of the unmatched field).
#' @param database_schema_df Master schema table.
#' @param field_map Parsed YAML file specifying mapping logic and custom definitions.
#'
#' @return A data frame with the same structure as the master schema table but populated with the unmatched fields and their attributes.

map_schema_fields <- function(unmatched_fields_df,
                              database_schema_df,
                              field_map) {
  # Loop over each field
  purrr::map_df(seq_len(nrow(unmatched_fields_df)), function(i) {
    target_table <- unmatched_fields_df$compiled_table[i]
    target_field <- unmatched_fields_df$field[i]

    # Look for a match in the database schema table
    ## Foreign keys were often resolved to lookup tables whose table name and field name are the same (e.g., physiography_id refers physiography field in physiography table)
    automatic_match <- database_schema_df |>
      dplyr::filter(
        schema_table == target_field,
        field == target_field
      )

    # If match is found, update names in master schema to reflect compiled table names. Keep all other attributes as they appear in the master schema.
    if (nrow(automatic_match) == 1) {
      return(
        automatic_match |>
          dplyr::mutate(
            schema_table = target_table,
            field = target_field
          )
      ) ## return() exits here if match is found
    }

    # If automatic matching fails, look for the field in the YAML map
    pointer <- field_map[[target_table]][[target_field]]

    if (!is.null(pointer)) {
      # Find relevant field in schema table
      base_query <- database_schema_df |>
        dplyr::filter(
          schema_table == pointer$db_table,
          field == pointer$db_field
        )

      # Print warning if table/field combination is not found in the master schema
      if (nrow(base_query) == 0) {
        warning(paste0(
          "YAML points to ", pointer$db_table, ".", pointer$db_field,
          ", but it does not exist in database schema table"
        ))
        return(NULL)
      }

      # Override field description in database schema table if a description exists in the YAML file
      if (!is.null(pointer$definition)) {
        return(
          base_query |>
            dplyr::mutate(
              schema_table = target_table,
              field = target_field,
              field_description = pointer$definition,
              is_unique = FALSE
            ) # Replace schema definition with custom one
        )
      } else {
        # Use existing description if one is not specified in the YAML file
        return(
          base_query |>
            dplyr::mutate(
              schema_table = target_table,
              field = target_field,
              is_unique = FALSE
            )
        )
      }
    }
    # Capture any unmatched fields that could not be automatically matched and that do not exist in the YAML file
    warning(paste0("Could not find reference for: ", target_table, ".", target_field))
    return(NULL)
  })
}

# ===========================================================================
# EML CONSTRAINTS ----
# ===========================================================================
#' Create data table constraints to link foreign keys with priamry keys
#'
#' @param constraint_name Name of constraint as it will appear in the EML file
#' @param foreign_key_name Character string of field name that serves as a foreign key for this table
#' @returns List that can be included in an eml$dataTable call

create_key_constraint <- function(constraint_name,
                                  foreign_key_name,
                                  entity_name) {
  eml$constraint(
    foreignKey = list(
      constraintName = constraint_name,
      key = list(attributeReference = foreign_key_name),
      entityReference = entity_name
    )
  )
}

# ===========================================================================
# EML KEYWORDS ----
# ===========================================================================

#' Create EML keyword set from CSV
#'
#' @param keyword_path Path to a CSV file of keywords with columns: Keyword, Thesaurus
#'
#' @returns A list of EML `keywordSet` objects, where each element in the list represents a grouped set of keywords associated with a specific thesaurus. If no thesaurus is provided, the corresponding `keywordSet` will contain `<keyword>` tags and an empty`<keywordThesaurus>` tag, which will be dropped when writing to XML via `EML::write_eml()`. when If a thesaurus is provided, the `keywordSet` will have values in both tags.
#'

create_keyword_set <- function(keyword_path) {
  # Read in keyword CSV
  keywords <- readr::read_csv(keyword_path, show_col_types = FALSE)

  # Group by thesaurus
  grouped_keywords <- keywords %>%
    dplyr::group_by(Thesaurus) %>%
    dplyr::summarize(
      keywords_list = list(Keyword),
      .groups = "drop"
    )

  # Construct EML keywordSet for each thesaurus group

  keyword_sets <- purrr::map(1:nrow(grouped_keywords), function(i) {
    thesaurus <- grouped_keywords$Thesaurus[i]
    words <- grouped_keywords$keywords_list[[i]]

    if (thesaurus == "None") {
      EML::eml$keywordSet(keyword = words) # Leave thesaurus undefined for local vocabularies
    } else {
      EML::eml$keywordSet(
        keyword = words,
        keywordThesaurus = thesaurus
      )
    }
  })
}

# ===========================================================================
# FIX FOREIGN KEY SEQUENCE ----
# ===========================================================================


#' Fix foreign key sequence for compliance with EML XML schema
#'
#' @param xml_file_path Path to the compiled EML XML file.
#' @return File path of the corrected EML XML file path with compliant foreignKey ordering.

fix_foreign_keys <- function(xml_file_path) {
  # Parse as XML doc
  xml_doc <- xml2::read_xml(xml_file_path)

  # Find all foreignKey elements across the dataset
  foreign_keys <- xml2::xml_find_all(xml_doc, "//foreignKey")

  # Reorder <entityReference> so that it comes after <key>
  for (fk in foreign_keys) {
    key_node <- xml2::xml_find_first(fk, "./key")
    entity_ref_node <- xml2::xml_find_first(fk, "./entityReference")

    if (!inherits(key_node, "xml_missing") && !inherits(entity_ref_node, "xml_missing")) {
      # Extract entity reference text
      entity_ref_text <- xml2::xml_text(entity_ref_node)
      # Remove existing node
      xml2::xml_remove(entity_ref_node)
      # Add entityReference node to the end of <foreignKey> (default behavior for add_child)
      xml2::xml_add_child(fk, entity_ref_node)
    }
  }

  xml2::write_xml(xml_doc, xml_file_path)
  message("Reordered foreignKey elements in: ", xml_file_path)
  return(invisible(xml_file_path))
}

# ===========================================================================
# BULK ADD FILES TO DATA PACKAGE ----
# ===========================================================================


#' Bulk add files to a DataPackage object.
#'
#' @param deposit_path Path to the folder that contains all files to be included in the deposit. Assumes that a single XML file exists in the directory, which is the EML XML file.
#' @return A complete DataPackage object
#'
create_data_package <- function(deposit_path) {
  # Get path of XML file
  xml_path <- fs::dir_ls(deposit_path, glob = "*.xml")

  # Validate EML schema before continuing
  is_valid <- EML::eml_validate(as.character(xml_path))

  if (!is_valid) {
    validation_errors <- attr(is_valid, "errors")

    message("EML validation failed\n")
    print(validation_errors)

    stop("Execution stopped")
  }

  message("EML schema validated successfully")

  # Extract packageId (urn:uuid) from EML file
  eml_doc <- EML::read_eml(xml_path)
  eml_id <- eml_doc$packageId

  # Create metadata object
  ## Pass package ID as an argument
  message("Creating metadata from... ", path_file(xml_path))

  metadata_object <- new(
    "DataObject",
    id       = eml_id,
    format   = "https://eml.ecoinformatics.org/eml-2.2.0",
    filename = xml_path
  )

  # Create empty DataPackage object and add metadata object
  dp <- new("DataPackage")
  dp <- addMember(dp, metadata_object)

  # Get list of files in deposit, excluding XML file
  all_files <- fs::dir_ls(deposit_path, type = "file")
  data_files <- all_files[all_files != xml_path]

  # Create data objects for remaining files
  for (file_path in data_files) {
    file_ext <- tolower(fs::path_ext(file_path))

    # Map file extension to DataONE format type
    format_type <- switch(file_ext,
      "csv"     = "text/csv",
      "pdf"     = "application/pdf",
      "rmd"     = "text/x-rmarkdown",
      "html"    = "text/html",
      "r"       = "text/plain",
      "txt"     = "text/plain",
      "zip"     = "application/zip",
      NULL
    )

    # Create source objects with appropriate file format
    if (is.null(format_type)) {
      message("Undefined file format. Skipping... ", path_file(file_path))
    } else {
      source_object <- new("DataObject", format = format_type, filename = file_path)
      # Add to data package and associate with metadata
      dp <- addMember(dp, source_object, metadata_object)
    }
  }
  # Return data package
  return(dp)
}
