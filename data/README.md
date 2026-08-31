# Data directory

- `input/<city_id>/` contains the four derived raster predictors required by the analysis: building presence, building height, NDVI, and NDBI.
- `training_labels/` contains manually delineated morphological labels for the eight training cities.
- `city_boundary/` contains study-city points and boundaries, national reference shares, and supporting GHS-UCDB files.
- `validation_sample_points_openAI.csv` contains the independent visual-validation sample.

The training polygons operationalize visually identifiable settlement morphology. They are informed by characteristics commonly associated with informal settlements—dense or irregular layout, small and heterogeneous structures, limited vegetation, and fragmented built form—but they are not direct observations of tenure, services, household deprivation, or the full UN-Habitat/SDG 11.1.1 definition.

Large third-party source downloads and non-release working rasters are kept out of Git; see the root `README.md` for publication details.

For the public country/city output hierarchy, raw probability GeoTIFFs, preview maps, and the separated KYC/model-label figures, see [`../data_release/`](../data_release/).
