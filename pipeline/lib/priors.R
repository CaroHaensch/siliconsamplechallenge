## ---------------------------------------------------------------------------
## priors.R — the classical model layer.
##
## Two published-evidence models, both computed BEFORE any LLM call and both
## written into the prompt:
##
##   A. BASELINE.  A linear model of each outcome on the six moderators,
##      giving the value this person would be expected to give in the control
##      condition, plus the spread of people like them around it.
##
##   B. INTERVENTION.  A prior on how much a single short text moves a 0-100
##      attitude item at all, and for whom.
##
## WHY ANCHOR THE MODEL AT ALL
##
## An LLM asked to be a 52-year-old Republican woman answers from its internal
## picture of that category, and that picture is systematically wrong in two
## documented directions at once: subgroup means are too far apart, and spread
## inside a subgroup is too small. Neither is fixable by better prompt wording,
## because the model has no calibrated access to the population quantity.
##
## A regression does. So we hand it over: the level and the spread come from
## survey research, the LLM supplies what regressions cannot — how this
## particular person reacts to this particular text, given who they are.
##
##
## ⚠ EVERY NUMBER IN THIS FILE IS A PRIOR (registration D.2 / G.3 / I.3)
##
## They are read off published US survey research and one published megastudy.
## None is fitted to any data from the target study, whose results are not
## public and which none of these sources measured. They are therefore
## defensible as priors and indefensible as calibration: do not tune them to
## make the output look better, because "we adjusted our priors until the
## predictions looked right" is not a method anyone can report honestly.
##
## Sources are named per coefficient block below, in the `source` column, which
## is written out to pipeline/out/prior_coefs_used.csv on every run so that
## registration.md can be filled from the file rather than from memory.
##
## Where a source reports a categorical split ("% with at least a fair amount
## of confidence") and we need a location on a 0-100 slider, the conversion is
## an assumption — a latent-normal one — and it is baked into the coefficient
## rather than exposed as a knob, because there is no principled way to tune it
## and a knob would invite exactly that. If you disagree with a conversion,
## change the coefficient and say so; do not sweep it.
##
## To replace these with coefficients you estimate yourself on public
## microdata, run pipeline/01b_fit_priors.R; it writes a CSV that
## `load_prior_coefs()` picks up in place of the defaults below.
## ---------------------------------------------------------------------------


## ===========================================================================
## A. BASELINE MODEL
## ===========================================================================
##
## Specification, for outcome o and person i:
##
##   mu_oi = base_o
##         + party_o[party_i]
##         + educ_o  * educ_z_i        (education rank, standardised)
##         + age_o   * age_z_i         (age in years, standardised)
##         + female_o * 1[female]
##         + nonwhite_o * 1[non-white]
##         + income_o * inc_z_i        (income rank, standardised)
##
## and the person's anchor is
##
##   anchor_oi = mu_oi + resid_sd_o * e_i(o)
##
## where e_i(o) is the standardised person-level residual already drawn in
## 01_build_profiles.R (the latent traits). Reusing it means two respondents in
## the same demographic cell get different anchors — which is the whole point,
## since it is within-cell homogeneity that the method fails on.
##
## COLUMNS
##   base       expected value at the reference cell (Independent, average
##              education / age / income, male, white), on the outcome's own
##              scale
##   rep/dem/ind/oth   party offsets (Independent = 0 by construction)
##   educ, age, income   per standard deviation
##   female, nonwhite    level offsets
##   resid_sd   spread of individuals around their own fitted value
##   trait      which latent residual from 01 drives this outcome
##   source     provenance, for registration.md
##
## PARTY IS THE LARGEST DEMOGRAPHIC PREDICTOR BY A WIDE MARGIN, and everything
## else is comparatively small. Hornsey et al. (2016), meta-analysing 25 polls
## and 171 studies across 56 nations, find political affiliation roughly twice
## the effect size of any other demographic, with education, sex, subjective
## knowledge and personal experience of extreme weather all much weaker than
## values and ideology. The coefficient sizes below reflect that ordering; a
## specification that gives education or age a party-sized coefficient is
## contradicting the best available evidence.

