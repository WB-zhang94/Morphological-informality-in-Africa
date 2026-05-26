library(terra)
library(countrycode)
library(readxl)
library(dplyr)
library(Metrics)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()
ensure_dir(output_data_dir, "CrossValidation")

# --- Input data ---
city_list  <- vect(c(
  vect(file.path(city_boundary_dir, "train_city_points.geojson")),
  vect(file.path(city_boundary_dir, "predict_city_points.geojson"))
))
city_df <- data.frame(
  index        = city_list$ID_UC_G0,
  city_name    = city_list$GC_UCN_MAI_2025,
  country_name = city_list$GC_CNT_GAD_2025
)
city_df$iso3 <- countrycode(city_df$country_name, origin = "country.name", destination = "iso3c")

slum_nonslum_values <- function(country_code,GHA_slum,GHA_nonslum) {
  ids <- city_df$index[city_df$iso3 == country_code]
  val_list <- list()
  for (id in ids) {
    # load probability raster
    settle10 <- rast(slum_probability_path(id))
    # extract values
    slum_vals <- terra::extract(settle10, GHA_slum)
    nonslum_vals <- terra::extract(settle10, GHA_nonslum)
    # add labels + city ID
    slum_df <- data.frame(
      id = id,
      label = "slum",
      value = slum_vals[,2]   # second column = extracted values
    )
    nonslum_df <- data.frame(
      id = id,
      label = "nonslum",
      value = nonslum_vals[,2]
    )
    val_list[[id]] <- bind_rows(slum_df, nonslum_df)
  }
  bind_rows(val_list) %>% na.omit()
}

GHA_df <- slum_nonslum_values(country_code = "GHA",
                              GHA_slum     = vect(cross_validation_path("slum_additional", "GHAslum.geojson")),
                              GHA_nonslum  = vect(cross_validation_path("slum_additional", "GHAnonslum.geojson"))
)
GHA_df$country <- "GHA"
KEN_df <- slum_nonslum_values(country_code = "KEN",
                              GHA_slum     = vect(cross_validation_path("slum_additional", "KENslum.geojson")),
                              GHA_nonslum  = vect(cross_validation_path("slum_additional", "KENnonslum.geojson"))
)
KEN_df$country <- "KEN"
MWI_df <- slum_nonslum_values(country_code = "MWI",
                              GHA_slum     = vect(cross_validation_path("slum_additional", "MWIslum.geojson")),
                              GHA_nonslum  = vect(cross_validation_path("slum_additional", "MWInonslum.geojson"))
)
MWI_df$country <- "MWI"
NGA_df <- slum_nonslum_values(country_code = "NGA",
                              GHA_slum     = vect(cross_validation_path("slum_additional", "NGAslum.geojson")),
                              GHA_nonslum  = vect(cross_validation_path("slum_additional", "NGAnonslum.geojson"))
)
NGA_df$country <- "NGA"

df <- rbind(GHA_df,KEN_df,MWI_df,NGA_df)
thresholds_df <- read.csv(file.path(output_data_dir, "thresholds_by_pop_share_country.csv"))
df <- df %>% left_join(thresholds_df,by = c("country"="iso3"))
t.test(value ~ label, data = df)
write.csv(df, cross_validation_path("points_validation.csv"))

df_openai <- read.csv(file.path(output_data_dir, "slum_analysis_results_openai.csv"))
df_openai <- df_openai %>%
  mutate(conf_band = case_when(
    confidence <= 3 ~ "Low (1–3)",
    confidence <= 7 ~ "Medium (4–7)",
    TRUE ~ "High (8–10)"
  ))
df_clean <- subset(df_openai, slum_status %in% c("definite_formal", "probable_formal", "mixed_area", "probable_slum", "definite_slum"))
df_clean$slum_status <- factor(df_clean$slum_status, 
                               levels = c("definite_formal", "probable_formal", "mixed_area", "probable_slum", "definite_slum"), 
                               ordered = TRUE)
summary_stats <- df_clean %>%
  group_by(slum_status) %>%
  summarise(
    n = n(),
    mean_prob = mean(original_slum_prob, na.rm = TRUE),
    sd_prob = sd(original_slum_prob, na.rm = TRUE)
  )
print(summary_stats)
library(broom)
pairwise_results <- list()
levels_status <- levels(df_clean$slum_status)
for(i in 1:(length(levels_status) - 1)) {
  group1 <- levels_status[i]
  group2 <- levels_status[i + 1]
  data1 <- df_clean$original_slum_prob[df_clean$slum_status == group1]
  data2 <- df_clean$original_slum_prob[df_clean$slum_status == group2]
  t_test <- t.test(data1, data2)
  pairwise_results[[paste(group1, "vs", group2)]] <- tidy(t_test)
}

# Print results for reporting
for(name in names(pairwise_results)) {
  cat(paste0("\n---\nComparison: ", name, "\n"))
  print(pairwise_results[[name]])
}

library(dplyr)
library(ggplot2)
library(patchwork)
library(readr)
library(caret)
points <- read.csv(cross_validation_path("points_validation.csv"))
points <- points %>%
  mutate(
    pred_orig = ifelse(value >= threshold, "slum", "nonslum"),
    pred_upd  = ifelse(value >= threshold_updated, "slum", "nonslum")
  )
