-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query soil horizons
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-12
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query soil horizons" queries all soil horizon data from the AKVEG Database.
-- ---------------------------------------------------------------------------

-- Compile soils data
SELECT soil_horizons.site_visit_code as site_visit_code
     , soil_horizons.horizon_order as horizon_order
     , soil_horizons.thickness_cm as thickness_cm
     , soil_horizons.depth_upper_cm as depth_upper_cm
     , soil_horizons.depth_lower_cm as depth_lower_cm
     , soil_horizons.depth_extend as depth_extend
     , soil_horizons.horizon_primary_code as horizon_primary_code
     , soil_horizons.horizon_suffix_1_code as horizon_suffix_1
     , soil_horizons.horizon_suffix_2_code as horizon_suffix_2
     , soil_horizons.horizon_secondary_code as horizon_secondary_code
     , soil_horizons.horizon_suffix_3_code as horizon_suffix_3
     , soil_horizons.horizon_suffix_4_code as horizon_suffix_4
     , soil_texture.soil_texture as texture
     , soil_horizons.clay_percent as clay_percent
     , soil_horizons.total_coarse_fragment_percent as total_coarse_fragment_percent
     , soil_horizons.gravel_percent as gravel_percent
     , soil_horizons.cobble_percent as cobble_percent
     , soil_horizons.stone_percent as stone_percent
     , soil_horizons.boulder_percent as boulder_percent
     , soil_structure.soil_structure as structure
     , soil_horizons.matrix_hue_code as matrix_hue_code
     , soil_horizons.matrix_value as matrix_value
     , soil_horizons.matrix_chroma as matrix_chroma
     , soil_nonmatrix_features.nonmatrix_feature as nonmatrix_feature
     , soil_horizons.nonmatrix_hue_code as nonmatrix_hue_code
     , soil_horizons.nonmatrix_value as nonmatrix_value
     , soil_horizons.nonmatrix_chroma as nonmatrix_chroma
FROM soil_horizons
    LEFT JOIN site_visit ON soil_horizons.site_visit_code = site_visit.site_visit_code
    LEFT JOIN soil_texture ON soil_horizons.texture_code = soil_texture.soil_texture_code
    LEFT JOIN soil_structure ON soil_horizons.structure_code = soil_structure.soil_structure_code
    LEFT JOIN soil_nonmatrix_features on soil_horizons.nonmatrix_feature_code = soil_nonmatrix_features.nonmatrix_feature_code;
