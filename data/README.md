# Data Directory

This directory contains the small metadata and label files that can be shared through GitHub.

Large raster predictors are expected under `data/input/<city_id>/` when running the full workflow, but `*.tif` files are intentionally excluded from Git. Publish those rasters through a data repository or institutional storage and use `data_manifest.csv` to document the file inventory.

The current R scripts require only these derived rasters for each city:

- `<city_id>_building_presence.tif`
- `<city_id>_building_height.tif`
- `<city_id>_ndvi.tif`
- `<city_id>_ndbi.tif`

Sentinel-2 composite rasters (`<city_id>_s2*.tif`) are not read by the current scripts. They can be omitted from the main data deposit unless you want to publish source imagery for provenance or for users who need to regenerate NDVI/NDBI.

Key subdirectories:

- `city_boundary/`: city boundary and city point GeoJSON files plus small supporting tables.
- `training_labels/`: manually labelled informal/formal settlement polygons for the eight training cities.
- `input/`: local location for large city-level raster predictors.

The large downloaded GHS-UCDB source files (`GHS_UCDB_GLOBE_R2024A.gpkg`, `GHS_UCDB_GLOBE_R2024A.xlsx`, and related PDFs) are also not required by the current scripts. The workflow uses the smaller derived GeoJSON city boundary/point files and `pop_share.xls`.
