## ---------------------------------------------------------------------------
## anes_recode.R — crosswalk from ANES variables to the benchmark's exact
## moderator levels.
##
## ⚠️  READ THIS BEFORE RUNNING ⚠️
##
## ANES variable names and code values differ between the Cumulative Data File
## and each Time Series release, and they are occasionally revised. The tables
## below are written from the published codebooks but MUST be verified against
## the codebook shipped with YOUR download. They are laid out as plain data,
## not buried in code, precisely so you can check them line by line.
##
## `validate_recode_spec()` fails loudly on a missing column and reports every
## source code it did not map, so a wrong guess here surfaces immediately
## instead of silently producing a biased donor pool. Run
## `Rscript pipeline/01_build_profiles.R --dry-run` first: it reads the file,
## applies the crosswalk, prints the resulting marginals, and writes nothing.
##
## Where ANES is coarser than the target (see `splits` below), the crosswalk
## assigns levels stochastically using published population shares. Every such
## split is a documented modelling assumption — list it in registration.md
## item D.1.
## ---------------------------------------------------------------------------


## --- target levels: must match scripts/lib/submission_spec.R exactly -------
## Verified against submission_spec.R$moderators. 01_build_profiles.R asserts
## the match at run time, so a benchmark-side edit cannot pass unnoticed.
TARGET_LEVELS <- list(
  gender    = c("Male", "Female", "Other"),
  age_band  = c("18-29", "30-44", "45-59", "60+"),
  race      = c("White / Caucasian", "Black / African American",
                "Hispanic / Latino", "Asian / Asian American", "Other"),
  education = c("Less than high school",
                "High school diploma / GED",
                "Some college or Associate's degree",
                "Bachelor's degree",
                "Master's degree / Professional degree",
                "Doctorate degree / Ph.D."),
  income    = c("Less than $30,000", "$30,000 to $55,999",
                "$56,000 to $99,999", "$100,000 to $167,999",
                "$168,000 or more"),
  party     = c("Republican", "Democrat", "Independent", "Other")
)


## ===========================================================================
## Crosswalk 1 — ANES Time Series Cumulative Data File (VCF* variables)
## ===========================================================================
## Advantage: one file, decades of respondents, stable names.
## Disadvantages, all of which cost you joint-structure fidelity:
##   * income is stored as PERCENTILE GROUPS, not dollars → needs a
##     probabilistic crosswalk to the dollar brackets (see `splits$income`);
##   * education tops out at "advanced degree" → Master's vs Doctorate split;
##   * gender is binary in most waves → almost no "Other" donors.
## Prefer `anes_2020` unless you need the long time series.

