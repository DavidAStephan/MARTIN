# nowcast_handover() + splice_handover() against the bundled MARTIN fixture.
#
# Strategy: chop the last 2 quarters off each handover variable, nowcast 2
# quarters ahead, splice back, and compare against the held-out actuals.
#
# The bar isn't "forecast accuracy" (impossible to guarantee with auto-ARIMA
# on whatever data lands in the test) but "did the pipeline run, produce
# the expected shape, and recover values in the right order of magnitude".

# Build a small synthetic database (3 variables, 80 quarters) so the tests
# don't depend on martin being installed. Real fixture coverage comes from
# the regression test in martin/, which solves the model end-to-end.
synth_database <- function(n = 80, start = c(2000, 1)) {
  set.seed(42)
  trend <- seq_len(n)
  walk  <- cumsum(stats::rnorm(n, sd = 0.5))
  list(
    Y     = bimets::TIMESERIES(100 + 0.5 * trend + walk,
                               START = start, FREQ = 4),
    LUR   = bimets::TIMESERIES(5 + 0.3 * sin(trend / 4) +
                                 cumsum(stats::rnorm(n, sd = 0.1)),
                               START = start, FREQ = 4),
    PTM   = bimets::TIMESERIES(0.6 + 0.02 * stats::rnorm(n),
                               START = start, FREQ = 4)
  )
}

test_that("nowcast_handover() returns the canonical shape", {
  db <- synth_database()
  out <- nowcast_handover(db, h = 2, method = "naive",
                          variables = c("Y", "LUR"))
  expect_s3_class(out, "tbl_df")
  expect_setequal(
    names(out),
    c("variable", "quarter", "central", "lower", "upper", "method")
  )
  expect_equal(nrow(out), 4L)  # 2 vars × 2 quarters
  expect_setequal(unique(out$variable), c("Y", "LUR"))
  expect_true(all(out$method == "naive"))
  expect_true(all(out$lower <= out$central))
  expect_true(all(out$central <= out$upper))
})

test_that("nowcast_handover() defaults to handover_variables() ∩ database", {
  # Only Y is in both the synth db and handover_variables() (LUR + PTM too)
  db <- synth_database()
  out <- nowcast_handover(db, h = 1, method = "naive")
  expect_setequal(unique(out$variable), c("Y", "LUR", "PTM"))
})

test_that("nowcast_handover() rejects too-short series", {
  short <- list(Y = bimets::TIMESERIES(1:5, START = c(2020, 1), FREQ = 4))
  expect_error(
    nowcast_handover(short, h = 2, method = "naive", variables = "Y"),
    "fewer than 8 observations"
  )
})

test_that("nowcast_handover() rejects missing handover variables", {
  db <- synth_database()
  expect_error(
    nowcast_handover(db, variables = c("Y", "NOT_THERE")),
    "missing handover variables"
  )
})

test_that("naive nowcast recovers the last observed value", {
  db <- synth_database()
  last_y <- as.numeric(db$Y)[length(as.numeric(db$Y))]
  out <- nowcast_handover(db, h = 2, method = "naive", variables = "Y")
  # Naive forecast is constant at the last observation
  expect_equal(out$central, c(last_y, last_y))
})

test_that("ARIMA nowcast on synthetic Y is in the right ballpark", {
  db <- synth_database()
  out <- nowcast_handover(db, h = 2, method = "arima", variables = "Y")
  # Y is roughly 100 + 0.5 * t around quarter 80; central forecast should be
  # in the same neighbourhood, not three orders of magnitude off.
  expect_true(all(out$central > 100 & out$central < 200))
})

test_that("splice_handover() writes central values into the database", {
  db <- synth_database()
  out <- nowcast_handover(db, h = 2, method = "naive",
                          variables = c("Y", "LUR"))
  spliced <- splice_handover(db, out)

  # Database extended by 2 quarters
  expect_equal(length(as.numeric(spliced$Y)),
               length(as.numeric(db$Y)) + 2L)
  # New cells equal the central forecast
  tail_y <- tail(as.numeric(spliced$Y), 2)
  expected <- out$central[out$variable == "Y"]
  expect_equal(tail_y, expected)
})

test_that("splice_handover() rejects forecasts for unknown variables", {
  db <- synth_database()
  bad <- tibble::tibble(
    variable = "NONEXISTENT",
    quarter  = tsibble::make_yearquarter(2020, 1),
    central  = 1.0,
    lower    = 0.5,
    upper    = 1.5,
    method   = "naive"
  )
  expect_error(splice_handover(db, bad), "no series for")
})

test_that("splice_handover() rejects malformed handover", {
  db <- synth_database()
  expect_error(splice_handover(db, tibble::tibble(variable = "Y")),
               "missing required columns")
})

# --- guards: interior NA, gaps, overwrite, non-finite ----------------------

