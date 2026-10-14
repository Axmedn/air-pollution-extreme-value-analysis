############################################
### EnvEco Group 11 Group Project R code ###
############################################

# Libraries ---------------------------------------------------------------

library(ggplot2)    # for visualisation
library(dplyr)      # for data manipulation
library(broom)      # for modelling
library(extRemes)   # for GEV models
library(tidyr)      # for data tidying
library(xtable)     # table creation
library(knitr)
library(cowplot)
library(mapview)
library(sf)
library(purrr)      # for map_int, map_dbl

# Data Loading and Manipulation -------------------------------------------

# Load Data
dir.create("plots", showWarnings = FALSE)  # figures are written here
df <- read.csv("data/california_no_monthly.csv", header = TRUE)

# Check Data Structure
glimpse(df)
# 1800 x 11

# Alter Variable Names
df <- df %>% # change certain variable names
  rename(
    NO = Nitric.oxide..NO.,
    wind_speed = Wind.Speed...Resultant,
    temperature = Outdoor.Temperature,
    pressure = Barometric.pressure
  ) %>% # create a column for the date, and convert character variables to factors
  mutate(
    date = as.Date(sprintf("%04d-%02d-01", year, month)),
    city = factor(city),
    site = factor(site)
  ) %>% # specify time frame of interest
  filter(year >= 2007 & year <= 2016)


# Include Continuous time variable
df$year_num <- df$year + df$month / 12

glimpse(df)
# Tidy data is 1200 x 12, new variable from data, and updated observation count from year filter

# Exploratory Data Analysis -----------------------------------------------

#########################
# Missing Data Analysis #
#########################

# Observe Missing data per variable
df_na <- df %>%
  summarise(across(everything(), ~sum(is.na(.))))
df_na

# Out of the 1200 observations, 867 missing values for pressure, implying that 
# this will not serve as a reliable covariate.
# 416 for wind speed and 310 for temperature is also bad and 131 for NO

# And now missing values by city
df_na_city <- df %>%
  group_by(city) %>%
  summarise(across(everything(), ~sum(is.na(.))))
df_na_city

# Check on missing NO values per year
NA_Count <- df %>%
  group_by(year) %>%
  summarise(NA_count = sum(is.na(NO)), .groups = "drop")
NA_Count
# Note 2016 has >10x more missing than other years 


# Check data in 2016
df_2016 <- df %>%
  filter(year == 2016) %>%
  group_by(month) %>%
  summarise(NA_count = sum(is.na(NO)), .groups = "drop")
df_2016
# All 10 data points missing after month 4 in 2016, assume study 
# ends in month 4 . High rate of missing data in all months of 2016


#############################
# NO concentrations Summary # 
#############################

# Make table of summary statistics for latex
summary_NO <- df %>%
  summarise(Min = min(NO, na.rm=TRUE),
            Max = max(NO, na.rm=TRUE),
            Median = median(NO, na.rm=TRUE),
            Mean = mean(NO, na.rm=TRUE),
            Std = sd(NO, na.rm=TRUE)) %>%
  mutate(Variable = "NO") 
summary_NO <- summary_NO %>%
  dplyr::select(Variable, Min, Max, Median, Mean, Std)
sum_tab <- xtable(summary_NO)
print(sum_tab, digits = c(0, 0, 2, 2, 2, 2, 2), include.rownames = FALSE)
# Heavy right skewing, mean does not equal median -> suggests extreme values


# Investigating differences across cities
# Make boxplots of NO concentrations for each city
ggplot(df, mapping = aes(x = city, y = NO)) +
  geom_boxplot(fill = "steelblue") +
  labs(x = "City", y = "Nitric Oxide (ppb)",
       title = "NO concentration across cities") +
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))

# Testing the difference of means by city
summary(aov(NO ~ city, data = df))
# Conclusion: at least one group mean is different

###################################
# Visualising Seasonality in Data #
###################################

