# Morphological informality in Africa

Data and code accompanying the paper:

**Hidden and fragmented patterns of morphological informality across African cities revealed by open geospatial data**

This repository shares the workflow, training data, fitted models, intermediate products, and outputs used to map morphological informality across African cities. The study develops a scalable remote-sensing framework that combines open satellite imagery, building datasets, manually labelled settlement polygons, city-specific random forest models, and an equal-weight cross-city ensemble to produce 10 m probability surfaces of morphologically informal settlements.

The outputs are intended to support reproducible analysis for the paper and to help other researchers inspect, reuse, or adapt the data and code for urban informality mapping.

## Study overview

Informal settlements are often spatially under-represented in official statistics and global urban datasets, especially when they occur as small or fragmented clusters embedded in otherwise formal neighbourhoods. This project maps the probability of morphological informality using built-environment and spectral indicators derived from open geospatial data.

The analysis:

- uses manually labelled informal and formal settlement polygons for eight African cities;
- trains city-specific random forest models using Sentinel-2, NDVI, NDBI, Google Open Buildings building presence, and building height predictors;
- transfers the city-specific models to other African cities using an equal-weight ensemble;
- generates 10 m informal-settlement probability maps and binary classifications;
- validates results using leave-one-city-out cross-validation, independent informal/formal reference points, and OpenAI-assisted visual settlement classification samples.

## Repository structure

