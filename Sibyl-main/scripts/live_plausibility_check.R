# Live-pipeline plausibility check.
#
# Runs the same economic sense-checks that test-plausibility.R applies to
# the fixture-input solve, but against the LIVE solve (live ABS/RBA/FRED
# pulled through sibyldata + merged with the fixture for historical
# completeness). The point is to catch silent regressions in the live
# pipeline that don't show up against the deterministic fixture.
#
# Run:
#   Rscript scripts/live_plausibility_check.R
#
# Exit status:
#   0 = all checks passed
#   1 = at least one check failed
#
# Output: scripts/output/live_plausibility_report.txt + stdout.

suppressPackageStartupMessages({
  for (p in c("judgement", "martin", "nowcast", "sibyldata")) {
    pkgload::load_all(file.path("packages", p), quiet = TRUE)
  }
})

dir.create("scripts/output", showWarnings = FALSE, recursive = TRUE)
log_path <- "scripts/output/live_plausibility_report.txt"
log_con  <- file(log_path, "w")
n_fail   <- 0L
n_pass   <- 0L

say <- function(...) {
  msg <- paste0(..., "\n")
  cat(msg)
  cat(msg, file = log_con, append = TRUE)
}

check_range <- function(var, vec, lo, hi) {
  if (is.null(vec) || length(vec) == 0L) {
    say(sprintf("  SKIP %-10s (not in projection)", var))
    return(invisible(NULL))
  }
  bad <- sum(vec < lo | vec > hi, na.rm = TRUE)
  n_total <- sum(!is.na(vec))
  status <- if (bad == 0L) "PASS" else "FAIL"
  if (status == "PASS") n_pass <<- n_pass + 1L else n_fail <<- n_fail + 1L
  say(sprintf(
    "  %s %-10s  obs=%d  range=[%.4f, %.4f]  expected=[%.2f, %.2f]%s",
    status, var, n_total,
    min(vec, na.rm = TRUE), max(vec, na.rm = TRUE),
    lo, hi,
    if (bad > 0L) sprintf("  (%d out-of-range)", bad) else ""
  ))
}

check_positive <- function(var, vec) {
  if (is.null(vec) || length(vec) == 0L) {
    say(sprintf("  SKIP %-10s (not in projection)", var))
    return(invisible(NULL))
  }
  bad <- sum(vec <= 0, na.rm = TRUE)
  status <- if (bad == 0L) "PASS" else "FAIL"
  if (status == "PASS") n_pass <<- n_pass + 1L else n_fail <<- n_fail + 1L
  say(sprintf("  %s %-10s positive  obs=%d%s",
              status, var, sum(!is.na(vec)),
              if (bad > 0L) sprintf("  (%d non-positive)", bad) else ""))
}

pluck <- function(projection, var) {
  vec <- projection$value[projection$variable == var]
  if (length(vec) == 0L) NULL else vec
}

# ---------------------------------------------------------------------------
say("=== SIBYL live plausibility check ===")
say("Loading targets pipeline ...")
res <- tryCatch(
  {
    targets::tar_load(baseline)
    baseline
  },
  error = function(e) {
    say("ERROR: ", conditionMessage(e))
    say("Run `targets::tar_make()` first to populate the cache.")
    NULL
  }
)
if (is.null(res)) {
  close(log_con)
  quit(status = 1L)
}

say(sprintf("Loaded baseline projection: %d rows, %d variables",
            nrow(res), length(unique(res$variable))))
say("")

# ---------------------------------------------------------------------------
say("--- Sanity: no NaN/Inf ---")
bad_finite <- sum(!is.finite(res$value))
if (bad_finite == 0L) {
  n_pass <- n_pass + 1L
  say("  PASS  0 non-finite values")
} else {
  n_fail <- n_fail + 1L
  say(sprintf("  FAIL  %d non-finite values", bad_finite))
}
say("")

# ---------------------------------------------------------------------------
say("--- Labour market ---")
check_range("LUR",  pluck(res, "LUR"),  2,    15)
check_range("LPR",  pluck(res, "LPR"),  50,   80)
check_positive("LE",   pluck(res, "LE"))
check_positive("LF",   pluck(res, "LF"))
check_positive("LPOP", pluck(res, "LPOP"))
say("")

# ---------------------------------------------------------------------------
say("--- Prices and inflation ---")
for (v in c("PTM", "P", "PC", "PG")) check_positive(v, pluck(res, v))
ptm <- pluck(res, "PTM")
if (!is.null(ptm) && length(ptm) > 4) {
  yoy_pct <- 100 * (log(ptm[-(1:4)]) - log(ptm[seq_len(length(ptm) - 4)]))
  check_range("DL4PTM_yoy", yoy_pct, -5, 15)
}
say("")

# ---------------------------------------------------------------------------
say("--- Interest rates and yield curve ---")
for (v in c("NCR", "N2R", "N10R", "NMR", "NBR")) {
  check_range(v, pluck(res, v), -2, 25)
}
say("")

# ---------------------------------------------------------------------------
say("--- State-space trends ---")
check_range("TLUR",  pluck(res, "TLUR"),  2, 12)
check_range("RSTAR", pluck(res, "RSTAR"), -5, 10)
check_range("PI_E",  pluck(res, "PI_E"),  -2, 12)
check_range("IBCR",  pluck(res, "IBCR"),  0,  1)
check_range("IBNDR", pluck(res, "IBNDR"), 0.1, 5)
check_range("IBNDRA",pluck(res, "IBNDRA"),0.5, 20)
say("")

# ---------------------------------------------------------------------------
say("--- Real activity ---")
check_positive("Y", pluck(res, "Y"))
y <- pluck(res, "Y")
if (!is.null(y) && length(y) > 4) {
  yoy <- 100 * (log(y[-(1:4)]) - log(y[seq_len(length(y) - 4)]))
  check_range("Y_yoy_growth", yoy, -10, 12)
}
rc <- pluck(res, "RC"); gne <- pluck(res, "GNE")
if (!is.null(rc) && !is.null(gne)) {
  share <- rc / gne
  check_range("RC/GNE share", share, 0.45, 0.70)
}
say("")

# ---------------------------------------------------------------------------
say("--- Exchange rates ---")
check_range("NUSD", pluck(res, "NUSD"), 0.3, 1.5)
check_range("NTWI", pluck(res, "NTWI"), 30,  120)
say("")

# ---------------------------------------------------------------------------
say("=== SUMMARY ===")
say(sprintf("  Pass: %d", n_pass))
say(sprintf("  Fail: %d", n_fail))
say(sprintf("Report saved to %s", log_path))
close(log_con)

if (n_fail > 0L) quit(status = 1L)