#Checking for Seasonality by month
ggplot(data = df,
       aes(y = NO, x = as.factor(month)))+
  geom_boxplot()+
  labs(y= "Nitric Oxide (ppb)",x="Months")

#Checking for Trend
ggplot(data = df,
       aes(y = NO, x = year_num ))+
  geom_point()+
  geom_smooth(method = "loess") +
  labs(x = "Time", y = "Nitric Oxide (ppb)")


# Formal Data Analysis ----------------------------------------------------

########################################
# Identifying Extreme Pollution Levels #
########################################

no_clean <- df$NO[is.finite(df$NO)]
thresholds <- quantile(no_clean, probs = c(0.80, 0.85, 0.90, 0.95))
r_rng <- quantile(no_clean, probs = c(0.80, 0.95),
                  na.rm = TRUE, names = FALSE)

# Determine threshold: u
u_main <- as.numeric(thresholds["85%"])

# Create table of threshold and exeedences
threshold_table <- tibble(
  Quantile   = c("80th", "85th", "90th", "95th"),
  Threshold  = round(as.numeric(thresholds), 2),
  N_exceed   = map_int(thresholds, ~sum(no_clean > .x)),
  Pct_exceed = map_dbl(thresholds, ~round(mean(no_clean > .x) * 100, 2))
)

# Create threshold table
threshold_table %>%
  kable(
    col.names = c("Quantile", "Threshold", "N Exceedances", "% Exceeding"),
    caption   = "Table 1: Candidate POT thresholds and exceedance counts."
  )

# Fig 1: Annual Maxima
df_max <- df %>%
  group_by(year) %>%
  summarise(max_NO = max(NO, na.rm = TRUE))

p1 <- ggplot() +
  geom_point(data = df, aes(x = year, y = NO),
             alpha = 0.3, color = "darkgray") +
  geom_point(data = df_max, aes(x = year, y = max_NO),
             color = "red", size = 3) +
  geom_line(data = df_max, aes(x = year, y = max_NO),
            color = "red", linetype = "dashed") +
  theme_minimal() +
  labs(title = "Annual Maxima vs. All Observations",
       x = "Year", y = "Nitric Oxide (ppb)")

ggsave("plots/Fig1_Annual_Maxima.png", plot = p1,
       width = 8, height = 5, dpi = 300, create.dir = TRUE)

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
dev.off()

# Fig 3: Parameter Stability
png("plots/Fig3_Parameter_Stability.png", width = 8, height = 6,
    units = "in", res = 300)
threshrange.plot(x = no_clean, r = c(80, 250), type = "GP", nint = 20)
title(main = "Parameter Stability: GPD Scale and Shape vs Threshold",
      line = -1)
dev.off()

###########################################
# Temporal Evolution of Extreme Pollution #
###########################################

# Exploratory count of NA values per year shows 2016 has extreme
# increase in NA values, over 10 times the second largest count in 2007.

# remove 2016 for further analysis
NO <- df %>%
  filter(year < 2016)

# threshold determined in Section 3.1
u <- 131.18

# Filter dataset to just exceedances
NO_exceed <- NO %>%
  filter(NO > u) %>%
  filter(!is.na(NO))

# Get exceedances per year
exceed_rate <- NO_exceed %>%
  group_by(year) %>%
  summarise(n_exceed = n(), .groups = "drop")
exceed_rate
# Note we see an overall dowmnward trend in the table

# Plot of exceedances demonstrating downward trend in time
ggplot(exceed_rate, aes(x = year, y = n_exceed)) +
  geom_line() +
  labs(y = "Exceedances", x = "Year")
# Displays a downward trend with spikes in 2011, 2012, 2013

# Linear Model Fit
lm_exceed <- lm(n_exceed ~ year, data = exceed_rate)
summary(lm_exceed)
# p-value < 0.05 => statistically significant temporal trend
# negative coeefcient trend is downward


# calculate residuals and plot ACF as seen in LAB 2
e0 <- resid(lm_exceed)