PRIOR_BASELINE <- local({

  row <- function(outcome, base, rep, dem, oth = 0, educ = 0, age = 0,
                  female = 0, nonwhite = 0, income = 0, resid_sd,
                  trait, source) {
    data.frame(outcome = outcome, base = base, party_Republican = rep,
               party_Democrat = dem, party_Independent = 0, party_Other = oth,
               educ = educ, age = age, female = female, nonwhite = nonwhite,
               income = income, resid_sd = resid_sd, trait = trait,
               source = source, stringsAsFactors = FALSE)
  }

  ## --- trust in climate scientists ---------------------------------------
  ## Pew (Oct 2025 fieldwork, published Jan 2026): 77% of US adults have at
  ## least a fair amount of confidence in scientists to act in the public's
  ## best interests; 90% of Democrats against 65% of Republicans. That is a
  ## categorical item, so its translation to a 0-100 slider is an assumption —
  ## we place the population mean near 60 and set the Democrat-Republican gap
  ## at ~26 points, which is what the confidence split implies under a normal
  ## latent-trust model. Climate scientists specifically are somewhat more
  ## polarised than "scientists" in general, so the gap is widened slightly for
  ## the climate-specific items and narrowed for the institutional battery.
  bind <- rbind(

    row("trust_multidimensional", base = 61, rep = -13, dem = 12, oth = -4,
        educ = 3.0, age = -0.5, female = 1.0, nonwhite = 0.5, income = 0.3,
        resid_sd = 19, trait = "sci_trust",
        source = "Pew Jan 2026 trust in scientists; Hornsey 2016 ordering"),

    row("trust_post", base = 59, rep = -15, dem = 13, oth = -5,
        educ = 3.0, age = -0.5, female = 1.0, nonwhite = 0.5, income = 0.3,
        resid_sd = 22, trait = "sci_trust",
        source = "as trust_multidimensional; single item, wider spread"),

    ## Distrust is not 100 minus trust: respondents endorse both to a degree,
    ## and the two items correlate strongly but not perfectly. Level well below
    ## the trust item, party sign reversed.
    row("distrust_post", base = 33, rep = 14, dem = -12, oth = 4,
        educ = -2.5, age = 0.5, female = -1.0, nonwhite = 0, income = 0,
        resid_sd = 21, trait = "sci_trust",
        source = "mirror of trust_post; ambivalence means it is not 100 - trust"),

    ## Institutional battery: EPA, NASA, NOAA, universities, federal
    ## government. NASA and NOAA are among the least polarised US institutions
    ## and the federal government is distrusted across the board, so the mean
    ## of the five is markedly less party-sensitive than the climate-scientist
    ## items, and its level is dragged down by the federal-government item.
    row("inst_trust_mean", base = 55, rep = -9, dem = 9, oth = -4,
        educ = 2.5, age = 0, female = 0, nonwhite = 0, income = 0,
        resid_sd = 18, trait = "sci_trust",
        source = "Pew institutional confidence; averaged over 5 heterogeneous targets"),

    ## Federal spending on climate research, already in the submission's
    ## direction (higher = wants more spending; the raw slider is reversed and
    ## flipped by clean.R).
    row("funding_perceptions", base = 58, rep = -17, dem = 15, oth = -5,
        educ = 2.0, age = -1.5, female = 1.5, nonwhite = 2.0, income = 0,
        resid_sd = 23, trait = "sci_trust",
        source = "GSS/Pew environmental spending items; party gap larger than for trust"),

    ## --- belief, concern, policy -----------------------------------------
    ## These are the most polarised items in US public opinion. Yale Climate
    ## Change Communication and Pew consistently put the partisan gap on
    ## "happening and human-caused" and on issue importance far above the gap
    ## on trust in scientists. Note the level: US belief is high in aggregate
    ## but well below the 85.7 that Vlasceanu et al. (2024) report as the
    ## 63-country control mean, which is dominated by countries with far less
    ## organised climate scepticism.
    row("belief_post", base = 68, rep = -20, dem = 16, oth = -6,
        educ = 3.0, age = -2.0, female = 2.0, nonwhite = 1.0, income = 0,
        resid_sd = 24, trait = "clim_concern",
        source = "Yale CCC / Pew belief items; Hornsey 2016 for predictor ordering"),

    row("concern_mean", base = 56, rep = -21, dem = 18, oth = -6,
        educ = 2.0, age = -2.5, female = 3.0, nonwhite = 3.0, income = 0,
        resid_sd = 23, trait = "clim_concern",
        source = "Yale CCC worry / seriousness / priority items"),

    row("policy_general", base = 60, rep = -21, dem = 17, oth = -6,
        educ = 2.5, age = -2.0, female = 2.5, nonwhite = 2.5, income = -1.0,
        resid_sd = 24, trait = "clim_concern",
        source = "Yale CCC 'government should do more'"),

    ## The specific-policy battery averages seven items of very different
    ## popularity (clean-water laws are near-consensual, fossil-fuel and
    ## carbon-food taxes are not), which pulls the mean toward the middle and
    ## compresses the party gap relative to the general item.
    row("policy_specific_mean", base = 60, rep = -17, dem = 14, oth = -5,
        educ = 2.0, age = -1.5, female = 3.0, nonwhite = 2.5, income = -1.0,
        resid_sd = 20, trait = "clim_concern",
        source = "averaged over 7 policies of very different popularity"),

    ## Whether scientists should engage with policy makers at all. Much less
    ## polarised than climate policy itself: even respondents who distrust
    ## climate science mostly endorse scientists communicating findings.
    row("policy_role_mean", base = 65, rep = -11, dem = 10, oth = -4,
        educ = 3.0, age = 0, female = 1.5, nonwhite = 1.0, income = 0,
        resid_sd = 19, trait = "clim_concern",
        source = "Pew items on scientists' role in policy debates"),

    ## --- behaviour --------------------------------------------------------
    ## Hornsey et al. (2016) report that belief translates only weakly into
    ## behaviour, so these carry smaller party coefficients than the attitude
    ## items and a lower level: stated intentions on a 0-100 likelihood scale
    ## sit near the middle even among the concerned.
    row("behavior_mean", base = 45, rep = -12, dem = 10, oth = -4,
        educ = 1.0, age = -3.0, female = 3.0, nonwhite = 2.0, income = 1.0,
        resid_sd = 21, trait = "action",
        source = "Hornsey 2016: belief-behaviour link is weak"),

    ## Dictator-style donation out of a $10 bonus. Real distributions are
    ## strongly bimodal at $0 and the full amount; the mean is low.
    row("donation_ams", base = 2.6, rep = -0.9, dem = 0.8, oth = -0.3,
        educ = 0.1, age = -0.1, female = 0.2, nonwhite = 0.1, income = 0.1,
        resid_sd = 2.6, trait = "action",
        source = "dictator-game norms; bimodal, low mean"),

    ## Proportion subscribing to an optional in-survey newsletter. Real opt-in
    ## rates for an offer of this kind are low; expressed on the 0-100 scale
    ## the prompt uses for a probability.
    row("newsletter_signup", base = 12, rep = -6, dem = 6, oth = -2,
        educ = 1.0, age = -1.0, female = 1.0, nonwhite = 0.5, income = 0,
        resid_sd = 10, trait = "action",
        source = "in-survey opt-in rates are typically well under 20%")
  )

  bind
})


