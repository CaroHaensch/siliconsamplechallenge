#!/usr/bin/env Rscript
## ---------------------------------------------------------------------------
## 04_diagnostics.R — is this a plausible survey dataset, or is it LLM output
## in the shape of one?
##
## Usage:
##   Rscript pipeline/04_diagnostics.R
##   Rscript pipeline/04_diagnostics.R predictions/myteam_T1_primary_v1.csv
##
## Reads the cleaned Tier-1 file if you pass one or if `make clean` has already
## produced it; otherwise it cleans the raw export in memory using the
## benchmark's own clean_submission(), so the numbers below are computed on
## exactly the values that will be scored.
##
## Output: a console report plus pipeline/out/diagnostics/*.csv.
##
##
## WHAT THIS IS FOR
##
## `make check` verifies that the file is well-formed: right columns, right
## levels, no missing cells. It says nothing about whether the numbers inside
## are a credible sample of American adults. Every published failure of the
## silicon-sample method is invisible to a format check and visible here:
##
##   - within-cell variance collapse   (section 2)
##   - flattened cross-outcome structure (section 3)
##   - inflated subgroup separation      (section 5)
##   - inflated treatment effects        (section 6)
##   - prompt-artefact dominance         (section 7)
##
## THE REFERENCE VALUES BELOW ARE PRIORS. They are rough targets from published
## US climate-opinion and trust research and from what 0-100 slider data
## generally looks like — not fitted to anything from the target study, whose
## results are not public. Treat them as "you are probably in trouble if you
## are far outside this", never as a target to tune toward: tuning your
## predictions to match a published survey you happened to pick is a different
## method than the one you registered, and worse, it is a method you cannot
## describe honestly under registration I.3.
## ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

args <- commandArgs(trailingOnly = TRUE)
args <- args[!grepl("^--", args)]

source("pipeline/00_config.R")
source("pipeline/lib/items.R")
source("scripts/lib/submission_spec.R")

out_dir <- file.path(dirname(cfg$responses_out), "diagnostics")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

hr <- function(title) message("\n", strrep("=", 74), "\n", title, "\n", strrep("=", 74))
note <- function(...) message("  > ", ...)


## ===========================================================================
## 0. Load the scored values
## ===========================================================================

load_scored <- function() {
  if (length(args) && file.exists(args[1])) {
    message("Reading ", args[1])
    return(readr::read_csv(args[1], show_col_types = FALSE))
  }
  cand <- list.files("predictions", pattern = "_T1_.*\\.csv$", full.names = TRUE)
  cand <- cand[!grepl("example_", basename(cand))]
  if (length(cand) == 1L) {
    message("Reading ", cand)
    return(readr::read_csv(cand, show_col_types = FALSE))
  }
  if (!file.exists(cfg$raw_export_out)) {
    stop("Nothing to diagnose. Run pipeline/03_export.R first, or pass a ",
         "cleaned Tier-1 file as an argument.", call. = FALSE)
  }
  message("Cleaning ", cfg$raw_export_out, " in memory (benchmark clean_submission)")
  suppressPackageStartupMessages({
    library(stringr); library(purrr); library(tidyr)
  })
  source("scripts/lib/clean_lib.R")
  clean_submission(cfg$raw_export_out)
}

d <- load_scored()
d <- as.data.frame(d)
message(sprintf("%d respondents, %d conditions", nrow(d), dplyr::n_distinct(d$condition)))

outcomes <- sst$outcomes
sliders  <- sst$scale_0_100
ctrl     <- d[d$condition == "control", , drop = FALSE]
if (!nrow(ctrl)) stop("No control respondents.", call. = FALSE)


## ===========================================================================
## 1. Marginals and the shape of the response distribution
## ===========================================================================
hr("1. MARGINALS (control condition)")

pile <- function(x, v) 100 * mean(abs(x - v) < 1e-9, na.rm = TRUE)

