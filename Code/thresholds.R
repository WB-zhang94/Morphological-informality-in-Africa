library(terra)
library(countrycode)
library(readxl)
library(dplyr)
library(Metrics)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()
ensure_dir(output_data_dir)

# --- Input data ---
city_list  <- vect(c(
  vect(file.path(city_boundary_dir, "train_city_points.geojson")),
  vect(file.path(city_boundary_dir, "predict_city_points.geojson"))
))
city_masks <- vect(file.path(city_boundary_dir, "CityBoundary.geojson"))

city_df <- data.frame(
  index        = city_list$ID_UC_G0,
  city_name    = city_list$GC_UCN_MAI_2025,
  country_name = city_list$GC_CNT_GAD_2025
)
city_df$iso3 <- countrycode(city_df$country_name, origin = "country.name", destination = "iso3c")

pop_share <- read_xls(file.path(city_boundary_dir, "pop_share.xls"))

# --- Country-level threshold function ---
find_country_threshold <- function(iso3, ids, city_masks, target_pop) {
  message("Processing country: ", iso3)
  pop <- rast(worldpop_population_path(iso3))
  # storage lists
  pop_list <- list()
  settle_list <- list()
  total_pop <- 0
  # prepare city-specific rasters
  for (id in ids) {
    city_mask <- city_masks[city_masks$ID_UC_G0 %in% id]
    # population restricted to city
    pop_id <- crop(pop, city_mask)
    pop_id <- mask(pop_id, city_mask)
    pop_id <- sum(pop_id, na.rm = TRUE)
    pop_list[[as.character(id)]] <- pop_id
    # population count for this city
    total_pop_id <- global(pop_id, "sum", na.rm = TRUE)[1, 1]
    total_pop <- total_pop + total_pop_id
    # informal settlement map (10m → 100m → aligned)
    settle10 <- rast(slum_probability_path(id))
    settle100 <- aggregate(settle10, fact = 10, fun = mean, na.rm = TRUE)
    settle100 <- resample(settle100, pop_id, method = "bilinear")
    settle_list[[as.character(id)]] <- settle100
  }
  # search thresholds (loop over 0–1)
  thr_seq <- seq(0, 1, by = 0.01)
  est_share <- sapply(thr_seq, function(thr) {
    est_pop_country <- 0
    for (id in ids) {
      mask_r <- settle_list[[as.character(id)]] >= thr
      est_pop_id <- global(pop_list[[as.character(id)]] * mask_r, "sum", na.rm = TRUE)[1, 1]
      est_pop_country <- est_pop_country + est_pop_id
    }
    est_pop_country / total_pop * 100
  })
  best_thr <- thr_seq[which.min(abs(est_share - target_pop))]
  data.frame(
    iso3            = iso3,
    threshold       = best_thr,
    reported_share  = target_pop,
    estimated_share = est_share[thr_seq == best_thr]
  )
}

# --- Loop by country ---
results <- list()
countries <- unique(city_df$iso3)

for (i in seq_along(countries)) {
  iso3 <- countries[i]
  ids <- city_df$index[city_df$iso3 == iso3]
  target_pop <- pop_share$`2022`[pop_share$`Country Code` == iso3]
  
  if (length(ids) > 0 & length(target_pop) > 0) {
    results[[i]] <- find_country_threshold(iso3, ids, city_masks, target_pop)
  }
  
  message("Processed ", i, " / ", length(countries), " countries")
}

thresholds_country <- do.call(rbind, results)
thresholds_country <- thresholds_country %>%
  mutate(share_ratio = reported_share / estimated_share)

thresholds_calibration <- read.csv(cross_validation_path("ensemble_metrics_summary.csv"))
names(thresholds_calibration) <- c("id","Y","F1","AUC")
city_masks_df <- as.data.frame(city_masks) %>% select(ID_UC_G0,GC_UCN_MAI_2025,GC_CNT_GAD_2025,GC_UCA_KM2_2025,GC_POP_TOT_2025)
df <- thresholds_calibration %>%
  left_join(city_masks_df, by = c("id"="ID_UC_G0")) %>%
  group_by(GC_CNT_GAD_2025) %>%
  reframe(Y = weighted.mean(Y,GC_POP_TOT_2025),
          iso3 = countrycode(GC_CNT_GAD_2025, origin = "country.name", destination = "iso3c")) %>%
  left_join(thresholds_country, by = "iso3")
# Logistic models
sigma <- function(x) 1 / (1 + exp(-x))
mc <- nls(Y ~ threshold + (1 - threshold) * sigma(a + b1*reported_share + b2*estimated_share + b3*share_ratio),
          data = df, start = list(a=0, b1=0, b2 = 0, b3 = 0))
# Evaluation helper
eval_logistic <- function(fit, name) {
  preds <- predict(fit, newdata = df)
  data.frame(
    Model = name,
    R2 = cor(df$Y, preds)^2,
    RMSE = rmse(df$Y, preds),
    MAE = mae(df$Y, preds),
    AIC = AIC(fit),
    BIC = BIC(fit)
  )
}

eval_logistic(mc, "C1: ratio")

thresholds_country$threshold_updated <- predict(mc, newdata = thresholds_country)

library(ggplot2)
library(ggrepel)

# --- Predictions for calibration set ---
df$pred <- predict(mc, newdata = df)

p1 <- ggplot(df, aes(x = Y, y = pred, label = iso3)) +
  geom_point(color = "steelblue", size = 3) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray40") +
  geom_text(vjust = -0.8, size = 3) +
  labs(x = "Calibrated thresholds",
       y = "Predicted thresholds",
       title = "a. Model Fitting") +
  theme_minimal(base_size = 13)

# --- Thresholds before vs after update ---
p2 <- ggplot(thresholds_country,
             aes(x = threshold, y = threshold_updated, label = iso3)) +
  geom_point(color = "darkred", size = 3) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray40") +
  geom_text_repel(size = 3, max.overlaps = 20, box.padding = 0.3) +
  labs(x = "Estimated Threshold",
       y = "Updated Threshold",
       title = "b. Country-level Thresholds: Before vs After Update") +
  theme_minimal(base_size = 13)

# Combine if you want side-by-side
library(patchwork)
combined_plot <- p1 + p2

ensure_dir(paper_figures_dir)
ggsave(file.path(paper_figures_dir, "thresholds_calibration.png"),
       combined_plot, width = 12, height = 6, dpi = 900)
write.csv(thresholds_country,
          file.path(output_data_dir, "thresholds_by_pop_share_country.csv"),
          row.names = FALSE)
