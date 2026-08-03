## Database Design and Structure

The AKVEG Database schema was built by translating the _Minimum Standards for Field Observation of Vegetation and Related Properties_ into a relational database schema with structured attributes and constrained vocabularies.

The _Minimum Standards_ were derived from the Federal Geographic Data Committee's U.S. National Vegetation Classification Standard Version 2 (https://www.fgdc.gov/standards/projects/vegetation/index_html), and are therefore compatible with federal standards. A copy of the Minimum Standards is archived in this data package (VWG_2022_Minimum_Standards_v1_1.pdf).

The database was implemented in a PostgreSQL (v17.9) system hosted in Google Cloud SQL. The SQL scripts used to build the AKVEG Database structure are permanently archived as version 2.9.2 on Zenodo: https://doi.org/10.5281/zenodo.20635288.

## Data Acquisition

Vegetation datasets were acquired from four main sources: (1) Original data: Downloading publicly available datasets from online repositories and catalogs; (2) Secondary databases: Extracting data from existing synthesized databases; (3) AKVEG origin: Compiling datasets managed by AKVEG staff, including digitizing paper datasheets; (4) Direct transfer: Obtaining data directly from principal investigators and data managers.

Tracking details for each source dataset, including how it was acquired and links to the original datasets, are documented in the PROJECT table.

To respect data sharing agreements and to keep this data package focused on the harmonized data, raw source files are not included in this data package. Instead, these files are securely stored within an enterprise cloud storage system maintained by the University of Alaska Anchorage. To prevent data loss, synchronized copies of the raw data files are maintained on a local computer and in secure cloud storage. An offline copy is saved to an external hard drive every six months.

## Data Harmonization and Quality Control

Data cleaning and harmonization were performed to reconcile original datasets into a single, unified structure. This process included four main components:

Taxonomic names: Original scientific names recorded in the field were matched to names in the _Checklist of Vascular Plants, Bryophytes, Lichens, and Lichenicolous Fungi of Alaska_. This checklist accounts for synonyms, spelling variations, and misapplied names, and is built into the AKVEG Database as a set of 10 reference tables. Original names were matched to an exact equivalent in the checklist. Ambiguous names that could not be automatically resolved by code were manually reviewed and corrected by an expert botanist. A compiled copy is included in this data package (taxonomy.csv).

Categorical values: Categorical values and qualitative descriptions were re-classified to the nearest appropriate term within the database's controlled vocabularies. In the AKVEG Database, these allowed values are enforced using field lookup tables. A list of allowed values and their definitions are included in this data package (database_dictionary.csv).

Measurement units: Quantitative field measurements were converted into standardized metric values using the International System of Units (SI). For datasets where vegetation cover was originally recorded using categorical cover classes (such as Braun-Blanquet or Daubenmire scales), ordinal classes were converted to continuous percentages using the midpoint of each class.

Coordinates: Original plot coordinates were transformed and re-projected into the North American Datum of 1983 (NAD83, corresponding to EPSG:4269).

Standardized quality control checks were executed within each processing script. These checks were designed to flag missing required fields, correct formatting inconsistencies, and identify outliers, such as geographic coordinates outside the target bounding box. Every flagged error was manually reviewed and verified against the original source data.

## Software and Code Availability

The harmonization workflow was executed using R (version 4.6.1; R Core Team, 2026) and Python (version 3.13.12; Python Software Foundation, 2024). The data processing scripts are permanently archived as version 2.9.2 on Zenodo: https://doi.org/10.5281/zenodo.20635288.

## Field Sampling Design

The original datasets integrated in the AKVEG Database reflect a wide variety of field sampling designs and protocols. Our processing workflow extracts key methodological metadata and documents them in the SITE and SITE_VISIT tables, which are included in this data package. These metadata fields are designed to capture attributes that are most relevant for vegetation mapping and classification, including:

Sampling strategy (location_type): Distinguishes between randomized sampling designs and subjective, targeted plot placements (such as plots intentionally placed within a specific vegetation community type).

Observation perspective (perspective): Identifies the physical vantage point of the primary observer, explicitly separating ground-level surveys from aerial survey.

Plot dimensions (plot_dimensions_m): Records the area and geometry of the sampling plot.

Vegetation cover method (cover_method): Documents the sampling protocol used to estimate vegetation cover, distinguishing between line-point intercept, semi-quantitative visual estimates, and categorical class methods.

Comprehensive descriptions of project-specific protocols are outside the scope of the AKVEG Database. Users looking for more context on a project's sampling design can consult the PROJECT_CITATIONS table, which includes references to the canonical publication or final report that accompanies each project.

## Study Extent

Spatial coverage is not uniform across the study region. Initial synthesis efforts intentionally prioritized arctic and boreal biomes, followed by targeted efforts to fill data gaps in Southwest Alaska, the Bering Sea and Aleutian Islands, and bordering regions of northwestern Canada. Data coverage in Southeast Alaska is limited, as datasets lacking precise, un-fuzzed geographic coordinates are omitted from inclusion in the AKVEG Database.

The database includes records spanning five decades (1975–2025). Observations collected between 2005 and 2014 represent 41% of the entire database, while only 18% of all records predate the year 2000. This temporal distribution reflects an intentional strategy to prioritize datasets that support contemporary vegetation mapping and classification. The database primarily captures snapshots in time rather than long-term monitoring trends. Of the 44,324 unique site visits compiled in the AKVEG Database, less than 1% (N=294) represent repeat visits to the same plot location.

Across all years, ground surveys account for 70% of all surveys in AKVEG, however, historical records prior to 2010 were primarily collected by aerial surveys. The reasons for this shift from aerial to ground surveys are beyond the scope of this study.

## Ethical Research Practices

Data in the AKVEG Database were compiled from historical and ongoing vegetation monitoring efforts conducted by many different agencies and research teams over several decades. Because this dataset is a synthesis of existing data, original land-use permits and field safety protocols were not verified.

Where known, field data collection protocols used low-impact sampling designs, including minimizing surface disturbance, re-filling soil pits, and restricting the harvesting of species to voucher specimens. Documented field safety protocols include standard protocols for fieldwork in remote wilderness settings: bear safety, firearm safety, and helicopter transport.

For users wishing to understand the original project contexts, the canonical publication or final report for each contributing project is available in the PROJECT_CITATIONS table.

At the request of the original data contributors, some datasets are not included in this public release. Records of sensitive species have also been removed from some datasets.

## Lineage

This data package represents the Version 2.11.0 release of the Alaska Vegetation (AKVEG) Database.
