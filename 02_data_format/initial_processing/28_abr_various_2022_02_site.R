# Format plots datasheet from ABR's 2022 database.

rm(list=ls())

# Load packages ----
library(readxl)
library(tidyverse)

# Define directories ----
drive <- "F:"
root_folder <- file.path(drive,"ACCS_Work/Projects/AKVEG_Database")
data_folder <- file.path(root_folder, "Data/Data_Plots")
project_folder <- file.path(data_folder, "27_ABR_2022")

# Define inputs ----
input_site <- file.path(project_folder, "export_tables", "tnawrocki_deliverable_two_plot.xlsx")
input_veg <- file.path(project_folder, "export_tables","tnawrocki_deliverable_two_veg.xlsx")
input_template <- file.path(root_folder, "Data/Data_Entry","02_Site.xlsx")

# Define outputs ----
output_site <- file.path(project_folder, "temp_files","02_abr_2022.csv")

# Read in data ----
site_data <- read_xlsx(path=input_site)
veg_data <- read_xlsx(path=input_veg)
template <- colnames(read_xlsx(path=input_template))

site_data <- left_join(site_data,veg_data,by="plot_id")

# Format data ----
site_formatted <- site_data %>% 
  rename(latitude_dd = latitude,
         longitude_dd = longitude,
         site_code = plot_id,
         plot_dimensions = plot_radius) %>% 
  mutate(positional_accuracy = case_when(loc_origin_code == "recgps" ~ "consumer grade GPS",
                                         loc_origin_code == "mapgps" ~ "mapping grade GPS",
                                         loc_origin_code == "survgps" ~ "survey grade GPS",
                                         loc_origin_code == "tabletgps" ~ "consumer grade GPS",
                                         loc_origin_code == "photopin" ~ "map interpretation"),
         location_type = "unknown",
         h_error_m = -999,
         h_datum = "NAD83",
         scope_vascular = "exhaustive",
         scope_bryophyte = "common species",
         scope_lichen = "common species",
         cover_method = "line-point intercept") %>% 
  select(all_of(template))

# Format plot dimensions entries
site_formatted$plot_dimensions <- site_formatted$plot_dimensions %>% 
  str_replace_all(c("m" = "",
                    " radius"="",
                    "No Data"="unknown",
                    "NULL"="unknown",
                    "x"="?"))

unique(site_formatted$plot_dimensions)

# Round coordinates. AKVEG accepts up to 16 decimal points
site_formatted$latitude_dd <- round(site_formatted$latitude_dd, digits = 16)
site_formatted$longitude_dd <- round(site_formatted$longitude_dd, digits = 16)            

# Export CSV ----
write_csv(site_formatted,output_site)
