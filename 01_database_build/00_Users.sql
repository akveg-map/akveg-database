-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Create private read only user
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-21
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Create read only users" creates the private-read user for the database
-- ---------------------------------------------------------------------------

-- Create a read only role
CREATE ROLE read_access;
GRANT CONNECT ON DATABASE akveg_private_build TO read_access;
GRANT USAGE ON SCHEMA public TO read_access;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_access;

-- Add a private user with read privileges
CREATE USER private_read WITH PASSWORD 'private_read_password';
GRANT read_access TO private_read;

-- Add a public user with read privileges
CREATE USER public_read WITH PASSWORD 'public_build_password';
GRANT read_access TO public_read;
