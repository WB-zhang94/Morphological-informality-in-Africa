# Morphological informality in Africa: data release

This repository contains the public model-output and training-label data accompanying the study **Hidden and fragmented patterns of morphological informality across African cities revealed by open geospatial data**.

## Contents

- [`city_probability_maps/`](city_probability_maps/) is organized as `<country>/<city>_<GHS Urban Centre ID>/`. Every city folder contains:
  - `morphological_informality_probability.tif`: the raw 10 m probability GeoTIFF;
  - `map_preview.png`: a directly viewable map using a common 0–1 colour scale;
  - `raster_metadata.json`: CRS, raster dimensions, bounds, data type, and sampled value range.
- [`training_labels/kyc_source/`](training_labels/kyc_source/) contains normalized GeoJSON copies of cleaned KnowYourCity (KYC) community-mapped settlement boundaries and preview figures.
- [`training_labels/used_in_models/`](training_labels/used_in_models/) contains the separate formal/informal morphological polygons used to train the eight city-specific models. In the GeoJSON files, `class = 1` denotes informal morphology and `class = -1` denotes formal morphology. Each preview overlays these polygons on the KYC boundaries, shown in yellow.
- [`city_index.csv`](city_index.csv) lists all 84 cities, countries, GHS Urban Centre IDs, paths, and training-city status.

The final model labels are a training sample rather than a replacement or exhaustive copy of KYC. The labels operationalize image-observable morphological informality and are not direct observations of tenure, services, household deprivation, or the complete UN-Habitat/SDG 11.1.1 household definition.

## Downloading the GeoTIFFs

The raw GeoTIFFs are stored with Git LFS. Install Git LFS before cloning or pulling the repository:

```bash
git lfs install
git clone https://github.com/WB-zhang94/Morphological-informality-in-Africa.git
```

## KYC source citation

Slum Dwellers International Profiling Teams. 2022. *KnowYourCity data for research*. Data processed by Dana R. Thomson and Hazem Mahmoud. [Source repository](https://github.com/hazemmahmoud88/KnowYourCity-data-for-research).
