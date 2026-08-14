#!/usr/bin/env Rscript
## ---------------------------------------------------------------------------
## 02_simulate.R — run the synthetic pool through the instrument.
##
##   profiles.csv
##     -> [optional] narrative backstories        (--stage backstories)
##     -> stage 1: pre-treatment items, no stimulus
##     -> stimulus, verbatim
##     -> stage 2: all post-treatment items in one structured answer
##     -> sampled item values -> responses_raw.csv
##
## Usage:
##   Rscript pipeline/02_simulate.R --dry-run                # print prompts, call nothing
##   Rscript pipeline/02_simulate.R --stage backstories      # optional, one call/respondent
##   Rscript pipeline/02_simulate.R --limit 50               # pilot across all conditions
##   Rscript pipeline/02_simulate.R                          # full run
##   Rscript pipeline/02_simulate.R --resume                 # continue after a crash
##
## Output: pipeline/out/responses_raw.csv — one row per respondent, one column
## per Qualtrics item. Values are CONTINUOUS: response-style extremity has been
## applied (it is part of how the person answers), but slider rounding and the
## discretisation of donation / newsletter have not. Those are reporting
## artefacts of the instrument and live in 03_export.R.
##
## No treatment effect is rescaled anywhere in this pipeline. The size of the
## effect is constrained in the prompt, by a published prior, and whatever the
## simulation then produces is what gets submitted.
##
##
## FIVE DESIGN CHOICES THAT DO THE WORK
##
## 1. No experiment cues. The persona is never told it is in a study, that the
##    text is an intervention, that a comparison condition exists, or what the
##    text is meant to achieve. Simulated respondents who can infer the
##    hypothesis move toward it, which is the main reason LLM-simulated
##    treatment effects come out several times larger than the human effects
##    they are predicting.
##
## 2. Two stages, not one. Stage 1 asks the pre-treatment items with no
##    stimulus in context; stage 2 replays those answers, shows the stimulus,
##    and asks the ~40 post-treatment items in a single structured response.
##    This gives the persona a position to be moved *from*, makes the pre/post
##    pair a genuine within-person anchor, and keeps stage 1 uncontaminated so
##    that a pre-treatment balance check is meaningful rather than circular.
##    Stage 2 is a fresh call carrying stage 1's answers as text rather than a
##    continued conversation: that keeps every request self-contained, hence
##    parallelisable and batchable, and makes the exact model input
##    reconstructible from the logs alone.
##
## 3. All post-treatment items in ONE response. Per-item calls are the standard
##    silicon-sample recipe and the standard way the method fails: nothing ties
##    a respondent's answers together except the persona text, and the
##    resulting correlation matrix across outcomes is far flatter than any real
##    survey's. One response lets the model hold a respondent's position fixed
##    across items. It also costs roughly ten times less input.
##
## 4. Answers are sampled, not maximised. Asking for a single number returns
##    something near the mode, and a cell built of modes has far less spread
##    than a cell built of draws. So the model reports a distribution per item
##    and we take an independent draw from each. The draw resolves only the
##    model's uncertainty about that item; where the respondent sits on the
##    underlying attitude is already fixed by the regression anchors, before
##    any call is made.
##
## 5. Averaging over prompt variants. Roughly half the variance in
##    persona-panel estimates sits between prompt phrasings rather than between
##    personas. See cfg$n_prompt_variants.
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
stage   <- get_arg("--stage", "survey")
limit_n <- suppressWarnings(as.integer(get_arg("--limit", NA)))
dry_run <- "--dry-run" %in% args
resume  <- "--resume"  %in% args

source("pipeline/00_config.R")
source("pipeline/lib/anes_recode.R")   # TARGET_LEVELS, used by priors.R
source("pipeline/lib/items.R")
source("pipeline/lib/persona.R")
source("pipeline/lib/priors.R")
source("pipeline/lib/stimuli.R")
source("scripts/lib/submission_spec.R")

## Offset from 01's stream so the sampling draws here are not a continuation of
## the pool-construction draws; re-running 01 must not silently reshuffle 02.
set.seed(cfg$seed + 2L)

stopifnot(cfg$elicitation %in% c("point", "distribution"))

