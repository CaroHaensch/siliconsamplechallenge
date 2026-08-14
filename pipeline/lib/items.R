## ---------------------------------------------------------------------------
## items.R — the survey item registry used to build prompts and to parse
## structured model output.
##
## One row per item that we actually elicit. Fields:
##
##   q        Qualtrics variable name. This is the field name in the structured
##            output schema AND the column name in the raw export, so the whole
##            pipeline speaks one vocabulary end to end (codebook.csv →
##            qualtrics_label). Never rename these.
##   target   codebook.csv → target_label, i.e. the name the cleaned submission
##            file carries. Kept here only so 03_export.R can assert the
##            crosswalk it relies on is the one the benchmark documents.
##   block    presentation block. Post-treatment blocks are shown to human
##            respondents in randomized order (the primary trust block always
##            first); we reproduce that randomization per respondent.
##   text     item wording, verbatim from survey/questionnaire.txt.
##   low/high anchor labels; `mid` where the survey labels the midpoint.
##   type     "slider" (integer 0–100), "dollar" (integer 0–10),
##            "binary" (yes/no).
##   valence  +1 if a higher number is the more pro-climate-science answer,
##            −1 if reversed (distrust, and funding_5 before clean.R flips it).
##            Descriptive only: nothing in the pipeline branches on it. It is
##            kept because it is the fastest way to check, when reading a
##            diagnostic table, whether a reverse-keyed item is behaving —
##            distrust should move against trust, and if it does not, the
##            problem is in the prompt or the priors, not in the sampling.
##
## The wordings below are transcribed from survey/questionnaire.txt.
## `validate_items()` re-checks the q → target crosswalk against codebook.csv
## at run time, so a transcription slip in a *name* fails loudly; a slip in the
## *wording* it cannot catch — diff against questionnaire.txt if you edit.
## ---------------------------------------------------------------------------

it <- function(q, target, block, text, low, high, mid = NA_character_,
               type = "slider", valence = 1L) {
  data.frame(q = q, target = target, block = block, text = text,
             low = low, high = high, mid = mid, type = type,
             valence = as.integer(valence), stringsAsFactors = FALSE)
}


## --- pre-treatment (stage 1) -----------------------------------------------
## Not scored. Elicited anyway because a persona that has already committed to
## a position on climate change and on scientists answers the post-treatment
## block far more coherently than one meeting the topic for the first time,
## and because the pre/post pair is the only within-person anchor we have.
PRE_ITEMS <- rbind(
  it("belief_pre", NA, "pre",
     'How accurate do you think this statement is? "Human activities are causing climate change."',
     "Not at all accurate", "Extremely accurate"),
  it("trust_pre", NA, "pre",
     "How much do you trust climate scientists?",
     "Not at all", "Very strongly")
)