test_that("nowcast rejects a series with an interior NA hole", {
  # A hole in the middle of the history would let fable fit through an
  # implicit gap and return an NA forecast. The conversion guard must stop.
  v <- as.numeric(synth_database()$Y)
  v[40] <- NA  # punch an interior hole
  db <- list(Y = bimets::TIMESERIES(v, START = c(2000, 1), FREQ = 4))
  expect_error(
    nowcast_handover(db, h = 2, method = "naive", variables = "Y"),
    "interior NA"
  )
})

test_that("nowcast tolerates trailing NAs (the benign ragged edge)", {
  v <- c(as.numeric(synth_database()$Y), NA, NA)
  db <- list(Y = bimets::TIMESERIES(v, START = c(2000, 1), FREQ = 4))
  out <- nowcast_handover(db, h = 2, method = "naive", variables = "Y")
  expect_equal(nrow(out), 2L)
  expect_true(all(is.finite(out$central)))
})

test_that("splice_handover() does not clobber observed cells by default", {
  db <- synth_database()
  last_y <- as.numeric(db$Y)[length(as.numeric(db$Y))]
  # Forecast aimed at the LAST observed quarter (a re-nowcast of a
  # provisional print). Default overwrite = FALSE leaves the observed value.
  lq <- last_observed_quarter(db$Y)
  ho <- tibble::tibble(
    variable = "Y", quarter = lq,
    central  = last_y + 999, lower = last_y + 998, upper = last_y + 1000,
    method   = "naive"
  )
  kept <- splice_handover(db, ho)
  n <- length(as.numeric(kept$Y))
  expect_equal(as.numeric(kept$Y)[n], last_y)  # untouched

  forced <- splice_handover(db, ho, overwrite = TRUE)
  expect_equal(as.numeric(forced$Y)[n], last_y + 999)  # overwritten
})

test_that("splice_handover() errors on a gap (sequencing bug)", {
  db <- synth_database()
  lq <- last_observed_quarter(db$Y)
  # Skip a quarter: jump two quarters past the last observation.
  gap_q <- lq + 2L
  ho <- tibble::tibble(
    variable = "Y", quarter = gap_q,
    central  = 1, lower = 0, upper = 2, method = "naive"
  )
  expect_error(splice_handover(db, ho), "gap")
})

test_that("splice_handover() refuses a non-finite central value", {
  db <- synth_database()
  lq <- last_observed_quarter(db$Y)
  ho <- tibble::tibble(
    variable = "Y", quarter = lq + 1L,
    central  = NA_real_, lower = NA_real_, upper = NA_real_, method = "naive"
  )
  expect_error(splice_handover(db, ho), "non-finite")
})

# Held-out evaluation against the bundled MARTIN fixture. This is the
# closest we get to "did the pipeline really work" in nowcast — chop, fit,
# forecast, compare.
test_that("nowcast recovers held-out actuals to within a wide tolerance", {
  skip_if_not_installed("martin")
  skip_if_not_installed("readxl")

  fixture <- martin::martin_data_fixture()
  skip_if_not(file.exists(fixture), "fixture missing")

  db <- martin::read_fixture()

  # Common handover vars that are present in the fixture
  vars <- intersect(handover_variables(), names(db))
  expect_true(length(vars) >= 10L, info = "fixture should cover most handover vars")

  # Chop the last 2 quarters off each handover variable and remember them
  held_out <- list()
  truncated_db <- db
  for (v in vars) {
    full <- as.numeric(db[[v]])
    n <- length(full)
    if (n < 12L) next
    held_out[[v]] <- full[(n - 1):n]
    # Truncate by reconstructing the ts
    start <- stats::tsp(db[[v]])[1]
    yr <- floor(start + 1e-9)
    q  <- round((start - yr) * 4 + 1)
    truncated_db[[v]] <- bimets::TIMESERIES(full[1:(n - 2)],
                                            START = c(yr, q), FREQ = 4)
  }

  vars <- names(held_out)
  expect_true(length(vars) >= 10L)

  out <- nowcast_handover(truncated_db, h = 2, method = "naive",
                          variables = vars)

  # Compare central forecasts vs held-out actuals. Naive forecast = last
  # observed value; for variables that drift, the error can be large in
  # absolute terms. Use percentage error with a *very* loose 30% threshold
  # and require at least 60% of variables to pass — this is a smoke test,
  # not a forecast-accuracy benchmark.
  hits <- vapply(vars, function(v) {
    actual <- held_out[[v]]
    forecast <- out$central[out$variable == v]
    rel_err <- abs(forecast - actual) / pmax(abs(actual), 1e-6)
    all(rel_err < 0.30)
  }, logical(1))
  pass_rate <- mean(hits)
  expect_gt(pass_rate, 0.60,
            label = sprintf("naive recovery pass rate (%.0f%%)",
                            pass_rate * 100))
})

