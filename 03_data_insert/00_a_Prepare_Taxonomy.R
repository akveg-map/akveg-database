# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Prepare taxonomic data for upload
# Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-04-23
# Usage: Script should be executed in R 4.5.1+.
# Description: "Prepare taxonomic data for upload" parses taxonomy data into a SQL query for upload into empty tables.
# ---------------------------------------------------------------------------

# Import required libraries
library(dplyr)
library(fs)
library(readr)
library(readxl)
library(stringr)
library(tibble)
library(tidyr)

# Set root directory
drive = 'C:'
root_folder = 'ACCS_Work/OneDrive - University of Alaska/ACCS_Teams/Vegetation/AKVEG_Database/Data'

# Define input folders
data_folder = path(drive,
                    root_folder,
                    'Tables_Taxonomy')
repository_folder = path(drive,
                         'ACCS_Work/Repositories/akveg-database')
output_folder = path(drive, root_folder, 'Data_Plots', 'sql_statements')

# Designate output sql file
sql_taxonomy = path(output_folder,
                    '00_a_Insert_Taxonomy.sql')

# Identify taxonomy tables
taxonomy_file = path(data_folder,
                      'taxonomy.xlsx')
unknown_file = path(data_folder,
                     'unknowns.xlsx')
citation_file = path(data_folder,
                      'citations.xlsx')

# Read taxonomy tables into dataframes
taxonomy_data = read_excel(taxonomy_file, sheet = 'taxonomy') %>%
  select(-code_manual, -org)
unknown_data = read_excel(unknown_file, sheet = 'taxonomy')
citation_data = read_excel(citation_file, sheet = 'citations')

# Merge taxonomy tables to single dataframe
taxonomy_data = bind_rows(taxonomy_data, unknown_data)

# Parse taxon author table
author_table = taxonomy_data %>%
  distinct(taxon_author) %>%
  arrange(taxon_author) %>%
  rowid_to_column('taxon_author_id')

# Parse taxon category table
category_table = taxonomy_data %>%
  distinct(taxon_category) %>%
  arrange(taxon_category) %>%
  rowid_to_column('taxon_category_id')

# Parse taxon family table
family_table = taxonomy_data %>%
  distinct(taxon_family) %>%
  arrange(taxon_family) %>%
  rowid_to_column('taxon_family_id')

# Parse growth habit table
habit_table = taxonomy_data %>%
  distinct(taxon_habit) %>%
  arrange(taxon_habit) %>%
  rowid_to_column('taxon_habit_id')

# Parse taxonomic status table
status_table = taxonomy_data %>%
  distinct(taxon_status) %>%
  arrange(taxon_status) %>%
  rowid_to_column('taxon_status_id')

# Parse taxonomic level table
level_table = taxonomy_data %>%
  distinct(taxon_level) %>%
  arrange(taxon_level) %>%
  rowid_to_column('taxon_level_id')

# Parse taxonomic source table
source_table = taxonomy_data %>%
  distinct(taxon_source) %>%
  arrange(taxon_source) %>%
  left_join(citation_data, by = 'taxon_source') %>%
  rowid_to_column('taxon_source_id')

# Parse hierarchy table
hierarchy_table = taxonomy_data %>%
  filter(taxon_level == 'genus' |
           taxon_level == 'unknown' |
           taxon_level == 'functional group') %>%
  filter(taxon_status == 'accepted' |
           taxon_status == 'historical' |
           taxon_status == 'taxonomy unresolved' |
           taxon_status == 'location unresolved' |
           taxon_status == 'adjacent Yukon' |
           taxon_status == 'adjacent BC' |
           taxon_status == 'adjacent Canada' |
           taxon_status == 'ephemeral non-native') %>%
  distinct(taxon_accepted, .keep_all = TRUE) %>%
  left_join(family_table, by = 'taxon_family') %>%
  left_join(category_table, by = 'taxon_category') %>%
  rename(taxon_genus = taxon_accepted) %>%
  rename(taxon_genus_code = taxon_code) %>%
  arrange(taxon_genus_code) %>%
  select(taxon_genus_code, taxon_genus, taxon_family_id, taxon_category_id)