marg <- do.call(rbind, lapply(sliders, function(o) {
  x <- ctrl[[o]]
  data.frame(outcome = o, mean = mean(x, na.rm = TRUE), sd = stats::sd(x, na.rm = TRUE),
             pct_0 = pile(x, 0), pct_50 = pile(x, 50), pct_100 = pile(x, 100),
             pct_mult5 = 100 * mean(abs(x %% 5) < 1e-9, na.rm = TRUE))
}))
print(marg %>% mutate(across(where(is.numeric), ~ round(.x, 1))), row.names = FALSE)

message("")
note("Reference: 0-100 attitude sliders in real US samples typically have SD 20-30.")
note("Endpoint and midpoint piling is normal and expected: a few percent on 0 and")
note("100, often 5-15% on exactly 50, and a large majority on multiples of 5.")
note("SD near 10 or below, or almost nothing on round numbers, means the")
note("distribution is model-smooth rather than human-lumpy.")

flag_sd <- marg$outcome[marg$sd < 12]
if (length(flag_sd)) {
  note("FLAG - implausibly tight: ", paste(flag_sd, collapse = ", "))
}
if (mean(marg$pct_mult5) < 60) {
  note("FLAG - only ", round(mean(marg$pct_mult5)), "% of answers land on multiples ",
       "of 5. Check cfg$style_probs$rounding and 03_export.R's round_to().")
}

if (all(c("donation_ams", "newsletter_signup") %in% names(ctrl))) {
  message("")
  message(sprintf("  donation_ams:      mean $%.2f, %% giving $0 = %.1f, %% giving $10 = %.1f",
                  mean(ctrl$donation_ams), pile(ctrl$donation_ams, 0),
                  pile(ctrl$donation_ams, 10)))
  message(sprintf("  newsletter_signup: %.1f%% subscribe", 100 * mean(ctrl$newsletter_signup)))
  note("Real dictator-style donation splits are strongly bimodal at $0 and the")
  note("full amount. Real in-survey newsletter opt-in is usually well under 20%.")
}


## ===========================================================================
## 2. Within-cell variance
## ===========================================================================
hr("2. WITHIN-CELL VARIANCE — the classic failure mode")

cell_sd <- d %>%
  group_by(condition) %>%
  summarise(across(all_of(sliders), ~ stats::sd(.x, na.rm = TRUE)), .groups = "drop")

sd_summary <- data.frame(
  outcome = sliders,
  min_cell_sd = round(vapply(sliders, function(o) min(cell_sd[[o]]), numeric(1)), 1),
  med_cell_sd = round(vapply(sliders, function(o) stats::median(cell_sd[[o]]), numeric(1)), 1),
  max_cell_sd = round(vapply(sliders, function(o) max(cell_sd[[o]]), numeric(1)), 1))
print(sd_summary, row.names = FALSE)

message("")
note("A cell SD far below the pooled SD in section 1 means respondents inside a")
note("condition are near-identical: the personas collapsed onto a modal answer.")
note("If so, the levers are cfg$elicitation ('distribution' samples rather than")
note("maximises), cfg$trait_r2_target (lower = personas differ more beyond their")
note("demographics), cfg$anchor_residual_share (higher = anchors themselves")
note("spread further apart within a cell), and the resid_sd column in priors.R.")

## Straightlining: a respondent whose answers barely vary across the 13
## outcomes is not a person, they are a single number repeated. Some real
## respondents do straightline, but only a few percent.
zs <- scale(d[, sliders, drop = FALSE])
straight <- mean(apply(zs, 1, stats::sd, na.rm = TRUE) < 0.25, na.rm = TRUE)
message(sprintf("\n  Straightlining (within-respondent SD of standardised outcomes < 0.25): %.1f%%",
                100 * straight))
if (straight > 0.15) {
  note("FLAG - a sixth or more of respondents answer everything the same way.")
  note("Usually a persona that states one attitude so plainly the model reuses")
  note("it for every item, or anchors so tight that every block lands together.")
}


## ===========================================================================
## 3. Cross-outcome correlation structure
## ===========================================================================
hr("3. CORRELATION AMONG THE 13 OUTCOMES (control only)")

cm <- stats::cor(ctrl[, outcomes], use = "pairwise.complete.obs")
print(round(cm, 2))

