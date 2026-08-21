#!/usr/bin/env Rscript
# Install ggseg + ggsegGlasser for the reproducibility container.
#
# Every brain figure in the paper is drawn by ggseg::geom_brain() against the
# ggsegGlasser atlas. Neither package is on CRAN, so DESCRIPTION's
# `Remotes: ggseg/ggseg, ggseg/ggsegGlasser` resolved to whatever GitHub HEAD
# happened to be on the day the image was built. That is how the project ended
# up with ggseg 2.1.1 in the image and ggseg 1.6.8 in a host-only user library,
# with the code written against 1.x, the reports pinned to 1.x via .libPaths(),
# and every published brain PNG frozen at 2026-05-06 because nothing could draw
# one any more.
#
# Pinned to explicit commits, and VERIFIED by drawing a plot: an upstream API
# change now breaks the image BUILD instead of silently freezing the figures.
#
# NOTE on the same-session hazard that bit install_lme4.R and install_patchwork.R:
# the loop below uses requireNamespace() for its "already present" check, which
# LOADS the old package, and R never replaces a loaded namespace within a
# session -- so the smoke test could end up exercising the version being
# replaced. It does not bite here only because the base image's ggseg 2.0.0 is
# incompatible with its ggplot2 4.x and fails to load at all, leaving nothing
# stale behind. That is a property of the current base image, not of this
# script. If a future base bump ships a loadable-but-wrong ggseg, move the
# verification below into a fresh Rscript subprocess the way the other two
# scripts do.
#
# Run inside the container image build (see Dockerfile).

# ggseg.formats is listed FIRST and deliberately. Both ggseg 2.x and
# ggsegGlasser 2.x Import it, neither declares a `Remotes:` entry pointing at
# it, and it did not reach CRAN until mid-2026 -- so under any date-pinned
# snapshot older than that, install_github("ggseg/ggseg@<sha>") fails at
# dependency resolution. Installing it from its own pinned commit first
# satisfies the Import, and `upgrade = "never"` below keeps remotes from
# reaching for a different one afterwards.
#
# Its SHA is the commit that was HEAD when ggseg 2.1.1 was cut (2026-04-03 vs
# 2026-04-16). The three ggsegverse repos move in lockstep, so contemporaneous
# commits are the compatible set; the smoke test at the bottom of this file is
# what actually proves it.
PKGS <- list(
  ggseg.formats = list(
    repo    = "ggsegverse/ggseg.formats",
    sha     = "3ff5ef6b05fbcccb5e4361dab795366c038ffdbc",
    version = "0.0.2"
  ),
  ggseg = list(
    repo    = "ggsegverse/ggseg",
    sha     = "9bfef3abd681b1ac62a3a8ae9db5a7f4f006dbac",
    version = "2.1.1"
  ),
  ggsegGlasser = list(
    repo    = "ggsegverse/ggsegGlasser",
    sha     = "c4f44cbb4502c0351be99adf17538b2d463720ca",
    version = "2.0.3"
  )
)

# A recent snapshot, so the heavy CRAN dependencies (sf, sfheaders, dplyr,
# tidyr) resolve as jammy binaries instead of source-building sf. The three
# ggsegverse packages come from their SHAs regardless of this date, and
# `upgrade = "never"` keeps the install from disturbing the image's ggplot2 4.x,
# which the smoke test below requires.
REPO <- Sys.getenv("CRAN_SNAPSHOT",
                   "https://packagemanager.posit.co/cran/__linux__/jammy/2026-08-01")
options(repos = c(CRAN = REPO), Ncpus = max(1L, parallel::detectCores() - 1L))

lib <- .libPaths()[1]
if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")

for (pkg in names(PKGS)) {
  spec <- PKGS[[pkg]]
  have <- requireNamespace(pkg, quietly = TRUE) &&
    packageVersion(pkg) == package_version(spec$version)
  if (have) {
    message(pkg, " ", spec$version, " already present")
    next
  }
  message("Installing ", pkg, " ", spec$version, " @ ", substr(spec$sha, 1, 8))
  remotes::install_github(paste0(spec$repo, "@", spec$sha),
                          upgrade = "never", lib = lib)
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("FAILED to install '%s'", pkg), call. = FALSE)
  }
  if (packageVersion(pkg) != package_version(spec$version)) {
    stop(sprintf(paste("Installed %s %s but the pin says %s; the SHA and the",
                       "version in PKGS have drifted apart -- update both."),
                 pkg, as.character(packageVersion(pkg)), spec$version),
         call. = FALSE)
  }
}

# ---------------------------------------------------------------------------
# Verify the API the analysis code actually uses. Installing the package is not
# enough: what broke last time was a shape change (atlas list -> constructor
# function, `side` column -> `view`) that leaves the install perfectly healthy
# and every figure unrenderable.
# ---------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(ggplot2)
  library(ggseg)
  library(ggsegGlasser)
})

# 1. The atlas is a constructor, and it produces a cortical atlas with a
#    region/hemi/label core of exactly 360 parcels.
if (!is.function(ggsegGlasser::glasser)) {
  stop("ggsegGlasser::glasser is not a function; this is not the 2.x API",
       call. = FALSE)
}
atlas <- ggsegGlasser::glasser()
stopifnot(
  inherits(atlas, "ggseg_atlas"),
  inherits(atlas, "cortical_atlas"),
  all(c("hemi", "region", "label") %in% names(atlas$core)),
  nrow(atlas$core) == 360L
)

# 2. The two sagittal views the figures draw are present.
views <- unique(as.character(atlas$data$sf$view))
missing_views <- setdiff(c("lateral", "medial"), views)
if (length(missing_views) > 0) {
  stop("Glasser atlas is missing view(s): ",
       paste(missing_views, collapse = ", "), call. = FALSE)
}

# 3. A plot BUILDS. ggplot2 is lazy, so only ggplot_build() exercises the
#    atlas join, the position and the geom.
d <- data.frame(region = c("V1", "V2", "10d"),
                hemi = c("left", "right", "left"),
                value = c(1, 2, 3))
p <- ggplot(d) +
  geom_brain(mapping = aes(fill = value), atlas = atlas,
             view = c("lateral", "medial"),
             position = position_brain(view ~ hemi))
built <- ggplot_build(p)
layer_data <- ggplot2::get_layer_data(built, 1L)
stopifnot(
  nrow(layer_data) > 100L,
  setequal(unique(layer_data$hemi), c("left", "right")),
  setequal(unique(as.character(layer_data$view)), c("lateral", "medial")),
  length(unique(layer_data$fill)) > 1L
)

# 4. It reaches a device.
f <- tempfile(fileext = ".png")
ggsave(f, p, width = 6, height = 4, dpi = 72)
if (!file.exists(f) || file.size(f) == 0) {
  stop("ggseg plot did not reach the graphics device", call. = FALSE)
}
unlink(f)

message("ggseg ", as.character(packageVersion("ggseg")),
        " + ggsegGlasser ", as.character(packageVersion("ggsegGlasser")),
        " installed and verified (brain plot renders)")
