# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format NRCS Alaska 2024 Site & Site Visit Data
# Author: Amanda Droghini
# Last Updated: 2026-03-05
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format NRCS Alaska 2024 Site & Site Visit Data" reads in tables from the NRCS SQLite export received in
# May
# 2025,
# drops sites with incomplete data, and formats data to populate the Site and Site Visit tables according to AKVEG
# requirements. The outputs are two CSV files that can be used in an SQL INSERT statement.
# ---------------------------------------------------------------------------

# Import librairies
import sqlite3
import pandas as pd
import geopandas as gpd
import numpy as np
from pathlib import Path
from pyproj import CRS, Transformer
import shapely.ops as ops

# Set root directory
drive = Path("C:/")
root_folder = Path("ACCS_Work")

# Define folder structure
project_folder = (
    drive
    / root_folder
    / "OneDrive - University of Alaska"
    / "ACCS_Teams"
    / "Vegetation"
    / "AKVEG_Database"
)
plot_folder = project_folder / "Data" / "Data_Plots" / "34_nrcs_soils_2024"
workspace_folder = plot_folder / "working"
spatial_folder = drive / "ACCS_Work" / "Projects" / "AKVEG_Map" / "Data" / "region_data"

# Define input files
boundary_input = spatial_folder / "AlaskaYukon_100_Tiles_3338.shp"
nrcs_database = plot_folder / "source" / "Alaska_NRCS_SPSD_data_May2025.sqlite"
template_site_input = project_folder / "Data" / "Data_Entry" / "02_site.xlsx"
template_visit_input = project_folder / "Data" / "Data_Entry" / "03_site_visit.xlsx"

# Define output files
site_output = workspace_folder / "02_site_nrcssoils2024.csv"  ## Output to workspace; includes duplicates
visit_output = workspace_folder / "03_sitevisit_nrcssoils2024.csv"  ## Output to workspace; includes duplicates
personnel_output = workspace_folder / "personnel_list.csv"
lookup_output = workspace_folder / "lookup_visit.csv"

# Read in data
region_boundary = gpd.read_file(boundary_input)
template_site = pd.read_excel(template_site_input)
template_visit = pd.read_excel(template_visit_input)

# Connect to SQLite database
## Ensure connection path is a string
with sqlite3.connect(str(nrcs_database)) as nrcs_db_connection:
    cursor = nrcs_db_connection.cursor()

# Join siteobs and vegplot tables
# Exclude sites that do not have a vegplotiid (i.e., missing vegetation data)
# Exclude vegplot ID 1026303 (erroneous date)
    cursor.execute(
        """SELECT siteobs.siteiidref, 
        siteobs.obsdate, siteobs.datacollector,
        vegplot.vegplotid, vegplot.vegplotiid,
        vegplot.primarydatacollector
           FROM siteobs
                    INNER JOIN vegplot
                                    ON siteobs.siteobsiid = vegplot.siteobsiidref 
                                    WHERE vegplot.vegplotiid <> 1026303"""
    )
    rows = cursor.fetchall()
    column_names = [description[0] for description in cursor.description]

    ## Convert to pandas Dataframe
    siteobs_original = pd.DataFrame(rows, columns=column_names)

    # Query site table
    ## Drop sites with missing coordinates (n=9)
    cursor.execute(
        """SELECT siteiid, latstddecimaldegrees, longstddecimaldegrees 
            FROM site
                WHERE NOT ( (latstddecimaldegrees IS NULL) OR (longstddecimaldegrees IS NULL) )"""
    )
    rows = cursor.fetchall()
    column_names = [description[0] for description in cursor.description]
    site_original = pd.DataFrame(rows, columns=column_names)

    # Query vegetation plot data
    ## Drop sites where all recorded species have null canopy cover
    ## While it's possible that the trace amount flag was mistakenly entered as 0
    # instead of 1, the list of plants doesn't immediately strike me as only consisting of trace species.
    cursor.execute(
        """SELECT vegplotiidref, speciescancovpct, speciestraceamtflag 
            FROM plotplantinventory 
            WHERE NOT ( (speciescancovpct IS NULL) AND (speciestraceamtflag = 0) )"""
    )
    rows = cursor.fetchall()
    column_names = [description[0] for description in cursor.description]
    vegcover_original = pd.DataFrame(rows, columns=column_names)

