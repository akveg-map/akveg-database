-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Build vegetation tables
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2026-07-10
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Build vegetation tables" creates the empty tables for the vegetation components of the AKVEG database. WARNING: THIS SCRIPT WILL ERASE ALL DATA IN EXISTING VEGETATION TABLES.
-- ---------------------------------------------------------------------------

-- Initialize transaction
START TRANSACTION;

-- Drop project tables if they exist
DROP TABLE IF EXISTS
    vegetation_cover,
    whole_tussock_cover,
    structural_group_cover,
    tree_structure,
    shrub_structure;

-- Create vegetation cover table
CREATE TABLE vegetation_cover (
    vegetation_cover_id serial PRIMARY KEY,
    site_visit_code varchar(65) NOT NULL REFERENCES site_visit,
    cover_type_id smallint NOT NULL REFERENCES cover_type,
    name_original varchar(120) NOT NULL,
    code_adjudicated varchar(12) NOT NULL REFERENCES taxon_all,
    cover_percent decimal(6,3) NOT NULL,
    dead_status boolean NOT NULL,
    UNIQUE(site_visit_code, cover_type_id, name_original, code_adjudicated, dead_status)
);

-- Create whole tussock cover table
CREATE TABLE whole_tussock_cover (
    tussock_id serial PRIMARY KEY,
    site_visit_code varchar(65) NOT NULL REFERENCES site_visit,
    cover_type_id smallint NOT NULL REFERENCES cover_type,
    cover_percent decimal(6,3) NOT NULL,
    UNIQUE(site_visit_code, cover_type_id)
);

-- Create structural group cover table
CREATE TABLE structural_group_cover (
    structural_cover_id serial PRIMARY KEY,
    site_visit_code varchar(65) NOT NULL REFERENCES site_visit,
    cover_type_id smallint NOT NULL REFERENCES cover_type CONSTRAINT str_group_check_cover_type CHECK (cover_type_id IN (1, 3)),
    structural_group_id smallint NOT NULL REFERENCES structural_group,
    cover_percent decimal(6,3) NOT NULL,
    UNIQUE(site_visit_code, cover_type_id, structural_group_id)
);

-- Create tree structure table
CREATE TABLE tree_structure (
    tree_structure_id serial PRIMARY KEY,
    site_visit_code varchar(65) NOT NULL REFERENCES site_visit,
    name_original varchar(120) NOT NULL,
    code_adjudicated varchar(12) NOT NULL REFERENCES taxon_all,
    crown_class_id smallint NOT NULL REFERENCES crown_class,
    height_type_id smallint NOT NULL REFERENCES height_type,
    height_cm decimal(8,1) NOT NULL,
    cover_type_id smallint REFERENCES cover_type CONSTRAINT tree_check_cover_type CHECK (cover_type_id IN (1, 3)),
    cover_percent decimal(6,3) NOT NULL,
    mean_dbh_cm decimal(7,3) NOT NULL,
    number_stems smallint NOT NULL,
    mean_tree_age_y smallint NOT NULL,
    tree_subplot_area_m2 decimal(10,3) NOT NULL
);

-- Create shrub structure table
CREATE TABLE shrub_structure (
    shrub_structure_id serial PRIMARY KEY,
    site_visit_code varchar(65) NOT NULL REFERENCES site_visit,
    name_original varchar(120) NOT NULL,
    code_adjudicated varchar(12) NOT NULL REFERENCES taxon_all,
    shrub_class_id smallint NOT NULL REFERENCES shrub_class,
    height_type_id smallint NOT NULL REFERENCES height_type,
    height_cm decimal(8,1) NOT NULL,
    cover_type_id smallint REFERENCES cover_type CONSTRAINT shrub_check_cover_type CHECK (cover_type_id IN (1, 3)),
    cover_percent decimal(6,3) NOT NULL,
    mean_diameter_cm decimal(7,3) NOT NULL,
    number_stems smallint NOT NULL,
    shrub_subplot_area_m2 decimal(10,3) NOT NULL
);

-- Commit transaction
COMMIT TRANSACTION;