# ============================
# Q1: Extreme NO via POT (GPD)
# Clean R script (no Quarto)
# ============================

library(tidyverse)
library(lubridate)
library(extRemes)

# ---- 1) Load + tidy data ----
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
  )

# Keep finite NO values for EVT
df_clean <- df %>% filter(is.finite(NO))
no_clean <- df_clean$NO

# Monthly data => 12 obs/year
m_per_year <- 12

# ---- 2) Candidate thresholds (quantiles) + exceedance counts ----
thresholds <- quantile(no_clean, probs = c(0.80, 0.85, 0.90, 0.95), na.rm = TRUE)

cand_tbl <- tibble(
  Quantile   = c("80th", "85th", "90th", "95th"),
  Threshold  = as.numeric(thresholds),
  N_exceed   = purrr::map_int(thresholds, ~sum(no_clean > .x)),
  Pct_exceed = purrr::map_dbl(thresholds, ~mean(no_clean > .x) * 100)
) %>%
  mutate(
    Threshold  = round(Threshold, 2),
    Pct_exceed = round(Pct_exceed, 2)
  )

print(cand_tbl)

# ---- 3) Histogram + candidate threshold lines ----
hist(no_clean, breaks = 60, col = "grey80", border = "white",
     main = "Monthly NO with Candidate Thresholds", xlab = "NO Concentration")

abline(v = thresholds["80%"], col = "forestgreen", lty = 2, lwd = 2)
abline(v = thresholds["90%"], col = "orange",      lty = 2, lwd = 2)
abline(v = thresholds["95%"], col = "tomato",      lty = 2, lwd = 2)

legend("topright",
       legend = c("80th", "90th", "95th"),
       col    = c("forestgreen", "orange", "tomato"),
       lty    = 2, lwd = 2, bty = "n")

# ---- 4) Mean Residual Life plot (MRL) ----
mrlplot(no_clean,
        main = "Mean Residual Life Plot",
        xlab = "Threshold u",
        col  = "steelblue",
        lwd  = 2)

abline(v = thresholds["80%"], col = "forestgreen", lty = 2, lwd = 2)
abline(v = thresholds["90%"], col = "orange",      lty = 2, lwd = 2)
abline(v = thresholds["95%"], col = "tomato",      lty = 2, lwd = 2)

legend("topright",
       legend = c("80th", "90th", "95th"),
       col    = c("forestgreen", "orange", "tomato"),
       lty    = 2, lwd = 2, bty = "n")

# ---- 5) Choose threshold u (primary + sensitivity) ----
u_main <- as.numeric(thresholds["90%"])  # primary
u_sens <- as.numeric(thresholds["95%"])  # sensitivity

cat("\nChosen u_main (90%):", round(u_main, 2), "\n")
cat("Chosen u_sens (95%):", round(u_sens, 2), "\n")

# ---- 6) Fit GPD (POT) using extRemes ----
fit_main <- fevd(no_clean, threshold = u_main, type = "GP", method = "MLE")
fit_sens <- fevd(no_clean, threshold = u_sens, type = "GP", method = "MLE")

cat("\n--- GPD fit at u_main ---\n")
print(summary(fit_main))

cat("\n--- GPD fit at u_sens ---\n")
print(summary(fit_sens))

# ---- 7) Diagnostics ----
# extRemes provides a standard diagnostic panel

par(mfrow = c(2,2), mar = c(3,3,2,1))  # smaller margins
plot(fit_main)
par(mfrow = c(1,1))
# ---- 8) Return levels (10y, 50y) via POT formula ----
exceed_rate_per_year <- function(x, u, m_per_year = 12) {
  n  <- length(x)
  Nu <- sum(x > u)
  lambda <- m_per_year * (Nu / n)  # expected exceedances per year
  list(n = n, Nu = Nu, lambda = lambda)
}

pot_return_level <- function(u, sigma, xi, lambda, T_years) {
  if (abs(xi) < 1e-8) {
    u + sigma * log(T_years * lambda)
  } else {
    u + (sigma / xi) * ((T_years * lambda)^xi - 1)
  }
}

rate_main <- exceed_rate_per_year(no_clean, u_main, m_per_year)

par_main   <- fit_main$results$par
sigma_main <- unname(par_main["scale"])
xi_main    <- unname(par_main["shape"])

T_vals <- c(10, 50)

return_tbl <- tibble(
  T_years = T_vals,
  zT = purrr::map_dbl(T_vals, ~pot_return_level(u_main, sigma_main, xi_main, rate_main$lambda, .x))
)

cat("\n--- Exceedance rate info (u_main) ---\n")
print(rate_main)

cat("\n--- Return levels (u_main) ---\n")
print(return_tbl)

# ---- 9) Flag extremes in monitoring data ----
df_flagged <- df_clean %>%
  mutate(
    extreme_u_main = NO > u_main,
    extreme_u_sens = NO > u_sens
  )

cat("\n--- Counts flagged as extremes ---\n")
print(df_flagged %>% summarise(
  n_total = n(),
  n_extreme_u_main = sum(extreme_u_main),
  n_extreme_u_sens = sum(extreme_u_sens)
))

# Optional: list top extreme events
cat("\n--- Top 10 NO values ---\n")
print(df_flagged %>% arrange(desc(NO)) %>% select(date, city, site, NO) %>% head(10))