# Parse taxon accepted table
accepted_table = taxonomy_data %>%
  filter(taxon_status == 'accepted' |
           taxon_status == 'historical' |
           taxon_status == 'taxonomy unresolved' |
           taxon_status == 'location unresolved' |
           taxon_status == 'adjacent Yukon' |
           taxon_status == 'adjacent BC' |
           taxon_status == 'adjacent Canada' |
           taxon_status == 'ephemeral non-native') %>%
  separate(taxon_accepted, c('taxon_genus'), extra = 'drop', sep = '([ ])', remove = FALSE) %>%
  mutate(join_name = case_when(taxon_level == 'functional group' |
                                 taxon_level == 'unknown' ~ taxon_accepted,
                               TRUE ~ taxon_genus)) %>%
  left_join(hierarchy_table, by = c('join_name' = 'taxon_genus')) %>%
  left_join(source_table, by = 'taxon_source') %>%
  left_join(level_table, by = 'taxon_level') %>%
  left_join(habit_table, by = 'taxon_habit') %>%
  arrange(taxon_accepted) %>%
  rename(taxon_accepted_code = taxon_code) %>%
  select(taxon_accepted_code, taxon_accepted, taxon_genus_code, taxon_source_id, taxon_link,
         taxon_level_id, taxon_habit_id, taxon_native, taxon_non_native)

# Parse taxon table
taxon_table = taxonomy_data %>%
  left_join(author_table, by = 'taxon_author') %>%
  left_join(status_table, by = 'taxon_status') %>%
  left_join(accepted_table, by = 'taxon_accepted') %>%
  select(taxon_code, taxon_name, taxon_author_id, taxon_status_id, taxon_accepted_code)

# Remove extra fields
accepted_table = accepted_table %>%
  select(-taxon_accepted)
hierarchy_table = hierarchy_table %>%
  select(-taxon_genus)

#### WRITE DATA TO SQL FILE

# Write statement header
statement = c(
  '-- -*- coding: utf-8 -*-',
  '-- ---------------------------------------------------------------------------',
  '-- Insert taxonomy data',
  '-- Author: Timm Nawrocki, Amanda Droghini, Alaska Center for Conservation Science',
  paste('-- Last Updated: ', Sys.Date()),
  '-- Usage: Script should be executed in a PostgreSQL 16+ database.',
  '-- Description: "Insert taxonomy data" pushes data from the taxonomy editing tables into the database server. The script "Build taxonomy tables" should be run prior to this script to start with empty, properly formatted tables.',
  '-- ---------------------------------------------------------------------------',
  '',
  '-- Initialize transaction',
  'START TRANSACTION;',
  ''
  )

# Add author statement
statement = c(statement,
              '-- Insert data into taxon author table',
              'INSERT INTO taxon_author (taxon_author_id, taxon_author) VALUES'
              )
author_sql = author_table %>%
  mutate_if(is.character,
            str_replace_all, pattern = '\'', replacement = '\'\'') %>%
  mutate(taxon_author = paste('\'', taxon_author, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep =''))
author_sql[nrow(author_sql),] = paste(str_sub(author_sql[nrow(author_sql),],
                                              start = 1,
                                              end = -2),
                                      ';',
                                      sep = '')
for (line in author_sql) {
  statement = c(statement, line)
}

# Add category statement
statement = c(statement,
              '',
              '-- Insert data into taxon category table',
              'INSERT INTO taxon_category (taxon_category_id, taxon_category) VALUES'
              )