test_that("bridge method returns the canonical shape for several variables", {
  skip_if_not_installed("martin")
  db <- martin::read_fixture()
  out <- nowcast_handover(db, h = 2, method = "bridge",
                          variables = c("RC", "NCR", "PTM"))
  expect_setequal(names(out),
                  c("variable", "quarter", "central", "lower", "upper",
                    "method"))
  expect_equal(nrow(out), 6L)  # 3 vars * 2 horizons
  expect_true(all(is.finite(out$central)))
  expect_true(all(out$method == "bridge"))
})

# --- bridge_monthly tests --------------------------------------------------

# Build a synthetic monthly indicator and a quarterly target with a known
# linear relationship: target = 2 * indicator_quarterly + noise.
make_synthetic_bridge <- function() {
  n_months <- 120L
  set.seed(42)
  ind_m <- 50 + cumsum(stats::rnorm(n_months, mean = 0.1, sd = 0.5))
  ind_ts <- bimets::TIMESERIES(ind_m, START = c(2010, 1), FREQ = 12)
  # Quarterly aggregation: mean of 3 monthly values
  ind_q <- sapply(seq.int(1L, n_months, by = 3L),
                  function(i) mean(ind_m[i:(i + 2)]))
  tgt_q <- 2 * ind_q + stats::rnorm(length(ind_q), 0, 0.3)
  tgt_ts <- bimets::TIMESERIES(tgt_q, START = c(2010, 1), FREQ = 4)
  list(target = tgt_ts, indicator = ind_ts)
}

test_that("bridge_monthly recovers a known growth relationship", {
  s <- make_synthetic_bridge()
  out <- nowcast_handover(
    database  = list(Y = s$target),
    h         = 2,
    method    = "bridge_monthly",
    variables = "Y",
    bridge_indicators  = list(Y = "HOURS"),
    monthly_indicators = list(HOURS = s$indicator)
  )
  expect_setequal(names(out),
                  c("variable", "quarter", "central", "lower", "upper",
                    "method"))
  expect_equal(nrow(out), 2L)
  # The bridge is now specified in GROWTH RATES: it chains predicted growth
  # onto the last observed target level, rather than predicting the level
  # directly from a (spurious) levels-on-levels regression. Since target ~=
  # 2 * indicator and the indicator is still drifting up, the Q+0 forecast
  # should sit near 2 * (recent indicator mean) and near the last observed
  # target level. Use level-aware (percentage) tolerances.
  ind_recent <- mean(tail(as.numeric(s$indicator), 6))
  expect_lt(abs(out$central[1] - 2 * ind_recent), 0.05 * (2 * ind_recent),
            label = "bridge_monthly Q+0 within 5% of 2*recent-indicator")
  last_tgt <- tail(as.numeric(s$target), 1)
  expect_lt(abs(out$central[1] - last_tgt), 0.10 * last_tgt)
  expect_true(all(is.finite(out$central)))
  expect_true(all(out$lower <= out$central & out$central <= out$upper))
  expect_true(all(out$method == "bridge_monthly[HOURS]"))
})

test_that("bridge_monthly partial-quarter point stays finite and bracketed", {
  # Drop the indicator's final months so the last indicator quarter is
  # partial; the partial-quarter widening path should still return a finite,
  # bracketed band.
  s <- make_synthetic_bridge()
  ind_v <- as.numeric(s$indicator)
  ind_trim <- bimets::TIMESERIES(ind_v[seq_len(length(ind_v) - 2L)],
                                 START = c(2010, 1), FREQ = 12)
  out <- nowcast_handover(
    database  = list(Y = s$target),
    h         = 2,
    method    = "bridge_monthly",
    variables = "Y",
    bridge_indicators  = list(Y = "HOURS"),
    monthly_indicators = list(HOURS = ind_trim)
  )
  expect_equal(nrow(out), 2L)
  expect_true(all(is.finite(out$central)))
  expect_true(all(out$lower <= out$central & out$central <= out$upper))
})

test_that("bridge_monthly falls back to ARIMA when indicator missing", {
  s <- make_synthetic_bridge()
  out <- nowcast_handover(
    database  = list(Y = s$target),
    h         = 2,
    method    = "bridge_monthly",
    variables = "Y",
    bridge_indicators  = list(Y = "NONEXISTENT"),
    monthly_indicators = list(HOURS = s$indicator)  # no NONEXISTENT key
  )
  expect_equal(nrow(out), 2L)
  expect_true(all(out$method == "arima"))
})

test_that("bridge_monthly errors when bridge_indicators or monthly_indicators missing", {
  s <- make_synthetic_bridge()
  expect_error(
    nowcast_handover(
      database = list(Y = s$target), h = 2,
      method = "bridge_monthly", variables = "Y"
    ),
    "bridge_indicators"
  )
})
