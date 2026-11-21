# -*- coding: utf-8 -*-
"""Process Environment Table for BLM AIM 2022–2025 data

Combines data from the BLM Riparian AIM GeoDatabase and from individual CSVs of "supplemental indicators" provided
by BLM Alaska. Appends unique site identifiers, re-classifies categorical values, converts missing values to
designated missing value codes, and performs quality control checks before exporting to CSV for ingestion into the
AKVEG Database.

Author: Amanda Droghini, Alaska Center for Conservation
Last Updated: 2026-11-21
Usage: Python 3.13+
"""

# -------- Load Packages -----------------------------------------------
from collections import defaultdict
from functools import reduce

import geopandas as gpd
import polars as pl
import polars.selectors as cs

from user_tools.utils_init import load_system_paths
from utils.utils import get_template

# -------- Set Up Environment ------------------------------------------
paths = load_system_paths()

# Define constants
FOLDER_ID = "44_aim_various_2025"
INDICATORS_RENAME_MAP = {"Overall Site Moisture Regime": "moisture_regime",
                         "Depth of Water (cm)": "depth_water_cm",
                         "Moss/Duff Thickness (cm)": "depth_moss_duff_cm",
                         "Depth Soil to ActiveLayer (cm)": "depth_restrictive_layer_cm",
                         "parentglobalid": "GlobalID"
                         }
SEVERITY_MAPPING = {0: None,
                    1: "low",
                    2: "moderate",
                    3: "high",
                    4: "high"
                    }


# Define basic cleaning function
def clean_data_table(
        original_df: pl.DataFrame,
        site_visit_table: pl.DataFrame,
        unique_id: str = "EvaluationID") -> pl.DataFrame:
    """
    Clean strings, format site visit codes, and join with site visit table.

    Replaces whitespace-only strings with nulls, converts string columns to lowercase (excluding the unique
    identifier), formats the unique visit identifier as sitecode_yyyymmdd, and joins with
    the processed Site Visit table to retain only valid site visits.

    :param original_df: Original Polars DataFrame.
    :param site_visit_table: Processed Site Visit table with valid site visit IDs.
    :param unique_id: Name of the unique visit identifier column.
    :return: Cleaned Polars DataFrame with only valid site visit codes.
    """
    cleaned_df = (original_df
                  .with_columns(cs.string().str.strip_chars().replace("", None))
                  .with_columns(cs.string().exclude(unique_id).str.to_lowercase())
                  # Create site visit code from EvaluationID
                  .with_columns(pl.col(unique_id).str.split_exact("_", 1)
                                .struct.rename_fields(["site_code", "date_string"])
                                .alias("fields")
                                )
                  .unnest("fields")
                  .with_columns(pl.col("date_string").str.replace_all(pattern="-", value="").alias("date_string"))
                  .with_columns((pl.col("site_code") + "_" + pl.col("date_string")).alias("site_visit_code"))
                  .drop(["site_code", "date_string"])
                  )
    # Join with Site Visit Table to retain only valid plots
    cleaned_df = cleaned_df.join(site_visit_table, on="site_visit_code", how="semi")
    return cleaned_df


# Define inputs
plot_folder = paths.cloud_assets.plots / FOLDER_ID
gdb_input = plot_folder / "source" / "BLM_Natl_AIM_RiparianWetland_Export_20260422.gdb"
indicators_input = plot_folder / "source" / "AK_Moss_and_Active_Layer_23Jan2026.xlsx"
visit_input = plot_folder / '03_sitevisit_aimvarious2025.csv'
# Define crosswalk inputs
moisture_input = paths.repository / "02_data_format" / "crosswalks" / "44_aim_various_2025_moisture_regime.csv"
disturbance_input = paths.repository / "02_data_format" / "crosswalks" / "44_aim_various_2025_disturbance.csv"

# Define output
envr_output = plot_folder / '12_environment_aimvarious2025.csv'

# -------- Load CSV Files -----------------------------------------
visit_original = pl.read_csv(visit_input, columns=["site_code", "site_visit_code"])
template = get_template("environment")
moisture_crosswalk = pl.read_csv(moisture_input)
disturbance_crosswalk = pl.read_csv(disturbance_input)

