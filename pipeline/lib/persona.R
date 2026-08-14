## ---------------------------------------------------------------------------
## persona.R — turn one row of profiles.csv into the text the model is asked
## to answer as.
##
## DESIGN NOTE (registration D.2 / E.2)
##
## The literature's recurring finding is that a persona built from a
## demographic checklist ("You are a 52-year-old white Republican woman…")
## produces a caricature: subgroup means separate far more than real subgroups
## do, and within-subgroup variance collapses. Two things push back on that,
## and both are implemented here.
##
##  1. Auxiliary conditioning. The donor row carries ideology, religion,
##     attendance, region/urbanicity, marital status and work status. These are
##     never scored, but they break the demographic stereotype by giving the
##     model a person rather than a cell label.
##
##  2. Latent traits, verbalised as *percentiles* rather than as adjectives.
##     "More trusting of scientists than about 30% of Americans" is a
##     quantitative instruction the model can follow monotonically; "somewhat
##     distrustful" is an adjective it will map to whatever its prior says the
##     modal distrustful person looks like — which re-imposes the caricature the
##     traits exist to avoid.
##
## The traits themselves come from 01_build_profiles.R, where they are a linear
## function of demographics plus a large correlated residual. That residual is
## the *only* reason two personas with identical demographics answer
## differently, so the persona text must transmit it — hence percentiles.
## ---------------------------------------------------------------------------


## --- auxiliary-code dictionaries -------------------------------------------
## anes_recode.R deliberately keeps aux_* columns as raw ANES codes so that the
## mapping to prose lives in exactly one place: here. Codes that are not listed
## (don't know / refused / inapplicable / negative sentinels) render as NULL and
## the corresponding clause is simply omitted — an incomplete backstory is
## better than a fabricated one.

AUX_LABELS <- list(

  anes_cumulative = list(
    ideology = c(
      "1" = "extremely liberal", "2" = "liberal", "3" = "slightly liberal",
      "4" = "middle of the road", "5" = "slightly conservative",
      "6" = "conservative", "7" = "extremely conservative"
    ),
    religion = c(
      "1" = "Protestant", "2" = "Catholic", "3" = "Jewish", "4" = "other or no religion"
    ),
    attendance = c(
      "1" = "attends religious services every week",
      "2" = "attends religious services almost every week",
      "3" = "attends religious services once or twice a month",
      "4" = "attends religious services a few times a year",
      "5" = "never attends religious services"
    ),
    region = c(
      "1" = "the Northeast", "2" = "the North Central states",
      "3" = "the South", "4" = "the West"
    ),
    marital = c(
      "1" = "married", "2" = "divorced", "3" = "widowed",
      "4" = "separated", "5" = "never married"
    ),
    employment = c(
      "1" = "working now", "2" = "temporarily laid off", "4" = "unemployed",
      "5" = "retired", "6" = "permanently disabled",
      "7" = "keeping house", "8" = "a student"
    )
  ),

  anes_2020 = list(
    ideology = c(
      "1" = "extremely liberal", "2" = "liberal", "3" = "slightly liberal",
      "4" = "moderate", "5" = "slightly conservative",
      "6" = "conservative", "7" = "extremely conservative"
    ),
    religion = c(
      "1" = "Protestant", "2" = "Roman Catholic", "3" = "Orthodox Christian",
      "4" = "Latter-Day Saints", "5" = "Jewish", "6" = "Muslim",
      "7" = "Buddhist", "8" = "Hindu", "9" = "Atheist", "10" = "Agnostic",
      "11" = "of another faith", "12" = "of no particular religion"
    ),
    attendance = c(
      "1" = "attends religious services every week or more",
      "2" = "attends religious services almost every week",
      "3" = "attends religious services once or twice a month",
      "4" = "attends religious services a few times a year",
      "5" = "never attends religious services"
    ),
    urbanicity = c(
      "1" = "a rural area", "2" = "a small town",
      "3" = "a suburb", "4" = "a city"
    ),
    marital = c(
      "1" = "married and living with their spouse", "2" = "married but separated",
      "3" = "widowed", "4" = "divorced", "5" = "separated", "6" = "never married"
    ),
    employment = c(
      "1" = "working now", "2" = "temporarily laid off", "3" = "unemployed",
      "4" = "retired", "5" = "permanently disabled",
      "6" = "keeping house", "7" = "a student"
    )
  )
)


aux_label <- function(profile, key, source_type) {
  col <- paste0("aux_", key)
  if (is.null(profile[[col]])) return(NULL)
  raw <- as.character(profile[[col]])
  if (is.na(raw) || !nzchar(raw)) return(NULL)
  dict <- AUX_LABELS[[source_type]][[key]]
  if (is.null(dict)) return(NULL)
  val <- unname(dict[raw])
  if (is.na(val)) NULL else val
}


## --- trait verbalisation ----------------------------------------------------
## Percentiles, not adjectives. See the design note above.