## 01 assigns prompt_variant round-robin over cfg$n_prompt_variants, and the
## variant indexes SYSTEM_VARIANTS directly. Raising the config knob without
## writing the extra variants would fail here rather than mid-run.
if (cfg$n_prompt_variants > length(SYSTEM_VARIANTS)) {
  stop("cfg$n_prompt_variants = ", cfg$n_prompt_variants, " but persona.R ",
       "defines only ", length(SYSTEM_VARIANTS), " system prompt variants.",
       call. = FALSE)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a


## ===========================================================================
## 1. Inputs
## ===========================================================================

validate_items()

stim <- load_stimuli()
ew   <- load_extreme_weather()
validate_stimuli(stim, sst$interventions, ew)
message(sprintf("[OK] stimuli: %d texts loaded", length(stim)))

if (!file.exists(cfg$profiles_out)) {
  stop("No profile pool at '", cfg$profiles_out,
       "'. Run: Rscript pipeline/01_build_profiles.R", call. = FALSE)
}
profiles <- readr::read_csv(cfg$profiles_out, show_col_types = FALSE)
message(sprintf("[OK] profiles: %d respondents", nrow(profiles)))

if (!is.na(limit_n)) {
  ## Stratified head, not the first n rows. Condition was randomised in 01, so
  ## a plain head would still cover all conditions in expectation — but a pilot
  ## that happens to miss one tells you nothing about that condition's prompt,
  ## and the extreme-weather arm in particular has branching worth eyeballing.
  per <- max(1L, ceiling(limit_n / length(sst$conditions)))
  profiles <- profiles %>%
    group_by(.data$condition) %>%
    slice_head(n = per) %>%
    ungroup()
  message(sprintf("--limit: piloting %d respondents across %d conditions",
                  nrow(profiles), dplyr::n_distinct(profiles$condition)))
}

dir.create(cfg$logs_dir,   recursive = TRUE, showWarnings = FALSE)
dir.create(cfg$chunks_dir, recursive = TRUE, showWarnings = FALSE)


## ===========================================================================
## 2. LLM adapter
## ===========================================================================
## ellmer's argument lists for the parallel / batch runners have moved between
## releases. Rather than pin a version, pass only the arguments the installed
## function actually declares — an unrecognised `rpm` should degrade to the
## default, not abort a 9,000-respondent run halfway through.
##
## This filtering is applied ONLY to the runners. ellmer::chat() takes
## `system_prompt` and `params` through `...`, so they are not in its formals
## and filtering would silently drop them — which would run the whole study
## with no system prompt and the provider's default temperature.

call_filtered <- function(fn, ...) {
  supplied <- list(...)
  do.call(fn, supplied[names(supplied) %in% names(formals(fn))])
}

new_chat <- function(system_prompt) {
  ellmer::chat(
    paste0(cfg$provider, "/", cfg$model),
    system_prompt = system_prompt,
    params        = ellmer::params(temperature = cfg$temperature)
  )
}

## Normalise whatever the installed ellmer returns (a data frame with list
## columns, or a list of lists) into a plain list with one element per prompt.
as_rowlist <- function(res) {
  if (is.data.frame(res)) {
    lapply(seq_len(nrow(res)), function(i) {
      row <- as.list(res[i, , drop = FALSE])
      lapply(row, function(v) if (is.list(v) && length(v) == 1L) v[[1L]] else v)
    })
  } else {
    as.list(res)
  }
}

## `on_error = "return"` asks ellmer to hand back a NULL for a failed request
## instead of aborting the whole call. Older releases do not have the argument
## (it is filtered out above), so the tryCatch is the fallback: a chunk-level
## failure becomes a chunk of NULLs, which the retry loop then re-submits. Both
## paths converge on the same behaviour — a transient 529 costs a retry, not
## the run.
run_llm <- function(prompts, type, variant, tag) {
  chat <- new_chat(SYSTEM_VARIANTS[[variant]])
  fn <- if (isTRUE(cfg$use_batch)) ellmer::batch_chat_structured
        else ellmer::parallel_chat_structured
  res <- tryCatch(
    call_filtered(
      fn,
      chat       = chat,
      prompts    = as.list(prompts),
      type       = type,
      path       = file.path(cfg$logs_dir, sprintf("batch_%s_v%d.json", tag, variant)),
      max_active = cfg$max_active,
      rpm        = cfg$rpm,
      on_error   = "return"
    ),
    error = function(e) {
      message("    request batch failed (", conditionMessage(e), ")")
      NULL
    })
  if (is.null(res)) return(vector("list", length(prompts)))
  as_rowlist(res)
}


## ===========================================================================
## 3. Optional stage: narrative backstories
## ===========================================================================
## One extra call per respondent. Worth it if the budget allows: a persona
## given a concrete life — a job, a routine, a media diet — is measurably
## harder for the model to caricature than one given a demographic cell.
##
## The generating prompt is forbidden from naming party, ideology, trust or
## climate. That is the point: the narrative must carry the person WITHOUT
## restating the very variables whose effect on the outcomes we are trying to
## predict, or the sketch becomes a leaked answer key. The quantitative
## information travels separately, as trait percentiles (see persona.R).

trait_phrase <- function(pct, low, mid, high) {
  ifelse(pct < 33, low, ifelse(pct < 67, mid, high))
}

build_backstory_prompt <- function(p) {
  sci <- trait_phrase(p$sci_trust_pct,
    "is fairly sceptical of experts and official institutions",
    "takes experts seriously but not uncritically",
    "generally trusts scientists and expert institutions")
  clim <- trait_phrase(p$clim_concern_pct,
    "rarely thinks about environmental questions and does not see them as urgent",
    "sees environmental questions as one concern among many",
    "thinks about environmental questions often and finds them worrying")
  act <- trait_phrase(p$action_pct,
    "does not go out of their way to change habits for a cause",
    "makes a few such choices when convenient",
    "actively changes habits and gives money to causes they believe in")

  sprintf(
"Write a short first-person self-description for one ordinary American adult.

Facts about this person:
- Gender: %s. Age: %s. Race/ethnicity: %s.
- Education: %s. Household income: %s.
- Dispositions: this person %s, %s, and %s.

Write 90-130 words in the first person, present tense. Include their job or
daily routine, where they live, what media they follow, and one concrete
recent experience. Make them specific and ordinary — a real person with an
uneven, particular life, not a representative of a category.

Do not use the words 'Democrat', 'Republican', 'liberal', 'conservative',
'trust', 'climate', or 'science'. Convey the dispositions indirectly through
habits, worries and everyday details.",
    p$gender,
    if (!is.na(p$age)) as.integer(p$age) else p$age_band,
    p$race, p$education, p$income, sci, clim, act)
}

if (identical(stage, "backstories")) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Package 'ellmer' is required.", call. = FALSE)
  }
  prompts <- vapply(seq_len(nrow(profiles)),
                    function(i) build_backstory_prompt(profiles[i, ]), character(1))
  type_bs <- ellmer::type_object(
    backstory = ellmer::type_string(description = "The first-person self-description."))

  out <- vector("list", cfg$n_prompt_variants)
  for (v in seq_len(cfg$n_prompt_variants)) {
    rows <- which(profiles$prompt_variant == v)
    if (!length(rows)) next
    ans <- run_llm(prompts[rows], type_bs, v, "backstories")
    out[[v]] <- data.frame(
      profile_id = profiles$profile_id[rows],
      backstory  = vapply(ans, function(a) as.character(a$backstory %||% NA)[1L],
                          character(1)),
      stringsAsFactors = FALSE)
  }
  bs <- dplyr::bind_rows(out)
  n_bad <- sum(is.na(bs$backstory) | nchar(bs$backstory) < 40)
  if (n_bad) warning(sprintf("%d backstories missing or too short", n_bad))

  dir.create(dirname(cfg$backstories_out), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(bs, cfg$backstories_out)
  message(sprintf("[OK] wrote %s (%d rows)", cfg$backstories_out, nrow(bs)))
  quit(save = "no")
}

