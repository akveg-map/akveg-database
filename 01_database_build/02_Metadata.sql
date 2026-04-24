-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Build metadata and constraint tables
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2026-04-23
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Build metadata and constraint tables" creates the empty tables for the metadata components of the AKVEG database, including the schema and data dictionary. WARNING: THIS SCRIPT WILL ERASE ALL DATA IN EXISTING METADATA TABLES.
-- ---------------------------------------------------------------------------

-- Initialize transaction
START TRANSACTION;

-- Drop metadata tables if they exist
DROP TABLE IF EXISTS
    citations,
    completion,
    cover_method,
    cover_type,
    crown_class,
    data_tier,
    data_type,
    database_dictionary,
    database_schema,
    disturbance,
    disturbance_severity,
    drainage,
    geomorphology,
    ground_element,
    h_datum,
    height_type,
    location_type,
    macrotopography,
    microtopography,
    moisture,
    organization,
    organization_type,
    personnel,
    perspective,
    physiography,
    plot_dimensions,
    positional_accuracy,
    restrictive_type,
    schema_category,
    schema_table,
    scope,
    shrub_class,
    soil_class,
    soil_nonmatrix_features,
    soil_structure,
    soil_texture,
    soil_horizon_type,
    soil_horizon_suffix,
    soil_hue,
    source_collection,
    source_type,
    structural_class,
    structural_group
CASCADE;

-- Create constraint tables

CREATE TABLE citations (
  citation_id serial PRIMARY KEY,
  citation_short varchar(50) UNIQUE NOT NULL,
  citation_long text UNIQUE NOT NULL,
  citation_url text
);

CREATE TABLE completion (
    completion_id smallint PRIMARY KEY,
    completion varchar(30) UNIQUE NOT NULL
);

CREATE TABLE cover_method (
    cover_method_id smallint PRIMARY KEY,
    cover_method varchar(50) UNIQUE NOT NULL
);

CREATE TABLE cover_type (
    cover_type_id smallint PRIMARY KEY,
    cover_type varchar(50) UNIQUE NOT NULL
);

CREATE TABLE crown_class (
    crown_class_id smallint PRIMARY KEY,
    crown_class varchar(30) UNIQUE NOT NULL
);

CREATE TABLE data_tier (
    data_tier_id smallint PRIMARY KEY,
    data_tier varchar(30) UNIQUE NOT NULL
);

CREATE TABLE data_type (
    data_type_id smallint PRIMARY KEY,
    data_type varchar(80) UNIQUE NOT NULL
);

CREATE TABLE disturbance (
    disturbance_id smallint PRIMARY KEY,
    disturbance varchar(50) UNIQUE NOT NULL
);

CREATE TABLE disturbance_severity (
    disturbance_severity_id smallint PRIMARY KEY,
    disturbance_severity varchar(20) UNIQUE NOT NULL
);

CREATE TABLE drainage (
    drainage_id smallint PRIMARY KEY,
    drainage varchar(50) UNIQUE NOT NULL
);

CREATE TABLE geomorphology (
    geomorphology_id smallint PRIMARY KEY,
    geomorphology varchar(50) UNIQUE NOT NULL
);

CREATE TABLE ground_element (
    ground_element_code varchar(2) PRIMARY KEY,
    ground_element varchar(50) UNIQUE NOT NULL,
    element_type varchar(7) NOT NULL
);

CREATE TABLE h_datum (
    h_datum_epsg integer PRIMARY KEY,
    h_datum varchar(20) UNIQUE NOT NULL
);

CREATE TABLE height_type (
    height_type_id smallint PRIMARY KEY,
    height_type varchar(50) UNIQUE NOT NULL
);

CREATE TABLE location_type (
    location_type_id smallint PRIMARY KEY,
    location_type varchar(20) UNIQUE NOT NULL
);

CREATE TABLE macrotopography (
    macrotopography_id smallint PRIMARY KEY,
    macrotopography varchar(50) UNIQUE NOT NULL
);

CREATE TABLE microtopography (
    microtopography_id smallint PRIMARY KEY,
    microtopography varchar(50) UNIQUE NOT NULL
);

CREATE TABLE moisture (
    moisture_id smallint PRIMARY KEY,
    moisture varchar(50) UNIQUE NOT NULL
);

CREATE TABLE organization_type (
    organization_type_id smallint PRIMARY KEY,
    organization_type varchar(50) UNIQUE NOT NULL
);

CREATE TABLE personnel (
    personnel_id smallint PRIMARY KEY,
    personnel varchar(50) UNIQUE NOT NULL
);

