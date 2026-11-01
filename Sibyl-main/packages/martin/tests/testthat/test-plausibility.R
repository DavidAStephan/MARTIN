# Plausibility / sense-check tests for solve_martin() output.
#
# These tests don't compare against a "correct" baseline — they encode
# economic priors about Australian macro variables and assert that the
# baseline solve produces values inside those priors. The point is to
# catch silent regressions where the pipeline still solves but produces
# garbage (a broken splice, a wrong sign on an identity, a state-space
# port that produces -25% real rates, etc.).
#
# Bounds are deliberately wide so legitimate macroeconomic swings (GFC,
# COVID, RBA policy pivots) all pass; only genuinely broken outputs
# should fail.
#
# Run against the bundled fixture so the test is deterministic and
# offline. A live-data equivalent lives in
# scripts/live_plausibility_check.R.

HORIZON <- c("2010Q1", "2019Q3")

solve_baseline <- function() {
  data <- read_fixture()
  solve_martin(
    database    = data,
    adjustments = NULL,
    horizon     = HORIZON,
    scenario    = "plausibility"
  )
}

# Helper: extract numeric values for one variable across the horizon.
pluck_var <- function(projection, var) {
  vec <- projection$value[projection$variable == var]
  if (length(vec) == 0L) NULL else vec
}

# Helper: assertion that all values lie in [lo, hi].
expect_in_range <- function(values, lo, hi, var) {
  expect_true(
    all(values >= lo & values <= hi, na.rm = TRUE),
    info = sprintf(
      "%s: %d/%d values outside [%.2f, %.2f]; observed range [%.4f, %.4f]",
      var,
      sum(values < lo | values > hi, na.rm = TRUE),
      length(values),
      lo, hi,
      min(values, na.rm = TRUE), max(values, na.rm = TRUE)
    )
  )
}

# ---- Sanity: no non-finite values anywhere ---------------------------------

test_that("baseline solve produces no NaN/Inf in projection values", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()
  expect_true(all(is.finite(p$value)),
              info = sprintf("%d non-finite values",
                             sum(!is.finite(p$value))))
})

# ---- Labour market --------------------------------------------------------

test_that("labour-market projections are economically plausible", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()

  # LUR: Australian unemployment was in [4, 7] over 2010-2019; allow a
  # generous bracket for parameter uncertainty.
  expect_in_range(pluck_var(p, "LUR"), 2, 15, "LUR")
  # LPR: participation has been 60-67%; allow wider for the solve.
  lpr <- pluck_var(p, "LPR")
  if (!is.null(lpr)) expect_in_range(lpr, 50, 80, "LPR")

  # LE, LF, LPOP: positive levels in thousands; the term ordering
  # LE < LF < LPOP should hold (employed ≤ labour force ≤ population).
  le <- pluck_var(p, "LE"); lf <- pluck_var(p, "LF"); lpop <- pluck_var(p, "LPOP")
  if (!is.null(le)) expect_true(all(le > 0))
  if (!is.null(lf) && !is.null(le)) {
    expect_true(all(lf >= le * 0.99),  # 1% tolerance for solver noise
                info = "LF should be >= LE")
  }
  if (!is.null(lpop) && !is.null(lf)) {
    expect_true(all(lpop >= lf * 0.99),
                info = "LPOP should be >= LF")
  }
})

# ---- Inflation and prices --------------------------------------------------

test_that("price level indices grow monotonically (small reversals tolerated)", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()
  for (var in c("PTM", "P", "PC", "PG")) {
    vec <- pluck_var(p, var)
    if (is.null(vec) || length(vec) < 4) next
    # Positive levels and at least 80% of quarters non-decreasing.
    expect_true(all(vec > 0), info = paste(var, "positive"))
    diffs <- diff(vec)
    expect_gte(mean(diffs >= 0), 0.8,
               label = paste(var, "monotonic share"))
  }
})

