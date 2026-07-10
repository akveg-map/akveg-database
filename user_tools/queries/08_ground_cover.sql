-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query ground cover
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2026-07-10
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query ground cover" queries the ground cover data.
-- ---------------------------------------------------------------------------

-- Compile ground cover data
SELECT ground_cover.site_visit_code as site_visit_code
     , ground_element.ground_element as ground_element
     , ground_cover.ground_cover_percent as ground_cover_percent
FROM ground_cover
    LEFT JOIN ground_element ON ground_cover.ground_element_code = ground_element.ground_element_code;
