## ---------------------------------------------------------------------------
## run_submission.R — clean + manifest + check, from RStudio.
##
## Press Source (Ctrl+Shift+S). No terminal, no flags.
##
## The organisers' entry points (scripts/clean.R, scripts/check.R) locate their
## own directory via the `--file=` argument that Rscript passes and source()
## does not, so they cannot be sourced from the editor. This file calls the
## same library functions directly, with the same arguments the entry points
## would have used. It is a convenience wrapper, not a reimplementation: if it
## disagrees with `Rscript scripts/check.R`, the entry point is right.
##
## Input : raw_data_deposit/<one>.csv   (written by pipeline/03_export.R)
## Output: predictions/<team_id>_T1_<entry>_v1.csv, metadata.json refreshed,
##         metadata_check_report.txt
##
## Before running for a new submission, edit metadata.json:
##   "entry"  — anything other than the previous run, or the file is overwritten
##   "models" — the exact identifier from the batch logs
## ---------------------------------------------------------------------------

if (!file.exists("metadata.json") || !dir.exists("scripts")) {
  stop("Working directory is '", getwd(), "', which is not the repository root.",
       "\nSession -> Set Working Directory -> To Source File Location.",
       call. = FALSE)
}

suppressPackageStartupMessages({
  library(jsonlite); library(digest)
  library(dplyr); library(readr); library(stringr); library(purrr); library(tidyr)
})

## --- 1. locate the raw export -----------------------------------------------
csvs <- list.files("raw_data_deposit", pattern = "\\.csv$", full.names = TRUE,
                   ignore.case = TRUE)
if (length(csvs) == 0L) {
  stop("No CSV in raw_data_deposit/. Run pipeline/03_export.R first.", call. = FALSE)
}
if (length(csvs) > 1L) {
  stop("Multiple CSVs in raw_data_deposit/:\n  ",
       paste(basename(csvs), collapse = "\n  "),
       "\nLeave exactly one.", call. = FALSE)
}
input <- csvs[1]

## --- 2. name the output from metadata.json ----------------------------------
meta  <- fromJSON("metadata.json")
team  <- meta$team_id
entry <- if (is.null(meta$entry) || !nzchar(meta$entry)) "primary" else meta$entry
if (is.null(team)) stop("metadata.json has no team_id.", call. = FALSE)
output <- file.path("predictions", sprintf("%s_T1_%s_v1.csv", team, entry))

message("Reading  ", input)
message("Writing  ", output)
message("Model declared in metadata.json: ", paste(meta$models, collapse = ", "))
if (file.exists(output)) {
  message("[!!] ", basename(output), " exists and will be overwritten. ",
          "Change \"entry\" in metadata.json to keep the previous submission.")
}

## --- 3. clean ---------------------------------------------------------------
source("scripts/lib/clean_lib.R")
clean_submission(input, output)

## --- 4. refresh the SHA-256 manifest ----------------------------------------
## manifest.R self-executes `update_manifest(.root)` at the bottom unless
## `.manifest_sourced` already exists — and `.root` is empty when the file is
## sourced rather than run by Rscript, which is why the unguarded version failed
## with "Argument hat Länge 0". clean.R sets the same flag for the same reason.
.manifest_sourced <- TRUE
source("scripts/manifest.R")            # defines update_manifest(), runs nothing
tryCatch(update_manifest("."),
         error = function(e) message("manifest: skipped (", conditionMessage(e), ")"))

## --- 5. check ---------------------------------------------------------------
source("scripts/lib/check_lib.R")
res <- check_repo(".")

if (any(res$status == "FAIL")) {
  message("\n[FAIL] Fix the items above, then Source this file again.")
} else if (any(res$status == "WARN")) {
  message("\n[ok] No failures. Read the warnings before submitting.")
} else {
  message("\n[ok] All checks passed.")
}

invisible(res)
