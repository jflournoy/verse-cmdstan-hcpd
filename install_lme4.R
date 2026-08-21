#!/usr/bin/env Rscript
# Pin lme4 to the version that matches this image's Matrix.
#
# The image ships lme4 2.0-1 on top of the rocker base's Matrix 1.6-1.1. That
# pair does not work: fitting anything with lmer() dies at load time with
#   function 'cholmod_factor_ldetA' not provided by package 'Matrix'
# lme4 2.0-1 links against Matrix internals that only exist in Matrix >= 1.7,
# but its DESCRIPTION only declares LinkingTo Matrix (>= 1.5-0), so the install
# succeeds and the failure surfaces at analysis time instead.
#
# Nothing under R/ uses lme4 directly. It reaches the project through psych::ICC
# (an ICC cross-check in the test suite) and through
# analysis_reports/data_check_FEEDBACK_WIN_LOSE.qmd. The breakage went unnoticed
# for as long as it did because the test helper and several reports prepended a
# host-only user library that carried a working lme4 1.1-38 -- the same
# mechanism that hid the ggseg migration. Once that shadowing was removed, this
# became visible.
#
# Pinned DOWN to 1.1-38 rather than upgrading Matrix, because Matrix CANNOT be
# upgraded here: Matrix 1.7-x is the first release to export the symbol lme4
# wants, and it declares Depends: R (>= 4.4) while this image is R 4.3.2.
# Verified against the image itself -- its Matrix 1.6.1.1 exports
# `chm_factor_ldetL2` and no `cholmod_factor_ldetA` at all.
#
# The version pin ALONE is not the fix, and this is the part that is easy to get
# wrong. A CRAN binary of lme4 1.1-38 is compiled against whatever Matrix the
# build farm had (1.7-4), so it fails at lmer() with the exact same
# cholmod_factor_ldetA error the pin was supposed to cure. lme4 compiles
# Matrix's `Matrix_stubs.c` from the INSTALLED Matrix's include directory, so a
# SOURCE build resolves the symbol against 1.6.1.1 and works. Hence
# type = "source" below -- it is load-bearing, not a preference.
#
# Run inside the container image build (see Dockerfile).

LME4_VERSION <- "1.1-38"

# 2026-02-01, not the image's default 2025-06-02 snapshot: 1.1-38 does not exist
# at 2025-06-02 (that snapshot carries 1.1-37) and install_version() cannot reach
# forward in time through the CRAN archive. The Dockerfile passes this date
# explicitly so the image-wide CRAN_SNAPSHOT -- held at 2025-06-02 for gratia
# 0.10.0 -- does not override it.
#
# Deliberately the plain snapshot URL rather than the __linux__/jammy one used
# elsewhere: that prefix exists to serve precompiled binaries, which is exactly
# what must NOT happen here.
REPO <- Sys.getenv("CRAN_SNAPSHOT",
                   "https://packagemanager.posit.co/cran/2026-02-01")
options(repos = c(CRAN = REPO), Ncpus = max(1L, parallel::detectCores() - 1L))

if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")

# Deliberately NOT requireNamespace("lme4"): that would LOAD the image's broken
# lme4 2.0-1 into this session, and R never replaces an already-loaded namespace
# within a session. packageVersion() reads DESCRIPTION off disk without loading
# anything.
installed_version <- function(pkg) {
  tryCatch(as.character(utils::packageVersion(pkg)),
           error = function(e) NA_character_)
}

have <- identical(installed_version("lme4"),
                  as.character(package_version(LME4_VERSION)))
if (!have) {
  message("Installing lme4 ", LME4_VERSION,
          " (Matrix ", as.character(packageVersion("Matrix")), ")")
  remotes::install_version("lme4", version = LME4_VERSION,
                           repos = REPO, type = "source", upgrade = "never")
}

# Verify by FITTING, not by loading, and do it in a FRESH R process. Both halves
# are load-bearing:
#   - by fitting, because the ABI mismatch only appears when the model object is
#     constructed, which is exactly why it survives an install; and
#   - in a fresh process, because anything earlier in THIS session (remotes and
#     its dependencies included) may already have loaded the old lme4's
#     namespace, and R will not swap it for the one we just wrote to disk. A
#     same-session library(lme4) would keep calling the replaced 2.0-1 DLL and
#     fail against a package that is no longer installed.
verify <- '
  suppressPackageStartupMessages(library(lme4))
  fit <- lme4::lmer(Reaction ~ Days + (Days | Subject), lme4::sleepstudy)
  if (!inherits(fit, "lmerMod") || !is.finite(as.numeric(logLik(fit)))) {
    stop("lme4 installed but lmer() did not produce a usable fit", call. = FALSE)
  }
  cat("lme4", as.character(packageVersion("lme4")),
      "installed and verified against Matrix",
      as.character(packageVersion("Matrix")), "\n")
'
if (system2(file.path(R.home("bin"), "Rscript"),
            c("-e", shQuote(verify))) != 0L) {
  stop("lme4 verification failed; see the output above", call. = FALSE)
}
