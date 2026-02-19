-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Build site and site visit tables
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2026-02-18
-- Usage: Script should be executed in a PostgreSQL 16+ database.
-- Description: "Build site tables" creates the empty tables for the site components of the AKVEG database. WARNING: THIS SCRIPT WILL ERASE ALL DATA IN EXISTING SITE TABLE.
-- ---------------------------------------------------------------------------

-- Initialize transaction
START TRANSACTION;

-- Drop site tables if they exist
DROP TABLE IF EXISTS
    site,
    site_visit
CASCADE;

-- Create site table
CREATE TABLE site (
    site_code varchar(50) PRIMARY KEY,
    establishing_project_code varchar(30) NOT NULL REFERENCES project,
    perspective_id smallint NOT NULL REFERENCES perspective,
    cover_method_id smallint NOT NULL REFERENCES cover_method,
    plot_dimensions_id smallint NOT NULL REFERENCES plot_dimensions,
    h_datum_epsg integer NOT NULL REFERENCES h_datum,
    latitude_dd decimal(19,16) NOT NULL CONSTRAINT latitude_limit CHECK (latitude_dd >= 50.4 AND latitude_dd <= 71.6),
    longitude_dd decimal(19,16) NOT NULL CONSTRAINT longitude_limit CHECK ((longitude_dd >= -179.99 AND longitude_dd <= -124) OR longitude_dd > 172),
    h_error_m decimal(6,2) NOT NULL DEFAULT -999,
    positional_accuracy_id smallint NOT NULL REFERENCES positional_accuracy,
    location_type_id smallint NOT NULL REFERENCES location_type
);

-- Create site visit table
CREATE TABLE site_visit (
    site_visit_code varchar(65) PRIMARY KEY,
    project_code varchar(30) NOT NULL REFERENCES project,
    site_code varchar(50) NOT NULL REFERENCES site,
    data_tier_id smallint NOT NULL REFERENCES data_tier,
    scope_vascular_id smallint NOT NULL REFERENCES scope,
    scope_bryophyte_id smallint NOT NULL REFERENCES scope,
    scope_lichen_id smallint NOT NULL REFERENCES scope,
    observe_date date NOT NULL CONSTRAINT year_range CHECK (EXTRACT(YEAR FROM observe_date) BETWEEN 1990 AND EXTRACT(YEAR FROM CURRENT_DATE)),
    veg_observer_id smallint NOT NULL REFERENCES personnel,
    veg_recorder_id smallint REFERENCES personnel,
    env_observer_id smallint REFERENCES personnel,
    soils_observer_id smallint REFERENCES personnel,
    structural_class_code varchar(10) NOT NULL REFERENCES structural_class,
    homogeneous boolean NOT NULL
);

-- Commit transaction
COMMIT TRANSACTION;