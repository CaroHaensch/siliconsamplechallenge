#!/usr/bin/env Rscript
## ---------------------------------------------------------------------------
## 03_export.R — responses_raw.csv  ->  a Qualtrics-shaped raw export.
##
##   drop incomplete respondents
##     -> slider rounding        (per-persona granularity)
##     -> discretisation         (donation to whole dollars, newsletter to 1/2)
##     -> demographic columns    (labels clean.R accepts verbatim)
##     -> raw_data_deposit/simulated_raw_export.csv
##
## Usage:
##   Rscript pipeline/03_export.R
##
## Then:  make clean   (builds predictions/<team_id>_T1_<entry>_v1.csv)
##
##
## WHY THESE STEPS LIVE HERE AND NOT IN 02
##
## Everything in 02_simulate.R is a property of one respondent and can be done
## the moment their answer arrives. Everything here is a reporting artefact of
## the instrument rather than of the person: a slider returns an integer, the
## donation question offers whole dollars, the newsletter question records a
## click rather than a propensity.
##
## NO POST-HOC ADJUSTMENT HAPPENS HERE. The simulated treatment effects are
## exported exactly as the simulation produced them. An earlier version shrank
## every intervention's deviation from the control mean toward zero, on the
## grounds that LLM-simulated effects run large; that was removed deliberately.
## A correction applied to finished numbers is a free parameter with nothing to
## discipline it — pick a different factor and you submit different
## predictions, and no reader can tell whether the factor or the simulation is
## doing the work. The effect size is instead constrained where it is
## generated, by the published intervention prior stated in the prompt
## (cfg$state_intervention_prior, see lib/priors.R). That prior can be right or
## wrong for reasons someone can check.
##
## The practical consequence is that this script is cheap to re-run and changes
## nothing substantive when you do.
## ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

source("pipeline/00_config.R")
source("pipeline/lib/items.R")
source("scripts/lib/submission_spec.R")

set.seed(cfg$seed + 3L)


## ===========================================================================
## 1. Inputs
## ===========================================================================

validate_items()

for (f in c(cfg$responses_out, cfg$profiles_out)) {
  if (!file.exists(f)) stop("Missing '", f, "'. Run the earlier steps first.",
                            call. = FALSE)
}

resp     <- readr::read_csv(cfg$responses_out, show_col_types = FALSE)
profiles <- readr::read_csv(cfg$profiles_out,  show_col_types = FALSE)

item_cols <- POST_ITEMS$q
missing   <- setdiff(item_cols, names(resp))
if (length(missing)) {
  stop("responses_raw.csv is missing item column(s): ",
       paste(missing, collapse = ", "),
       "\nWas it produced by a different version of items.R?", call. = FALSE)
}

## Demographics come from the profile, never from the model. The moderator
## columns are assigned facts about the synthetic respondent; letting the model
## restate them would introduce disagreement between the person we simulated
## and the person we report having simulated.
d <- profiles %>%
  select(profile_id, condition, gender, age, age_band, race, education,
         income, party, style_rounding, style_extremity) %>%
  inner_join(resp %>% select(profile_id, all_of(item_cols)), by = "profile_id") %>%
  as.data.frame()   # matrix-block assignment below; tibbles resist it

message(sprintf("Joined %d respondents", nrow(d)))


## ===========================================================================
## 2. Drop incomplete respondents
## ===========================================================================
## Partial rows are dropped whole rather than imputed. An imputed composite is
## a prediction about a respondent we never actually simulated, and the
## benchmark scores composites as submitted rather than recomputing them, so a
## partially-imputed row would enter every analysis it touches on invented
## values. The precision floor exists to be spent on exactly this.

before <- nrow(d)
d <- d[stats::complete.cases(d[, item_cols]), , drop = FALSE]
message(sprintf("Complete on all %d items: %d -> %d (%.1f%% dropped)",
                length(item_cols), before, nrow(d),
                100 * (1 - nrow(d) / before)))

if (!nrow(d)) stop("No complete respondents.", call. = FALSE)

tab <- table(d$condition)
iv  <- tab[names(tab) != "control"]
message(sprintf("Per condition: control %d | interventions min %d, max %d",
                tab[["control"]], min(iv), max(iv)))
if (tab[["control"]] < 1000 || min(iv) < 500) {
  warning("Below the benchmark's precision floor (1000 control / 500 per ",
          "intervention). `make check` will warn on the resulting file.",
          call. = FALSE)
}


## ===========================================================================
## 3. Treatment effects — reported, never adjusted
## ===========================================================================
## The simulated effects are computed here only so they can be looked at and
## written to disk. NOTHING IS MODIFIED. The values that go into the submission
## are the ones the simulation produced.
##
## If these come out much larger than the published prior the prompt states —
## Vlasceanu et al. (2024) found the best of eleven interventions moved a
## 0-100 attitude item by under three points — then the model did not take the
## prior seriously, and the response is to fix the prompt and re-run, not to
## rescale the output afterwards. Rescaling would make the submitted effects a
## function of a coefficient we chose, and no reader could then tell whether
## the coefficient or the simulation produced the prediction.

ctrl_means <- colMeans(d[d$condition == "control", item_cols, drop = FALSE])

sim_ate <- matrix(NA_real_, length(sst$interventions), length(item_cols),
                  dimnames = list(sst$interventions, item_cols))
for (cond in sst$interventions) {
  rows <- which(d$condition == cond)
  if (!length(rows)) next
  sim_ate[cond, ] <- colMeans(d[rows, item_cols, drop = FALSE]) - ctrl_means
}

