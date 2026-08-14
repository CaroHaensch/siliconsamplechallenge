#!/usr/bin/env Rscript
## ---------------------------------------------------------------------------
## 01_build_profiles.R — build the synthetic respondent pool.
##
##   ANES donor rows  ->  benchmark moderator levels  ->  latent traits
##                    ->  response style  ->  condition assignment
##
## Usage:
##   Rscript pipeline/01_build_profiles.R --dry-run   # inspect, write nothing
##   Rscript pipeline/01_build_profiles.R
##
## Output: pipeline/out/profiles.csv, one row per synthetic respondent.
##
## WHY DONOR ROWS RATHER THAN A FACTORIAL GRID
## Drawing gender, age, race, education, income and party independently from
## their marginals produces cells that barely exist in the population (a
## 25-year-old Republican with a doctorate earning under $30k) and destroys
## every predictor-predictor correlation. Since the Tier-2 moderator file is
## scored on subgroup means, that correlation structure is not cosmetic:
## the "Bachelor's degree" cell mean depends on who actually holds bachelor's
## degrees. Sampling whole respondent rows, weighted, preserves the joint
## distribution for free.
## ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

args    <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args

source("pipeline/00_config.R")
source("pipeline/lib/anes_recode.R")
source("pipeline/lib/states.R")

set.seed(cfg$seed)


## ---------------------------------------------------------------------------
## 0. Assert our level strings still match the benchmark's
## ---------------------------------------------------------------------------
## submission_spec.R is the benchmark's single source of truth. If the
## organizers rename a level, this stops the run rather than letting us
## produce a file that fails `make check` after a full simulation spend.
source("scripts/lib/submission_spec.R")
for (m in names(TARGET_LEVELS)) {
  if (!identical(TARGET_LEVELS[[m]], sst$moderators[[m]])) {
    stop(sprintf(
      "Level mismatch for '%s'.\n  pipeline: %s\n  benchmark: %s\nUpdate TARGET_LEVELS in pipeline/lib/anes_recode.R.",
      m,
      paste(TARGET_LEVELS[[m]], collapse = " | "),
      paste(sst$moderators[[m]], collapse = " | ")
    ), call. = FALSE)
  }
}
message("✓ moderator levels match submission_spec.R")


## ---------------------------------------------------------------------------
## 1. Read and recode the donor file
## ---------------------------------------------------------------------------
if (!file.exists(cfg$anes_path)) {
  stop(sprintf(
    paste0("ANES file not found at '%s'.\n\n",
           "ANES data requires a free account; nothing is downloaded ",
           "automatically. Get it from https://electionstudies.org/data-center/ ",
           "and set cfg$anes_path in pipeline/00_config.R."),
    cfg$anes_path
  ), call. = FALSE)
}

spec <- RECODE_SPECS[[cfg$source_type]]
if (is.null(spec)) {
  stop("Unknown cfg$source_type: ", cfg$source_type,
       ". Available: ", paste(names(RECODE_SPECS), collapse = ", "))
}

raw <- readr::read_csv(cfg$anes_path, show_col_types = FALSE,
                       guess_max = 50000)
message(sprintf("Read %s rows x %s columns", nrow(raw), ncol(raw)))

message("Checking crosswalk against the file:")
validate_recode_spec(raw, spec)

donors <- recode_anes(raw, spec, fold_leaners = TRUE)

if (!is.null(spec$year_var) && !is.null(cfg$min_year)) {
  before  <- nrow(donors)
  donors  <- donors[!is.na(donors$year) &
                      as.numeric(donors$year) >= cfg$min_year, ]
  message(sprintf("Year filter (>= %d): %d -> %d rows",
                  cfg$min_year, before, nrow(donors)))
}

## Complete cases on the six scored moderators only. Auxiliary variables may
## be missing; the backstory renderer simply omits what it does not have.
core    <- c("gender", "age_band", "race", "education", "income", "party")
before  <- nrow(donors)
donors  <- donors[stats::complete.cases(donors[, core]), ]
message(sprintf("Complete cases on the six moderators: %d -> %d rows (%.1f%% dropped)",
                before, nrow(donors), 100 * (1 - nrow(donors) / before)))

if (nrow(donors) < 500) {
  stop("Fewer than 500 usable donor rows. The crosswalk is almost certainly ",
       "mapping the wrong columns — re-check the unmapped-code report above.",
       call. = FALSE)
}

