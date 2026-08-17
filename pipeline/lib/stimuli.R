## ---------------------------------------------------------------------------
## stimuli.R — extract the intervention texts from survey/questionnaire.txt.
##
## The texts are presented VERBATIM (registration E.1). Paraphrasing them would
## change the treatment, and the predicted effects would then be predictions of
## a different study.
##
## Two things make this less trivial than splitting on headings:
##
## 1. questionnaire.txt interleaves the participant-facing text with authoring
##    scaffolding — page-break markers, source lists, reference blocks, and
##    passages explicitly flagged "[not displayed to participants]". Feeding
##    those to a simulated respondent hands it a bibliography and a set of
##    programmer instructions that no human participant ever saw.
##
## 2. "Extreme weather predictions" is STATE-CONTINGENT. The respondent names a
##    state, and sees an intro naming that state's risk category plus exactly
##    ONE of four case texts (flood / wildfire / winter storm / generic
##    fallback). Concatenating all four would present a stimulus four times the
##    real length. `render_extreme_weather()` reproduces the branch.
## ---------------------------------------------------------------------------

RE_PAGEBREAK <- "^\\s*[-—–]{1,2}\\s*page\\s*break\\s*[-—–]{0,2}\\s*$"
RE_SEPARATOR <- "^-{10,}\\s*$"
RE_BRACKETED <- "^\\s*\\[.*\\]\\s*$"
RE_URL       <- "https?://|doi\\.org"
RE_SOURCES   <- "^\\s*(Sources?|References?)\\s*:?\\s*$"
RE_NOTDISP   <- "not displayed to participants"

## Strip scaffolding. Stops at the first "[not displayed to participants]"
## marker or horizontal rule, because everything after either is authoring
## material or the next section.
##
## Reference lists are the awkward case: several stimuli interleave a bare
## "Sources:" header, its citations, and further participant-facing prose on the
## same page. Dropping only the header (as an earlier version did) left the
## citations in the stimulus. So a "Sources:"/"References:" line opens a
## reference block that runs until a blank line, a page break, or a rule —
## whichever comes first — and, independently, any line carrying a URL or DOI is
## dropped wherever it occurs, which catches citations that follow a blank line
## inside a list.
clean_stimulus <- function(body) {
  keep <- character(0)
  in_refs <- FALSE
  for (l in body) {
    if (grepl(RE_NOTDISP, l, ignore.case = TRUE)) break
    if (grepl(RE_SEPARATOR, l))                   break
    if (grepl(RE_SOURCES, l, ignore.case = TRUE)) { in_refs <- TRUE; next }
    if (in_refs) {
      ## The list ends at the first blank line or page break; both are also
      ## dropped, so a trailing reference block leaves no stray whitespace.
      if (!nzchar(trimws(l)) || grepl(RE_PAGEBREAK, l, ignore.case = TRUE)) {
        in_refs <- FALSE
      }
      next
    }
    if (grepl(RE_PAGEBREAK, l, ignore.case = TRUE)) next
    if (grepl(RE_BRACKETED, l))                   next
    if (grepl(RE_URL, l))                         next
    keep <- c(keep, sub("\\s+$", "", l))
  }
  txt <- paste(keep, collapse = "\n")
  trimws(gsub("\n{3,}", "\n\n", txt))
}


## Return the raw line blocks per "### " heading, before cleaning.
.stimulus_blocks <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  start <- grep("^CONDITION\\b", lines)
  end   <- grep("^POST-TREATMENT OUTCOMES", lines)
  if (!length(start) || !length(end)) {
    stop("Could not locate the CONDITION / POST-TREATMENT OUTCOMES banners in ",
         path, ". Has the questionnaire been regenerated in a new format?",
         call. = FALSE)
  }
  block <- lines[start[1]:end[1]]
  heads <- grep("^### ", block)
  if (!length(heads)) stop("No '### ' stimulus headings found.", call. = FALSE)

  bounds <- c(heads, length(block) + 1L)
  out <- list()
  for (i in seq_along(heads)) {
    title <- sub("^### ", "", block[heads[i]])
    out[[title]] <- block[(heads[i] + 1L):(bounds[i + 1L] - 1L)]
  }
  out
}


load_stimuli <- function(path = "survey/questionnaire.txt") {
  blocks <- .stimulus_blocks(path)
  out <- list()
  for (title in names(blocks)) {
    key <- if (grepl("^control", title)) {
      if (grepl("Neckties", title, fixed = TRUE))       "control:neckties"
      else if (grepl("Baseball", title, fixed = TRUE))  "control:baseball"
      else                                              "control:dances"
    } else title
    out[[key]] <- clean_stimulus(blocks[[title]])
  }
  out
}


