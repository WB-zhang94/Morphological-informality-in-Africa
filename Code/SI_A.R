library(ggplot2)
library(dplyr)
library(tidyr)
library(patchwork)
library(randomForest)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()
ensure_dir(paper_figures_dir, "SI")

# slum label data
slums_labels_training_data <- list.files(training_labels_dir, pattern = "\\.geojson$")

# RF models
var_labels <- c(
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
  "Building_Height"   = "Building Height (mean)",
  "Building_Height_CV"= "Building Height (CV)",
  "NDVI"     = "NDVI (Vegetation Index)",
  "NDVI_CV"  = "NDVI Variability",
  "NDBI"     = "NDBI (Built-up Index)",
  "NDBI_CV"  = "NDBI Variability"
)
for (cities in slums_labels_training_data) {
  index <- sub(".*_([0-9]+)\\.geojson$", "\\1", cities)
  rf_mod <- readRDS(rf_model_path(index))
  err <- as.data.frame(rf_mod$err.rate)
  err$Trees <- 1:nrow(err)
  err_long <- pivot_longer(err, -Trees, names_to = "Class", values_to = "Error")
  err_long <- err_long%>%
    mutate(Class = recode(Class,
                          "OOB" = "Overall",
                          "slum" = "Informal settlement",
                          "non_slum" = "Formal settlement"))
  p <- ggplot(err_long, aes(x = Trees, y = Error, colour = Class)) +
    geom_line(size = 1) +
    scale_color_brewer(palette = "Set1") +
    labs(x = "Number of trees", y = "OOB error rate") +
    theme_classic(base_size = 14) +
    theme(
      legend.position = c(0.8, 0.8),
      legend.title = element_blank()
    )
  ggsave(file.path(paper_figures_dir, "SI", paste0(basename(cities), "_importance_error.png")),
         p, width = 8, height = 6, dpi = 300)
}







