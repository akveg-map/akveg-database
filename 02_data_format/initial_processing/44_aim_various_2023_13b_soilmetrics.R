# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# "Format Soil Metrics for BLM AIM Various 2022 data"
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2024-09-06
# Usage: Must be executed in R version 4.4.1+.
# Description: "Format Soil Metrics for BLM AIM Various 2022 data" appends unique site visit identifier, ensures formatting matches the AKVEG template, and performs QA/QC checks. The script depends on the output from the 44_aim_various_2022_13_soilmetrics.py script. The output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Load packages ----
library(dplyr)
library(fs)
library(readr)
library(readxl)
library(stringr)
library(tidyr)

# Define directories ----

# Set root directory
drive = 'C:'
root_folder = 'ACCS_Work'

# Define input folders
project_folder = path(drive, root_folder, 'OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database')
plot_folder = path(project_folder, 'Data', 'Data_Plots', '44_aim_various_2022')
workspace_folder = path(plot_folder, 'working')
template_folder = path(project_folder, 'Data', 'Data_Entry')

# Define datasets ----

# Define input datasets
site_visit_input = path(plot_folder, "03_sitevisit_aimvarious2022.csv")
soil_metrics_input = path(workspace_folder, 'soil_metrics_export.csv')
template_input = path(project_folder, 'Data', "Data_Entry", "13_soil_metrics.xlsx")

# Define output dataset
soil_metrics_output = path(plot_folder, '13_soilmetrics_aimvarious2022.csv')

# Read in data ----
site_visit_original = read_csv(site_visit_input)
soil_metrics_original = read_csv(soil_metrics_input)
template = colnames(read_xlsx(path=template_input))

# Format site code ----
# Remove 'AK' prefix
# Remove "CYFO' and 'EIFO' prefixes (project_code already includes this info)
soil_metrics_data = soil_metrics_original %>% 
  mutate(site_code = str_remove_all(PlotID, c("AK-|CYFO-|EIFO-")),
         site_code = str_replace_all(site_code, "-", "_"))

# Append site visit code ----
soil_metrics_data = site_visit_original %>% 
  select(site_code, site_visit_code) %>%
  right_join(soil_metrics_data, by = "site_code") %>% # Use right join to drop any excluded plots
  select(-c(site_code, OBJECTID, PlotID, Project))

# Format sample collection data ----
soil_metrics_data = soil_metrics_data %>% 
  mutate(water_measurement = case_when(ChemistrySampleFrom == 'Surface Water' ~ 'TRUE',
                                       ChemistrySampleFrom == 'Groundwater' ~ 'FALSE')) %>% 
  rename(measure_depth_cm = Depth) %>% 
  select(-c(ChemistrySampleFrom, Location, StandFlow))

# Explore measurement data ----
# Unclear what the 'Not collected' in the 'flag' columns are supposed to indicate, since those comments have a measurement associated with them.
# Make sure all values are within a reasonable range

plot(soil_metrics_data$Temp)
plot(soil_metrics_data$pH)
plot(soil_metrics_data$EC) # Drop outlier values of 519 and 3072

# If there are null values, convert to -999
summary(soil_metrics_data$Temp)
summary(soil_metrics_data$pH) # Manually check and values below 4 or above 7.5
summary(soil_metrics_data$EC)

# Drop outliers and final formatting ----
soil_metrics_final = soil_metrics_data %>% 
  mutate(conductivity_mus = case_when(EC > 300 ~ -999,
                                      .default = EC)) %>% 
  rename(ph = pH,
         temperature_deg_c = Temp) %>% 
  select(all_of(template))

# QA/QC ----

# Do any of the columns have null values that need to be addressed?
cbind(
  lapply(
    lapply(soil_metrics_final, is.na)
    , sum)
)

# Verify values for water measurement column (should be Boolean)
table(soil_metrics_final$water_measurement)

# Export data ----
write_csv(soil_metrics_final,file=soil_metrics_output)

# Clean workspace ----
rm(list=ls())
