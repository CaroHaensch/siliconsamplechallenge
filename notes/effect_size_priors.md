# Effect-size priors for the Silicon Sample Benchmark

Literature review to calibrate expectations for the 16 trust-in-climate-scientists interventions
× 13 outcomes. Compiled 2026-08-05. All outcomes in the target study are 0–100 sliders (plus one
$0–10 donation and one binary sign-up), so effects are quoted in **percentage points of scale
range (pp)** wherever possible.

---

## 1. Bottom line

**Expect almost nothing.** For a single ~300–900-word text read once in an online panel:

| Quantity | Prior |
|---|---|
| Typical ATE on an attitudinal 0–100 slider | **0.5–2 pp** |
| Best intervention on the primary outcome | **2–4 pp**, plausibly up to 5 pp |
| Share of intervention × outcome cells that are essentially zero (\|ATE\| < 1 pp) | **~50–70%** |
| Effect on the real-money donation | **≈ 0**, sign ambiguous, backfire possible |
| Effect on newsletter sign-up | **≈ 0 to +2 pp** |
| Sign of the average effect | Positive, but individual cells will be noisily negative |
| Standardized scale | Cohen's *d* ≈ **0.02–0.12** for most cells |

The dominant failure mode for a silicon sample here is **exaggeration**, not wrong sign. The
scoring pipeline's calibration regression (slope β) is designed to catch exactly this: if you
predict 10 pp where humans show 1.5 pp, directional agreement and Spearman ρ can still look fine
while β and RMSE are terrible. A pipeline that predicts the *right ordering* with *compressed
magnitudes* will score better than one that predicts psychologically "plausible" large shifts.

A second, related failure mode: **variance compression**. LLM personas produce responses that are
too homogeneous and too modal-response-heavy, which inflates apparent effects relative to the
noise and destroys the Tier-1 distributional metrics (variance ratio, OVL, KS, W1). See §7.

---

## 2. The closest analogue: Voelkel et al. (2026, *Nature Climate Change*)

This is the single most informative prior. Nearly the same design as the target study: US
non-probability panel matched to census benchmarks, *N* = 13,544, 10 message interventions vs.
pooled control, 0–100 slider outcomes, plus a real donation measure.

**Effects on primary outcomes (pooled across the 10 treatments, vs. control):**

| Outcome | Overall ATE | Largest single treatment | % of partisan gap |
|---|---|---|---|
| Belief in climate change | +1.16 pp | Scientific Consensus 2: **+3.12 pp** | 5% / 14% |
| Climate change concern | +1.23 pp | Purity framing: **+2.47 pp** | 3% / 7% |
| Support for general mitigation policy | +0.76 pp | Purity framing: **+1.65 pp** | 2% / 5% |
| Political pro-env. behavioural intentions | +1.84 pp | System preservation: **+3.67 pp** | 8% / 15% |
| Support for pro-env. candidates | +1.25 pp | Dire-but-solvable: **+2.14 pp** | 11% / 19% |
| Support for specific policies | +1.34 pp | Gains framing: **+2.05 pp** | 5% / 8% |
| **Pro-environmental donation** | **−1.69 pp (n.s., p=.061)** | Sci. Consensus 2: **−3.95 pp (backfire)** | — |

**Control-condition means and SDs (0–100)** — directly usable as baseline anchors for structurally
similar items in the target survey:

| Outcome | M | SD |
|---|---|---|
| Support for pro-environmental candidates | 32.5 | 21.5 |
| Political pro-env. behavioural intentions | 33.9 | 28.9 |
| Support for *specific* mitigation policies | 53.3 | 24.0 |
| Non-political pro-env. behavioural intentions | 54.5 | 24.3 |
| Climate change concern | 60.4 | 31.7 |
| Pro-environmental donation | 61.6 | 45.3 |
| Belief in climate change | 65.4 | 22.5 |
| Support for *general* mitigation policy | 68.0 | 29.3 |
| Support for company-led mitigation | 70.9 | 28.1 |

Note the very large SDs (22–32 on a 0–100 scale; 45 for donation). Human response distributions
on these sliders are wide, multimodal, and heavily clustered on round numbers (0, 50, 100). This
is the single hardest thing for a silicon sample to reproduce.

**Three findings from this paper that should directly constrain your predictions:**

1. **Heterogeneity is small and mostly in the "wrong" direction.** Only 12 of 90 treatment ×
   partisanship interactions were significant, and 10 of those showed *stronger* effects among
   Democrats, not Republicans. Treatments that worked on Democrats also worked on Republicans
   (average *r* = .57 across treatments). Targeted/moral-reframing theory predicting large
   conservative-specific gains was **not** supported. → Do not build large party × treatment
   interactions into your predictions. The benchmark scores subgroup heterogeneity, and the
   defensible prior is "nearly parallel effects with slightly larger movement among Democrats."