SPEC_ANES_CUMULATIVE <- list(

  id_var     = "VCF0006",
  year_var   = "VCF0004",
  weight_var = "VCF0009z",   # full-sample weight; verify for your release

  vars = c(
    gender    = "VCF0104",
    age       = "VCF0101",   # age in years; recoded to bands below
    race      = "VCF0105a",  # 7-category race-ethnicity summary
    education = "VCF0140a",  # 7-category education
    income    = "VCF0114",   # income PERCENTILE group (not dollars)
    party     = "VCF0301"    # 7-point party ID
  ),

  ## Auxiliary variables carried into the persona narrative but never scored.
  ## Richer conditioning is the best-evidenced defence against caricature:
  ## personas built from values, habits and circumstances produce far less
  ## stereotyped answers than personas built from a demographic checklist.
  aux_vars = c(
    ideology   = "VCF0803",  # 7-point liberal-conservative
    religion   = "VCF0128",  # religious preference (major categories)
    attendance = "VCF0130",  # church attendance
    region     = "VCF0112",  # census region
    marital    = "VCF0147",  # marital status
    employment = "VCF0116"   # work status
  ),

  maps = list(
    gender = c(
      "1" = "Male",
      "2" = "Female",
      "3" = "Other"
      # 0 = NA -> dropped
    ),
    race = c(
      "1" = "White / Caucasian",          # White non-Hispanic
      "2" = "Black / African American",   # Black non-Hispanic
      "3" = "Asian / Asian American",     # Asian or Pacific Islander non-Hisp
      "4" = "Other",                      # American Indian / Alaska Native
      "5" = "Hispanic / Latino",
      "6" = "Other",                      # Other or multiple races non-Hisp
      "7" = "Other"                       # Non-white and non-black (old waves)
      # 9 = NA -> dropped
    ),
    education = c(
      "1" = "Less than high school",                    # 8 grades or less
      "2" = "Less than high school",                    # 9-12, no diploma
      "3" = "High school diploma / GED",                # 12 grades + diploma
      "4" = "High school diploma / GED",                # + non-academic train
      "5" = "Some college or Associate's degree",
      "6" = "Bachelor's degree",
      "7" = "__ADVANCED__"                              # split, see below
      # 8, 9 = DK/NA -> dropped
    ),
    party = c(
      "1" = "Democrat",     "2" = "Democrat",  "3" = "Democrat",
      "4" = "Independent",
      "5" = "Republican",   "6" = "Republican", "7" = "Republican"
      # 0 = DK/NA -> dropped.
      # NOTE: leaners (3, 5) are folded into their party. The benchmark's
      # `party` item is a 4-way self-identification with an explicit
      # Independent option, so folding leaners overstates partisanship
      # relative to the survey. Set `fold_leaners = FALSE` in
      # 01_build_profiles.R to map 3 and 5 to "Independent" instead.
    )
  ),

  ## Stochastic splits where ANES is coarser than the target. Shares are
  ## population estimates, applied independently of other characteristics —
  ## the weakest link in this crosswalk. Refine them (e.g. condition the
  ## Master's/Doctorate split on age and income) if the moderator cells for
  ## these levels matter to you.
  splits = list(

    ## Among US adults holding an advanced degree, doctorates (incl. PhD,
    ## EdD, and research doctorates but excluding most professional degrees,
    ## which the benchmark groups with Master's) are the clear minority.
    ## VERIFY against a current ACS educational-attainment table.
    education = list(
      "__ADVANCED__" = c(
        "Master's degree / Professional degree" = 0.82,
        "Doctorate degree / Ph.D."              = 0.18
      )
    ),

    ## Percentile group -> dollar bracket. The ANES cut points (16/33/67/95)
    ## do not line up with the survey's brackets, so each percentile group
    ## spreads across neighbouring brackets. Rows must sum to 1.
    ## VERIFY against a current household-income distribution; these are
    ## approximations and are the single largest source of income-moderator
    ## error in this pipeline.
    income = list(
      "1" = c("Less than $30,000" = 0.90, "$30,000 to $55,999" = 0.10),
      "2" = c("Less than $30,000" = 0.35, "$30,000 to $55,999" = 0.60,
              "$56,000 to $99,999" = 0.05),
      "3" = c("$30,000 to $55,999" = 0.30, "$56,000 to $99,999" = 0.55,
              "$100,000 to $167,999" = 0.15),
      "4" = c("$56,000 to $99,999" = 0.30, "$100,000 to $167,999" = 0.55,
              "$168,000 or more" = 0.15),
      "5" = c("$100,000 to $167,999" = 0.20, "$168,000 or more" = 0.80)
    )
  )
)


## ===========================================================================
## Crosswalk 2 — ANES 2020 Time Series (V20* variables)
## ===========================================================================
## Recommended. Finer race, education and income categories, and closest in
## time to the target study. Income still needs a bracket crosswalk because
## the ANES brackets are narrower than the survey's, but it is a
## dollars-to-dollars mapping rather than a percentile guess.

