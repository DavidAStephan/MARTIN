# End-to-end forecast-round walkthrough — plumbing test.
#
# Exercises the full data-to-projection workflow without the LLM (which
# requires ANTHROPIC_API_KEY). Instead of letting judgement::propose_
# adjustments() call the Claude API, we construct manual add-factors
# that approximate what a competent LLM would output for a given
# narrative, then run the rest of the chain:
#
#   narrative → manual add-factors → solve_martin(with adjustments)
#                                  → compare vs baseline projection
#                                  → print diff report
#
# To run with the real LLM, set ANTHROPIC_API_KEY and use `tar_make()`
# instead — the _targets.R `proposed_adjustments` target will call
# judgement::propose_adjustments() when the key is present.
#
# Run:
#   Rscript scripts/end_to_end_round_walkthrough.R
#
# Output: scripts/output/round_walkthrough_report.txt + stdout.

suppressPackageStartupMessages({
  for (p in c("judgement", "martin", "nowcast", "sibyldata")) {
    pkgload::load_all(file.path("packages", p), quiet = TRUE)
  }
})

dir.create("scripts/output", showWarnings = FALSE, recursive = TRUE)
log_path <- "scripts/output/round_walkthrough_report.txt"
log_con  <- file(log_path, "w")

say <- function(...) {
  msg <- paste0(..., "\n")
  cat(msg)
  cat(msg, file = log_con, append = TRUE)
}

# ---------------------------------------------------------------------------
# 1. The narrative — what a forecaster would write
# ---------------------------------------------------------------------------
narrative <- paste(
  "Services inflation has been persistently sticky in our latest data.",
  "We think trimmed-mean inflation stays roughly 0.1 percentage points",
  "higher than baseline through 2018Q3, fading thereafter as labour-",
  "market slack opens up. No change to our view on the cash-rate path."
)

say("=== End-to-end forecast-round walkthrough ===")
say("")
say("NARRATIVE:")
say("")
say(strwrap(narrative, width = 70, indent = 2L, exdent = 2L))
say("")

# ---------------------------------------------------------------------------
# 2. Manual add-factors that approximate the LLM's output
# ---------------------------------------------------------------------------
# A competent LLM, given the narrative above, would propose add-factors
# on PTM's behavioural equation: small upward shocks for 2017-2018 that
# decay after 2018Q3. The actual judgement::propose_adjustments() call
# would produce something like this with rationale + confidence; we
# hand-construct the equivalent to test the rest of the chain.

adj_horizon <- c("2017Q1", "2017Q2", "2017Q3", "2017Q4",
                 "2018Q1", "2018Q2", "2018Q3")
# PTM's equation LHS is TSDELTALOG(PTM, 1) — a log-change rate. A 0.001
# add-factor on the residual is +0.1pp quarterly inflation = +0.4pp
# annualised. (A "+0.1pp" intuition in the narrative refers to the
# annualised rate; on the log-change LHS this is 0.001.)
manual_adjustments <- judgement::adjustment_list(
  judgement::adjustment(
    equation        = "PTM",
    horizon         = adj_horizon,
    value           = rep(0.001, length(adj_horizon)),
    rationale       = paste(
      "Services inflation has been persistently sticky in the latest",
      "data — shocking PTM's residual up by 0.001 on TSDELTALOG (~0.4pp",
      "annualised inflation) captures the narrative's view that",
      "trimmed-mean inflation stays above baseline through 2018Q3."
    ),
    channel         = "supply-side cost pass-through",
    expected_effect = "Higher PTM through 2018Q3, fading via decay tail",
    confidence      = "medium",
    tail            = "decay_50",
    owner           = "manual-walkthrough",
    round_id        = "walkthrough-2026Q2",
    source          = "human"
  )
)

say("MANUAL ADD-FACTORS (proxy for LLM output):")
say("")
adj_df <- judgement::as_tibble_adjustments(manual_adjustments)
say(paste(capture.output(print(adj_df, n = nrow(adj_df))), collapse = "\n"))
say("")

# ---------------------------------------------------------------------------
# 3. Load the live database via targets
# ---------------------------------------------------------------------------
say("Loading live database from targets cache ...")
db <- tryCatch(
  { targets::tar_load(database_with_handover); database_with_handover },
  error = function(e) {
    say("ERROR: ", conditionMessage(e),
        "  — run `targets::tar_make()` first.")
    NULL
  }
)
if (is.null(db)) { close(log_con); quit(status = 1L) }

say(sprintf("Database has %d MARTIN variables.", length(db)))
say("")

# ---------------------------------------------------------------------------
# 4. Solve baseline (no adjustments) and with adjustments
# ---------------------------------------------------------------------------
horizon <- c("2010Q1", "2018Q3")
say(sprintf("Solving baseline over %s..%s ...", horizon[1], horizon[2]))
baseline <- suppressWarnings(suppressMessages(martin::solve_martin(
  database = db, adjustments = NULL,
  horizon = horizon, scenario = "baseline"
)))

