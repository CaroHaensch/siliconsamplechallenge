## ---------------------------------------------------------------------------
## states.R — assign a US state to each synthetic respondent.
##
## Needed only by the "Extreme weather predictions" arm, which branches on the
## respondent's state (flood / wildfire / winter-storm risk category). But the
## state is assigned to EVERY respondent, in every condition, because the
## survey asks it of everyone and because it makes the backstories concrete.
##
## Preferred source is the donor's own ANES state. The population table below
## is a fallback for donor files that do not carry state, and for respondents
## whose state code is missing.
##
## ⚠️ These are approximate 2020-census resident populations in millions,
## used only as sampling weights. An error of a few percent shifts nobody's
## risk category; verify them if you plan to use state for anything else.
## ---------------------------------------------------------------------------

STATE_POP <- c(
  "Alabama" = 5.02, "Alaska" = 0.73, "Arizona" = 7.15, "Arkansas" = 3.01,
  "California" = 39.54, "Colorado" = 5.77, "Connecticut" = 3.61,
  "Delaware" = 0.99, "Florida" = 21.54, "Georgia" = 10.71, "Hawaii" = 1.46,
  "Idaho" = 1.84, "Illinois" = 12.81, "Indiana" = 6.79, "Iowa" = 3.19,
  "Kansas" = 2.94, "Kentucky" = 4.51, "Louisiana" = 4.66, "Maine" = 1.36,
  "Maryland" = 6.18, "Massachusetts" = 7.03, "Michigan" = 10.08,
  "Minnesota" = 5.71, "Mississippi" = 2.96, "Missouri" = 6.15,
  "Montana" = 1.08, "Nebraska" = 1.96, "Nevada" = 3.10,
  "New Hampshire" = 1.38, "New Jersey" = 9.29, "New Mexico" = 2.12,
  "New York" = 20.20, "North Carolina" = 10.44, "North Dakota" = 0.78,
  "Ohio" = 11.80, "Oklahoma" = 3.96, "Oregon" = 4.24,
  "Pennsylvania" = 13.00, "Rhode Island" = 1.10, "South Carolina" = 5.12,
  "South Dakota" = 0.89, "Tennessee" = 6.91, "Texas" = 29.15, "Utah" = 3.27,
  "Vermont" = 0.64, "Virginia" = 8.63, "Washington" = 7.71,
  "West Virginia" = 1.79, "Wisconsin" = 5.89, "Wyoming" = 0.58,
  "Washington D.C." = 0.69
)

## Share of respondents who decline to give a state. The survey offers
## "Prefer not to say", and those respondents get the generic Case-4 branch.
## Keeping a small share here means Case 4 is actually exercised rather than
## being a code path that never runs.
PREFER_NOT_TO_SAY <- 0.02

assign_states <- function(n, prefer_not_to_say = PREFER_NOT_TO_SAY) {
  s <- sample(names(STATE_POP), n, replace = TRUE, prob = STATE_POP)
  decline <- stats::runif(n) < prefer_not_to_say
  s[decline] <- "Prefer not to say"
  s
}

## Reconcile the state names used by the questionnaire's case lists with the
## table above. The questionnaire writes the District as "Washington D.C." in
## one place and "Washington, D.C." in another; normalise before joining.
normalise_state <- function(x) {
  x <- trimws(x)
  x[x %in% c("Washington, D.C.", "Washington DC", "District of Columbia")] <-
    "Washington D.C."
  x
}
