#!/usr/bin/env Rscript
## ---------------------------------------------------------------------------
## 01b_fit_priors.R — estimate the baseline coefficients yourself, instead of
## using the literature defaults shipped in lib/priors.R.
##
## Usage:
##   Rscript pipeline/01b_fit_priors.R --spec pipeline/prior_fits.csv
##   Rscript pipeline/01b_fit_priors.R --spec pipeline/prior_fits.csv --dry-run
##
## Output: pipeline/out/prior_coefs_fitted.csv, which lib/priors.R picks up via
## cfg$prior_coef_path. Outcomes you do not fit keep their shipped defaults, so
## a partial fit is perfectly fine — fit the ones your microdata measures well
## and leave the rest.
##
##
## WHY BOTHER, GIVEN THE DEFAULTS
##
## The shipped coefficients are read off published summaries: a partisan
## confidence split here, a meta-analytic ordering there. That is enough to get
## the direction and rough magnitude right, but published summaries almost
## never report the thing we actually need — a regression of the outcome on all
## six moderators simultaneously. Reported gaps are marginal, so the "education
## effect" in a press release is partly a party effect wearing a different hat.
## Fitting the six jointly on microdata removes that confounding, and it is the
## difference between a prior that is roughly right and one that is defensible.
##
##
## WHAT YOU NEED
##
## Any public US microdata file with (a) the six moderators and (b) at least
## one item that plausibly measures one of the 13 outcomes. ANES, GSS and the
## Yale Climate Opinion survey series all qualify. NOTHING IS DOWNLOADED
## AUTOMATICALLY and no variable names are guessed for you: you write the
## crosswalk, because a silently mismapped variable produces a plausible-looking
## coefficient that is simply wrong, and no assertion in this file could catch it.
##
## Formats: csv, tsv, rds, RData, and — via `haven` — sav, dta, sas7bdat, xpt.
## Read the archive's own file rather than exporting to CSV first. NORC ships
## the GSS only as SPSS / Stata / SAS, and an export step is where missing-value
## codes quietly become data.
##
##
## BLINDING (registration attestation)
##
## Every source you fit on must predate and be independent of the target study.
## Public reference surveys are fine. Any pilot, preprint or partial release
## from the megastudy being predicted is not — fitting on it would make your
## submission a retrodiction, and the attestation in registration.md false.
##
##
## THE SPEC FILE
##
## A CSV with one row per outcome you want to fit:
##
##   outcome,            data_path,      item,     item_min,item_max,weight,spec,min_year,notes
##   trust_post,         gssr::gss_all,  consci,   3,       1,       wtssps,gss, 2016,"confidence in sci community, reversed"
##   funding_perceptions,gssr::gss_all,  natenvir, 3,       1,       wtssps,gss, 2016,"env spending"
##
##   outcome    one of the 13 (must match submission_spec.R)
##   data_path  a file you downloaded yourself, OR `pkg::dataset` for data
##              bundled in an R package — `gssr::gss_all` is the GSS cumulative
##              file (1972-2024, release 3), no download and no format
##              conversion
##   item       the column holding the outcome, in that file
##   item_min   source value meaning the LOWEST point of the target 0-100 scale
##   item_max   source value meaning the HIGHEST point
##              (swap them, as above, for a reverse-coded source item)
##   weight     survey weight column. Missing name = hard error, not a silent
##              unweighted fit. Leave empty to fit unweighted on purpose.
##   spec       which RECODE_SPECS entry maps this file's demographics
##              ("anes_cumulative", "anes_2020", "gss"); empty = cfg$source_type
##   min_year   earliest wave to include; empty = cfg$min_year. See the note in
##              prep_source() — this one matters more than it looks.
##   notes      free text, copied into the output for registration.md
##
## The moderator columns are read through the same crosswalk machinery
## 01_build_profiles.R uses (RECODE_SPECS in lib/anes_recode.R). The `spec`
## column exists because the fitting source need not be the donor source: you
## can build the pool from ANES and fit a coefficient on GSS.
##
##
## THE LINEAR RESCALING IS AN ASSUMPTION
##
## Mapping a 5-point Likert item onto 0-100 by stretching its endpoints assumes
## the categories are equally spaced and that the source item measures the same
## construct as the benchmark's slider. Neither is exactly true. It is a far
## better assumption than transcribing a marginal percentage, and a far worse
## one than having the actual item. Say so in registration.md D.2 — the fitted
## `source` column carries the item name so you can.
## ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) && length(args) > i[1]) args[i[1] + 1] else default
}
spec_path <- get_arg("--spec", "pipeline/prior_fits.csv")
dry_run   <- "--dry-run" %in% args

