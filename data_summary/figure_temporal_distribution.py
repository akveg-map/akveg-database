# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Plot temporal distribution of data in AKVEG
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-26
# Usage: Execute in Python 3.13+.
# Description: "Plot temporal distribution of data" produces a figure of the temporal distribution of site visits in
# the AKVEG Database, binned into 5-year intervals.
# ---------------------------------------------------------------------------

# Import libraries
import plotly.express as px
import plotly.io as pio
import polars as pl
from pathlib import Path
from akutils import connect_database_postgresql
from akutils import query_to_dataframe

# Define directories
drive = Path('C:/')
root = drive / 'ACCS_Work'
credential_folder = (root / 'OneDrive - University of Alaska' /'ACCS_Teams' /'Vegetation' / 'AKVEG_Database' /
                     "Credentials")
repository_folder = root / 'Repositories' / 'akveg-database'
manuscript_folder = root / 'Projects' / 'AKVEG_Database' / 'Manuscript'

# Define inputs
akveg_credentials = (credential_folder / "akveg_private_read" / "authentication_akveg_private_read.csv")

# Define outputs
counts_output =  manuscript_folder / 'Tables' / 'table_record_counts.csv'
plot_output = manuscript_folder / 'Figures' / 'figure_temporal_extent.png'

# Connect to the AKVEG Database
akveg_db_connection = connect_database_postgresql(akveg_credentials)

# Create cursor
cursor = akveg_db_connection.cursor()

# --- Get number of records for all data tables --- #

# Define data tables
table_list = ['project', 'site', 'site_visit', 'vegetation_cover', 'abiotic_top_cover', 'ground_cover',
                'structural_group_cover', 'shrub_structure',
                'tree_structure',
                'environment', 'soil_metrics', 'soil_horizons']

# Build query segments
queries = [f"SELECT '{t}' as table_name, COUNT(*) FROM {t}" for t in table_list]

# Join segments with UNION ALL
full_query = "\nUNION ALL\n".join(queries)

# Execute query and store results in a dataframe
cursor.execute(full_query)
records = cursor.fetchall()
counts_df = pl.DataFrame(records, schema=["table_name", "row_count"], orient="row")

# --- Plot temporal range of data --- #

# Query site visit table
visit_date_query = f"""
SELECT site_visit_code, 
observe_date, 
perspective.perspective,
scope_vascular.scope AS scope_vascular,
scope_bryophyte.scope AS scope_bryophyte,
scope_lichen.scope AS scope_lichen
FROM site_visit 
LEFT JOIN site ON site_visit.site_code = site.site_code 
LEFT JOIN perspective ON site.perspective_id = perspective.perspective_id
LEFT JOIN scope AS scope_vascular ON site_visit.scope_vascular_id = scope_vascular.scope_id
LEFT JOIN scope AS scope_bryophyte ON site_visit.scope_bryophyte_id = scope_bryophyte.scope_id
LEFT JOIN scope AS scope_lichen ON site_visit.scope_lichen_id = scope_lichen.scope_id
"""
visit_date_df = query_to_dataframe(akveg_db_connection, visit_date_query)
visit_date_df = pl.from_pandas(visit_date_df)

# Bin data by 5-year intervals
## Except for pre-2000 data, which accounts for less than 2% of the total records
visit_date_df = (visit_date_df.with_columns(pl.col("observe_date").dt.year().alias("observe_year")
                                            )
                 .with_columns(pl.when(pl.col("observe_year") < 2000)
                               .then(pl.lit("Pre-2000"))
                               # Format all other years as 5-year intervals
                               .otherwise(pl.format("{}-{}",
                                                    (pl.col("observe_year") // 5) * 5,
                                                    (pl.col("observe_year") // 5) * 5 + 4)
                                          )
                               .alias("year_interval")
                               )
                 )

# Calculate total number of site visits per time bin and perspective
year_data = visit_date_df.group_by('year_interval', 'perspective').len(name="record_count")

# Define sort order for plotting
interval_order = ["Pre-2000", "2000-2004", "2005-2009", "2010-2014", "2015-2019", "2020-2024", "2025-2029"]

# Create year-range plot with clustered bars for each perspective
year_plot = px.bar(
    year_data,
    x='year_interval',
    y='record_count',
    color='perspective',
    barmode='group',
    pattern_shape='perspective',  # Represent different perspectives with patterns
    pattern_shape_sequence=['', '/'],
    color_discrete_sequence=['#404040', '#bababa'],
    category_orders={"year_interval": interval_order},
    template="plotly_white",
    labels={"year_interval": "Year Interval", "record_count": "Number of Site Visits", "perspective": "Perspective"}
)

# Add black outlines around bars
year_plot.update_traces(marker_line_color='black', marker_line_width=1)

# Add counts as text on top of bars
## Use thousands separator
year_plot.update_traces(texttemplate='%{y:,.0f}', textposition='outside')

# Add final touches to plot formatting
year_plot.update_layout(
    yaxis_tickformat=',',  # Update y-axis to use thousands separator
    font=dict(
        family="Arial",
        size=20
    ),
    legend=dict(
        orientation="h",
        yanchor="bottom",
        y=1.05,
        xanchor="center",
        x=0.5
    )
)

# Show plot
year_plot.show()

# --- Export outputs ---
# Export count table
counts_df.write_csv(counts_output)

# Export year range plot to PNG
pio.write_image(year_plot, plot_output, width=1300, height=800, scale=3)

# --- Close DB connection ---
cursor.close()
akveg_db_connection.close()