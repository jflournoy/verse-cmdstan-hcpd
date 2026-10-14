#!/usr/bin/env Rscript
# Install the packages the code uses that the image lacked.
#
# Every one of these lived only in the host user library
# (~/R/x86_64-pc-linux-gnu-library/4.3), which R puts on .libPaths() by
# itself whenever that directory exists. So the code worked on this host and
# nowhere else: under Snakemake (which runs jobs with HOME set to the project)
# and in the release image they were simply missing. kableExtra was missing
# from both; the model report had a fallback that dropped its table coloring
# silently. tests/testthat/test-image-has-used-packages.R fails while any
# package the code uses resolves from outside the image.
#
# Pinned to the versions the code has been running against (the host
# library's, 2026-10-05; kableExtra to its 1.4.0 release), and each VERIFIED by
# exercising what the code calls, so an install that cannot do the job fails
# HERE, at build time.
#
# Run inside the container image build (see Dockerfile). This file is a copy of
# the analysis project's docker/install_render_packages.R; keep the two in sync.

PKGS <- c(
  # gsl is FIRST and the order matters. energy declares it in Imports, and the
  # index's current gsl, 2.1-9, declares Depends: R (>= 4.5.0). This image is
  # R 4.3.2, so available.packages() filters 2.1-9 out and gsl LOOKS absent
  # from every index (snapshot and cloud.r-project.org alike); resolving
  # energy's dependencies then fails with "dependency 'gsl' is not available"
  # and the build dies at the energy step. Installing 2.1-8, the last release
  # that supports R 4.3, first satisfies the dependency before energy asks for
  # it. install_version() reaches it through the snapshot's archive, and the
  # base image already carries libgsl.so.27 and /usr/include/gsl to compile
  # against. Verified 2026-10-14.
  gsl         = "2.1.8",   # energy's Imports; 2.1-9 needs R >= 4.5, so pinned here
  ciftiTools  = "0.19.0",  # R/subcortical_parcel_geometry.R, dropout audit; its
                           # extdata surfaces feed the raw-signal figure
  energy      = "1.7-12",  # reports/motion_signal_exploration.qmd (dcor)
  GGally      = "2.4.0",   # reports/motion_signal_exploration.qmd (ggpairs)
  hexbin      = "1.28.5",  # scripts/dropout_coverage_vs_varcope.R
  psych       = "2.5.6",   # data-check and measurement-variability reports (ICC)
  scico       = "1.5.0",   # R/per_parcel_age_maps.R and others (vik palette)
  targets     = "1.11.4",  # run_pipeline.R, the cluster-network fits
  tarchetypes = "0.13.2",  # _targets.R
  kableExtra  = "1.4.0"    # analysis_reports/model_analysis_report.qmd
)

REPO <- Sys.getenv("CRAN_SNAPSHOT",
                   "https://packagemanager.posit.co/cran/2025-06-02")
options(repos = c(CRAN = REPO), Ncpus = max(1L, parallel::detectCores() - 1L))
lib <- .libPaths()[1]
if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")

for (pkg in names(PKGS)) {
  want <- package_version(PKGS[[pkg]])
  if (requireNamespace(pkg, quietly = TRUE) && packageVersion(pkg) == want) {
    message(pkg, " ", want, " already present")
    next
  }
  message("Installing ", pkg, " ", want)
  # One pinned repo, no fallback. The fallback used to be here because five of
  # these pins are older than the snapshot head and so come from its archive --
  # but the snapshot serves its own archive, and all of hexbin, psych, targets,
  # tarchetypes and kableExtra were verified to resolve from REPO alone on
  # 2026-10-14. A fallback to cloud.r-project.org is a moving target, which is
  # the wrong thing to leave in a build whose purpose is a reproducible image.
  remotes::install_version(pkg, version = PKGS[[pkg]], upgrade = "never",
                           lib = lib, repos = REPO)
  if (!requireNamespace(pkg, quietly = TRUE) || packageVersion(pkg) != want) {
    stop(sprintf("FAILED to install %s %s", pkg, want), call. = FALSE)
  }
}

# ---------------------------------------------------------------------------
# Verify by using each package the way the code does.
# ---------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(ggplot2)
  library(data.table)
})
check <- function(what, expr) {
  ok <- tryCatch({ force(expr); TRUE }, error = function(e) {
    message("FAILED: ", what, ": ", conditionMessage(e)); FALSE
  })
  if (!ok) stop("package verification failed: ", what, call. = FALSE)
  message("ok: ", what)
}
draw <- function(p) {
  f <- tempfile(fileext = ".png")
  ggsave(f, p, width = 3, height = 2, dpi = 50)
  stopifnot(file.size(f) > 0)
  unlink(f)
}
set.seed(1)
xy <- data.table(x = rnorm(500), y = rnorm(500))

check("ciftiTools surfaces for the raw-signal figure", {
  ext <- system.file("extdata", package = "ciftiTools")
  for (h in c("L", "R")) {
    stopifnot(file.exists(file.path(ext, sprintf("S1200.%s.inflated_MSMAll.32k_fs_LR.surf.gii", h))))
  }
  stopifnot(is.function(ciftiTools::read_cifti))
})
check("energy::dcor", {
  d <- energy::dcor(xy$x, xy$x^2)
  stopifnot(is.numeric(d), d > 0)
})
check("GGally::ggpairs draws", {
  f <- tempfile(fileext = ".png")
  png(f); print(GGally::ggpairs(as.data.frame(xy))); dev.off()
  stopifnot(file.size(f) > 0)
})
check("hexbin stat_binhex draws", {
  draw(ggplot(xy, aes(x, y)) + stat_binhex(aes(fill = after_stat(log10(count))), bins = 20))
})
check("psych::ICC", {
  m <- cbind(a = xy$x, b = xy$x + rnorm(500, sd = 0.3))
  r <- psych::ICC(m, lmer = FALSE)
  stopifnot(nrow(r$results) == 6)
})
check("scico vik scale draws", {
  draw(ggplot(xy, aes(x, y, fill = x)) + geom_tile() +
         scico::scale_fill_scico(palette = "vik", midpoint = 0))
})
check("targets namespace", {
  stopifnot(is.function(targets::tar_make), is.function(tarchetypes::tar_map))
})
check("kableExtra styles an HTML table", {
  h <- kableExtra::kable_styling(knitr::kable(head(mtcars), format = "html"),
                                 bootstrap_options = "striped")
  stopifnot(grepl("table-striped", as.character(h)))
})
message("All render packages verified.")
