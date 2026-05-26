# Morphological informality in Africa

Data and code accompanying the paper:

**Hidden and fragmented patterns of morphological informality across African cities revealed by open geospatial data**

This repository shares the workflow, training data, fitted models, intermediate products, and outputs used to map morphological informality across African cities. The study develops a scalable remote-sensing framework that combines open satellite imagery, building datasets, manually labelled settlement polygons, city-specific random forest models, and a similarity-weighted ensemble to produce 10 m probability surfaces of morphologically informal settlements.

The outputs are intended to support reproducible analysis for the paper and to help other researchers inspect, reuse, or adapt the data and code for urban informality mapping.

## Study overview

Informal settlements are often spatially under-represented in official statistics and global urban datasets, especially when they occur as small or fragmented clusters embedded in otherwise formal neighbourhoods. This project maps the probability of morphological informality using built-environment and spectral indicators derived from open geospatial data.

The analysis:

- uses manually labelled informal and formal settlement polygons for eight African cities;
- trains city-specific random forest models using Sentinel-2, NDVI, NDBI, Google Open Buildings building presence, and building height predictors;
- computes inter-city similarity from urban descriptor variables;
- transfers the city-specific models to other African cities using a similarity-weighted ensemble;
- generates 10 m informal-settlement probability maps and binary classifications;
- validates results using leave-one-city-out cross-validation, independent informal/formal reference points, and OpenAI-assisted visual settlement classification samples.

## Repository structure

