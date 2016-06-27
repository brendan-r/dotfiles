#!/usr/bin/env Rscript
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

install.packages("rstan", dependencies = TRUE)