TRAIT_FRAMES <- list(
  sci_trust = paste(
    "trusts scientists in general more than about %d%% of American adults"),
  clim_concern = paste(
    "is more concerned about climate change than about %d%% of American adults"),
  action = paste(
    "is more willing to change their own behaviour or give money for an",
    "environmental cause than about %d%% of American adults")
)

## SUPERSEDED by the model anchors in lib/priors.R, and kept only as a fallback
## for cfg$use_model_anchors = FALSE (useful as an ablation: run the same
## pipeline with and without the anchors and the difference is what the
## classical models contributed). The percentiles say where the person sits on
## an abstract disposition; the anchors say what they are expected to answer,
## on the actual scale, with a spread attached. The second is strictly more
## information and is what the model needs.
render_traits <- function(profile) {
  out <- character(0)
  for (tn in names(TRAIT_FRAMES)) {
    pct <- profile[[paste0(tn, "_pct")]]
    if (is.null(pct) || is.na(pct)) next
    out <- c(out, sprintf(TRAIT_FRAMES[[tn]], as.integer(pct)))
  }
  out
}


## --- response style ---------------------------------------------------------
## Only the extremity tendency is verbalised. The rounding granularity is NOT
## described to the model: telling it "round to multiples of 10" invites it to
## also flatten the underlying judgement, and it is applied deterministically in
## 02_simulate.R anyway, where it cannot contaminate anything else.

STYLE_TEXT <- c(
  moderate = paste(
    "When using rating scales, this person tends to avoid the extreme ends and",
    "keeps their answers in the middle range unless they feel strongly."),
  average  = paste(
    "This person uses rating scales in an ordinary way, using the full range",
    "when they have a clear view."),
  extreme  = paste(
    "When using rating scales, this person readily uses the extreme ends,",
    "including 0 and 100, when their view is clear.")
)


## --- backstory ---------------------------------------------------------------

fmt_age <- function(profile) {
  if (!is.null(profile$age) && !is.na(profile$age)) {
    sprintf("%d years old", as.integer(profile$age))
  } else {
    sprintf("in the %s age group", profile$age_band)
  }
}

## Party is rendered as plain self-identification. Note that with
## fold_leaners = TRUE (the default in 01_build_profiles.R) ANES leaners are
## counted as partisans, which makes the synthetic pool somewhat more partisan
## than the benchmark's own four-way item would. If the party moderator cells
## come out too separated, that flag is the first thing to change.
##
## `narrative` is the optional LLM-written first-person sketch produced by
## `02_simulate.R --stage backstories`. When present it is placed FIRST and the
## structured facts follow it: the narrative de-stereotypes (a life with a job
## and a routine is harder to caricature than a demographic cell), the facts
## keep the moderators explicit.
##
## `anchors` is the rendered block of predictions from lib/priors.R — what a
## regression on US survey data expects this person to answer, and how widely
## people like them scatter around it. It goes LAST, immediately before the
## questions, because it is the part the model should still have in view when
## it answers.
##
## The division of labour, and it is worth being precise about it in
## registration.md: the regression supplies the LEVEL, which is a population
## quantity an LLM has no calibrated access to; the LLM supplies the RESPONSE
## to a specific text for a specific person, which no regression in this
## literature can supply. Neither component is doing the other's job.
render_backstory <- function(profile, source_type, narrative = NULL,
                             anchors = NULL) {

  bits <- c(
    sprintf("%s, %s", profile$gender, fmt_age(profile)),
    sprintf("identifies as %s", profile$race),
    sprintf("highest education: %s", profile$education),
    sprintf("household income: %s", profile$income),
    sprintf("identifies politically as %s", profile$party)
  )

  ideol <- aux_label(profile, "ideology", source_type)
  if (!is.null(ideol)) bits <- c(bits, sprintf("politically %s", ideol))

  relig <- aux_label(profile, "religion", source_type)
  att   <- aux_label(profile, "attendance", source_type)
  if (!is.null(relig)) {
    bits <- c(bits, if (!is.null(att)) sprintf("%s, %s", relig, att) else relig)
  } else if (!is.null(att)) {
    bits <- c(bits, att)
  }

  ## The cumulative file carries census region, the 2020 file urbanicity.
  place <- aux_label(profile, "region", source_type)
  if (is.null(place)) {
    urb <- aux_label(profile, "urbanicity", source_type)
    if (!is.null(urb)) place <- urb
  }
  if (!is.null(place)) bits <- c(bits, sprintf("lives in %s", place))

  mar <- aux_label(profile, "marital", source_type)
  if (!is.null(mar)) bits <- c(bits, mar)

  emp <- aux_label(profile, "employment", source_type)
  if (!is.null(emp)) bits <- c(bits, emp)

  style <- unname(STYLE_TEXT[profile$style_extremity])

  has_narr   <- !is.null(narrative) && !is.na(narrative) && nzchar(narrative)
  has_anchor <- !is.null(anchors) && nzchar(anchors)

  ## Trait percentiles are the fallback: informative when there are no model
  ## anchors, redundant and slightly contradictory once there are (they would
  ## state the same person-level standing twice, in two different currencies).
  traits <- if (has_anchor) character(0) else render_traits(profile)

  paste0(
    if (has_narr) paste0("IN THIS PERSON'S OWN WORDS\n", narrative, "\n\n") else "",
    "PERSON\n",
    paste0("- ", bits, collapse = "\n"),
    if (length(traits)) paste0(
      "\n\nHOW THIS PERSON COMPARES WITH OTHER AMERICANS\n",
      paste0("- ", traits, collapse = "\n")
    ) else "",
    "\n\nANSWERING STYLE\n- ", style,
    if (has_anchor) paste0("\n\n", anchors) else ""
  )
}


