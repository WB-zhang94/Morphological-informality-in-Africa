library(terra)
library(dplyr)
library(stringr)
library(ggplot2)
library(forcats)
library(tidyr)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()
ensure_dir(output_data_dir)
ensure_dir(paper_figures_dir)

# slum label data
cities_predict <- vect(file.path(city_boundary_dir, "predict_city_points.geojson"))
cities_train <- vect(file.path(city_boundary_dir, "train_city_points.geojson"))
cities <- vect(c(cities_predict,cities_train))

slum_probs <- list.files(file.path(output_data_dir, "slum_probability", ""),pattern = "\\.tif$",full.names = T)

breaks <- c(0, 0.2, 0.4, 0.6, 0.8, 1.0)
bin_labels <- c("p0_0.2", "p0.2_0.4", "p0.4_0.6", "p0.6_0.8", "p0.8_1")

process_raster <- function(f) {
  # Load raster
  r <- rast(f)
  
  # Reclassify into bins 1–5
  m <- cbind(breaks[-length(breaks)], breaks[-1], 1:5)
  rc <- classify(r, m, include.lowest = TRUE, right = TRUE)
  
  # Frequency table
  freq_df <- freq(rc) |> as.data.frame()
  
  # Initialize count vector (0s)
  counts <- setNames(rep(0, 5), bin_labels)
  
  # Fill in counts where available
  if (nrow(freq_df) > 0) {
    for (i in seq_len(nrow(freq_df))) {
      bin_index <- freq_df$value[i]      # bin number 1–5
      counts[bin_index] <- freq_df$count[i]
    }
  }
  
  # Extract city ID from filename (e.g. "8564_ensemble_prob.tif")
  city_id <- str_extract(basename(f), "^[0-9]+") |> as.integer()
  
  # Return tidy row
  data.frame(ID_UC_G0 = city_id, t(counts))
}

# Apply to all rasters
results_list <- lapply(slum_probs, process_raster)
results_df <- bind_rows(results_list)

# Join to cities
cities_out <- merge(cities, results_df, by = "ID_UC_G0", all.x = TRUE)

cities_df <- as.data.frame(cities_out)
df <- cities_df %>% select(ID_UC_G0,GC_UCN_MAI_2025,GC_CNT_GAD_2025,GC_UCA_KM2_2025,GC_POP_TOT_2025,
                     GC_DEV_WIG_2025,GC_DEV_USR_2025,p0_0.2,p0.2_0.4,p0.4_0.6,p0.6_0.8,p0.8_1)

head(df)

bin_levels <- c("p0_0.2", "p0.2_0.4", "p0.4_0.6", "p0.6_0.8", "p0.8_1")
bin_labels <- c("[0,0.2)", "[0.2,0.4)", "[0.4,0.6)", "[0.6,0.8)", "[0.8,1.0]")

# Long format
results_long <- results_df %>%
  pivot_longer(cols = all_of(bin_levels),
               names_to = "bin",
               values_to = "count") %>%
  mutate(bin = factor(bin, levels = bin_levels)) %>%
  left_join(df %>% select(ID_UC_G0, GC_UCN_MAI_2025, GC_CNT_GAD_2025),
            by = "ID_UC_G0") %>%
  mutate(city_country = paste0(GC_UCN_MAI_2025, " (", GC_CNT_GAD_2025, ")"))

# Proportions per city
results_prop <- results_long %>%
  group_by(ID_UC_G0, city_country) %>%
  mutate(prop = count / sum(count)) %>%
  ungroup()

# Sort by share of highest bin
city_order <- results_prop %>%
  filter(bin == "p0.8_1") %>%
  arrange(desc(prop)) %>%
  pull(city_country)

results_prop <- results_prop %>%
  mutate(city_country = factor(city_country, levels = city_order))
write.csv(results_prop, file.path(output_data_dir, "informality_share.csv"))
# --- Plot ---
ggplot(results_prop, aes(x = prop, y = city_country, fill = bin)) +
  geom_col(width = 0.7) +
  scale_fill_manual(
    name   = "Informal settlements probability",
    values = c(
      "p0_0.2"   = "#d9d9d9",  # light grey
      "p0.2_0.4" = "#a6bddb",  # muted blue
      "p0.4_0.6" = "#3690c0",  # mid blue
      "p0.6_0.8" = "#045a8d",  # dark blue
      "p0.8_1"   = "#d73027"   # red highlight
    ),
    labels = bin_labels
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(color = "grey80", size = 0.3),
    axis.text.y = element_text(size = 7, face = "italic"),
    axis.text.x = element_text(size = 9),
    axis.title = element_text(size = 11),
    legend.title = element_text(size = 10),
    legend.text = element_text(size = 8.5),
    legend.position = "top",
    legend.justification = c(1.2,0),
    legend.margin = margin(t = 4, r = 4, b = -6, l = 4),
    plot.margin = margin(t = 0, r = 4, b = 4, l = 4)
  ) +
  labs(
    x = "Proportion of settlements",
    y = "City (Country)"
  )

fig_width_in <- 7.2
fig_height_in <- 9

# Save as PDF (vector, best for Nature submissions)
ggsave(file.path(paper_figures_dir, "Fig1_SlumProbability_Cities.pdf"), 
       width = fig_width_in, height = fig_height_in, units = "in", device = cairo_pdf)

# Save as TIFF (300 dpi, high-res raster)
ggsave(file.path(paper_figures_dir, "Fig1_SlumProbability_Cities.tiff"), 
       width = fig_width_in, height = fig_height_in, units = "in", dpi = 600, compression = "lzw")



