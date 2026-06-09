<div align="left">
  <img src="assets/akveg_logo.png" width="300" style="margin-bottom: -20px;" alt="AKVEG logo with text: Alaska Vegetation Map">
</div>

# Alaska Vegetation Database

The Alaska Vegetation (AKVEG) Database is a cloud-based, PostgreSQL database that contains harmonized field observation data on vegetation cover,
environmental site characteristics, and soils metrics for over 44,000 plots in Alaska and adjacent Canada. 

Data in AKVEG span five decades, four bioclimatic zones, and two nations, making it one of the most comprehensive field vegetation databases in northwest North America.

![Spatial distribution of plots in AKVEG](assets/map_akveg_plots.png)

## About the Project 🌿

The AKVEG Database provides researchers and land managers with easy-to-use, harmonized data on vegetation cover and associated environmental characteristics. Prior to being added to the AKVEG Database, all datasets are cleaned and standardized to a common schema: qualitative values are re-classified, measurement units are standardized, and scientific names are reconciled to a taxonomic standard.

The AKVEG Database contains:

- Site- and date-specific observations of vegetation and related environmental characteristics.
- Methodological metadata for all datasets, allowing users to evaluate whether a specific dataset or site is appropriate for their application.
- A taxonomic standard to reconcile taxon names and concepts applied in Alaska and adjacent Canada.

The AKVEG Database supports a variety of projects related to conservation, vegetation ecology, wildlife ecology, and land use planning. Data in AKVEG have been used to:

- Provide biodiversity data for the region.
- Develop [ecologically detailed vegetation maps](https://www.akveg.org/maps).
- Update vegetation classification schemes.
- Predict [important wildlife habitat](https://doi.org/10.1002/ecs2.70069).

## Getting Started 🖥️

The AKVEG Database is built in PostgreSQL and hosted on a cloud server that can be queried in numerous ways. This repository provides example scripts to query the database in Python and R.

You will need server credentials to query the database. You can request server credentials by filling out a
[Database Access Form](https://akveg.org/request-database-access/). The database is public and
free to use; the purpose of the server credentials is to prevent excessive loads on the server and for us to know
how many people are connecting.

## Documentation 📚

The reference for the AKVEG Database can be accessed at [docs.akveg.org](https://docs.akveg.org/).

Our online documentation includes a detailed guide for connecting to, understanding, and exploring the AKVEG Database.

Once you have obtained the server credentials, the [Getting Started tutorial](https://docs.akveg.org/docs/database/get-started/) will guide you through connecting to the database and executing simple queries to extract data from the database.

## Update Schedule 🗓️

The AKVEG Database is updated at least once a quarter. If you need a static version of the data, you can export your query results to a CSV file.

Changes related to datasets and the database schema are recorded in the [CHANGELOG](CHANGELOG.md), while changes related to the taxonomic standard are documented in a separate [TAXONOMY CHANGELOG](CHANGELOG_TAXONOMY.md).

## Contributing 🤝

If you've spotted an error in the database, [open a new issue](https://github.com/accs-uaa/akveg-database-public/issues). Please review existing issues before opening a new one to avoid duplicates. If your issue already exists, add a comment to help us prioritize issues that are most relevant to our users.

If you would like to contribute a dataset, consult the [Become a contributor](https://docs.akveg.org/docs/database/contribute/) section of our documentation.

## Built With 🛠️

- Python 3.13.12
- R 4.6.0
- PostgreSQL 17.9

Exact package versions for Python and R are documented in this repository.

### Python Environment
Python dependencies are managed via Conda/Miniforge and are provided in `environment.yml`.

To replicate, run `conda env create -f environment.yml`

### R Environment
R dependencies are tracked via `renv`. They are provided in the `renv.lock` file.

To replicate, install the `renv` package in R, set your working directory to this repository's root folder, and run `renv::restore()`.

### SQL Environment
SQL scripts were executed in a PostgreSQL 17.9 on a Google Cloud SQL instance. No extensions are required.

## License ⚖️

This repository contains only the scripts used to build the AKVEG Database. It does not include the data themselves.

All scripts and configuration files in this repository are licensed under the [MIT License](LICENSE). You are free to copy, modify, distribute, and use this software, including for private and commercial purposes. If you wish to re-distribute this code, please include the original copyright notice and permission notice in your code package.

## Citation

If you use these scripts to process data for your research, you can cite this software repository:

> Droghini, A., and T.W. Nawrocki. 2026. The AKVEG Database Code Repository (v1.0.0). Zenodo.

If you use data from the AKVEG Database, you can cite the database itself:

> Droghini, A., T.W. Nawrocki, A.F. Wells, M.J. Macander, and L.A. Flagstad. 2026. Alaska Vegetation (AKVEG) Database: Harmonized, multi-project vegetation field data for Alaska. Alaska Geospatial Council, Vegetation Working Group. Available: [https://www.akveg.org](https://www.akveg.org). Data downloaded on [date of query].

## Acknowledgments 🫶

AKVEG is a collaborative effort supported by several agencies and institutions. The U.S. Fish & Wildlife Service, Bureau of Land Management, National Park Service, U.S. Forest Service, Alaska Department of Fish & Game, Alaska Department of Natural Resources, Department of Navy, and University of Alaska Anchorage provided funding for the AKVEG Database.

## Authors

- **Amanda Droghini** - _Alaska Center for Conservation Science, University of Alaska Anchorage_
- **Timm W. Nawrocki** - _Alaska Center for Conservation Science, University of Alaska Anchorage_

## Contact 📧

- **Project Maintainer**: Amanda Droghini
- **Email**: adroghini (at) alaska (dot) edu
- **GitHub**: [@adroghini](https://github.com/adroghini)
