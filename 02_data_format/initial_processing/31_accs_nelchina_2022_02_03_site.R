# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site and Site Visit Tables for ACCS Nelchina data.
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2022-11-02
# Usage: Code chunks must be executed sequentially in R version 4.2.1+.
# Description: "Format Site and Site Visit Tables for ACCS Nelchina data" reads in data from a Survey 123 form, renames columns, creates site visit id, and selects specific columns to match the Site and Site Visit tables in the AKVEG Database.
# ---------------------------------------------------------------------------

rm(list=ls())

# Load packages ----
library(readxl)
library(tidyverse)

# Define directories ----
drive <- "F:"
root_folder <- file.path(drive,"ACCS_Work/Projects/AKVEG_Database")
data_folder <- file.path(root_folder, "Data/Data_Plots")
project_folder <- file.path(data_folder, "31_accsNelchina_2022")

# Define inputs ----
input_survey <- file.path(project_folder, "source", "Nelchina_2022_Site.xlsx")
input_site_template <- file.path(root_folder, "Data", "Data_Entry", "02_Site.xlsx")
input_visit_template <- file.path(root_folder, "Data", "Data_Entry", "03_Site_Visit.xlsx")

# Define outputs ----
output_site <- file.path(project_folder, "temp_files","02_accs_nelchina.csv")
output_visit <- file.path(project_folder, "temp_files","03_accs_nelchina.csv")

# Read in data ----
survey_data <- read_xlsx(path=input_survey)
site_columns <- colnames(read_xlsx(path=input_site_template))
visit_columns <- colnames(read_xlsx(path=input_visit_template))

# Create Site datasheet ----
site_formatted <- survey_data %>%
  rename(site_code = `Site Code`,
         cover_method = `Cover Method`,
         positional_accuracy = `Positional Accuracy`,
         h_datum = `Horizontal Datum`,
         h_error_m = error_m,
         plot_dimensions = `Plot Dimensions (m)`,
         scope_vascular = `Vascular Scope`,
         scope_bryophyte = `Bryophyte Scope`,
         scope_lichen = `Lichen Scope`,
         location_type = `Location Type`) %>% 
  select(all_of(site_columns))

site_formatted$plot_dimensions = str_replace_all(site_formatted$plot_dimensions, pattern =" m radius", replacement = "")

# Round error number to match SQL field specification
site_formatted$h_error_m <- round(site_formatted$h_error_m,digits=2)

# Create Site Visit datasheet ----
visit_formatted <- survey_data %>% 
  rename(site_code = `Site Code`,
         data_tier = `Data Tier`,
         observe_date = observed_date,
         veg_observer = `Veg. Observer`,
         veg_recorder = `Veg. Recorder`,
         env_observer = `Env. Observer`,
         soils_observer = `Soils Observer`,
         structural_class = `Structural Class`) %>% 
  mutate(project_code = "accs_nelchina",
         date_string = str_replace_all(observe_date, pattern="-", replacement=""),
         site_visit_id=paste(site_code,date_string,sep="_"),
         structural_class = str_to_title(structural_class)) %>%
  mutate(structural_class = if_else(structural_class=="Barrens/Partially Vegetated",
                                    "Barrens or Partially Vegetated",structural_class)) %>% 
  select(all_of(visit_columns))

# Export data ----
write_csv(x=site_formatted, file=output_site)
write_csv(x=visit_formatted,file=output_visit)