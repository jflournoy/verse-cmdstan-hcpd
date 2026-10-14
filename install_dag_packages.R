#!/usr/bin/env Rscript
# Install the DAG-drawing packages for the reproducibility container.
#
# dagitty and ggdag are used by two reports only -- reports/dag_analysis_report.qmd
# and reports/control_variables_brief.qmd -- to draw and query the causal DAG
# behind the covariate choices. They are report dependencies, not analysis
# dependencies: nothing in R/ needs them and no fitted model depends on them.
#
# They were never in the image. dag_analysis_report.qmd tried to paper over that
# with `if (!require("dagitty")) install.packages("dagitty")` at render time,
# which cannot work in a sealed container (no network, no writable site library)
# and failed with "unable to install packages" on every render since 2026-08-04.
# A report that installs its own dependency is not reproducible; the dependency
# belongs in the image.
#
# Uses the image's date-pinned CRAN snapshot (CRAN_SNAPSHOT) so the build stays
# reproducible, matching install_gratia.R.
#
# Run inside the container image build (see Dockerfile).

PKGS <- c(dagitty = "0.3-4", ggdag = "0.2.13")

REPO <- Sys.getenv("CRAN_SNAPSHOT",
                   "https://packagemanager.posit.co/cran/2025-06-02")
lib <- .libPaths()[1]
message("Installing DAG packages into ", lib)

if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", repos = REPO)
}

for (pkg in names(PKGS)) {
  want <- package_version(PKGS[[pkg]])
  if (requireNamespace(pkg, quietly = TRUE) && packageVersion(pkg) == want) {
    message(pkg, " ", want, " already present")
    next
  }
  remotes::install_version(pkg, version = PKGS[[pkg]],
                           repos = REPO,
                           upgrade = "never", lib = lib)
  if (!requireNamespace(pkg, quietly = TRUE) || packageVersion(pkg) != want) {
    stop(sprintf("FAILED to install %s %s", pkg, want), call. = FALSE)
  }
  message("installed ", pkg, " ", as.character(packageVersion(pkg)))
}
