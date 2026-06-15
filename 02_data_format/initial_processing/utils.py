# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# utils.py
# Author: Amanda Droghini
# Last Updated: 2026-06-15
# ---------------------------------------------------------------------------

"""
This module provides utility functions for processing and ingestion of datasets into the
AKVEG Database.

Functions include:
1. get_template: Read in template schema for use when validating processed tables.
2. filter_sites_in_alaska: Filter plots that aren't within the map boundary (Alaska and adjacent Canada)
and re-project coordinates of included sites to NAD83.
3. plot_survey_dates: Create a bar chart (histogram) displaying the distribution of survey dates across sites.
Facilitates detection of temporal outliers.
4. get_taxonomy: Queries the AKVEG Database to obtain all taxonomic names in the AKVEG Comprehensive Checklist and
their corresponding accepted name.
5. get_usda_codes: Removes author names from accepted scientific names for USDA plant codes. The resulting cleaned
column can now be joined with the scientific names in the AKVEG Database without further processing.
6. get_abiotic_elements: Queries the AKVEG Database to obtain abiotic/ground elements and their element type.
7. add_abiotic_elements: Uses the abiotic query from function 5 to identify and add missing abiotic elements with a
cover of 0%.
8. get_valid_values: Queries the AKVEG Database to retrieve valid values from a reference table.
"""

# Import packages
import geopandas as gpd
import numpy as np
import plotly.express as px
import polars as pl
import os
from akutils import connect_database_postgresql
from akutils import query_to_dataframe
from typing import Union, Literal, List, Tuple
from pathlib import Path
from psycopg2 import sql
from plotly.graph_objects import Figure
from pyproj import CRS

# Define file path for the map boundary
BOUNDARY_PATH = os.path.join("C:/", "ACCS_Work", "Projects", "AKVEG_Map", "Data", "region_data",
                             "AlaskaYukon_MapDomain_3338.shp")

# Define project folder
PROJECT_FOLDER = os.path.join("C:/", "ACCS_Work", 'OneDrive - University of Alaska', 'ACCS_Teams', 'Vegetation',
                              'AKVEG_Database')

# Define database credential file
CREDENTIAL_FILE = os.path.join(PROJECT_FOLDER, 'Credentials', 'akveg_public_read',
                               'authentication_akveg_public_read.csv')

# Define USDA Plants file
USDA_CODES_FILE = os.path.join(PROJECT_FOLDER, 'Data', "Tables_Taxonomy", "USDA_Plants", "USDA_Plants_20240301.csv")

# Define allowed element type values
ElementTypes = Literal["all", "ground", "abiotic"]
VALID_ELEMENT_TYPES = {"all", "ground", "abiotic"}  # For validating input during runtime

# Define template folder path
TEMPLATE_DIR = os.path.join(PROJECT_FOLDER, 'Data', 'Data_Entry')

# Map template shorthand codes to their file paths
TEMPLATE_MAP = {}

for file in Path(TEMPLATE_DIR).glob('[0-9][0-9]_*'):
    file_stem = file.stem
    # Split file stem at first underscore only to get rid of the numbers
    file_code = file_stem.split('_',1)[1]
    TEMPLATE_MAP[file_code]=file

# Define schema for specific template tables
# If table is not listed, uses default Polars type
SCHEMA_OVERRIDES = {
        "project": {"year_start": pl.Int64,
                    "year_end": pl.Int64
                    },
        "site": {"latitude_dd": pl.Decimal(precision=19, scale=16),
                 "longitude_dd": pl.Decimal(precision=19, scale=16),
                 "h_error_m": pl.Decimal(precision=6, scale=2)
                 },
        "environment": {"disturbance_time_y": pl.Int64,
                        "depth_water_cm": pl.Decimal(precision=4, scale=1),
                        "depth_moss_duff_cm": pl.Decimal(precision=4, scale=1),
                        "depth_restrictive_layer_cm": pl.Decimal(precision=4, scale=1),
                        "microrelief_cm": pl.Decimal(precision=4, scale=1),
                        "surface_water": pl.Boolean,
                        "cryoturbation": pl.Boolean,
                        "depth_15_percent_coarse_fragments_cm": pl.Decimal(precision=4, scale=1)
                        }
}

