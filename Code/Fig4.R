# ============================================================
# Fig 4 : cleaner code + clearer, more elegant figure
#   a) RF feature-importance heatmap (top, full width)
#   b) Calibrated vs updated thresholds (bottom-left, top)
#   c) Estimated vs updated thresholds (bottom-left, bottom)
#   d) Δ-threshold map (bottom-right, wider)
#
# Notes:
# - No recomputation: reads threshold_updated from CSV
# - Makes b/c rectangular via coord_fixed()
# - Uses a compact, consistent "Nature-ish" theme
# - Uses patchwork design to guarantee bottom width ratio
# ============================================================

library(terra)
library(dplyr)
library(ggplot2)
library(patchwork)
library(sf)
library(rnaturalearth)
library(rnaturalearthdata)
library(countrycode)
library(ggrepel)
library(randomForest)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()
ensure_dir(paper_figures_dir)

# -----------------------------
# A) Feature importance heatmap
# -----------------------------
model_files <- list.files(rf_models_dir, pattern = "_mask_before_predict.rds$", full.names = TRUE)
model_ids   <- gsub(".*model_([0-9]+)_mask_before_predict.rds$", "\\1", model_files)

rf_df <- bind_rows(lapply(seq_along(model_files), function(i) {
  rf_mod <- readRDS(model_files[i])
  imp <- randomForest::importance(rf_mod)[, 1]  # %IncMSE
  tibble(
    City          = as.character(model_ids[i]),
    Variable      = names(imp),
    RF_importance = as.numeric(imp)
  )
})) %>%
  group_by(City) %>%
  mutate(RF_importance = RF_importance / max(RF_importance, na.rm = TRUE)) %>%
  ungroup()

cities <- vect(file.path(city_boundary_dir, "train_city_points.geojson"))
city_meta <- as.data.frame(cities)[, c("ID_UC_G0", "GC_UCN_MAI_2025", "GC_DEV_WIG_2025")]
names(city_meta) <- c("City", "CityName", "DevGroup")
city_meta$City <- as.character(city_meta$City)

rf_df <- rf_df %>%
  left_join(city_meta, by = "City")

var_labels <- c(
  "NDBI_CV"               = "NDBI variability",
  "NDBI"                  = "NDBI",
  "NDVI_CV"               = "NDVI variability",
  "NDVI"                  = "NDVI",
  "Building_Height_CV"    = "Building height (CV)",
  "Building_Height"       = "Building height (mean)",
  "Building_Presence_90.0"= "Building presence (90–100%)",
  "Building_Presence_80.0"= "Building presence (80–90%)",
  "Building_Presence_70.0"= "Building presence (70–80%)",
  "Building_Presence_60.0"= "Building presence (60–70%)",
  "Building_Presence_50.0"= "Building presence (50–60%)",
  "Building_Presence_40.0"= "Building presence (40–50%)",
  "Building_Presence_30.0"= "Building presence (30–40%)",
  "Building_Presence_20.0"= "Building presence (20–30%)",
  "Building_Presence_10.0"= "Building presence (10–20%)",
  "Building_Presence_0.0" = "Building presence (0–10%)"
)

# keep only known vars + enforce order (top-to-bottom exactly as above)
rf_df <- rf_df %>% filter(Variable %in% names(var_labels))
rf_df$Variable <- factor(rf_df$Variable, levels = names(var_labels), labels = unname(var_labels))

# order cities within DevGroup
city_order <- rf_df %>%
  distinct(CityName, DevGroup) %>%
  arrange(DevGroup, CityName) %>%
  pull(CityName)

rf_df <- rf_df %>%
  mutate(CityName = factor(CityName, levels = city_order))

p_feat <- ggplot(rf_df, aes(x = CityName, y = Variable, fill = RF_importance)) +
  geom_tile(color = "white", linewidth = 0.25) +
  scale_fill_viridis_c(
    name = "Importance",
    limits = c(0, 1),
    breaks = c(0, 0.5, 1),
    labels = c("0", "0.5", "1")
  ) +
  facet_grid(. ~ DevGroup, scales = "free_x", space = "free_x") +
  labs(x = NULL, y = NULL) +
  theme_classic(base_size = 9) +
  theme(
    axis.title = element_text(size = 9),
    axis.text  = element_text(size = 9, colour = "black"),
    strip.text = element_text(size = 9, face = "bold", colour = "black"),
    strip.background = element_blank(),
    legend.title = element_text(size = 10),
    legend.key.height = unit(10, "mm"),
    legend.key.width  = unit(4, "mm"),
    panel.grid = element_blank()
  )

# -----------------------------
# B) Read thresholds (precomputed)
# -----------------------------
thr_path <- file.path(output_data_dir, "thresholds_by_pop_share_country.csv")
thresholds_country <- read.csv(thr_path, stringsAsFactors = FALSE)

