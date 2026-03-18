# Alaska Vegetation Database

The Alaska Vegetation (AKVEG) Database is a cloud-based, PostgreSQL database that contains comprehensive vegetation,
environmental, and soils data for over 34,000 plots across Alaska and the western Yukon.

![Screenshot from the AKVEG Docs website](assets/flowchart.svg)

## About the Project 🌿

The AKVEG Database is a collaborative effort that seeks to provide scientists and natural resource managers with easy-to-use, standardized data on vegetation and associated environmental characteristics. Prior to being added to the AKVEG Database, all datasets are standardized and taxonomically reconciled. The data in the AKVEG Database are therefore analysis-ready: they follow a common format, have been cleaned to correct or omit errors, and share the same constrained values.

The AKVEG Database contains:

- A taxonomic standard to reconcile taxon names and concepts applied in Alaska and adjacent Canada
- Site- and date-specific observations of vegetation and related environmental characteristics covering four biomes (Arctic, boreal, temperate, and northern subpolar oceanic) in Alaska and adjacent Canada
- A versioned set of vegetation types officially accepted in [USNVC](https://usnvc.org/), along with additional provisional types for Alaska _(under development)_

The AKVEG Database supports a variety of projects related to conservation, vegetation ecology, wildlife ecology, and land use planning. Some of the goals of this project are to:

- Provide basic biodiversity data for the region.
- Support the development of high-resolution vegetation and land cover maps.
- Support vegetation classification efforts.
- Extends the value of field data beyond the area and purpose of the original data collection effort.
- Preserve legacy data and enable its compatibility with newly collected data.

## Getting Started 🖥️

The AKVEG Database is built in PostgreSQL and hosted on a cloud server that can be queried in numerous ways. This repository provides example scripts to query the database in Python and R.

You will need server credentials to query the database. You can request server credentials by filling out a
[Database Access Form](https://akveg.uaa.alaska.edu/request-access/). The database is public and
free to use; the purpose of the server credentials is to prevent excessive loads on the server and for us to know
how many people are connecting.

## Documentation 📚

The reference for the AKVEG Database can be accessed at [docs.akveg.org](https://docs.akveg.org/).

Our online documentation includes a detailed guide for connecting to, understanding, and exploring the AKVEG Database.

Once you have obtained the server credentials, the [Getting Started tutorial](https://docs.akveg.org/docs/database/get-started/) will guide you through connecting to the database and executing simple queries to extract data from the database.

## Update Schedule 🗓️

The AKVEG Database is updated at least once a quarter. Changes are recorded in our [CHANGELOG](CHANGELOG.md). If 
you need a static version of the data, you can export your query results to a CSV file.

## Contributing 🤝

If you've spotted an error in the database, [open a new issue](https://github.com/accs-uaa/akveg-database-public/issues). Please review existing issues before opening a new ticket to avoid duplicates. If your issue already exists, add a comment - This helps us prioritize issues that are most relevant to our users.

If you would like to contribute a dataset, consult the [Become a contributor](https://docs.akveg.org/docs/database/contribute/) section of our documentation.

## Credits

### Built With 🛠️

- PostgreSQL 17
- R 4.5.1
- Python 3.13
- Hugo 0.147.8

### Support 🫶

The U.S. Fish & Wildlife Service, Bureau of Land Management, National Park Service, U.S. Forest Service, Alaska Department of Fish & Game, and Alaska Department of Natural Resources provided funding in support of the development of the AKVEG Database.

### Usage Requirements

Citing the database is not required to use the data as all data are public. Where a citation is sensible, we would appreciate you citing the AKVEG Database as follows:

Droghini, A., T.W. Nawrocki, A.F. Wells, M.J. Macander, and L.A. Flagstad. 2025. Alaska Vegetation (AKVEG) Database: Standardized, multi-project field and classification data for Alaska. Alaska Geospatial Council, Vegetation Working Group. Available: [https://akveg.uaa.alaska.edu](https://akveg.uaa.alaska.edu). Data downloaded on [date of query].

### License ⚖️

This project is provided under the GNU General Public License v3.0. It is free to use and modify in part or in whole.

### Authors

- **Timm Nawrocki** - _Alaska Center for Conservation Science, University of Alaska Anchorage_
- **Amanda Droghini** - _Alaska Center for Conservation Science, University of Alaska Anchorage_

### Contact 📧

* **Project Maintainer**: Amanda Droghini 
* **Email**: adroghini (at) alaska (dot) edu
* **GitHub**: [@adroghini](https://github.com/adroghini)