## Load user-fitted coefficients if 01b_fit_priors.R has produced them.
## Fitted rows REPLACE the shipped row for the same outcome; anything not
## fitted keeps its literature default, so a partial fit is fine — you can
## estimate the four outcomes your microdata actually measures and leave the
## rest.
load_prior_coefs <- function(path = NULL) {
  tbl <- PRIOR_BASELINE
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    message("[priors] using shipped literature coefficients for all ",
            nrow(tbl), " outcomes")
    return(tbl)
  }
  fit <- utils::read.csv(path, stringsAsFactors = FALSE)
  need <- setdiff(names(tbl), c("trait", "source"))
  miss <- setdiff(need, names(fit))
  if (length(miss)) {
    stop("Fitted coefficient file '", path, "' is missing column(s): ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  unknown <- setdiff(fit$outcome, tbl$outcome)
  if (length(unknown)) {
    stop("Fitted coefficient file names unknown outcome(s): ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  ## Keep trait assignment from the shipped table; it is a modelling choice,
  ## not something a regression on other data can tell you.
  fit$trait <- tbl$trait[match(fit$outcome, tbl$outcome)]
  if (is.null(fit$source)) fit$source <- paste("fitted:", basename(path))

  keep <- tbl[!tbl$outcome %in% fit$outcome, , drop = FALSE]
  out  <- rbind(keep, fit[, names(tbl)])
  out  <- out[match(tbl$outcome, out$outcome), , drop = FALSE]
  message(sprintf("[priors] %d/%d outcomes use fitted coefficients from %s",
                  nrow(fit), nrow(tbl), path))
  out
}


## ---------------------------------------------------------------------------
## predict_baseline() — one anchor per outcome per person.
##
## Returns a list with `mu` (the fitted value, i.e. what a person with these
## demographics answers on average), `anchor` (that person's own expected
## answer, fitted plus their latent residual) and `spread` (how far people who
## share this person's profile AND this person's disposition still scatter).
##
## The distinction between the three matters for what goes in the prompt.
## Handing the model `mu` alone would make every respondent in a demographic
## cell identical. Handing it `anchor` with no spread would make the answer
## deterministic. Handing it both is what lets the model place this person
## while still producing a distribution.
## ---------------------------------------------------------------------------
predict_baseline <- function(profiles, coefs = PRIOR_BASELINE,
                             residual_share = 0.75) {

  stopifnot(residual_share >= 0, residual_share <= 1)

  z <- function(x) {
    s <- stats::sd(x, na.rm = TRUE)
    if (is.na(s) || s == 0) return(rep(0, length(x)))
    (x - mean(x, na.rm = TRUE)) / s
  }

  educ_z <- z(match(profiles$education, TARGET_LEVELS$education))
  inc_z  <- z(match(profiles$income,    TARGET_LEVELS$income))
  age_z  <- z(profiles$age)
  educ_z[is.na(educ_z)] <- 0
  inc_z[is.na(inc_z)]   <- 0
  age_z[is.na(age_z)]   <- 0

  female   <- as.numeric(profiles$gender == "Female")
  nonwhite <- as.numeric(profiles$race != "White / Caucasian")

  n  <- nrow(profiles)
  os <- coefs$outcome
  mu     <- matrix(NA_real_, n, length(os), dimnames = list(NULL, os))
  anchor <- mu
  spread <- mu

  for (j in seq_along(os)) {
    cf <- coefs[j, ]

    party_off <- vapply(profiles$party, function(p) {
      col <- paste0("party_", p)
      if (col %in% names(cf)) as.numeric(cf[[col]]) else 0
    }, numeric(1))

    mu[, j] <- cf$base + party_off +
      cf$educ * educ_z + cf$age * age_z +
      cf$female * female + cf$nonwhite * nonwhite + cf$income * inc_z

    ## The person's own standing, from the latent residual drawn in 01. That
    ## residual is standardised, so multiplying by resid_sd puts it on the
    ## outcome's scale. `residual_share` splits resid_sd between what we
    ## resolve here (differences between people) and what we leave to the model
    ## to resolve (variation in how one person answers a given item).
    e <- profiles[[cf$trait]]
    if (is.null(e)) {
      stop("Profile column '", cf$trait, "' not found. Was 01_build_profiles.R ",
           "run with the same cfg$trait_loadings?", call. = FALSE)
    }
    e <- e / stats::sd(e, na.rm = TRUE)
    e[is.na(e)] <- 0

    ## distrust loads negatively on the trust residual: someone whose
    ## disposition is to trust scientists is, by the same disposition, less
    ## distrusting. Without this the anchor would move both items the same way.
    sign_e <- if (identical(cf$outcome, "distrust_post")) -1 else 1

    between_sd <- cf$resid_sd * sqrt(residual_share)
    within_sd  <- cf$resid_sd * sqrt(1 - residual_share)

    anchor[, j] <- mu[, j] + sign_e * between_sd * e
    spread[, j] <- within_sd
  }

  ## Clamp to each outcome's own range.
  hi <- ifelse(os == "donation_ams", 10, 100)
  for (j in seq_along(os)) {
    anchor[, j] <- pmin(pmax(anchor[, j], 0), hi[j])
    mu[, j]     <- pmin(pmax(mu[, j],     0), hi[j])
  }

  list(mu = mu, anchor = anchor, spread = spread, coefs = coefs)
}


## ===========================================================================
## B. INTERVENTION PRIOR
## ===========================================================================
##
## Vlasceanu et al. (2024, Science Advances 10, eadj5778) ran a head-to-head
## tournament of 11 climate interventions on 59,440 participants in 63
## countries. On the two outcomes that most resemble this benchmark's — belief
## in climate change and climate policy support, both on 0-100 scales — the
## results were:
##
##   * BEST intervention on belief:        +2.3 points (94% CrI 1.6 to 2.9)
##   * BEST intervention on policy support:+2.6 points (2.0 to 3.2)
##   * Several interventions:               indistinguishable from control
##   * Effortful pro-environmental behaviour (a tree-planting task):
##     NO intervention beat control, and several REDUCED it
##   * Effects were largest among the uncertain, subject to ceiling effects
##     among strong believers, and near-null on policy support among sceptics
##     (initial belief < 35%)
##
## That is the single most relevant calibration fact available: the largest
## effect any of eleven professionally designed interventions achieved on a
## 0-100 attitude item was under three points. LLM-simulated treatment effects
## routinely come out several times larger, because a persona that can infer
## what a text is for obligingly moves toward it.
##
## TRANSFER CAVEAT, to be stated plainly in registration.md rather than
## quietly assumed. The megastudy's interventions are psychological framings
## (psychological distance, letter to a future generation, negative emotion);
## this benchmark's are informational texts about climate scientists and their
## work, and its primary outcome is trust in those scientists, which the
## megastudy did not measure. The prior therefore transfers as an
## order-of-magnitude claim — a single short text moves a 0-100 attitude item
## by roughly 0 to 3 points, not 15 — and not as a per-intervention estimate.
## No number below is specific to any of the 16 conditions.

INTERVENTION_PRIOR <- list(

  ## Expected shift in points on a 0-100 scale, by outcome family.
  ## `typical` is the effect an average intervention in this family achieves;
  ## `best` is roughly the ceiling observed in the megastudy.
  shift = list(
    trust     = c(typical = 1.2, best = 3.0),   # nearest analogue: belief
    attitude  = c(typical = 1.0, best = 2.6),   # belief, concern, policy
    behaviour = c(typical = 0.0, best = 1.0)    # megastudy: null or negative
  ),

  outcome_family = c(
    trust_multidimensional = "trust", trust_post = "trust",
    distrust_post = "trust", inst_trust_mean = "trust",
    funding_perceptions = "attitude", belief_post = "attitude",
    concern_mean = "attitude", policy_general = "attitude",
    policy_specific_mean = "attitude", policy_role_mean = "attitude",
    behavior_mean = "behaviour", donation_ams = "behaviour",
    newsletter_signup = "behaviour"
  ),

  ## Moderation by the respondent's own starting point, as a multiplier on the
  ## shift. Read off the heterogeneity analysis: interventions bite hardest on
  ## the uncertain middle, run into the ceiling among strong believers, and do
  ## little for policy support among sceptics.
  moderation = function(baseline_belief_0_100) {
    b <- baseline_belief_0_100
    ifelse(b < 35, 0.5,
    ifelse(b < 65, 1.3,
    ifelse(b < 85, 1.0, 0.5)))
  }
)


## Render the intervention prior as prompt text. Deliberately expressed as a
## range over "texts of this kind" rather than a number for this condition: we
## have no per-condition evidence, and quoting a point estimate we do not have
## would invite the model to hit it.
render_intervention_prior <- function(baseline_belief) {
  m <- INTERVENTION_PRIOR$moderation(baseline_belief)
  band <- if (m >= 1.2) {
    "This person is in the range where such texts have the most room to move someone."
  } else if (m <= 0.6) {
    paste("This person is at one end of the belief scale, where such texts",
          "typically achieve very little - either because they have already",
          "made up their mind against, or because they are already near the",
          "top of the scale.")
  } else {
    "This person is in the range where such texts have a modest effect at most."
  }
  paste(
    "WHAT IS KNOWN ABOUT TEXTS OF THIS KIND",
    paste("In the largest head-to-head test of climate communication to date",
          "(11 interventions, 59,440 participants, 63 countries), the single",
          "most effective intervention moved belief in climate change by 2.3",
          "points and policy support by 2.6 points on a 0-100 scale. Several",
          "interventions did nothing measurable. None increased effortful",
          "pro-environmental behaviour, and some reduced it."),
    band,
    paste("So: most people's answers after reading a text like this are close",
          "to what they would have said anyway. A few are moved a little. Do",
          "not move this person more than the evidence supports."),
    sep = "\n")
}


## ===========================================================================
## Rendering the baseline anchors
## ===========================================================================
## One anchor per outcome would mean 13 numbers, which is a lot of prompt for
## the model to keep straight and invites it to treat them as targets to hit
## item by item. We render one anchor per QUESTION BLOCK instead: the block's
## expected average and the spread around it. The model then distributes
## across the items inside the block, which is the part it is actually good at.

## Which prior outcome anchors which block of items (see lib/items.R).
BLOCK_ANCHOR <- c(
  trust           = "trust_multidimensional",
  trust_single    = "trust_post",
  funding         = "funding_perceptions",
  inst_trust      = "inst_trust_mean",
  policy_role     = "policy_role_mean",
  belief          = "belief_post",
  concern         = "concern_mean",
  behavior        = "behavior_mean",
  policy_general  = "policy_general",
  policy_specific = "policy_specific_mean",
  donation        = "donation_ams",
  newsletter      = "newsletter_signup"
)

ANCHOR_LABEL <- c(
  trust_multidimensional = "how competent, honest, caring and open they think climate scientists are (average of the 12 items)",
  trust_post             = "how much they say they trust climate scientists",
  funding_perceptions    = "how much federal funding for climate research they think there should be (higher = more)",
  inst_trust_mean        = "how much they trust EPA, NASA, NOAA, universities and the federal government (average)",
  policy_role_mean       = "how much they think scientists should engage with policy makers (average)",
  belief_post            = "how accurate they think 'human activities are causing climate change' is",
  concern_mean           = "how concerned they are about climate change (average)",
  behavior_mean          = "how likely they are to take pro-environmental actions (average)",
  policy_general         = "how much they support the government doing more",
  policy_specific_mean   = "how much they support seven specific climate policies (average)",
  donation_ams           = "how many of their $10 bonus dollars they donate",
  newsletter_signup      = "their percentage chance of subscribing to the newsletter"
)

## `blocks` is the respondent's block order; only blocks with an anchor appear.
render_anchors <- function(anchor_row, spread_row, blocks) {
  lines <- character(0)
  for (b in blocks) {
    o <- BLOCK_ANCHOR[[b]]
    if (is.null(o) || is.na(o)) next
    a <- anchor_row[[o]]
    s <- spread_row[[o]]
    if (is.na(a)) next
    unit <- if (identical(o, "donation_ams")) "$" else ""
    lines <- c(lines, sprintf("- %s: about %s%s (people like them scatter roughly +/- %s%s around this)",
                              ANCHOR_LABEL[[o]], unit, round(a, if (unit == "$") 1 else 0),
                              unit, round(s, if (unit == "$") 1 else 0)))
  }
  if (!length(lines)) return("")
  paste0(
    "WHAT A STATISTICAL MODEL PREDICTS FOR THIS PERSON\n",
    "These are estimates from regression models of US survey data, using this\n",
    "person's party, age, education, income, gender and race, plus how they\n",
    "differ from others with the same profile. They are the starting point,\n",
    "not the answer: they say where someone like this typically lands, and how\n",
    "widely such people actually scatter. Stay in that neighbourhood unless the\n",
    "specific question gives you a reason not to.\n\n",
    paste(lines, collapse = "\n"))
}


## ---------------------------------------------------------------------------
## Sanity checks on the prior table itself.
## ---------------------------------------------------------------------------
validate_priors <- function(coefs = PRIOR_BASELINE, spec = sst) {

  miss <- setdiff(spec$outcomes, coefs$outcome)
  if (length(miss)) {
    stop("No baseline prior for outcome(s): ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  extra <- setdiff(coefs$outcome, spec$outcomes)
  if (length(extra)) {
    warning("Prior table has outcome(s) the benchmark does not score: ",
            paste(extra, collapse = ", "))
  }

  ## The Democrat-Republican gap is the coefficient most likely to be wrong in
  ## the direction that matters. Anything beyond 45 points on a 0-100 item is
  ## larger than any documented US partisan gap on these questions and would
  ## reproduce, in the prior, exactly the caricature the prior exists to
  ## prevent.
  gap <- coefs$party_Democrat - coefs$party_Republican
  scale100 <- coefs$outcome != "donation_ams"
  big <- coefs$outcome[scale100 & gap > 45]
  if (length(big)) {
    warning("Implausibly large Democrat-Republican gap (>45 points) for: ",
            paste(big, collapse = ", "))
  }

  ## Distrust must move against trust, or the anchors contradict each other.
  tr <- coefs[coefs$outcome == "trust_post", ]
  di <- coefs[coefs$outcome == "distrust_post", ]
  if (nrow(tr) && nrow(di) &&
      sign(tr$party_Republican) == sign(di$party_Republican)) {
    warning("trust_post and distrust_post have the same-signed party ",
            "coefficient; one of them is miscoded.")
  }

  if (any(coefs$resid_sd <= 0)) stop("Non-positive resid_sd.", call. = FALSE)

  message(sprintf("[OK] priors: %d outcomes, mean D-R gap %.1f points",
                  nrow(coefs), mean(gap[scale100])))
  invisible(TRUE)
}
