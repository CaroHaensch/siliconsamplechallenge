# Simulation pipeline

R + [ellmer](https://ellmer.tidyverse.org). Lives outside `scripts/`, which the
benchmark ships and tells you not to edit.

```
00_config.R                 every knob, in one place
lib/anes_recode.R           ANES  ->  benchmark moderator levels
lib/states.R                state assignment (the extreme-weather arm needs it)
lib/stimuli.R               parse questionnaire.txt into stimulus texts
lib/items.R                 the 44 scored items, verbatim, + the q -> target crosswalk
lib/priors.R                the classical model layer: baseline + intervention priors
lib/persona.R               profile row -> the text the model answers as
01_build_profiles.R         donor rows -> latent residuals -> conditions
01b_fit_priors.R            (optional) estimate the baseline coefficients yourself
02_simulate.R               backstories, then two calls per respondent
03_export.R                 responses -> Qualtrics-shaped raw export
04_diagnostics.R            is this a plausible survey dataset?
```

```r
install.packages(c("ellmer", "dplyr", "readr", "tibble"))

Rscript pipeline/01_build_profiles.R --dry-run     # inspect, write nothing
Rscript pipeline/01_build_profiles.R

Rscript pipeline/01b_fit_priors.R --spec pipeline/prior_fits.csv   # optional

Rscript pipeline/02_simulate.R --dry-run           # print the prompts, call nothing
Rscript pipeline/02_simulate.R --stage backstories # optional, 1 call/respondent
Rscript pipeline/02_simulate.R --limit 50          # smoke test first
Rscript pipeline/02_simulate.R

Rscript pipeline/03_export.R
Rscript pipeline/04_diagnostics.R
make clean && make check
```

## What this is trying to get right

The benchmark scores cell means and ATEs. The documented failure of the
silicon-sample method is not that LLM personas show too little demographic
structure — it is that they show too much, on top of far too little
within-group variance, and that simulated treatment effects come out several
times larger than the human effects being predicted.

The design answer here is to stop asking the language model for things it has
no calibrated access to, and to hand it those things instead.

**1 · Whole donor rows, not a factorial grid** (`01_build_profiles.R`)
Sampling gender, age, race, education, income and party independently from
their marginals invents cells that barely exist — the 25-year-old Republican
with a doctorate earning under $30k — and destroys every predictor-predictor
association. Drawing complete ANES respondent rows, weighted, keeps the joint
distribution at no cost. Verified: party × race Cramér's V ≈ 0.26 in the
synthetic pool, versus ≈ 0 under independent sampling.

**2 · Regression anchors in the prompt** (`lib/priors.R`, `cfg$use_model_anchors`)
For each question block, the prompt states what a linear model of US survey
data predicts this person will answer, and how widely people like them
scatter around it:

> *how much they say they trust climate scientists: about 47 (people like them
> scatter roughly ± 11 around this)*

An LLM asked to be "a 52-year-old Republican woman" answers from its internal
picture of that category, and that picture is wrong in two directions at once.
No amount of prompt wording fixes it, because the model has no calibrated
access to the population quantity. A regression does.

Coefficients come from Pew (Jan 2026 trust-in-scientists split: 90 % of
Democrats against 65 % of Republicans), Yale Climate Change Communication, and
Hornsey et al. (2016) for the *ordering* of predictors — party roughly twice
the effect size of anything else. Every row carries its source. Run
`01b_fit_priors.R` to replace them with coefficients you estimate yourself on
public microdata; a partial fit is fine.

**3 · An intervention prior, stated where the effect is generated**
(`cfg$state_intervention_prior`)
Vlasceanu et al. (2024), 11 interventions, 59,440 participants, 63 countries:
the *best* intervention moved belief in climate change by 2.3 points and policy
support by 2.6 points on 0-100 scales. Several did nothing. None increased
effortful pro-environmental behaviour. The stage-2 prompt says so, after the
stimulus and before the questions, together with the megastudy's heterogeneity
finding — most room to move in the uncertain middle, ceiling effects among
strong believers.

**There is deliberately no post-hoc shrinkage.** An earlier version rescaled
every intervention's deviation from the control mean. That was removed: a
correction applied to finished numbers is a free parameter with nothing to
discipline it, and it makes the submitted effects a function of a coefficient
we chose rather than of the simulation. Constraining the effect where it is
generated, with a citable prior, is either right or wrong for reasons a reader
can check. `03_export.R` reports the simulated effects and warns if they are
implausibly large, but changes nothing.

**4 · No experiment cues** (`02_simulate.R`)
The persona is never told it is in a study, that the text is an intervention,
that a comparison condition exists, or what the text is meant to do. A
simulated respondent who can infer the hypothesis moves toward it.

**5 · Two stages per respondent**
Stage 1 asks the pre-treatment items with no stimulus in context and gets two
or three sentences in the person's own voice. Stage 2 replays those, shows the
stimulus verbatim, and asks all 44 post-treatment items in one structured
response. The split gives the persona a position to be moved *from*, and keeps
stage 1 uncontaminated so a pre-treatment balance check means something.

**6 · Sampled answers, not modal ones** (`cfg$elicitation`)
Asking for one number returns something near the modal answer and within-cell
SD collapses. The model instead reports a distribution over five fifths of the
scale per item, and each item is drawn independently from its own. The draw
resolves the model's uncertainty about that item and nothing more — where the
respondent sits on the underlying attitude is already fixed by the anchors.
Each persona also carries a rounding granularity, because real slider data
piles up on 0, 50, 100 and multiples of 5 and 10, and model output does not.

**7 · Averaging over prompt variants** (`cfg$n_prompt_variants`)
A large share of the variance in persona-panel estimates sits between prompt
phrasings rather than between personas. With one prompt, every cell mean is a
draw from a distribution you never measured.

## The question this design has to answer

How much did the language model actually contribute?

`02_simulate.R` prints an anchor-adherence table at the end of every run: for
each block, the anchor given, the mean realised, the bias, and the correlation
between them.

- **r ≈ 1.00, bias ≈ 0** — the model transcribed the regression. Submit the
  regression and save the money.
- **r ≈ 0** — the model ignored the anchors. You are running the un-anchored
  version with extra steps.
- **r ≈ .6-.9 with a small bias** — anchored levels, with the model supplying
  deviation where the item or the stimulus warrants it. This is the design
  working.

`cfg$use_model_anchors = FALSE` runs the same pipeline without the anchors, on
the latent-trait percentiles alone. The difference between the two runs is the
contribution of the classical models, measured rather than asserted. Worth
doing once, and worth reporting.

## Before you spend money

- **`--dry-run` on both scripts.** `01` applies the crosswalk, prints the
  marginals and the joint-structure check, and writes nothing. `02` prints a
  complete stage-1 and stage-2 prompt for one respondent in the
  extreme-weather arm — the only condition whose stimulus is assembled rather
  than looked up.
- **`--limit 50`.** Stratified across all 17 conditions. Read a few prompts and
  a few responses end to end before committing to ~18,000 calls.
- **Check the implied control means.** `02` prints what the anchors alone
  predict for the control condition before any call is made. Those numbers are
  a prediction of the human data, arrived at without an LLM. If they look
  wrong, the run will be wrong.
- **`cfg$use_batch = TRUE`** for the production run: roughly half price, up to
  24h latency.

Rough order of magnitude at the configured pool size (1,500 control +
16 × 750 = 13,500 respondents): ~27,000 calls across the two stages, plus
13,500 more if you generate narrative backstories. Each stage-2 call carries a
200-900-word stimulus plus 44 items. Budget from `token_usage()` after the
smoke test rather than from this paragraph, and record the real figures in
`registration.md` item K.3.

## Known weak points

Ranked by how much they would change a score.

1. **The prior coefficients are read off published summaries.** Published gaps
   are marginal, so the "education effect" in a press release is partly a party
   effect wearing a different hat. `01b_fit_priors.R` fixes this by fitting all
   six moderators jointly on microdata — but only for the outcomes your data
   measures, and the mapping of a source item onto the benchmark's 0-100 scale
   is itself an assumption.
2. **The intervention prior transfers by analogy, not by measurement.**
   Vlasceanu et al.'s interventions are psychological framings; these are
   informational texts about climate scientists, and the primary outcome is
   trust in those scientists, which that megastudy did not measure. The prior
   is an order-of-magnitude claim — a short text moves a 0-100 item by 0-3
   points, not 15 — and nothing in it is specific to any of the 16 conditions.
3. **Income in the ANES cumulative file is percentile groups, not dollars,** so
   `splits$income` spreads each group across neighbouring dollar brackets using
   population approximations. This is the largest source of error in the income
   moderator. `cfg$source_type = "anes_2020"` avoids it.
4. **ANES variable names are release-specific.** The crosswalk tables are
   written from published codebooks but must be checked against the codebook
   shipped with your download. `validate_recode_spec()` fails loudly on a
   missing column and reports unmapped codes, so a wrong guess surfaces
   immediately — but it cannot catch a name that exists and means something
   else.
5. **Party leaners are folded into their party** by default, which overstates
   partisanship relative to the survey's 4-way item with an explicit
   Independent option. `fold_leaners = FALSE` in `01_build_profiles.R` maps
   them to Independent instead.
6. **Block randomisation is partial.** The order in which items are *read* is
   randomised per respondent; the order in which they are *answered* is schema
   order, because structured output is generated in schema order and the schema
   is fixed across a variant group. Declare this rather than claiming the
   instrument's randomisation was replicated.
7. **44 structured-output fields per call, each a 5-element array.** Some
   providers cap schema size or degrade on wide objects. If you see malformed
   returns, split the item set across two calls — at the cost of re-sending the
   stimulus.

## What goes in registration.md

| Item | Source |
|---|---|
| D.1 profile source | ANES release, `cfg$min_year`, `cfg$use_weights`, the `splits` tables, the leaner-folding choice |
| D.2 verbalization | `render_backstory()`, the anchor text from `render_anchors()`, and `pipeline/out/prior_coefs_used.csv` for every coefficient and its source |
| D.3 assignment | `cfg$n_per_intervention`, `cfg$n_control`, random condition assignment |
| B.3 configuration | `cfg$provider`, `cfg$model`, `cfg$temperature` |
| C.1 prompts | `SYSTEM_VARIANTS` (all `cfg$n_prompt_variants`), `prompt_stage1()`, `prompt_stage2()` |
| E.1 stimulus | verbatim from `questionnaire.txt`; state-contingent branch via `render_extreme_weather()` |
| E.3 elicitation | `cfg$elicitation`, the five-bin schema, the independent per-item draw, and the partial block randomisation |
| F.1/F.2 stochasticity | `cfg$seed`; one generation per respondent |
| G.2 post-processing | clamping, rounding, discretisation, the missing-value report, **and the anchor-adherence table** |
| G.3 calibration | the intervention prior in `lib/priors.R`, with its source and its transfer caveat. State explicitly that no post-hoc rescaling is applied |
| I.3 blinding | every prior predates and is independent of the target study; nothing is fitted to it |
| K.2 raw logs | `cfg$logs_dir` |
| K.3 resources | `ellmer::token_usage()` |

## Verification status

Written and reviewed without an R interpreter available. Checked mechanically:
bracket balance, cross-file symbol resolution, every `cfg$` reference, the
44-item crosswalk against `codebook.csv`, the export columns against
`clean_lib.R`'s rename map, and all 13 outcomes against `submission_spec.R`.

Not checked: that it runs. Do `--dry-run`, then `--limit 50`, before the full
spend.