calc_metrics <- function(df, pred_col, lab_col = "label") {
  cm <- caret::confusionMatrix(
    factor(df[[pred_col]], levels = c("slum","nonslum")),
    factor(df[[lab_col]], levels = c("slum","nonslum"))
  )
  
  precision <- cm$byClass["Pos Pred Value"]
  recall    <- cm$byClass["Sensitivity"]
  f1        <- ifelse((precision + recall) == 0, NA,
                      2 * precision * recall / (precision + recall))
  
  data.frame(
    Accuracy  = cm$overall["Accuracy"],
    Precision = precision,
    Recall    = recall,
    F1        = f1
  )
}

# Apply to both Original and Updated thresholds
acc_summary <- bind_rows(
  calc_metrics(points, "pred_orig") %>% mutate(Scheme = "Original"),
  calc_metrics(points, "pred_upd")  %>% mutate(Scheme = "Updated")
)

print(acc_summary)

# --- Panel a: Probability distributions ---
p1 <- ggplot(points, aes(x = label, y = value, fill = label)) +
  geom_violin(trim = FALSE, alpha = 0.5, colour = NA) +
  geom_boxplot(width = 0.1, outlier.shape = NA, alpha = 0.7, colour = "black") +
  scale_fill_brewer(palette = "Set1") +
  labs(y = "Predicted probability", x = "Independent reference points") +
  scale_x_discrete(labels = c(
    "nonslum"  = "Formal",
    "slum"  = "Informal"
  )) +
  theme_classic(base_size = 14) +
  theme(legend.position = "none",
        axis.text.x = element_text(size = 13, colour = "black"))
# --- threshold classification ---
points_long <- points %>%
  mutate(
    pred_class_orig = ifelse(value >= threshold, "slum", "nonslum"),
    correct_orig = ifelse(pred_class_orig == label, "Correct", "Incorrect"),
    pred_class_upd = ifelse(value >= threshold_updated, "slum", "nonslum"),
    correct_upd = ifelse(pred_class_upd == label, "Correct", "Incorrect")
  ) %>%
  tidyr::pivot_longer(
    cols = c(correct_orig, correct_upd),
    names_to = "Scheme", values_to = "Correctness"
  ) %>%
  mutate(Scheme = ifelse(Scheme == "correct_orig", "Original", "Updated")) %>%
  group_by(label, Scheme, Correctness) %>%
  summarise(N = n(), .groups = "drop") %>%
  group_by(label, Scheme) %>%
  mutate(Prop = N / sum(N)) %>%
  ungroup()
points_long$Prop[points_long$Correctness=="Correct"] = 1
# Plot: grouped bars in single panel
p2 <- ggplot(points_long, aes(x = label, y = Prop, fill = Correctness)) +
  geom_col(aes(fill = Correctness, group = Scheme),
           position = position_dodge(width = 0.8),
           width = 0.35, colour = "black") +
  geom_text(aes(label = Scheme, group = Scheme, y = -0.05), 
            position = position_dodge(width = 0.8), 
            vjust = 1.2, size = 4, colour = "black") +
  scale_y_continuous(labels = scales::percent_format(),
                     expand = expansion(mult = c(0.15, 0.05))) +
  scale_x_discrete(labels = c(
    "nonslum"  = "Formal",
    "slum"  = "Informal"
  )) +
  scale_fill_brewer(palette = "Set2") +
  labs(x = "Independent reference points", y = "Proportion of points") +
  theme_classic(base_size = 14) +
  theme(
    axis.text.x = element_text(size = 13, colour = "black"),
    legend.title = element_blank(),
    legend.position = "right"
  )

p3 <- ggplot(df_openai %>%
               dplyr::filter(!slum_status %in% c("no_buildings", "unknown")) %>%
               dplyr::mutate(slum_status = factor(
                 slum_status,
                 levels = c(
                   "definite_formal",
                   "probable_formal",
                   "mixed_area",
                   "probable_slum",
                   "definite_slum"
                 )
               )) %>% na.omit,
             aes(x = slum_status, y = original_slum_prob, fill = slum_status)) +
  geom_violin(trim = FALSE, alpha = 0.5, colour = NA) +
  geom_boxplot(width = 0.1, outlier.shape = NA, alpha = 0.7, colour = "black") +
  scale_fill_brewer(palette = "Set1") +
  scale_x_discrete(labels = c(
    "definite_formal"  = "Formal",
    "probable_formal"  = "Probable formal",
    "mixed_area"       = "Mixed",
    "probable_slum"    = "Probable informal",
    "definite_slum"    = "Informal"
  )) +
  labs(y = "Predicted probability", x = "Openai classification") +
  theme_classic(base_size = 14) +
  theme(
    legend.position = "none",
    axis.text.x = element_text(size = 13, colour = "black")
  )


# --- Combine ---
final_plot <- ggdraw() +
  draw_plot(p3, x = 0, y = 0, width = 1, height = 0.48) +
  draw_plot(p1, x = 0, y = 0.5, width = 0.5, height = 0.48) +
  draw_plot(p2, x = 0.5, y = 0.5, width = 0.5, height = 0.48) + 
  draw_plot_label(
    label = c("a", "b", "c"),
    x     = c(0.01, 0.495, 0.01),  # adjust positions
    y     = c(1, 1, 0.52),  # adjust positions
    size  = 18, 
    fontface = "bold"
  )

ggsave(cross_validation_path("validation.jpeg"), final_plot, width = 11, height = 6, dpi = 600)
ggsave(cross_validation_path("validation.eps"), final_plot, device = cairo_ps, width = 11, height = 6)
