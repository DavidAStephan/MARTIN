# LUR-gap walkthrough — close the labour-market gap with add-factors.
#
# Context. After re-estimation through 2025Q2, the baseline projection
# matches actuals for NCR (4.5% vs actual 4.35%), PTM (149 vs ~140), and
# real GDP (590k vs ~588k) — but LUR stays stuck at 5.6% versus actual
# ~4.0%. That's a 1.6pp gap. The labour market behavioural equations
# can't pick this up from coefficient updates alone — it's a structural
# shift in employment/participation that the model's reduced-form
# representation doesn't capture.
#
# This is exactly what add-factors are for. A competent forecaster
# (or LLM) reading the latest LFS data would write a narrative like:
#
#   "Employment growth has been persistently stronger than the model
#    predicts since the post-COVID reopening — possibly reflecting
#    structural changes in labour-force attachment (long-COVID exits,
#    care economy growth, immigration composition). We expect this to
#    persist through 2025."
#
# And construct an add-factor on the LE equation pushing employment up
# enough to bring LUR down to observed levels. This script does that
# manually (no API key required) and reports the result.
#
# Run:
#   Rscript scripts/lur_gap_walkthrough.R
#
# Output: scripts/output/lur_gap_walkthrough.txt + stdout.

suppressPackageStartupMessages({
  for (p in c("judgement", "martin", "nowcast", "sibyldata")) {
    pkgload::load_all(file.path("packages", p), quiet = TRUE)
  }
})

