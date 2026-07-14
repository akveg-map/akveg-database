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

map_to_schema_fields <- function(unmatched_fields_df,
                                 database_schema_df,
                                 field_map) {
  
  # Loop over each field
  purrr::map_df(seq_len(nrow(unmatched_fields_df)), function(i) {
    
    target_table <- unmatched_fields_df$compiled_table[i]
    target_field <- unmatched_fields_df$field[i]
    
    # Look for a match in the database schema table
    ## Foreign keys were often resolved to lookup tables whose table name and field name are the same (e.g., physiography_id refers physiography field in physiography table)
    automatic_match <- database_schema_df |> 
      dplyr::filter(schema_table == target_field,
                    field == target_field)
    
    # If match is found, update names in master schema to reflect compiled table names. Keep all other attributes as they appear in the master schema.
    if (nrow(automatic_match) == 1) {
      return(
        automatic_match |> 
          dplyr::mutate(schema_table = target_table, 
                        field = target_field)
      )  ## return() exits here if match is found
    }
    
    # If automatic matching fails, look for the field in the YAML map
    pointer <- field_map[[target_table]][[target_field]]
    
    if (!is.null(pointer)) {
      # Find relevant field in schema table
      base_query <- database_schema_df |> 
        dplyr::filter(schema_table == pointer$db_table, 
                      field == pointer$db_field)
      
      # Print warning if table/field combination is not found in the master schema
      if (nrow(base_query) == 0) {
        warning(paste0("YAML points to ", pointer$db_table, ".", pointer$db_field, 
                       ", but it does not exist in database schema table"))
        return(NULL)
      }
      
      # Override field description in database schema table if a description exists in the YAML file 
      if (!is.null(pointer$definition)){
        return(
          base_query |> 
            dplyr::mutate(schema_table = target_table, 
                          field = target_field, 
                          field_description = pointer$definition)  # Replace schema definition with custom one
        )
      } else {
        # Use existing description is one is not specified in the YAML file
        return(
          base_query |> 
            dplyr::mutate(schema_table = target_table,
                          field = target_field)
          
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