# -------- Load Shapefiles ---------------------------------------------

# Define nested dictionary (key: layer name, values: column names) for shapefiles in GeoDatabase
# Separate source data tables by theme and by relational type e.g., DisturbancesDetail has >1 entry for each
# EvaluationID; combining it with a one-to-one table like PlotCharacterization makes it harder to handle duplicates
gdb_dict = {
    # Site & hdrology data
    "site_hydrology": {
        "AIM_Wetland__F_PlotCharacterization": ['EvaluationID', 'Elevation_m', 'Slope', 'AlaskaEcotypeClassification',
                                                'LandscapeType', 'LandscapeTypeSecondary', 'VerticalSlopeShape',
                                                'PlotDescription'],

        "AIM_Wetland__F_Hydrology": ['EvaluationID', 'PermafrostInfluence', 'DepthActiveLayer', 'SurfaceWaterPresent',
                                     'SurfaceWaterDepth']
    },
    # Soil horizons
    "soil_horizons": {
        "AIM_Wetland__F_Soils": ['EvaluationID', 'ImpenetrableDescrip']
    },
    # Disturbance data
    "disturbance": {
        "AIM_Wetland__F_NaturalandHumanDisturbances": ['EvaluationID', 'DisturbancesObserved'],
        "AIM_Wetland__F_DisturbancesDetail": ['EvaluationID', 'Disturbance', 'OtherDisturbance',
                                              'MonitoringPlotScope', 'MonitoringPlotDegree', 'DisturbanceComment']
    }
}

# Use dictionary comprehension to iteratively load shapefiles as DataFrames
environment_layers = {
    group: {
        layer_name: pl.from_pandas(gpd.read_file(gdb_input, layer=layer_name, columns=cols, ignore_geometry=True))
        for layer_name, cols in layers.items()
    }
    for group, layers in gdb_dict.items()
}

# Lightly clean tables & sequentially join DataFrames in each dict group (using reduce)
# Ensure appropriate order (metadata first, data second) for left join to return expected results
environment_cleaned = {
    group: clean_data_table(reduce(lambda left, right: left.join(right, on="EvaluationID", how="left"),
                                   layers.values()), site_visit_table=visit_original)
    for group, layers in environment_layers.items()
}

# Unpack dictionary into three DataFrames
hydrology_original, horizons_original, disturbance_original = environment_cleaned.values()

del gdb_dict, environment_layers, environment_cleaned

# -------- Load Excel Sheets -------------------------------------------
excel_dict = {"MossActiveLayer 2021": {"cols": ["Office", "Plot ID", "Plot Key", "Overall Site Moisture Regime"],
                                       "year_end": "2021"},
              "MossActiveLayer_Details 2021": {"cols": ["Plot Key",
                                                        "Moss/Duff Thickness (cm)", "Depth of Water (cm)",
                                                        "Depth Soil to ActiveLayer (cm)", "Notes"],
                                               "year_end": "2021"},
              "MossActiveLayer 2022-25": {"cols": ["Plot ID", "Evaluation ID", "GlobalID"],
                                          "year_end": "2025"},
              "MossActiveLayer_Details 2023-25": {"cols": ["parentglobalid", "Moss/Duff Thickness (cm)",
                                                           "Depth of Water (cm)", "Depth Soil to ActiveLayer (cm)",
                                                           "Notes"],
                                                  "year_end": "2025"}
              }

# Read Excel sheets
excel_sheets = pl.read_excel(source=indicators_input, sheet_name=list(excel_dict.keys()))