sliders_only <- item_cols[POST_ITEMS$type[match(item_cols, POST_ITEMS$q)] == "slider"]
mean_abs <- mean(abs(sim_ate[, sliders_only]), na.rm = TRUE)
max_abs  <- max(abs(sim_ate[, sliders_only]), na.rm = TRUE)

message(sprintf("\nSimulated effects on 0-100 items: mean |ATE| = %.2f, max = %.2f points",
                mean_abs, max_abs))
message("  Published reference: the best of 11 interventions in a 59,440-person")
message("  megastudy moved belief by 2.3 and policy support by 2.6 points.")
if (mean_abs > 4) {
  warning(sprintf(
    "Mean |ATE| of %.1f points is well above anything the intervention ",
    mean_abs),
    "literature reports for a single short text. The prompt-level prior did ",
    "not bind. Check cfg$state_intervention_prior and the wording in ",
    "render_intervention_prior(); do not rescale the output.", call. = FALSE)
}


## ===========================================================================
## 4. Quantisation
## ===========================================================================

## Humans reach for round numbers on sliders — the marginals of any real
## 0-100 item pile up on 0, 50, 100 and on multiples of 5 and 10. Models do
## not, and the resulting too-smooth marginal is one of the easier tells that a
## dataset is synthetic. Granularity was assigned per persona in 01.
round_to <- function(x, granularity) {
  pmin(pmax(round(x / granularity) * granularity, 0), 100)
}

slider_q <- POST_ITEMS$q[POST_ITEMS$type == "slider"]
for (q in slider_q) d[[q]] <- as.integer(round_to(d[[q]], d$style_rounding))

## Donation: whole dollars, 0-10.
d$donation <- as.integer(pmin(pmax(round(d$donation), 0), 10))

## Newsletter: the model reports a propensity; the survey records a click. A
## Bernoulli draw is the honest conversion — rounding the propensity at 50
## instead would make every respondent below the threshold a certain "no" and
## drive the cell proportion to 0 or 1.
##
## Raw Qualtrics coding: 1 = Yes, 2 = No (clean.R recodes to 1/0).
d$newsletter <- ifelse(
  stats::rbinom(nrow(d), 1, pmin(pmax(d$newsletter, 0), 100) / 100) == 1L, 1L, 2L)

message(sprintf("Newsletter signup rate: %.1f%%", 100 * mean(d$newsletter == 1)))
message("  (Real opt-in rates for an in-survey newsletter offer are usually ",
        "well under 20%. A much higher rate is the model being agreeable, not ",
        "a finding — note it under registration G.2.)")


## ===========================================================================
## 5. Demographic columns
## ===========================================================================
## clean.R's .recode_demo() accepts either the numeric Qualtrics codes or the
## canonical label strings. We write the labels: they are self-documenting in
## the deposited raw file, and a transposed numeric code would be a silent
## error where a wrong label is a hard stop.
##
## `year_birth` is what clean.R parses; it reconstructs age as 2026 -
## year_birth and cuts the bands itself. Writing the year rather than the band
## keeps the derivation in the benchmark's hands, so our age_band cannot
## disagree with theirs.

stopifnot(!anyNA(d$age))
d$year_birth <- as.integer(2026 - round(d$age))

## Guard: our band and the band clean.R will derive must agree, or the
## moderator cells we predicted are not the ones that get scored.
derived <- cut(2026 - d$year_birth, breaks = c(17, 29, 44, 59, Inf),
               labels = sst$moderators$age_band, right = TRUE)
if (!identical(as.character(derived), as.character(d$age_band))) {
  n <- sum(as.character(derived) != as.character(d$age_band), na.rm = TRUE)
  stop("age_band mismatch for ", n, " rows between profiles.csv and the band ",
       "clean.R will derive from year_birth. Check age_to_band() in ",
       "pipeline/lib/anes_recode.R against clean_lib.R's cut points.",
       call. = FALSE)
}

for (m in names(sst$moderators)) {
  bad <- setdiff(unique(as.character(d[[m]])), sst$moderators[[m]])
  if (length(bad)) {
    stop("Value(s) of '", m, "' not in submission_spec.R: ",
         paste0('"', bad, '"', collapse = ", "), call. = FALSE)
  }
}


## ===========================================================================
## 6. Write
## ===========================================================================

## Item columns are ordered as the questionnaire presents them, so a human
## opening the deposited file can read it against questionnaire.txt.
export <- d[, c("profile_id", "condition", "gender", "year_birth", "race",
                "education", "income", "party", item_cols)]

dir.create(dirname(cfg$raw_export_out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(export, cfg$raw_export_out)
message(sprintf("\n[OK] wrote %s (%d rows x %d cols)",
                cfg$raw_export_out, nrow(export), ncol(export)))

## The per-item effects as simulated. Written for inspection and for
## registration.md; they are not an input to anything.
ate_path <- file.path(dirname(cfg$responses_out), "simulated_ate_by_item.csv")
readr::write_csv(
  cbind(data.frame(condition = rownames(sim_ate), stringsAsFactors = FALSE),
        as.data.frame(sim_ate)),
  ate_path)
message(sprintf("[OK] wrote %s", ate_path))

message("\nNext:")
message("  Rscript pipeline/04_diagnostics.R    # check before you spend the deposit")
message("  make clean                           # -> predictions/<team_id>_T1_<entry>_v1.csv")
message("  make check")
message("\nReminder: raw_data_deposit/ must contain exactly ONE csv when you run")
message("`make clean`. Delete the shipped example_raw_export.csv first.")

