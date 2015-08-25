#!/usr/bin/env Rscript
update.packages(repos = "http://cran.us.r-project.org", ask = FALSE)

install.packages(
  repos = "http://cran.us.r-project.org",
  c(
    "Rcpp",
    "dplyr",
    "tidyr",
    "lubridate",
    "devtools",
    "knitr",
    "httr",
    "ggplot2",
    "NPS",
    "arm",
    "lme4",
    "RPushbullet",
    "Cairo",
    "boxr"
  )
)

source('http://mc-stan.org/rstan/install.R', echo = TRUE, max.deparse.length = 2000)
install_rstan()