CREATE TABLE perspective (
    perspective_id smallint PRIMARY KEY,
    perspective varchar(50) UNIQUE NOT NULL
);

CREATE TABLE physiography (
    physiography_id smallint PRIMARY KEY,
    physiography varchar(30) UNIQUE NOT NULL
);

CREATE TABLE plot_dimensions (
    plot_dimensions_id smallint PRIMARY KEY,
    plot_dimensions_m varchar(20) UNIQUE NOT NULL
);

CREATE TABLE positional_accuracy (
    positional_accuracy_id smallint PRIMARY KEY,
    positional_accuracy varchar(30) UNIQUE NOT NULL
);

CREATE TABLE restrictive_type (
    restrictive_type_id smallint PRIMARY KEY,
    restrictive_type varchar(50) UNIQUE NOT NULL
);

CREATE TABLE schema_category (
    schema_category_id smallint PRIMARY KEY,
    schema_category varchar(80) UNIQUE NOT NULL
);

CREATE TABLE schema_table (
    schema_table_id smallint PRIMARY KEY,
    schema_table varchar(80) UNIQUE NOT NULL
);

CREATE TABLE scope (
    scope_id smallint PRIMARY KEY,
    scope varchar(30) UNIQUE NOT NULL
);

CREATE TABLE shrub_class (
    shrub_class_id smallint PRIMARY KEY,
    shrub_class varchar(20) UNIQUE NOT NULL
);

CREATE TABLE soil_class (
    soil_class_id smallint PRIMARY KEY,
    soil_class varchar(50) UNIQUE NOT NULL
);

CREATE TABLE soil_nonmatrix_features (
    nonmatrix_feature_code varchar(2) PRIMARY KEY,
    nonmatrix_feature varchar(30) UNIQUE NOT NULL
);

CREATE TABLE soil_structure (
    soil_structure_code varchar(3) PRIMARY KEY,
    soil_structure varchar(30) UNIQUE NOT NULL
);

CREATE TABLE soil_texture (
    soil_texture_code varchar(4) PRIMARY KEY,
    soil_texture varchar(50) UNIQUE NOT NULL
);

CREATE TABLE soil_horizon_type (
    soil_horizon_type_code varchar(1) PRIMARY KEY,
    soil_horizon_type varchar(30) UNIQUE NOT NULL
);

CREATE TABLE soil_horizon_suffix (
    soil_horizon_suffix_code varchar(2) PRIMARY KEY,
    soil_horizon_suffix varchar(50) UNIQUE NOT NULL
);

CREATE TABLE soil_hue (
    soil_hue_code varchar(5) PRIMARY KEY,
    soil_hue varchar(5) UNIQUE NOT NULL
);

CREATE TABLE source_collection (
    source_collection_id smallint PRIMARY KEY,
    source_collection varchar(50) UNIQUE NOT NULL
);

CREATE TABLE source_type (
    source_type_id smallint PRIMARY KEY,
    source_type varchar(30) UNIQUE NOT NULL
);

CREATE TABLE structural_class (
    structural_class_code varchar(10) PRIMARY KEY,
    structural_class varchar(50) UNIQUE NOT NULL
);

CREATE TABLE structural_group (
    structural_group_id smallint PRIMARY KEY,
    structural_group varchar(50) UNIQUE NOT NULL
);

-- Create organization table
CREATE TABLE organization (
    organization_id smallint PRIMARY KEY,
    organization varchar(20) UNIQUE NOT NULL,
    organization_type_id smallint NOT NULL REFERENCES organization_type
);

-- Create schema table
CREATE TABLE database_schema (
    field_id smallint PRIMARY KEY,
    standards_section smallint NOT NULL,
    schema_category_id smallint NOT NULL REFERENCES schema_category,
    schema_table_id smallint NOT NULL REFERENCES schema_table,
    field varchar(50) NOT NULL,
    data_type_id smallint NOT NULL REFERENCES data_type,
    field_length varchar(10),
    is_unique boolean NOT NULL,
    is_key boolean NOT NULL,
    required boolean NOT NULL,
    link_table_id smallint REFERENCES schema_table,
    field_description varchar(2000) NOT NULL
);

-- Create dictionary table
CREATE TABLE database_dictionary (
    dictionary_id integer PRIMARY KEY,
    field_id smallint NOT NULL REFERENCES database_schema,
    data_attribute_id varchar(10) NOT NULL,
    data_attribute varchar(120) NOT NULL,
    definition varchar(2000) NOT NULL
);

-- Commit transaction
COMMIT TRANSACTION;