-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query soil metrics
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated: 2025-03-12
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query soil metrics" queries all soil pH, conductivity, and temperature data from the AKVEG Database.
-- ---------------------------------------------------------------------------

-- Compile soils data
SELECT soil_metrics.site_visit_code as site_visit_code
     , soil_metrics.water_measurement as water_measurement
     , soil_metrics.measure_depth_cm as measure_depth_cm
     , soil_metrics.ph as ph
     , soil_metrics.conductivity_mus as conductivity_mus
     , soil_metrics.temperature_deg_c as temperature_deg_c
FROM soil_metrics
    LEFT JOIN site_visit ON soil_metrics.site_visit_code = site_visit.site_visit_code;