dir.create("scripts/output", showWarnings = FALSE, recursive = TRUE)
log_path <- "scripts/output/lur_gap_walkthrough.txt"
log_con  <- file(log_path, "w")
say <- function(...) {
  msg <- paste0(..., "\n")
  cat(msg)
  cat(msg, file = log_con, append = TRUE)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

say("=== LUR-gap walkthrough ===")
say("")
say("NARRATIVE (what a forecaster / LLM would write):")
say("")
say(strwrap(paste(
  "Employment growth has been persistently stronger than the model",
  "predicts since the post-COVID reopening — possibly reflecting",
  "structural changes in labour-force attachment (long-COVID exits,",
  "care-economy growth, immigration composition). We expect this to",
  "persist through 2025. Translation: positive add-factor on LE's",
  "residual through 2020Q1-2025Q4 that compounds to ~1.6 % higher",
  "employment by end-2025 (= ~1.6 pp lower unemployment rate)."
), width = 70, indent = 2L, exdent = 2L))
say("")

# ---------------------------------------------------------------------------
# 1. Load the same database the targets pipeline uses
# ---------------------------------------------------------------------------
say("Loading database from targets cache ...")
targets::tar_load(database_with_handover)
targets::tar_load(baseline)
targets::tar_load(estimation_end)
targets::tar_load(horizon)
say(sprintf("  database vars: %d  horizon: %s..%s  estimation_end: %s",
            length(database_with_handover), horizon[1], horizon[2],
            estimation_end %||% "NULL (frozen)"))
say("")

# ---------------------------------------------------------------------------
# 2. Construct the LUR add-factor
# ---------------------------------------------------------------------------
# In MARTIN, LF is an identity (LF = LE / (1 - LUR/100)) and LUR has its
# own behavioural equation:
#
#   TSDELTA(LUR, 1) = c1 * (LOKLAG*lag(TSDELTA(LUR,1))
#                            - LUR_DUM*0.025*(lag(LUR,2) - lag(TLUR,1)))
#                   + c2 * ((LOG(Y) - LOG(lag(Y,2)))/2 - TY)
#                   + c3 * ((LOG(lag(RULC,2)) - LOG(lag(RULC,4)))/2)
#
# An add-factor on the LE equation alone doesn't move LUR — LF just
# rises in lockstep via the identity (verified: prior version of this
# script pushed LE up by ~140k and LF up by ~155k, LUR unchanged).
# We need to target LUR's residual directly.
#
# LUR's LHS is TSDELTA(LUR) — first difference. Each quarter's AF is
# pp/quarter, so a sustained -0.08 AF over 20 quarters cumulates to
# -1.6 pp on the LUR level — sufficient to close the 5.6 → 4.0 gap.
adj_horizon <- vapply(seq.int(2020, 2024), function(y) {
  paste0(y, "Q", 1:4)
}, character(4L))
adj_horizon <- as.vector(adj_horizon)
afs <- judgement::adjustment_list(
  judgement::adjustment(
    equation        = "LUR",
    horizon         = adj_horizon,
    value           = rep(-0.08, length(adj_horizon)),
    rationale       = paste(
      "Post-COVID structural labour-market tightening: unemployment",
      "fell faster than the model's Okun-law representation can",
      "explain. Long-COVID exits + composition shifts in immigration",
      "+ care-economy growth reduced effective labour supply.",
      "-0.08 pp per quarter on TSDELTA(LUR) over 20 quarters",
      "compounds to ~1.6 pp lower LUR level — closing the gap between",
      "baseline (5.6 %) and observed (~4.0 %)."
    ),
    channel         = "LUR residual; LE/LF identity follows",
    expected_effect = "LUR down ~1.6 pp by 2024Q4",
    confidence      = "medium",
    tail            = "decay_50",
    owner           = "lur-gap-walkthrough",
    round_id        = "lur-gap-2026Q2",
    source          = "human"
  )
)

say("Add-factor (proxy for LLM output):")
say(sprintf("  equation: LUR | %d quarters (%s..%s) | value -0.08 pp/qtr",
            length(adj_horizon), head(adj_horizon, 1), tail(adj_horizon, 1)))
say(sprintf("  tail: decay_50 (fades through 2025)"))
say("")

# ---------------------------------------------------------------------------
# 3. Solve adjusted scenario
# ---------------------------------------------------------------------------
say("Solving adjusted scenario ...")
adjusted <- suppressWarnings(suppressMessages(martin::solve_martin(
  database       = database_with_handover,
  adjustments    = afs,
  horizon        = horizon,
  coefficients   = if (is.null(estimation_end)) "frozen" else "reestimated",
  estimation_end = estimation_end,
  scenario       = "lur_adjusted"
)))
say(sprintf("  adjusted: %d rows, %d vars",
            nrow(adjusted), length(unique(adjusted$variable))))
say("")

# ---------------------------------------------------------------------------
# 4. Compare key variables: baseline vs adjusted
# ---------------------------------------------------------------------------
key_vars <- c("LE", "LF", "LUR", "LPR", "Y", "RC", "PTM", "NCR")
say("Last 4 quarters — baseline vs adjusted:")
say("")
fmt <- function(x) sprintf("%.3f", x)
for (v in key_vars) {
  b <- baseline$value[baseline$variable == v]
  a <- adjusted$value[adjusted$variable == v]
  q <- baseline$quarter[baseline$variable == v]
  if (length(b) == 0L || length(a) == 0L) next
  tail4 <- (length(q) - 3L):length(q)
  say(sprintf("  %-4s  %s",
              v,
              paste(sprintf("%s base=%s adj=%s",
                            q[tail4], fmt(b[tail4]), fmt(a[tail4])),
                    collapse = "  ")))
}
say("")

# ---------------------------------------------------------------------------
# 5. Did we close the gap?
# ---------------------------------------------------------------------------
lur_b <- baseline$value[baseline$variable == "LUR"]
lur_a <- adjusted$value[adjusted$variable == "LUR"]
qs    <- baseline$quarter[baseline$variable == "LUR"]
end_idx <- which(qs == "2025Q4")
mid_idx <- which(qs == "2023Q1")

say("Gap-closure summary on LUR:")
say(sprintf("  Baseline 2025Q4 LUR: %.2f %%", lur_b[end_idx]))
say(sprintf("  Adjusted 2025Q4 LUR: %.2f %% (target ~4.0%%)",
            lur_a[end_idx]))
say(sprintf("  Change:               %.2f pp", lur_a[end_idx] - lur_b[end_idx]))
say(sprintf("  Adjusted 2023Q1 LUR: %.2f %% (mid-window)", lur_a[mid_idx]))
say("")

# Sanity: was the impact concentrated in the adjustment window?
within <- qs %in% adj_horizon
say("LUR response within / outside the adjustment window:")
say(sprintf("  mean(LUR_adj - LUR_base) within 2020Q1-2024Q4: %+.3f pp",
            mean((lur_a - lur_b)[within])))
say(sprintf("  mean(LUR_adj - LUR_base) before 2020Q1:        %+.3f pp",
            mean((lur_a - lur_b)[!within & qs < "2020Q1"])))
say(sprintf("  mean(LUR_adj - LUR_base) after  2024Q4 (decay):%+.3f pp",
            mean((lur_a - lur_b)[!within & qs > "2024Q4"])))
say("")
say(sprintf("Report saved to %s", log_path))
close(log_con)

# Helper for nullable defaults — defined late so it doesn't pollute scope.
`%||%` <- function(a, b) if (is.null(a)) b else a