off <- cm[upper.tri(cm)]
message(sprintf("\n  Off-diagonal |r|: median %.2f, IQR %.2f-%.2f, max %.2f",
                stats::median(abs(off)), stats::quantile(abs(off), .25),
                stats::quantile(abs(off), .75), max(abs(off))))

message("")
note("This is the structure the project cares most about, and the benchmark")
note("never inspects it directly — but the Tier-2 moderator file is scored on")
note("subgroup means, and a subgroup mean is a conditional expectation, so")
note("predictor-outcome structure enters the score whether or not anything is")
note("labelled 'correlation'.")
note("Reference: in US climate-opinion data, trust in scientists, belief,")
note("concern and policy support intercorrelate roughly .5 to .75. Distrust")
note("correlates about -.6 to -.8 with trust. Behavioural intentions and")
note("donation correlate more weakly with attitudes, roughly .3 to .5.")
note("Median |r| below ~.25 means neither the anchors nor the persona are")
note("reaching the answers. Median |r| above ~.8 means the persona is answering")
note("one underlying question over and over, which is just as wrong.")
note("Nothing in the pipeline sets these correlations directly — they arise")
note("from the anchors sharing predictors and from the model answering the")
note("blocks as one person. That is the honest way to get them, and it means")
note("this table is a result to report, not a knob to turn.")

if (stats::median(abs(off)) < 0.25) note("FLAG - structure is too flat.")
if (stats::median(abs(off)) > 0.80) note("FLAG - structure is too uniform.")

## Trust and distrust are the same attitude with opposite keying, so this is
## the cheapest check that the model read the items rather than pattern-matched
## the block.
if (all(c("trust_post", "distrust_post") %in% names(ctrl))) {
  r_td <- stats::cor(ctrl$trust_post, ctrl$distrust_post, use = "complete.obs")
  message(sprintf("\n  cor(trust_post, distrust_post) = %+.2f", r_td))
  if (r_td > -0.3) {
    note("FLAG - should be strongly negative. The model is not distinguishing")
    note("trust from distrust; check that both anchors are reaching the prompt")
    note("(the distrust prior deliberately loads negatively on the same trait).")
  }
}

## Internal consistency of the primary outcome's battery. Real multi-item trust
## scales run about .90-.95. Near 1.0 means the twelve items carry one number.
alpha <- function(m) {
  m <- m[stats::complete.cases(m), , drop = FALSE]
  k <- ncol(m)
  k / (k - 1) * (1 - sum(apply(m, 2, stats::var)) / stats::var(rowSums(m)))
}
a_trust <- alpha(as.matrix(ctrl[, sst$trust_items]))
message(sprintf("\n  Cronbach's alpha, 12 trust items: %.3f", a_trust))
note("Reference: real multidimensional trust batteries land around .90-.95.")
if (a_trust > 0.98) note("FLAG - the 12 items are one item with 12 labels.")
if (a_trust < 0.75) note("FLAG - the battery is not cohering; check item wordings.")

readr::write_csv(as.data.frame(cm) %>% tibble::rownames_to_column("outcome"),
                 file.path(out_dir, "outcome_correlations_control.csv"))


## ===========================================================================
## 4. Randomisation check
## ===========================================================================
hr("4. RANDOMISATION CHECK")
## Demographics were assigned orthogonally to condition in 01, so any
## systematic pre-treatment difference across conditions means something in the
## pipeline reintroduced a dependency — which would contaminate every ATE.

chi <- vapply(names(sst$moderators), function(m) {
  suppressWarnings(stats::chisq.test(table(d[[m]], d$condition))$p.value)
}, numeric(1))
print(round(chi, 3))
note("These are p-values for moderator x condition independence. They should")
note("be uniformly distributed; a very small one means condition assignment is")
note("no longer orthogonal to demographics.")