## Splice in the narratives if the optional stage was run. Absent, personas are
## built from the structured facts and trait percentiles alone — a complete and
## valid configuration, just a slightly more checklist-like one.
if (file.exists(cfg$backstories_out)) {
  bs <- readr::read_csv(cfg$backstories_out, show_col_types = FALSE)
  profiles <- dplyr::left_join(profiles, bs, by = "profile_id")
  message(sprintf("[OK] narratives: %d/%d personas have one",
                  sum(!is.na(profiles$backstory)), nrow(profiles)))
} else {
  profiles$backstory <- NA_character_
  message("[--] no backstories.csv; using structured personas only")
}


## ===========================================================================
## 3b. Classical model layer
## ===========================================================================
## Regression predictions per person, computed once for the whole pool before
## any call is made. `anchor` is what this person is expected to answer;
## `spread` is how much room they still have around it. Both go into the
## prompt (see lib/priors.R for provenance of every coefficient).

if (isTRUE(cfg$use_model_anchors)) {
  prior_coefs <- load_prior_coefs(cfg$prior_coef_path)
  validate_priors(prior_coefs, sst)
  BASE <- predict_baseline(profiles, prior_coefs,
                           residual_share = cfg$anchor_residual_share)

  ## What the anchors imply about the control condition, before a single token
  ## is spent. If these look wrong, the run will be wrong: the model is being
  ## told to answer near them.
  message("\n--- Implied control-condition means (from the priors alone) ---")
  ctrl_idx <- which(profiles$condition == "control")
  for (o in colnames(BASE$anchor)) {
    message(sprintf("  %-24s %6.1f  (SD across people %.1f)", o,
                    mean(BASE$anchor[ctrl_idx, o]),
                    stats::sd(BASE$anchor[ctrl_idx, o])))
  }
  message("  These are predictions of the human data, arrived at without any LLM.")
  message("  Worth comparing against pipeline/04_diagnostics.R afterwards: if the")
  message("  simulated control means differ substantially from these, the model")
  message("  overrode the anchors and you should know by how much.")
} else {
  BASE <- NULL
  message("\n[--] cfg$use_model_anchors = FALSE: running the trait-percentile ",
          "ablation, no regression anchors in the prompt")
}


