# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Plot site locations
# Author: Amanda Droghini, Alaska Center for Conservation Science
# Last Updated: 2026-09-12
# Usage: Script should be executed in R 4.4.1+.
# Description: A function that outputs a map (plot) of site coordinates on a Google Maps basemap, to help users
identify spatial outliers.

# Parameters
# @param sf_data An sf object with the appropriate coordinate reference system specified
# @ param api_key String of the user's Google Maps API key. More information can be found: https://developers.google.com/maps/documentation/embed/get-api-key
# @ param map_extent An integer from 3 to 21, equivalent to zoom parameter in ggmap::get_map(). The default value is 7. If plots are in a single, general area within the state of Alaska, I recommend choosing a value between 6 (larger scale) and 12 (smaller scale e.g., all plots are within a ~12 km radius), and going up/down as needed. Make sure there are no warnings about values outside the scale range when mapping.

# Packages
# @import ggmap
# @import ggplot2
# @import terra
# ---------------------------------------------------------------------------

plot_outliers = function(sf_data, api_key, map_extent = 7) {
  
  ggmap::register_google(key=api_key)
  
  # Define spatial extent
  data_extent = terra::ext(sf_data)
  
  # Download basemap
  basemap = ggmap::get_map(
    c(
      left = as.numeric(data_extent$xmin),
      bottom = as.numeric(data_extent$ymin),
      right = as.numeric(data_extent$xmax),
      top = as.numeric(data_extent$ymax)
    ),
    maptype = "hybrid",
    zoom = map_extent
  )
  
  # Plot locations
  # Coordinate system warning can be ignored
  # Thank you to @Allan Cameron for the code: https://stackoverflow.com/questions/77244364/is-ggmap-sf-still-plotting-point-in-wrong-place
  outlier_map = ggmap::ggmap(basemap) + 
    geom_point(data = as.data.frame(st_coordinates(sf_data)), aes(X, Y), 
               inherit.aes = FALSE, 
               fill = '#ee6677', 
               size = 1.3, 
               pch = 21) +
    xlab('Longitude') +
    ylab('Latitude')
  
  print(outlier_map)
}