source("pipeline/00_config.R")
source("pipeline/lib/anes_recode.R")
source("pipeline/lib/priors.R")
source("scripts/lib/submission_spec.R")

set.seed(cfg$seed + 1L)

if (!file.exists(spec_path)) {
  stop("No spec file at '", spec_path, "'.\n\n",
       "Create one with these columns:\n",
       "  outcome,data_path,item,item_min,item_max,weight,notes\n\n",
       "See the header of this script for what each column means.",
       call. = FALSE)
}

spec <- readr::read_csv(spec_path, show_col_types = FALSE)
req  <- c("outcome", "data_path", "item", "item_min", "item_max")
miss <- setdiff(req, names(spec))
if (length(miss)) {
  stop("Spec file is missing column(s): ", paste(miss, collapse = ", "),
       call. = FALSE)
}

bad <- setdiff(spec$outcome, sst$outcomes)
if (length(bad)) {
  stop("Spec names outcome(s) the benchmark does not score: ",
       paste(bad, collapse = ", "), call. = FALSE)
}

message(sprintf("Fitting %d outcome(s) from %d source file(s)",
                nrow(spec), dplyr::n_distinct(spec$data_path)))


## ---------------------------------------------------------------------------
## Prepare one source file: moderators on benchmark levels + the outcome item
## rescaled to 0-100 (or 0-10 for the donation outcome).
## ---------------------------------------------------------------------------

## Read whatever the archive actually ships. NORC distributes the GSS as SPSS,
## Stata and SAS only — there is no CSV — so insisting on CSV would force a
## manual export step, and exporting from SPSS or Stata to CSV is exactly where
## missing-value codes get silently turned into data. `haven` reads the native
## formats and preserves them.
read_microdata <- function(path) {

  ## `pkg::object` loads a dataset bundled in an R package rather than a file.
  ## The case this exists for is gssr, which ships the GSS Cumulative File
  ## (1972-2024, release 3) as an R data object — no download, no format
  ## conversion, and the haven labels arrive intact.
  ##
  ##   install.packages("gssr",
  ##     repos = c("https://kjhealy.r-universe.dev", "https://cloud.r-project.org"))
  ##
  ## Note gssr deliberately does NOT lazy-load: `gssr::gss_all` on its own does
  ## not work, you have to data() it. Hence the explicit load below.
  if (grepl("^[A-Za-z][A-Za-z0-9.]*::[A-Za-z._][A-Za-z0-9._]*$", path)) {
    parts <- strsplit(path, "::", fixed = TRUE)[[1]]
    pkg <- parts[1]; obj <- parts[2]
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Package '", pkg, "' is not installed.",
           if (pkg == "gssr") paste0(
             '\n  install.packages("gssr", repos = c(',
             '"https://kjhealy.r-universe.dev", "https://cloud.r-project.org"))',
             '\n  (and "gssrdoc" too — it puts the GSS codebook in R\'s help ',
             'system, which is how you check a variable means what you think)'
           ) else "", call. = FALSE)
    }
    e <- new.env()
    utils::data(list = obj, package = pkg, envir = e)
    if (!exists(obj, envir = e, inherits = FALSE)) {
      stop("Package '", pkg, "' has no dataset '", obj, "'.", call. = FALSE)
    }
    df <- get(obj, envir = e, inherits = FALSE)
    message(sprintf("  loaded %s: %d rows x %d columns", path,
                    nrow(df), ncol(df)))
    if (requireNamespace("haven", quietly = TRUE)) {
      df[] <- lapply(df, function(x)
        if (inherits(x, "haven_labelled")) haven::zap_labels(x) else x)
    }
    return(df)
  }

  if (!file.exists(path)) {
    stop("Source file not found: '", path, "'. Nothing is downloaded ",
         "automatically.", call. = FALSE)
  }
  ext <- tolower(tools::file_ext(path))

  if (ext %in% c("csv", "tsv", "txt")) {
    return(readr::read_delim(path, show_col_types = FALSE, guess_max = 50000,
                             delim = if (ext == "csv") "," else "\t"))
  }
  if (ext %in% c("rds")) return(readRDS(path))
  if (ext %in% c("rdata", "rda")) {
    e <- new.env(); load(path, envir = e)
    objs <- ls(e)
    if (length(objs) != 1L) {
      stop("'", path, "' contains ", length(objs), " objects (",
           paste(objs, collapse = ", "), "). Save the one data frame you want ",
           "as .rds instead.", call. = FALSE)
    }
    return(get(objs[1], envir = e))
  }
  if (ext %in% c("sav", "zsav", "por", "dta", "sas7bdat", "xpt")) {
    if (!requireNamespace("haven", quietly = TRUE)) {
      stop("Reading '", ext, "' needs the haven package: ",
           'install.packages("haven")', call. = FALSE)
    }
    df <- switch(ext,
      sav = , zsav = , por = haven::read_spss(path),
      dta                = haven::read_dta(path),
      sas7bdat           = haven::read_sas(path),
      xpt                = haven::read_xpt(path))
    ## haven returns labelled vectors. The crosswalks in anes_recode.R match on
    ## the underlying CODE, not the label, so strip the labels rather than let
    ## as.character() render them as text and miss every map entry.
    df[] <- lapply(df, function(x) if (inherits(x, "haven_labelled")) haven::zap_labels(x) else x)
    return(df)
  }
  stop("Unsupported file type '.", ext, "'. Supported: csv, tsv, rds, RData, ",
       "sav, dta, sas7bdat, xpt.", call. = FALSE)
}