# Query plant id table
    cursor.execute("SELECT plantiid, plantsym, plantsciname FROM plant")
    rows = cursor.fetchall()
    column_names = [description[0] for description in cursor.description]
    plantid_original = pd.DataFrame(rows, columns=column_names)

# Create lookup table
lookup_visit = siteobs_original.loc[:, ["vegplotid", "vegplotiid", "siteiidref"]]

## Drop sites that aren't in site table (i.e., missing coordinates)
lookup_visit = lookup_visit.loc[
    lookup_visit["siteiidref"].isin(site_original["siteiid"])
]

# Drop sites from lookup table with no entry in the 'plot plant inventory' table
lookup_visit = lookup_visit.loc[
    lookup_visit["vegplotiid"].isin(vegcover_original["vegplotiidref"].unique())
]

## Convert veg plot ID to integer
lookup_visit = lookup_visit.assign(vegplotiid=lookup_visit["vegplotiid"].astype(int))

## Ensure vegplotiid is unique
print(lookup_visit[lookup_visit["vegplotiid"].duplicated()].shape[0])

# --- Format Site table  ---

# Obtain vegplotiid
site = site_original.merge(
    right=lookup_visit, how="right", left_on="siteiid", right_on="siteiidref"
)

# Ensure all sites are in Alaska

## Explore coordinates
print(site.describe())  ## Minimum latitude is 0.00; obviously an error

## Set high-precision mathematical transformation for WGS84 -> NAD83
source_crs = CRS("EPSG:8999")
target_crs = CRS("EPSG:6318")
transformer = Transformer.from_crs(source_crs, target_crs, always_xy=True)

## Create geodataframe
site_spatial_precise = gpd.GeoDataFrame(
    site,
    geometry=gpd.points_from_xy(site.longstddecimaldegrees, site.latstddecimaldegrees),
    crs=source_crs)

## Shift coordinates using transformation
site_spatial_precise['geometry'] = site_spatial_precise['geometry'].map(
    lambda geom: ops.transform(transformer.transform, geom)
)

## Set the CRS using the object for better compatibility
site_spatial_precise.crs = "EPSG:6318"

## Create temporary object in EPSG:3338 for boundary check
## Prevents having to re-project multiple times, with compounding uncertainty
## Reset index (original index is not sequential)
site_spatial_temp = site_spatial_precise.to_crs("EPSG:3338").reset_index(drop=True)

## Ensure projections are the same
print(region_boundary.crs == site_spatial_temp.crs)

## Filter points that intersect with the area of interest
sites_inside = region_boundary.sindex.query(
    geometry=site_spatial_temp.geometry,
    predicate="intersects"
)[0]

## Drop problematic site
sites_filtered = site_spatial_precise.iloc[sites_inside].copy()

## Investigate points that are outside region boundary
## Single site discovered above (with latitude = 0)
sites_outside = site_spatial_precise.drop(sites_filtered.index)
print(sites_outside)

# Round high-precision coordinates to six decimal points
sites_filtered["longitude_dd"] = round(sites_filtered.geometry.x, 6)
sites_filtered["latitude_dd"] = round(sites_filtered.geometry.y, 6)

# Populate remaining columns
sites_filtered = sites_filtered.assign(
    establishing_project_code="nrcs_soils_2024",
    perspective="ground",
    cover_method="semi-quantitative visual estimate",
    h_datum="NAD83",
    positional_accuracy="consumer grade GPS",
    plot_dimensions_m="11.6 radius",
    h_error_m=-999,
    location_type="targeted",
    site_code=("nrcs_" + sites_filtered["vegplotiid"].astype("string")),
)

# Overwrite lookup table to drop excluded sites
## Keep vegplotid for compatibility with previous version of the dataset that was processed for AKVEG
lookup_visit = sites_filtered.loc[:, ["vegplotid", "vegplotiid", "site_code"]]

# Clean workspace
del (
    sites_outside,
    sites_inside,
    site_spatial_temp,
    site_spatial_precise,
    rows,
    site_original,
    region_boundary,
)

# --- Format Site Visit table ---

# Drop sites that aren't in Site table
visit = siteobs_original.merge(right=lookup_visit, how="right", on="vegplotiid")

# Format date and site visit code
print(visit.obsdate.isna().sum())
print(visit.obsdate.describe())