## --- post-treatment (stage 2) ----------------------------------------------
POST_ITEMS <- rbind(

  ## PRIMARY OUTCOME — multidimensional trust. Always shown first, as in the
  ## human instrument.
  it("trust_competent_1", "trust_competence_1", "trust",
     "How incompetent or competent are most climate scientists?",
     "Very incompetent", "Very competent"),
  it("trust_intelligent_1", "trust_competence_2", "trust",
     "How unintelligent or intelligent are most climate scientists?",
     "Very unintelligent", "Very intelligent"),
  it("trust_qualified_1", "trust_competence_3", "trust",
     "How unqualified or qualified are most climate scientists?",
     "Very unqualified", "Very qualified"),
  it("trust_honest_1", "trust_integrity_1", "trust",
     "How dishonest or honest are most climate scientists?",
     "Very dishonest", "Very honest"),
  it("trust_ethical_1", "trust_integrity_2", "trust",
     "How unethical or ethical are most climate scientists?",
     "Very unethical", "Very ethical"),
  it("trust_sincere_1", "trust_integrity_3", "trust",
     "How insincere or sincere are most climate scientists?",
     "Very insincere", "Very sincere"),
  it("trust_concerned_1", "trust_benevolence_1", "trust",
     "How unconcerned or concerned are most climate scientists about people's wellbeing?",
     "Very unconcerned", "Very concerned"),
  it("trust_improve_1", "trust_benevolence_2", "trust",
     "How uneager or eager are most climate scientists to improve others' lives?",
     "Very uneager", "Very eager"),
  it("trust_considerate_1", "trust_benevolence_3", "trust",
     "How inconsiderate or considerate are most climate scientists of others' interests?",
     "Very inconsiderate", "Very considerate"),
  it("trust_feedback_1", "trust_openness_1", "trust",
     "How open, if at all, are most climate scientists to feedback?",
     "Not open at all", "Very open"),
  it("trust_transparent_1", "trust_openness_2", "trust",
     "How unwilling or willing are most climate scientists to be transparent?",
     "Very unwilling", "Very willing"),
  it("trust_attention_1", "trust_openness_3", "trust",
     "How much or how little attention do climate scientists pay to other people's views?",
     "Very little attention", "A great deal of attention"),

  ## SECONDARY — federal research funding.
  ## Reverse-keyed by construction: the slider runs from "far too little" (0)
  ## to "far too much" (100), and cleaning flips it (funding_perceptions =
  ## 100 − funding_5). We elicit the RAW direction, exactly as a respondent
  ## sees it, and let make clean do the flip. Hence valence = −1.
  it("funding_5", "funding_perceptions", "funding",
     paste("Do you think the federal government is spending too much, too little",
           "or about the right amount of money on climate change research?"),
     "Far too little", "Far too much", mid = "About the right amount",
     valence = -1L),

  ## SECONDARY — institutional trust.
  it("inst_trust_epa_1", "inst_trust_epa", "inst_trust",
     "Environmental Protection Agency (EPA)", "Not at all", "Very strongly"),
  it("inst_trust_nasa_1", "inst_trust_nasa", "inst_trust",
     "National Aeronautics and Space Administration (NASA)", "Not at all", "Very strongly"),
  it("inst_trust_noaa_1", "inst_trust_noaa", "inst_trust",
     "National Oceanic and Atmospheric Administration (NOAA)", "Not at all", "Very strongly"),
  it("inst_trust_uni_1", "inst_trust_universities", "inst_trust",
     "Universities and colleges", "Not at all", "Very strongly"),
  it("inst_trust_gov_1", "inst_trust_federal_gov", "inst_trust",
     "Federal government", "Not at all", "Very strongly"),

  ## SECONDARY — scientists' role in policy making.
  it("policy_1_1", "policy_role_1", "policy_role",
     paste("Climate scientists should work closely with policy makers to",
           "integrate scientific results into policy-making."),
     "Strongly disagree", "Strongly agree"),
  it("policy_2_1", "policy_role_2", "policy_role",
     "Climate scientists should actively advocate for specific policies.",
     "Strongly disagree", "Strongly agree"),
  it("policy_3_1", "policy_role_3", "policy_role",
     "Climate scientists should communicate their findings to policy makers.",
     "Strongly disagree", "Strongly agree"),
  it("policy_4_1", "policy_role_4", "policy_role",
     "Climate scientists should be more involved in the policy-making process.",
     "Strongly disagree", "Strongly agree"),

  ## SECONDARY — single-item trust / distrust.
  ## distrust is reverse-valenced: same underlying attitude, opposite sign.
  it("trust_post_1", "trust_post", "trust_single",
     "How much do you trust climate scientists?", "Not at all", "Very strongly"),
  it("distrust_1", "distrust_post", "trust_single",
     "How much do you distrust climate scientists?", "Not at all", "Very strongly",
     valence = -1L),

  ## SECONDARY — behavioural: donation and newsletter signup.
  it("donation", "donation_ams", "donation",
     paste("Of the $10 bonus, how much would you like to donate to the",
           "American Meteorological Society (AMS)?"),
     "$0", "$10", type = "dollar"),
  it("newsletter", "newsletter_signup", "newsletter",
     'Did you subscribe to the "Talking Climate" newsletter on the previous page?',
     "No", "Yes", type = "binary"),

  ## TERTIARY — belief, concern, behaviour, policy support.
  it("belief_post_1", "belief_post", "belief",
     'How accurate do you think this statement is? "Human activities are causing climate change."',
     "Not at all accurate", "Extremely accurate"),

  it("concern_1_1", "concern_1", "concern",
     "How concerned are you about climate change?", "Not at all", "Extremely"),
  it("concern_2_1", "concern_2", "concern",
     "How serious a problem is climate change?", "Not at all", "Extremely"),
  it("concern_3_1", "concern_3", "concern",
     "Relative to other issues facing the U.S., how important is climate change?",
     "The least important issue", "The most important issue"),

  it("individual_meat_1", "behavior_meat", "behavior",
     "Eat less meat", "Not likely at all", "Extremely likely"),
  it("individual_transport_1", "behavior_transport", "behavior",
     paste("Walk, bicycle, carpool, or take public transportation more often",
           "instead of driving by yourself"),
     "Not likely at all", "Extremely likely"),
  it("individual_solar_1", "behavior_solar", "behavior",
     "Install a solar panel", "Not likely at all", "Extremely likely"),
  it("individual_fly_1", "behavior_fly", "behavior",
     "Go on less personal (non-business) air travel", "Not likely at all", "Extremely likely"),
  it("individual_talk_1", "behavior_talk", "behavior",
     "Talk to friends and family about the importance of climate change",
     "Not likely at all", "Extremely likely"),
  it("individual_donate_1", "behavior_donate", "behavior",
     "Donate to an environmental NGO", "Not likely at all", "Extremely likely"),

  it("policy_general_1", "policy_general", "policy_general",
     paste('How much do you oppose or support the following statement?',
           '"The U.S. government should do more to reduce global warming"'),
     "Strongly oppose", "Strongly support"),

  it("policy_specific_1_1", "policy_specific_1", "policy_specific",
     "Raising taxes on fossil fuels (e.g., gas, oil, coal)", "Strongly oppose", "Strongly support"),
  it("policy_specific_2_1", "policy_specific_2", "policy_specific",
     "Expanding infrastructure for public transportation", "Strongly oppose", "Strongly support"),
  it("policy_specific_3_1", "policy_specific_3", "policy_specific",
     "Increasing the use of sustainable energy such as wind and solar energy",
     "Strongly oppose", "Strongly support"),
  it("policy_specific_4_1", "policy_specific_4", "policy_specific",
     "Protecting forested and land areas", "Strongly oppose", "Strongly support"),
  it("policy_specific_5_1", "policy_specific_5", "policy_specific",
     "Increasing taxes on carbon-intensive foods (e.g., beef and dairy products)",
     "Strongly oppose", "Strongly support"),
  it("policy_specific_6_1", "policy_specific_6", "policy_specific",
     "Investing more in green jobs and businesses", "Strongly oppose", "Strongly support"),
  it("policy_specific_7_1", "policy_specific_7", "policy_specific",
     "Introducing laws to keep waterways and oceans clean", "Strongly oppose", "Strongly support")
)