# Select & rename columns, group sheets by year
subsets_by_year = defaultdict(list)
for sheet, attribute in excel_dict.items():
    year = attribute["year_end"]
    df = excel_sheets[sheet].select(attribute["cols"]).rename(INDICATORS_RENAME_MAP, strict=False)
    # Drop rows without a Plot Key (2 site visits) in 2021 data
    if year == "2021":
        df = df.remove(pl.col("Plot Key") == "<Null>")
    # Combine multiple moisture regime entries into a single row per site visit (moisture regime was taken at each
    # line in 2021)
    if sheet == "MossActiveLayer 2021":
        df = (df.group_by(pl.col("Plot Key"))
              .agg(pl.col("moisture_regime").drop_nulls().unique().str.join(delimiter=", ")))
    # Drop site visits with same Evaluation ID (but different Global ID); measurements cannot be reconciled to unique ID
    if sheet == "MossActiveLayer 2022-25":
        df = df.unique(subset=pl.col("Evaluation ID"), keep="none")
    subsets_by_year[year].append(df)

# Join dataframes of the same year
year_join_keys = {"2021": "Plot Key",
                  "2025": "GlobalID"}

# Use left join to drop measurements associated with duplicate Evaluation ID
indicators_merged = [
    reduce(lambda left, right: left.join(right, on=year_join_keys[year], how="left"),
           df_list)
    for year, df_list in subsets_by_year.items()
]

# Concatenate joined tables using "diagonal_relaxed" to combine common columns and coerce mismatched types
indicators_original = (pl.concat(indicators_merged, how="diagonal_relaxed")
                       # Replace string literal <Null> with null
                       .with_columns(cs.string().replace(old="<Null>", new=None))
                       # Cast numeric columns to appropriate data type
                       .with_columns(pl.col("depth_water_cm").cast(pl.Float64)
                                     .alias("depth_water_cm"))
                       )

del excel_dict, excel_sheets, subsets_by_year, year_join_keys, indicators_merged

# -------- Classify Disturbance ------------------------------------

# The DisturbanceDetails table is many-to-one: It can store >1 entry per site visit. It also evaluates disturbances
# at both the plot scale and the broader, landscape scale. In contrast, the AKVEG Database stores only one
# disturbance per site visit: the *primary* disturbance in the plot. We process the original disturbance data by
# considering only plot-level disturbances, calculating the total severity (scope + degree), and choosing the
# highest-ranked disturbance at a plot.

# Examine Scope values; ensure 5_Present is absent (re-classification relies on a true ordinal scale from low to high)
print(disturbance_original.select("MonitoringPlotScope").unique())

disturbance = (disturbance_original
               # Extract numeric part of the severity scale and cast as Integer
               .with_columns(pl.col("MonitoringPlotScope", "MonitoringPlotDegree")
                             .str.extract(r"(^\d)")
                             .cast(pl.Int64)
                             )
               # Calculate total disturbance score (scope + degree); assign None if both scope and degree are null
               .with_columns(pl.when(pl.all_horizontal(pl.col("MonitoringPlotScope",
                                                              "MonitoringPlotDegree").is_null()))
                             .then(None)
                             .otherwise(pl.sum_horizontal("MonitoringPlotScope", "MonitoringPlotDegree"))
                             .alias("total_severity")
                             )
               # Keep the entry associated with the largest total severity (highest score)
               .sort(by=["site_visit_code", "total_severity"], descending=[False, True], nulls_last=True)
               .unique(subset=["site_visit_code"], keep="first")
               )

# Classify disturbance severity and create time since disturbance column (not recorded, fill with missing value code)
disturbance = disturbance.with_columns(pl.col("MonitoringPlotDegree").replace_strict(SEVERITY_MAPPING)
                             .alias("disturbance_severity"),
                             pl.lit("-999").cast(pl.Int16).alias("disturbance_time_y"))

