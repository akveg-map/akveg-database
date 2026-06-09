-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query vegetation cover
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-21
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query vegetation cover" queries all vegetation cover data from the AKVEG Database.
-- ---------------------------------------------------------------------------

-- Compile vegetation cover
SELECT vegetation_cover.site_visit_code as site_visit_code
     , taxon_accepted.taxon_code as code_accepted
     , taxon_accepted.taxon_name as name_accepted
     , vegetation_cover.dead_status as dead_status
     , cover_type.cover_type as cover_type
     , vegetation_cover.cover_percent as cover_percent
FROM vegetation_cover
	LEFT JOIN site_visit ON vegetation_cover.site_visit_code = site_visit.site_visit_code
    LEFT JOIN cover_type ON vegetation_cover.cover_type_id = cover_type.cover_type_id
    LEFT JOIN taxon_all taxon_adjudicated ON vegetation_cover.code_adjudicated = taxon_adjudicated.taxon_code
    LEFT JOIN taxon_all taxon_accepted ON taxon_adjudicated.taxon_accepted_code = taxon_accepted.taxon_code;