## Block-level intros, shown verbatim above the items of that block, as in the
## instrument. The primary trust block is always presented first; the rest are
## randomized per respondent (see block_order()).
BLOCK_INTRO <- c(
  pre            = "",
  trust          = "Please answer the following questions on how you perceive climate scientists.",
  funding        = "",
  inst_trust     = "How much do you trust the following institutions?",
  policy_role    = "To what extent do you agree or disagree with the following statements?",
  trust_single   = "",
  donation       = paste(
    "As a thank you, you have been given a $10 bonus. You may keep all of it,",
    "or donate some of it to the American Meteorological Society (AMS), a",
    "scientific society that supports research and education in weather,",
    "water and climate. Choices are in $1 increments from $0 to $10."),
  newsletter     = paste(
    "OFFER PAGE (shown to you immediately before the question below):",
    "",
    "  Learn more about climate science",
    "",
    "  If you'd like to learn more about climate science and solutions, you can",
    "  subscribe to the newsletter by climate scientist Katharine Hayhoe. Her",
    '  newsletter "Talking Climate" provides short, accessible updates on climate',
    "  science and climate solutions for a general audience.",
    "",
    "  Signing up takes less than a minute. Please select the free subscription",
    "  option — there is no need to choose a paid version.",
    "",
    "  The link below will open the newsletter in a new tab. You can switch back",
    "  to the current tab and continue the survey right away.",
    "",
    "  [ Open Talking Climate newsletter (opens in a new tab) ]",
    "",
    "  Note: Subscribing to this newsletter is optional.",
    sep = "\n"),
  belief         = "",
  concern        = "Please indicate your views on the following questions.",
  behavior       = "How likely are you to engage in the following activities in the next twelve months?",
  policy_general = "",
  policy_specific = "How much do you support or oppose the following policies?"
)

