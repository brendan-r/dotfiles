#!/usr/bin/env Rscript
install.packages(
  repos = "http://cran.us.r-project.org",
  c(
    "Rcpp",
    "tidyverse",
    "lubridate",
    "devtools",
    "rmarkdown",
    "httr",
    "arm",
    "lme4",
    "Cairo",
    "prophet"
  )
)
