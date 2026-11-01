# Verifies that the bimets wrapper around judgement::expand_adjustments()
# produces correctly-shaped bimets TIMESERIES objects.

mk <- function(...) {
  # PTM is a log_diff equation; defaults stay under the 0.02 per-quarter
  # ceiling enforced by judgement::validate_adjustment_bounds().
  defaults <- list(
    equation        = "PTM",
    horizon         = c("2026Q1", "2026Q2"),
    value           = c(0.01, 0.005),
    rationale       = "test fixture",
    tail            = "zero",
    confidence      = "medium",
    source          = "human"
  )
  do.call(judgement::adjustment, modifyList(defaults, list(...)))
}

test_that("to_constant_adjustment_list() returns an empty list for empty input", {
  out <- to_constant_adjustment_list(
    judgement::adjustment_list(),
    solve_range = c("2026Q1", "2027Q4")
  )
  expect_length(out, 0L)
  expect_type(out, "list")
})

test_that("to_constant_adjustment_list() wraps values in bimets TIMESERIES", {
  skip_if_not_installed("bimets")

  al <- judgement::adjustment_list(mk())
  out <- to_constant_adjustment_list(al, solve_range = c("2026Q1", "2027Q4"))

  expect_named(out, "PTM")
  expect_s3_class(out$PTM, "ts")
  # bimets TIMESERIES starts at 2026 Q1 (i.e. tsp[1] == 2026.0)
  expect_equal(stats::tsp(out$PTM)[1], 2026.0)
  expect_equal(stats::tsp(out$PTM)[3], 4)
  # 8 quarters: 2026Q1..2027Q4 inclusive
  expect_length(as.numeric(out$PTM), 8L)
  # First two cells are the explicit horizon values; rest are zero (zero tail)
  expect_equal(as.numeric(out$PTM), c(0.01, 0.005, 0, 0, 0, 0, 0, 0))
})

test_that("to_constant_adjustment_list() carries multiple equations through", {
  skip_if_not_installed("bimets")

  al <- judgement::adjustment_list(
    mk(equation = "PTM",
       horizon = c("2026Q1", "2026Q2"), value = c(0.01, 0.005)),
    mk(equation = "NCR",
       horizon = c("2026Q1"), value = 0.25,
       rationale = "Pre-emptive hike")
  )
  out <- to_constant_adjustment_list(al, solve_range = c("2026Q1", "2026Q4"))

  expect_setequal(names(out), c("PTM", "NCR"))
  expect_equal(as.numeric(out$NCR), c(0.25, 0, 0, 0))
  expect_equal(as.numeric(out$PTM), c(0.01, 0.005, 0, 0))
})
