# Silicon Sample Benchmark — method registration form

Fill in every item before the prediction lock; this file ships inside your repo's Zenodo release
(see the README's *Deposit* step). This form covers **one entry** (one repo / one Zenodo release,
`primary` or `secondary-k` — see the README's *What counts as a submission*); if you submit several
entries, fill one form per entry. Items marked **★**
must be disclosed **fully publicly** (never escrowed or withheld). Items marked **†** must be at
minimum escrowed — they may be sealed from the public, but never withheld from the core team. Items
not applicable to your approach: write `N/A`. When several models serve different pipeline stages, complete the model
sections (B) once per model. See the call's *Disclosure policy* for escrow rules.

---

## 0 · Approach identity and output
- **0.1 Team ★** — Team "Munichmetrics" (team_id 20). Anna-Carolina Haensch, LMU Munich, University of Maryland College Park, MCML, Contact: C.Haensch@lmu.de
- **0.2 Plain-language summary ★** — I build a synthetic stand-in for the study's participants and put it through the same survey the real participants took. Each synthetic respondent is a specific person rather than an average one — a particular combination of age, education, income, party, race and gender, drawn so that these characteristics go together the way they do among real Americans, together with a disposition of their own: how much they tend to trust experts, how much they worry about the environment, how much effort they will actually put in. Before any of them answers anything, we work out from decades of existing US survey data what a person like that typically says, and how much people who look alike on paper nonetheless disagree. Each synthetic respondent then reads one of the study's texts, word for word as a participant would see it, and answers all thirteen outcome measures. What we submit is one predicted answer per person per question — 9,900 people, all 17 conditions — from which the study's effects can be computed exactly as they will be from the human data. We have not seen any results from the study, and nothing in our procedure was adjusted to match them.
- **0.3 Submission tier & approach family ★** — tier (1/2/3); family (e.g. per-respondent simulation / agent / direct forecast; single model / ensemble / multi-agent; zero-shot / literature-conditioned):
  **Tier 1.** Per-respondent simulation; single model, no ensemble, no agentic scaffold;
  **literature-conditioned** — both the baseline levels and the expected intervention effect enter
  the prompt as explicit priors from public microdata and published survey research.
  This entry is **`primary`**: GPT-5-mini, template personas, no generated backstories. Further
  Tier-1 entries from this team, each in its own repository and Zenodo deposit, differ in persona
  construction rather than in this pipeline. A GPT-5-nano variant was piloted and **not submitted**
  (see J.1).
- **0.4 Pipeline diagram** — ordered steps from raw inputs to submitted file:
  ```
  ANES cumulative microdata (2016+, weighted)
    → 01_build_profiles.R    donor resampling → 9,900 personas; latent traits;
                             condition assignment; state assignment; prompt-variant assignment
  GSS microdata + published survey research
    → 01b_fit_priors.R       baseline coefficients (3 outcomes fitted, 10 from literature)
    → predict_baseline()     per-person anchor + spread for each of the 13 outcomes
  survey/questionnaire.txt
    → stimuli.R              stimulus text parsed verbatim; extreme-weather branch resolved
    → 02_simulate.R          stage 1 (pre-treatment items, no stimulus)
                             → stage 2 (stimulus verbatim + 44 post-treatment items)
                             → distributions returned → one value sampled per item
    → 03_export.R            response-style rounding, discretisation → Qualtrics-shaped raw export
    → scripts/clean.R        → predictions/<team_id>_T1_<entry>_v1.csv  (+ SHA-256 in metadata.json)
    → 04_diagnostics.R       internal quality checks (not part of the submission)
  ```
- **0.5 Coverage ★** — number of respondents/cells/estimates; mapping to conditions. Full coverage is required: every submission predicts **all 16 interventions and all 13 outcomes** (partial coverage is not accepted). Confirm here:
  **Full coverage confirmed.** 9,900 synthetic respondents across all 17 conditions — 1,100 control
  and 550 in each of the 16 interventions — each answering all 13 scored outcomes. The three control
  filler texts (neckties, baseball, dances) map to the single condition label `control`. No
  condition and no outcome is missing or imputed. Verified after the run: 1,100 control and 549–550
  per intervention usable, one respondent of 9,900 dropped for a single missing cell (see G.2).

## A · Scope of LLM use
- **A.1 Purpose** — every workflow stage where LLMs are used:
  One stage only: generating the simulated respondents' answers (two calls per respondent, see E.2).
  Every other stage is classical and LLM-free — donor resampling from ANES, latent-trait draws,
  the regression anchors, sampling from the returned distributions, the response-style transform,
  export, cleaning and diagnostics. In this entry the optional narrative-backstory stage was **not**
  run, so no LLM contributes to persona construction either.
- **A.2 Degree of automation ★** — confirm fully automated, no human in the loop at prediction time:
  Fully automated. No human inspected, selected, edited or discarded any individual generation at
  prediction time. Humans set the configuration and read aggregate diagnostics between pilot runs
  (see J.1); the submitted run itself is a single unattended batch job.

## B · Model / system details (once per model)
- **B.1 Model name(s)** — exact identifiers incl. provider, size, version/timestamp, source link:
  OpenAI **`gpt-5-mini-2025-08-07`** — the dated snapshot the API itself reported (`batch.model` in
  every Batch result file), not the requested alias `gpt-5-mini`. Size undisclosed by the provider.
  <https://platform.openai.com/docs/models>
- **B.2 Access & context mode** — API/web/local; API name + version; chat vs stateless; exact call dates:
  Public OpenAI API, **Batch API** (24-hour completion window), called from R via the `ellmer`
  package (`ellmer::batch_chat_structured()`), **ellmer 0.4.2**.
  **Stateless** — every request carries its full context; no conversation threads, no server-side
  state between the two calls (see E.2 on how stage 1 is replayed into stage 2).
  Call dates: the submitted run was executed in a single session on **16 August 2026, 13:20–22:48
  CEST**. Pilot runs preceding it: 14 August 2026 (n = 102, Claude Sonnet; n = 51, GPT-5-mini),
  14–15 August 2026 (n = 850, GPT-5-mini), 16 August 2026 (n = 850, GPT-5-nano). See J.1.
- **B.3 Configuration** — temperature, top-p/top-k, max tokens, penalties, stop sequences, seeds, reasoning effort, completions per item:
  Temperature 1.0. All other decoding parameters at provider defaults: top-p/top-k, max tokens,
  penalties and stop sequences are not set by the pipeline, and no provider-side seed is set.
  Reasoning effort is not set explicitly and runs at the provider default; note that reasoning
  tokens dominate output volume for this model family (84% of output tokens in the n = 850 pilot).
  **One completion per call, one call per stage, two stages per respondent** — no repeated sampling
  of the same respondent and no best-of-n selection.
- **B.4 Customization** — fine-tuning, RAG, prompt optimization, tool use, web search, agentic scaffolds (cross-ref H):
  None. No fine-tuning, no retrieval or RAG, no tool use, no web access, no agentic scaffold, no
  automated prompt optimization. Prompts were revised by hand between pilot runs (C.1, J.1).
- **B.5 Persistent memory** — across interactions? what persisted:
  None. Requests are independent; nothing persists on the provider side between them. What carries
  across the two stages is written into the stage-2 prompt as plain text by the pipeline (E.2).
- **B.6 Inference stack** — for local models: serving framework + version, quantization, hardware:
  N/A — hosted API, no local inference.
- **B.7 Ensembles** — members + exact aggregation rule:
  N/A — a single model. The three system-prompt variants are not an ensemble: they are assigned to
  disjoint thirds of the pool and never aggregated within a respondent (F.2).

## C · Prompts
- **C.1 Exact prompts** — verbatim text or link to deposited file; were they iteratively refined? pre-specified vs in response to outputs:
  Prompts are generated programmatically, not stored as fixed text. The generators are
  `pipeline/lib/persona.R` (`SYSTEM_VARIANTS`, `render_persona()`) and `pipeline/02_simulate.R`
  (`prompt_stage1()`, `prompt_stage2()`, `build_backstory_prompt()`), all deposited with the code.
  A fully rendered example for one respondent — system prompt, stage-1 user prompt, stage-2 user
  prompt — is deposited at `pipeline/out/logs/prompts_preview.txt` and can be regenerated for any
  respondent with `Rscript pipeline/02_simulate.R --dry-run`.

  **Iteratively refined, in response to outputs — not pre-specified.** The prompt structure was
  revised after inspecting pilot runs (n = 51 and n = 850), against internal diagnostics only
  (`pipeline/04_diagnostics.R`: cross-outcome correlation structure, within-cell variance, scale
  usage). No revision was made in response to any outcome data from the target study, which we have
  not seen. See J.1.
- **C.2 System-wide instructions**:
  Three semantically equivalent system-prompt variants (`SYSTEM_VARIANTS` in
  `pipeline/lib/persona.R`), assigned to respondents round-robin in `01_build_profiles.R` so that
  each variant carries one third of the pool (3,300 of 9,900). All three instruct the model to
  answer as the described person rather than as itself; to stay inside that person's level of
  information, interests and patience; that real respondents are inconsistent, not well-informed and
  not eager to please; not to soften or balance views to be agreeable; and to return only the
  requested structured output. Variants differ in wording, not in content. Rationale: roughly half
  the variance in persona-panel estimates sits between prompt phrasings rather than between
  personas, so a single phrasing would make each cell mean a draw from an unmeasured distribution.
- **C.3 Prompt-design rationale** — brief rationale for the prompt design: why prompts were structured as they were, and the reasoning behind major design choices (recommended, not required):
  Four choices do the work.
  (i) *Anchoring.* An LLM asked to be a member of a demographic category answers from its internal
  picture of that category, which is documented to be wrong in two directions at once: subgroup
  means too far apart, within-subgroup spread too small. Neither is fixable by prompt wording,
  because the model has no calibrated access to the population quantity. A regression does, so the
  level and the spread are handed to the model explicitly and the model is asked only for the
  deviation.
  (ii) *Latent traits.* Three person-level traits are drawn before generation and verbalised into
  the persona. They are what makes the thirteen outcomes co-vary within a respondent; item-by-item
  elicitation without them produces outcomes far less correlated than real survey data.
  (iii) *Effect-size prior in context.* The stage-2 prompt states what the largest published
  head-to-head test of climate-communication interventions found (Vlasceanu et al. 2024: best
  intervention moved belief 2.3 and policy support 2.6 points on 0–100; several did nothing; none
  increased effortful behaviour). Constraining the effect where it is generated, with a citable
  prior, is verifiable; rescaling the effect afterwards would not be. No treatment effect is
  rescaled anywhere in this pipeline.
  (iv) *Two-stage administration.* Pre-treatment items are elicited before the stimulus is shown, so
  the model cannot plan the session backwards from a target effect.

## D · Persona / profile construction (Tiers 1–2)
- **D.1 Profile source** — source of demographic profiles you constructed: a public survey (e.g. GSS / ANES / Census), other survey, fully synthetic, or none. The benchmark ships no participant pool; report how you built yours, incl. condition assignments:
  ANES Time Series Cumulative Data File (`anes_timeseries_cdf_csv_20260205`), waves from 2016 on,
  complete cases on the six scored moderators, sampled **with survey weights** (`VCF0009z`).
  Profiles are resampled donor rows, not independent draws per variable, so the joint distribution
  of gender, age band, race, education, income and party is the donor file's rather than a product
  of marginals. Crosswalk in `pipeline/lib/anes_recode.R`; two coarseness problems are handled by
  documented stochastic splits (ANES education tops out at "advanced degree" → Master's/Doctorate
  split 0.82/0.18; income is stored as percentile groups → probabilistic mapping to dollar
  brackets).

  Two limits of this donor file, both disclosed rather than patched:
  (a) `party` is recoded from the 7-point party ID (`VCF0301`), which has **no "other party"
  category** — so `party = "Other"` never occurs in the pool, although the submission schema allows
  it. Leaners (codes 3 and 5) are folded into their party (`fold_leaners = TRUE`), which overstates
  partisanship relative to a 4-way self-identification item.
  (b) `gender` is binary in most ANES waves, so `gender = "Other"` is near-absent (9 donors in
  13,500 in an earlier pool build; 0 in the submitted pool).

  Home state is assigned independently of the donor's census region (`assign_states()` in
  `pipeline/lib/states.R`), because ANES region is coarser than the state the extreme-weather arm
  requires. To avoid a persona that contradicts itself, census region is therefore **not** rendered
  into the persona text (see `pipeline/lib/persona.R`).