prep_source <- function(path, item, item_min, item_max, weight_col,
                        spec_name = NULL, min_year = NULL) {

  raw <- read_microdata(path)

  if (!item %in% names(raw)) {
    stop("Item '", item, "' not found in ", path, ".\nColumns starting with '",
         substr(item, 1, 3), "': ",
         paste(utils::head(grep(paste0("^", substr(item, 1, 3)), names(raw),
                                value = TRUE), 20), collapse = ", "),
         call. = FALSE)
  }

  ## Which demographic crosswalk applies to THIS file. Defaults to the one the
  ## donor pool uses, but a GSS file needs the GSS spec — applying the ANES
  ## crosswalk to it would fail on the first missing column, which is the good
  ## outcome, or map a coincidentally-named column, which is not.
  sn <- if (is.null(spec_name) || is.na(spec_name) || !nzchar(spec_name)) {
    cfg$source_type
  } else spec_name
  rspec <- RECODE_SPECS[[sn]]
  if (is.null(rspec)) {
    stop("Unknown recode spec '", sn, "'. Available: ",
         paste(names(RECODE_SPECS), collapse = ", "), call. = FALSE)
  }
  message("  crosswalk: ", sn)
  validate_recode_spec(raw, rspec)
  d <- recode_anes(raw, rspec, fold_leaners = TRUE)

  y <- suppressWarnings(as.numeric(raw[[item]]))

  ## RESTRICT THE YEARS. This is not housekeeping; it is the single most
  ## consequential choice in the whole fitting step.
  ##
  ## The GSS cumulative file runs from 1972 and the ANES cumulative from 1948.
  ## Pooling all of it estimates an average partisan gap over half a century,
  ## and the partisan gap in trust in science is not a constant — it widened
  ## sharply after 2000 and again after 2020. A coefficient fitted on the full
  ## series would materially understate today's polarisation, and the anchors
  ## built from it would place Republicans far too close to Democrats.
  ##
  ## Defaults to cfg$min_year, the same cut the donor pool uses.
  my <- if (is.null(min_year) || is.na(min_year)) cfg$min_year else min_year
  if (!is.null(my) && !is.null(rspec$year_var) && rspec$year_var %in% names(raw)) {
    yr <- suppressWarnings(as.numeric(raw[[rspec$year_var]]))
    keep <- !is.na(yr) & yr >= my
    message(sprintf("  year filter (>= %d): %d -> %d rows", as.integer(my),
                    nrow(d), sum(keep)))
    d <- d[keep, ]; y <- y[keep]; raw <- raw[keep, ]
    if (sum(keep)) {
      yrs <- sort(unique(yr[keep]))
      message("  waves used: ", paste(yrs, collapse = ", "))
    }
  } else if (!is.null(my)) {
    message("  no year variable in this spec; using all rows")
  }

  ## Negative sentinels and out-of-range codes are missing, not data. ANES in
  ## particular uses -9/-8/-7 for refused / don't know / no post-interview;
  ## treating those as low scores would manufacture a gradient out of
  ## non-response, which correlates with the moderators.
  lo <- min(item_min, item_max)
  hi <- max(item_min, item_max)
  y[y < lo | y > hi] <- NA

  ## Linear stretch onto 0-100, honouring a reversed source item.
  d$y <- if (item_min <= item_max) {
    100 * (y - item_min) / (item_max - item_min)
  } else {
    100 * (item_min - y) / (item_min - item_max)
  }

  ## Survey weight. A silently-unweighted fit is a real risk here: GSS weight
  ## names have changed across releases (wtssall / wtssps / wtssnrps), so a
  ## stale name in the spec file would fall through to unweighted without
  ## anyone noticing. Fail loudly instead, and say what IS available.
  if (!is.null(weight_col) && !is.na(weight_col) && nzchar(weight_col)) {
    if (!weight_col %in% names(raw)) {
      cand <- grep("^(wt|weight|VCF0009|V2000)", names(raw), value = TRUE,
                   ignore.case = TRUE)
      stop("Weight column '", weight_col, "' not found in ", path,
           ".\nWeight-looking columns present: ",
           if (length(cand)) paste(utils::head(cand, 15), collapse = ", ")
           else "(none)",
           "\nLeave the `weight` cell empty to fit unweighted, deliberately.",
           call. = FALSE)
    }
    w <- suppressWarnings(as.numeric(raw[[weight_col]]))
    w[is.na(w) | w <= 0] <- NA
    d$w <- w
    message(sprintf("  weight: %s (%.1f%% usable)", weight_col,
                    100 * mean(!is.na(w))))
  } else {
    d$w <- rep(1, nrow(d))
    message("  weight: none (unweighted)")
  }

  core <- c("gender", "age_band", "race", "education", "income", "party")
  d <- d[stats::complete.cases(d[, c(core, "y")]) & !is.na(d$w), ]
  d
}


