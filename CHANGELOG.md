<div align="left">
  <img src="assets/akveg_logo.png" width="300" style="margin-bottom: -20px;" alt="AKVEG logo with text: Alaska Vegetation Map">
</div>

# Changelog

All changes to the AKVEG database are documented in this file. Changes to the AKVEG taxonomic standard are
documented in [CHANGELOG_TAXONOMY.md](CHANGELOG_TAXONOMY.md).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2.9.0] - 2026-05-06

### Fixed
* **Enforced referential integrity for citations in the `project` table.** Replaced `download_url` with 
  `citation_id`, which  references the `citations` table. This ensures that citations in the `project` table are 
  linked to formal bibliographic references. 
* **Updated LANDFIRE 2016 citation in `citations` table**.
* **Redacted sensitive species from the `vegetation_cover` table**. This redaction applies only to BLM AIM sites in
  the public version of the database. 38 records were redacted.

### Added
* The following project codes (all related to BLM AIM 2022-2023) are now public:
  * aim_central_yukon_fo_2022
  * aim_central_yukon_fo_2023
  * aim_eastern_interior_fo_2022
  * aim_eastern_interior_fo_2023
  * aim_kobuk_seward_2022
  * aim_kobuk_seward_2023

## [2.8.1] - 2026-04-28

* **Added provenance tracking to the `project` table.** New fields indicate how a project was acquired 
  (`source_type_id`), publication status and download URL (`published`, `download_url`), the original 
  database for secondary sources (`source_collection_id`), contact name for direct transfers (`source_contact_id`), and 
  the `acquisition_date`.
* **Added bibliographic citations**. Added a `citations` table and a `project_citations` junction table to store 
  metadata for reports, datasets, and other primary sources associated with each project.

## [2.8.0] - 2026-03-18

### Added
* **fws_yukonflats_2025**: Added Project, Site, Site Visit, and Vegetation Cover tables, representing 34 site visits and 579 unique cover observations.

### Fixed
* **yukon_biophysical_2020**: Restored 18 sites with 100% abiotic cover. These sites were previously excluded by QC filters due to a lack of vegetation cover observations.
* **fws_pribilof_2022**: Restored 10 sites (100% water/abiotic cover) that were previously excluded by QC filters.
* Restricted post-compilation adjudication of *Salix planifolia* to *S. pulchra* to central and western Alaska projects only. QC script previously applied correction to Canadian sites in the yukon_biophysical_2020 dataset.

## [2.7.0] - 2026-03-05

### Fixed
* **nrcs_soils_2024** [private]: Improved spatial alignment of site coordinates with original data. Upgraded the 
  coordinate transformation process from a generic WGS84-to-NAD83 shift to a high-precision datum realization 
  (ITRF2000 to NAD83 2011), resolving a ~2-meter horizontal drift.

## [2.6.0] - 2026-02-19

### Fixed
* **yukon_biophysical_2020**: Corrected `cover_type` for all site visits in Vegetation Cover table.

## [2.5.0] - 2026-02-18

### Added
* **yukon_biophysical_2020**: Replaces yukon_biophysical_2015 and yukon_landcover_2016 (previously private, now 
  public). Add Project, Site, Site Visit, and Vegetation Cover.

## [2.4.0] - 2026-02-09

### Added
* **nrcs_soils_2024** [private]: Added Environment table.

### Fixed
* **fws_tetlin_2024**: Reconciled 1 unknown plant code for site visit code TET24_058_20240829.

## [2.3.0] - 2026-01-24

### Added
* **aim_various_2023** [private]: Replaces aim_various_2022.
* **fws_tetlin_2024**: Added 22 site visits that were surveyed in late summer 2024. Dataset was private, but 
  is now public.

### Fixed
* **accs_nwisouthcentral_2024**: Corrected plot dimensions for all plots to 10 radius.
* **accs_shemya_2022**: Added two vegetation cover estimates which had previously been dropped because of missing 
  values. Correct `name_adjudicated` field to reflect correct value: `name_adjudicated` should be the taxon name 
  with the closest match in the AKVEG Checklist (i.e., corrected of typos), not the currently accepted name.
* **nrcs_soils_2024** [private]: Removed 201 duplicate sites.

## [2.2.0] - 2025-10-28

### Added

* **accs_nwisouthcentral_2024**: Add Project, Site, Site Visit, Vegetation Cover, Abiotic Top Cover, and Whole Tussock 
  Cover.
* **nps_swan_2024**: Replaces nps_swan_2021 (previously private, now public). Add Project, Site, Site Visit, and 
  Vegetation Cover. Abiotic Top Cover was available for nps_swan_2021, but is not yet available for nps_swan_2024.

### Removed

* **Abiotic Top Cover**: Removed data of elements that did not belong to the abiotic element set i.e., animal litter 
  and biotic.
* **yukon_biophysical_2015** [private] and **yukon_landcover_2016** [private]: Will be replaced by a newer, public 
  version 
  of the data that includes plots up until 2020.

### Fixed

* **Abiotic Top Cover**: Added missing elements for each site visit record and assigned them a cover percent of 0%.

## [2.1.1] 2025-09-24

### Added

* **ground_element_table**: Add `element_type` column to distinguish between elements that are included in the 
  abiotic top cover table, the ground cover table, or both.

## [2.1.0] - 2025-07-19

### Added

* **nrcs_soils_2024** [private]: Replaces nrcs_soils_2022.
* **abr_arcticrefuge_2019**: Add Environment, Soil Metrics, and Soil Horizons.
* **accs_ribdon_2019**: Add Abiotic Top Cover and Ground Cover.
* Add Whole Tussock Cover and Structural Group Cover for several ABR projects:
  * abr_meltwater_2000
  * abr_drillsite3s_2001
  * abr_npra_2003
  * abr_kuparuk_2006
  * abr_milnepoint_2008
  * abr_nuna_2010
  * abr_news_2011
  * abr_susitna_2013
  * abr_cd5_2016
  * abr_willow_2018
  * abr_stonyhill_2018
  * abr_colville_1996
  * abr_tarn_1997
  * abr_colville_1998

### Removed

* **nrcs_soils_2022**: Replaced by nrcs_soils_2024.

### Fixed

* Adjudicate all entries with *Salix planifolia* as name_original to *Salix pulchra* (#13).

## Versioning System

We use a MAJOR.MINOR.PATCH versioning system where we increment the:

1. MAJOR version when we change the database schema.
2. MINOR version for changes related to datasets, including adding, removing, or modifying datasets.
3. PATCH version for changes to the database schema or dictionary that do not substantially alter its structure e.g.,
   adding a constrained value, adding or modifying a descriptive field.

We began this change log on 2025-07-19. At that date, we were on schema version 2.0. For simplicity's sake, we started 
our minor version numbering at 1, though there were several changes to the database between the release of schema 2.0 and the updates on 2025-07-19.