SPEC_ANES_2020 <- list(

  id_var     = "V200001",
  year_var   = NULL,
  weight_var = "V200010b",   # post-election full-sample weight

  vars = c(
    gender    = "V201600",   # R self-identified gender
    age       = "V201507x",  # age; 80 = "80 or older"
    race      = "V201549x",  # race-ethnicity summary
    education = "V201510",   # highest level of education
    income    = "V201617x",  # household income, 22 dollar brackets
    party     = "V201231x"   # 7-point party ID summary
  ),

  aux_vars = c(
    ideology   = "V201200",  # 7-point liberal-conservative
    religion   = "V201435",
    attendance = "V201452",
    urbanicity = "V201014b",
    marital    = "V201508",
    employment = "V201534x"
  ),

  maps = list(
    gender = c("1" = "Male", "2" = "Female"),  # negatives = missing
    race = c(
      "1" = "White / Caucasian",
      "2" = "Black / African American",
      "3" = "Hispanic / Latino",
      "4" = "Asian / Asian American",   # Asian or Native Hawaiian/PI
      "5" = "Other",                    # Native American / Alaska Native etc.
      "6" = "Other"                     # multiple races
    ),
    education = c(
      "1" = "Less than high school",
      "2" = "High school diploma / GED",
      "3" = "Some college or Associate's degree",
      "4" = "Some college or Associate's degree",  # associate, vocational
      "5" = "Some college or Associate's degree",  # associate, academic
      "6" = "Bachelor's degree",
      "7" = "Master's degree / Professional degree",
      "8" = "Doctorate degree / Ph.D."             # professional / doctorate
    ),
    party = c(
      "1" = "Democrat",   "2" = "Democrat",   "3" = "Democrat",
      "4" = "Independent",
      "5" = "Republican", "6" = "Republican", "7" = "Republican"
    )
  ),

  ## ANES 2020 income is 22 dollar brackets. Rather than transcribe all 22
  ## boundaries (a transcription error here is invisible), map each code to
  ## the MIDPOINT of its bracket in dollars and let `income_from_dollars()`
  ## assign the target bracket. Verify these midpoints against the codebook;
  ## an error of a few thousand dollars only matters at a boundary.
  income_midpoints = c(
    "1" = 5000,    "2" = 11250,  "3" = 13750,  "4" = 16250,  "5" = 18750,
    "6" = 21250,   "7" = 23750,  "8" = 26250,  "9" = 28750,  "10" = 32500,
    "11" = 37500,  "12" = 42500, "13" = 47500, "14" = 52500, "15" = 57500,
    "16" = 62500,  "17" = 67500, "18" = 72500, "19" = 77500, "20" = 85000,
    "21" = 95000,  "22" = 125000
  ),

  splits = list()
)