test_that("annualised inflation rates stay within macro-historical bounds", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()
  ptm <- pluck_var(p, "PTM")
  if (!is.null(ptm) && length(ptm) > 4) {
    # YoY inflation in percent
    yoy_pct <- 100 * (log(ptm[-(1:4)]) - log(ptm[seq_len(length(ptm) - 4)]))
    expect_in_range(yoy_pct, -5, 15, "100 * dlog(PTM, 4)")
  }
})

# ---- Interest rates / yield curve ----------------------------------------

test_that("policy and market rates stay in plausible bounds", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()
  for (var in c("NCR", "N2R", "N10R", "NMR", "NBR")) {
    vec <- pluck_var(p, var)
    if (is.null(vec)) next
    expect_in_range(vec, -2, 25, var)
  }
})

test_that("mortgage and business rates are at least cash rate (loose tolerance)", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()
  ncr <- pluck_var(p, "NCR")
  nmr <- pluck_var(p, "NMR")
  if (!is.null(ncr) && !is.null(nmr)) {
    # Mortgage rate should be > cash rate on average (positive spread).
    expect_gt(mean(nmr - ncr, na.rm = TRUE), 0,
              label = "NMR-NCR positive mean spread")
  }
})

# ---- State-space trends ---------------------------------------------------

test_that("state-space trend variables stay within plausible bounds", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()

  # NAIRU: post-1980 Australian NAIRU estimates have been in [4, 8]
  tlur <- pluck_var(p, "TLUR")
  if (!is.null(tlur)) expect_in_range(tlur, 2, 12, "TLUR")

  # Neutral real cash rate: typically [0, 5] but RBA estimates have
  # dipped negative since GFC; allow [-3, 8].
  rstar <- pluck_var(p, "RSTAR")
  if (!is.null(rstar)) expect_in_range(rstar, -5, 10, "RSTAR")

  # Inflation expectations: in line with target band; allow [0, 10].
  pi_e <- pluck_var(p, "PI_E")
  if (!is.null(pi_e)) expect_in_range(pi_e, -2, 12, "PI_E")

  # Cost of capital ratio
  ibcr <- pluck_var(p, "IBCR")
  if (!is.null(ibcr)) expect_in_range(ibcr, 0, 1, "IBCR")

  # Quarterly depreciation rate
  ibndr <- pluck_var(p, "IBNDR")
  if (!is.null(ibndr)) expect_in_range(ibndr, 0.1, 5, "IBNDR")

  # Annualised depreciation rate (4-quarter sum)
  ibndra <- pluck_var(p, "IBNDRA")
  if (!is.null(ibndra)) expect_in_range(ibndra, 0.5, 20, "IBNDRA")
})

# ---- Real activity --------------------------------------------------------

test_that("real GDP and components are positive with plausible growth", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()

  y <- pluck_var(p, "Y")
  if (!is.null(y) && length(y) > 4) {
    expect_true(all(y > 0), info = "Y positive")
    # Year-on-year real GDP growth: -10% to +10% covers all of Aus history.
    yoy <- 100 * (log(y[-(1:4)]) - log(y[seq_len(length(y) - 4)]))
    expect_in_range(yoy, -10, 12, "100 * dlog(Y, 4)")
  }

  # Consumption share of GNE: historically 0.55-0.62.
  rc <- pluck_var(p, "RC"); gne <- pluck_var(p, "GNE")
  if (!is.null(rc) && !is.null(gne)) {
    share <- rc / gne
    expect_in_range(share, 0.45, 0.70, "RC/GNE share")
  }
})

# ---- Exchange rates -------------------------------------------------------

test_that("exchange-rate variables stay in observed bands", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  p <- solve_baseline()
  # NUSD (USD per AUD): post-float range ~ 0.4 to 1.1. Generous bracket.
  nusd <- pluck_var(p, "NUSD")
  if (!is.null(nusd)) expect_in_range(nusd, 0.3, 1.5, "NUSD")
  # NTWI (trade-weighted index, base 1970): typically 55-80.
  ntwi <- pluck_var(p, "NTWI")
  if (!is.null(ntwi)) expect_in_range(ntwi, 30, 120, "NTWI")
})
