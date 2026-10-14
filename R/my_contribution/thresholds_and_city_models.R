#SECTION: Q1(set up), Q4(Partial: CITY LEVEL), Q5
library(tidyverse)
library(extRemes)
library(knitr)
library(cowplot)
library(forecast)

dir.create("plots", showWarnings = FALSE)

# DATA

df <- read.csv("data/california_no_monthly.csv") %>%
  rename(
    NO          = Nitric.oxide..NO.,
    wind_speed  = Wind.Speed...Resultant,
    temperature = Outdoor.Temperature,
    pressure    = Barometric.pressure
  ) %>%
  mutate(
    date = as.Date(sprintf("%04d-%02d-01", year, month)),
    city = factor(city),
    site = factor(site)
  ) %>%
  filter(year >= 2007 & year <= 2016)

# Q1: THRESHOLD SELECTION

no_clean   <- df$NO[is.finite(df$NO)]; plot(no_clean)
thresholds <- quantile(no_clean, probs = c(0.80, 0.85, 0.90, 0.95))
r_rng      <- quantile(no_clean, probs = c(0.80, 0.95),
                       na.rm = TRUE, names = FALSE)
u_main     <- as.numeric(thresholds["85%"])

threshold_table <- tibble(
  Quantile   = c("80th", "85th", "90th", "95th"),
  Threshold  = round(as.numeric(thresholds), 2),
  N_exceed   = map_int(thresholds, ~sum(no_clean > .x)),
  Pct_exceed = map_dbl(thresholds, ~round(mean(no_clean > .x) * 100, 2))
)

#write.csv(threshold_table, "plots/Table1_Thresholds.csv", row.names = FALSE)

threshold_table %>%
  kable(
    col.names = c("Quantile", "Threshold (ppb)", "N Exceed", "\\% Exceed"),
    escape = FALSE,
    caption   = "Table 1: Candidate POT thresholds and exceedance counts."
  )


writeLines(
  kable(threshold_table,
        format    = "latex",
        booktabs  = TRUE,
        escape    = FALSE,
        col.names = c("Quantile", "Threshold (ppb)",
                      "N Exceed", "\\% Exceed"),
        caption   = "Candidate POT thresholds."),
  "plots/Table1_Thresholds.tex"
)

# Fig 1: Annual Maxima
ewe_max <- df %>%
  group_by(year) %>%
  summarise(max_NO = max(NO, na.rm = TRUE))

p1 <- ggplot() +
  geom_point(data = df, aes(x = year, y = NO),
             alpha = 0.3, color = "darkgray") +
  geom_point(data = ewe_max, aes(x = year, y = max_NO),
             color = "red", size = 3) +
  geom_line(data = ewe_max, aes(x = year, y = max_NO),
            color = "red", linetype = "dashed") +
  theme_minimal() +
  labs(title = "Annual Maxima vs. All Observations",
       x = "Year", y = "Nitric Oxide (ppb)")


# Fig 2: MRL Plot
png("plots/Fig2_MRL_Plot.png", width = 8, height = 5,
    units = "in", res = 300)
mrlplot(no_clean, main = "", xlab = "Threshold u",
        col = "steelblue", lwd = 1.5)
abline(v = thresholds["80%"], col = "forestgreen", lty = 2, lwd = 1.1)
abline(v = thresholds["85%"], col = "purple",      lty = 2, lwd = 1.1)
abline(v = thresholds["90%"], col = "orange",      lty = 2, lwd = 1.1)
abline(v = thresholds["95%"], col = "tomato",      lty = 2, lwd = 1.1)
legend("topright", legend = c("80th", "85th", "90th", "95th"),
       col = c("forestgreen", "purple", "orange", "tomato"),
       lty = 2, bty = "n", cex = 0.8)

png("plots/Fig3_Parameter_Stability.png",
    width  = 9,
    height = 5,      # not 4 — two panels need breathing room
    units  = "in",
    res    = 300)
threshrange.plot(x = no_clean, r = c(80, 250), type = "GP", nint = 20)
dev.off()

# Q4: COVARIATE EFFECTS BY CITY