- **D.2 Profile verbalization** — which variables, rendered how (template vs generated narrative; if generated: model + prompt):
  **Template, no generated narrative in this entry.** (The optional narrative-backstory stage exists
  in the code, `--stage backstories`, but was not run for this entry; it is the subject of a
  separate entry.) Rendered per respondent by `render_persona()`:
  scored moderators (gender, age, race, education, income, party); auxiliary ANES variables used for
  persona detail only and never scored (ideology, religion, religious attendance, marital status,
  employment); a response-style descriptor drawn per persona; and the model-based anchors.

  Anchors are written in words, one line per outcome block, as a predicted value plus a spread
  ("about 76 (people like them scatter roughly +/- 15 around this)"), with a preamble stating that
  these are regression estimates and a starting point rather than the answer. They come from linear
  models of each outcome on all six moderators: **three outcomes** (`trust_multidimensional`,
  `trust_post`, `funding_perceptions`) are fitted on GSS microdata; the remaining **ten** use
  coefficients read off published survey research. Full provenance, including one fit that was
  estimated and then deliberately discarded, is in `notes/prior_fit_decisions.md`; every coefficient
  actually used in the run is written to `pipeline/out/prior_coefs_used.csv`.
- **D.3 Assignment & weighting** — number of personas, assignment to conditions (your responsibility, all 17 conditions), reuse, weighting/matching:
  9,900 personas: 1,100 control and 550 in each of the 16 interventions (`cfg$n_control`,
  `cfg$n_per_intervention`), above the Tier-1 floor of 1,000/500 by 10% so that malformed
  generations can be dropped without falling under it. Condition is assigned by random permutation
  of a fixed condition vector in `01_build_profiles.R`, independently of all demographics; the
  resulting independence is tested in `04_diagnostics.R`. Each persona appears in exactly one
  condition and is used once — no reuse, no matched pairs across conditions. Survey weights enter at
  pool construction (donor sampling), not as post-hoc weights on the output.

