-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query site visits
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-12
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query site visits" queries all site visit data from the AKVEG Database.
-- ---------------------------------------------------------------------------

-- Compile site visit data
SELECT site_visit.site_visit_code as site_visit_code
	 , site_visit.project_code as project_code
     , site_visit.site_code as site_code
     , data_tier.data_tier as data_tier
	 , scope_vascular.scope as scope_vascular
     , scope_bryophyte.scope as scope_bryophyte
     , scope_lichen.scope as scope_lichen
	 , perspective.perspective as perspective
	 , cover_method.cover_method as cover_method
	 , plot_dimensions.plot_dimensions_m as plot_dimensions_m
	 , site_visit.observe_date as observe_date
     , site.latitude_dd as latitude_dd
     , site.longitude_dd as longitude_dd
     , structural_class.structural_class as structural_class
     , site_visit.homogeneous as homogeneous
FROM site_visit
    LEFT JOIN data_tier ON site_visit.data_tier_id = data_tier.data_tier_id
    LEFT JOIN site ON site_visit.site_code = site.site_code
	LEFT JOIN scope scope_vascular ON site_visit.scope_vascular_id = scope_vascular.scope_id
    LEFT JOIN scope scope_bryophyte ON site_visit.scope_bryophyte_id = scope_bryophyte.scope_id
    LEFT JOIN scope scope_lichen ON site_visit.scope_lichen_id = scope_lichen.scope_id
	LEFT JOIN perspective ON site.perspective_id = perspective.perspective_id
	LEFT JOIN cover_method ON site.cover_method_id = cover_method.cover_method_id
	LEFT JOIN plot_dimensions ON site.plot_dimensions_id = plot_dimensions.plot_dimensions_id
    LEFT JOIN structural_class ON site_visit.structural_class_code = structural_class.structural_class_code;