## ---------------------------------------------------------------------------
## GSS Cumulative Data File (1972-2024)
##
## NOT a donor pool for 01_build_profiles.R — use it only as a fitting source
## for 01b_fit_priors.R. The GSS carries `consci` (confidence in the scientific
## community) and `natenvir` (environmental spending), which are the closest
## public analogues to two of the benchmark's outcomes, but its demographics
## are coarser than ANES 2020 on race and it has no usable climate-belief item.
##
## ⚠ VERIFY THESE AGAINST YOUR RELEASE. GSS variable names are stable by
## reputation and not by guarantee: `sex` was joined by `sexnow1` in later
## waves, the weight variable has been `wtssall` / `wtssps` / `wtssnrps`
## depending on years covered, and `race` is the pre-1972-style 3-category
## variable that needs `hispanic` to separate Hispanic respondents.
## validate_recode_spec() will tell you if a name is missing; it cannot tell
## you if a name means something other than you think.
SPEC_GSS <- list(

  id_var     = "id",
  year_var   = "year",
  weight_var = "wtssps",     # verify: wtssall in older releases

  vars = c(
    gender    = "sex",       # 1 = male, 2 = female
    age       = "age",       # years; 89 = "89 or older"
    race      = "race",      # 1 = white, 2 = black, 3 = other
    education = "degree",    # 0 = lt high school ... 4 = graduate
    income    = "conrinc",   # respondent income in constant dollars
    party     = "partyid"    # 0 = strong Dem ... 6 = strong Rep, 7 = other
  ),

  aux_vars = c(
    ideology   = "polviews",
    religion   = "relig",
    attendance = "attend",
    region     = "region",
    marital    = "marital",
    employment = "wrkstat"
  ),

  maps = list(
    gender = c("1" = "Male", "2" = "Female"),
    ## The GSS `race` variable predates the current census categories and does
    ## not separate Hispanic respondents, who are distributed across all three
    ## codes. Fitting a "nonwhite" coefficient on this is defensible; fitting
    ## separate Hispanic and Asian coefficients is not — those levels will be
    ## badly measured, so treat any race coefficient from GSS as approximate.
    race = c("1" = "White / Caucasian",
             "2" = "Black / African American",
             "3" = "Other"),
    education = c("0" = "Less than high school",
                  "1" = "High school diploma / GED",
                  "2" = "Some college or Associate's degree",
                  "3" = "Bachelor's degree",
                  "4" = "Master's degree / Professional degree"),
    ## partyid 0-2 lean Democrat, 4-6 lean Republican, 3 independent, 7 other.
    ## Folded the same way as ANES leaners, for consistency across sources.
    party = c("0" = "Democrat", "1" = "Democrat", "2" = "Democrat",
              "3" = "Independent",
              "4" = "Republican", "5" = "Republican", "6" = "Republican",
              "7" = "Other")
  ),

  ## `conrinc` is already in constant dollars, so it goes straight through
  ## income_from_dollars() rather than through a bracket crosswalk. Note the
  ## base year of the deflator in your release: it is not 2026 dollars, and the
  ## income brackets the benchmark uses are nominal. Adjust or accept the
  ## mismatch knowingly.
  income_is_dollars = TRUE,

  splits = list()
)


RECODE_SPECS <- list(
  anes_cumulative = SPEC_ANES_CUMULATIVE,
  anes_2020       = SPEC_ANES_2020,
  gss             = SPEC_GSS
)


## ---------------------------------------------------------------------------
## helpers
## ---------------------------------------------------------------------------

age_to_band <- function(age) {
  age <- suppressWarnings(as.numeric(age))
  out <- rep(NA_character_, length(age))
  out[age >= 18 & age <= 29] <- "18-29"
  out[age >= 30 & age <= 44] <- "30-44"
  out[age >= 45 & age <= 59] <- "45-59"
  out[age >= 60]             <- "60+"
  out
}

income_from_dollars <- function(dollars) {
  cut(
    dollars,
    breaks = c(-Inf, 30000, 56000, 100000, 168000, Inf),
    labels = TARGET_LEVELS$income,
    right  = FALSE
  ) |> as.character()
}

## Apply a documented stochastic split. Deterministic given the RNG state, so
## the whole pipeline stays reproducible from cfg$seed.
apply_split <- function(x, split_table) {
  for (placeholder in names(split_table)) {
    idx <- which(x == placeholder)
    if (!length(idx)) next
    shares <- split_table[[placeholder]]
    stopifnot(abs(sum(shares) - 1) < 1e-8)
    x[idx] <- sample(names(shares), length(idx), replace = TRUE, prob = shares)
  }
  x
}

## Map a source column through a value map, returning NA for unmapped codes.
map_codes <- function(x, map) unname(map[as.character(x)])


