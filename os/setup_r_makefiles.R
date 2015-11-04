#!/usr/bin/env Rscript
#
# Recommended by the Stan team
# See https://github.com/stan-dev/rstan/wiki/RStan-Getting-Started#configuration
#
# This will set-up a makevars file which is optmized for Stan executing code.
# However, they do note that this *might* cause problems for other pakcages
# compiling during installation. Beware!

dotR <- file.path(Sys.getenv("HOME"), ".R")
if (!file.exists(dotR)) dir.create(dotR)
M <- file.path(dotR, "Makevars")
if (!file.exists(M)) file.create(M)
cat("\nCXXFLAGS=-O3", file = M, sep = "\n", append = TRUE)

# As you're likely to be using g++ > 4.9, the follwing is recommended
cat("\nCXXFLAGS+=-flto -ffat-lto-objects",
    file = M, sep = "\n", append = TRUE)

