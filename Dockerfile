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

# =============================================================================
# ggseg + ggsegGlasser -- the brain figures.
#
# Pinned to explicit commits rather than GitHub HEAD. Unpinned, the image
# silently moved from ggseg 1.x to 2.x, which changed the atlas from a list to
# a constructor function and renamed `side` to `view`; downstream code kept
# targeting 1.x by prepending a host-only user library, and every published
# brain PNG froze. install_ggseg.R draws a plot at build time so that kind of
# drift fails HERE.
#
# The CRAN combination (ggseg 2.0.0 + ggsegGlasser 1.0.1 + ggseg.formats 0.0.1)
# is incompatible with ggplot2 4.x -- LayerBrain$setup_layer calls
# as.data.frame() on a brain_atlas S3 list with no method -- which is why these
# come from GitHub commits rather than from the snapshot.
#
# CRAN_SNAPSHOT is overridden for this step only: the ggsegverse packages come
# from their SHAs, but their CRAN dependencies (sf, sfheaders, dplyr, tidyr)
# resolve against this date, and a recent one serves jammy binaries instead of
# source-building sf.
# =============================================================================

COPY install_ggseg.R /tmp/install_ggseg.R

RUN CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/jammy/2026-08-01 \
    Rscript /tmp/install_ggseg.R && rm /tmp/install_ggseg.R

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

# =============================================================================
# dagitty + ggdag -- report-only dependencies for the causal-DAG reports.
#
# Installed into the image rather than at render time: a report that calls
# install.packages() on itself cannot work in a sealed container and is not
# reproducible either way. Both versions are current at the image-wide
# CRAN_SNAPSHOT, so this step inherits it unchanged.
# =============================================================================

COPY install_dag_packages.R /tmp/install_dag_packages.R

RUN Rscript /tmp/install_dag_packages.R && rm /tmp/install_dag_packages.R

# =============================================================================
# lme4 -- pinned DOWN from the image's 2.0-1, and built FROM SOURCE.
#
# lme4 2.0-x calls a Matrix routine this image's Matrix 1.6.1.1 does not export,
# so lmer() dies at model construction with
#   function 'cholmod_factor_ldetA' not provided by package 'Matrix'
# while the install itself succeeds. Matrix cannot be upgraded to fix it:
# Matrix 1.7-x declares Depends: R (>= 4.4) and this image is R 4.3.2.
#
# The version pin alone is NOT sufficient. A CRAN binary of 1.1-38 is compiled
# against the build farm's Matrix 1.7-4 and reproduces the identical error --
# this exact build failed that way once. lme4 compiles Matrix's Matrix_stubs.c
# from the installed Matrix's headers, so a source build resolves the symbol
# against 1.6.1.1 and works. install_lme4.R therefore passes type = "source",
# and verifies by FITTING a model rather than merely loading the package,
# because the mismatch only surfaces at model construction.
#
# The snapshot is overridden here because 1.1-38 does not exist at 2025-06-02
# (that snapshot carries 1.1-37), and install_version() cannot reach a future
# version through the CRAN archive. Note the PLAIN snapshot URL, not the
# __linux__/jammy one used elsewhere: that prefix serves precompiled binaries,
# which is precisely what must not happen here.
# =============================================================================

COPY install_lme4.R /tmp/install_lme4.R

RUN CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/2026-02-01 \
    Rscript /tmp/install_lme4.R && rm /tmp/install_lme4.R

# =============================================================================
# patchwork -- pinned UP to a version with ggplot2 4.x (S7) theme support.
#
# ggplot2 4.0 moved themes to S7; patchwork 1.3.0 has no S7 method for `&`, so
# the idiom used to apply one theme across a composed figure --
#     (p_a | p_b) & theme(legend.position = "bottom")
# -- fails with "Can't find method for generic `&(e1, e2)`". 1.3.2 adds it.
# install_patchwork.R composes and DRAWS such a figure at build time.
#
# Same snapshot override, same reason: 1.3.2 postdates the 2025-06-02 pin.
# =============================================================================

COPY install_patchwork.R /tmp/install_patchwork.R

RUN CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/jammy/2026-02-01 \
    Rscript /tmp/install_patchwork.R && rm /tmp/install_patchwork.R

WORKDIR /home/rstudio
