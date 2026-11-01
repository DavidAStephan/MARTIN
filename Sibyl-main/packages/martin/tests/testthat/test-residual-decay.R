# Tests for the residual-decay extension that lets solve_martin handle
# horizons past the historical data end.

# Helper duplicated from test-regression-against-bimets.R to keep this
# file self-contained.
bimets_baseline_reference <- function(data, tsrange) {
  model <- load_martin(data, variant = "af", estimate = TRUE)
  ca <- lapply(model$behaviorals, function(b) b$residuals)
  ca <- ca[!vapply(ca, is.null, logical(1))]
  model <- bimets::SIMULATE(
    model,
    TSRANGE            = tsrange,
    ConstantAdjustment = ca,
    simConvergence     = 1e-6,
    simIterLimit       = 100
  )
  simulation_to_tibble(model, scenario = "bimets_reference")
}

test_that("extend_residual_with_decay() is a no-op when horizon is in-range", {
  ts <- bimets::TIMESERIES(1:10, START = c(2000, 1), FREQ = 4)
  out <- martin:::extend_residual_with_decay(ts, end_year = 2001,
                                              end_quarter = 1)
  expect_equal(as.numeric(out), as.numeric(ts))
  expect_equal(stats::tsp(out), stats::tsp(ts))
})

test_that("extend_residual_with_decay() applies *-0.5 per quarter past end", {
  ts <- bimets::TIMESERIES(c(0, 0, 0, 1.0), START = c(2000, 1), FREQ = 4)
  # ts ends 2000Q4 with value 1.0; extend by 4 quarters
  out <- martin:::extend_residual_with_decay(ts, end_year = 2001,
                                              end_quarter = 4)
  expect_equal(
    as.numeric(out),
    c(0, 0, 0, 1.0, -0.5, 0.25, -0.125, 0.0625)
  )
  # Check the ts time labels still align with quarters
  expect_equal(stats::tsp(out)[2], 2001.75)
})

test_that("extend_residual_with_decay() seeds from last non-NA value", {
  # NA tail; should reach back to the last real value
  vals <- c(0, 0, 0.4, NA, NA)
  ts <- bimets::TIMESERIES(vals, START = c(2000, 1), FREQ = 4)
  out <- martin:::extend_residual_with_decay(ts, end_year = 2001,
                                              end_quarter = 2)
  # ts already runs through 2001Q1 (length 5); extend by 1 quarter to 2001Q2
  expect_equal(length(as.numeric(out)), 6L)
  # The last in-vector real value is 0.4 at 2000Q3; the 6th cell is 2001Q2,
  # which is 3 quarters past 2000Q3 → 0.4 * (-0.5)^3 = -0.05
  # But the seed is the LAST non-NA value, and the function extends past
  # the ts end-time, so the appended cell at 2001Q2 has step=1: -0.5 * 0.4 = -0.2
  expect_equal(tail(as.numeric(out), 1), -0.2)
})

test_that("extend_residual_with_decay() handles all-NA input gracefully", {
  ts <- bimets::TIMESERIES(rep(NA_real_, 4), START = c(2000, 1), FREQ = 4)
  out <- martin:::extend_residual_with_decay(ts, end_year = 2001,
                                              end_quarter = 4)
  # Seed = 0, so all extension cells are also 0
  expect_equal(tail(as.numeric(out), 4), rep(0, 4))
})

test_that("extend_residual_with_decay() returns NULL for NULL input", {
  expect_null(martin:::extend_residual_with_decay(NULL, 2025, 4))
})

test_that("decay extension does not change in-range simulation output", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()))

  data <- read_fixture()
  # In-range horizon (matches what the regression test uses) — the
  # extension should be a no-op for these residuals, so the solve must
  # produce the same numbers as before this change.
  reference <- bimets_baseline_reference(data, c(2010, 1, 2019, 3))
  sibyl <- solve_martin(database = data, adjustments = NULL,
                        horizon = c("2010Q1", "2019Q3"))
  for (var in c("Y", "RC", "GNE", "LUR", "PTM", "NCR")) {
    expect_equal(
      dplyr::filter(sibyl,     variable == var)$value,
      dplyr::filter(reference, variable == var)$value,
      tolerance = 1e-8,
      info = paste("post-decay-extension drift in", var)
    )
  }
})