# --- Function 1 ---
def get_template(
        template_code: str
) -> pl.DataFrame:
    """
            Reads an AKVEG template Excel file into a Polars DataFrame. The template file can be used to validate
            column names and column order during processing.

            Args:
                template_code: Short-hand identifier for the table (e.g., 'project').

            Returns:
                A Polars DataFrame of the template schema.
            """
    # Standardize code
    clean_code = template_code.replace(" ", "_").replace("-", "_").lower()
    # Retrieve file path associated with template code
    template_path = TEMPLATE_MAP.get(clean_code)

    if template_path is None:
        raise ValueError(f"Table '{template_code}' not found. Available: {list(TEMPLATE_MAP.keys())}")

    # Apply schema overrides if they exist and return template table
    overrides = SCHEMA_OVERRIDES.get(clean_code, {})
    return pl.read_excel(template_path, schema_overrides=overrides)


# --- Function 2 ---
def filter_sites_in_alaska(
        site_df: pl.DataFrame | gpd.GeoDataFrame,
        input_crs: str | None = None,
        longitude_col: str | None = "longitude_dd",
        latitude_col: str | None = "latitude_dd",
        return_outside: bool = False
) -> pl.DataFrame | Tuple[pl.DataFrame, gpd.GeoDataFrame] | None:
    """
    Filters a DataFrame of sites (Polars or GeoPandas), keeping only those
    that fall within the map boundary, and re-projects the coordinates to NAD83 (2011).

    Args:
        site_df: The input DataFrame containing site coordinates. Accepted input types: Polars DataFrame, GeoPandas
        GeoDataFrame.
        input_crs: The EPSG code (as a string, e.g., "EPSG:4269") of the
                   input latitude and longitude columns. Required if site_df is a Polars DataFrame.
        longitude_col: Column name for longitude.
        latitude_col: Column name for latitude.
        return_outside: bool, default False
            If True, the function returns a tuple containing (sites_inside_df, sites_outside_gdf).
            If False, returns only the sites_inside_df DataFrame.

    Returns:
        A tuple containing:
        1. sites_inside_df (pl.DataFrame): Sites inside the boundary,
           re-projected to NAD83 with updated lat/long columns.
        2. sites_outside_gdf (gpd.GeoDataFrame): Original sites that fell
           outside the boundary (for troubleshooting).
        Returns (None, None) if the boundary file cannot be loaded.
    """

    # --- Validate input ---
    if not os.path.exists(BOUNDARY_PATH):
        print(f"ERROR: Map boundary file not found at: {BOUNDARY_PATH}")
        return None

    # --- Setup CRSs ---
    # CRS of map boundary
    TARGET_CRS_INTERSECT = "EPSG:3338"
    # CRS of final output
    ## Use precise realization of NAD83
    TARGET_CRS_NAD83 = "EPSG:6318"
    # Modern realization of WGS84
    MODERN_WGS84_CRS = "EPSG:8999"

    # 1. Load the region boundary
    try:
        region_boundary = gpd.read_file(BOUNDARY_PATH).to_crs(TARGET_CRS_INTERSECT)
    except Exception as e:
        print(f"ERROR loading or reprojecting region boundary: {e}")
        if return_outside:
            return None, None
        return None

    # 2. Determine object type and convert to GeoDataFrame
    if isinstance(site_df, pl.DataFrame):

        ## Ensure user has specified CRS and coordinates
        if input_crs is None:
            raise ValueError("input_crs must be provided for Polars DataFrames.")

        # Validate CRS
        try:
            valid_crs = CRS.from_user_input(input_crs)
        except Exception:
            raise ValueError(f"Invalid CRS provided: {input_crs}")

        # Identify missing coordinate columns
        required_coords = [longitude_col, latitude_col]
        missing_cols = []
        for col_name in required_coords:
            if col_name not in site_df.columns:
                missing_cols.append(col_name)

        # Raise error if any are missing
        if missing_cols:
            raise ValueError(f"Required coordinate columns {missing_cols} are missing from the Polars DataFrame.")

        ## Convert to GeoPandas GeoDataFrame
        site_pd = site_df.to_pandas()
        site_spatial = gpd.GeoDataFrame(
                site_pd,
                geometry=gpd.points_from_xy(site_pd[longitude_col], site_pd[latitude_col]),
                crs=valid_crs
            )
    elif isinstance(site_df, gpd.GeoDataFrame):
        site_spatial = site_df.copy()

    # Log input CRS
    detected_crs = site_spatial.crs.to_string() if site_spatial.crs else "None"
    print(f"Detected Input CRS: {detected_crs}")

    # Override input CRS if generic WGS84 was used
    if site_spatial.crs and site_spatial.crs.to_epsg() == 4326:
        print(f"Re-interpreting generic EPSG:4326 as {MODERN_WGS84_CRS}")
        site_spatial.crs = MODERN_WGS84_CRS

    # 2. Project to NAD83 (2011)
    site_spatial_project = site_spatial.to_crs(TARGET_CRS_NAD83)

    # 3. Create temporary object in EPSG:3338 for boundary check
    ## Prevents having to re-project multiple times, with compounding uncertainty
    site_spatial_temp = site_spatial_project.to_crs(crs=TARGET_CRS_INTERSECT)

    # 4. Find sites within the map boundary
    ## Spatial query returns an ndarray with shape 2 (input_geometries, tree_geometries). Index
    # 0 will contain row indices for the input geometries (i.e., sites) that had at least one intersection with the
    # region_boundary polygon.
    sites_inside_idx = region_boundary.sindex.query(
        geometry=site_spatial_temp.geometry,
        predicate="intersects"
    )[0]

    # 5. Filter the original data using the resulting indices
    unique_idx = np.unique(sites_inside_idx)  ## Necessary because region_boundary is a shapefile with multiple
    # polygons; edge cases where a site is on the border of two polygons can lead to duplicate rows
    sites_inside_gdf = site_spatial_project.iloc[unique_idx].copy()

    # 6. Log sites that fell outside region boundary
    sites_outside_gdf = site_spatial_project[~site_spatial_project.index.isin(sites_inside_gdf.index)].copy()
    print(f"Total input sites: {site_df.shape[0]}")
    print(f"Sites remaining after filtering (inside boundary): {sites_inside_gdf.shape[0]}")
    print(f"Sites filtered out (outside boundary): {sites_outside_gdf.shape[0]}")

    # 7. Add new lat/long columns from the reprojected geometry
    sites_inside_gdf['longitude_dd'] = sites_inside_gdf.geometry.x.round(decimals=6)
    sites_inside_gdf['latitude_dd'] = sites_inside_gdf.geometry.y.round(decimals=6)

    # 8. Convert the filtered GeoDataFrame back to a Polars DataFrame
    # Drop internal geometry column, but preserve original coordinates + NAD83-transformed coordinates
    sites_inside_df = (
        pl.from_pandas(sites_inside_gdf.drop(columns=['geometry']))
    )

    if return_outside:
        return sites_inside_df, sites_outside_gdf

    return sites_inside_df


