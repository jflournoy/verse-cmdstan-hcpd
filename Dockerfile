FROM jflournoy/verse-cmdstan:latest
LABEL maintainer="John Flournoy <jcflournoyphd@pm.me>"

# ========================================
# Connectome Workbench (wb_command, wb_view)
# ========================================
# Installs from NeuroDebian. wb_command -show-scene renders scenes
# headlessly via OSMesa, so no X server/VNC is required.
USER root
RUN . /etc/os-release \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl gnupg ca-certificates \
 && curl -fsSL "http://neuro.debian.net/lists/${VERSION_CODENAME}.us-nh.full" \
      -o /etc/apt/sources.list.d/neurodebian.sources.list \
 && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x439754ED1F42AA2C" \
      | gpg --dearmor -o /usr/share/keyrings/neurodebian-archive-keyring.gpg \
 && sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/neurodebian-archive-keyring.gpg] |' \
      /etc/apt/sources.list.d/neurodebian.sources.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      connectome-workbench \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Smoke test: confirm wb_command is on PATH and can report its version.
RUN wb_command -version | head -5

# ========================================
# ggseg stack pinned to GitHub main
# ========================================
# The CRAN ggseg 2.0.0 + ggsegGlasser 1.0.1 + ggseg.formats 0.0.1 combo
# is incompatible with ggplot2 4.x: LayerBrain$setup_layer calls
# as.data.frame() on a brain_atlas S3 list that has no method, and the
# ggseg_atlas method in ggseg.formats fails on a NULL $core slot under
# vctrs 1.x. Upstream has fixes on GitHub main. We install all three
# from main and verify with a build-time smoke test so a bad upstream
# commit fails the image build rather than silently breaking reports.
RUN R -q -e ' \
  options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest")); \
  remotes::install_github("ggseg/ggseg.formats", upgrade = "never", quiet = TRUE); \
  remotes::install_github("ggseg/ggseg",         upgrade = "never", quiet = TRUE); \
  remotes::install_github("ggseg/ggsegGlasser",  upgrade = "never", quiet = TRUE); \
  for (pkg in c("ggseg", "ggsegGlasser", "ggseg.formats")) { \
    cat(sprintf("%-15s %s\n", pkg, as.character(packageVersion(pkg)))); \
  }; \
  suppressPackageStartupMessages({ library(ggseg); library(ggsegGlasser); library(ggplot2) }); \
  glasser_atlas <- if (is.function(ggsegGlasser::glasser)) ggsegGlasser::glasser() else ggsegGlasser::glasser; \
  cat("glasser_atlas class:", paste(class(glasser_atlas), collapse=","), "\n"); \
  df <- data.frame(region = c("V1", "MST", "V6"), hemi = "left", val = c(1, -1, 2)); \
  p <- ggplot(df) + \
       geom_brain(atlas = glasser_atlas, aes(fill = val), \
                  position = position_brain(view ~ hemi)); \
  invisible(ggplot2::ggplot_build(p)); \
  cat("ggseg smoke test: PASS\n") \
'

# =============================================================================
# gratia — simultaneous-interval derivatives for the developmental shape
# taxonomy.
#
# Why gratia rather than a hand-rolled derivative: the shape taxonomy's U /
# inverted-U test asks whether the fitted age trajectory's FIRST DERIVATIVE
# credibly changes sign, under a SIMULTANEOUS (whole-curve) interval. gratia
# implements exactly that construction, is maintained by mgcv's own ecosystem,
# and keeps the criterion auditable against a published reference rather than
# against our own linear algebra.
#
# Pinned deliberately. An unpinned install would let an upstream change to
# derivatives() silently alter which parcels are called U-shaped.
# =============================================================================

# System libraries gratia's dependency tree needs. Most are already present in
# rocker/verse; listed explicitly so this block is self-contained if the base
# image changes.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libxml2-dev \
        libssl-dev \
        libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Date-pinned CRAN snapshot: the same URL always resolves to the same sources.
# The __linux__/jammy prefix serves precompiled binaries for this base image,
# which keeps the same pin without compiling gratia's tree from source.
ENV CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/jammy/2025-06-02

COPY install_gratia.R /tmp/install_gratia.R

# The script verifies the install by calling derivatives() with the exact
# arguments the taxonomy uses, so an API drift fails HERE, at build time,
# instead of silently at analysis time.
RUN Rscript /tmp/install_gratia.R && rm /tmp/install_gratia.R

WORKDIR /home/rstudio