# Classify disturbance type Combine Disturbance and OtherDisturbance values into a single column
disturbance = (disturbance.with_columns(pl.col("Disturbance").replace(old="other", new=None)
                                        .alias("Disturbance"))
               .with_columns(pl.coalesce("Disturbance", "OtherDisturbance").str.strip_suffix(".")
                             .alias("original_disturbance"))
               .join(disturbance_crosswalk, how="left", on="original_disturbance")
               # Manually resolve ambiguous values
               .with_columns(pl.when(pl.col("DisturbanceComment").str.contains("historical winter trail"))
                             .then(pl.lit("historic anthropogenic"))
                             .when((pl.col("Disturbance") == "recreation") &
                                   (pl.col("DisturbanceComment").str.contains("apparent winter trail|hiking trail")))
                             .then(pl.lit("trail"))
                             .when((pl.col("Disturbance") == "recreation") &
                                   (pl.col("DisturbanceComment").str.contains("atv trail")))
                             .then(pl.lit("ATV use"))
                             .when(pl.col("original_disturbance") == "snow/ice road/pad disturbance")
                             .then(pl.lit("ATV use"))  # Based on DisturbanceComment
                             .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                   (pl.col("DisturbanceComment").str.contains("trail")))
                             .then(pl.lit("wildlife trails"))
                             .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                   (pl.col("DisturbanceComment").str.contains("burrow|digging")))
                             .then(pl.lit("wildlife digging"))
                             .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                   (pl.col("DisturbanceComment").str.contains(r"caribou|forage")))
                             .then(pl.lit("wildlife foraging"))
                             .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                   (pl.col("DisturbanceComment").str.contains(
                                       r"trample|moose tracks and disturbed soil")))
                             .then(pl.lit("wildlife trampling"))
                             .when((pl.col("original_disturbance") == "soil disturbance animals") &
                                   (pl.col("total_severity") <= 2))  # Comments only mention tracks
                             .then(pl.lit("none"))
                             .otherwise(pl.col("disturbance"))
                             .alias("disturbance")
                             )
               # Assign "none" when no disturbance was observed
               .with_columns(pl.when((pl.col("DisturbancesObserved") == "no") | (pl.col("total_severity") == 0))
                             .then(pl.lit("none"))
                             .otherwise(pl.col("disturbance"))
                             .alias("disturbance")
                             )
               )

# Create cryoturbation column using OtherDisturbance
# Use disturbance_original to evaluate all entries, then join to processed (1:1) disturbance table
cryoturbation = (disturbance_original.with_columns(pl.when(pl.col("OtherDisturbance").str.contains("cryoturbation"))
                                   .then(pl.lit("TRUE"))
                                   .alias("cryoturbation"))
                 .filter(pl.col("cryoturbation") == "TRUE")
                 .select(["site_visit_code", "cryoturbation"])
                 )

disturbance = disturbance.join(cryoturbation, how="left", on="site_visit_code")

# Ensure there are no null values
print(disturbance.select("disturbance").null_count())

# -------- Classify Landforms & Hydrology ------------------------------

print(hydrology_original.select("LandscapeType").unique())
print(hydrology_original.select("AlaskaEcotypeClassification").unique())

# Classify geomorphology
hydrology = (hydrology_original
             .with_columns(pl.when(pl.col("PlotDescription").str.contains("coastal plain", literal=True))
                                .then(pl.lit("coastal plain"))
                                .when((pl.col("Elevation_m") <= 300) & (pl.col("LandscapeType") == 'hill mountain'))
                                .then(pl.lit("hill"))
                                .when(pl.col("LandscapeType") == 'floodplain basin')
                                .then(pl.lit("floodplain"))
                                .when((pl.col("LandscapeType") == 'flat plain') & (pl.col("Slope") <= 8))
                                .then(pl.lit("plain"))
                                .otherwise(None)
                                .alias("geomorphology")
                                )
             )

# Classify physiography
# Likely misattributes subalpine plots to upland because ecotype does not differentiate between the two
hydrology = (hydrology.with_columns(pl.col("AlaskaEcotypeClassification")
                                   .str.replace("riverine", "riparian", literal=True)
                                   .str.extract(r"(^[a-z]+\b)")
                                   .alias("physiography"))
             .with_columns(pl.when(pl.col("PlotDescription")
                                   .str.contains(r"(at|near)\streeline|near upland-alpine transition"))
                           .then(pl.lit("subalpine"))
                           .otherwise(pl.col("physiography"))
                           .alias("physiography")))

