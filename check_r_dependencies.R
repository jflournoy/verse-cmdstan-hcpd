#!/usr/bin/env Rscript
# Check that every installed R package's declared dependencies are met: the R
# equivalent of `pip check`.
#
# Each install_*.R step verifies the packages it pins, but nothing checked what
# those installs did to everything ELSE. A dependency that resolves to a version
# needing a newer R, or a pinned package that needs a newer version of something
# already in the image, can install cleanly and still leave a package that fails
# at load time, or at analysis time. This runs last, over every library on
# .libPaths(), and fails the build on any unmet Depends / Imports / LinkingTo
# constraint, R itself included.
#
# KNOWN lists violations already present in the base image, which this image
# does not install or own. Each entry must still be violated: one that has been
# fixed fails the check, so the list cannot go stale.
#
# Run inside the container image build (see Dockerfile).

KNOWN <- character(0)

ip <- installed.packages(fields = c("Depends", "Imports", "LinkingTo"))
ip <- ip[!duplicated(ip[, "Package"]), , drop = FALSE]  # first on .libPaths() wins, as library() does
have <- setNames(ip[, "Version"], ip[, "Package"])
have[["R"]] <- as.character(getRversion())
base_pkgs <- rownames(installed.packages(priority = "base"))

parse_deps <- function(field) {
  if (is.na(field) || !nzchar(field)) return(NULL)
  parts <- trimws(strsplit(gsub("\\s+", " ", field), ",")[[1]])
  parts <- parts[nzchar(parts)]
  m <- regmatches(parts, regexec("^([[:alnum:].]+)\\s*(\\(\\s*([<>=!]+)\\s*([^)]+)\\))?", parts))
  do.call(rbind, lapply(m, function(x) data.frame(pkg = x[2], op = x[4], ver = trimws(x[5]))))
}

problems <- character(0)
for (i in seq_len(nrow(ip))) {
  pkg <- ip[i, "Package"]
  deps <- do.call(rbind, lapply(c("Depends", "Imports", "LinkingTo"),
                                function(f) parse_deps(ip[i, f])))
  if (is.null(deps)) next
  for (j in seq_len(nrow(deps))) {
    d <- deps[j, ]
    if (d$pkg %in% base_pkgs && d$pkg != "R") next
    if (!d$pkg %in% names(have)) {
      problems <- c(problems, sprintf("%s %s: needs %s, which is not installed",
                                      pkg, ip[i, "Version"], d$pkg))
      next
    }
    if (is.na(d$op) || !nzchar(d$op)) next
    ok <- do.call(d$op, list(package_version(have[[d$pkg]]), package_version(d$ver)))
    if (!ok) {
      problems <- c(problems, sprintf("%s %s: needs %s %s %s, has %s",
                                      pkg, ip[i, "Version"], d$pkg, d$op, d$ver, have[[d$pkg]]))
    }
  }
}

problems <- unique(problems)
new <- setdiff(problems, KNOWN)
fixed <- setdiff(KNOWN, problems)
if (length(problems)) message("Dependency violations:\n  ", paste(problems, collapse = "\n  "))
if (length(fixed)) message("KNOWN entries no longer violated (remove them):\n  ",
                           paste(fixed, collapse = "\n  "))
if (length(new) || length(fixed)) stop("R dependency check failed", call. = FALSE)
message(sprintf("R dependency check: %d packages consistent (%d known base-image violations).",
                nrow(ip), length(KNOWN)))
