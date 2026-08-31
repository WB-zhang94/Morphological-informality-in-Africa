# Training labels

The two subdirectories intentionally separate provenance from the labels fitted by the models.

- `kyc_source/`: cleaned KnowYourCity settlement boundaries, normalized to GeoJSON from the source shapefiles. These are community-mapped informal-settlement boundaries.
- `used_in_models/`: the study's final morphological training polygons. In these files, `class = 1` denotes informal morphology and `class = -1` denotes formal morphology.

The final model labels are a training sample rather than a replacement or exhaustive copy of KYC. Please cite: Slum Dwellers International Profiling Teams (2022), *KnowYourCity data for research*, processed by Dana R. Thomson and Hazem Mahmoud, https://github.com/hazemmahmoud88/KnowYourCity-data-for-research.
