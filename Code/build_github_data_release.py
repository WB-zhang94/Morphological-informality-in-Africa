"""Build the public, browsable data release for GitHub.

The script does not delete source data. Probability GeoTIFFs are hard-linked when
possible (and copied as a fallback), so the release tree can coexist with the
analysis outputs without unnecessarily duplicating local disk usage.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import unicodedata
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import rasterio
import shapefile
from matplotlib.lines import Line2D
from rasterio.enums import Resampling
from shapely.geometry import shape


ROOT = Path(__file__).resolve().parents[1]
CITY_LIST = ROOT / "models" / "rf" / "city_list.csv"
PROBABILITY_DIR = ROOT / "results" / "output_data" / "slum_probability"
PREDICTOR_DIR = ROOT / "data" / "input"
MODEL_LABEL_DIR = ROOT / "data" / "training_labels"
KYC_DIR = ROOT / "data" / "KnowYourCity-data-for-research-main"
RELEASE_DIR = ROOT / "data_release"


def slug(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(char for char in value if not unicodedata.combining(char))
    value = value.lower().replace("&", " and ")
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value


def link_or_copy(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if target.stat().st_size != source.stat().st_size:
            raise RuntimeError(f"Existing file differs in size: {target}")
        return
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)


def sampled_raster(path: Path, max_dimension: int = 1600):
    with rasterio.open(path) as dataset:
        scale = min(1.0, max_dimension / max(dataset.width, dataset.height))
        width = max(1, round(dataset.width * scale))
        height = max(1, round(dataset.height * scale))
        data = dataset.read(
            1,
            out_shape=(height, width),
            masked=True,
            resampling=Resampling.bilinear,
        )
        extent = (
            dataset.bounds.left,
            dataset.bounds.right,
            dataset.bounds.bottom,
            dataset.bounds.top,
        )
        metadata = {
            "crs": str(dataset.crs),
            "width": dataset.width,
            "height": dataset.height,
            "left": dataset.bounds.left,
            "bottom": dataset.bounds.bottom,
            "right": dataset.bounds.right,
            "top": dataset.bounds.top,
            "dtype": dataset.dtypes[0],
            "nodata": None if dataset.nodata is None or np.isnan(dataset.nodata) else dataset.nodata,
        }
    return data, extent, metadata


def save_probability_preview(source: Path, target: Path, city: str, country: str, city_id: str) -> dict:
    data, extent, metadata = sampled_raster(source)
    finite = np.asarray(data.compressed(), dtype=float)
    metadata["sample_min"] = float(finite.min())
    metadata["sample_max"] = float(finite.max())

    fig, ax = plt.subplots(figsize=(8.4, 7.2), constrained_layout=True)
    image = ax.imshow(data, extent=extent, origin="upper", cmap="magma", vmin=0, vmax=1)
    colorbar = fig.colorbar(image, ax=ax, shrink=0.82, pad=0.025)
    colorbar.set_label("Morphological informality probability")
    fig.suptitle(f"{city}, {country}", x=0.08, ha="left", fontsize=15, fontweight="bold")
    ax.set_title(f"GHS Urban Centre ID: {city_id}", loc="left", fontsize=9, color="#555555", pad=6)
    ax.set_xlabel("Longitude")
    ax.set_ylabel("Latitude")
    ax.ticklabel_format(useOffset=False)
    target.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(target, dpi=180, facecolor="white")
    plt.close(fig)
    return metadata


def geojson_geometries(path: Path, class_field: bool = False):
    document = json.loads(path.read_text(encoding="utf-8"))
    output = []
    for feature in document["features"]:
        geometry = shape(feature["geometry"])
        class_value = feature.get("properties", {}).get("class") if class_field else None
        output.append((geometry, class_value))
    return output


def shapefile_to_geojson(source: Path, target: Path):
    reader = shapefile.Reader(str(source), encoding="utf-8", encodingErrors="replace")
    fields = [field[0] for field in reader.fields[1:]]
    features = []
    for record in reader.iterShapeRecords():
        properties = {key: value for key, value in zip(fields, record.record)}
        features.append(
            {
                "type": "Feature",
                "properties": properties,
                "geometry": record.shape.__geo_interface__,
            }
        )
    collection = {
        "type": "FeatureCollection",
        "name": "kyc_cleaned_settlements",
        "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:OGC:1.3:CRS84"}},
        "features": features,
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(collection, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return [(shape(feature["geometry"]), None) for feature in features]


def polygon_parts(geometry):
    if geometry.geom_type == "Polygon":
        yield geometry
    elif geometry.geom_type == "MultiPolygon":
        yield from geometry.geoms


def draw_geometry(ax, geometry, *, edgecolor, facecolor="none", linewidth=1.0, alpha=1.0, zorder=2):
    for polygon in polygon_parts(geometry):
        x, y = polygon.exterior.xy
        ax.fill(x, y, edgecolor=edgecolor, facecolor=facecolor, linewidth=linewidth, alpha=alpha, zorder=zorder)


def save_label_preview(
    target: Path,
    background_path: Path,
    city: str,
    country: str,
    city_id: str,
    kyc_geometries,
    model_geometries=None,
):
    background, extent, _ = sampled_raster(background_path)
    values = np.asarray(background.compressed(), dtype=float)
    upper = float(np.nanpercentile(values, 99)) if values.size else 1.0
    if not np.isfinite(upper) or upper <= 0:
        upper = 1.0

    fig, ax = plt.subplots(figsize=(8.4, 7.2), constrained_layout=True)
    ax.imshow(background, extent=extent, origin="upper", cmap="Greys", vmin=0, vmax=upper, alpha=0.72)
    kyc_colour = "#FFD400"
    for geometry, _ in kyc_geometries:
        draw_geometry(ax, geometry, edgecolor=kyc_colour, linewidth=1.6, alpha=0.95, zorder=2)

    legend = [Line2D([0], [0], color=kyc_colour, lw=2.5, label="KYC cleaned settlement boundary")]
    title_prefix = "KYC source labels"
    if model_geometries is not None:
        for geometry, class_value in model_geometries:
            if int(class_value) == 1:
                draw_geometry(ax, geometry, edgecolor="#0571b0", facecolor="#92c5de", linewidth=1.2, alpha=0.62, zorder=4)
            elif int(class_value) == -1:
                draw_geometry(ax, geometry, edgecolor="#ca0020", facecolor="#f4a582", linewidth=1.2, alpha=0.62, zorder=3)
        legend.extend(
            [
                Line2D([0], [0], color="#0571b0", lw=5, alpha=0.7, label="Used label: informal morphology (+1)"),
                Line2D([0], [0], color="#ca0020", lw=5, alpha=0.7, label="Used label: formal morphology (-1)"),
            ]
        )
        title_prefix = "Training labels used in the model"

    fig.suptitle(
        f"{title_prefix}: {city}, {country}",
        x=0.06,
        ha="left",
        fontsize=14,
        fontweight="bold",
    )
    ax.set_title(f"GHS Urban Centre ID: {city_id}", loc="left", fontsize=9, color="#555555", pad=6)
    ax.legend(handles=legend, loc="lower left", frameon=True, framealpha=0.92, fontsize=8)
    ax.set_xlabel("Longitude")
    ax.set_ylabel("Latitude")
    ax.ticklabel_format(useOffset=False)
    target.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(target, dpi=180, facecolor="white")
    plt.close(fig)


def find_kyc_directory(city: str, country: str) -> Path:
    wanted = slug(city + " " + country).replace("-", "")
    candidates = [path for path in KYC_DIR.glob("kyc_cln_data_*") if path.is_dir()]
    for candidate in candidates:
        candidate_key = slug(candidate.name.removeprefix("kyc_cln_data_")).replace("-", "")
        if candidate_key == wanted:
            return candidate
    raise FileNotFoundError(f"No cleaned KYC folder found for {city}, {country}")


def find_model_label(city_id: str) -> Path:
    matches = list(MODEL_LABEL_DIR.glob(f"Training_polygons_*_{city_id}.geojson"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one model-label file for city {city_id}; found {len(matches)}")
    return matches[0]


def write_readmes():
    (RELEASE_DIR / "README.md").write_text(
        "# Data release\n\n"
        "This directory provides a browsable release of the model outputs and training labels.\n\n"
        "- `city_probability_maps/<country>/<city>_<id>/` contains the raw 10 m GeoTIFF "
        "(`morphological_informality_probability.tif`), a PNG visualization with a fixed 0–1 "
        "colour scale (`map_preview.png`), and machine-readable raster metadata.\n"
        "- `training_labels/kyc_source/` contains normalized GeoJSON copies of the cleaned "
        "KnowYourCity (KYC) community-mapped settlement boundaries used as source evidence.\n"
        "- `training_labels/used_in_models/` contains the separate formal/informal morphology "
        "GeoJSON samples used to fit the eight city-specific models. Each folder includes a map "
        "that overlays the final labels on the cleaned KYC boundaries.\n"
        "- `city_index.csv` is the complete city/country/path inventory.\n\n"
        "Regenerate the package from the repository root with "
        "`python Code/build_github_data_release.py`. The builder never deletes source data.\n\n"
        "GeoTIFFs are stored with Git LFS. Clone with Git LFS enabled to retrieve raster content.\n",
        encoding="utf-8",
    )
    labels = RELEASE_DIR / "training_labels"
    labels.mkdir(parents=True, exist_ok=True)
    (labels / "README.md").write_text(
        "# Training labels\n\n"
        "The two subdirectories intentionally separate provenance from the labels fitted by the models.\n\n"
        "- `kyc_source/`: cleaned KnowYourCity settlement boundaries, normalized to GeoJSON from "
        "the source shapefiles. These are community-mapped informal-settlement boundaries.\n"
        "- `used_in_models/`: the study's final morphological training polygons. In these files, "
        "`class = 1` denotes informal morphology and `class = -1` denotes formal morphology.\n\n"
        "The final model labels are a training sample rather than a replacement or exhaustive copy "
        "of KYC. Please cite: Slum Dwellers International Profiling Teams (2022), *KnowYourCity "
        "data for research*, processed by Dana R. Thomson and Hazem Mahmoud, "
        "https://github.com/hazemmahmoud88/KnowYourCity-data-for-research.\n",
        encoding="utf-8",
    )


def build() -> None:
    RELEASE_DIR.mkdir(parents=True, exist_ok=True)
    write_readmes()
    with CITY_LIST.open(newline="", encoding="utf-8-sig") as source:
        cities = list(csv.DictReader(source))

    index_rows = []
    training_ids = {
        path.stem.rsplit("_", 1)[-1]
        for path in MODEL_LABEL_DIR.glob("Training_polygons_*.geojson")
    }
    for number, row in enumerate(cities, start=1):
        city_id = row["ID_UC_G0"]
        city = row["GC_UCN_MAI_2025"]
        country = row["GC_CNT_GAD_2025"]
        folder = f"{slug(city)}_{city_id}"
        probability_source = PROBABILITY_DIR / f"{city_id}_ensemble_prob.tif"
        if not probability_source.exists():
            raise FileNotFoundError(probability_source)

        relative_city_dir = Path("city_probability_maps") / slug(country) / folder
        city_dir = RELEASE_DIR / relative_city_dir
        probability_target = city_dir / "morphological_informality_probability.tif"
        preview_target = city_dir / "map_preview.png"
        metadata_target = city_dir / "raster_metadata.json"
        link_or_copy(probability_source, probability_target)
        metadata = save_probability_preview(probability_source, preview_target, city, country, city_id)
        metadata.update({"city_id": city_id, "city": city, "country": country, "value_range": [0, 1]})
        metadata_target.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        index_rows.append(
            {
                "city_id": city_id,
                "city": city,
                "country": country,
                "probability_tif": (relative_city_dir / probability_target.name).as_posix(),
                "map_preview": (relative_city_dir / preview_target.name).as_posix(),
                "is_training_city": str(city_id in training_ids).lower(),
            }
        )
        print(f"[{number:02d}/{len(cities)}] {country} / {city}", flush=True)

    with (RELEASE_DIR / "city_index.csv").open("w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=index_rows[0].keys())
        writer.writeheader()
        writer.writerows(index_rows)

    training_rows = [row for row in cities if row["ID_UC_G0"] in training_ids]
    for number, row in enumerate(training_rows, start=1):
        city_id = row["ID_UC_G0"]
        city = row["GC_UCN_MAI_2025"]
        country = row["GC_CNT_GAD_2025"]
        folder = f"{slug(city)}_{city_id}"
        country_folder = slug(country)
        background = PREDICTOR_DIR / city_id / f"{city_id}_building_presence.tif"

        kyc_directory = find_kyc_directory(city, country)
        shapefiles = list(kyc_directory.glob("*.shp"))
        if len(shapefiles) != 1:
            raise RuntimeError(f"Expected one KYC shapefile in {kyc_directory}; found {len(shapefiles)}")
        kyc_target_dir = RELEASE_DIR / "training_labels" / "kyc_source" / country_folder / folder
        kyc_target = kyc_target_dir / "kyc_cleaned_settlements.geojson"
        kyc_geometries = shapefile_to_geojson(shapefiles[0], kyc_target)
        save_label_preview(
            kyc_target_dir / "map_preview.png",
            background,
            city,
            country,
            city_id,
            kyc_geometries,
        )

        model_source = find_model_label(city_id)
        model_target_dir = RELEASE_DIR / "training_labels" / "used_in_models" / country_folder / folder
        model_target = model_target_dir / "training_labels.geojson"
        model_target_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(model_source, model_target)
        model_geometries = geojson_geometries(model_target, class_field=True)
        save_label_preview(
            model_target_dir / "map_preview.png",
            background,
            city,
            country,
            city_id,
            kyc_geometries,
            model_geometries,
        )
        print(f"[labels {number:02d}/{len(training_rows)}] {country} / {city}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    build()


if __name__ == "__main__":
    main()
