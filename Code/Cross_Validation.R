library(terra)
library(randomForest)
library(pROC)
library(MLmetrics)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()

# Load city list and RF models
slums_labels_training_data <- list.files(training_labels_dir, pattern = "\\.geojson$")
total_cities <- length(slums_labels_training_data)
city_similarity <- read.csv(file.path(rf_models_dir, "similarity.csv"))
ensure_dir(output_data_dir, "CrossValidation")
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

# Loop through cities
results_df <- data.frame(
  city = character(),
  threshold = numeric(),
  F1 = numeric(),
  AUC = numeric(),
  stringsAsFactors = FALSE
)

for (i in seq_along(slums_labels_training_data)) {
  cities <- slums_labels_training_data[i]
  cat("\nProcessing city", i, "of", total_cities, ":", cities, "\n")
  index <- sub(".*_([0-9]+)\\.geojson$", "\\1", cities)
  
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
  
  # Ground truth for AUC calculation
  train_vector <- vect(file.path(training_labels_dir, cities))
  gt_raster <- rasterize(train_vector, Buildings_presence, field = "class", touches = TRUE)
  gt_vals <- values(gt_raster)
  pred_vals <- values(pred_total)
  
  valid <- which(!is.na(gt_vals) & !is.na(pred_vals))
  y_true <- ifelse(gt_vals[valid] == -1, 0, 1)
  y_pred <- pred_vals[valid]
  
  # Compute AUC
  roc_obj <- roc(y_true, y_pred)
  all_coords <- coords(roc_obj, "all", ret = c("threshold"), transpose = FALSE)
  f1s <- sapply(all_coords$threshold, function(t) {
    pred_bin <- ifelse(y_pred >= t, 1, 0)
    F1_Score(y_true, pred_bin, positive = "1")
  })
  opt_thresh_f1 <- all_coords$threshold[which.max(f1s)]
  pred_class <- terra::ifel(pred_total >= opt_thresh_f1, 1, 0)
  
  F1_opt <- max(f1s,na.rm=TRUE)
  results_df <- rbind(results_df, data.frame(
    city = index,
    threshold = opt_thresh_f1,
    F1 = F1_opt,
    AUC = as.numeric(auc(roc_obj))
  ))
  
  png(filename = file.path(output_data_dir, "CrossValidation", paste0("ROC_City_", index, ".png")), width = 450, height = 450)
  plot(roc_obj, main = paste("ROC Curve for City", index), legacy.axes = TRUE)
  abline(a = 0, b = 1, lty = 2, col = "gray")
  dev.off()
  
  # Save prediction
  writeRaster(
    pred_total,
    file.path(output_data_dir, "CrossValidation", paste0(index, "_ensemble_prob.tif")),
    overwrite = TRUE
  )
  writeRaster(
    pred_class,
    file.path(output_data_dir, "CrossValidation", paste0(index, "_ensemble_class.tif")),
    overwrite = TRUE
  )
  
  gc()
}
write.csv(results_df, file.path(output_data_dir, "CrossValidation", "ensemble_metrics_summary.csv"), row.names = FALSE)
