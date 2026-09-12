# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# utils_init.py
# Author: Amanda Droghini
# Last Updated: 2026-09-12
# ---------------------------------------------------------------------------

"""
This module provides functions for initializing the ETL working environment.


Functions include:
1. load_system_paths: Create an object with absolute file paths so that relative paths can be used within scripts.
"""

# Import packages
import yaml
from pathlib import Path
from types import SimpleNamespace
from typing import Union

# --- Function 1 ---
# Load local file paths from yaml config file
def load_system_paths(config_file: Union[str, Path] = "paths.yaml") -> SimpleNamespace:
  """
  Description: Parses a YAML configuration file relative to the project's root folder and returns a nested
  SimpleNamespace object with resolved absolute file paths.

  :param config_file: Relative string filename or Path to the config file. Defaults to "paths.yaml" in the project root.
  :return: A nested SimpleNamespace object containing absolute pathlib.Path objects.
  """

  # Establish location of config file
  project_root = Path(__file__).resolve().parent.parent  # Relative to user_tools/utils_init.py
  config_path = project_root / config_file

  # Read the YAML file
  with open(config_path, encoding="utf-8") as f:
    raw_config = yaml.safe_load(f)

  # Define nested dictionary
  anchor = raw_config["default"]

  # Build the base paths
  drive = Path(anchor["drive"])
  root = drive / anchor["root_folder"]
  cloud = root / anchor["cloud_path"]

  # Construct absolute system paths
  root_paths = {
    "repository": root / anchor["repository_path"],
    "archive": root / anchor["archive_path"]
  }

  cloud_paths = {
    "plots": cloud / anchor["plots_path"],
    "templates": cloud / anchor["templates_path"],
    "taxonomy": cloud / anchor["taxonomy_path"],
    "metadata": cloud / anchor["metadata_path"],
    "credentials": cloud / anchor["authentication_file"],
  }

  # Convert to SimpleNamespace to use dot notation
  return SimpleNamespace(root=root,
                         cloud=cloud,
                         repository=root_paths.get("repository"),
                         archive=root_paths.get("archive"),
                         cloud_assets=SimpleNamespace(**cloud_paths))

