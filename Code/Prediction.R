library(terra)
library(randomForest)
library(dplyr)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()

# Load city list and RF models
ref_cities <- sub(".*_([0-9]+)\\.geojson$", "\\1", list.files(training_labels_dir, pattern = "\\.geojson$"))
city_similarity <- read.csv(file.path(rf_models_dir, "similarity.csv"))
df_self <- read.csv(file.path(output_data_dir, "CrossValidation", "self_metrics_summary.csv"))
df_ensemble <- read.csv(file.path(output_data_dir, "CrossValidation", "ensemble_metrics_summary.csv"))
ensure_dir(output_data_dir, "slum_probability")

df <- data.frame(id = df_self$city)
df$self <- df_self$threshold[match(df$id, df_self$city)]
df$ensemble <- df_ensemble$threshold[match(df$id, df_ensemble$city)]
df$x47 <- city_similarity$X47[match(df$id, city_similarity$X)]
df$X431 <- city_similarity$X431[match(df$id, city_similarity$X)]
df$X1289 <- city_similarity$X1289[match(df$id, city_similarity$X)]
df$X1711 <- city_similarity$X1711[match(df$id, city_similarity$X)]
df$X1717 <- city_similarity$X1717[match(df$id, city_similarity$X)]
df$X3175 <- city_similarity$X3175[match(df$id, city_similarity$X)]
df$X3570 <- city_similarity$X3570[match(df$id, city_similarity$X)]
df$X7209 <- city_similarity$X7209[match(df$id, city_similarity$X)]
df[] <- lapply(df, function(x) {
  if (is.numeric(x)) x[is.infinite(x)] <- NA
  return(x)
})

index <- which(city_similarity$X %in% ref_cities)
city_list <- city_similarity$X[-index]

RF_models <- list(
  X47 = readRDS(rf_model_path("47")),
  X431 = readRDS(rf_model_path("431")),
  X1289 = readRDS(rf_model_path("1289")),
  X1711 = readRDS(rf_model_path("1711")),
  X1717 = readRDS(rf_model_path("1717")),
  X3175 = readRDS(rf_model_path("3175")),
  X3570 = readRDS(rf_model_path("3570")),
  X7209 = readRDS(rf_model_path("7209"))
)

for (i in seq_along(city_list)) {
  index <- city_list[i]
  cat("\nProcessing city", i, "of", length(city_list), "\n")
  # Load covariates
  Buildings_presence <- rast(input_raster_path(index, "building_presence"))
  Building_height <- rast(input_raster_path(index, "building_height"))
  NDVI <- rast(input_raster_path(index, "ndvi"))
  NDBI <- rast(input_raster_path(index, "ndbi"))
  city_mask <- Buildings_presence > 0
  win <- matrix(1, 13, 13)
  breaks <- seq(0, 100, length.out = 11)
  Buildings_presence_bins <- lapply(seq_len(length(breaks) - 1), function(i) {
    m <- (Buildings_presence >= breaks[i]) & (Buildings_presence < breaks[i + 1])
    focal(m, w = win, fun = sum, na.rm = TRUE, na.policy = "omit")
  })
  Buildings_presence_bins <- rast(Buildings_presence_bins)
  names(Buildings_presence_bins) <- paste0("Building_Presence_", sprintf("%.1f", breaks[-length(breaks)]))
  # Additional covariate stats
  Building_height_cv <- focal(Building_height, w = win, fun = var, na.rm = TRUE) /
    (focal(Building_height, w = win, fun = mean, na.rm = TRUE) + 1e-6)
  NDVI_cv <- focal(NDVI, w = win, fun = var, na.rm = TRUE) /
    (focal(NDVI, w = win, fun = mean, na.rm = TRUE) + 1e-6)
  NDBI_cv <- focal(NDBI, w = win, fun = var, na.rm = TRUE) /
    (focal(NDBI, w = win, fun = mean, na.rm = TRUE) + 1e-6)
  names(Building_height) <- "Building_Height"
  names(Building_height_cv) <- "Building_Height_CV"
  names(NDVI) <- "NDVI"
  names(NDVI_cv) <- "NDVI_CV"
  names(NDBI) <- "NDBI"
  names(NDBI_cv) <- "NDBI_CV"
  X <- c(Buildings_presence_bins, Building_height, Building_height_cv, NDVI, NDVI_cv, NDBI, NDBI_cv)
  X <- mask(X, city_mask, maskvalues = FALSE)
  # Get similarity weights
  city_row <- city_similarity[city_similarity$X == as.numeric(index), ]
  sim_vals <- as.numeric(city_row[-1])
  names(sim_vals) <- names(city_row)[-1]
  # Remove self and infinite
  valid_idx <- which(is.finite(sim_vals))
  sim_vals <- sim_vals[valid_idx]
  softmax <- function(x, temp) {
    exps <- exp(x / temp - max(x / temp))  # keep high similarities = higher weight
    exps / sum(exps)
  }
  weights <- softmax(sim_vals, temp = 0.8)
  # Weighted prediction
  pred_stack <- list()
  k <- 1
  for (model_name in names(weights)) {
    rf_mod <- RF_models[[model_name]]
    pred <- predict(X, rf_mod, type = "prob", index = 2)  # class = 1 prob
    pred_stack[[k]] <- pred * weights[[model_name]]
    k <- k + 1
  }
  pred_total <- Reduce(`+`, pred_stack)
  names(pred_total) <- "slum_prob"
  # Save prediction
  writeRaster(
    pred_total,
    file.path(output_data_dir, "slum_probability", paste0(index, "_ensemble_prob.tif")),
    overwrite = TRUE
  )
  gc()
}
