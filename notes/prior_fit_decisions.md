# Which baseline priors are fitted, and which are read off the literature

Supporting note for registration D.2 (profile verbalization / anchors) and G.3
(priors). Companion to `notes/effect_size_priors.md`, which covers the
*intervention* prior; this file covers the *baseline* prior — the value a
synthetic respondent is expected to give in the control condition.

Last updated 2026-08-14.

## Summary

Of the 13 scored outcomes, **3 use coefficients estimated on public microdata**
and **10 keep the literature defaults** shipped in `pipeline/lib/priors.R`.

| | outcomes |
|---|---|
| fitted (GSS) | `trust_multidimensional`, `trust_post`, `funding_perceptions` |
| literature | the other 10 |

`pipeline/prior_fits.csv` is the fit specification; `01b_fit_priors.R` writes
`pipeline/out/prior_coefs_fitted.csv`, which `load_prior_coefs()` merges over
the defaults. Outcomes absent from the fitted file silently keep their default —
that is by design and is why this note exists.

No ANES fit was attempted. Everything estimated here comes from the GSS
(`gssr::gss_all`), waves from 2016 on, weighted by `wtssps`, with all six
moderators entered jointly.

## The three fitted outcomes

| outcome | GSS item | n | R² | resid. SD | D–R gap |
|---|---|---|---|---|---|
| `trust_multidimensional` | `consci` — confidence in the scientific community | 5,845 | 0.106 | 30.1 | 16.8 |
| `trust_post` | `consci` (same item, fitted separately) | 5,845 | 0.106 | 30.1 | 16.8 |
| `funding_perceptions` | `natenvir` — spending on protecting the environment | 4,415 | 0.203 | 29.2 | 28.1 |

Each is a compromise, and the compromise should be stated rather than buried:

- **`consci`** asks about "the scientific community", not climate scientists
  specifically, and is 3 categories against a 0–100 slider. It is nonetheless
  the closest public analogue to the primary outcome, and it is measured on
  enough respondents to estimate all six moderators jointly.
- **`trust_post`** is fitted on the same item as `trust_multidimensional` and
  therefore inherits the same coefficients. It is listed separately so that the
  single-item outcome can carry a wider residual SD than the battery mean.
  The two are not independent estimates and should not be reported as such.
- **`natenvir`** is about environmental spending generally, not climate research
  funding. Its R² (0.20) is the highest of the three, which is a warning as much
  as a recommendation: environmental spending attitudes are closer to a party
  identification item than the trust items are.

The R² values are low in absolute terms (0.05–0.20). That is expected for
attitude items regressed on demographics, but it has a direct consequence: the
fitted residual SDs (29–30) are substantially wider than the literature
defaults they replace (18–23). Anchors built from the fits are therefore
*less* informative per respondent, not more. The argument for using them anyway
is that they are estimated jointly on the six moderators, whereas published
summaries report marginal gaps in which the "education effect" is partly a
party effect wearing a different hat.

## The one fit that was estimated and then discarded

**`inst_trust_mean` ← GSS `confed`** (confidence in the executive branch;
n = 5,891, R² = 0.052, resid. SD 33.3, D–R gap 13.6).

Dropped on 2026-08-14, deliberately. `inst_trust_mean` averages trust in five
institutions — EPA, NASA, NOAA, universities, and the federal government.
`confed` anchors exactly one of them, and it is the least trusted of the five.
The fit put the baseline at **30** against a literature default of **55**: using
it would have pulled the whole five-institution mean down to the level of its
least trusted member, which is a measurement artefact of the donor item rather
than anything about the target population.

The row has been removed from `pipeline/prior_fits.csv`, so a re-run of
`01b_fit_priors.R` does not reintroduce it. `inst_trust_mean` keeps the Pew
literature default. To reverse this decision, re-add the row:

```
inst_trust_mean,gssr::gss_all,confed,3,1,wtssps,gss,2016,"see notes/prior_fit_decisions.md"
```

## Why the remaining nine are not fitted

No public microdata source we have access to measures them in a form that would
survive the crosswalk. Specifically:

- `distrust_post` — distrust is not the complement of trust (ambivalence is
  real), and no GSS/ANES item measures it separately. Modelled as a mirror of
  `trust_post` with an offset, from the literature.
- `belief_post`, `concern_mean` — Yale CCC measures these well, but as published
  aggregates rather than as microdata we can regress on all six moderators.
- `policy_general`, `policy_specific_mean`, `policy_role_mean` — the specific
  policies in this instrument (and the "role of scientists in policy debates"
  framing) have no close public analogue; `policy_specific_mean` in particular
  averages seven policies of very different popularity.
- `behavior_mean` — self-reported climate behaviours; the relevant published
  quantity is the belief–behaviour link, which Hornsey et al. (2016) report
  meta-analytically and which is weak.
- `donation_ams`, `newsletter_signup` — behavioural outcomes inside the survey.
  Anchored on dictator-game norms and typical in-survey opt-in rates. No survey
  microdata measures these at all.

Sources for all 10 defaults are recorded per coefficient in
`pipeline/lib/priors.R` and written out to `pipeline/out/prior_coefs_used.csv`
on every run. Fill registration B/D.2/G.3 from that file rather than from this
one, since it reflects what a given run actually used.

## Two things a reader should know about the run history

1. **The fits were inactive until 2026-08-14.** `cfg$prior_coef_path` was set to
   the bare filename `prior_coefs_fitted.csv`, which resolves against the
   repository root, while `01b` writes to `pipeline/out/`. `load_prior_coefs()`
   checks `file.exists()` and falls back to the literature defaults with only a
   `message()`. Any run before that date — including the 102-respondent pilot —
   was fully literature-based regardless of what the config appeared to say.
   The path is now `pipeline/out/prior_coefs_fitted.csv`. Confirm at run time
   that the console reports `[priors] 3/13 outcomes use fitted coefficients`.

2. **Blinding.** Every fitted source predates and is independent of the target
   study: the GSS waves used were collected from 2016 on and none of them
   measured the target study's outcomes. No coefficient in this pipeline is
   fitted to target-study data, and none has been tuned to make the simulated
   output look closer to any expected result.