2. **The strongest moderator was pre-treatment concern, not party** (26 of 90 interactions;
   19 indicating stronger effects among the already-concerned). Persuasion accrues to the already
   persuaded.
3. **Costly behaviour does not move.** No treatment increased donations; one significantly
   *decreased* them. The most effective attitude-mover (Scientific Consensus 2) was the one that
   backfired on donation — attitudinal and behavioural effects were not merely attenuated but
   partly *decoupled*.

---

## 3. Second anchor: Vlasceanu et al. (2024, *Science Advances*)

Global intervention tournament, 11 expert-crowdsourced interventions, *N* = 59,440, 63 countries.

- Best effect on climate **beliefs**: decreasing psychological distance, **+2.3%**
- Best effect on **policy support**: writing a letter to a future generation member, **+2.6%**
- Best effect on **sharing intentions**: negative emotion induction, **+12.1%** (the outlier —
  cheap, low-cost expressive outcomes move much more than anything else)
- Effect on the **effortful behavioural task** (tree-planting WEPT): **no intervention increased
  it; several significantly reduced it**. Control-condition baseline: 53.1% completed all 8 pages.

Read together with Voelkel: the *ordering across outcome types* is a strong, replicated
regularity. Cheap self-report > policy attitudes > costly behaviour, with the last at or below
zero. In the target study this maps onto:

```
sharing/expressive-type items  >  trust sliders, concern, policy support  >  donation, newsletter
        (largest)                          (small, 1–3 pp)                     (≈ 0 or negative)
```

---

## 4. Meta-analytic anchors

| Source | Finding | Relevance |
|---|---|---|
| van Stekelenburg et al. (2022), *Psych. Science*, 43 experiments | Consensus messaging: *g* = **0.55** on *perceived consensus*, but only *g* = **0.12** on *belief in the underlying facts* (0.44–0.46 after removing influential cases) | The proximal, message-restating item moves a lot; everything downstream moves little. Expect the same gradient between "what the message asserted" and the trust composite. |
| Rode et al. (2021), *J. Environ. Psychol.* | Small significant average effect of interventions on climate attitudes; **policy support moves less than belief**; skepticism-inducing messages had *stronger* effects than belief-promoting ones | Asymmetry: it is easier to reduce trust than to raise it. Relevant for the oil-industry-misinformation intervention. |
| Bergquist et al. (2022), *Nature Climate Change*, 89 datasets, *N* = 119,465 | Perceived **fairness** and **effectiveness** are the strongest correlates of climate policy support; knowledge and demographics weak or near-zero | Interventions that do not touch fairness/efficacy perceptions should not be predicted to move policy support. |
| Cologna & Siegrist (2020), *J. Environ. Psychol.*, 141 correlations / 51 studies | Trust in scientists correlates **strongly** with public/political climate behaviours, **moderately** with private behaviours, weakly for institutional and general trust | Governs the *correlational* structure you should reproduce between trust and downstream outcomes — not the causal effect size. |
| Nisbet et al. / general megastudy literature | Behavioural-intervention effects on climate action are *d* ≈ 0.08–0.16 while active, with little persistence | Sanity ceiling. |

---

## 5. Trust-in-scientists interventions specifically

The literature here is thinner and the effects are, if anything, smaller than for climate attitudes:

- **Infographic on the scientific process** (RCT, 2021, *JMIR*): trust in science difference-in-
  difference = **0.03** scale points, *t* = 2.16, *p* = .031. Statistically significant, substantively
  negligible.
- **"Do Your Own Research" intervention** (2026, *Sci. Rep.*): among the larger reported effects
  (aRRR 1.69 for trust in science) but uses an active, multi-step task, not a passive text — not a
  fair analogue for a read-once stimulus.
- **Self-disclosure by scientists** (Altenmüller et al., 2023): improves perceived *benevolence*
  and *integrity* but trades off against *competence*, and **does not** increase trust in the
  research itself. → Expect the four METI-style subscales in the target study
  (competence / integrity / benevolence / openness) to move **differentially and sometimes in
  opposite directions**. Predicting a uniform lift on all four is almost certainly wrong.
- **Competence is near ceiling.** Public perceptions of scientists are stereotypically
  "competent but cold." Competence items therefore have the least headroom; **benevolence and
  openness are the dimensions with room to move**, and are the plausible targets of the
  humanizing/portrait/interview/community-helper interventions in this study.

