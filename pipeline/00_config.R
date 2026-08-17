## ---------------------------------------------------------------------------
## 00_config.R — every knob of the simulation pipeline in one place.
##
## Sourced by 01_build_profiles.R and 02_simulate.R. Nothing else is
## configurable; if you change behaviour, change it here so that the
## registration form (registration.md) can be filled from this file alone.
## ---------------------------------------------------------------------------

cfg <- list(

  ## --- reproducibility ----------------------------------------------------
  seed = 20260831L,

  ## --- source of demographic profiles (registration D.1) ------------------
  ## Path to an ANES data file you downloaded yourself (electionstudies.org
  ## requires a free account; nothing is fetched automatically).
  ##
  ## source_type:
  ##   "anes_cumulative" — ANES Time Series Cumulative Data File (VCF* names).
  ##                       Stable, well documented, but coarse on race,
  ##                       education and income (see lib/anes_recode.R).
  ##   "anes_2020"       — ANES 2020 Time Series (V20* names). Finer on all
  ##                       three, and closer in time to the target study.
  anes_path   = "data/anes_timeseries_cdf_csv_20260205.csv",
  source_type = "anes_cumulative",

  ## Restrict the donor pool to recent waves. Older respondents carry
  ## outdated joint structure (e.g. the party-education gradient has flipped
  ## sign among white voters since ~2012).
  min_year = 2016L,

  ## Draw donor rows with probability proportional to the ANES survey weight
  ## so the synthetic pool matches the US adult population, not the ANES
  ## sample design.
  use_weights = TRUE,

  ## --- sample size (README: >= 500 per intervention, >= 1000 control) -----
  ## The floor is a *precision* requirement, not a scoring input. Going above
  ## it buys stability, not score.
  ##
  ## 550/1100 is the floor plus 10%. The headroom is not decoration: rows with
  ## malformed generations get dropped, and at exactly 500/1000 a single dropped
  ## row per cell puts the submission under the floor and makes it invalid.
  ## 10% covers the failure rates seen in the pilot; if yours are higher, raise
  ## this rather than patching the shortfall afterwards.
  ##
  ## Cost scales linearly in n: 9,900 respondents is ~73% of the 13,500 this
  ## was set to before. Check cfg$use_batch too — that halves the bill again.
  n_per_intervention = 550L,
  n_control          = 1100L,

  ## --- latent-trait layer (see pipeline/README.md, "Why latent traits") ---
  ## Three person-level traits are drawn *before* the LLM is called and are
  ## verbalised into the persona. They are what makes the 13 outcomes
  ## co-vary within a respondent; without them, item-by-item elicitation
  ## produces outcomes that are far less correlated than in real survey data.
  ##
  ## Loadings are on a standardised (mean 0, sd 1) scale and encode direction
  ## and rough magnitude only. They are PRIOR BELIEFS, set from published
  ## climate-opinion research, not fitted to any data from the target study.
  ## Document them in registration.md item D.2 / H.2.
  trait_loadings = list(
    ## general trust in scientists as institutions
    sci_trust = c(
      party_rep = -0.55, party_ind = -0.20, party_oth = -0.15,
      educ_z    =  0.25, age_z     = -0.05, income_z  =  0.05,
      female    =  0.05, nonwhite  =  0.05
    ),
    ## climate concern / issue salience
    clim_concern = c(
      party_rep = -0.60, party_ind = -0.22, party_oth = -0.15,
      educ_z    =  0.15, age_z     = -0.15, income_z  =  0.00,
      female    =  0.12, nonwhite  =  0.10
    ),
    ## willingness to act personally (donate, sign up, change behaviour)
    action = c(
      party_rep = -0.35, party_ind = -0.12, party_oth = -0.10,
      educ_z    =  0.15, age_z     = -0.20, income_z  =  0.12,
      female    =  0.10, nonwhite  =  0.05
    )
  ),

  ## How much of each trait's variance demographics should explain.
  ##
  ## This is the single most consequential number in the pipeline, so it is
  ## set as a TARGET and the residual sd is solved for it, rather than being
  ## a hand-tuned sd whose implied R2 nobody checks. In US climate-opinion
  ## data, demographics (party above all) explain roughly 20-35% of the
  ## variance in trust and concern items.
  ##
  ## Too high and subgroups separate more than real subgroups do — the
  ## caricature failure that makes LLM-simulated party gaps far exceed the
  ## measured ones. Too low and the demographic gradients the Tier-2
  ## moderator file is scored on wash out entirely. 0.28 sits mid-range.
  trait_r2_target = 0.28,

  ## Correlation among the three traits *after* conditioning on demographics.
  ## Real data show substantial shared variance beyond demographics.
  trait_resid_cor = 0.45,

  ## --- response style (drawn per person, verbalised into the persona) ----
  ## Human 0-100 slider data is not smooth: respondents pile on 0, 50 and 100
  ## and round to multiples of 5 or 10. LLMs left to themselves produce
  ## suspiciously fine-grained, midpoint-avoiding answers. Assigning each
  ## persona a rounding granularity and an extremity tendency reproduces the
  ## observed lumpiness of the human marginal distributions.
  style_probs = list(
    rounding  = c(`1` = 0.15, `5` = 0.45, `10` = 0.35, `25` = 0.05),
    extremity = c(moderate = 0.45, average = 0.35, extreme = 0.20)
  ),

  ## --- LLM (registration B) ----------------------------------------------
  ## provider/model are passed to ellmer::chat(). Use the fully versioned
  ## identifier so B.1 is reproducible.
  #provider    = "anthropic",
  #model       = "claude-sonnet-5",
  provider = "openai",
  model    = "gpt-5-mini",
  temperature = 1.0,

  ## Number of semantically equivalent prompt variants. Roughly half the
  ## variance in persona-panel estimates sits *between* prompts, so a single
  ## prompt makes your cell means a draw from an unmeasured distribution.
  ## Personas are assigned round-robin across variants.
  n_prompt_variants = 3L,

  ## parallel_chat_structured() throughput. Lower max_active if you hit
  ## output-tokens-per-minute limits.
  max_active = 8L,
  rpm        = 400L,

  ## Use batch_chat_structured() instead of parallel_chat_structured():
  ## ~50% cheaper, up to 24h latency. Recommended for the full run.
  use_batch = TRUE,

  ## --- elicitation (registration E.3) ------------------------------------
  ## "point"        — the model returns one integer per item.
  ## "distribution" — the model returns a small probability distribution over
  ##                  scale anchors per item and we SAMPLE from it. Costs
  ##                  more output tokens but is the single most effective
  ##                  fix for within-cell variance collapse, because taking
  ##                  the modal answer is variance-destroying by construction.
  elicitation = "distribution",

  ## Each item is then drawn independently from its own reported distribution.
  ## The draw resolves the model's uncertainty about that item and nothing
  ## more: where the respondent sits on the underlying attitude is set by the
  ## regression anchors below, before any call is made.

  ## --- classical model layer (registration D.2) ---------------------------
  ## Write regression predictions into the prompt: for each question block,
  ## what a linear model of US survey data expects this person to answer, and
  ## how widely people like them scatter around it. See pipeline/lib/priors.R.
  ##
  ## The reason this exists: an LLM asked to be "a 52-year-old Republican
  ## woman" answers from its internal picture of that category, and that
  ## picture is wrong in two documented directions at once — subgroup means too
  ## far apart, spread within a subgroup too small. Better prompt wording does
  ## not fix it, because the model has no calibrated access to the population
  ## quantity. A regression does, so we supply it.
  ##
  ## FALSE runs the same pipeline without the anchors, falling back to the
  ## latent-trait percentiles. Worth running once as an ablation: the
  ## difference between the two is what the classical models contributed.
  use_model_anchors = TRUE,

  ## State the intervention-effect prior in the stage-2 prompt: how much a
  ## single short text moves a 0-100 attitude item at all (Vlasceanu et al.
  ## 2024: at most ~2-3 points, often nothing).
  ##
  ## This is the ONLY place the size of the treatment effect is constrained.
  ## The pipeline deliberately has no post-hoc shrinkage of the finished
  ## numbers: a correction applied after the fact is a free parameter with
  ## nothing to discipline it, and it makes the submitted effects a function of
  ## a coefficient chosen by us rather than of the simulation. Constraining the
  ## effect where it is generated, with a citable prior, is either right or
  ## wrong for reasons a reader can check.
  state_intervention_prior = TRUE,

  ## Coefficients estimated by 01b_fit_priors.R on public microdata you supply.
  ## Empty or missing = use the literature defaults shipped in priors.R.
  ## Outcomes absent from the file keep their defaults, so a partial fit is fine.
  ##
  ## Path is relative to the repository root, like every other path in this
  ## file. It must match where 01b writes: file.path(dirname(cfg$responses_out),
  ## "prior_coefs_fitted.csv"). A bare filename here resolves to the repo root,
  ## the file is not found, and load_prior_coefs() falls back to the literature
  ## defaults with only a message — i.e. the fit is silently ignored.
  prior_coef_path = "pipeline/out/prior_coefs_fitted.csv",

  ## How much of each outcome's between-person spread is resolved in the anchor
  ## (i.e. how different two people in the same demographic cell are told they
  ## are), versus left for the model to express as within-person uncertainty.
  ##
  ## Too high and every persona gets a near-deterministic target; too low and
  ## the anchors collapse to the cell mean and reintroduce the homogeneity the
  ## anchors exist to prevent. 0.75 leaves a quarter of the residual variance
  ## as answering noise, which is roughly the split between stable individual
  ## differences and occasion-to-occasion variability in attitude measurement.
  anchor_residual_share = 0.75,

  ## --- run mechanics ------------------------------------------------------
  ## Respondents per chunk. Each chunk is written to disk before the next
  ## starts, so --resume can pick up after a crash or a rate-limit wall
  ## without re-spending on completed respondents.
  chunk_size  = 1000L,
  max_retries = 2L,

  ## --- paths --------------------------------------------------------------
  chunks_dir     = "pipeline/out/chunks",
  profiles_out   = "pipeline/out/profiles.csv",
  backstories_out= "pipeline/out/backstories.csv",
  responses_out  = "pipeline/out/responses_raw.csv",
  logs_dir       = "pipeline/out/logs",   # registration K.2: raw model output
  raw_export_out = "raw_data_deposit/simulated_raw_export.csv"
)
