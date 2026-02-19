# Changelog

All changes to the AKVEG Database will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses a [custom versioning 
system](#versioning-system).

## [2.5.1] - 2026-02-19

### Fixed
* **yukon_biophysical_2020**: Corrected `cover_type` for all site visits in Vegetation Cover table.

## [2.5.0] - 2026-02-18

### Added
* 2 new taxonomic records: *×Elyhordeum* and *×Elyhordeum macounii*.
* **yukon_biophysical_2020**: Replaces yukon_biophysical_2015 and yukon_landcover_2016 (previously private, now 
  public). Add Project, Site, Site Visit, and Vegetation Cover.

## [2.4.1] - 2026-02-12

### Added
* 71 new taxonomic records, including 41 accepted species. These taxa need to exist in our 
  taxonomy table before Canadian datasets can be added. Most occur in Canada, but not in Alaska.

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