## E · Stimulus and survey administration
- **E.1 Stimulus presentation** — verbatim vs paraphrase; how state-contingent content is handled:
  **Verbatim.** Stimulus text is parsed out of `survey/questionnaire.txt` at run time
  (`pipeline/lib/stimuli.R`) rather than retyped, and only authoring scaffolding is stripped: page-break
  markers, source lists and reference blocks, and passages marked "[not displayed to participants]".
  No paraphrase, no truncation, no summarisation. The three control filler texts (neckties,
  baseball, dances) are treated as the single condition `control`.

  The **extreme-weather arm is state-contingent** and is reproduced branch by branch rather than
  concatenated. Each respondent is assigned a US state; the state list in the questionnaire maps it
  to one of three risk cases (flood / wildfire / winter storm); the respondent sees the templated
  intro with `[STATE]` and `[CASE]` filled in, followed by exactly one of the four case texts.
  Respondents with no state reported receive the generic intro and case 4, exactly as the
  questionnaire specifies. Implemented in `render_extreme_weather()`.
- **E.2 Survey walk-through** — one item/call vs blocks vs whole survey; context carry-over; item/option ordering & randomization; scale display; attention/comprehension handling:
  **Two calls per respondent, blocks not single items.** Call 1: the two pre-treatment items
  (`belief_pre`, `trust_pre`) plus a short free-text self-description, with no stimulus present.
  Call 2: the stimulus verbatim, then all 44 post-treatment items in one structured response.
  Rationale: one response per stage lets the model hold a respondent's position fixed across items,
  which is what produces realistic within-person covariation; per-item calls would also multiply
  input cost.

  **Context carry-over is explicit, not conversational.** The two calls are stateless; stage 2
  replays stage 1's sampled numeric answers and self-description as text ("EARLIER IN THIS SURVEY,
  BEFORE READING ANYTHING, THIS PERSON ANSWERED …"), so the exact model input is auditable and the
  run is parallelisable and batchable.

  **Item order** follows the questionnaire's printed order within and across blocks. **Randomization
  is not implemented**: the questionnaire randomises the three consensus-estimation items (with item
  3 always in the middle); all respondents here see the printed order. Scales are presented as text
  with numeric endpoints and the questionnaire's anchor labels (e.g. "0 = Not at all accurate,
  100 = Extremely accurate"); the reverse-keyed funding item is elicited in its **raw** direction
  (0 = far too little … 100 = far too much) and reversed in cleaning, as the codebook specifies.
  No attention or comprehension checks are administered.