par(mfrow = c(1, 3))
plot(exceed_rate$year, e0, type = "l", xlab = "Year",ylab = "Residual", main = "Residual Time Series")
abline(h = 0, lty = 2)

acf(e0,  main = "Residual ACF")
pacf(e0, main = "Residual PACF")
# shows no breaches of CI's so we can progress without ARIMA
par(mfrow = c(1, 1))

# Model Summary Plots
par(mfrow = c(1, 4))
plot(lm_exceed, which = 1:4)
par(mfrow = c(1, 1))
############################################
# Modelling with Meteorological Covariates #
############################################

#Monthly Exceedances
exceed_month <- df %>%
  group_by(month) %>%
  summarise(n_exceed = sum(NO > u_main, na.rm = TRUE),
            .groups = "drop")

ggplot(exceed_month, 
       aes(x = month, y = n_exceed)) +
  geom_line(color = "steelblue") +
  geom_point(color = "steelblue", size = 1.5)+
  scale_x_continuous(breaks = 1:12, labels = month.abb) +
  theme_minimal() +
  labs(title = "Monthly Exceedances",
       x = "Month", y = "Number of Exceedances")


df_modified <- df %>%
  mutate(sin_month = sin(2 * pi * month / 12),
         cos_month = cos(2 * pi * month / 12)) %>%
  dplyr::select(NO, temperature, wind_speed, pressure, sin_month, cos_month, city) %>%
  drop_na()


fit_stat  <- fevd(x = NO, data = df_modified,
                  threshold = u_main, type = "GP")
fit_seasonality <- fevd(x = NO, data = df_modified,
                        threshold = u_main, type = "GP",
                        scale.fun = ~sin_month + cos_month)
lr.test(fit_stat, fit_seasonality) #p-value 0.011, evidence seasonality is important to model


fit_temp  <- fevd(x = NO, data = df_modified,
                  threshold = u_main, type = "GP",
                  scale.fun = ~temperature)
fit_temp_seasonality  <- fevd(x = NO, data = df_modified,
                              threshold = u_main, type = "GP",
                              scale.fun = ~temperature +  sin_month + cos_month)

lr.test(fit_stat, fit_temp) #p-value 0.62 
lr.test(fit_seasonality, fit_temp_seasonality) #p-value 0.33


fit_wind  <- fevd(x = NO, data = df_modified,
                  threshold = u_main, type = "GP",
                  scale.fun = ~wind_speed)
fit_wind_seasonality  <- fevd(x = NO, data = df_modified,
                              threshold = u_main, type = "GP",
                              scale.fun = ~wind_speed +  sin_month + cos_month)

lr.test(fit_stat, fit_wind)  #p-value 0.496
lr.test(fit_seasonality, fit_wind_seasonality)  #p-value 0.79



fit_pressure  <- fevd(x = NO, data = df_modified,
                      threshold = u_main, type = "GP",
                      scale.fun = ~pressure)
fit_pressure_seasonality  <- fevd(x = NO, data = df_modified,
                                  threshold = u_main, type = "GP",
                                  scale.fun = ~pressure +  sin_month + cos_month)

lr.test(fit_stat, fit_pressure)  #p-value 0.13
lr.test(fit_seasonality, fit_pressure_seasonality)  #p-value 0.08

#not much evidence to suggest any meterological covariates can improve model. 
#of the three covariates, pressure best improves model.

# Fig: Monthly exceedances by city
exceed_city_month <- df %>%
  group_by(city, month) %>%
  summarise(n_exceed = sum(NO > u_main, na.rm = TRUE),
            .groups = "drop")

p_city_month <- ggplot(exceed_city_month, 
                       aes(x = month, y = n_exceed)) +
  geom_line(color = "steelblue") +
  geom_point(color = "steelblue", size = 1.5) +
  scale_x_continuous(breaks = 1:12, labels = month.abb) +
  facet_wrap(~city) +
  theme_minimal() +
  labs(title = "Monthly Exceedances by City",
       x = "Month", y = "Number of Exceedances")
