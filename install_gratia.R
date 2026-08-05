#!/usr/bin/env Rscript
# Install gratia and its dependencies for the reproducibility container.
#
# gratia supplies the simultaneous-interval derivative machinery the
# developmental shape taxonomy classifies on (gratia::derivatives(...,
# interval = "simultaneous")). Pinned to an explicit version so the container
# build is reproducible: an unpinned install would silently change the shape
# criteria the moment upstream changes how derivatives are computed.
#
# Run inside the container image build (see Dockerfile).

GRATIA_VERSION <- "0.10.0"

# Posit's date-pinned CRAN snapshot: same URL always resolves to the same
# package sources, which a plain CRAN mirror does not guarantee.
REPO <- Sys.getenv("CRAN_SNAPSHOT",
                   "https://packagemanager.posit.co/cran/__linux__/jammy/2025-06-02")

options(repos = c(CRAN = REPO), Ncpus = max(1L, parallel::detectCores() - 1L))

need <- function(pkg) !requireNamespace(pkg, quietly = TRUE)

# mvnfast is gratia's fast multivariate-normal sampler, used for the posterior
# draws behind simultaneous intervals. Everything else gratia needs
# (dplyr/tidyr/tibble/purrr/rlang/vctrs/ggplot2/patchwork/withr) already ships
# in the rocker verse base; install only what is missing.
deps <- c("mvnfast")
missing <- Filter(need, deps)
if (length(missing) > 0) {
  message("Installing gratia dependencies: ", paste(missing, collapse = ", "))
  install.packages(missing)
}

if (need("gratia") ||
    packageVersion("gratia") != package_version(GRATIA_VERSION)) {
  message("Installing gratia ", GRATIA_VERSION)
  if (need("remotes")) install.packages("remotes")
  remotes::install_version("gratia", version = GRATIA_VERSION,
                           repos = REPO, upgrade = "never")
}

# Fail the build loudly rather than producing an image that silently lacks the
# package -- a missing gratia would make every shape label fall back or error at
# analysis time, long after the image was built.
for (p in c(deps, "gratia")) {
  if (!requireNamespace(p, quietly = TRUE)) {
    stop(sprintf("FAILED to install '%s'", p), call. = FALSE)
  }
}

# The taxonomy calls derivatives() with these arguments; verify the installed
# version actually accepts them, so an upstream API change breaks the BUILD
# rather than the analysis.
suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(gratia))
set.seed(1)
d <- data.frame(x = seq(0, 1, length.out = 200))
d$y <- sin(2 * pi * d$x) + rnorm(200, sd = 0.2)
fit <- gam(y ~ s(x), data = d, method = "REML")
# `select=` rather than `term=`: term was deprecated in gratia 0.8.9.9 and
# still works in 0.10.0 only with a warning. Verifying against the current
# argument means this check fails when `term` is finally removed upstream
# rather than passing on a deprecation warning we'd never see in build logs.
chk <- gratia::derivatives(fit, select = "s(x)", type = "central",
                           interval = "simultaneous", n_sim = 100, n = 50)
stopifnot(is.data.frame(chk), nrow(chk) == 50)
lower_col <- intersect(c(".lower_ci", "lower"), names(chk))
if (length(lower_col) == 0) {
  stop("gratia::derivatives() returned no recognisable lower-CI column; ",
       "the shape taxonomy's column mapping needs updating for this version",
       call. = FALSE)
}

message("gratia ", as.character(packageVersion("gratia")),
        " installed and verified (CI columns: ",
        paste(intersect(c(".lower_ci", "lower", ".upper_ci", "upper"),
                        names(chk)), collapse = ", "), ")")