## ===========================================================================
## 4. Prompt construction
## ===========================================================================

## The stimulus this respondent saw. Control respondents each got one of three
## fillers (assigned in 01); the extreme-weather arm branches on their state.
stimulus_for <- function(p) {
  txt <- if (identical(p$condition, "Extreme weather predictions")) {
    render_extreme_weather(ew, p$state %||% NA_character_)
  } else if (identical(p$condition, "control")) {
    stim[[paste0("control:", p$control_filler)]]
  } else {
    stim[[p$condition]]
  }
  if (is.null(txt) || !nzchar(txt)) {
    stop("No stimulus text for condition '", p$condition, "'", call. = FALSE)
  }
  txt
}

## `i` is the row index into the profile pool, which is how the anchor matrices
## are keyed. `blocks` restricts the anchors to the blocks this respondent is
## about to see, in the order they will see them.
##
## Stage 1 gets only the two anchors relevant to the pre-treatment items
## (belief and trust); showing the model all thirteen before the stimulus would
## let it plan the whole session backwards from them.
persona_for <- function(p, i = NULL, blocks = NULL) {
  anchors <- NULL
  if (!is.null(BASE) && !is.null(i) && !is.null(blocks)) {
    anchors <- render_anchors(BASE$anchor[i, ], BASE$spread[i, ], blocks)
    if (!nzchar(anchors)) anchors <- NULL
  }
  render_backstory(p, cfg$source_type, p$backstory, anchors)
}

## Block order is per-respondent: the primary trust block first, the rest
## shuffled, mirroring the instrument's block randomizer. Seeded off the
## profile id, so it is reproducible and independent of run order — and of
## whether the run was resumed.
##
## HONEST LIMITATION. This randomises the order in which the items are READ,
## not the order in which they are ANSWERED: structured output is generated in
## schema order, and the schema is fixed across respondents so that one call
## can cover a whole variant group. Order effects in the human data therefore
## are only partially reproduced. Randomising the schema too would mean one
## type object per respondent, which the parallel and batch runners do not
## support. Declare this under registration E.3 rather than claiming the
## instrument's randomisation was fully replicated.
blocks_for <- function(p) {
  block_order(cfg$seed + as.integer(sub("^p", "", p$profile_id)))
}

fmt_num <- function(x) {
  if (is.null(x) || length(x) == 0L || is.na(x)) "(no answer)"
  else sprintf("%d", as.integer(round(x)))
}

prompt_stage1 <- function(p, i = NULL) {
  paste(
    ## Only the two pre-treatment anchors. Handing over all thirteen here would
    ## let the model plan the whole session backwards from the post-treatment
    ## targets, which would defeat the point of measuring pre-treatment first.
    persona_for(p, i, c("belief", "trust_single")),
    "",
    "---",
    "",
    paste("This person has begun an online survey. After some background",
          "questions they were told:"),
    "",
    paste('  "Climate scientists study changes in the Earth\'s climate over time',
          'and how they might affect the planet in the future. Please keep this',
          'definition in mind when answering the following questions."'),
    "",
    if (identical(cfg$elicitation, "distribution")) instructions_distribution(nrow(PRE_ITEMS))
    else instructions_point(nrow(PRE_ITEMS)),
    "",
    render_block(PRE_ITEMS, "pre"),
    "",
    paste("Also give `self_description`: two or three sentences, in this",
          "person's own voice and vocabulary, on what they make of climate",
          "change and of climate scientists. Write what they would actually",
          "say, hedges and all — not a tidy summary."),
    sep = "\n")
}