---

## 6. Baseline (control-cell) anchors for the US

The benchmark scores *demographic baseline calibration* separately, so getting the control
condition right is worth as much as getting the effects right — and it is far more tractable.

**Trust levels**

- TISP many-labs (Cologna et al. 2025, *Nat. Hum. Behav.*, *N* = 71,922, 68 countries): trust in
  scientists global *M* = **3.62** (SD 0.70) on 1–5; trust in **climate** scientists *M* = **3.50**
  (SD **1.18**, single item). US is in the top third for trust in scientists but is among the
  countries where climate scientists are trusted *less* than scientists generally.
  → On a 0–100 rescaling, ~65 for scientists, ~62 for climate scientists, with a **much wider**
  distribution for the climate-specific item.
- Pew (Oct 2025): **77%** of US adults have at least a fair amount of confidence in scientists
  (28% "a great deal"); Democrats 90%, Republicans 65% — a **25 pp partisan gap**.
- Pew (2023): only **24%** think climate scientists understand the *causes* of climate change very
  well (Dem 41% vs. Rep 7%).

**Climate attitudes** (Yale CCAM Fall 2025): happening 72%; mostly human-caused 58%; at least
somewhat worried 64%; personally important 59%.
Gallup (2026): "great deal" of worry 44% overall — **Dem 72% vs. Rep 6%**.

**Institutional trust** (Pew 2025, % favourable): National Weather Service/NOAA **76%**,
NASA ~**64%**, federal government **17%** trust to do the right thing. NASA and NOAA are trusted
*across* party lines; EPA and the federal government are strongly polarized. → The
`inst_trust_*` block should show a steep gradient NASA/NOAA > universities > EPA > federal
government, with the party gap widening as you move right along that ordering.

**Demographic gradients** (Cologna et al. 2025; Ghasemi et al. 2025, *Environ. Res. Lett.*):
trust in scientists is higher among women, older, urban, higher-income, more-educated and
left-leaning respondents. **Important reversal:** age is *positively* associated with trust in
scientists generally but *negatively* with trust in **climate** scientists. Conservatism is a
stronger negative predictor for climate scientists than for scientists generally.

**Donation baseline.** Engel (2011) dictator-game meta-study: mean **28.35%** of endowment given,
~36% give zero. Charity recipients and unearned ("bonus") endowments push giving up. A reasonable
prior for the $10-to-AMS task: mean **$2.80–4.00**, ~25–35% giving $0, mass points at $5 (~15%)
and $10 (~5%). This composite is an inference, not a published figure — treat it as an assumption.
Voelkel's donation measure had *M* = 61.6 on a 0–100 rescaling with SD 45.3, i.e. bimodal at the
extremes; expect the same U-shape.

**Newsletter sign-up.** No citable base rate found. Field ballpark 5–20%; treat any value as an
unsourced modelling assumption and do not let it drive your predictions.

---

## 7. Implications for the pipeline

1. **Shrink aggressively.** Whatever your raw simulated ATEs are, the empirical prior is 1–3 pp.
   If your pipeline produces 8–15 pp shifts, it is describing a different universe. Post-hoc
   scaling is permitted (item G.3) but must be declared and cannot be fitted to any outcome data
   from this study — fit it to the published anchors above instead.
2. **Rank, don't inflate.** Spearman ρ and directional agreement are the metrics you are most
   likely to win; RMSE and β are the ones you are most likely to lose. Optimizing for plausible
   ordering while compressing magnitudes dominates.
3. **Expect ~half the cells to be noise.** With 16 × 13 = 208 cells and true effects near zero,
   even the human half-sample reference will have poor directional agreement on the null cells.
   The human replication reference is the benchmark you are actually chasing, and it is not
   perfect — it will be noticeably below ceiling.
4. **Do not build strong party × treatment interactions.** Voelkel found near-parallel effects.
   Baseline *levels* by party should be dramatically different; *treatment effects* by party
   should not.
5. **Predict flat-to-negative behavioural effects.** The safest prediction for `donation_ams` and
   `newsletter_signup` is a distribution centred on zero. A confident positive prediction on
   donations is the highest-variance bet in the whole submission and both megastudies argue
   against it.
6. **Reproduce dispersion, not just means.** Human SDs of 22–32 on 0–100 sliders, with mass at 0,
   50 and 100. LLM personas are known to produce compressed, over-modal distributions (Bisbee
   et al. 2024, *Political Analysis*, on the perils of synthetic survey data), which directly
   damages the variance-ratio, OVL, KS and W1 metrics.
