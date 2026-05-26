library(terra)
library(dplyr)
library(ggplot2)
library(patchwork)
library(ggplot2)
library(patchwork)
library(sf)
library(rnaturalearth)
library(rnaturalearthdata)
library(cowplot)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()
ensure_dir(paper_figures_dir)

# List of trained models
model_files <- list.files(rf_models_dir, pattern = "_mask_before_predict.rds$", full.names = TRUE)
model_ids <- gsub(".*model_([0-9]+)_mask_before_predict.rds$", "\\1", model_files)

all_rf_importance <- list()
all_shap <- list()

# Loop through models
for (i in seq_along(model_files)) {
  city_id <- model_ids[i]
  rf_mod <- readRDS(model_files[i])
  
  # --- 1. RF variable importance ---
  imp <- randomForest::importance(rf_mod)[,1]  # %IncMSE
  imp_df <- data.frame(
    City = city_id,
    Variable = names(imp),
    RF_importance = imp
  )
  all_rf_importance[[i]] <- imp_df
}
# Bind results
rf_df <- bind_rows(all_rf_importance) %>%
  group_by(City) %>%
  mutate(RF_importance = RF_importance / max(RF_importance, na.rm = TRUE)) %>%
  ungroup()

cities <- vect(file.path(city_boundary_dir, "train_city_points.geojson"))
city_meta <- as.data.frame(cities)[, c("ID_UC_G0", "GC_UCN_MAI_2025", "GC_DEV_WIG_2025")]
names(city_meta) <- c("City", "CityName", "DevGroup")
city_meta$City <- as.character(city_meta$City)
# Join with your RF and SHAP results
rf_df <- rf_df %>%
  left_join(city_meta, by = "City") %>%
  mutate(CityName = factor(CityName, levels = unique(CityName)))

var_labels <- c(
  # Building presence bins (0–100%)
  "Building_Presence_0.0"  = "Building Presence (0–10%)",
  "Building_Presence_10.0" = "Building Presence (10–20%)",
  "Building_Presence_20.0" = "Building Presence (20–30%)",
  "Building_Presence_30.0" = "Building Presence (30–40%)",
  "Building_Presence_40.0" = "Building Presence (40–50%)",
  "Building_Presence_50.0" = "Building Presence (50–60%)",
  "Building_Presence_60.0" = "Building Presence (60–70%)",
  "Building_Presence_70.0" = "Building Presence (70–80%)",
  "Building_Presence_80.0" = "Building Presence (80–90%)",
  "Building_Presence_90.0" = "Building Presence (90–100%)",
  
  # Building height
  "Building_Height"   = "Building Height (mean)",
  "Building_Height_CV"= "Building Height (CV)",
  
  # NDVI
  "NDVI"     = "NDVI (Vegetation Index)",
  "NDVI_CV"  = "NDVI Variability",
  
  # NDBI
  "NDBI"     = "NDBI (Built-up Index)",
  "NDBI_CV"  = "NDBI Variability"
)

rf_df$Variable <- factor(rf_df$Variable, 
                         levels = names(var_labels), 
                         labels = var_labels[names(var_labels)])

city_order <- rf_df %>%
  distinct(CityName, DevGroup) %>%
  arrange(DevGroup, CityName) %>%   # sort inside groups
  pull(CityName)

rf_df <- rf_df %>%
  mutate(CityName = factor(CityName, levels = city_order))

thresholds_country <- read.csv(file.path(output_data_dir, "thresholds_by_pop_share_country.csv"))
city_list  <- vect(c(
  vect(file.path(city_boundary_dir, "train_city_points.geojson")),
  vect(file.path(city_boundary_dir, "predict_city_points.geojson"))
))
city_df <- data.frame(
  country_name = city_list$GC_CNT_GAD_2025,
  DevGroup = city_list$GC_DEV_WIG_2025
)
city_df$iso3 <- countrycode(city_df$country_name, origin = "country.name", destination = "iso3c")
thresholds_country <- thresholds_country %>% left_join(city_df,by = c("iso3")) %>% unique()
world <- ne_countries(scale = "medium", returnclass = "sf")
africa <- world %>% dplyr::filter(region_un == "Africa")
thresholds_sf <- left_join(africa, thresholds_country, by = c("iso_a3" = "iso3"))
thresholds_sf$diff_threshold <- thresholds_sf$threshold_updated - thresholds_sf$threshold

# plot
p1 <- ggplot(rf_df, aes(x = CityName, y = Variable, fill = RF_importance)) +
  geom_tile(color = "white") +
  scale_fill_viridis_c(name = "Importance", limits = c(0,1)) +
  facet_grid(. ~ DevGroup, scales = "free_x", space = "free_x") +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 14) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 14, colour = "black"),
        strip.text = element_text(size = 13, face = "bold", colour = "black"),
        axis.text.y = element_text(size = 13, colour = "black"))

p2 <- ggplot(thresholds_country, aes(x = DevGroup, y = threshold_updated, fill = DevGroup)) +
  geom_violin(trim = FALSE, drop = FALSE, alpha = 0.6, colour = NA) +
  geom_jitter(width = 0.15, size = 2, alpha = 0.7, aes(color = DevGroup)) +
  scale_fill_brewer(palette = "Set2") +
  scale_color_brewer(palette = "Set2") +
  labs(y = "Updated Threshold", x = NULL) +
  theme_classic(base_size = 14) +
  theme(
    legend.position = "none",
    axis.text.x = element_text(size = 13, colour = "black"),
    axis.text.y = element_text(size = 13, colour = "black")
  )

p3 <- ggplot(thresholds_sf) +
  geom_sf(aes(fill = diff_threshold), color = "white", size = 0.2)  +
  scale_fill_gradient(
    low = "white", high = "red",
    name = expression(Delta~"Threshold")   # shows Δ symbol
  ) +
  coord_sf(xlim = c(-20, 55),
           ylim = c(-35, 40),
           expand = FALSE) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "bottom",
    legend.title = element_text(size = 13, face = "bold"),
    panel.grid   = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank()
  )

final_plot <- ggdraw() +
  draw_plot(p1, x = 0, y = 0, width = 0.72, height = 0.55) +
  draw_plot(p2, x = 0.075, y = 0.55, width = 0.4, height = 0.4) + 
  draw_plot(p3, x = 0.5, y = 0, width = 0.52, height = 1) +
  draw_plot_label(
    label = c("a", "b", "c"),
    x     = c(0.05, 0.55, 0.05),  # adjust positions
    y     = c(0.965, 0.965, 0.55),  # adjust positions
    size  = 28, 
    fontface = "bold"
  )

ggsave(file.path(paper_figures_dir, "heterogeneity_preview_new.jpeg"), final_plot, width = 17, height = 10,dpi = 600)
ggsave(file.path(paper_figures_dir, "heterogeneity_preview.eps"), final_plot, device = cairo_ps, width = 17, height = 10)

