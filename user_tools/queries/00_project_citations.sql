-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query project citations
-- Author: Amanda Droghini, Alaska Center for Conservation Science
-- Last Updated: 2026-07-09
-- Usage: Script should be executed in a PostgreSQL 17+ database.
-- Description: "Query project citations" queries the project citations junction table, joining foreign key fields with their respective reference table.
-- ---------------------------------------------------------------------------

-- Compile project citations
SELECT project_citations.project_code as project_code
     , citations.citation_short as citation_short
     , citations.citation_long as citation_long
     , citations.citation_url as citation_url
FROM project_citations
    LEFT JOIN citations ON project_citations.citation_id = citations.citation_id
ORDER BY project_citations.project_code, citations.citation_short;