## Stage 1 is replayed as text. The numbers alone would leave the model free to
## re-derive its stance from the persona; replaying the self-description fixes
## the voice too, which is what keeps the ~40 post items consistent with THIS
## respondent rather than merely with their demographic label.
prompt_stage2 <- function(p, pre, i = NULL) {

  blocks <- blocks_for(p)

  recap <- paste0(
    "EARLIER IN THIS SURVEY, BEFORE READING ANYTHING, THIS PERSON ANSWERED\n",
    sprintf('- "How accurate is: human activities are causing climate change?" (0-100): %s\n',
            fmt_num(pre$belief_pre)),
    sprintf('- "How much do you trust climate scientists?" (0-100): %s\n',
            fmt_num(pre$trust_pre)),
    if (!is.null(pre$self_description) && !is.na(pre$self_description) &&
        nzchar(pre$self_description))
      sprintf('- In their own words: "%s"\n', pre$self_description) else "")

  ## The intervention prior is stated AFTER the stimulus and before the
  ## questions: it is a statement about what texts like the one just read
  ## typically achieve, so it belongs where the model is deciding how far to
  ## move. Placing it earlier would have it read as a fact about the person.
  ##
  ## Moderation uses the respondent's own pre-treatment belief where we have
  ## it, falling back to the model-predicted belief. That is the moderator the
  ## megastudy actually reports heterogeneity on.
  iv_prior <- if (isTRUE(cfg$state_intervention_prior) &&
                  !identical(p$condition, "control")) {
    b <- pre$belief_pre
    if (is.null(b) || is.na(b)) {
      b <- if (!is.null(BASE) && !is.null(i)) BASE$anchor[i, "belief_post"] else 60
    }
    c("", render_intervention_prior(b), "")
  } else character(0)

  paste(c(
    persona_for(p, i, blocks),
    "",
    recap,
    "---",
    "",
    "THE PERSON WAS THEN SHOWN THE FOLLOWING TEXT AND ASKED TO READ IT CAREFULLY",
    "",
    stimulus_for(p),
    "",
    "---",
    iv_prior,
    paste("They then answered the questions below. Their earlier answers are",
          "context, not a constraint: a person can be moved by what they just",
          "read, or not moved at all. Most people are not moved much."),
    "",
    if (identical(cfg$elicitation, "distribution")) instructions_distribution(nrow(POST_ITEMS))
    else instructions_point(nrow(POST_ITEMS)),
    "",
    render_questionnaire(POST_ITEMS, blocks)),
    collapse = "\n")
}


## ===========================================================================
## 5. Structured-output schema
## ===========================================================================
## One field per item, keyed by the Qualtrics variable name — the same
## vocabulary items.R, the raw export and codebook.csv use, so nothing has to
## be renamed anywhere downstream.

build_type <- function(items, extra = list()) {
  fields <- list()
  for (i in seq_len(nrow(items))) {
    q <- items$q[i]
    fields[[q]] <- if (identical(cfg$elicitation, "distribution")) {
      ellmer::type_array(
        items       = ellmer::type_integer(),
        description = sprintf(
          "Five whole percentages summing to 100, over the fifths of the scale, for: %s",
          items$text[i]))
    } else {
      ellmer::type_integer(description = items$text[i])
    }
  }
  do.call(ellmer::type_object, c(fields, extra))
}


## ===========================================================================
## 6. Parsing and sampling
## ===========================================================================

## Five bins over the response scale; the model reports the share of
## like-respondents falling in each.
bin_edges <- function(type) {
  switch(type,
    dollar = c(-0.5, 2.5, 4.5, 6.5, 8.5, 10.5),   # $0-2, 3-4, 5-6, 7-8, 9-10
    c(0, 20, 40, 60, 80, 100))                    # sliders and probabilities
}

## Inverse CDF of the piecewise-uniform distribution implied by `probs` over
## `edges`. This is what turns the model's stated uncertainty into a draw.
qpiecewise <- function(u, probs, edges) {
  p <- suppressWarnings(as.numeric(probs))
  if (length(p) != length(edges) - 1L || anyNA(p) || all(p <= 0)) return(NA_real_)
  p <- pmax(p, 0); p <- p / sum(p)
  cum <- cumsum(p)
  k <- which(u <= cum)[1L]
  if (is.na(k)) k <- length(p)
  lo_cum <- if (k == 1L) 0 else cum[k - 1L]
  frac <- if (p[k] > 0) (u - lo_cum) / p[k] else 0.5
  edges[k] + min(max(frac, 0), 1) * (edges[k + 1L] - edges[k])
}

## One independent uniform per item. The draw resolves the model's stated
## uncertainty about that item and nothing else — a respondent's position on
## the underlying attitude is already fixed, before any call, by the regression
## anchors in lib/priors.R.

