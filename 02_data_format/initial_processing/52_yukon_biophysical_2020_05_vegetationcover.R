# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# "Format Vegetation Cover for Yukon Biophysical Inventory System Plots"
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-02-18
# Usage: Must be executed in R version 4.5.1+.
# Description: "Format Vegetation Cover for Yukon Biophysical Inventory System Plots" formats vegetation cover data for ingestion into the AKVEG Database. The script appends unique site visit identifiers, corrects taxonomic names using the AKVEG comprehensive checklist, and enforces formatting to match the AKVEG template. The output is a CSV table that can be converted and included in a SQL INSERT statement.
# ---------------------------------------------------------------------------

# Load packages ----
library(dplyr, warn.conflicts = FALSE)
library(fs)
library(readr)
library(readxl)
library(RPostgres)
library(stringr)
library(tidyr)

# Define directories ----

# Set root directory
drive <- "C:"
root_folder <- "ACCS_Work"

# Define input folders
project_folder <- path(drive, root_folder, "OneDrive - University of Alaska", "ACCS_Teams", "Vegetation", "AKVEG_Database")
plot_folder <- path(project_folder, "Data", "Data_Plots", "52_yukon_biophysical_2020")
template_folder <- path(project_folder, "Data", "Data_Entry")
source_folder <- path(plot_folder, "source", "ECLDataForAlaska_20240919", "YBIS_Data")

# Set repository directory
repository_folder <- path(drive, root_folder, "Repositories", "akveg-database")

# Set credentials directory
credential_folder <- path(project_folder, "Credentials", "akveg_public_read")

# Define datasets ----

# Define input datasets
visit_input <- path(plot_folder, "03_sitevisit_yukonbiophysical2020.csv")
veg_input <- path(source_folder, "Veg_2024Apr09.xlsx")
template_input <- path(template_folder, "05_vegetation_cover.xlsx")

# Define output dataset
veg_output <- path(plot_folder, "05_vegetationcover_yukonbiophysical2020.csv")

# Define credentials file
authentication <- path(credential_folder, "authentication_akveg_public_read.csv")

# Define query file
taxa_file <- path(repository_folder, "queries", "00_taxonomy.sql")

# Read in data ----
visit_original <- read_csv(visit_input, col_select = c("site_code", "site_visit_code"))
veg_original <- read_xlsx(veg_input, .name_repair = "universal") ## Ignore warnings
template <- colnames(read_xlsx(path = template_input))

# Connect to AKVEG Database ----

# Import database connection function
connection_script <- path(
  repository_folder,
  "pull_functions", "connect_database_postgresql.R"
)
source(connection_script)

# Connect to the AKVEG PostgreSQL database
akveg_connection <- connect_database_postgresql(authentication)

# Format taxonomy ----

# Define query
query_taxa <- "SELECT taxon_name FROM taxon_all;"

# Read SQL table as dataframe
taxonomy_original <- as_tibble(dbGetQuery(akveg_connection, query_taxa))

# Append site visit code ----
veg_data <- veg_original %>%
  mutate(site_code = str_c(Project.ID, Plot.ID, sep = "_")) %>%
  right_join(visit_original, by = "site_code") %>% ## Drop sites that aren't included in site table
  select(
    site_visit_code, Scientific.name, Veg.cover.pct,
    Needs.checking.flg, Stratum.display.order, Veg.stratum.cd, Access
  )

# Ensure every site visit has at least one entry
print(veg_data %>% filter(is.na(Veg.cover.pct)))

# Standardize scientific names ----

# Correct non-matching codes
veg_taxa <- veg_data %>%
  mutate(
    name_original = str_remove(Scientific.name, " sp\\."),
    name_original = str_remove(name_original, " spp\\.")
  ) %>%
  mutate(name_original = case_when(grepl("Bryophyte", name_original) ~ "bryophyte",
    name_original == "Lichen" ~ "lichen",
    name_original == "Lichen crustose" ~ "crustose lichen",
    name_original == "Liverwort" ~ "liverwort",
    grepl("^Alga", name_original) ~ "algae",
    name_original == "Picea x 3" ~ "Picea",
    name_original == "Cladonia arbuscula ssp mitis" ~ "Cladonia arbuscula ssp. mitis",
    grepl("Elyhordeum", name_original) ~ str_replace(name_original, "x ", "×"),
    name_original == "Hierochloe hirta" ~ "Hierochloë hirta",
    name_original == "Galium brandegeei" ~ "Galium brandegei",
    name_original == "Carex amblyorhyncha" ~ "Carex amblyorrhyncha",
    name_original == "Deschampsia caespitosa" ~ "Deschampsia cespitosa",
    name_original == "Temporarily unidentified" ~ "Unspecified",  ## Combine into single "Unspecified" class
    .default = name_original
  )) %>%
  # Re-classify unknowns
  ## Using stratum code to determine appropriate functional group
  mutate(name_original = case_when(name_original == "Unspecified" & Veg.stratum.cd == "AQ" ~ "unknown",
                                   name_original == "Unspecified" & Veg.stratum.cd == "BR" ~ "liverwort",
                                   name_original == "Unspecified" & Veg.stratum.cd == "FB" ~ "forb",
                                   name_original == "Unspecified" & Veg.stratum.cd == "FG" ~ "fungus",
                                   name_original == "Fungus" ~ "fungus",
                                   name_original == "Unspecified" & Veg.stratum.cd == "FN" ~ "fern",
                                   name_original == "Unspecified" & Veg.stratum.cd == "GR" ~ "graminoid",
                                   name_original == "Unspecified" & Veg.stratum.cd == "GS" ~ "shrub",
                                   name_original == "Unspecified" & Veg.stratum.cd == "LN" ~ "lichen",
                                   name_original == "Unspecified" & Veg.stratum.cd == "LS" ~ "shrub",
                                   name_original == "Unspecified" & Veg.stratum.cd == "MS" ~ "shrub",
                                   name_original == "Unspecified" & Veg.stratum.cd == "S2" ~ "unknown",
                                   name_original == "Unspecified" & Veg.stratum.cd == "S6" ~ "unknown",
                                   name_original == "Unspecified" & Veg.stratum.cd == "SN" ~ "unknown",
                                   .default = name_original)) %>% 
  filter(Veg.stratum.cd != "NV") ##  Remove non-vegetated codes