- **E.3 Response elicitation** — free text / constrained choice / structured output / token log-probabilities (if logprobs: normalization & mapping):
  **Structured output (JSON schema via ellmer's typed interface), distributional rather than
  point-valued.** For each item the model returns five whole percentages summing to 100, the share
  of people like this respondent whose answer would fall in each fifth of the scale
  ([0-20, 21-40, 41-60, 61-80, 81-100]). One value per item is then **sampled** from that
  distribution: a bin is drawn with the reported probabilities and a value drawn uniformly within
  it. The donation item uses the same five bins over $0–$10; the newsletter item over the
  probability of subscribing. `cfg$elicitation = "distribution"`. No log-probabilities are used.

  Rationale: a point answer conflates the model's uncertainty about the item with the respondent's
  position on it. Asking for the distribution and sampling once separates them, and it is what
  prevents the within-cell variance collapse that point elicitation produces.

## F · Stochasticity and aggregation
- **F.1 Runs & seeds** — runs per respondent/item/estimate; seeds; reproducibility under identical settings:
  **One generation per respondent per stage** — no repeated sampling of the same respondent, no
  best-of-n, no self-consistency voting. Variation across the pool comes from the personas, the
  latent traits, the three prompt variants and the temperature, not from repeating individuals.
  Temperature 1.0; all other decoding parameters at provider defaults (see B.3).
  R-side seeds are fixed and offset per stage (`cfg$seed = 20260831`; `01` uses `seed`, `02` uses
  `seed + 2`) so that the pool, the trait draws, the anchor residuals and the within-bin draws are
  reproducible. **The API side is not deterministic**: at temperature 1.0 with no provider seed, an
  identical re-run reproduces the pool and the prompts exactly but not the model's answers.
- **F.2 Aggregation rule** — how multiple generations become submitted values (mean/median/mode/first/sampled/…):
  **Sampled, not aggregated.** Each item's submitted value is a single draw from the five-bin
  distribution the model returned for that item (see E.3), after which a per-persona response-style
  transform and the instrument's own rounding are applied (see G.2). There is no averaging over
  generations, because there is only one generation per respondent. The three prompt variants are
  not aggregated either: they are assigned to disjoint thirds of the pool, so variant is a source of
  between-respondent variance rather than something averaged away within a respondent.

## G · Validation & post-processing
- **G.1 Human validation** — any human review of outputs (often N/A):
  No human review or editing of individual generations. Aggregate output was inspected by the team
  through `pipeline/04_diagnostics.R` (correlation structure, variance, scale usage, randomisation
  check) and pilot runs were used to revise the pipeline; see J.1. No respondent-level output was
  read, selected, edited or excluded on the basis of its content.
- **G.2 Post-processing** — parsing rules; handling of refusals/malformed/missing/out-of-range; exclusions; for approaches that generate individual responses, the resulting effective N per condition (descriptive disclosure, not a scoring input):
  *Parsing.* Structured output is parsed field by field against the item list. A response counts as
  incomplete if fewer than 90% of the expected fields are present; incomplete responses are
  re-requested up to `cfg$max_retries = 2` times. Failed requests are returned as NULL by the
  provider wrapper rather than aborting the chunk.

  *Sampling and clipping.* Each item value is drawn from the returned distribution and clipped to
  the item's range (0–100, or $0–$10 for donation).

  *Response-style transform.* Each persona is assigned a rounding granularity (1/5/10/25 with
  probabilities .15/.45/.35/.05) and an extremity tendency (moderate/average/extreme, .45/.35/.20)
  before generation. Extremity is applied in `02_simulate.R` as part of how the person answers;
  slider rounding and the discretisation of donation (whole dollars) and newsletter (binary) are
  applied in `03_export.R`, because they are artefacts of the instrument rather than of the person.
  These transforms are fixed a priori and fit to no data — see G.3.

  *Exclusions.* Respondents missing any scored item after retries are dropped in `03_export.R`.

  **Effective N: 1,100 control and 549–550 per intervention, from a generated pool of 9,900.**
  Exactly **one** respondent of 9,900 was dropped — a single missing cell, a drop rate of 0.01% —
  so one intervention cell holds 549 rather than 550. Both figures remain above the Tier-1 precision
  floor (1,000 control / 500 per intervention). No respondent was excluded for any reason other than
  a missing scored item; none was excluded on the basis of the content of its answers.
- **G.3 Calibration corrections** — any post-hoc scaling/shifting/debiasing and exactly what data it was fit on (cross-ref H/I):
  **No post-hoc calibration of any kind.** No treatment effect is rescaled, shifted or debiased
  anywhere in the pipeline, and no parameter is tuned to make the output resemble any expected
  result.

  Two things that are adjacent to calibration and are therefore stated explicitly:
  (i) The baseline anchors (D.2) are a *prior applied before generation*, not a correction applied
  after it. Three sets of coefficients are estimated on GSS microdata and ten are read off published
  survey research; none is fitted to, or tuned against, any data from the target study. Provenance
  per coefficient: `pipeline/out/prior_coefs_used.csv` and `notes/prior_fit_decisions.md`.
  (ii) The response-style transforms in G.2 are fixed a priori from the general survey-methodology
  literature on scale-use heterogeneity; their parameters were not fit to data of any kind.

## H · Learning and conditioning components
- **H.1 Fine-tuning data** — exact corpus (hashes/DOIs), hyperparameters, checkpoints:
  N/A — no fine-tuning. The model is used off the shelf through the public API.
- **H.2 Context & retrieval corpora** — exact document set in context / indexed, archived in the deposit:
  No retrieval, no index, no tool use, no web access at generation time. Everything the model sees
  is assembled locally into the prompt and consists of exactly four things:
  (1) the stimulus text for the respondent's condition, verbatim from `survey/questionnaire.txt`
  (deposited);
  (2) the item wordings and scale anchors, from `pipeline/lib/items.R` (deposited), which mirror the
  questionnaire;
  (3) the persona and the numeric anchors described in D.2, generated from the ANES pool and the
  coefficient table in `pipeline/out/prior_coefs_used.csv` (deposited);
  (4) two sentences of published effect-size evidence used as an intervention prior — the headline
  result of Vlasceanu et al. (2024), *Science Advances* — a global intervention tournament with 11
  expert-crowdsourced interventions, N = 59,440, 63 countries, best effect on belief +2.3 points and
  on policy support +2.6 points. Provenance and the derivation of the prior, including the second
  anchor used for the correlational structure, are in `notes/effect_size_priors.md` (deposited).
  No text from the target study's results, pilots or analyses is in context at any point.

## I · Data inputs, blinding, and competing interests
- **I.1 Competing interests ★** — funding, in-kind compute/model access, relationships with LLM-interested entities:
- **I.2 External human data †** — all external human datasets that informed the approach anywhere (training/fine-tuning/retrieval/ICL/calibration):
  Three, all public and all independent of the target study:
  (1) **ANES Time Series Cumulative Data File** (`anes_timeseries_cdf_csv_20260205`), waves 2016+ —
  the donor pool for the synthetic respondents (D.1). Not redistributed in this deposit: the ANES
  licence permits use, not republication.
  (2) **GSS** (via `gssr::gss_all`), waves 2016+, items `consci` and `natenvir` — baseline
  coefficients for 3 of the 13 outcomes (D.2). Likewise not redistributed.
  (3) **Published aggregate survey research** — Pew (trust in scientists; institutional
  confidence), Yale Climate Change Communication (belief, worry, policy items), Hornsey et al.
  (2016) meta-analysis, Vlasceanu et al. (2024) intervention tournament, and dictator-game norms for
  the donation item. These inform the remaining 10 baseline priors and the intervention prior.
  Per-coefficient provenance: `pipeline/out/prior_coefs_used.csv`, `notes/prior_fit_decisions.md`,
  `notes/effect_size_priors.md`.
  No dataset here contains any outcome measured by the target study.
- **I.3 Blinding attestation ★** — **mandatory.** Signed attestation that no team member accessed, solicited, or was shown any human outcome data from this study, including pilots, before the prediction lock:
  I attest that no member of this team accessed, solicited, or was shown any human outcome data from
  this study, including pilot data, at any point before the prediction lock. Every quantity that
  informed this pipeline comes from the sources listed in I.2, all of which predate and are
  independent of the target study. No parameter was tuned against any target-study result, and no
  output was adjusted to resemble one.
  **[SIGN: name, affiliation, date]**
- **I.4 Contamination note †** — training cutoff of every model vs public release dates of this project's materials; note any known exposure:
  **No contamination is possible from this project's materials, because the model's training cutoff
  precedes their existence by roughly two years.**

  Model: OpenAI `gpt-5-mini-2025-08-07`, the only model behind the submitted predictions. Reported
  knowledge cutoff **31 May 2024** (the GPT-5 family was released 7 August 2025; the flagship
  `gpt-5` carries a cutoff of 30 September 2024, the mini variant an earlier one). Third-party
  trackers rather than a single authoritative provider page are the source for the mini figure, and
  reported dates for hosted models vary between trackers — but every candidate date lies in 2024,
  which is what matters here.

  This project's materials: invited teams received the intervention texts, survey instrument,
  codebook and submission template on **21 July 2026**; the benchmark preregistration and the call
  are public on the project site from around the same period. The Zenodo deposits — including this
  one — are created before the lock on **31 August 2026**. All of this postdates the model's cutoff
  by about two years, so neither the questionnaire, nor the preregistration, nor any team's deposit
  can be in its training data.

  The target study's *results* are in no model's training data under any assumption: the ≈18,000
  human responses were collected by July 2026 and are held sealed by the core team, unpublished,
  until after the lock.

  No team member prompted the model about this study, and no attempt was made to elicit prior
  knowledge of it. The pilot runs used Claude Sonnet and `gpt-5-nano-2025-08-07`; neither contributed
  to the submitted predictions, and the same cutoff argument applies to both.

## J · Internal selection procedure
- **J.1 Design-space search †** — how the final pipeline was chosen: how many configurations tried, internal validation criterion, what data it ran against:
  The pipeline was developed against **internal diagnostics only**, never against target-study data.
  Runs performed before the submitted run:
  (1) n = 102, Claude Sonnet — full pipeline test; revealed a flat cross-outcome correlation
  structure (mean inter-item r in the 13-item trust battery ≈ .12 against .4–.6 in US
  climate-opinion data);
  (2) n = 51 and (3) n = 850, `gpt-5-mini` — the n = 850 run gave the first control group large
  enough (n = 50) for the correlation structure to be estimable.
  Selection criterion: the checks in `pipeline/04_diagnostics.R`, chiefly the control-group
  cross-outcome correlation matrix judged against published US climate-opinion benchmarks (median
  |r| between .25 and .80; trust–distrust strongly negative), plus within-cell variance and scale
  usage. Effect sizes were **not** a selection criterion, and at these pilot sizes were in any case
  smaller than their own standard errors.
  Configuration changes made on the basis of these runs: prompt wording revisions; removal of census
  region from the persona (it contradicted the independently assigned home state); sample size set
  to 550/1,100; batch mode and chunk size for throughput. Model choice across the three entries is
  itself the comparison being submitted, not a selection.
  **This is the complete list.** No further models, prompts or hyperparameter settings were tried
  and discarded beyond those named above: four pilot runs, one submitted run, and the configuration
  changes listed. Temperature was never varied, no prompt was selected from a set of candidates on
  the basis of output quality, and no seed was chosen for its results.

  One configuration was piloted and **rejected**: `gpt-5-nano-2025-08-07` (n = 850, 16 August 2026).
  Rejected on internal diagnostics — trust and distrust correlated −0.05 in its control group,
  against −0.59 for GPT-5-mini and −0.6 to −0.8 in human data, i.e. the model did not distinguish
  the reverse-keyed item from its positively keyed counterpart. It also showed a 2.4% incomplete-response
  rate against 0% for mini, and cost more per respondent (3.7× the output tokens), so nothing
  recommended it. Its logs are retained.

## K · Reproducibility & frozen artifacts
- **K.1 Code & materials** — link/DOI, secrets removed, determinism/seeds documented (also record the link in `metadata.json` → `code_repository` / `code_doi`):
  Code: <https://github.com/CaroHaensch/siliconsamplechallenge> — **[FILL IN the repository and
  Zenodo DOI for THIS entry; each of the three entries has its own]**.
  No credentials in the repository: the provider key is read from the environment
  (`OPENAI_API_KEY`); `.Renviron`, `.env`, `*.key` and `*.pem` are git-ignored.
  Determinism: R-side seeds are fixed and documented (F.1). The API side is not deterministic at
  temperature 1.0 with no provider seed — a re-run reproduces the pool and the prompts exactly, but
  not the model's answers. The ANES and GSS microdata are **not** redistributed (licence); the
  filenames, waves and crosswalk needed to reproduce the pool are in `pipeline/lib/anes_recode.R`
  and `pipeline/prior_fits.csv`.
