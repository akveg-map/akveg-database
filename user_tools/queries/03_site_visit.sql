-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query site visits
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2026-07-09
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
     , site_visit.observe_date as observe_date
     , veg_observer.personnel as veg_observer
     , veg_recorder.personnel as veg_recorder
     , env_observer.personnel as env_observer
     , soils_observer.personnel as soils_observer
     , structural_class.structural_class as structural_class
     , site_visit.homogeneous as homogeneous
FROM site_visit
    LEFT JOIN data_tier ON site_visit.data_tier_id = data_tier.data_tier_id
    LEFT JOIN site ON site_visit.site_code = site.site_code
	LEFT JOIN scope scope_vascular ON site_visit.scope_vascular_id = scope_vascular.scope_id
    LEFT JOIN scope scope_bryophyte ON site_visit.scope_bryophyte_id = scope_bryophyte.scope_id
    LEFT JOIN scope scope_lichen ON site_visit.scope_lichen_id = scope_lichen.scope_id
    LEFT JOIN personnel veg_observer ON site_visit.veg_observer_id = veg_observer.personnel_id
    LEFT JOIN personnel veg_recorder ON site_visit.veg_recorder_id = veg_recorder.personnel_id
    LEFT JOIN personnel env_observer ON site_visit.env_observer_id = env_observer.personnel_id
    LEFT JOIN personnel soils_observer ON site_visit.soils_observer_id = soils_observer.personnel_id
    LEFT JOIN structural_class ON site_visit.structural_class_code = structural_class.structural_class_code;