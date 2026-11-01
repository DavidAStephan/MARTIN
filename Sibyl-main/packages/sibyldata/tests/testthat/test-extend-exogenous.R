mk_ts <- function(vals, start = c(2020, 1)) {
  bimets::TIMESERIES(vals, START = start, FREQ = 4)
}

test_that("extend_exogenous() carries values forward by default", {
  db <- list(X = mk_ts(c(1, 2, 3, 4)))
  out <- extend_exogenous(db, end_quarter = "2021Q4")
  expect_equal(length(as.numeric(out$X)), 8L)
  # Tail four should all be 4 (carry from last observation)
  expect_equal(tail(as.numeric(out$X), 4), c(4, 4, 4, 4))
})

test_that("extend_exogenous() constant mode uses the supplied value", {
  db <- list(PI_TARGET = mk_ts(rep(2.5, 4)))
  out <- extend_exogenous(
    db, end_quarter = "2021Q4",
    rules = list(PI_TARGET = list(mode = "constant", value = 2.5))
  )
  expect_equal(as.numeric(out$PI_TARGET), rep(2.5, 8))
})

test_that("extend_exogenous() linear mode extrapolates the trend", {
  db <- list(TREND = mk_ts(c(1, 2, 3, 4)))
  out <- extend_exogenous(
    db, end_quarter = "2020Q4",
    rules = list(TREND = list(mode = "linear", lookback = 4))
  )
  # Slope = mean(diff(1,2,3,4)) = 1; extend by 0 quarters since we already
  # end at 2020Q4. Try a target past the end:
  out2 <- extend_exogenous(
    db, end_quarter = "2021Q2",
    rules = list(TREND = list(mode = "linear", lookback = 4))
  )
  expect_equal(as.numeric(out2$TREND), c(1, 2, 3, 4, 5, 6))
})

test_that("extend_exogenous() is a no-op when target is in-range", {
  db <- list(X = mk_ts(c(1, 2, 3, 4)))
  out <- extend_exogenous(db, end_quarter = "2020Q3")
  expect_equal(as.numeric(out$X), c(1, 2, 3, 4))
})

test_that("extend_exogenous() leaves unlisted variables alone", {
  db <- list(A = mk_ts(c(1, 2, 3, 4)),
             B = mk_ts(c(10, 20, 30, 40)))
  out <- extend_exogenous(
    db, end_quarter = "2021Q4",
    rules = list(A = list(mode = "carry"))
  )
  # A extended; B untouched
  expect_equal(length(as.numeric(out$A)), 8L)
  expect_equal(as.numeric(out$B), c(10, 20, 30, 40))
})

test_that("extend_exogenous() rejects malformed rules", {
  db <- list(X = mk_ts(1:4))
  expect_error(
    extend_exogenous(db, "2021Q1", rules = list(list(mode = "carry"))),
    "named list"
  )
})

test_that("extend_exogenous() composes with solve_martin future horizon", {
  skip_if_not_installed("martin")
  skip_if_not(file.exists(martin::martin_data_fixture()), "fixture missing")

  # Smoke test: extend a clean fixture forward and solve past data end.
  db <- martin::read_fixture()
  db_ext <- extend_exogenous(db, end_quarter = "2021Q4")
  result <- martin::solve_martin(
    db_ext, NULL, horizon = c("2020Q1", "2021Q4")
  )
  expect_gt(nrow(result), 100L)
  expect_true("Y" %in% unique(result$variable))
})
