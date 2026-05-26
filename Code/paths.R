find_project_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)

  repeat {
    if (
      dir.exists(file.path(current, "Code")) &&
        dir.exists(file.path(current, "data")) &&
        dir.exists(file.path(current, "results"))
    ) {
      return(current)
    }

    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find project root. Run scripts from the repository root or from the Code directory.", call. = FALSE)
    }
    current <- parent
  }
}

project_root <- find_project_root()

project_path <- function(...) {
  file.path(project_root, ...)
}

ensure_dir <- function(...) {
  parts <- c(...)
  path <- if (length(parts) >= 1 && grepl("^([A-Za-z]:)?[\\/]", parts[[1]])) {
    do.call(file.path, as.list(parts))
  } else {
    project_path(...)
  }
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  path
}

project_setwd <- function() {
  setwd(project_root)
  invisible(project_root)
}

data_dir <- project_path("data")
input_data_dir <- project_path("data", "input")
city_boundary_dir <- project_path("data", "city_boundary")
training_labels_dir <- project_path("data", "training_labels")
validation_points_file <- project_path("data", "validation_sample_points_openAI.csv")

models_dir <- project_path("models")
rf_models_dir <- project_path("models", "rf")

results_dir <- project_path("results")
output_data_dir <- project_path("results", "output_data")
rf_figures_dir <- project_path("results", "rf_figures")
paper_figures_dir <- project_path("results", "paper_figures")
worldpop_root <- Sys.getenv("WORLDPOP_ROOT", unset = "")
worldpop_base_url <- Sys.getenv(
  "WORLDPOP_BASE_URL",
  unset = "https://worldpop-public-data.soton.ac.uk/GIS/Population/Global_2015_2030/R2025A/2023"
)

input_raster_path <- function(city_id, layer) {
  file.path(input_data_dir, city_id, paste0(city_id, "_", layer, ".tif"))
}

rf_model_path <- function(city_id) {
  file.path(rf_models_dir, paste0("model_", city_id, "_mask_before_predict.rds"))
}

rf_figure_path <- function(city_id, suffix) {
  file.path(rf_figures_dir, paste0("model_", city_id, "_", suffix, ".png"))
}

slum_probability_path <- function(city_id) {
  file.path(output_data_dir, "slum_probability", paste0(city_id, "_ensemble_prob.tif"))
}

self_probability_path <- function(city_id) {
  file.path(output_data_dir, "CrossValidation", "self", paste0(city_id, "_self_prob.tif"))
}

self_class_path <- function(city_id) {
  file.path(output_data_dir, "CrossValidation", "self", paste0(city_id, "_self_class.tif"))
}

cross_validation_path <- function(...) {
  file.path(output_data_dir, "CrossValidation", ...)
}

worldpop_population_path <- function(iso3) {
  if (nzchar(worldpop_root)) {
    local_dir <- file.path(worldpop_root, iso3, "v1", "100m", "constrained")
    local_files <- list.files(local_dir, pattern = "_pop_2023_CN_100m_R2025A_v1\\.tif$", full.names = TRUE)
    if (length(local_files) == 0) {
      stop("No WorldPop population raster found for ", iso3, " under ", local_dir, call. = FALSE)
    }
    return(local_files[[1]])
  }

  paste0(
    sub("/+$", "", worldpop_base_url),
    "/",
    iso3,
    "/v1/100m/constrained/",
    tolower(iso3),
    "_pop_2023_CN_100m_R2025A_v1.tif"
  )
}
