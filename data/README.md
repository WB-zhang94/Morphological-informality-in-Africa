# Data Directory

This directory contains the small metadata and label files that can be shared through GitHub.

Large raster predictors are expected under `data/input/<city_id>/` when running the full workflow, but `*.tif` files are intentionally excluded from Git. Publish those rasters through a data repository or institutional storage and use `data_manifest.csv` to document the file inventory.

Key subdirectories:

- `city_boundary/`: city boundary and city point GeoJSON files plus small supporting tables.
- `training_labels/`: manually labelled informal/formal settlement polygons for the eight training cities.
- `input/`: local location for large city-level raster predictors.

