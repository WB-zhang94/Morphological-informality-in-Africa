library(terra)
library(randomForest)
library(pROC)
library(MLmetrics)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()

# slum label data
slums_labels_training_data <- list.files(training_labels_dir, pattern = "\\.geojson$")
ensure_dir(rf_models_dir)
ensure_dir(rf_figures_dir)
ensure_dir(output_data_dir, "CrossValidation", "self")

# RF models
total_cities <- length(slums_labels_training_data)
i=1
for (cities in slums_labels_training_data) {
  cat("\nProcessing city", i, "of", total_cities, ":", cities, "\n")
  cat(total_cities - i, "cities remaining...\n")
  index <- sub(".*_([0-9]+)\\.geojson$", "\\1", cities)
  Buildings_presence <- rast(input_raster_path(index, "building_presence"))
  Building_height <- rast(input_raster_path(index, "building_height"))
  NDVI <- rast(input_raster_path(index, "ndvi"))
  NDBI <- rast(input_raster_path(index, "ndbi"))
  city_mask <- Buildings_presence > 0
  win <- matrix(1, 13, 13)
  breaks <- seq(0, 100, length.out = 11)
  # Focal bins
  Buildings_presence_bins <- lapply(seq_len(length(breaks) - 1), function(j) {
    low  <- breaks[j]
    high <- breaks[j+1]
    m <- (Buildings_presence >= low) & (Buildings_presence < high)
    focal(m, w = win, fun = sum, na.rm = TRUE, na.policy = "omit")
  })
  Buildings_presence_bins <- rast(Buildings_presence_bins)
  names(Buildings_presence_bins) <- paste0("Building_Presence_", sprintf("%.1f", breaks[-length(breaks)]))
  # Height / NDVI / NDBI stats
  Building_height_v <- focal(Building_height, w = win, fun = var, na.rm = TRUE)
  Building_height_m <- focal(Building_height, w = win, fun = mean, na.rm = TRUE)
  Building_height_cv <- Building_height_v / (Building_height_m + 1e-6)
  names(Building_height_cv) <- "Building_Height_CV"
  names(Building_height) <- "Building_Height"
  NDVI_v <- focal(NDVI, w = win, fun = var, na.rm = TRUE)
  NDVI_m <- focal(NDVI, w = win, fun = mean, na.rm = TRUE)
  NDVI_cv <- NDVI_v / (NDVI_m + 1e-6)
  names(NDVI_cv) <- "NDVI_CV"
  names(NDVI) <- "NDVI"
  NDBI_v <- focal(NDBI, w = win, fun = var, na.rm = TRUE)
  NDBI_m <- focal(NDBI, w = win, fun = mean, na.rm = TRUE)
  NDBI_cv <- NDBI_v / (NDBI_m + 1e-6)
  names(NDBI_cv) <- "NDBI_CV"
  names(NDBI) <- "NDBI"
  X <- c(Buildings_presence_bins, Building_height, Building_height_cv, NDVI, NDVI_cv, NDBI, NDBI_cv)
  train_vector <- vect(file.path(training_labels_dir, cities))
  output_raster <- rasterize(train_vector, Buildings_presence, field = "class", touches = TRUE)
  train_df <- as.data.frame(c(output_raster, X), na.rm = TRUE)
  train_df$class <- factor(ifelse(train_df$class == -1, "non_slum", "slum"))
  rf_mod <- randomForest(class ~ ., data = train_df, importance = TRUE, ntree = 299)
  # Save model
  saveRDS(rf_mod, file = rf_model_path(index))
  # Save plots
  png(rf_figure_path(index, "importance_mask_before_predict"), width = 1000, height = 800)
  varImpPlot(rf_mod, main = paste0("Variable Importance - City ", index))
  dev.off()
  png(rf_figure_path(index, "error_mask_before_predict"), width = 800, height = 600)
  plot(rf_mod, main = paste0("OOB Error - City ", index))
  legend("topright", legend = colnames(rf_mod$err.rate),
         col = 1:ncol(rf_mod$err.rate), lty = 1, cex = 0.8)
  dev.off()
  # Predict
  X <- mask(X,city_mask, maskvalues = FALSE)
  terra::predict(
    X,
    rf_mod,
    type = "prob",
    filename = file.path(output_data_dir, "CrossValidation", "self", paste0(index, "_self_prob.tif")),
    overwrite = TRUE
  )
  i=i+1
  gc()
}







