-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Build project tables
-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
-- Last Updated: 2026-04-23
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Build project tables" creates the empty tables for the vegetation survey and monitoring projects components of the AKVEG database. WARNING: THIS SCRIPT WILL ERASE ALL DATA IN EXISTING PROJECT TABLES.
-- ---------------------------------------------------------------------------

-- Initialize transaction
START TRANSACTION;

-- Drop project tables if they exist
DROP TABLE IF EXISTS
    project,
    project_source,
    project_status,
    project_citations
CASCADE;

-- Create projects table
CREATE TABLE project (
    project_code varchar(30) PRIMARY KEY,
    project_name varchar(250) UNIQUE NOT NULL,
    originator_id smallint NOT NULL REFERENCES organization,
    funder_id smallint NOT NULL REFERENCES organization,
    manager_id smallint NOT NULL REFERENCES personnel,
    completion_id smallint NOT NULL REFERENCES completion,
    year_start smallint NOT NULL,
    year_end smallint NOT NULL,
    project_description varchar(500) NOT NULL,
    private boolean NOT NULL,
    source_type_id smallint NOT NULL REFERENCES source_type,
    source_collection_id smallint REFERENCES source_collection,
    published bool NOT NULL,
    download_url text,
    source_contact_id smallint REFERENCES personnel,
    acquisition_date date NOT NULL
);

-- Create project status table
CREATE TABLE project_status (
    project_status_id smallint PRIMARY KEY,
    project_code varchar(30) NOT NULL REFERENCES project,
    project_modified date NOT NULL,
    site_modified date,
    vegetation_modified date,
    abiotic_modified date,
    environment_modified date,
    modified_by_id smallint NOT NULL
);

--- Create project citation junction table
CREATE TABLE project_citations (
    project_code varchar(30) NOT NULL REFERENCES project,
    citation_id smallint NOT NULL REFERENCES citations,
    PRIMARY KEY (project_code, citation_id)
);

-- Commit transaction
COMMIT TRANSACTION;