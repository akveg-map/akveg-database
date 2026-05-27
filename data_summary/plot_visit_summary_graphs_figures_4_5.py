# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Produce bar graphs for publication
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-05-27
# Usage: Execute in Python 3.13+.
# Description: "Produce bar graphs for publication" produces two clustered bar graphs summarizing aspects of the data
# in the AKVEG Database: (1) temporal distribution of site visits, binned into 5-year intervals
# and classified by survey perspective (aerial vs. ground); and (2) number of site visits classified by
# taxonomic group (vascular, bryophyte, lichen) and taxonomic scope.
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
year_output = manuscript_folder / 'Figures' / 'figure_temporal_extent.png'
scope_output = manuscript_folder / 'Figures' / 'figure_taxon_scope.png'

# Connect to the AKVEG Database
akveg_db_connection = connect_database_postgresql(akveg_credentials)

# --- Query site visit table ---
visit_query = f"""
SELECT site_visit_code, 
observe_date, 
perspective.perspective,
scope_vascular.scope AS vascular,
scope_bryophyte.scope AS bryophyte,
scope_lichen.scope AS lichen
FROM site_visit 
LEFT JOIN site ON site_visit.site_code = site.site_code 
LEFT JOIN perspective ON site.perspective_id = perspective.perspective_id
LEFT JOIN scope AS scope_vascular ON site_visit.scope_vascular_id = scope_vascular.scope_id
LEFT JOIN scope AS scope_bryophyte ON site_visit.scope_bryophyte_id = scope_bryophyte.scope_id
LEFT JOIN scope AS scope_lichen ON site_visit.scope_lichen_id = scope_lichen.scope_id
"""
visit_df = query_to_dataframe(akveg_db_connection, visit_query)
visit_df = pl.from_pandas(visit_df)

# --- Plot temporal range of data ---
# Bin data into 5-year intervals
# Except for pre-2000 data, which accounts for less than 2% of the total records
visit_df = (visit_df.with_columns(pl.col("observe_date").dt.year()
                                  .alias("observe_year"),
                                  pl.col("perspective").str.replace_many({"aerial": "Aerial",
                                                                          "ground": "Ground"})
                                  )
                 .with_columns(pl.when(pl.col("observe_year") < 2000)
                               .then(pl.lit("Pre-2000"))
                               # Format all other years as 5-year intervals
                               .otherwise(pl.format("{}–{}",
                                                    (pl.col("observe_year") // 5) * 5,
                                                    (pl.col("observe_year") // 5) * 5 + 4)
                                          )
                               .alias("year_interval")
                               )
                 )

# Calculate total number of site visits per time bin and perspective
year_data = visit_df.group_by('year_interval', 'perspective').len(name="record_count")

# Define sort order for plotting
interval_order = ["Pre-2000", "2000–2004", "2005–2009", "2010–2014", "2015–2019", "2020–2024", "2025–2029"]

# Create year plot with clustered bars for each perspective
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
    labels={"year_interval": "Year Interval",
            "record_count": "Number of Site Visits"
            }
)

# Add black outlines around bars
year_plot.update_traces(marker_line_color='black', marker_line_width=1)

# Add counts as text on top of bars
## Use thousands separator
year_plot.update_traces(texttemplate='%{y:,.0f}', textposition='outside')

# Drop x-axis title
year_plot.update_xaxes(
    title=None
)

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
        x=0.5,
        title_text=None
    )
)

# --- Plot taxonomic scope of data ---
# Prepare data
scope_mapping = {
    "exhaustive": "Exhaustive",
    "partial": "Partial",
    "category": "Partial",
    "top canopy": "Dominant Only",
    "common species": "Dominant Only",
    "high cover species": "Dominant Only",
    "non-trace species": "Dominant Only",
    "none": "Not Sampled"
}
scope_data = (visit_df.select(["site_visit_code", "vascular", "bryophyte", "lichen"])
              .unpivot(index="site_visit_code",
                       variable_name="taxon_group",
                       value_name="scope_type")
              .with_columns(pl.col("scope_type").str.replace_many(scope_mapping)
                            .alias("scope_reclass")
                            )
              )

# Calculate total number of site visits per scope type
scope_data = scope_data.group_by('taxon_group', 'scope_reclass').len(name="record_count")

# Define sort order
taxon_order = ["vascular", "bryophyte", "lichen"]
scope_order = ["Exhaustive", "Dominant Only", "Partial", "Not Sampled"]

# Create plot with clustered bars for each taxonomic scope
scope_plot = px.bar(
    scope_data,
    x='taxon_group',
    y='record_count',
    color='scope_reclass',
    barmode='group',
    pattern_shape='scope_reclass',
    pattern_shape_sequence=['', '/', '\\', '.'],
    color_discrete_sequence=['#252525', '#636363', '#b0b0b0', '#f0f0f0'],
    category_orders={"taxon_group": taxon_order,
                     "scope_reclass": scope_order},
    template="plotly_white",
    labels={"taxon_group": "Taxonomic Group",
            "record_count": "Number of Site Visits"}
)

# Update x-axis labels and drop title
scope_plot.update_xaxes(
    title=None,
    tickmode='array',
    tickvals=['vascular', 'bryophyte', 'lichen'],
    ticktext=['Vascular Plants', 'Bryophytes', 'Lichens']
)

# Add same aesthetic modifications as year_plot
scope_plot.update_traces(marker_line_color='black', marker_line_width=1)
scope_plot.update_traces(texttemplate='%{y:,.0f}', textposition='outside')
scope_plot.update_layout(
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
        x=0.5,
        title_text=None
    )
)

# --- Show plots ---
year_plot.show()
scope_plot.show()

# --- Export plots to PNG ---
pio.write_image(year_plot, year_output, width=1300, height=800, scale=3)
pio.write_image(scope_plot, scope_output, width=1300, height=800, scale=3)

# --- Close DB connection ---
akveg_db_connection.close()