## ---------------------------------------------------------------------------
## validate_recode_spec() — fail loudly, and say exactly what is wrong.
## ---------------------------------------------------------------------------
validate_recode_spec <- function(df, spec, verbose = TRUE) {

  needed <- c(spec$id_var, spec$year_var, spec$weight_var,
              spec$vars, spec$aux_vars)
  needed <- needed[!vapply(needed, is.null, logical(1))]
  missing <- setdiff(unname(needed), names(df))

  if (length(missing)) {
    stop(
      "These columns are not in the data file:\n  ",
      paste(missing, collapse = ", "),
      "\n\nANES variable names differ between releases. Open the codebook that ",
      "came with your download, find the equivalent variables, and edit ",
      "pipeline/lib/anes_recode.R. Available columns starting with the same ",
      "prefix:\n  ",
      paste(utils::head(grep(paste0("^", substr(missing[1], 1, 4)),
                             names(df), value = TRUE), 20), collapse = ", "),
      call. = FALSE
    )
  }

  ## Report unmapped codes rather than silently dropping them: a code that
  ## should have been mapped shows up here as an unexpectedly large NA share.
  if (verbose) {
    for (v in names(spec$maps)) {
      src  <- spec$vars[[v]]
      seen <- unique(as.character(df[[src]]))
      unmapped <- setdiff(seen, names(spec$maps[[v]]))
      if (length(unmapped)) {
        n_unmapped <- sum(as.character(df[[src]]) %in% unmapped)
        message(sprintf(
          "  %-10s (%s): %d unmapped code(s) [%s] covering %.1f%% of rows",
          v, src, length(unmapped),
          paste(utils::head(sort(unmapped), 8), collapse = ", "),
          100 * n_unmapped / nrow(df)
        ))
      }
    }
  }

  invisible(TRUE)
}


## ---------------------------------------------------------------------------
## recode_anes() — source file -> tidy donor pool on benchmark levels.
## ---------------------------------------------------------------------------
recode_anes <- function(df, spec, fold_leaners = TRUE) {

  out <- data.frame(
    donor_id = df[[spec$id_var]],
    weight   = if (!is.null(spec$weight_var)) {
      suppressWarnings(as.numeric(df[[spec$weight_var]]))
    } else 1,
    stringsAsFactors = FALSE
  )
  if (!is.null(spec$year_var)) out$year <- df[[spec$year_var]]

  out$gender    <- map_codes(df[[spec$vars[["gender"]]]],    spec$maps$gender)
  out$race      <- map_codes(df[[spec$vars[["race"]]]],      spec$maps$race)
  out$education <- map_codes(df[[spec$vars[["education"]]]], spec$maps$education)
  out$age_band  <- age_to_band(df[[spec$vars[["age"]]]])
  out$age       <- suppressWarnings(as.numeric(df[[spec$vars[["age"]]]]))

  party_map <- spec$maps$party
  if (!fold_leaners) party_map[c("3", "5")] <- "Independent"
  out$party <- map_codes(df[[spec$vars[["party"]]]], party_map)

  ## income: dollar midpoints where available, percentile crosswalk otherwise
  inc_src <- as.character(df[[spec$vars[["income"]]]])
  if (isTRUE(spec$income_is_dollars)) {
    ## Source already reports dollars (GSS conrinc); bracket it directly.
    out$income <- income_from_dollars(suppressWarnings(as.numeric(inc_src)))
  } else if (!is.null(spec$income_midpoints)) {
    out$income <- income_from_dollars(unname(spec$income_midpoints[inc_src]))
  } else {
    out$income <- rep(NA_character_, nrow(df))
    for (grp in names(spec$splits$income)) {
      idx <- which(inc_src == grp)
      if (!length(idx)) next
      shares <- spec$splits$income[[grp]]
      stopifnot(abs(sum(shares) - 1) < 1e-8)
      out$income[idx] <- sample(names(shares), length(idx),
                                replace = TRUE, prob = shares)
    }
  }

  if (!is.null(spec$splits$education)) {
    out$education <- apply_split(out$education, spec$splits$education)
  }

  ## auxiliary variables kept as raw codes; 02_simulate.R renders them into
  ## the backstory. Kept raw so the mapping to prose lives in one place.
  for (a in names(spec$aux_vars)) {
    out[[paste0("aux_", a)]] <- df[[spec$aux_vars[[a]]]]
  }

  out
}