## Response-style extremity: stretch or compress the answer around the scale
## midpoint. Clipping at the ends is not a defect — it is the mechanism that
## reproduces the pile-up on 0 and 100 that every real slider dataset shows and
## that unaided LLM output never does. It does mean an item already sitting near
## a bound gets nudged toward it; since extremity is assigned independently of
## condition in 01, that inflates variance and shifts levels slightly, but does
## not bias the treatment contrast.
EXTREMITY_K <- c(moderate = 0.85, average = 1.00, extreme = 1.15)

apply_extremity <- function(v, style, type) {
  if (!identical(type, "slider")) return(v)   # dollars and probabilities untouched
  k <- unname(EXTREMITY_K[style])
  if (is.na(k)) k <- 1
  min(max(50 + (v - 50) * k, 0), 100)
}

## Parse one respondent's structured answer into continuous item values.
parse_respondent <- function(ans, items, style) {
  n <- nrow(items)
  u <- stats::runif(n)
  out <- stats::setNames(rep(NA_real_, n), items$q)
  if (is.null(ans) || !length(ans)) return(out)

  for (i in seq_len(n)) {
    q   <- items$q[i]
    val <- ans[[q]]
    if (is.null(val)) next

    v <- if (identical(cfg$elicitation, "distribution")) {
      qpiecewise(u[i], unlist(val), bin_edges(items$type[i]))
    } else {
      suppressWarnings(as.numeric(val)[1L])
    }
    if (is.na(v)) next

    rng <- if (identical(items$type[i], "dollar")) c(0, 10) else c(0, 100)
    out[[q]] <- apply_extremity(min(max(v, rng[1]), rng[2]), style, items$type[i])
  }
  out
}


## ===========================================================================
## 7. Dry run
## ===========================================================================

if (dry_run) {
  ## Show the extreme-weather arm: it is the only condition whose stimulus is
  ## assembled rather than looked up, so it is the one worth eyeballing.
  i <- which(profiles$condition == "Extreme weather predictions")[1]
  if (is.na(i)) i <- 1L
  p <- profiles[i, ]
  cat("\n=========== STAGE 1 SYSTEM (variant ", p$prompt_variant, ") ===========\n\n", sep = "")
  cat(SYSTEM_VARIANTS[[p$prompt_variant]], "\n")
  cat("\n=========== STAGE 1 USER ===========\n\n")
  cat(prompt_stage1(p, i), "\n")
  cat("\n=========== STAGE 2 USER ===========\n\n")
  cat(prompt_stage2(p, list(belief_pre = 72, trust_pre = 55,
                            self_description = "(example)"), i), "\n")
  message("\n--dry-run: no API calls made, nothing written.")
  quit(save = "no")
}


## ===========================================================================
## 8. Run
## ===========================================================================

if (!requireNamespace("ellmer", quietly = TRUE)) {
  stop("Package 'ellmer' is required. install.packages(\"ellmer\")", call. = FALSE)
}

type_pre <- build_type(PRE_ITEMS, extra = list(
  self_description = ellmer::type_string(
    description = "Two or three sentences in this person's own voice.")))
type_post <- build_type(POST_ITEMS)

chunks <- split(seq_len(nrow(profiles)),
                ceiling(seq_len(nrow(profiles)) / cfg$chunk_size))
message(sprintf("\nRunning %d respondents in %d chunk(s) of up to %d [%s, %s]",
                nrow(profiles), length(chunks), cfg$chunk_size,
                cfg$elicitation, if (isTRUE(cfg$use_batch)) "batch" else "parallel"))

## `on_error = "return"` means a failed request lands as NULL rather than
## aborting the chunk, so a transient 529 costs one retry, not the run.
is_bad <- function(ans, items) {
  if (is.null(ans) || !length(ans)) return(TRUE)
  present <- vapply(items$q, function(q) !is.null(ans[[q]]), logical(1))
  mean(present) < 0.9
}

run_with_retries <- function(prompts, type, variant, tag, items) {
  ans <- run_llm(prompts, type, variant, tag)
  for (attempt in seq_len(cfg$max_retries)) {
    bad <- which(vapply(ans, is_bad, logical(1), items = items))
    if (!length(bad)) break
    message(sprintf("    retry %d: %d incomplete", attempt, length(bad)))
    ans[bad] <- run_llm(prompts[bad], type, variant,
                        sprintf("%s_retry%d", tag, attempt))
  }
  ans
}

all_rows <- vector("list", length(chunks))