- **K.2 Raw output logs †** — complete unprocessed model responses archived, hashed, time-stamped (required for Tiers 1–2, public or escrowed; Tier 3 where intermediate generations exist; oversized logs may be a separate linked Zenodo upload):
  Complete unprocessed responses for every request are archived as the Batch API result files in
  `pipeline/out/logs/batch_*.json` — one file per stage × prompt-variant × chunk, each containing
  the provider's batch record (id, model, status, request counts) and the full response body and
  token usage for every request. Per-chunk parsed responses are in `pipeline/out/chunks/*.rds` and
  `pipeline/out/logs/raw_output_*.rds`.
  **[DECIDE: deposit these publicly with the repo, or as a separate linked Zenodo upload if
  oversized, or escrow them — and record the choice in `metadata.json` → `disclosure_class`. Note
  `pipeline/out/` is currently git-ignored; un-ignore it or attach the logs to the deposit
  explicitly, or they will not ship.]**
- **K.3 Computational resources** — API-call counts, total tokens, cost, compute time:
  Submitted run (9,900 respondents, 2 calls each):

  | | |
  |---|---|
  | API calls returning results | **19,800** |
  | Requests submitted | 20,800 — 1,000 in four batches that stalled and were re-submitted |
  | Failed requests | **0** |
  | Input tokens | **67,790,537** (6,848 per respondent) |
  | Output tokens | **61,116,828** (6,173 per respondent) |
  | Total tokens | **128,907,365** |
  | Cost | **$69.93** at list price |
  | Wall-clock time | **9h 28m** (16 Aug 2026, 13:20–22:48 CEST), 10 chunks of ≤1,000 |
  | Local compute | negligible — R on a laptop; the run is I/O-bound on the Batch API |

  Two notes on the cost figure. It is computed from the per-request `usage` records in the deposited
  batch files at the provider's **list** price ($0.13/M input, $1.00/M output); the Batch API's
  advertised 50% discount would halve it to $34.96, and which of the two the invoice reflects was
  not resolved at the time of writing. And **~84% of output tokens are reasoning tokens** for this
  model family, which is why output volume (and hence cost) is far above the README's planning range
  of 1–3k output tokens per respondent.

  Pilot runs are not included in these figures and cost roughly $11 in total.

## L · Disclosure class
Each item above is deposited as **public**, **escrowed** (sealed from the public but available to the
core team and auditors under confidentiality, with a public SHA-256 hash + timestamp so the lock is
still verifiable — an embargo with a sunset date is encouraged), or **withheld** (permitted only for
items marked neither ★ nor †). Your entry's class is set by its **most restricted item** and recorded
in `metadata.json` → `disclosure_class` (and `escrow_doi` if anything is escrowed):
- **A · Open** — all items public. Full results-table standing; all features enter the design-choice analysis.
- **B · Escrowed** — some items sealed but every item is available to the core team/auditors under confidentiality. Full standing with an *escrowed* badge; only publicly disclosed features enter the design-choice analysis.
- **C · Sealed** — one or more permitted items withheld even from escrow. Scored and reported with a *not independently verifiable* flag; excluded from the approach catalogue and design-choice analysis.

★ items must always be public (never escrowed or withheld); † items must be at minimum escrowed. Full
policy: <https://janpfander.github.io/llm_predictions_megastudy/#disclosure>