## A moderator whose spec allows a level that the pool never draws produces an
## all-zero row, an expected count of zero, and a NaN p-value. That is not a
## randomisation failure, but it does mean the moderator went unchecked here —
## and it is worth knowing about in its own right, because a level the scoring
## expects and the pool never produces is a structural hole in the submission.
if (anyNA(chi)) {
  na_m <- names(chi)[is.na(chi)]
  note("NOT TESTED (NaN): ", paste(na_m, collapse = ", "),
       " - a level in the spec has zero cases, so the test is undefined.")
  for (m in na_m) {
    empty <- setdiff(sst$moderators[[m]], unique(as.character(d[[m]])))
    if (length(empty)) {
      note("  ", m, ": level(s) with no respondents: ",
           paste(empty, collapse = ", "))
    }
  }
}

if (any(chi < 0.001, na.rm = TRUE)) note("FLAG - assignment is not independent of demographics.")


## ===========================================================================
## 5. Subgroup structure
## ===========================================================================
hr("5. SUBGROUP GRADIENTS (control condition)")
## Scored directly by the Tier-2 moderator file. The documented failure mode
## here is over-separation, not under-separation: LLM personas exaggerate the
## partisan gap while flattening variation inside each party.

key <- intersect(c("trust_multidimensional", "belief_post", "concern_mean",
                   "policy_general"), outcomes)

for (m in c("party", "education", "age_band")) {
  message("\n  by ", m, ":")
  tabm <- ctrl %>%
    group_by(.data[[m]]) %>%
    summarise(n = dplyr::n(),
              across(all_of(key), ~ round(mean(.x, na.rm = TRUE), 1)),
              across(all_of(key), ~ round(stats::sd(.x, na.rm = TRUE), 1),
                     .names = "sd_{.col}"),
              .groups = "drop")
  print(as.data.frame(tabm), row.names = FALSE)
}

if ("party" %in% names(ctrl)) {
  gap <- ctrl %>%
    filter(.data$party %in% c("Democrat", "Republican")) %>%
    group_by(.data$party) %>%
    summarise(across(all_of(key), ~ mean(.x, na.rm = TRUE)), .groups = "drop")
  if (nrow(gap) == 2) {
    dr <- as.numeric(gap[gap$party == "Democrat", key]) -
          as.numeric(gap[gap$party == "Republican", key])
    message("\n  Democrat - Republican gap (0-100 points):")
    for (i in seq_along(key)) message(sprintf("    %-24s %+6.1f", key[i], dr[i]))
    note("Reference: on 0-100 climate items, US partisan gaps are large but")
    note("finite - roughly 20-35 points on belief and concern, somewhat less on")
    note("trust in scientists. Gaps above ~50 points, or near-zero within-party")
    note("SDs in the tables above, are the caricature failure. The lever is")
    note("cfg$trait_loadings (party coefficients) against cfg$trait_r2_target.")
  }
}

## R-squared of demographics on each outcome: how much of a respondent is
## predictable from their moderator cell. Real climate-opinion data lands
## around .20-.35; much higher means personas are their demographics.
r2 <- vapply(key, function(o) {
  f <- stats::as.formula(paste(o, "~ gender + age_band + race + education + income + party"))
  summary(stats::lm(f, data = ctrl))$r.squared
}, numeric(1))
message("\n  R2 of the six moderators on each outcome:")
for (i in seq_along(r2)) message(sprintf("    %-24s %.2f", names(r2)[i], r2[i]))
note("Reference: roughly .20-.35 in real US survey data. Far above that and the")
note("personas are interchangeable within a cell; far below and the demographic")
note("gradients the Tier-2 moderator file scores have been washed out.")


## ===========================================================================
## 6. Treatment effects
## ===========================================================================
hr("6. TREATMENT EFFECTS (this is what Tier 3 is scored on)")

ate <- do.call(rbind, lapply(sst$interventions, function(cond) {
  x <- d[d$condition == cond, , drop = FALSE]
  data.frame(condition = cond,
             outcome = outcomes,
             ate = vapply(outcomes, function(o)
               mean(x[[o]], na.rm = TRUE) - mean(ctrl[[o]], na.rm = TRUE), numeric(1)),
             d = vapply(outcomes, function(o) {
               s <- stats::sd(ctrl[[o]], na.rm = TRUE)
               if (is.na(s) || s == 0) NA_real_ else
                 (mean(x[[o]], na.rm = TRUE) - mean(ctrl[[o]], na.rm = TRUE)) / s
             }, numeric(1)),
             row.names = NULL)
}))

