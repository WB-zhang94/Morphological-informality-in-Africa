library(terra)
library(dplyr)
library(cluster) 
library(pheatmap)

source(file.path(if (dir.exists("Code")) "Code" else ".", "paths.R"))
project_setwd()
ensure_dir(rf_models_dir)

ref_cities <- vect(file.path(city_boundary_dir, "train_city_points.geojson"))
train_cities <- vect(file.path(city_boundary_dir, "predict_city_points.geojson"))
city_list <- vect(c(ref_cities,train_cities))

df <- as.data.frame(city_list)
write.csv(df, file.path(rf_models_dir, "city_list.csv"))
df_features <- df %>%
  mutate(
    city_name = GC_UCN_MAI_2025,
    #Population density (people per km²)
    pop_density_2025 = GC_POP_TOT_2025 / GC_UCA_KM2_2025,
    #Building morphology (avg / max / variability)
    build_height_avg = GH_BUH_AVG_2020,
    build_height_std = GH_BUH_STD_2020,
    build_height_max = GH_BUH_MAX_2020,
    #Residential share in built-up area
    res_share_2020 = GH_BPC_RES_2020 / GH_BPC_TOT_2020,
    #Population growth rate (Compound Annual Growth)
    pop_growth_cagr = GH_POP_CAG_2020,
    #Building stock growth in last 20 yrs
    build_stock_growth = GH_BUS_TOT_2020 - GH_BUS_TOT_2000,
    #Urban service / development readiness
    dev_service_wig = factor(GC_DEV_WIG_2025),
    dev_service_usr = factor(GC_DEV_USR_2025)
  ) %>%
  # Keep only relevant columns
  select(
    city_name,
    ID_UC_G0,
    pop_density_2025,
    build_height_avg, build_height_std, build_height_max,
    res_share_2020,
    pop_growth_cagr,
    build_stock_growth,
    dev_service_wig, dev_service_usr
  )

feature_matrix <- daisy(df_features %>% select(-c(city_name,ID_UC_G0)), metric = "gower")
dist_matrix <- dist(feature_matrix, method = "euclidean")
dist_matrix_mat <- as.matrix(dist_matrix)
rownames(dist_matrix_mat) <- df_features$city_name
colnames(dist_matrix_mat) <- df_features$city_name

index <- which(df_features$ID_UC_G0 %in% ref_cities$ID_UC_G0)
dist_to_refs <- dist_matrix_mat[index, , drop = FALSE]

pheatmap(
  dist_to_refs,
  clustering_distance_rows = "euclidean",
  clustering_distance_cols = "euclidean",
  clustering_method = "ward.D2",
  main = "City dissimilarity Heatmap"
)

rownames(dist_matrix_mat) <- df_features$ID_UC_G0
colnames(dist_matrix_mat) <- df_features$ID_UC_G0
dist_to_refs <- t(dist_matrix_mat[index, , drop = FALSE])
dist_to_refs <- 1 / dist_to_refs

write.csv(dist_to_refs, file.path(rf_models_dir, "similarity.csv"))