```text
.
|-- Code/                    R scripts used for modelling, prediction, validation, and figures
|   `-- misc/                Miscellaneous exploratory notes
|-- data/
|   |-- city_boundary/       Urban centre boundaries, city points, and GHS-UCDB reference files
|   |-- input/               City-level raster predictor stacks
|   |-- training_labels/     Manual informal/formal settlement training polygons
|   `-- validation_sample_points_openAI.csv
|-- models/
|   `-- rf/                  Fitted random forest models and city similarity tables
|-- results/
|   |-- output_data/         Model outputs, validation summaries, thresholds, and derived rasters
|   |-- paper_figures/       Generated paper and supplementary figures
|   |-- r_session/           R session artifacts moved out of the script folder
|   `-- rf_figures/          Random forest diagnostic plots and variable-importance figures
`-- README.md
```

## Main data products

Large raster files are not committed to GitHub. They are listed in `data_manifest.csv` and should be published through a data repository, institutional archive, or another large-file distribution channel. The GitHub repository is intended to hold the code, documentation, training labels, model objects, and small summary tables.

### Input predictors

`data/input/<city_id>/` contains raster predictors for each city. The current R workflow requires four derived predictor rasters:

- `<city_id>_ndvi.tif`: Normalized Difference Vegetation Index;
- `<city_id>_ndbi.tif`: Normalized Difference Built-up Index;
- `<city_id>_building_presence.tif`: building presence layer;
- `<city_id>_building_height.tif`: building height layer.

The raw or composite Sentinel-2 rasters (`<city_id>_s2*.tif`) are not read by the current scripts. They are useful only if users need to inspect the source imagery or regenerate NDVI/NDBI. For publishing the reproducible analysis package, the Sentinel-2 composites can be omitted as long as the derived NDVI and NDBI rasters are provided or can be regenerated.

City identifiers correspond to the GHS Urban Centre Database field `ID_UC_G0`.

### Training labels

`data/training_labels/` contains manually labelled GeoJSON polygons for eight training cities:

- Accra, Ghana (`3175`)
- Cape Town, South Africa (`431`)
- Dar es Salaam, Tanzania (`3570`)
- Freetown, Sierra Leone (`47`)
- Kampala, Uganda (`1711`)
- Lagos, Nigeria (`1289`)
- Nairobi, Kenya (`1717`)
- Port Harcourt, Nigeria (`7209`)

### Model outputs

`results/output_data/` includes:

- `slum_probability/`: 10 m ensemble probability rasters (`*_ensemble_prob.tif`);
- `slum_class/`: binary classified rasters for training/evaluation cities;
- `slum_percentage_1km/t50/`: 1 km aggregated percentage rasters;
- `CrossValidation/`: leave-one-city-out outputs, ROC plots, validation points, and model metrics;
- `thresholds_by_pop_share_country.csv`: country-level probability thresholds and calibrated updated thresholds;
- `informality_share.csv`: city-level probability-bin summaries;
- `slum_analysis_results_openai.csv`: OpenAI-assisted validation results.

`models/rf/` contains fitted random forest models (`.rds`), the city list, and the similarity matrix used to weight the ensemble predictions.

## Code workflow

The core scripts in `Code/` are:

1. `Base_models.R`
   Trains the eight city-specific random forest models from the manually labelled polygons and predictor rasters.

2. `City_similarity.R`
   Calculates inter-city similarity between the training cities and target cities using GHS-UCDB city descriptor variables.

3. `Cross_Validation.R`
   Runs leave-one-city-out cross-validation for the similarity-weighted ensemble.

4. `Prediction.R`
   Applies the fitted models to target cities and combines them into similarity-weighted ensemble probability maps.

5. `thresholds.R` and `City_threshold.R`
   Estimate and calibrate probability thresholds for binary informal-settlement classification.

6. `slum_percentage.R`
   Aggregates probability outputs and derives city-level informality summaries.

7. `points_validation.R`
   Evaluates the probability maps against independent reference points and OpenAI-assisted visual classification outputs.

8. `spatial_heterogeneity.R`, `Fig4.R`, and `SI_A.R`
   Generate figures and supplementary analyses for the manuscript.

## Requirements

The analysis is written in R. The main packages used by the scripts include:

- `terra`
- `sf`
- `dplyr`
- `tidyr`
- `stringr`
- `randomForest`
- `pROC`
- `MLmetrics`
- `Metrics`
- `readxl`
- `ggplot2`
- `patchwork`
- `ggrepel`
- `cowplot`
- `rnaturalearth`
- `rnaturalearthdata`
- `countrycode`
- `cluster`
- `pheatmap`
- `caret`
- `broom`

The R scripts source `Code/paths.R`, which finds the repository root automatically when scripts are run from either the project root or the `Code/` directory. Most inputs and outputs are therefore resolved through named project paths such as `data/input/`, `models/rf/`, and `results/output_data/`.

`thresholds.R` reads WorldPop 2023 constrained 100 m population rasters from the public WorldPop HTTPS archive by default. The default base URL is:

```text
https://worldpop-public-data.soton.ac.uk/GIS/Population/Global_2015_2030/R2025A/2023
```

For offline or repeated runs, you can instead use a local cache by setting `WORLDPOP_ROOT` to the directory that contains the country folders, for example:

```r
Sys.setenv(WORLDPOP_ROOT = "D:/path/to/WorldPop/Global_2015_2030/R2025A/2023")
```

You can also override the remote source with `WORLDPOP_BASE_URL` if the WorldPop mirror changes.

## External data sources

The workflow uses the following external datasets:

- Global Human Settlement Urban Centre Database (GHS-UCDB 2024A): urban boundaries and city descriptor variables.
- Sentinel-2 Level-2A surface reflectance: spectral composites, NDVI, and NDBI.
- Google Open Buildings 2.5D Temporal Dataset: building presence and height predictors.
- WorldPop Global 2 population data: population surfaces used in threshold calibration and population-share summaries.
- UN-Habitat statistics on the share of urban populations living in slums: national reference values for threshold calibration.

Google Maps and Google Street View imagery used for visual validation cannot be redistributed due to copyright restrictions. The repository includes the sampled validation points and classification outputs where redistribution is permitted.

## Large Files And Publication

The repository excludes large raster and third-party reference files using `.gitignore`, including `*.tif`, large GHS-UCDB downloads, generated paper figures, and local R session artifacts. This keeps the GitHub `main` branch lightweight and avoids GitHub file-size limits.

Use `data_manifest.csv` as the inventory for files that should be deposited separately. Recommended publication pattern:

- Publish this GitHub repository for code, labels, fitted random forest models, and summary tables.
- Deposit the required derived predictor rasters (`building_presence`, `building_height`, `ndvi`, `ndbi`) and large output rasters in Zenodo, Figshare, an institutional repository, or another data archive.
- Treat Sentinel-2 composite rasters (`*_s2*.tif`) and bulky downloaded GHS-UCDB source files (`GHS_UCDB_GLOBE_R2024A.gpkg`, `GHS_UCDB_GLOBE_R2024A.xlsx`) as optional provenance/source files rather than required inputs for the current R workflow.
- Add the data archive DOI or download URL to this README and, if needed, to the manuscript data availability statement.

## Reproducing the analysis

A typical rerun follows this order:

```r
source("Code/Base_models.R")
source("Code/City_similarity.R")
source("Code/Cross_Validation.R")
source("Code/Prediction.R")
source("Code/thresholds.R")
source("Code/slum_percentage.R")
source("Code/points_validation.R")
```

Figure scripts can be run after the model outputs and summary tables have been generated.

Because the repository contains large geospatial rasters and fitted model objects, users may not need to rerun every step. For many reuse cases, the most useful files are the probability rasters in `results/output_data/slum_probability/`, the calibrated thresholds in `results/output_data/thresholds_by_pop_share_country.csv`, and the validation summaries in `results/output_data/CrossValidation/`.

## Citation

If you use this repository, please cite the associated paper:

Zhang, W., Fang, W., Sorichetta, A., Nosatiuk, B., Priyatikanto, R., McKeen, T., Liang, L., Bondarenko, M., Lai, S., Espey, J., Atkinson, P. M., Tatem, A. J., & Tejedor-Garavito, N. Hidden and fragmented patterns of morphological informality across African cities revealed by open geospatial data.

## Contact

- Wenbin Zhang: wb.zhang@soton.ac.uk