for (ci in seq_along(chunks)) {

  chunk_file <- file.path(cfg$chunks_dir, sprintf("chunk_%04d.rds", ci))
  if (resume && file.exists(chunk_file)) {
    all_rows[[ci]] <- readRDS(chunk_file)
    message(sprintf("  chunk %d/%d: resumed from disk", ci, length(chunks)))
    next
  }

  ## `gidx` maps a chunk row back to its row in the full pool, which is how the
  ## anchor matrices from predict_baseline() are keyed. Using the chunk-local
  ## index instead would silently hand every respondent someone else's
  ## predictions — and the output would look entirely reasonable.
  gidx <- chunks[[ci]]
  pc   <- profiles[gidx, ]
  message(sprintf("  chunk %d/%d: %d respondents", ci, length(chunks), nrow(pc)))

  ## Group by prompt variant: the variant lives in the system prompt, so one
  ## chat object serves every respondent assigned to it.
  by_variant <- split(seq_len(nrow(pc)), pc$prompt_variant)

  pre_ans  <- vector("list", nrow(pc))
  post_ans <- vector("list", nrow(pc))

  ## --- stage 1 ---
  for (v in names(by_variant)) {
    rows <- by_variant[[v]]
    prompts <- vapply(rows, function(r) prompt_stage1(pc[r, ], gidx[r]),
                      character(1))
    pre_ans[rows] <- run_with_retries(prompts, type_pre, as.integer(v),
                                      sprintf("s1_c%04d", ci), PRE_ITEMS)
  }

  ## Sample the pre-treatment values now: stage 2 replays the number the
  ## respondent actually entered, not the distribution behind it.
  pre_vals <- lapply(seq_len(nrow(pc)), function(r) {
    v <- parse_respondent(pre_ans[[r]], PRE_ITEMS, pc$style_extremity[r])
    s <- pre_ans[[r]][["self_description"]]
    list(belief_pre = unname(v[["belief_pre"]]),
         trust_pre  = unname(v[["trust_pre"]]),
         self_description = if (is.null(s)) NA_character_ else as.character(s)[1L])
  })

  ## --- stage 2 ---
  for (v in names(by_variant)) {
    rows <- by_variant[[v]]
    prompts <- vapply(rows, function(r) prompt_stage2(pc[r, ], pre_vals[[r]],
                                                      gidx[r]), character(1))
    post_ans[rows] <- run_with_retries(prompts, type_post, as.integer(v),
                                       sprintf("s2_c%04d", ci), POST_ITEMS)
  }

  ## --- assemble ---
  vals <- t(vapply(seq_len(nrow(pc)), function(r) {
    parse_respondent(post_ans[[r]], POST_ITEMS, pc$style_extremity[r])
  }, numeric(nrow(POST_ITEMS))))
  colnames(vals) <- POST_ITEMS$q

  rows_df <- data.frame(
    profile_id       = pc$profile_id,
    condition        = pc$condition,
    prompt_variant   = pc$prompt_variant,
    style_rounding   = pc$style_rounding,
    style_extremity  = pc$style_extremity,
    belief_pre       = vapply(pre_vals, function(x) x$belief_pre %||% NA_real_, numeric(1)),
    trust_pre        = vapply(pre_vals, function(x) x$trust_pre  %||% NA_real_, numeric(1)),
    self_description = vapply(pre_vals, function(x) x$self_description %||% NA_character_,
                              character(1)),
    stringsAsFactors = FALSE)
  rows_df <- cbind(rows_df, as.data.frame(vals))

  ## Registration K.2: the model's own output, before any of our sampling, is
  ## part of the transparency record. Store it verbatim.
  saveRDS(list(pre = pre_ans, post = post_ans, profile_id = pc$profile_id),
          file.path(cfg$logs_dir, sprintf("raw_output_c%04d.rds", ci)))

  saveRDS(rows_df, chunk_file)
  all_rows[[ci]] <- rows_df

  n_ok <- sum(stats::complete.cases(vals))
  message(sprintf("    %d/%d complete (%.1f%%)", n_ok, nrow(pc), 100 * n_ok / nrow(pc)))
}

responses <- dplyr::bind_rows(all_rows)


## ===========================================================================
## 9. Report and write
## ===========================================================================

item_cols <- POST_ITEMS$q
ok <- stats::complete.cases(responses[, item_cols])
message(sprintf("\n%d/%d respondents complete on all %d items (%d incomplete)",
                sum(ok), nrow(responses), length(item_cols), sum(!ok)))