if (cfg$use_weights) {
  donors$weight[is.na(donors$weight) | donors$weight <= 0] <- NA
  n_bad <- sum(is.na(donors$weight))
  if (n_bad > 0.5 * nrow(donors)) {
    warning("More than half the survey weights are missing or non-positive; ",
            "falling back to unweighted sampling. Check cfg / spec$weight_var.")
    donors$weight <- 1
  } else {
    donors$weight[is.na(donors$weight)] <- stats::median(donors$weight, na.rm = TRUE)
  }
} else {
  donors$weight <- 1
}


## ---------------------------------------------------------------------------
## 2. Condition assignment and pool size
## ---------------------------------------------------------------------------
interventions <- sst$interventions
stopifnot(length(interventions) == 16)

condition_vec <- c(
  rep("control", cfg$n_control),
  rep(interventions, each = cfg$n_per_intervention)
)
n_total <- length(condition_vec)
message(sprintf("Pool: %d respondents (%d control + 16 x %d)",
                n_total, cfg$n_control, cfg$n_per_intervention))

## Draw donors WITH replacement, proportional to weight. Each draw is an
## independent synthetic person: the same donor row may seed several personas,
## which is fine because the latent traits and response style below are drawn
## fresh each time, so they are not duplicates.
idx <- sample.int(nrow(donors), n_total, replace = TRUE,
                  prob = donors$weight)
profiles <- donors[idx, ]

## Randomise which persona lands in which condition, so demographics are
## orthogonal to condition by construction — exactly as the human study's
## randomiser guarantees. Without this, any donor-order structure leaks into
## the treatment contrast.
profiles$condition <- sample(condition_vec)
profiles$profile_id <- sprintf("p%05d", seq_len(n_total))


## ---------------------------------------------------------------------------
## 3. Latent traits
## ---------------------------------------------------------------------------
## Three standardised traits per person: trust in scientists, climate concern,
## and willingness to act. Each is a linear function of demographics plus a
## large correlated residual.
##
## The residual is the important part. Its size controls how much within-cell
## heterogeneity the personas carry, and its cross-trait correlation is what
## makes a person who distrusts scientists also tend to doubt the climate
## consensus — the covariance that item-by-item elicitation otherwise
## destroys. Loadings and residual scale are priors from published
## climate-opinion research, not fitted to anything from the target study
## (registration I.3).

z <- function(x) {
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(x)))
  (x - mean(x, na.rm = TRUE)) / s
}

educ_rank <- match(profiles$education, TARGET_LEVELS$education)
inc_rank  <- match(profiles$income,    TARGET_LEVELS$income)

X <- cbind(
  party_rep = as.numeric(profiles$party == "Republican"),
  party_ind = as.numeric(profiles$party == "Independent"),
  party_oth = as.numeric(profiles$party == "Other"),
  educ_z    = z(educ_rank),
  age_z     = z(profiles$age),
  income_z  = z(inc_rank),
  female    = as.numeric(profiles$gender == "Female"),
  nonwhite  = as.numeric(profiles$race != "White / Caucasian")
)
X[is.na(X)] <- 0

trait_names <- names(cfg$trait_loadings)
k <- length(trait_names)

## Correlated residuals via a Cholesky factor of an equicorrelation matrix.
R <- matrix(cfg$trait_resid_cor, k, k)
diag(R) <- 1
L <- chol(R)
E0 <- matrix(stats::rnorm(n_total * k), n_total, k) %*% L   # unit scale

## Solve each residual sd for the target R2 rather than hard-coding it.
## With  var(trait) = var(fitted) + sd^2  and  R2 = var(fitted)/var(trait),
##   sd = sqrt( var(fitted) * (1 - R2) / R2 ).
## Verified numerically: the realised R2 lands within +/-0.01 of the target.
r2 <- cfg$trait_r2_target
stopifnot(r2 > 0, r2 < 1)

fitted_mat <- matrix(NA_real_, n_total, k, dimnames = list(NULL, trait_names))
for (j in seq_along(trait_names)) {
  b <- cfg$trait_loadings[[trait_names[j]]]
  stopifnot(all(names(b) %in% colnames(X)))
  fitted_mat[, j] <- as.vector(X[, names(b), drop = FALSE] %*% b)
}

resid_sd <- sqrt(apply(fitted_mat, 2, stats::var) * (1 - r2) / r2)
traits   <- fitted_mat + sweep(E0, 2, resid_sd, `*`)