message(sprintf("  |Cohen's d| across %d intervention x outcome cells:", nrow(ate)))
message(sprintf("    median %.3f | 90th pct %.3f | max %.3f",
                stats::median(abs(ate$d), na.rm = TRUE),
                stats::quantile(abs(ate$d), .9, na.rm = TRUE),
                max(abs(ate$d), na.rm = TRUE)))

message("\n  Largest effects on the primary outcome:")
prim <- ate[ate$outcome == "trust_multidimensional", ]
print(head(prim[order(-abs(prim$d)), c("condition", "ate", "d")] %>%
             mutate(across(where(is.numeric), ~ round(.x, 3))), 6), row.names = FALSE)

message("")
note("Reference: behavioural-science megastudies overwhelmingly return small")
note("effects - most interventions land under d = 0.2, and a good many are")
note("indistinguishable from zero. LLM simulations routinely return effects")
note("several times larger, because the persona can infer what the text is for.")
note("If your median |d| is above ~0.25 the predictions are probably too")
note("confident: strengthen the prior wording in render_intervention_prior()")
note("and re-run, rather than rescaling the finished numbers. If effects are")
note("near-identical across")
note("all 16 interventions, the model is responding to 'a pro-science text was")
note("shown' rather than to the specific content, which is a real limitation to")
note("declare under registration G.2, not a bug to hide.")

spread <- prim$ate
message(sprintf("\n  Spread of the 16 primary-outcome ATEs: SD = %.2f points, range %.2f to %.2f",
                stats::sd(spread), min(spread), max(spread)))
if (stats::sd(spread) < 0.5) {
  note("FLAG - the interventions are barely distinguishable from one another.")
}

readr::write_csv(ate, file.path(out_dir, "ate_by_condition_outcome.csv"))


## ===========================================================================
## 7. Prompt-variant sensitivity
## ===========================================================================
hr("7. PROMPT-VARIANT SENSITIVITY")
## Only available if the raw responses are still around: prompt_variant is not
## part of the submission schema.

if (file.exists(cfg$responses_out)) {
  rr <- readr::read_csv(cfg$responses_out, show_col_types = FALSE)
  if ("prompt_variant" %in% names(rr) && dplyr::n_distinct(rr$prompt_variant) > 1) {
    key_items <- POST_ITEMS$q[POST_ITEMS$block == "trust"]
    rr$trust_bar <- rowMeans(rr[, key_items], na.rm = TRUE)
    bv <- rr %>%
      filter(.data$condition == "control") %>%
      group_by(.data$prompt_variant) %>%
      summarise(mean_trust = mean(.data$trust_bar, na.rm = TRUE),
                sd_trust = stats::sd(.data$trust_bar, na.rm = TRUE),
                n = dplyr::n(), .groups = "drop")
    print(as.data.frame(bv %>% mutate(across(where(is.numeric), ~ round(.x, 2)))),
          row.names = FALSE)
    between <- stats::sd(bv$mean_trust)
    within  <- mean(bv$sd_trust)
    message(sprintf("\n  Between-variant SD of the control mean: %.2f points (within-variant SD %.2f)",
                    between, within))
    note("This is the part of your prediction that comes from how the prompt was")
    note("phrased rather than from the method. A between-variant SD of more than")
    note("a few points means a single-prompt design would have been reporting a")
    note("draw from an unmeasured distribution. Report it under registration E.2.")
    if (between > 5) note("FLAG - prompt phrasing moves the control mean by more than 5 points.")
  } else {
    note("Only one prompt variant present; nothing to compare.")
  }
} else {
  note("responses_raw.csv not found; skipping.")
}


## ===========================================================================
## 8. Summary
## ===========================================================================
hr("SUMMARY")
message("Wrote:")
for (f in list.files(out_dir, full.names = TRUE)) message("  ", f)
message("\nNone of the above is scored. All of it is the difference between a")
message("submission that fails for a reason you can name in registration.md and")
message("one that fails for a reason you never looked for.")
