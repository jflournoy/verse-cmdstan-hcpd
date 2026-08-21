#!/usr/bin/env Rscript
# Pin patchwork to a version that works with the image's ggplot2 4.x.
#
# ggplot2 4.0 moved themes to S7. patchwork 1.3.0 (what the image shipped) has
# no S7 method for `&`, so the idiom this project uses everywhere to apply one
# theme across a composed figure --
#     (p_male | p_female) & theme(legend.position = "bottom")
# -- dies with:
#     Can't find method for generic `&(e1, e2)`: e1: <patchwork>, e2: <theme>
# patchwork 1.3.2 adds the S7 methods.
#
# Like the ggseg and lme4 pins, this was masked for months: the reports and the
# test helper prepended a host-only user library that happened to carry
# patchwork 1.3.2, so every composed figure rendered on this host and would have
# failed in the release container.
#
# Run inside the container image build (see Dockerfile).

PATCHWORK_VERSION <- "1.3.2"

# 2026-02-01, not the image's default 2025-06-02 snapshot: the pinned version
# below is the CURRENT version at this date, so the jammy binary repo serves it
# directly. At 2025-06-02 it does not exist yet, and install_version() cannot
# reach forward in time via the CRAN archive. The Dockerfile passes this same
# date explicitly so the image-wide CRAN_SNAPSHOT (held at 2025-06-02 for
# gratia 0.10.0) does not override it.
REPO <- Sys.getenv("CRAN_SNAPSHOT",
                   "https://packagemanager.posit.co/cran/__linux__/jammy/2026-02-01")
options(repos = c(CRAN = REPO), Ncpus = max(1L, parallel::detectCores() - 1L))

if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")

# packageVersion(), not requireNamespace(): loading the OLD patchwork here would
# pin this session to it, and R never replaces a loaded namespace mid-session --
# the verification below would then test the very version we are replacing.
current <- tryCatch(utils::packageVersion("patchwork"),
                    error = function(e) NULL)
have <- !is.null(current) && current >= package_version(PATCHWORK_VERSION)
if (!have) {
  message("Installing patchwork ", PATCHWORK_VERSION)
  remotes::install_version("patchwork", version = PATCHWORK_VERSION,
                           repos = REPO, upgrade = "never")
}

# Verify the exact operation the renderers use, and DRAW it: the missing S7
# method only surfaces when `&` is dispatched, not when the package loads.
#
# Run in a fresh R process for the same reason as install_lme4.R -- gratia's
# dependency tree installs patchwork 1.3.0, so by the time this script runs the
# old version may already be loaded in-session and library(patchwork) would
# silently keep using it, testing the wrong version and passing or failing for
# the wrong reason.
verify <- '
  suppressPackageStartupMessages({
    library(ggplot2)
    library(patchwork)
  })
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  composed <- (p | p) & theme(legend.position = "bottom")
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  print(composed)
  cat("patchwork", as.character(packageVersion("patchwork")),
      "installed and verified against ggplot2",
      as.character(packageVersion("ggplot2")), "\n")
'
if (system2(file.path(R.home("bin"), "Rscript"),
            c("-e", shQuote(verify))) != 0L) {
  stop("patchwork verification failed; see the output above", call. = FALSE)
}