## The primary outcome block is fixed first; the others are randomized, exactly
## as the human instrument does it. Order effects are real and, left fixed,
## become a constant unmodelled bias in every cell mean.
FIXED_FIRST_BLOCK <- "trust"

block_order <- function(seed_int) {
  rest <- setdiff(unique(POST_ITEMS$block), FIXED_FIRST_BLOCK)
  ## Local RNG stream so block order does not consume draws from, and thereby
  ## shift, the pool-level stream in 02_simulate.R.
  old <- if (exists(".Random.seed", .GlobalEnv)) get(".Random.seed", .GlobalEnv) else NULL
  set.seed(seed_int)
  out <- c(FIXED_FIRST_BLOCK, sample(rest))
  if (!is.null(old)) assign(".Random.seed", old, .GlobalEnv)
  out
}


## --- rendering --------------------------------------------------------------

## One line per item, as the respondent would read it. The qualtrics name is
## shown because it is the key the model must use in its structured answer;
## keeping the key visible next to the wording is what keeps a 40-field object
## aligned with the right questions.
render_item <- function(row) {
  anchors <- if (row$type == "dollar") {
    "whole dollars, $0 to $10"
  } else if (row$type == "binary") {
    "probability you subscribed, 0-100"
  } else if (!is.na(row$mid)) {
    sprintf("0 = %s, 50 = %s, 100 = %s", row$low, row$mid, row$high)
  } else {
    sprintf("0 = %s, 100 = %s", row$low, row$high)
  }
  sprintf("- [%s] %s (%s)", row$q, row$text, ascii_dashes(anchors))
}

## Guard against a stray non-ASCII dash sneaking into anchor text and breaking
## the JSON schema description on some providers.
ascii_dashes <- function(x) gsub("–|—", "-", x)

render_block <- function(items, block) {
  rows  <- items[items$block == block, , drop = FALSE]
  intro <- BLOCK_INTRO[[block]]
  lines <- vapply(seq_len(nrow(rows)), function(i) render_item(rows[i, ]), character(1))
  paste0(if (nzchar(intro)) paste0(intro, "\n") else "", paste(lines, collapse = "\n"))
}

render_questionnaire <- function(items, blocks) {
  paste(vapply(blocks, function(b) render_block(items, b), character(1)),
        collapse = "\n\n")
}


## --- validation -------------------------------------------------------------

## Assert that every scored item we elicit exists in codebook.csv under the same
## qualtrics_label → target_label mapping, and that between them the items cover
## every constructed variable the Tier-1 schema requires. A silent mismatch here
## would surface only as a failed `make check` after a full simulation spend.
validate_items <- function(codebook_path = "codebook.csv") {
  cb <- utils::read.csv(codebook_path, stringsAsFactors = FALSE)
  cb <- cb[!is.na(cb$qualtrics_label) & nzchar(cb$qualtrics_label) &
             cb$qualtrics_label != "NA", ]

  scored <- POST_ITEMS[!is.na(POST_ITEMS$target), ]

  missing <- setdiff(scored$q, cb$qualtrics_label)
  if (length(missing)) {
    stop("Items not found in ", codebook_path, ": ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  map <- stats::setNames(cb$target_label, cb$qualtrics_label)
  bad <- scored[map[scored$q] != scored$target, , drop = FALSE]
  if (nrow(bad)) {
    stop("q -> target mismatch against ", codebook_path, ":\n",
         paste(sprintf("  %s: items.R says '%s', codebook says '%s'",
                       bad$q, bad$target, map[bad$q]), collapse = "\n"),
         call. = FALSE)
  }

  ## Every measured item in the codebook that is not a demographic must be
  ## elicited, or a constructed composite will come out NA.
  demog <- c("gender", "year_birth", "race", "education", "income", "party")
  need  <- setdiff(cb$qualtrics_label[cb$section == "A. Measured items"], demog)
  gap   <- setdiff(need, scored$q)
  if (length(gap)) {
    stop("codebook items we never elicit (composites would be NA): ",
         paste(gap, collapse = ", "), call. = FALSE)
  }

  message(sprintf("[OK] items.R: %d scored items match codebook.csv", nrow(scored)))
  invisible(TRUE)
}
