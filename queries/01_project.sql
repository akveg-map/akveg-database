-- -*- coding: utf-8 -*-
-- ---------------------------------------------------------------------------
-- Query projects
-- Author: Timm Nawrocki, Alaska Center for Conservation Science
-- Last Updated:  2026-05-05
-- Usage: Script should be executed in a PostgreSQL 16+ database.
-- Description: "Query projects" queries the project metadata.
-- ---------------------------------------------------------------------------

-- Compile project data
SELECT DISTINCT site_visit.project_code     as project_code
              , project.project_name        as project_name
              , originator.organization     as originator
              , funder.organization         as funder
              , personnel.personnel         as manager
              , completion.completion       as project_status
              , project.year_start          as year_start
              , project.year_end            as year_end
              , project.project_description as project_description
              , project.private             as private
              , source_type.source_type     as source_type
              , citations.citation_short    as source_citation
              , citations.citation_url      as source_url
              , project.acquisition_date    as acquisition_date
FROM site_visit
         LEFT JOIN project ON site_visit.project_code = project.project_code
         LEFT JOIN organization originator ON project.originator_id = originator.organization_id
         LEFT JOIN organization funder ON project.funder_id = funder.organization_id
         LEFT JOIN personnel ON project.manager_id = personnel.personnel_id
         LEFT JOIN completion ON project.completion_id = completion.completion_id
         LEFT JOIN source_type ON project.source_type_id = source_type.source_type_id
         LEFT JOIN citations ON project.citation_id = citations.citation_id;