## ---------------------------------------------------------------------------
## Fit and convert to the priors.R parameterisation.
##
## priors.R expects party offsets relative to Independent, standardised slopes
## for education / age / income, and level offsets for female and non-white —
## so the regression is specified in exactly that form and the coefficients
## transfer without further arithmetic.
## ---------------------------------------------------------------------------

fit_one <- function(d, outcome) {

  z <- function(x) {
    s <- stats::sd(x, na.rm = TRUE)
    if (is.na(s) || s == 0) rep(0, length(x)) else (x - mean(x, na.rm = TRUE)) / s
  }

  d$party    <- factor(d$party, levels = c("Independent", "Republican",
                                           "Democrat", "Other"))
  d$educ_z   <- z(match(d$education, TARGET_LEVELS$education))
  d$income_z <- z(match(d$income,    TARGET_LEVELS$income))
  d$age_z    <- z(d$age)
  d$female   <- as.numeric(d$gender == "Female")
  d$nonwhite <- as.numeric(d$race != "White / Caucasian")

  m <- stats::lm(y ~ party + educ_z + age_z + female + nonwhite + income_z,
                 data = d, weights = d$w)
  b <- stats::coef(m)
  g <- function(nm) if (nm %in% names(b) && !is.na(b[[nm]])) unname(b[[nm]]) else 0

  ## Residual SD of the fit is the between-person spread net of the six
  ## moderators — precisely the `resid_sd` priors.R wants.
  rsd <- stats::sigma(m)
  r2  <- summary(m)$r.squared

  ## The donation outcome lives on 0-10, not 0-100; the source item was
  ## rescaled to 0-100 above, so scale the whole fit back down.
  k <- if (identical(outcome, "donation_ams")) 0.1 else 1

  list(
    row = data.frame(
      outcome            = outcome,
      base               = k * g("(Intercept)"),
      party_Republican   = k * g("partyRepublican"),
      party_Democrat     = k * g("partyDemocrat"),
      party_Independent  = 0,
      party_Other        = k * g("partyOther"),
      educ               = k * g("educ_z"),
      age                = k * g("age_z"),
      female             = k * g("female"),
      nonwhite           = k * g("nonwhite"),
      income             = k * g("income_z"),
      resid_sd           = k * rsd,
      stringsAsFactors   = FALSE),
    n = nrow(d), r2 = r2)
}