# --- Function 3 ---
def plot_survey_dates(
        visit_df: pl.DataFrame,
        date_col: str = "observe_date",
        title: str = "Distribution of Survey Dates"
) -> Figure:
    """
    Generates a Plotly bar chart (histogram) showing the frequency of survey dates.

    :param visit_df: The input Polars DataFrame containing site visit dates.
    :param date_col: The name of the column with the observation dates.
    :param title: The title of the Plotly figure.
    :return: A Plotly Figure object.
    """

    # 1. Count number of occurrences per date
    hist_data = (
        visit_df.select(pl.col(date_col).cast(pl.Date).alias(date_col))
        .group_by(date_col)
        .agg(
            pl.len().alias("Count")
        )
        .sort(date_col)  # Sort for proper plotting
    )

    # 2. Create bar chart
    fig = px.bar(
        hist_data.to_pandas(),
        x=date_col,
        y="Count",
        title=title,
        labels={date_col: "Survey Date"}  # Set the x-axis label
    )

    # 3. Style and return Figure object
    fig.update_traces(marker_line_width=1, marker_line_color="black")

    return fig


# --- Function 4 ---
def get_taxonomy(
        credential_file: str = CREDENTIAL_FILE,
        simple: bool = False
) -> Union[pl.DataFrame, None]:
    """
    Queries the AKVEG Database taxonomy table.

    Args:
        credential_file: A string and valid file path that contains the credentials for authenticating to the AKVEG
        Database.

    Returns:
        A Polars dataframe with all synonymized names and their accepted names.
    """
    # --- Validate input ---
    if not os.path.exists(credential_file):
        print(f"ERROR: Database credential file not found at: {credential_file}")
        return None

    # 1. Connect to database
    akveg_db_connection = connect_database_postgresql(credential_file)

    # --- Validate database connection ---
    if akveg_db_connection is None:
        print("ERROR: Could not establish database connection.")
        return None

    try:
        # 2. Query database for taxonomy checklist
        taxonomy_query = """SELECT taxon_all.taxon_code
        , taxon_all.taxon_name
        , taxon_all.taxon_accepted_code
        , taxon_family.taxon_family as taxon_family
        , taxon_habit.taxon_habit as taxon_habit
        FROM taxon_all
        LEFT JOIN taxon_accepted ON taxon_all.taxon_accepted_code = taxon_accepted.taxon_accepted_code
        LEFT JOIN taxon_hierarchy ON taxon_accepted.taxon_genus_code = taxon_hierarchy.taxon_genus_code
        LEFT JOIN taxon_family ON taxon_hierarchy.taxon_family_id = taxon_family.taxon_family_id
        LEFT JOIN taxon_habit ON taxon_accepted.taxon_habit_id = taxon_habit.taxon_habit_id;"""

        # 3. Obtain full synonymized checklist
        taxonomy_original = query_to_dataframe(akveg_db_connection, taxonomy_query)
        taxonomy_original = pl.from_pandas(taxonomy_original)

        # 4. Create table with accepted names only
        taxonomy_accepted = (
            taxonomy_original.filter(pl.col("taxon_code") == pl.col("taxon_accepted_code"))
            .rename({"taxon_name": "name_accepted"})
            .select("taxon_accepted_code", "name_accepted")
        )

        # 5. Include accepted name in synonymized checklist
        taxonomy_akveg = (taxonomy_original.join(taxonomy_accepted, on='taxon_accepted_code', how='left')
                          )

        # 6. Drop 'extra' columns if simple = True
        if simple is True:
            taxonomy_akveg = taxonomy_akveg.select("taxon_code", "taxon_name")

        return taxonomy_akveg

    except Exception as e:
        print(f"An error occurred during query or processing: {e}")
        return None

    finally:
        # 6. Close the database connection
        akveg_db_connection.close()