visit = (
    visit.assign(
        utc_time=pd.to_datetime(visit["obsdate"], unit="s", utc=True)
    )  # Convert UNIX time to datetime;
    # assume times are in UTC
    .assign(
        local_time=lambda df: df["utc_time"].dt.tz_convert("America/Anchorage")
    )  # Convert to local time
    .assign(
        observe_date=lambda df: df["local_time"]
        .dt.strftime("%Y-%m-%d")
        .astype("string")  # Keep date only; convert to string
    )
    .assign(
        observe_date_string=lambda df: df["observe_date"].str.replace(
            pat="-", repl="", regex=False
        )  # Create date string for site visit code
    )
    .assign(
        site_visit_code=lambda df: df["site_code"].str.cat(
            others=df["observe_date_string"], sep="_"
        )  # Create site visit code
    )
)

# Ensure site visit codes are unique
print(visit[visit.site_visit_code.duplicated()].shape[0])

# Drop sites with questionable dates
print(visit["local_time"].describe())

errors_winter = visit.assign(month=visit["local_time"].dt.month)
errors_winter = errors_winter.loc[
    (errors_winter.month > 10) | (errors_winter.month < 5)
]
errors_winter = pd.Series(errors_winter["site_visit_code"].unique())

visit = visit.loc[~visit["site_visit_code"].isin(errors_winter)].reset_index()

# Keep only relevant columns
visit = visit.loc[
    :,
    [
        "site_visit_code",
        "site_code",
        "observe_date",
        "datacollector",
        "primarydatacollector",
    ],
]

# Append site visit code to lookup table
lookup_visit = lookup_visit.merge(
    right=visit, how="right", on="site_code"
)  # Use right join to drop sites w/
# incorrect dates
lookup_visit = lookup_visit.loc[:, ["vegplotid", "vegplotiid", "site_code", "site_visit_code"]]

# Format personnel names

# Convert names to all caps
visit = visit.assign(
    datacollector=visit.datacollector.str.upper().astype("string"),
    primarydatacollector=visit.primarydatacollector.str.upper().astype("string"),
)

# Remove periods and question marks
visit = visit.assign(
    datacollector=visit.datacollector.str.replace(pat=".", repl="", regex=False),
    primarydatacollector=visit.primarydatacollector.str.replace(
        pat=".", repl="", regex=False
    ),
)

# Replace 'and' with '&' to facilitate string extraction
visit = visit.replace(to_replace=r"(\sAND\s)", value=" & ", regex=True)

## Standardize capitalization
visit = visit.assign(
    datacollector=visit.datacollector.str.title().astype("string"),
    primarydatacollector=visit.primarydatacollector.str.title().astype("string"),
)

# Replace null values with unknown
visit = visit.replace(["Unknown", "0", "4", "5", "6", "8", "10", "13"], np.nan)
visit = visit.fillna(value="unknown")

# Specify regex patterns
regex_pattern = r"^([^/&,;]*)" r"(?:\s*(?:/|&|,|;)\s*(.*))?$"

# Extract names from data collector columns
primary_collectors = visit["primarydatacollector"].str.extract(regex_pattern)
other_collectors = visit["datacollector"].str.extract(regex_pattern)

# Combine into single dataframe
combined_collectors = (
    pd.DataFrame(np.hstack([primary_collectors, other_collectors]))
    .rename(
        {0: "veg_observer", 1: "veg_recorder", 2: "env_observer", 3: "soils_observer"},
        axis=1,
    )
    .fillna(value="unknown")  # str.extract generates NA in populated columns
).apply(
    lambda x: x.str.strip()
)  # Strip whitespaces

# Replace unknowns with alternate names if available
combined_collectors = combined_collectors.assign(
    veg_recorder=np.where(
        (combined_collectors.veg_recorder == "unknown")
        & (combined_collectors.soils_observer != "unknown"),
        combined_collectors.soils_observer,
        "unknown",
    )
)

# Correct remaining names

