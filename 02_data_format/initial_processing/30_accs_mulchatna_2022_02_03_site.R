# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Format Site and Site Visit Tables for ACCS Mulchatna data.
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2022-11-02
# Usage: Code chunks must be executed sequentially in R version 4.2.1+.
# Description: "Format Site and Site Visit Tables for ACCS Mulchatna data" reads in data from a Survey 123 form, renames columns, creates site visit id, and selects specific columns to match the Site and Site Visit tables in the AKVEG Database.
# ---------------------------------------------------------------------------

rm(list=ls())

# Load packages ----
library(readxl)
library(tidyverse)

# Define directories ----
drive <- "F:"
root_folder <- file.path(drive,"ACCS_Work/Projects/AKVEG_Database")
data_folder <- file.path(root_folder, "Data/Data_Plots")
project_folder <- file.path(data_folder, "30_accsMulchatna_2022")

# Define inputs ----
input_survey <- file.path(project_folder, "survey123", "mulchatna_2022_site.xlsx")
input_site_template <- file.path(root_folder, "Data", "Data_Entry", "02_Site.xlsx")
input_visit_template <- file.path(root_folder, "Data", "Data_Entry", "03_Site_Visit.xlsx")

# Define outputs ----
output_site <- file.path(project_folder, "temp_files","02_accs_mulchatna.csv")
output_visit <- file.path(project_folder, "temp_files","03_accs_mulchatna.csv")

# Read in data ----
survey_data <- read_xlsx(path=input_survey, sheet="site_metadata")
site_template <- read_xlsx(path=input_site_template)
visit_template <- read_xlsx(path=input_visit_template)

# Define columns
site_columns <- colnames(site_template)
visit_columns <- colnames(visit_template)

# Create Site datasheet ----
site_formatted <- survey_data %>%
  rename(h_error_m = error_m) %>% 
  select(all_of(site_columns)) %>% 
  mutate(plot_dimensions = "12.5")

# Round error number to match SQL field specification
site_formatted$h_error_m <- round(site_formatted$h_error_m,digits=2)

# Create Site Visit datasheet ----
visit_formatted <- survey_data %>% 
  mutate(project_code = "accs_mulchatna",
         date_string = str_replace_all(observed_date, pattern="-", replacement=""),
         site_visit_id=paste(site_code,date_string,sep="_"),
         structural_class = str_to_title(structural_class)) %>%
  rename(observe_date = observed_date) %>% 
  select(all_of(visit_columns))

# Export data ----
write_csv(x=site_formatted, file=output_site)
write_csv(x=visit_formatted,file=output_visit)