```text
.
|-- Code/                    R scripts used for modelling, prediction, validation, and figures
|   |-- sensitivity/         Optional pooled-model and similarity-weighting analyses
|   `-- README.md            Production run order and helper-script notes
|-- data/
|   |-- city_boundary/       Urban centre boundaries, city points, and GHS-UCDB reference files
|   |-- input/               City-level raster predictor stacks
|   |-- training_labels/     Manual informal/formal settlement training polygons
|   `-- validation_sample_points_openAI.csv
|-- data_release/            Browsable country/city maps, raw output TIFFs, and label figures
|-- models/
|   `-- rf/                  Eight fitted city-specific Random Forest models
|-- results/
|   |-- output_data/         Current equal-weight outputs, validation summaries, and thresholds
|   |-- paper_figures/       Generated paper and supplementary figures
|   |-- sensitivity/         Optional model-comparison and weighting sensitivity analyses
|   |-- archive/             Dated superseded outputs; excluded from Git
|   |-- cache/               Regenerable analysis caches; excluded from Git
|   |-- logs/                Runtime logs; excluded from Git
|   `-- rf_figures/          Random forest diagnostic plots and variable-importance figures
`-- README.md
```

## Main data products

Required predictor rasters and the public probability release are managed through Git LFS. Bulky third-party downloads, working files, caches, and superseded outputs remain local and are excluded by `.gitignore`.

### Browsable country/city release

[`data_release/`](data_release/) organizes all 84 modelled cities first by country and then by city. Each city folder contains the raw 10 m probability GeoTIFF, a directly viewable PNG map using a common 0–1 colour scale, and raster metadata. [`data_release/city_index.csv`](data_release/city_index.csv) provides the complete inventory and relative paths.

Training-label provenance is kept separate under [`data_release/training_labels/`](data_release/training_labels/):

- `kyc_source/` contains normalized copies of the cleaned KnowYourCity community-mapped boundaries;
- `used_in_models/` contains the eight final formal/informal morphological label sets actually used for model fitting;
- each city folder includes a PNG figure so the spatial labels can be inspected without GIS software.

The release GeoTIFFs are stored with Git LFS. Run `git lfs install` before cloning or pulling the raster content.

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

The polygons operationalize image-observable **morphological informality**. They are guided by characteristics such as dense or irregular layouts, small and heterogeneous structures, limited vegetation and fragmented settlement edges; they are not direct labels of tenure, services, overcrowding or the complete UN-Habitat/SDG 11.1.1 household definition.

### Model outputs

`results/output_data/` includes:

- `slum_probability/`: 10 m ensemble probability rasters (`*_ensemble_prob.tif`);
- `CrossValidation/`: leave-one-city-out outputs, ROC plots, validation points, and model metrics;
- `probability_output_quality_assurance.csv`: completeness, geometry, and probability-range checks for all 84 rasters;
- `Table1_transferability.csv`: manuscript-ready leave-one-city-out performance table;
- `thresholds_by_pop_share_country.csv`: population-aligned and recalibrated country thresholds, uncertainty intervals, and provenance;
- `threshold_recalibration_metrics.csv`: apparent and leave-one-country-out recalibration diagnostics;
- `informality_share.csv`: city-level probability-bin summaries;
- `slum_analysis_results_openai.csv`: OpenAI-assisted validation results.

`models/rf/` contains the eight fitted random forest models (`.rds`). Legacy city-similarity files are retained only to reproduce the sensitivity analyses and are not used by the main equal-weight pipeline.

## Code workflow

The core scripts in `Code/` are:

1. `Base_models.R`
   Trains the eight city-specific random forest models from the manually labelled polygons and predictor rasters.

2. `Cross_Validation.R`
   Runs leave-one-city-out cross-validation for the equal-weight ensemble. The held-out city's own model is excluded.

3. `run_predictions_parallel.R` and `Prediction.R`
   Partition cities by raster size and generate equal-weight probabilities. For labelled cities, the city's own model is excluded; unlabelled cities use all eight donor models. `qa_probability_outputs.R` checks the finished surfaces.

4. `thresholds.R` and `City_threshold.R`
   Estimate population-aligned thresholds and apply a bounded one-parameter recalibration, with country-bootstrap intervals and leave-one-country-out diagnostics.

5. `slum_percentage.R`
   Aggregates probability outputs and derives city-level informality summaries.

6. `points_validation.R`
   Evaluates the probability maps against independent reference points and OpenAI-assisted visual classification outputs.

7. `Fig_transferability.R`, `spatial_heterogeneity.R`, `Fig4.R`, and `SI_A.R`
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

The R scripts source `Code/paths.R`, which finds the repository root automatically. Run scripts from the repository root so that both core and optional sensitivity scripts resolve paths consistently. Inputs and outputs use named project paths such as `data/input/`, `models/rf/`, and `results/output_data/`.

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

## Large files and publication

The repository stores only the explicitly allowlisted predictor and release GeoTIFFs with Git LFS. Other rasters, large GHS-UCDB downloads, generated paper figures, manuscript working files, caches, and local session artifacts are excluded with `.gitignore`.

Use `data_release/city_index.csv` as the public city-output inventory. Recommended publication pattern:

- Publish this GitHub repository for code, labels, fitted random forest models, summary tables, preview figures, and LFS-managed GeoTIFFs.
- Mirror the release in Zenodo, Figshare, an institutional repository, or another archival service when a citable DOI and long-term preservation are required.
- Treat Sentinel-2 composite rasters (`*_s2*.tif`) and bulky downloaded GHS-UCDB source files (`GHS_UCDB_GLOBE_R2024A.gpkg`, `GHS_UCDB_GLOBE_R2024A.xlsx`) as optional provenance/source files rather than required inputs for the current R workflow.
- Add the data archive DOI or download URL to this README and, if needed, to the manuscript data availability statement.

## Reproducing the analysis

A typical rerun follows this order:

```r
source("Code/Base_models.R")
source("Code/Cross_Validation.R")
source("Code/Prediction.R")
source("Code/thresholds.R")
source("Code/slum_percentage.R")
source("Code/points_validation.R")
```

Alternatively, `source("Code/run_analysis.R")` executes the complete production workflow with the existing fitted models, records the R session information, and refreshes the data manifest. Set `RETRAIN_MODELS=true` only if model retraining is required.

Figure scripts can be run after the model outputs and summary tables have been generated.

The main analysis does not require a city-similarity matrix. Scripts that compare pooled, equal-weight, and similarity-weighted alternatives are retained under `Code/sensitivity/` and are not part of the production run.

Because the repository contains large geospatial rasters and fitted model objects, users may not need to rerun every step. For many reuse cases, the most useful files are the probability rasters in `results/output_data/slum_probability/`, the calibrated thresholds in `results/output_data/thresholds_by_pop_share_country.csv`, and the validation summaries in `results/output_data/CrossValidation/`.

## Citation

If you use this repository, please cite the associated paper:

Zhang, W., Fang, W., Sorichetta, A., Nosatiuk, B., Priyatikanto, R., McKeen, T., Liang, L., Bondarenko, M., Lai, S., Espey, J., Atkinson, P. M., Tatem, A. J., & Tejedor-Garavito, N. Hidden and fragmented patterns of morphological informality across African cities revealed by open geospatial data.

## Contact

- Wenbin Zhang: wb.zhang@soton.ac.uk
