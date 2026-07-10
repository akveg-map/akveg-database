-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Build taxonomy tables
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2026-07-10
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Build taxonomy tables" creates the empty tables for the taxonomy components of the AKVEG database. WARNING: THIS SCRIPT WILL ERASE ALL DATA IN EXISTING TAXONOMY TABLES.
-- ---------------------------------------------------------------------------

-- Initialize transaction
START TRANSACTION;

-- Drop taxonomy tables if they exist
DROP TABLE IF EXISTS
    taxon_all,
    taxon_accepted,
    taxon_hierarchy,
    taxon_author,
    taxon_category,
    taxon_family,
    taxon_habit,
    taxon_status,
    taxon_level,
    taxon_source
CASCADE;

-- Create constraint tables
CREATE TABLE taxon_author (
    taxon_author_id integer PRIMARY KEY,
    taxon_author varchar(120) UNIQUE NOT NULL
);
CREATE TABLE taxon_category (
    taxon_category_id smallint PRIMARY KEY,
    taxon_category varchar(30) UNIQUE NOT NULL
);
CREATE TABLE taxon_family (
    taxon_family_id smallint PRIMARY KEY,
    taxon_family varchar(80) UNIQUE NOT NULL
);
CREATE TABLE taxon_habit (
    taxon_habit_id smallint PRIMARY KEY,
    taxon_habit varchar(80) UNIQUE NOT NULL
);
CREATE TABLE taxon_status (
    taxon_status_id smallint PRIMARY KEY,
    taxon_status varchar(30) UNIQUE NOT NULL
);
CREATE TABLE taxon_level (
    taxon_level_id smallint PRIMARY KEY,
    taxon_level varchar(30) UNIQUE NOT NULL
);
CREATE TABLE taxon_source (
    taxon_source_id smallint PRIMARY KEY,
    taxon_source varchar(50) UNIQUE NOT NULL,
    taxon_citation varchar(500) UNIQUE NOT NULL
);

-- Create hierarchy table
CREATE TABLE taxon_hierarchy (
    taxon_genus_code varchar(15) PRIMARY KEY,
    taxon_family_id smallint NOT NULL REFERENCES taxon_family,
    taxon_category_id smallint NOT NULL REFERENCES taxon_category
);

-- Create accepted taxa table
CREATE TABLE taxon_accepted (
    taxon_accepted_code varchar(15) PRIMARY KEY,
    taxon_genus_code varchar(15) NOT NULL REFERENCES taxon_hierarchy,
    taxon_source_id smallint NOT NULL REFERENCES taxon_source,
    taxon_link varchar(255),
    taxon_level_id smallint NOT NULL REFERENCES taxon_level,
    taxon_habit_id smallint NOT NULL REFERENCES taxon_habit,
    taxon_native boolean NOT NULL,
    taxon_non_native boolean NOT NULL
);

-- Create taxa table
CREATE TABLE taxon_all (
    taxon_code varchar(15) PRIMARY KEY,
    taxon_name varchar(120) UNIQUE NOT NULL,
    taxon_author_id integer NOT NULL REFERENCES taxon_author,
    taxon_status_id smallint NOT NULL REFERENCES taxon_status,
    taxon_accepted_code varchar(15) NOT NULL REFERENCES taxon_accepted
);

-- Commit transaction
COMMIT TRANSACTION;