## The precision floor is checked on the rows that SURVIVE, not the rows we
## asked for. cfg$n_per_intervention = 750 against a floor of 500 is exactly
## the headroom that lets us drop these.
tab <- table(responses$condition[ok])
iv  <- tab[names(tab) != "control"]
if (length(iv)) {
  n_ctrl <- if ("control" %in% names(tab)) tab[["control"]] else 0L
  message(sprintf("Usable per condition: control %d | interventions min %d, max %d",
                  n_ctrl, min(iv), max(iv)))
  if (is.na(limit_n) && (n_ctrl < 1000 || min(iv) < 500)) {
    warning("Below the benchmark's precision floor (1000 control / 500 per ",
            "intervention) after dropping incomplete respondents. Raise ",
            "cfg$n_per_intervention / cfg$n_control and re-run, or `make check` ",
            "will flag the submission.", call. = FALSE)
  }
}

## Did the model follow the anchors?
##
## This is the question the whole design turns on, and it has two bad answers.
## If the model reproduces the anchors exactly, the submission is a regression
## with an expensive wrapper and the LLM contributed nothing. If it ignores
## them, the calibration was never applied and the run is the un-anchored
## version with extra steps. The useful outcome is in between: anchored levels,
## with the model supplying deviation where the specific item or the stimulus
## warrants it.
usable <- responses[ok, , drop = FALSE]

if (nrow(usable) > 30 && !is.null(BASE)) {
  message("\n--- Anchor adherence (control condition) ---")
  ctrl <- usable$condition == "control"
  gi   <- match(usable$profile_id, profiles$profile_id)

  ## Compare each anchored block's realised mean with the anchor it was given.
  for (b in names(BLOCK_ANCHOR)) {
    qs <- POST_ITEMS$q[POST_ITEMS$block == b]
    if (!length(qs)) next
    realised <- rowMeans(usable[, qs, drop = FALSE])
    given    <- BASE$anchor[gi, BLOCK_ANCHOR[[b]]]
    keep     <- ctrl & !is.na(realised) & !is.na(given)
    if (sum(keep) < 30) next
    message(sprintf("  %-16s anchor %5.1f -> realised %5.1f (bias %+5.1f, r = %+.2f)",
                    b, mean(given[keep]), mean(realised[keep]),
                    mean(realised[keep] - given[keep]),
                    stats::cor(given[keep], realised[keep])))
  }
  message("  r near 1.00 with bias near 0: the model is transcribing the")
  message("  regression. r near 0: it ignored it. Somewhere around .6-.9 with a")
  message("  small bias is the design working as intended.")
  message("  Report this table under registration G.2 — it is the honest answer")
  message("  to 'what did the language model actually contribute?'")
}

if (nrow(usable) > 30) {
  tr <- rowMeans(usable[, POST_ITEMS$q[POST_ITEMS$block == "trust"]])
  message(sprintf("\nSpot check: mean(trust battery) = %.1f, SD = %.1f",
                  mean(tr), stats::sd(tr)))
  message("  Real 0-100 attitude items: SD roughly 20-25. A much smaller SD means")
  message("  the personas collapsed onto a modal answer despite the anchor spread.")
}

dir.create(dirname(cfg$responses_out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(responses, cfg$responses_out)
message(sprintf("\n[OK] wrote %s (%d rows)", cfg$responses_out, nrow(responses)))

## The rendered personas are the actual model input and therefore part of the
## reproducibility record: profiles.csv alone does not determine them once
## anyone edits persona.R or the prior coefficients.
readr::write_csv(
  data.frame(
    profile_id     = profiles$profile_id,
    prompt_variant = profiles$prompt_variant,
    persona        = vapply(seq_len(nrow(profiles)), function(i)
                       persona_for(profiles[i, ], i, blocks_for(profiles[i, ])),
                       character(1)),
    stringsAsFactors = FALSE),
  file.path(dirname(cfg$responses_out), "personas_rendered.csv"))

## The anchors themselves, one row per person. These ARE a prediction of the
## human data — made without any LLM — so keeping them lets you score the
## classical model separately and report what the language model added.
if (!is.null(BASE)) {
  readr::write_csv(
    cbind(data.frame(profile_id = profiles$profile_id,
                     condition = profiles$condition,
                     stringsAsFactors = FALSE),
          as.data.frame(BASE$anchor)),
    file.path(dirname(cfg$responses_out), "model_anchors.csv"))
  readr::write_csv(BASE$coefs,
                   file.path(dirname(cfg$responses_out), "prior_coefs_used.csv"))
}

message("Next: Rscript pipeline/03_export.R")
