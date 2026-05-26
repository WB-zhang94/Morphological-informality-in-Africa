# Results Directory

This directory contains model outputs and validation products.

Large raster outputs are intentionally excluded from Git:

- `results/output_data/slum_probability/*.tif`
- `results/output_data/slum_percentage_1km/**/*.tif`
- `results/output_data/slum_class/*.tif`
- cross-validation probability/classification rasters

Small CSV summaries and validation tables can be committed to GitHub. Large rasters should be published through a data repository or release asset storage and documented in `data_manifest.csv`.