# Classify macrotopography (no changes made to alluvial fan or terrace)
hydrology = (hydrology.with_columns(pl.col("LandscapeTypeSecondary").replace(["tread", "riser", "backslope"],
                                                                         [None, None, "slope"])
                                   .alias("macrotopography"))
             .with_columns(pl.col("VerticalSlopeShape").replace(old="linear", new="planar")
                           .alias("VerticalSlopeShape"))
             .with_columns(pl.when(pl.col("macrotopography") == "slope")
                           .then(pl.concat_str([pl.col("macrotopography"), pl.col("VerticalSlopeShape")],
                                               separator=" "))
                           .otherwise(pl.col("macrotopography"))
                           .alias("macrotopography")
                           ))

# Convert surface water to TRUE/FALSE
print(hydrology_original.select("SurfaceWaterPresent").unique())

hydrology = hydrology.with_columns(pl.col("SurfaceWaterPresent")
                                   .replace_strict(["yes", "no"], ["TRUE", "FALSE"])
                                   .alias("surface_water")
                                   )

print(hydrology.filter(pl.col("surface_water") == "FALSE").select("SurfaceWaterDepth").unique())  # Ensure only null

# Classify water depth
# For plots with surface water, take midpoint of range
hydrology = (hydrology.with_columns(pl.col("SurfaceWaterDepth")
                                   .str.split_exact("_", 1)
                                   .struct.rename_fields(["lower_range", "upper_range"])
                                   .cast(pl.Int64)
                                   .alias("fields")
                                   )
             .unnest("fields")
             .with_columns(pl.when(pl.all_horizontal(pl.col("lower_range",
                                                            "upper_range").is_null()))
                           .then(pl.lit(-999))
                           .otherwise(pl.mean_horizontal("lower_range", "upper_range"))
                           .alias("depth_water_cm")  # Currently redundant with indicator data; needs QC
                           )
             )

# Create columns for missing data; microtopo and drainage would have to be parsed from PlotDescription
hydrology = hydrology.with_columns(pl.lit(None).cast(pl.String).alias("microtopography"),
                                   pl.lit(None).cast(pl.String).alias("drainage"),
                                   pl.lit(None).cast(pl.String).alias("soil_class"),
                                   pl.lit(-999).cast(pl.Decimal(4,1)).alias("microrelief_cm")
                                   )

# -------- Classify Soils Data -----------------------------------------

# Classify restrictive type
print(horizons_original["ImpenetrableDescrip"].value_counts())

horizons = horizons_original.with_columns(pl.col("ImpenetrableDescrip").replace(old=["large boulders",
                                                                                     "cemented layer",
                                                                                     "other"],
                                                                                new=["rock unconsolidated",
                                                                                     "unknown",
                                                                                     "unknown"])
                                          .alias("restrictive_type"))

# Ensure frequency matches expectation from original ImpenetrableDescrip column
print(horizons["restrictive_type"].value_counts())

# -------- Prepare Indicator Data (Depths & Moisture) ------------------

# Ensure Plot Key and Evaluation ID are mutually exclusive (they should be, because the 2021 data used "Plot Key" as
# a unique site visit identifier, while the 2025 data used "Evaluation ID")
print(indicators_original.select(["Plot Key", "Evaluation ID"]).count(),
      indicators_original.select(["Plot Key", "Evaluation ID"]).null_count())

indicators = (indicators_original
                 # Coalesce Plot Key and Evaluation ID
                 .with_columns(pl.coalesce(pl.col(["Plot Key", "Evaluation ID"])
                                           .alias("plot_key")),
                               # Convert Notes to lowercase
                               pl.col("Notes").str.to_lowercase().alias("Notes"))
                 # Convert "unmeasurable" depth values to null to exclude them from mean calculation
                 .with_columns(pl.when(pl.col("Notes").str.contains(r"greater.*100"))
                               .then(None)
                               .otherwise(pl.col("depth_restrictive_layer_cm"))
                               .alias("depth_restrictive_layer_cm"))
                 .with_columns(cs.numeric().replace([-999, 999, 9999], None))
                 .drop(["Plot Key", "Evaluation ID", "GlobalID", "Notes"])
                 )

# Ensure that only one moisture regime value exists per site visit
print(indicators.group_by("plot_key").agg(pl.col("moisture_regime").n_unique())
      .filter(pl.col("moisture_regime") > 1))  # Should be empty