## --- prompt variants ---------------------------------------------------------
## Roughly half the variance in persona-panel estimates sits between prompt
## phrasings rather than between personas (registration E.2). Averaging over
## semantically equivalent variants converts that from an unmeasured bias into
## measurable noise. The variants below differ in framing, not in content: none
## adds, removes, or reweights any information about the person.
##
## Keep them genuinely equivalent. A variant that, say, stresses honesty more
## than the others is a different treatment, not a paraphrase.

SYSTEM_VARIANTS <- c(

  ## 1. First-person inhabitation.
  paste(
    "You are taking part in an online survey of American adults. Answer every",
    "question as the person described below would answer it, not as you would.",
    "\n\nStay inside that person's point of view: their level of information,",
    "their interests and their patience with a long questionnaire. Real survey",
    "respondents are not consistent, well-informed, or eager to please. Some",
    "questions they have a firm view on; others they answer quickly and",
    "approximately. Do not soften or balance their views to be agreeable.",
    "\n\nYou answer only with the requested structured output. No commentary."
  ),

  ## 2. Third-person prediction.
  paste(
    "You are a survey methodologist predicting how one specific American adult",
    "would fill in an online questionnaire. You are given a description of that",
    "person; produce the answers they would actually give.",
    "\n\nBase the answers on how people with this combination of background,",
    "politics and dispositions actually respond in US survey data — not on how",
    "a thoughtful or well-informed person ought to respond. Individual",
    "respondents deviate from their group's average in both directions; the",
    "description tells you where this one sits.",
    "\n\nYou answer only with the requested structured output. No commentary."
  ),

  ## 3. Reconstruction from a completed questionnaire.
  paste(
    "A specific American adult has already completed an online survey. You are",
    "reconstructing the answers they gave, from a description of who they are.",
    "\n\nGive the answers that person recorded, including the inconsistencies",
    "and rough approximations real respondents produce. Do not produce the",
    "answers of an idealised, informed, or moderate respondent; produce theirs.",
    "\n\nYou answer only with the requested structured output. No commentary."
  )
)

stopifnot(length(SYSTEM_VARIANTS) >= 1)


## --- elicitation instructions ------------------------------------------------
## Two modes, set by cfg$elicitation.
##
## "point" asks for the single number the respondent would enter.
##
## "distribution" asks instead for how the answer would be distributed if the
## same kind of person answered many times, and 02_simulate.R samples from it.
## This is the single most effective fix for within-cell variance collapse:
## a model asked for one number returns something close to the mode of its
## posterior, and a cell built out of modes has far less spread than a cell
## built out of draws. It costs roughly five times the output tokens.

instructions_point <- function(n_items) sprintf(paste(
  "Below are %d survey questions in the order this person saw them.",
  "For each one, give the single number this person entered.",
  "\n\nSliders are whole numbers from 0 to 100. The donation is a whole number",
  "of dollars from 0 to 10. For the newsletter question, give the percentage",
  "chance from 0 to 100 that this person subscribed.",
  "\n\nAnswer every question. Use the bracketed variable name as the field name."
), n_items)

instructions_distribution <- function(n_items) sprintf(paste(
  "Below are %d survey questions in the order this person saw them.",
  "\n\nFor each question, do not give a single number. Instead give how this",
  "person's answer would be distributed if many people just like them — same",
  "background, same politics, same dispositions — answered it. Report five",
  "whole percentages that sum to 100, giving the share of such people whose",
  "answer would fall in each fifth of the scale:",
  "\n\n  [0-20, 21-40, 41-60, 61-80, 81-100]",
  "\n\nExample: [0, 5, 20, 45, 30] means most such people answer in the upper",
  "half, with a long tail downwards.",
  "\n\nSpread matters as much as location. People who look alike on paper still",
  "disagree, so a distribution concentrated in one bin should be rare and",
  "reserved for questions where such people really do agree almost entirely.",
  "\n\nWhere a statistical prediction is given above, it tells you both: the",
  "predicted value is roughly where the distribution should be centred, and",
  "the scatter given with it is roughly how wide it should be. Individual",
  "items within a block may sit above or below the block's prediction - that",
  "is expected - but the block should average out near it.",
  "\n\nThe donation question uses the same five bins over $0-$10:",
  "[$0-2, $3-4, $5-6, $7-8, $9-10]. For the newsletter question, use the bins",
  "over the percentage chance that this person subscribed.",
  "\n\nAnswer every question. Use the bracketed variable name as the field name."
), n_items)
