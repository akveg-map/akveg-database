-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query environment
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-12
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query environment" queries all environment data from the AKVEG Database.
-- ---------------------------------------------------------------------------

-- Compile environment data
SELECT environment.site_visit_code as site_visit_code
     , physiography.physiography as physiography
     , geomorphology.geomorphology as geomorphology
     , macrotopography.macrotopography as macrotopography
     , microtopography.microtopography as microtopography
     , moisture.moisture as moisture_regime
     , drainage.drainage as drainage
     , disturbance.disturbance as disturbance
     , disturbance_severity.disturbance_severity as disturbance_severity
     , environment.disturbance_time_y as disturbance_time_y
     , environment.depth_water_cm as depth_water_cm
     , environment.depth_moss_duff_cm as depth_moss_duff_cm
     , environment.depth_restrictive_layer_cm as depth_restrictive_layer_cm
     , restrictive_type.restrictive_type as restrictive_type
     , environment.microrelief_cm as microrelief_cm
     , environment.surface_water as surface_water
     , soil_class.soil_class as soil_class
     , environment.cryoturbation as cryoturbation
     , soil_texture.soil_texture as dominant_texture_40_cm
     , environment.depth_15_percent_coarse_fragments_cm as depth_15_percent_coarse_fragments_cm
FROM environment
    LEFT JOIN site_visit ON environment.site_visit_code = site_visit.site_visit_code
    LEFT JOIN physiography ON environment.physiography_id = physiography.physiography_id
    LEFT JOIN geomorphology ON environment.geomorphology_id = geomorphology.geomorphology_id
    LEFT JOIN macrotopography ON environment.macrotopography_id = macrotopography.macrotopography_id
    LEFT JOIN microtopography ON environment.microtopography_id = microtopography.microtopography_id
    LEFT JOIN drainage ON environment.drainage_id = drainage.drainage_id
    LEFT JOIN moisture ON environment.moisture_id = moisture.moisture_id
    LEFT JOIN restrictive_type ON environment.restrictive_type_id = restrictive_type.restrictive_type_id
    LEFT JOIN disturbance ON environment.disturbance_id = disturbance.disturbance_id
    LEFT JOIN disturbance_severity ON environment.disturbance_severity_id = disturbance_severity.disturbance_severity_id
    LEFT JOIN soil_class ON environment.soil_class_id = soil_class.soil_class_id
    LEFT JOIN soil_texture ON environment.dominant_texture_40_cm_code = soil_texture.soil_texture_code;