# --- Function 5 ---
def get_usda_codes(
        usda_file: str = USDA_CODES_FILE
) -> pl.DataFrame:
    """
    Processes the USDA Plants file to remove author names from accepted names.
    :param usda_file: A string and valid file path that contains a list of USDA plant codes.
    :return: A Polars dataframe with all USDA Plants code and their accepted names without author names.
    """

    codes_lazy = pl.scan_csv(usda_file, null_values="")

    plant_codes = (
        codes_lazy
        .select(["Symbol", "Synonym Symbol", "Scientific Name with Author"])

        # Replace null values
        .with_columns(pl.when(pl.col("Synonym Symbol").is_null())
                      .then(pl.col("Symbol"))
                      .otherwise(pl.col("Synonym Symbol"))
                      .alias("usda_code")
                      )

        # Remove author name
        .with_columns(pl.col("Scientific Name with Author")
                      .str.replace(r"L\.", "")
                      .str.replace_all(r"\s+", " ")
                      .str.extract(r"^(.*?)(?:\s[A-Z]\.|\s[A-Z]|\s\(.*|$)", 1)
                      .str.strip_chars()
                      .alias("name_original"))

        # Select only desired columns
        .select(["usda_code", "name_original"])

        .collect()
    )

    return plant_codes

# --- Function 6 ---
def get_abiotic_elements(
        credential_file: str = CREDENTIAL_FILE,
        element_type: ElementTypes = "all"
) -> Union[pl.DataFrame, None]:
    """
    Queries the AKVEG Database ground cover table.

    Args:
        credential_file: A string and valid file path that contains the credentials for authenticating to the AKVEG
        Database.
        element_type: A string literal that identifies what type of element to return. Must be one of the following
        values: "all", "ground", or "abiotic".

    Returns:
        A Polars dataframe with all abiotic elements and their element type (abiotic, ground, or both).
    """
    # --- Validate input ---
    if not os.path.exists(credential_file):
        print(f"ERROR: Database credential file not found at: {credential_file}")
        return None

    if element_type not in VALID_ELEMENT_TYPES:
        allowed_values = ", ".join(sorted(VALID_ELEMENT_TYPES))
        raise ValueError(
            f"Invalid value for 'element_type': '{element_type}'. "
            f"Argument must be one of: {allowed_values}."
        )

    # 1. Connect to database
    akveg_db_connection = connect_database_postgresql(credential_file)

    # --- Validate database connection ---
    if akveg_db_connection is None:
        print("ERROR: Could not establish database connection.")
        return None

    try:
        # 2. Query database for abiotic elements
        abiotic_query = """SELECT ground_element.ground_element, ground_element.element_type
                    FROM ground_element;"""

        # 3. Convert to Polars dataframe
        all_elements = query_to_dataframe(akveg_db_connection, abiotic_query)
        all_elements = pl.from_pandas(all_elements)

        # 4. Subset based on element type
        ground_elements = all_elements.filter(pl.col("element_type") != "abiotic")
        abiotic_elements = all_elements.filter(pl.col("element_type") != "ground")

        if element_type == "abiotic":
            return abiotic_elements
        elif element_type == "ground":
            return ground_elements
        else:
            return all_elements

    except Exception as e:
        print(f"An error occurred during query or processing: {e}")
        return None

    finally:
        # 6. Close the database connection
        akveg_db_connection.close()

