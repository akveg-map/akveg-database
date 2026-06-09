-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query database dictionary
-- Author: Amanda Droghini, Alaska Center for Conservation Science
-- Last Updated: 2026-06-02
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Query database dictionary" queries the database dictionary table, joining foreign key fields with their respective reference tables.
-- ---------------------------------------------------------------------------

-- Compile database dictionary
SELECT database_schema.field as field
     , database_dictionary.data_attribute as data_attribute
     , database_dictionary.definition as definition
FROM database_dictionary
    LEFT JOIN database_schema ON database_dictionary.field_id = database_schema.field_id
ORDER BY field, database_dictionary.data_attribute;