## Define regex matches
personnel_regex_dict = {
    r"^(Ab[a-z]+)\s(Clapp)(.*)": "Abigail Clapp",
    r"^Ac\b(.*)": "Abigail Clapp",
    r"^B([a-z]*)\sCasar": "Brad Casar",
    r"^Bc([a-z]*)?": "Brad Casar",
    "C Chicvara-Roland": "Conor Roland-Chicvara",
    r"^C(onor)?\sR(o[a-z]*)?(\s|-)Chi([a-z]{1})vara(.*)": "Conor Roland-Chicvara",
    r"^Cr(.*)": "Conor Roland-Chicvara",
    r"^E(ric)?\sG([ei]{2})s(t?)ler": "Eric Geisler",
    r"^J(osh[a-z]*)?\sPaul": "Joshua Paul",
    r"^Krista.*": "Krista Bryan",
    r"^Kb(.*)": "Krista Bryan",
    r"^Pb(arber)?": "Phil Barber",
    r"^P([a-z]*)\sBa(r*)ber(.*)": "Phil Barber",
    r"^Pr(.*)": "Phil Roberts",
    r"^Np(arry)?": "Nathan Parry",
    r"^N\sParry(.*)": "Nathan Parry",
    r"^Trav.*": "Travis Nauman",
    r"^S([a-z]*)\sDatson(.*)": "Sara Datson",
    r"^N([a-z]*)\sRoe(.*)": "Nathan Roe",
    r"^Mk(.*)": "Monica Kopp",
    r"^Matt\sD([a-z]+)fy": "Matt Duffy",
    r"^Lh(.*)": "Larissa Hindman",
    r"^Kar([a-z]{1})n\sNoy([es]{2})": "Karen Noyes",
    r"^A([a-z]{0,2})\sL([a-z]{1,2})": "Amy Li",
    r"^Jamin\sJohans[eo]{1}n(.*)": "Jamin Johanson",
    r"^Jj(.*)": "Jamin Johanson",
    r"^Ao(.*)": "Andy Oxford",
    r"^Cc(\?{0,1})": "Charlotte Crowder",
    r"^C(harlotte)?\sCr([ow]{2})der(.*)": "Charlotte Crowder",
    r"^Cha[dp]{1}\sOur?kl?rop": "Chad Oukrop",
    r"^M\s?[gG]r?acz": "Mike Gracz",
    r"^Madel(e?)ine\sTucker(.*)": "Madeleine Tucker",
    r"^Mckee, Beard(.*)": "Taylor Beard",
    r"^M(ichael)?\sSinger(.*)": "Michael Singer",
    r"^Mi([a-z]*)\sSousa": "Michael Sousa",
    r"^Z\sAs[a-z]$": "unknown",
}

## Define non-regex matches
personnel_dict = {
    "Andrew Mcnown": "Andrew McNown",
    "Annetts": "Tyler Annetts",
    "A Oxford": "Andy Oxford",
    "A Williams": "unknown",
    "A Williams, D Mulligan": "Dennis Mulligan",
    "As": "Aliza Segal",
    "Bb": "Bonnie Bernard",
    "Brad": "Brad Casar",
    "B Spellman": "Blaine Spellman",
    "Bspellman": "Blaine Spellman",
    "Bh": "Brian Houseman",
    "Blane": "Blaine Spellman",
    "Bryan": "Bryan Strong",
    "Brian Strong": "Bryan Strong",
    "Bstrong": "Bryan Strong",
    "Britney P": "unknown",
    "Casar": "Brad Casar",
    "Cf": "Conrad Field",
    "Co": "Chad Oukrop",
    "C Julius": "Chyenna Julius",
    "Clapp; Annette": "Abigail Clapp",
    "Cj": "Chyenna Julius",
    "Cs": "Casey Schroeder",
    "D Mulligan": "Dennis Mulligan",
    "Dm": "Dennis Mulligan",
    "D Stich": "Daniel Stich",
    "Eh": "Ezra Hoffman",
    "Eg": "Eric Geisler",
    "Ezra Huffman": "Ezra Hoffman",
    "Elizabeth": "unknown",
    "Ep": "Elizabeth Powers",
    "Geisler": "Eric Geisler",
    "Garrett": "unknown",
    "Glass": "Dallas Glass",
    "Gm": "Greg Mazer",
    "Gvb": "Gabriel Benitez",
    "Gb, Sd": "Gabriel Benitez",
    "Hindman": "Larissa Hindman",
    "Hoffman": "Ezra Hoffman",
    "J Ferrara": "Jack Ferrara",
    "Jenifer Robinette": "Jennifer Robinette",
    "Jelinski": "Nic Jelinski",
    "Jm": "Jeff Mason",
    "J Oatley": "Jeff Oatley",
    "Julius": "Chyenna Julius",
    "L Hindman": "Larissa Hindman",
    "Liebermann": "Robert Liebermann",
    "Ll": "Lily Lewis",
    "Marc Much": "unknown",
    "Mg": "Mike Gracz",
    "Mjs, Nah, Gvb": "Gabriel Benitez",
    "Monca Kopp": "Monica Kopp",
    "Mm": "Mike Mungoven",
    "Mulligan": "Dennis Mulligan",
    "N Jelinski": "Nic Jelinski",
    "Nj": "Nic Jelinski",
    "N Roth": "Nathan Roth",
    "Nathan Ro": "Nathan Roe",
    "Pete": "Pete Goodwin",
    "Pg": "Pete Goodwin",
    "S Castillo": "Sunny Castillo",
    "Sc, Ac, Nr, Jf": "Sunny Castillo",
    "Schmit": "Stephanie Schmit",
    "Sd Eh": "Ezra Hoffman",
    "Sd Ka": "Kade Anderson",
    "Sdb, Sl": "Sydney Lance",
    "Sl": "Sydney Lance",
    "Shoemaker": "Stephanie Shoemaker",
    "Steph Shoemaker": "Stephanie Shoemaker",
    "Spellman": "Blaine Spellman",
    "Strong": "Bryan Strong",
    "Sousa": "Michael Sousa",
    "S Schmit": "Stephanie Schmit",
    "Stoy": "Damian Stoy",
    "Sydney Lance, Scott Debruyne": "Sydney Lance",
    "Ta": "Tyler Annetts",
    "Talise (Stacy) Dow": "Stacy Dow",
    "Tb": "Taylor Beard",
    "Td": "Stacy Dow",
    "Tim Reibe": "Tim Riebe",
    "Tr": "Tim Riebe",
    "Tyler Annettes": "Tyler Annetts",
    "Mazer": "Greg Mazer",
    "Z Ash, L Hindman, S Datson": "Larissa Hindman",
    "Z Ash, S Datson, L Hindman": "Sara Datson",
}