for (j in seq_along(trait_names)) {
  realised <- stats::var(fitted_mat[, j]) / stats::var(traits[, j])
  message(sprintf("  trait %-13s R2 = %.2f (target %.2f), residual sd = %.2f",
                  trait_names[j], realised, r2, resid_sd[j]))
  if (abs(realised - r2) > 0.05) {
    warning(sprintf("Trait '%s' R2 is %.2f, off target %.2f.",
                    trait_names[j], realised, r2))
  }
}

profiles <- cbind(profiles, as.data.frame(traits))

## Percentile form, easier to verbalise than a z-score.
for (tn in trait_names) {
  profiles[[paste0(tn, "_pct")]] <- round(100 * stats::pnorm(
    profiles[[tn]] / stats::sd(profiles[[tn]])
  ))
}


## ---------------------------------------------------------------------------
## 4. Response style
## ---------------------------------------------------------------------------
## Real 0-100 slider data piles up on 0, 50 and 100 and on multiples of 5 and
## 10, because people reach for round numbers. Assigning each persona a
## rounding granularity up front and applying it in 02_simulate.R reproduces
## that lumpiness; leaving it out gives smooth, uniform-looking marginals that
## no human sample has ever produced.
profiles$style_rounding <- as.integer(sample(
  names(cfg$style_probs$rounding), n_total, replace = TRUE,
  prob = cfg$style_probs$rounding
))
profiles$style_extremity <- sample(
  names(cfg$style_probs$extremity), n_total, replace = TRUE,
  prob = cfg$style_probs$extremity
)

## State of residence. The survey asks it of everyone, and the "Extreme
## weather predictions" arm branches on it (flood / wildfire / winter-storm
## risk category), so it has to be assigned before the stimulus is rendered.
profiles$state <- normalise_state(assign_states(n_total))
message(sprintf("\nStates assigned: %d distinct, %.1f%% 'Prefer not to say'",
                length(unique(profiles$state)),
                100 * mean(profiles$state == "Prefer not to say")))

## Control respondents each see exactly one of the three filler texts, as the
## survey's randomiser does. All three map to the single label "control".
profiles$control_filler <- NA_character_
ctrl <- profiles$condition == "control"
profiles$control_filler[ctrl] <- sample(
  c("neckties", "baseball", "dances"), sum(ctrl), replace = TRUE
)

## Prompt variant, assigned round-robin. Roughly half the variance in
## persona-panel estimates sits between prompt phrasings rather than between
## personas, so a single prompt makes every cell mean a draw from an
## unmeasured distribution. Averaging over variants removes that.
profiles$prompt_variant <- rep_len(seq_len(cfg$n_prompt_variants), n_total)


## ---------------------------------------------------------------------------
## 5. Report and write
## ---------------------------------------------------------------------------
message("\n--- Marginals of the synthetic pool ---")
for (m in core) {
  tab <- round(100 * prop.table(table(profiles[[m]])), 1)
  message("  ", m, ": ",
          paste(sprintf("%s %.1f%%", names(tab), as.numeric(tab)),
                collapse = " | "))
}

## Joint-structure spot check. These associations are strong and well
## documented in the US population; if they are near zero here, the crosswalk
## has scrambled something and the donor rows are not doing their job.
message("\n--- Joint-structure check (should be far from independent) ---")
print(round(100 * prop.table(table(profiles$party, profiles$race), 2), 1))

message("\n--- Condition balance ---")
cond_tab <- table(profiles$condition)
message(sprintf("  control: %d | interventions: min %d, max %d",
                cond_tab[["control"]],
                min(cond_tab[names(cond_tab) != "control"]),
                max(cond_tab[names(cond_tab) != "control"])))

stopifnot(
  setequal(unique(profiles$condition), sst$conditions),
  cond_tab[["control"]] >= 1000,
  min(cond_tab[names(cond_tab) != "control"]) >= 500,
  !anyNA(profiles[, core]),
  all(profiles$gender    %in% TARGET_LEVELS$gender),
  all(profiles$age_band  %in% TARGET_LEVELS$age_band),
  all(profiles$race      %in% TARGET_LEVELS$race),
  all(profiles$education %in% TARGET_LEVELS$education),
  all(profiles$income    %in% TARGET_LEVELS$income),
  all(profiles$party     %in% TARGET_LEVELS$party)
)
message("\n✓ all assertions passed")

if (dry_run) {
  message("\n--dry-run: nothing written.")
} else {
  dir.create(dirname(cfg$profiles_out), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(profiles, cfg$profiles_out)
  message(sprintf("\n✓ wrote %s (%d rows)", cfg$profiles_out, nrow(profiles)))
}