# --- Function 7 ---
def add_missing_elements(
        visit_codes: List[str],
        abiotic_df: pl.DataFrame,
        abiotic_query: pl.DataFrame
) -> pl.DataFrame:

    """
        Identifies and adds missing abiotic elements for each site visit, giving them a cover of 0%.

        Args:
            visit_codes: A list of unique site visits.
            abiotic_df: A Polars DataFrame containing site visit code, abiotic element name, and abiotic top
            cover percent for each abiotic element encountered during the site visit.
            abiotic_query: A Polars DataFrame containing entries for each abiotic element in the AKVEG Database. The
            get_abiotic_elements function returns a compatible DataFrame.

        Returns:
            A Polars DataFrame containing only the sites inside the boundary with coordinates in NAD83,
            or None if the boundary file cannot be loaded.
        """

    # Initialize a list to hold the result from each loop iteration
    results: List[pl.DataFrame] = []
    final_columns = ["site_visit_code", "abiotic_element", "abiotic_top_cover_percent"]

    for visit_code in visit_codes:
        subset_cover = (abiotic_df
                        .select(final_columns)
                        .filter(pl.col("site_visit_code") == visit_code))

        # If subset dataframe is empty, no abiotic top cover hits were recorded at that line.
        # Add every abiotic element with 0% percent
        if subset_cover.shape[0] == 0:
            elements_missing = abiotic_query

        # If subset dataframe is not empty, identify missing elements.
        else:
            elements_present = subset_cover['abiotic_element'].implode()
            elements_missing = abiotic_query.filter(~pl.col('ground_element').is_in(elements_present)
                                                    )
        # Assign 0% cover and visit code to missing elements
        elements_missing = (elements_missing.with_columns(pl.lit(0.0).alias("abiotic_top_cover_percent"),
                                                          pl.lit(visit_code).alias("site_visit_code"))
                            .rename({"ground_element": "abiotic_element"})
                            .select(final_columns)
                            )

        # Combine subset data with missing elements for complete list of abiotic elements for that site visit
        final_subset = pl.concat([subset_cover, elements_missing])

        # Append final subset to master list
        results.append(final_subset)

    # Concatenate list of results into Polars dataframe
    final_dataframe = (pl.concat(results)
                       .with_columns(pl.col("abiotic_top_cover_percent").round(decimals=2))
                       .sort(by=["site_visit_code", "abiotic_element"]))
    return final_dataframe


# --- Function 8 ---
def get_valid_values(
        table_name: str,
        field_name: str = None,
        credential_file: str = CREDENTIAL_FILE,
) -> Union[set, None]:
    """
    Queries the AKVEG Database to retrieve a list of valid values from a reference table.

    Args:
        credential_file: A string and valid file path that contains the credentials for authenticating to the AKVEG
        Database.
        table_name: Name of reference table.
        field_name: The column name in the reference table that has the constrained values.

    Returns:
        A set of constrained values.
    """
    # --- Validate input ---
    if not os.path.exists(credential_file):
        print(f"ERROR: Database credential file not found at: {credential_file}")
        return None

    # 1. Connect to database
    akveg_db_connection = connect_database_postgresql(credential_file)

    # --- Validate database connection ---
    if akveg_db_connection is None:
        print("ERROR: Could not establish database connection.")
        return None

    # 2. If field name is not supplied, try using table name
    if field_name is None:
        field_name = table_name

    try:
        # 3. Query database for foreign key values
        query_valid_values = sql.SQL("SELECT {field} FROM {table}").format(
            field=sql.Identifier(field_name),
            table=sql.Identifier(table_name)
        )

        values_original = query_to_dataframe(akveg_db_connection, query_valid_values.as_string(akveg_db_connection))
        values_set = set(pl.from_pandas(values_original)[field_name].unique())

        return values_set

    except Exception as e:
        print(f"An error occurred during query or processing: {e}")
        return None

    finally:
        # 4. Close the database connection
        akveg_db_connection.close()