## ---------------------------------------------------------------------------
## Extreme weather predictions — the state-contingent arm
## ---------------------------------------------------------------------------
load_extreme_weather <- function(path = "survey/questionnaire.txt") {

  blocks <- .stimulus_blocks(path)
  ew <- blocks[["Extreme weather predictions"]]
  if (is.null(ew)) {
    stop("'Extreme weather predictions' not found in ", path, call. = FALSE)
  }
  txt <- paste(ew, collapse = "\n")

  ## Section I lists the states assigned to cases 1-3; case 4 is the fallback
  ## for respondents who decline to name a state.
  state_to_case <- character(0)
  case_label    <- character(3)
  for (cs in 1:3) {
    pat <- sprintf("Case %d – [“”\"](.*?)[“”\"]\\s*\n(.*?)(\n\\s*\n|$)", cs)
    m <- regmatches(txt, regexec(pat, txt, perl = TRUE))[[1]]
    if (length(m) < 3) {
      stop("Could not parse the state list for Case ", cs,
           " in 'Extreme weather predictions'.", call. = FALSE)
    }
    case_label[cs] <- m[2]
    states <- trimws(strsplit(m[3], ",")[[1]])
    states <- states[nzchar(states)]
    state_to_case[states] <- as.character(cs)
  }

  ## Case bodies live under "Intervention page 3", each introduced by a bare
  ## "Case N" line. The phrase also occurs inline in the authoring note above,
  ## so anchor on the line that consists of the marker alone and take the last
  ## such line.
  all_lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  p3_start  <- grep("^\\s*Intervention page 3\\s*$", all_lines)
  if (!length(p3_start)) stop("'Intervention page 3' marker not found.", call. = FALSE)
  p3_start  <- p3_start[length(p3_start)]
  p3_lines  <- all_lines[(p3_start + 1L):length(all_lines)]

  ## Authoring scaffolding (References, Risk categories) trails the last case
  ## body and must not leak into it.
  scaffold <- grep("[not displayed to participants]", p3_lines, fixed = TRUE)
  if (length(scaffold)) p3_lines <- p3_lines[seq_len(scaffold[1] - 1L)]

  case_starts <- grep("^Case ([0-9])\\s*$", p3_lines)
  if (length(case_starts) < 4) {
    stop("Expected 4 case texts, found ", length(case_starts), ".", call. = FALSE)
  }
  cb_bounds <- c(case_starts, length(p3_lines) + 1L)
  case_body <- character(4)
  for (i in seq_along(case_starts)) {
    n <- as.integer(sub("^Case ", "", trimws(p3_lines[case_starts[i]])))
    case_body[n] <- clean_stimulus(
      p3_lines[(case_starts[i] + 1L):(cb_bounds[i + 1L] - 1L)]
    )
  }

  ## Intro paragraphs (Intervention page 2): a generic branch for respondents
  ## who decline to name a state, and a templated branch for everyone else.
  intro_generic <- paste(
    "You are living in the United States, a country facing risks by more and",
    "more extreme weather events. Please read the text on the following page",
    "carefully. It describes a real project in the U.S., working particularly",
    "on reducing the risks from these hazards by helping communities prepare",
    "for extreme weather."
  )
  intro_state <- paste(
    "You reported that you are currently living in [STATE], one of several",
    "[CASE]. Please read the text on the following page carefully. It",
    "describes a real project in the U.S., working particularly on reducing",
    "the risks from these hazards by helping communities prepare for extreme",
    "weather."
  )

  list(
    state_to_case = state_to_case,
    case_label    = case_label,
    case_body     = case_body,
    intro_generic = intro_generic,
    intro_state   = intro_state
  )
}


## Render the arm for one respondent. `state` NA or "Prefer not to say"
## reproduces the fallback branch (Case 4 + generic intro).
render_extreme_weather <- function(ew, state) {
  if (is.na(state) || identical(state, "Prefer not to say") ||
      is.na(ew$state_to_case[state])) {
    return(paste(ew$intro_generic, ew$case_body[4], sep = "\n\n"))
  }
  cs    <- as.integer(ew$state_to_case[state])
  intro <- sub("\\[STATE\\]", state, ew$intro_state)
  intro <- sub("\\[CASE\\]", ew$case_label[cs], intro)
  paste(intro, ew$case_body[cs], sep = "\n\n")
}


## ---------------------------------------------------------------------------
## validation
## ---------------------------------------------------------------------------
validate_stimuli <- function(stim, interventions, ew = NULL) {

  need <- c("control:neckties", "control:baseball", "control:dances",
            interventions)
  missing <- setdiff(need, names(stim))
  if (length(missing)) {
    stop("Missing stimulus text(s):\n  ", paste(missing, collapse = "\n  "),
         "\nFound:\n  ", paste(names(stim), collapse = "\n  "),
         call. = FALSE)
  }

  ## The README describes the stimuli as roughly 300-900 words. Anything far
  ## outside that suggests the cleaner ate real text or left scaffolding in.
  wc <- vapply(stim[need], function(s) length(strsplit(s, "\\s+")[[1]]),
               integer(1))
  odd <- names(wc)[wc < 60 | wc > 1200]
  ## "Extreme weather predictions" is expected to be short here: its real
  ## length comes from render_extreme_weather(), not from the shared block.
  odd <- setdiff(odd, "Extreme weather predictions")
  if (length(odd)) {
    warning("Stimulus length outside the expected range for: ",
            paste(sprintf("%s (%d words)", odd, wc[odd]), collapse = ", "),
            ". Check clean_stimulus() against questionnaire.txt.")
  }

  ## Scaffolding that must never reach a respondent.
  leaked <- names(stim)[vapply(stim, function(s)
    grepl(RE_NOTDISP, s, ignore.case = TRUE) ||
    grepl("https?://", s), logical(1))]
  if (length(leaked)) {
    warning("Authoring scaffolding leaked into: ",
            paste(leaked, collapse = ", "))
  }

  if (!is.null(ew)) {
    stopifnot(
      length(ew$case_body) == 4,
      all(nzchar(ew$case_body)),
      length(ew$state_to_case) >= 50,
      !anyDuplicated(names(ew$state_to_case))
    )
    message(sprintf("  extreme-weather arm: %d states mapped, 4 case texts (%s words)",
                    length(ew$state_to_case),
                    paste(vapply(ew$case_body, function(s)
                      length(strsplit(s, "\\s+")[[1]]), integer(1)),
                      collapse = "/")))
  }

  invisible(TRUE)
}