say("Solving with manual adjustments ...")
adjusted <- suppressWarnings(suppressMessages(martin::solve_martin(
  database = db, adjustments = manual_adjustments,
  horizon = horizon, scenario = "with_adjustments"
)))

say(sprintf("  baseline:  %d rows, %d vars",
            nrow(baseline), length(unique(baseline$variable))))
say(sprintf("  adjusted:  %d rows, %d vars",
            nrow(adjusted), length(unique(adjusted$variable))))
say("")

# ---------------------------------------------------------------------------
# 5. Compare key variables — adjustment should propagate
# ---------------------------------------------------------------------------
compare_var <- function(var) {
  b <- baseline$value[baseline$variable == var]
  a <- adjusted$value[adjusted$variable == var]
  q <- baseline$quarter[baseline$variable == var]
  if (length(b) == 0L || length(a) == 0L) {
    say(sprintf("  %s not in projection", var))
    return(invisible(NULL))
  }
  diffs <- a - b
  say(sprintf(
    "  %-6s  base mean=%.4f  adj mean=%.4f  diff mean=%.4f  max|diff|=%.4f",
    var, mean(b, na.rm = TRUE), mean(a, na.rm = TRUE),
    mean(diffs, na.rm = TRUE), max(abs(diffs), na.rm = TRUE)
  ))
  invisible(NULL)
}

say("Effect on key variables (adjusted vs baseline):")
say("")
for (v in c("PTM", "DL4PTM", "NCR", "LUR", "RC", "Y", "NMR", "PI_E", "TLUR")) {
  compare_var(v)
}
say("")

# ---------------------------------------------------------------------------
# 6. Plausibility: did the adjustment do what we expected?
# ---------------------------------------------------------------------------
# We shocked PTM's residual upward; PTM in the adjusted scenario should
# be higher than baseline on average. Persistence in the equation means
# the impact persists past 2018Q3 too (cumulative log-change).
ptm_b <- baseline$value[baseline$variable == "PTM"]
ptm_a <- adjusted$value[adjusted$variable == "PTM"]
ptm_q <- baseline$quarter[baseline$variable == "PTM"]
# ptm_q is a "yyyyQq" character vector; lexicographic ordering matches
# chronological ordering on quarter strings.
within_horizon <- ptm_q %in% adj_horizon

say("SANITY CHECK on PTM (the variable we shocked):")
mean_diff_within  <- mean((ptm_a - ptm_b)[within_horizon], na.rm = TRUE)
mean_diff_outside <- mean((ptm_a - ptm_b)[!within_horizon], na.rm = TRUE)
say(sprintf("  mean(PTM_adj - PTM_base) within 2017Q1-2018Q3: %.4f", mean_diff_within))
say(sprintf("  mean(PTM_adj - PTM_base) outside that range:    %.4f", mean_diff_outside))
ok <- mean_diff_within > 0 && mean_diff_within > abs(mean_diff_outside)
say(sprintf("  %s: shock is concentrated within the horizon window",
            if (ok) "PASS" else "FAIL"))
say("")

# ---------------------------------------------------------------------------
# 7. What the LLM step would do
# ---------------------------------------------------------------------------
say("--- LLM steps (skipped without ANTHROPIC_API_KEY) ---")
if (nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
  say("ANTHROPIC_API_KEY is set — running propose_adjustments() ...")
  proposed <- tryCatch(
    judgement::propose_adjustments(
      narrative = narrative,
      baseline  = baseline,
      round_id  = "walkthrough-2026Q2",
      model     = "claude-haiku-4-5"
    ),
    error = function(e) {
      say("propose_adjustments ERROR: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(proposed)) {
    say(sprintf("LLM proposed %d adjustment(s).", length(proposed)))
    if (length(proposed)) {
      print(judgement::as_tibble_adjustments(proposed))
    }
  }
  say("")
  say("Running describe_projection() ...")
  desc <- tryCatch(
    judgement::describe_projection(
      projection = adjusted, baseline = baseline,
      narrative = narrative, model = "claude-haiku-4-5"
    ),
    error = function(e) {
      say("describe_projection ERROR: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(desc)) {
    say("Description:")
    say(strwrap(desc, width = 70, indent = 2L, exdent = 2L))
  }
} else {
  say(paste(
    "ANTHROPIC_API_KEY is not set. To exercise the LLM steps:",
    "",
    "  export ANTHROPIC_API_KEY=sk-ant-...",
    "  Rscript scripts/end_to_end_round_walkthrough.R",
    "",
    "Or set the key in .Renviron (gitignored) and restart R.",
    sep = "\n"
  ))
}
say("")
say(sprintf("Report saved to %s", log_path))
close(log_con)
