# Data release

This directory provides a browsable release of the model outputs and training labels.

- `city_probability_maps/<country>/<city>_<id>/` contains the raw 10 m GeoTIFF (`morphological_informality_probability.tif`), a PNG visualization with a fixed 0–1 colour scale (`map_preview.png`), and machine-readable raster metadata.
- `training_labels/kyc_source/` contains normalized GeoJSON copies of the cleaned KnowYourCity (KYC) community-mapped settlement boundaries used as source evidence.
- `training_labels/used_in_models/` contains the separate formal/informal morphology GeoJSON samples used to fit the eight city-specific models. Each folder includes a map that overlays the final labels on the cleaned KYC boundaries.
- `city_index.csv` is the complete city/country/path inventory.

Regenerate the package from the repository root with `python Code/build_github_data_release.py`. The builder never deletes source data.

GeoTIFFs are stored with Git LFS. Clone with Git LFS enabled to retrieve raster content.
