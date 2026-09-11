-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Create public read only user
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-21
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Create read only users" creates the public-read user for the database
-- ---------------------------------------------------------------------------

-- Create a read only role
CREATE ROLE read_access;
GRANT CONNECT ON DATABASE akveg_public TO read_access;
GRANT USAGE ON SCHEMA public TO read_access;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_access;

-- Add a public user with read privileges
CREATE USER public_read WITH PASSWORD 'public_read_password';
GRANT read_access TO public_read;
