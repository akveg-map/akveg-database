-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query structural group cover
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-12
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query structural group cover" queries the structural group cover data.
-- ---------------------------------------------------------------------------

-- Compile structural group cover data
SELECT structural_group_cover.site_visit_code as site_visit_code
     , cover_type.cover_type as cover_type
     , structural_group.structural_group as structural_group
     , structural_group_cover.cover_percent as cover_percent
FROM structural_group_cover
    LEFT JOIN site_visit ON structural_group_cover.site_visit_code = site_visit.site_visit_code
    LEFT JOIN cover_type ON structural_group_cover.cover_type_id = cover_type.cover_type_id
    LEFT JOIN structural_group ON structural_group_cover.structural_group_id = structural_group.structural_group_id;