## ---------------------------------------------------------------------------
## Run
## ---------------------------------------------------------------------------

rows  <- list()
report <- list()

for (i in seq_len(nrow(spec))) {
  s <- spec[i, ]
  message(sprintf("\n%s  <-  %s [%s]", s$outcome, basename(s$data_path), s$item))

  d <- prep_source(s$data_path, s$item, s$item_min, s$item_max,
                   if ("weight"   %in% names(s)) s$weight   else NA,
                   if ("spec"     %in% names(s)) s$spec     else NA,
                   if ("min_year" %in% names(s)) s$min_year else NA)
  if (nrow(d) < 200) {
    warning("Only ", nrow(d), " usable rows for ", s$outcome,
            "; coefficients will be noisy. Skipping.")
    next
  }

  f <- fit_one(d, s$outcome)
  r <- f$row
  r$source <- paste0("fitted: ", basename(s$data_path), " [", s$item, "]",
                     if ("notes" %in% names(s) && !is.na(s$notes))
                       paste0(" - ", s$notes) else "")
  rows[[length(rows) + 1L]] <- r

  gap <- r$party_Democrat - r$party_Republican
  message(sprintf("  n = %d, R2 = %.3f, resid_sd = %.1f, D-R gap = %+.1f",
                  f$n, f$r2, r$resid_sd, gap))

  ## The two numbers most worth eyeballing. R2 far above ~.40 means the six
  ## moderators explain more than they do in any real attitude data and the
  ## anchors will separate subgroups too sharply; a D-R gap beyond ~45 points
  ## on a 0-100 item is larger than any documented US partisan gap on these
  ## questions.
  if (f$r2 > 0.40) {
    warning(sprintf("R2 = %.2f for %s is high for an attitude item; check ",
                    f$r2, s$outcome),
            "that the source item is not partly a party-identification item.")
  }
  if (abs(gap) > 45 && s$outcome != "donation_ams") {
    warning(sprintf("D-R gap of %+.1f points for %s exceeds anything ",
                    gap, s$outcome),
            "documented in US survey data; check item_min / item_max.")
  }

  report[[length(report) + 1L]] <- data.frame(
    outcome = s$outcome, source = basename(s$data_path), item = s$item,
    n = f$n, r2 = round(f$r2, 3), resid_sd = round(r$resid_sd, 2),
    dr_gap = round(gap, 2), stringsAsFactors = FALSE)
}

if (!length(rows)) stop("Nothing was fitted.", call. = FALSE)

fitted <- dplyr::bind_rows(rows)

message("\n--- Fitted vs shipped literature priors ---")
cmp <- merge(
  fitted[, c("outcome", "base", "party_Republican", "party_Democrat", "resid_sd")],
  PRIOR_BASELINE[, c("outcome", "base", "party_Republican", "party_Democrat", "resid_sd")],
  by = "outcome", suffixes = c("_fit", "_lit"))
print(cmp %>% mutate(across(where(is.numeric), ~ round(.x, 1))), row.names = FALSE)
message("\nLarge disagreements are informative, not embarrassing: they usually")
message("mean the source item measures something adjacent rather than the same")
message("construct. Decide which to trust per outcome, and record the decision.")

if (dry_run) {
  message("\n--dry-run: nothing written.")
  quit(save = "no")
}

out_path <- file.path(dirname(cfg$responses_out), "prior_coefs_fitted.csv")
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(fitted, out_path)
readr::write_csv(dplyr::bind_rows(report),
                 file.path(dirname(out_path), "prior_fit_report.csv"))

message(sprintf("\n[OK] wrote %s (%d outcomes)", out_path, nrow(fitted)))
message("Set cfg$prior_coef_path to this path in pipeline/00_config.R to use it.")