# Calculate mean depths and grab first moisture regime value (all values at a site visit are the same)
indicators = (indicators.group_by("plot_key").agg(cs.numeric().mean().cast(pl.Decimal(4,1)),
                                                        cs.string().first())
                 .rename({"moisture_regime": "original_values"}))

# Join with moisture crosswalk to map old moisture values onto AKVEG Database Dictionary values
indicators = indicators.join(moisture_crosswalk, how="left", on="original_values")

# Ensure that original and re-class moisture columns have the same number of nulls
print(indicators.select(["original_values", "moisture_regime"]).null_count())

# --- Combine Data ----
# Replace nulls with string literal "NULL" for SQL compatibility
.with_columns(cs.string().replace(None, "NULL"))
)


## Format depth at 15% coarse fragments
# Use information from soil horizons table

# For each site, find the first instance where total_coarse_fragments = 15
coarse_fragments_15 = soil_horizons[soil_horizons['total_coarse_fragment_percent'] >= 15].copy()
coarse_fragments_15['min_horizon'] = coarse_fragments_15.groupby('site_visit_code')['horizon_order'].transform('min')
coarse_fragments_15['keep_row'] = coarse_fragments_15['horizon_order'].eq(coarse_fragments_15['min_horizon'])
coarse_fragments_15 = coarse_fragments_15[coarse_fragments_15['keep_row'] == True]
coarse_fragments_15.drop(columns=['horizon_order', 'depth_lower', 'texture',
                                  'total_coarse_fragment_percent', 'min_horizon', 'keep_row'],
                         inplace=True)
coarse_fragments_15.rename(columns={'depth_upper': 'depth_15_percent_coarse_fragments_cm'}, inplace=True)

environment_table = pd.merge(environment_table, coarse_fragments_15, 'left', on='site_visit_code')

# Replace NaN with appropriate null value
environment_table.depth_15_percent_coarse_fragments_cm.fillna(value=-999, inplace=True)

## Format dominant texture at 40 cm
# Use information from soil horizons table
texture_40cm = soil_horizons[soil_horizons['depth_lower'] >= 40].copy()
texture_40cm['min_horizon'] = texture_40cm.groupby('site_visit_code')['horizon_order'].transform('min')
texture_40cm['max_horizon'] = texture_40cm.groupby('site_visit_code')['horizon_order'].transform('max')

# Create conditions: If transition from one horizon to the other is at 40cm, choose the lower horizon
conditions = [(texture_40cm['horizon_order'].eq(texture_40cm['min_horizon'])) & (texture_40cm['depth_lower'] != 40),
              (texture_40cm['min_horizon'].eq(texture_40cm['max_horizon'])) & (texture_40cm['depth_lower'] == 40),
              (texture_40cm['max_horizon'].eq(texture_40cm['horizon_order'])) & (texture_40cm['depth_upper'] == 40)]
choices = [True, True, True]
texture_40cm['keep_row'] = np.select(conditions, choices, default=False)

texture_40cm = texture_40cm[texture_40cm['keep_row'] == True]

# Join with environment table
texture_40cm.drop(columns=['horizon_order', 'depth_upper', 'depth_lower',
                           'total_coarse_fragment_percent', 'min_horizon', 'keep_row'],
                  inplace=True)
texture_40cm.rename(columns={'texture': 'dominant_texture_40_cm'}, inplace=True)
environment_table = pd.merge(environment_table, texture_40cm, 'left', on='site_visit_code')

# Replace NaN with appropriate null value
environment_table.dominant_texture_40_cm.fillna(value='NULL', inplace=True)

## Populate remaining columns with appropriate null values
environment_final = environment_table.assign(depth_moss_duff_cm=-999,
                                             soil_class='NULL')

## Drop all columns that aren't in the template and reorder them to match data entry template
environment_final = environment_final[template.columns]

# -------- Perform Quality Checks --------------------------------------

# Ensure all site codes are associated with a site visit code
environment_table.site_visit_code.isna().sum()

# -------- Export Data -------------------------------------------------
environment_final.to_csv(environment_table_output, index=False, encoding='UTF-8')