# Define unknown/ambiguous initials
initials_dict = {
    r"^[A-Z][a-z]{0,3}$": "unknown",
    r"^[A-Z][a-z]{0,3}(,\s[A-Z][a-z]{0,3}){1,4}": "unknown",
    r"^^[A-Z][a-z]{1,2}\s[A-Z][a-z]{1}$$": "unknown",
}

# Replace values
combined_collectors = combined_collectors.replace(
    to_replace=personnel_regex_dict, regex=True
)
combined_collectors = combined_collectors.replace(
    to_replace=personnel_dict, regex=False
)
combined_collectors = combined_collectors.replace(to_replace=initials_dict, regex=True)

# Assign names to new columns
visit = visit.assign(
    veg_observer=combined_collectors["veg_observer"],
    veg_recorder=combined_collectors["veg_recorder"],
    env_observer=combined_collectors["env_observer"],
    soils_observer="unknown",
)

print(visit.isna().sum())

# Replace env_observer with veg_recorder if env_observer is unknown
visit = visit.assign(
    env_observer=np.where(
        visit["env_observer"] == "unknown", visit["veg_recorder"], visit["env_observer"]
    )
)

# Obtain list of unique personnel names to update data dictionary
personnel_list = pd.concat(
    [
        visit["veg_observer"],
        visit["veg_recorder"],
        visit["env_observer"],
    ]
)
personnel_list = personnel_list.unique()
personnel_list = pd.DataFrame(personnel_list).sort_values(by=0)

# Populate remaining columns
visit_final = visit.assign(
    project_code="nrcs_soils_2024",
    data_tier="map development & verification",
    structural_class="not available",
    scope_vascular="exhaustive",
    scope_bryophyte="common species",
    scope_lichen="common species",
    homogeneous="TRUE",
)

# Drop remaining sites from Site table
site_final = sites_filtered.loc[
    sites_filtered["site_code"].isin(lookup_visit["site_code"])
]

# Reorder columns to match data entry template
visit_final = visit_final[template_visit.columns]
site_final = site_final[template_site.columns]

# Export dataframes to CSV
site_final.to_csv(site_output, index=False, encoding="UTF-8")
visit_final.to_csv(visit_output, index=False, encoding="UTF-8")
personnel_list.to_csv(personnel_output, index=False, encoding="UTF-8")
lookup_visit.to_csv(lookup_output, index=False, encoding="UTF-8")
