library(terra)
library(pROC)
library(MLmetrics)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()

# Load city list and RF models
slums_labels_training_data <- list.files(training_labels_dir, pattern = "\\.geojson$")
total_cities <- length(slums_labels_training_data)
ensure_dir(output_data_dir, "CrossValidation")
ensure_dir(output_data_dir, "CrossValidation", "self")
slums_probs <- list(
  X47 = rast(self_probability_path("47")),
  X431 = rast(self_probability_path("431")),
  X1289 = rast(self_probability_path("1289")),
  X1711 = rast(self_probability_path("1711")),
  X1717 = rast(self_probability_path("1717")),
  X3175 = rast(self_probability_path("3175")),
  X3570 = rast(self_probability_path("3570")),
  X7209 = rast(self_probability_path("7209"))
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
  
  prob_raster <- slums_probs[[paste0("X", index)]]
  slum_prob <- if (nlyr(prob_raster) >= 2) prob_raster[[2]] else prob_raster[[1]]

  Ref_vector <- vect(file.path(training_labels_dir, cities))
  
  gt_raster <- rasterize(Ref_vector, slum_prob, field = "class", touches = TRUE)
  
  gt_vals <- values(gt_raster)
  pred_vals <- values(slum_prob)
  
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
  pred_class <- terra::ifel(slum_prob >= opt_thresh_f1, 1, 0)
  
  F1_opt <- max(f1s,na.rm=TRUE)
  results_df <- rbind(results_df, data.frame(
    city = index,
    threshold = opt_thresh_f1,
    F1 = F1_opt,
    AUC = as.numeric(auc(roc_obj))
  ))
  
  png(filename = cross_validation_path("self", paste0("ROC_City_", index, "_self.png")), width = 450, height = 450)
  plot(roc_obj, main = paste("ROC Curve for City", index), legacy.axes = TRUE)
  abline(a = 0, b = 1, lty = 2, col = "gray")
  dev.off()
  
  # Save prediction
  writeRaster(
    pred_class,
    self_class_path(index),
    overwrite = TRUE
  )
  
  gc()
}
write.csv(results_df, cross_validation_path("self_metrics_summary.csv"), row.names = FALSE)