#Fig 7: Monthly exceedances by city (raw data) 
exceed_city_month <- df %>%
  group_by(city, month) %>%
  summarise(n_exceed = sum(NO > u_main, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(city = fct_reorder(city, n_exceed,
                            .fun = sum, .desc = TRUE))

p_city_month <- ggplot(exceed_city_month,
                       aes(x = month, y = n_exceed)) +
  geom_line(color = "steelblue") +
  geom_point(color = "steelblue", size = 1) +
  scale_x_continuous(breaks = c(1, 4, 7, 10),
                     labels = c("Jan","Apr","Jul","Oct")) +
  facet_wrap(~city) +
  theme_minimal(base_size = 8) +
  labs(title = "Monthly Exceedances by City",
       x = "Month", y = "Number of Exceedances")

ggsave("plots/Fig7_City_Monthly_Exceedances.png",
       plot = p_city_month,
       width = 7, height = 5, dpi = 300)

# --- Table: Raw exceedances per city ---
city_raw_exceed <- exceed_city_month %>%
  group_by(city) %>%
  summarise(Total_Exceedances = sum(n_exceed)) %>%
  arrange(desc(Total_Exceedances))

writeLines(
  kable(city_raw_exceed,
        format    = "latex",
        booktabs  = TRUE,
        col.names = c("City", "Total Exceedances"),
        caption   = "Total exceedances per city under the 
                     global threshold of 131.18 ppb."),
  "plots/Table_RawExceedances.tex"
)

# Covariate dataset 
df_no_wind <- df %>%
  mutate(sin_month = sin(2 * pi * month / 12),
         cos_month = cos(2 * pi * month / 12)) %>%
  dplyr::select(NO, temperature, sin_month, cos_month, city) %>%
  drop_na()

city_counts <- df_no_wind %>%
  filter(NO > u_main) %>%
  count(city, name = "Exceedances") %>%
  arrange(desc(Exceedances))
print(city_counts)

# GPD models: Rubidoux (n = 66)

df_rubidoux <- df_no_wind %>% filter(city == "Rubidoux")

fit_stat_rub   <- fevd(x = NO, data = df_rubidoux,
                       threshold = u_main, type = "GP")
fit_temp_rub   <- fevd(x = NO, data = df_rubidoux,
                       threshold = u_main, type = "GP",
                       scale.fun = ~temperature)
fit_season_rub <- fevd(x = NO, data = df_rubidoux,
                       threshold = u_main, type = "GP",
                       scale.fun = ~sin_month + cos_month)
fit_full_rub   <- fevd(x = NO, data = df_rubidoux,
                       threshold = u_main, type = "GP",
                       scale.fun = ~temperature + sin_month + cos_month)

lr.test(fit_stat_rub, fit_temp_rub)
lr.test(fit_stat_rub, fit_season_rub)
lr.test(fit_stat_rub, fit_full_rub)

# GPD models: Roseville: n = 20
df_roseville <- df_no_wind %>% filter(city == "Roseville")

fit_stat_ros <- fevd(x = NO, data = df_roseville,
                     threshold = u_main, type = "GP")
fit_full_ros <- fevd(x = NO, data = df_roseville,
                     threshold = u_main, type = "GP",
                     scale.fun = ~temperature + sin_month + cos_month)

lr.test(fit_stat_ros, fit_full_ros)

# Q5: IMPROVING ESTIMATION; City-specific thresholds
city_thresholds <- df %>%
  filter(is.finite(NO)) %>%
  group_by(city) %>%
  summarise(
    u_city   = quantile(NO, 0.85),
    n_exceed = sum(NO > quantile(NO, 0.85)),
    mean_NO  = round(mean(NO), 2)
  ) %>%
  arrange(desc(u_city))

print(city_thresholds)

city_thresholds %>%
  kable(
    col.names = c("City", "Threshold (ppb)",
                  "N Exceedances", "Mean NO (ppb)"),
    caption = "City-specific 85th percentile thresholds.",
    digits  = 1
  )

# City-specific GPD fits
cities   <- levels(df$city)
city_gpd <- data.frame()

for (cty in cities) {
  city_data <- df %>% filter(city == cty, is.finite(NO))
  u_cty     <- quantile(city_data$NO, 0.85)
  exceed    <- city_data$NO[city_data$NO > u_cty]
  fit       <- fevd(exceed, threshold = u_cty, type = "GP")
  params    <- distill(fit)
  city_gpd  <- rbind(city_gpd, data.frame(
    city  = cty,
    u     = round(u_cty, 2),
    scale = round(as.numeric(params["scale"]), 3),
    shape = round(as.numeric(params["shape"]), 3)
  ))
}
rownames(city_gpd) <- NULL
print(city_gpd)

  # Table 2
writeLines(
  kable(city_thresholds,
        format    = "latex",
        booktabs  = TRUE,
        col.names = c("City", "u (ppb)", "n", "Mean"),
        digits    = 1,
        row.names = FALSE),
  "plots/Table2_content.tex"
)

# Table 3
writeLines(
  kable(city_gpd,
        format    = "latex",
        booktabs  = TRUE,
        col.names = c("City", "u (ppb)", "Scale", "Shape"),
        digits    = 3,
        row.names = FALSE),
  "plots/Table3_content.tex"
)

