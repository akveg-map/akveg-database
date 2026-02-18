# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site table for  Yukon Biophysical Inventory System plot data
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-02-18
# Usage: Must be executed in a Python 3.13+ distribution.
# Description: "Format Site table for Yukon Biophysical Inventory System plot data" extracts relevant
# information from an ESRI shapefile, re-projects to NAD83, drops sites with missing data, replaces values with the
# correct constrained values, and performs QC checks. The
# output is a CSV file that can be used to write a SQL INSERT
# statement for ingestion into the AKVEG database.
# ---------------------------------------------------------------------------

# Import packages
import geopandas as gpd
import pandas as pd
import polars as pl
from pathlib import Path

# Define folder structure
drive = Path('C:/')
root_folder = drive / 'ACCS_Work'

project_folder = root_folder / 'OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database' / 'Data'
plot_folder = project_folder / 'Data_Plots' / '52_yukon_biophysical_2020'
source_folder = plot_folder / 'source' / 'ECLDataForAlaska_20240919' / 'YBIS_Data'

# Define inputs
plot_input = source_folder / 'YBISPlotLocations.shp'
veg_input = source_folder / 'Veg_2024Apr09.xlsx'
template_input = project_folder / 'Data_Entry' / '02_site.xlsx'

# Define output
site_output = plot_folder / '02_site_yukonbiophysical2020.csv'

# Read in data
site_original = gpd.read_file(plot_input)
veg_original = pl.read_excel(veg_input, columns=["Project ID", "Plot ID", "Veg cover pct", "Access"])
template = pl.read_excel(template_input)

# Drop sites with no geometry (n=3015)
## These are also blank in the 'Plot' spreadsheet
site_project = site_original[site_original.geometry.notna()]

# Re-project plot data to NAD83
output_crs = 'EPSG:4269'
site_project = site_project.to_crs(output_crs)
print(site_project.crs)

# Add XY coordinates
site_project['longitude_dd'] = site_project.geometry.x
site_project['latitude_dd'] = site_project.geometry.y

# Explore coordinates
## Not particularly useful to intersect with map boundary since ~50% of sites are outside of it. Perform a visual
# check instead.
site_project[["longitude_dd", "latitude_dd"]].describe()  ## Values are reasonable

# Convert to polars dataframe
site = pd.DataFrame(site_project).drop(columns=['geometry'])
site = pl.from_pandas(site)

## Ensure Plot IDs are unique as this column will be used for
# subsequent filtering
print(site["Plot_ID"].n_unique() == site.height)

# Drop sites that are not for public access (n=3102)
## Communication with data manager on 2025-09-25: Project IDs 206 and 208 can be made public
public_sites = veg_original.filter((pl.col("Access") == 'Available to all users.') |
                            (pl.col("Project ID").is_in([206, 208])))
site = site.join(public_sites, left_on='Plot_ID', right_on='Plot ID', how='semi')

# Drop site for which all percent cover are zero (n=1)
## Notes indicate this is because % cover was not recorded
no_cover = (public_sites.group_by('Plot ID')
            .agg(pl.col("Veg cover pct").sum().alias("total_cover"))
            .filter(pl.col('total_cover') == 0)
            .select('Plot ID'))
site = site.join(no_cover, left_on='Plot_ID', right_on='Plot ID', how='anti')

# Drop sites with incomplete data
## Plots seem to be missing vegetation data (or additional entries for non-vegetated classes). Sum of abiotic cover
# percent is far less
# than 100% and notes for 10425 indicate the plot should have vegetation data associated with it.
site = site.filter(~pl.col("Plot_ID").is_in([10425, 10428, 10394, 10411, 10210])
                              )
## Construct LazyFrame
lazy_site = site.lazy()

## Specify chain of operations
site_chain = (
    lazy_site
    # Retain only relevant columns
    .select(['Project_ID', 'Plot_ID',
             'Survey_dat',
             'Project_ty', 'Plot_type_',
             'latitude_dd', 'longitude_dd',
             'Coord_prec', 'Coord_sour'])
    # Create site code by combining project + plot IDs
    .with_columns(
    (pl.col("Project_ID").cast(pl.Utf8) +
    pl.lit("_") +
    pl.col("Plot_ID").cast(pl.Utf8))
    .alias("site_code")
    )
    # Replace empty/unknown values to 'unknown' string; prevents nulls from being inadvertently dropped during filtering
    .with_columns(
    pl.col(pl.Utf8)
    .replace(old=[' ', 'UNK', None], new='unknown')
    )
    # Combine 'coord source' and 'coord precision' into a single column for easier filtering
    .with_columns(
        (pl.col("Coord_sour").cast(pl.Utf8) +
         pl.lit("_") +
         pl.col("Coord_prec").cast(pl.Utf8)
        ).alias("coord_unknown")
    )
    # Add 'date' and 'month' columns
    .with_columns(pl.col("Survey_dat").str.to_date("%Y %b %d").alias('observe_date'))
    .with_columns(pl.col('observe_date').dt.month().alias('observe_month'))
    # Apply filtering conditions
    .filter(
        # Drop sites without survey dates (n=1)
        (pl.col('Survey_dat') != 'unknown')
        & # Drop sites with only plot + soil data (n=6)
        (pl.col('Plot_type_') != 'Plot and soil information only')
        & # Drop coarse minimum mapping unit (n=2678)
        (~pl.col('Coord_prec').is_in(['MMU50K', 'MMU250K']))
        & # Drop sites where both coordinate source and precision are unknown (n=1500)
        (pl.col('coord_unknown') != 'unknown_unknown')
        & # Drop sites with winter survey months (n=2)
        ((pl.col('observe_month') >= 4) & (pl.col('observe_month') <= 10))
    )
)