category_sql = category_table %>%
  mutate(taxon_category = paste('\'', taxon_category, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
category_sql[nrow(category_sql),] = paste(str_sub(category_sql[nrow(category_sql),],
                                              start = 1,
                                              end = -2),
                                          ';',
                                          sep = '')
for (line in category_sql) {
  statement = c(statement, line)
}

# Add family statement
statement = c(statement,
              '',
              '-- Insert data into taxon family table',
              'INSERT INTO taxon_family (taxon_family_id, taxon_family) VALUES'
              )
family_sql = family_table %>%
  mutate(taxon_family = paste('\'', taxon_family, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
family_sql[nrow(family_sql),] = paste(str_sub(family_sql[nrow(family_sql),],
                                                  start = 1,
                                                  end = -2),
                                      ';',
                                      sep = '')
for (line in family_sql) {
  statement = c(statement, line)
}

# Add habit statement
statement = c(statement,
              '',
              '-- Insert data into taxon habit table',
              'INSERT INTO taxon_habit (taxon_habit_id, taxon_habit) VALUES'
)
habit_sql = habit_table %>%
  mutate(taxon_habit = paste('\'', taxon_habit, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
habit_sql[nrow(habit_sql),] = paste(str_sub(habit_sql[nrow(habit_sql),],
                                              start = 1,
                                              end = -2),
                                      ';',
                                      sep = '')
for (line in habit_sql) {
  statement = c(statement, line)
}

# Add taxon status statement
statement = c(statement,
              '',
              '-- Insert data into taxon status table',
              'INSERT INTO taxon_status (taxon_status_id, taxon_status) VALUES'
)
status_sql = status_table %>%
  mutate(taxon_status = paste('\'', taxon_status, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
status_sql[nrow(status_sql),] = paste(str_sub(status_sql[nrow(status_sql),],
                                            start = 1,
                                            end = -2),
                                    ';',
                                    sep = '')
for (line in status_sql) {
  statement = c(statement, line)
}

# Add taxon level statement
statement = c(statement,
              '',
              '-- Insert data into taxon level table',
              'INSERT INTO taxon_level (taxon_level_id, taxon_level) VALUES'
)
level_sql = level_table %>%
  mutate(taxon_level = paste('\'', taxon_level, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
level_sql[nrow(level_sql),] = paste(str_sub(level_sql[nrow(level_sql),],
                                              start = 1,
                                              end = -2),
                                      ';',
                                      sep = '')
for (line in level_sql) {
  statement = c(statement, line)
}

# Add taxon source statement
statement = c(statement,
              '',
              '-- Insert data into taxon source table',
              'INSERT INTO taxon_source (taxon_source_id, taxon_source, taxon_citation) VALUES'
)
source_sql = source_table %>%
  mutate_if(is.character,
            str_replace_all, pattern = '\'', replacement = '\'\'') %>%
  mutate(taxon_source = paste('\'', taxon_source, '\'', sep = '')) %>%
  mutate(taxon_citation = paste('\'', taxon_citation, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
source_sql[nrow(source_sql),] = paste(str_sub(source_sql[nrow(source_sql),],
                                            start = 1,
                                            end = -2),
                                    ';',
                                    sep = '')
for (line in source_sql) {
  statement = c(statement, line)
}

# Add hierarchy statement
statement = c(statement,
              '',
              '-- Insert data into taxon hierarchy table',
              'INSERT INTO taxon_hierarchy (taxon_genus_code, taxon_family_id, taxon_category_id) VALUES'
)
hierarchy_sql = hierarchy_table %>%
  mutate(taxon_genus_code = paste('\'', taxon_genus_code, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
hierarchy_sql[nrow(hierarchy_sql),] = paste(str_sub(hierarchy_sql[nrow(hierarchy_sql),],
                                            start = 1,
                                            end = -2),
                                    ';',
                                    sep = '')
for (line in hierarchy_sql) {
  statement = c(statement, line)
}

# Add taxon accepted statement
statement = c(statement,
              '',
              '-- Insert data into taxon accepted table',
              'INSERT INTO taxon_accepted (taxon_accepted_code, taxon_genus_code, taxon_source_id, taxon_link, taxon_level_id, taxon_habit_id, taxon_native, taxon_non_native) VALUES'
)
accepted_sql = accepted_table %>%
  mutate_if(is.character,
            str_replace_all, pattern = '\'', replacement = '\'\'') %>%
  mutate(taxon_accepted_code = paste('\'', taxon_accepted_code, '\'', sep = '')) %>%
  mutate(taxon_genus_code = paste('\'', taxon_genus_code, '\'', sep = '')) %>%
  mutate(taxon_link = paste('\'', taxon_link, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
accepted_sql[nrow(accepted_sql),] = paste(str_sub(accepted_sql[nrow(accepted_sql),],
                                                    start = 1,
                                                    end = -2),
                                            ';',
                                            sep = '')
for (line in accepted_sql) {
  statement = c(statement, line)
}

# Add taxon statement
statement = c(statement,
              '',
              '-- Insert data into taxon all table',
              'INSERT INTO taxon_all (taxon_code, taxon_name, taxon_author_id, taxon_status_id, taxon_accepted_code) VALUES'
)
taxon_sql = taxon_table %>%
  mutate(taxon_name = paste('\'', taxon_name, '\'', sep = '')) %>%
  mutate(taxon_code = paste('\'', taxon_code, '\'', sep = '')) %>%
  mutate(taxon_accepted_code = paste('\'', taxon_accepted_code, '\'', sep = '')) %>%
  unite(sql, sep = ', ', remove = TRUE) %>%
  mutate(sql = paste('(', sql, '),', sep = ''))
taxon_sql[nrow(taxon_sql),] = paste(str_sub(taxon_sql[nrow(taxon_sql),],
                                                  start = 1,
                                                  end = -2),
                                          ';',
                                          sep = '')
for (line in taxon_sql) {
  statement = c(statement, line)
}

# Finalize statement
statement = c(statement,
              '',
              '-- Commit transaction',
              'COMMIT TRANSACTION;')

# Write statement to SQL file
write_lines(statement, sql_taxonomy)

# Clear workspace
rm(list=ls())
