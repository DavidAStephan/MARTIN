# Multi-narrative coherence check — confirm SIBYL's LLM judgement layer
# behaves coherently across qualitatively different narratives.
#
# Runs three independent narratives back-to-back through the full
# propose_with_refinement() loop and reports:
#
#   * which equation(s) the LLM picked for each narrative,
#   * the realised magnitudes on the relevant headline variables,
#   * the round-trip audit verdict,
#   * a diagnostic breakdown via judgement::diagnose_audit().
#
# Pass criteria (qualitative -- LLM is non-deterministic):
#   1. Each narrative produces a *distinct* set of adjustments (no
#      cross-contamination between rounds).
#   2. The dominant equation for each narrative matches the narrative's
#      stated channel (e.g. sticky inflation -> PTM; labour gap -> LUR
#      or TLUR; capex slowdown -> IBN/IBRE or similar).
#   3. Round-trip audit doesn't falsely "agree" when the narratives are
#      logically incompatible (e.g. you can't have falling unemployment
#      AND stable inflation without a cancelling AF).
#
# Run:
#   Rscript scripts/multi_narrative_coherence_check.R
#
# Output:
#   scripts/output/multi_narrative_coherence_check.txt  (full log)
#
# This script reuses the cached baseline + sensitivity_matrix from the
# main pipeline (tar_load(...)). The propose / solve / audit calls run
# fresh against the live Anthropic API for each narrative -- expect
# ~3-4 minutes per narrative with Sonnet for propose and Haiku for the
# rest, ~10 minutes total.

suppressPackageStartupMessages({
  for (p in c("judgement", "martin", "nowcast", "sibyldata")) {
    pkgload::load_all(file.path("packages", p), quiet = TRUE)
  }
  library(targets)
})