site_filtered = site_chain.collect()

# Ensure there are no null values remaining
with pl.Config(tbl_cols=-1):
    print(site_filtered.null_count())

# Format horizontal error
site_filtered = site_filtered.with_columns(pl.when(pl.col('Coord_prec') == '>100m')
                                           .then(pl.lit("200"))
                                           .when(pl.col('Coord_prec') == 'unknown')
                                           .then(pl.lit("-999"))
                                           .otherwise(pl.col('Coord_prec').str.replace(r"m$", "", literal=False))
                                           .alias('h_error_m'))
site_filtered = site_filtered.with_columns(pl.col('h_error_m').str.strip_chars().cast(pl.Int16))  ## Convert to integer

print(site_filtered['h_error_m'].value_counts())

# Format plot dimensions
dimensions_map = {
    '20 m diameter': '10 radius',
    '10 m diameter': '5 radius',
    '1x1 m': '1×1',
    '10x10 m': '10×10',
    '10x5 m': '5×10',
    '20x20 m': '20×20',
    'approximately 100x100 m observed from an aircraft (size may vary)': '100×100',
    'Non-standard plot of irregular shape (e.g., trough in polygonal landscape)': 'unknown',
    'Unable to determine plot type for older data': 'unknown',
    'Trees: 10x10m; Shrubs: 5x5m; Herbs: 1x1m': '10×10',
    'Trees: 20x20m; Shrubs: 5x5m; Herbs: 1x1m': '20×20'
}

## Replace values to match constrained values in AKVEG Database
site_filtered = site_filtered.with_columns(pl.col('Plot_type_').str.replace_many(dimensions_map)
                         .alias('plot_dimensions_m'))

# Format positional accuracy
## Replace values to match constrained values in AKVEG Database
site_filtered = site_filtered.with_columns(pl.col('Coord_sour').str.replace(r"^[A-Z]GPS$", "consumer grade GPS")
                                           .str.replace("ORTHOPHOTO1.0", "image interpretation",
                                                                            literal=True)
                                           .str.replace(r"^DIGITIZED.*$", "map interpretation")
                                           .str.replace(r"^MAP.*$", "map interpretation")
                                           .alias("positional_accuracy"))

print(site_filtered['positional_accuracy'].value_counts())

## Correct 2 sites with unknown positional accuracy and relatively low positional error
site_filtered = site_filtered.with_columns(pl.when((pl.col('positional_accuracy') == 'unknown')
                                                   & (pl.col('h_error_m') <= 10))
                         .then(pl.lit('consumer grade GPS'))
                         .otherwise(pl.col('positional_accuracy'))
                         .alias('positional_accuracy'))

## Drop remaining sites with unknown positional accuracy and high positional error (n=7): cannot be used for map
# development + positional accuracy cannot be unknown
site_filtered = site_filtered.filter(pl.col('positional_accuracy') != 'unknown')

# Format perspective
site_filtered = site_filtered.with_columns(pl.when(pl.col('Plot_type_').str.contains('aircraft'))
                         .then(pl.lit('aerial'))
                         .otherwise(pl.lit('ground'))
                         .alias('perspective'))

## Examine ground sites associated with aerial projects (project type=AYBI)
ground_sites = site_filtered.filter((pl.col('Project_ty') == 'AYBI')
                                    & (pl.col('perspective') == 'ground')) ## Notes indicate that these were ground
# sites opportunistically surveyed during aerial work; nothing to change

# Populate remaining columns and match template formatting
site_final = (site_filtered.with_columns(pl.lit('yukon_biophysical_2020').alias('establishing_project_code'),
                                         pl.lit('semi-quantitative visual estimate').alias('cover_method'),
                                         pl.lit('NAD83').alias('h_datum'),
                                         pl.lit('targeted').alias('location_type'))
              .select(template.columns))

# Export to CSV
site_final.write_csv(site_output)