cities_df <- as.data.frame(cities_out, geom = "XY")

# --- 2. Reshape to long format ---
bin_levels <- c("p0_0.2","p0.2_0.4","p0.4_0.6","p0.6_0.8","p0.8_1")
bin_labels <- c("[0,0.2)", "[0.2,0.4)", "[0.4,0.6)", "[0.6,0.8)", "[0.8,1.0]")

df_long_map <- cities_df %>%
  pivot_longer(cols = all_of(bin_levels),
               names_to = "bin", values_to = "count") %>%
  group_by(ID_UC_G0, GC_UCN_MAI_2025, GC_CNT_GAD_2025, x, y, GC_POP_TOT_2025) %>%
  mutate(
    prop = count / sum(count),
    bin  = factor(bin, levels = bin_levels, labels = bin_labels)
  ) %>%
  ungroup()

# --- 3. Compute start & end angles for pies ---
df_pies <- df_long_map %>%
  group_by(ID_UC_G0) %>%
  arrange(bin) %>%
  mutate(
    end   = cumsum(prop),
    start = lag(end, default = 0)
  ) %>%
  ungroup()

# --- 4. Plot map with pies ---
ggplot() +
  # basemap (world simplified)
  borders("world", colour = "grey90", fill = "grey95") +
  # pies
  geom_arc_bar(
    data = df_pies,
    aes(
      x0 = x, y0 = y,
      r0 = 0,
      # scale pie size by log-population for readability
      r = 0.5 + 1.5 * scales::rescale(log1p(GC_POP_TOT_2025)),
      start = start * 2*pi, end = end * 2*pi,
      fill = bin
    ),
    color = "black", size = 0.1
  ) +
  coord_fixed(1.2, xlim = c(-20, 55), ylim = c(-35, 40)) + # focus on Africa
  scale_fill_manual(
    name = "Informal settlements\nprobability",
    values = c(
      "[0,0.2)"  = "#d9d9d9",
      "[0.2,0.4)"= "#a6bddb",
      "[0.4,0.6)"= "#3690c0",
      "[0.6,0.8)"= "#045a8d",
      "[0.8,1.0]"= "#d73027"
    )
  ) +
  theme_minimal(base_size = 7) +
  theme(
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank(),
    legend.title = element_text(size = 6, face = "bold"),
    legend.text = element_text(size = 5),
    legend.position = c(0.05,0.05),
    legend.justification = c(-0,-0),
    legend.margin = margin(t = 0, r = 0, b = 0, l = 0),
    plot.margin = margin(t = -3, r = 0, b = -15, l = 0)
  ) +
  labs(
    x = NULL, y = NULL
  )

fig_width_in <- 3.54
fig_height_in <- 4.1

# Save as PDF (vector, best for Nature submissions)
ggsave(file.path(paper_figures_dir, "Fig2_SlumProbability_Cities.pdf"), 
       width = fig_width_in, height = fig_height_in, units = "in", device = cairo_pdf)

# Save as TIFF (300 dpi, high-res raster)
ggsave(file.path(paper_figures_dir, "Fig2_SlumProbability_Cities.tiff"), 
       width = fig_width_in, height = fig_height_in, units = "in", dpi = 600, compression = "lzw")

library(dplyr)
library(tidyr)
library(ggplot2)

# --- 1. Compute shares ---
df_rank <- df %>%
  mutate(
    total_pix = p0_0.2 + p0.2_0.4 + p0.4_0.6 + p0.6_0.8 + p0.8_1,
    share_0.8 = p0.8_1 / total_pix,
    share_0.6 = (p0.6_0.8 + p0.8_1) / total_pix,
    share_0.4 = (p0.4_0.6 + p0.6_0.8 + p0.8_1) / total_pix
  ) %>%
  select(ID_UC_G0, GC_UCN_MAI_2025, GC_CNT_GAD_2025,
         GC_POP_TOT_2025, GC_UCA_KM2_2025,
         share_0.8, share_0.6, share_0.4)

# --- 2. Long format and compute ranks ---
df_rank_long <- df_rank %>%
  pivot_longer(cols = c(share_0.8, share_0.6, share_0.4,
                        GC_POP_TOT_2025, GC_UCA_KM2_2025),
               names_to = "metric", values_to = "value") %>%
  group_by(metric) %>%
  mutate(rank = rank(-value, ties.method = "first")) %>%
  ungroup()

# --- 3. Clean labels ---
df_rank_long <- df_rank_long %>%
  mutate(metric = recode(metric,
                         share_0.8 = "Share [0.8,1.0]",
                         share_0.6 = "Share [0.6,1.0]",
                         share_0.4 = "Share [0.4,1.0]",
                         GC_POP_TOT_2025 = "Population",
                         GC_UCA_KM2_2025 = "Urban area"
  ))

# --- 4. Plot classic rank–size (Zipf style) ---
ggplot(df_rank_long, aes(x = rank, y = value, color = metric)) +
  geom_point(size = 2, alpha = 0.7) +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE) +  # linear fit in log-log
  scale_x_log10() +
  scale_y_log10() +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "top",
    legend.title = element_blank()
  ) +
  labs(
    title = "Rank–size scaling of city metrics",
    x = "City rank (1 = largest → left)",
    y = "Metric value (log scale)"
  )

exponents <- df_rank_long %>%
  group_by(metric) %>%
  do({
    fit <- lm(log10(value) ~ log10(rank), data = .)
    data.frame(
      exponent = coef(fit)[2],
      r2 = summary(fit)$r.squared
    )
  })

print(exponents)