if (Sys.getenv("ANTHROPIC_API_KEY") == "") {
  stop("ANTHROPIC_API_KEY is not set. Add it to .Renviron.", call. = FALSE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

dir.create("scripts/output", showWarnings = FALSE, recursive = TRUE)
log_path <- "scripts/output/multi_narrative_coherence_check.txt"
log_con  <- file(log_path, "w")
say <- function(...) {
  msg <- paste0(..., "\n")
  cat(msg)
  cat(msg, file = log_con, append = TRUE)
}

say("=== Multi-narrative coherence check ===")
say(sprintf("Run started: %s", format(Sys.time())))
say("")

# Load pipeline inputs.
say("Loading pipeline cache (baseline, sensitivity_matrix, ...) ...")
tar_load(c(database_with_handover, baseline, horizon, estimation_end,
           sensitivity_matrix, round_id))
say(sprintf("  horizon: %s..%s | estimation_end: %s",
            horizon[1], horizon[2], estimation_end %||% "NULL"))
say(sprintf("  sensitivity matrix: %d rows, %d equations",
            nrow(sensitivity_matrix),
            length(unique(sensitivity_matrix$equation))))
say("")

solve_fn <- function(adj) {
  martin::solve_martin(
    database       = database_with_handover,
    adjustments    = adj,
    horizon        = horizon,
    coefficients   = if (is.null(estimation_end)) "frozen" else "reestimated",
    estimation_end = estimation_end,
    scenario       = "multi-narrative-probe"
  )
}

narratives <- list(
  sticky_inflation = paste(
    "Services inflation has been persistently sticky in our latest data.",
    "We think trimmed-mean inflation stays roughly 0.1 percentage points",
    "higher than baseline through 2025Q2, fading thereafter as labour-",
    "market slack opens up. No change to our view on the cash-rate path."
  ),
  labour_gap = paste(
    "Employment growth has been persistently stronger than the model",
    "predicts since the post-COVID reopening - possibly reflecting",
    "structural changes in labour-force attachment (long-COVID exits,",
    "care-economy growth, immigration composition). We expect this to",
    "persist, lowering the unemployment rate by roughly 1.5 percentage",
    "points below baseline through 2025Q4. No change to our view on",
    "the cash-rate path or inflation."
  ),
  capex_slowdown = paste(
    "Business investment intentions have softened materially in the",
    "latest NAB capex survey. We expect non-mining business investment",
    "to run roughly 4% below baseline through 2025Q4, with knock-on",
    "weakness for real GDP and labour demand. The RBA is expected to",
    "respond by cutting the cash rate ~50bp lower than baseline by",
    "end-2025."
  )
)

results <- list()
for (i in seq_along(narratives)) {
  name <- names(narratives)[i]
  narr <- narratives[[i]]
  say(sprintf("\n--- Narrative %d: %s ---", i, name))
  say(strwrap(narr, width = 76, indent = 2L, exdent = 2L) |>
        paste(collapse = "\n"))
  say("")

  t0 <- Sys.time()
  rd <- judgement::propose_with_refinement(
    narrative          = narr,
    baseline           = baseline,
    solve_fn           = solve_fn,
    max_iters          = 3L,
    round_id           = sprintf("%s-%s", round_id, name),
    sensitivity_matrix = sensitivity_matrix,
    model              = "claude-haiku-4-5",
    model_propose      = "claude-sonnet-4-6"
  )
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  say(sprintf("  Round took %.0fs, %d iter(s), best iter = %d",
              dt, length(rd$history), rd$best_iter))
  results[[name]] <- rd

  if (length(rd$adjustments) == 0L) {
    say("  No adjustments proposed.")
    next
  }
  tbl <- judgement::as_tibble_adjustments(rd$adjustments)
  eqs <- unique(tbl$equation)
  say(sprintf("  Final equations: %s", paste(eqs, collapse = ", ")))
  for (eq in eqs) {
    e <- tbl[tbl$equation == eq, ]
    say(sprintf("    %s @ %s..%s, values=%s",
                eq, min(e$quarter), max(e$quarter),
                paste(unique(format(round(e$value, 4))), collapse = ",")))
  }

  diag <- judgement::diagnose_audit(rd$audit, rd$projection, baseline)
  say(sprintf("  Audit overall_match: %s",
              attr(rd$audit, "overall_match") %||% "?"))
  cats <- table(diag$category)
  for (cat_name in names(cats)) {
    say(sprintf("    %-18s: %d", cat_name, cats[[cat_name]]))
  }
}

# Cross-narrative coherence checks
say("\n\n=== Cross-narrative coherence ===\n")

equations_used <- lapply(results, function(rd) {
  if (length(rd$adjustments) == 0L) return(character())
  unique(judgement::as_tibble_adjustments(rd$adjustments)$equation)
})
say("Equations chosen per narrative:")
for (name in names(equations_used)) {
  say(sprintf("  %-20s: %s", name,
              paste(equations_used[[name]], collapse = ", ")))
}
say("")

# Check 1: distinct narratives produce distinct equation sets
all_eq <- unique(unlist(equations_used))
say(sprintf("Distinct equations across all narratives: %d", length(all_eq)))
overlap <- length(intersect(equations_used$sticky_inflation,
                            equations_used$labour_gap))
say(sprintf("  sticky_inflation/labour_gap overlap: %d", overlap))
if (overlap > 0) {
  say("  WARNING: overlap suggests cross-contamination.")
}

# Check 2: dominant equation per narrative matches the narrative theme
say("")
say("Dominant-equation expectation check:")
expectations <- list(
  sticky_inflation = c("PTM", "P", "PC"),
  labour_gap       = c("LUR", "TLUR", "LE"),
  capex_slowdown   = c("IBN", "IBRE", "IBNDR", "NCR")
)
for (name in names(expectations)) {
  used <- equations_used[[name]]
  expected <- expectations[[name]]
  ok <- any(used %in% expected)
  say(sprintf("  %-20s: used [%s], expected one of [%s] -> %s",
              name,
              paste(used, collapse = ","),
              paste(expected, collapse = ","),
              if (ok) "OK" else "MISS"))
}

# Check 3: realised LUR diff for the labour_gap narrative
say("")
say("Magnitude sanity (labour_gap narrative):")
rd <- results$labour_gap
if (!is.null(rd) && !is.null(rd$projection)) {
  proj <- rd$projection
  lur_p <- tail(proj$value[proj$variable == "LUR"], 1)
  lur_b <- tail(baseline$value[baseline$variable == "LUR"], 1)
  say(sprintf("  LUR at 2025Q4: baseline=%.2fpp, scenario=%.2fpp, diff=%+.2fpp (target ~ -1.5pp)",
              lur_b, lur_p, lur_p - lur_b))
}

say("")
say(sprintf("Report saved to %s", log_path))
close(log_con)
