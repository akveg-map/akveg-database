# ===========================================================================
# ENVIRONMENT SET-UP ----
# ===========================================================================
#' Load local file paths
#'
#' Parses a local YAML configuration file and returns a structured list
#' of resolved absolute paths.
#'
#' @param config_file Path to the YAML file. Defaults to "paths.yml" in the project root.
#'
#' @return A named list of class `fs_path` objects.
#'

load_system_paths <- function(config_file = "paths.yaml") {
  # Read the YAML file
  raw_config <- config::get(file = config_file)
  
  # Build the base paths
  drive_path <- fs::path(raw_config$drive)
  root_path <- fs::path(drive_path, raw_config$root_folder)
  
  # Construct absolute system paths
  resolved_paths <- list(
    root        = root_path,
    repository  = fs::path(root_path, raw_config$repository_path),
    archive     = fs::path(root_path, raw_config$archive_path),
    credentials = fs::path(root_path, raw_config$authentication_file)
  )
  
  return(resolved_paths)
}