ggsave("plots/Fig7_City_Monthly_Exceedances.png", 
       plot = p_city_month,
       width = 10, height = 7, dpi = 300, create.dir = TRUE)

df_no_wind <- df %>%
  mutate(sin_month = sin(2 * pi * month / 12),
         cos_month = cos(2 * pi * month / 12)) %>%
  dplyr::select(NO, temperature, sin_month, cos_month, city) %>%
  drop_na()

# City exceedance counts
city_counts <- df_no_wind %>%
  filter(NO > u_main) %>%
  count(city, name = "Exceedances") %>%
  arrange(desc(Exceedances))
print(city_counts)

# Rubidoux (n = 66 — sufficient for modelling)
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

# Roseville (n = 20 — borderline, interpret with caution)
df_roseville <- df_no_wind %>% filter(city == "Roseville")

fit_stat_ros <- fevd(x = NO, data = df_roseville,
                     threshold = u_main, type = "GP")
fit_full_ros <- fevd(x = NO, data = df_roseville,
                     threshold = u_main, type = "GP",
                     scale.fun = ~temperature + sin_month + cos_month)

lr.test(fit_stat_ros, fit_full_ros)

###########################################################
# Variariation of Extreme Pollution Levels Between Cities #
###########################################################

# Examining different levels in the raw data:

# Make table of maximum NO concentration and number of exceedances recorded in 
# each city
df_ex_city <- df %>%
  group_by(city) %>%
  summarise(Maximum = as.integer(max(NO, na.rm=TRUE)), 
            `N Exceedances` = sum(NO>u_main, na.rm=TRUE)) %>%
  rename(City = city)
df_ex_city
ex_tab <- xtable(df_ex_city)
print(ex_tab, include.rownames = FALSE)

# Now to compare the cities we can model
# We only have two(ish) models, so want to compare them to see if extreme values
# are similar between cities
# Note: results for Roseville are borderline

# How many obs each
df_obs <- df %>%
  filter(city %in% c("Rubidoux", "Roseville")) %>%
  group_by(city) %>%
  summarise(N=sum(!is.na(NO)))
df_obs
# Both got a bit of missing data

# Sample sizes not very large, can't assume difference in rates is normal
# Therefore Wald test is not appropriate
# Poisson test for count of exceedances:

# Number of exceedances
n1 <- city_counts$Exceedances[city_counts$city=="Rubidoux"]
n2 <- city_counts$Exceedances[city_counts$city=="Roseville"]

# Total observation period (ie number of recorded months)
t1 <- nrow(df_no_wind[df_no_wind$city=="Rubidoux",])
t2 <- nrow(df_no_wind[df_no_wind$city=="Roseville",])

poisson.test(c(n1,n2), c(t1,t2))
# Conclude that true rate ratio is not equal to 1, therefore exceedances do not 
# occur at the same rates in these cities

# Convert data frame to a spatial object to create a map
sf_df <- st_as_sf(df, coords = c("long", "lat"), crs = 4326)

# Create a column containing the mean NO concentration at each site
sf_df <- sf_df %>% 
  group_by(site) %>%
  mutate(NO_mean = mean(`NO`, na.rm=TRUE)) %>%
  ungroup()

# Make a map  
mapview(sf_df, zcol="NO_mean")

# Variation does not appear to be correlated to location i.e. longitude or proximity
# to coast
# Appears that main influence is proximity to larger urban areas


########################
# Improving Estimation #
########################

# Q5: IMPROVING ESTIMATION

# City-specific thresholds
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
    scale = round(params["scale"], 3),
    shape = round(params["shape"], 3)
  ))
}

print(city_gpd)

city_gpd %>%
  knitr::kable(
    col.names = c("City", "Threshold (ppb)", "Scale", "Shape"),
    caption   = "City-specific GPD parameter estimates.",
    digits    = 3
  )


# End of R code