# Join with AKVEG Checklist
veg_taxa <- veg_taxa %>%
  left_join(taxonomy_original, by = join_by("name_original" == "taxon_name"), keep=TRUE)

# Address codes without a match
veg_taxa <- veg_taxa %>%
  mutate(name_adjudicated = case_when(name_original == "Poaceae" ~ "grass (Poaceae)",
    grepl("^Alopecurus", Scientific.name) & is.na(taxon_name) ~ "Alopecurus",
    name_original == "Astragalus eucosmus ssp. eucosmus" ~ "Astragalus eucosmus",
    name_original == "Bromus carinatus" ~ "grass (Poaceae)",
    name_original == "Cardamine oligosperma" ~ "Cardamine umbellata",
    name_original == "Carex x flavicans" ~ "Carex subspathacea",
    name_original == "Chrysanthemum" ~ "forb",
    name_original == "Cryptogramma crispa var." ~ "Cryptogramma acrostichoides",
    name_original == "Dryas octopetala" ~ "Dryas ajanensis ssp. beringensis",
    name_original == "Galium labradoricum" ~ "Galium",
    name_original == "Melandrium apetalum" ~ "Silene uralensis",
    name_original == "Minuartia" ~ "forb",
    name_original == "Oxytropis borealis var. hudsonica" ~ "Oxytropis borealis",
    name_original == "Pedicularis sudetica" ~ "Pedicularis",
    name_original == "Poa alpina ssp. vivipara" ~ "Poa alpina var. alpina",
    name_original == "Potentilla egedii" ~ "Potentilla anserina ssp. groenlandica",
    name_original == "Potentilla uniflora" ~ "Potentilla vulcanicola",
    name_original == "Ranunculus gmelinii var. gmelinii" ~ "Ranunculus gmelinii ssp. gmelinii",
    name_original == "Salix arctica ssp. arctica" ~ "Salix arctica",
    name_original == "Salix brachycarpa" ~ "Salix niphoclada",
    name_original == "Saxifraga bronchialis" ~ "Saxifraga funstonii",
    name_original == "Scirpus caespitosus" ~ "Trichophorum cespitosum",
    name_original == "Silene acaulis ssp. acaulis" ~ "Silene acaulis",
    name_original == "Vaccinium oxycoccos" ~ "Oxycoccus microcarpus",
    name_original == "Xanthoparmelia chlorochroa" ~ "Xanthoparmelia",
    name_original == "Xanthoria" ~ "lichen",
    .default = taxon_name
  ))

# Ensure that all name original have an adjudicated name
print(veg_taxa %>%
  filter(is.na(name_adjudicated)) %>%
  distinct(name_original))

# Ensure that all accepted names are in the AKVEG checklist
print(which(!(veg_taxa$name_adjudicated %in% unique(taxonomy_original$taxon_name))))  # Should be empty

# Format dead status ----
# Use "veg stratum" column. Codes are defined on pages 4-8 and 4-9 of the "Field manual for describing Yukon ecosystems". All other plants are live.
veg_taxa <- veg_taxa %>%
  mutate(dead_status = case_when(Veg.stratum.cd == "SN" ~ "TRUE",
                                 grepl("S\\d", Veg.stratum.cd) ~ "TRUE",
    .default = "FALSE"
  ))

## Ensure classification worked as expected
print(veg_taxa %>% 
        distinct(Veg.stratum.cd, dead_status) %>% 
        arrange(Veg.stratum.cd))

# Summarize percent cover ---
veg_final <- veg_taxa %>%
  group_by(site_visit_code, name_original, name_adjudicated, dead_status) %>%
  summarize(cover_percent = sum(Veg.cover.pct))

# Format remaining columns ----
veg_final <- veg_final %>%
  mutate(
    cover_type = "absolute foliar cover",
    cover_percent = signif(cover_percent, digits = 3)
  ) %>%
  select(all_of(template))

# QC -----

# Do any of the columns have null values that need to be addressed?
cbind(
  lapply(
    lapply(veg_final, is.na),
    sum
  )
)

# Is the range of summed percent cover reasonable?
temp <- veg_final %>%
  group_by(site_visit_code) %>%
  summarise(total_percent = sum(cover_percent)) %>%
  arrange(-total_percent)

# Are values for dead status Boolean?
print(table(veg_final$dead_status))

# Are the correct number of sites included?
missing_sites = visit_original %>%
  filter(!(site_visit_code %in% veg_final$site_visit_code)) %>%
  select(site_visit_code) # Plots with 100% abiotic cover

missing_data = veg_data %>% 
  filter(site_visit_code %in% missing_sites$site_visit_code) %>% 
  group_by(site_visit_code) %>% 
  summarise(total_percent = sum(Veg.cover.pct)) %>% 
  arrange(total_percent)

# Are there any duplicates?
veg_final %>%
  distinct(site_visit_code, name_adjudicated, dead_status) %>%
  nrow() == nrow(veg_final) # If TRUE, no duplicates to address

# Export data ----
write_csv(veg_final, veg_output)

# Clean workspace ----
rm(list = ls())
