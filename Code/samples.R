library(dplyr)
library(terra)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()

raster_files <- list.files(path = file.path(output_data_dir, "slum_probability", ""), pattern = "\\.tif$", full.names = TRUE)
df <- lapply(raster_files, function(file) {
  r <- rast(file)
  r_df <- as.data.frame(r, xy=TRUE, na.rm=TRUE)
  set.seed(123) 
  sampled_df <- r_df %>%
    mutate(prob_bin = cut(
      slum_prob,
      breaks = seq(0, 1, by = 0.5),
      include.lowest = TRUE
    )) %>%
    group_by(prob_bin) %>%
    slice_sample(n = 10, replace = FALSE)
})
df <- bind_rows(df)
write.csv(df, validation_points_file, row.names = FALSE)