7. **Do not let demographics do all the work.** The stereotyping diagnostic compares the *R²* of
   demographics predicting responses in your sample vs. humans. In human data, demographics
   explain a modest share of variance in trust items — party far more than gender, race or age.
   Persona prompts that make demographics highly salient will overshoot this *R²*.

---

## Sources

- [Voelkel, Ashokkumar, Abeles et al. (2026). A registered report megastudy on the persuasiveness of the most-cited climate messages. *Nature Climate Change* 16, 214–225](https://doi.org/10.1038/s41558-025-02536-2) · [open-access manuscript](https://orca.cardiff.ac.uk/id/eprint/183814/1/Manuscript.pdf) · [data/code](https://doi.org/10.17605/OSF.IO/2MCF8)
- [Vlasceanu et al. (2024). Addressing climate change with behavioral science: A global intervention tournament in 63 countries. *Science Advances* 10, eadj5778](https://www.science.org/doi/10.1126/sciadv.adj5778)
- [van Stekelenburg et al. (2022). Scientific-Consensus Communication About Contested Science: A Preregistered Meta-Analysis. *Psychological Science*](https://journals.sagepub.com/doi/10.1177/09567976221083219)
- [Rode et al. (2021). Influencing climate change attitudes in the United States: A systematic review and meta-analysis. *J. Environmental Psychology* 76, 101623](https://www.sciencedirect.com/science/article/abs/pii/S0272494421000761)
- [Bergquist et al. (2022). Meta-analyses of fifteen determinants of public opinion about climate change taxes and laws. *Nature Climate Change*](https://www.nature.com/articles/s41558-022-01297-6)
- [Cologna & Siegrist (2020). The role of trust for climate change mitigation and adaptation behaviour: A meta-analysis. *J. Environmental Psychology*](https://www.sciencedirect.com/science/article/abs/pii/S0272494419304281)
- [Cologna et al. (2025). Trust in scientists and their role in society across 68 countries. *Nature Human Behaviour* 9, 713–730](https://www.nature.com/articles/s41562-024-02090-5)
- [Ghasemi, Cologna, Mede et al. (2025). Gaps in public trust between scientists and climate scientists: a 68 country study. *Environmental Research Letters* 20, 061002](https://iopscience.iop.org/article/10.1088/1748-9326/add1f9)
- [Pew Research Center (Jan 2026). Americans' Confidence in Scientists](https://www.pewresearch.org/science/2026/01/15/americans-confidence-in-scientists/)
- [Pew Research Center (Oct 2023). Americans continue to have doubts about climate scientists' understanding of climate change](https://www.pewresearch.org/short-reads/2023/10/25/americans-continue-to-have-doubts-about-climate-scientists-understanding-of-climate-change/)
- [Pew Research Center (Aug 2025). Federal agency favourability](https://www.pewresearch.org/politics/2025/08/27/republicans-views-of-justice-department-fbi-rebound-as-democrats-views-shift-more-negative/)
- [Yale Program on Climate Change Communication. Climate Change in the American Mind, Fall 2025](https://climatecommunication.yale.edu/publications/climate-change-in-the-american-mind-beliefs-attitudes-fall-2025/)
- [Gallup (Mar 2026). Climate Change Concern Near High Point](https://news.gallup.com/poll/708050/climate-change-concern-near-high-point.aspx)
- [Engel (2011). Dictator games: a meta study. *Experimental Economics* 14, 583–610](https://link.springer.com/article/10.1007/s10683-011-9283-7)
- [Agley et al. (2021). Intervening on Trust in Science… RCT. *JMIR* 23(10):e32425](https://www.jmir.org/2021/10/e32425)
- [Increasing trust in science through a "Do Your Own Research" intervention (2026). *Scientific Reports*](https://www.nature.com/articles/s41598-026-35268-0)
- [Hewitt et al. (2026). Large language models can predict the results of social science experiments. *Nature*](https://www.nature.com/articles/s41586-026-10742-x) — *r* = 0.85 across 476 treatment effects (0.90 for unpublished studies), 90% directional agreement. The optimistic benchmark for what a good pipeline can achieve.
- [Bisbee, Clinton, Dorff, Kenkel & Larson (2024). Synthetic Replacements for Human Survey Data? The Perils of Large Language Models. *Political Analysis* 32(4), 401–416](https://www.cambridge.org/core/journals/political-analysis/article/synthetic-replacements-for-human-survey-data-the-perils-of-large-language-models/B92267DC26195C7F36E63EA04A47D2FE) — the pessimistic counterpart: persona-prompted LLM responses have similar means but **smaller variance**, and exaggerate the extremity of partisan and social division.
