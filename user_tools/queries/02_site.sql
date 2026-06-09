-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query sites
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated:  2023-04-04
-- Usage: Script should be executed in a PostgreSQL 14+ database.
-- Description: "Query sites" queries the site data.
-- ---------------------------------------------------------------------------

-- Compile site data
SELECT site.site_code as site_code
     , site.establishing_project_code as establishing_project_code
     , perspective.perspective as perspective
     , cover_method.cover_method as cover_method
     , h_datum.h_datum as h_datum
     , site.latitude_dd as latitude_dd
     , site.longitude_dd as longitude_dd
     , site.h_error_m as h_error_m
     , positional_accuracy.positional_accuracy as positional_accuracy
     , plot_dimensions.plot_dimensions_m as plot_dimensions_m
     , location_type.location_type as location_type
FROM site
    LEFT JOIN perspective ON site.perspective_id = perspective.perspective_id
    LEFT JOIN cover_method ON site.cover_method_id = cover_method.cover_method_id
    LEFT JOIN h_datum ON site.h_datum_epsg = h_datum.h_datum_epsg
    LEFT JOIN positional_accuracy ON site.positional_accuracy_id = positional_accuracy.positional_accuracy_id
    LEFT JOIN plot_dimensions ON site.plot_dimensions_id = plot_dimensions.plot_dimensions_id
    LEFT JOIN location_type ON site.location_type_id = location_type.location_type_id
ORDER BY establishing_project_code, site_code;
