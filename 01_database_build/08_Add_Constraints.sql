-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Define check constraints
-- Author: Amanda Droghini, Alaska Center for Conservation Science
-- Last Updated: 2026-04-27
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Define check constraints" alters existing tables by defining and adding a check constraint to validate inserted data. This script must be run after the INSERT scripts to function properly.
-- ---------------------------------------------------------------------------

-- Initialize transaction
START TRANSACTION;

-- Create function for constraining abiotic element type
CREATE OR REPLACE FUNCTION check_abiotic_element(p_code varchar)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM ground_element
        WHERE ground_element_code = p_code
          AND element_type IN ('abiotic', 'both')
        );
END;
$$ LANGUAGE plpgsql;

-- Add constraint to abiotic top cover table and validate records
ALTER TABLE abiotic_top_cover
    ADD CONSTRAINT check_abiotic_element_type
    CHECK (check_abiotic_element(abiotic_element_code));

-- Remove constraint to avoid issues with export file
ALTER TABLE abiotic_top_cover
    DROP CONSTRAINT check_abiotic_element_type;

-- Commit transaction
COMMIT TRANSACTION;
