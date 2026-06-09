-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query shrub structure
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-12
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query shrub structure" queries all shrub structure data from the AKVEG Database with standardized taxonomic concepts.
-- ---------------------------------------------------------------------------

-- Compile shrub structure data
SELECT shrub_structure.site_visit_code as site_visit_code
     , taxon_accepted.taxon_code as code_accepted
     , taxon_accepted.taxon_name as name_accepted
     , shrub_class.shrub_class as shrub_class
     , height_type.height_type as height_type
     , shrub_structure.height_cm as height_cm
     , cover_type.cover_type as cover_type
     , shrub_structure.cover_percent as cover_percent
     , shrub_structure.mean_diameter_cm as mean_diameter_cm
     , shrub_structure.number_stems as number_stems
     , shrub_structure.shrub_subplot_area_m2 as shrub_subplot_area_m2
FROM shrub_structure
    LEFT JOIN site_visit ON shrub_structure.site_visit_code = site_visit.site_visit_code
    LEFT JOIN taxon_all taxon_adjudicated ON shrub_structure.code_adjudicated = taxon_adjudicated.taxon_code
    LEFT JOIN taxon_all taxon_accepted ON taxon_adjudicated.taxon_accepted_code = taxon_accepted.taxon_code
    LEFT JOIN cover_type ON shrub_structure.cover_type_id = cover_type.cover_type_id
    LEFT JOIN shrub_class ON shrub_structure.shrub_class_id = shrub_class.shrub_class_id
    LEFT JOIN height_type ON shrub_structure.height_type_id = height_type.height_type_id;
