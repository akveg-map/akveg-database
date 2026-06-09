-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query abiotic top cover
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-12
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query abiotic top cover" queries all abiotic top cover data from the AKVEG Database.
-- ---------------------------------------------------------------------------

-- Compile abiotic top cover data
SELECT abiotic_top_cover.site_visit_code as site_visit_code
     , ground_element.ground_element as abiotic_element
     , abiotic_top_cover.abiotic_top_cover_percent as cover_percent
FROM abiotic_top_cover
    LEFT JOIN site_visit ON abiotic_top_cover.site_visit_code = site_visit.site_visit_code
    LEFT JOIN ground_element ON abiotic_top_cover.abiotic_element_code = ground_element.ground_element_code;
