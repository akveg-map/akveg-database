-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query database schema
-- Author: Amanda Droghini, Alaska Center for Conservation Science
-- Last Updated: 2026-07-12
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Query database schema" queries the database schema table, joining foreign key fields with their respective reference table.
-- ---------------------------------------------------------------------------

-- Compile database schema
SELECT database_schema.standards_section as standards_section
     , schema_category.schema_category as schema_category
     , schema_table.schema_table as schema_table
     , database_schema.field as field
     , data_type.data_type as data_type
	 , database_schema.field_length as field_length
     , database_schema.is_unique as is_unique
	 , database_schema.is_primary_key as is_primary_key
	 , database_schema.is_foreign_key as is_foreign_key
     , database_schema.is_required as is_required
     , link_table.schema_table as link_table
     , database_schema.field_description as field_description
     , missing_value_code.missing_value_code as missing_value_code
     , database_schema.missing_value_description as missing_value_description
FROM database_schema
    LEFT JOIN schema_category ON database_schema.schema_category_id = schema_category.schema_category_id
	LEFT JOIN schema_table ON database_schema.schema_table_id = schema_table.schema_table_id
    LEFT JOIN data_type ON database_schema.data_type_id = data_type.data_type_id
	LEFT JOIN schema_table as link_table ON database_schema.link_table_id = link_table.schema_table_id
    LEFT JOIN missing_value_code ON database_schema.missing_value_code_id = missing_value_code.missing_value_code_id
ORDER BY database_schema.standards_section, schema_table, database_schema.field;