num_cols <- c("threshold", "reported_share", "estimated_share", "share_ratio", "threshold_updated")
thresholds_country[num_cols] <- lapply(thresholds_country[num_cols], function(x) as.numeric(as.character(x)))

# -----------------------------
# C) Calibration set: observed Y (country-level) from CV summary
# -----------------------------
cal_path  <- file.path(output_data_dir, "CrossValidation", "ensemble_metrics_summary.csv")
city_masks <- vect(file.path(city_boundary_dir, "CityBoundary.geojson"))

cal <- read.csv(cal_path, stringsAsFactors = FALSE)
names(cal) <- c("id", "Y", "F1", "AUC")

city_masks_df <- as.data.frame(city_masks) %>%
  select(ID_UC_G0, GC_CNT_GAD_2025, GC_POP_TOT_2025)

df_cal <- cal %>%
  left_join(city_masks_df, by = c("id" = "ID_UC_G0")) %>%
  group_by(GC_CNT_GAD_2025) %>%
  reframe(
    Y    = weighted.mean(Y, GC_POP_TOT_2025, na.rm = TRUE),
    iso3 = countrycode(GC_CNT_GAD_2025, origin = "country.name", destination = "iso3c")
  ) %>%
  left_join(thresholds_country, by = "iso3") %>%
  filter(!is.na(Y), !is.na(threshold_updated))

# -----------------------------
# D) Calibration plots (make rectangular with coord_fixed)
# -----------------------------
p_cal_fit <- ggplot(df_cal, aes(x = Y, y = threshold_updated)) +
  geom_point(size = 2.2) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", linewidth = 0.5) +
  geom_text_repel(aes(label = iso3), size = 3, max.overlaps = 30, box.padding = 0.25) +
  scale_x_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
  scale_y_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
  labs(x = "Calibrated threshold", y = "Population-adjusted threshold") +
  coord_fixed(ratio = 0.85) +
  theme_classic(base_size = 9) +
  theme(
    axis.title = element_text(size = 10.5),
    axis.text  = element_text(size = 9, colour = "black"),
    panel.grid = element_blank()
  )

p_cal_beforeafter <- ggplot(thresholds_country, aes(x = threshold, y = threshold_updated)) +
  geom_point(size = 1.9, alpha = 0.9) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", linewidth = 0.5) +
  geom_text_repel(aes(label = iso3), size = 2.7, max.overlaps = 25, box.padding = 0.25) +
  scale_x_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
  scale_y_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
  labs(x = "Population-estimated threshold", y = "Population-adjusted threshold") +
  coord_fixed(ratio = 0.85) +
  theme_classic(base_size = 9) +
  theme(
    axis.title = element_text(size = 10.5),
    axis.text  = element_text(size = 9, colour = "black"),
    panel.grid = element_blank()
  )

# -----------------------------
# E) Δ-threshold map
# -----------------------------
world  <- ne_countries(scale = "medium", returnclass = "sf")
africa <- world %>% filter(region_un == "Africa")

thresholds_sf <- left_join(africa, thresholds_country, by = c("iso_a3" = "iso3")) %>%
  mutate(diff_threshold = threshold_updated - threshold)

p_delta <- ggplot(thresholds_sf) +
  geom_sf(aes(fill = diff_threshold), color = "white", linewidth = 0.15) +
  scale_fill_gradient(
    low = "white", high = "red",
    name = expression(Delta~"threshold"),
    breaks = c(0, 0.3, 0.6),
    labels = c("0", "0.3", "0.6")
  ) +
  coord_sf(xlim = c(-20, 55), ylim = c(-35, 40), expand = FALSE) +
  theme_void(base_size = 9) +
  theme(
    legend.title = element_text(size = 10),
    legend.text  = element_text(size = 9),
    legend.key.height = unit(10, "mm"),
    legend.key.width  = unit(4, "mm")
  ) 

# -----------------------------
# F) Final layout (explicit design so widths behave)
#   Top row: A spans full width
#   Bottom row: B (left_stack) narrow, D (map) wide
# -----------------------------
final_plot <- free(p_feat) / (p_cal_fit | p_cal_beforeafter | p_delta) +
  plot_layout(heights = c(1, 1.2), widths = c(1, 1, 1.5)) +
  plot_annotation(tag_levels = "a") &
  theme(
    plot.tag = element_text(face = "bold", size = 12),
    plot.tag.position = c(0.01, 1.01)
  )
ggsave(file.path(paper_figures_dir, "Fig4.png"), final_plot, width = 12, height = 6.5, dpi = 600)
ggsave(file.path(paper_figures_dir, "Fig4.eps"), final_plot, device = cairo_ps, width = 12, height = 6.5)

message("Saved: ", file.path(paper_figures_dir, "Fig4.png"), " and .eps")
