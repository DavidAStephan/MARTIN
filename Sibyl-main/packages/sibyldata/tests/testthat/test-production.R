# Tests for the CES production-function calibration and efficiency trend
# (docs/martin_enhancements_plan.md, Workstream A). Uses a synthetic database
# so the test is independent of the martin fixture.

synth_db <- function(n = 80) {
  st <- c(2000, 1)
  mk <- function(v) bimets::TIMESERIES(v, START = st, FREQ = 4)
  t <- seq_len(n)
  list(
    Y     = mk(300000 * exp(0.006 * t)),
    KIBN  = mk(800000 * exp(0.005 * t)),
    KIBRE = mk(200000 * exp(0.007 * t)),
    LE    = mk(10000  * exp(0.004 * t)),
    LHPP  = mk(rep(33, n))
  )
}

test_that("ces_calibration returns sensible constants", {
  skip_if_not_installed("bimets")
  cal <- ces_calibration(synth_db())
  expect_equal(cal$sigma, 0.5)
  expect_equal(cal$theta_n, 1 - cal$theta_k)
  expect_true(cal$theta_k > 0 && cal$theta_k < 1)
  expect_true(is.finite(cal$gamma) && cal$gamma > 0)
})

test_that("ces_calibration rejects non-harmonic sigma", {
  skip_if_not_installed("bimets")
  expect_error(ces_calibration(synth_db(), sigma = 0.7), "harmonic")
})

test_that("fit_efficiency_trend returns a positive, smoother-than-raw trend", {
  skip_if_not_installed("bimets")
  db   <- synth_db()
  eff  <- fit_efficiency_trend(db)
  v    <- as.numeric(eff)
  vf   <- v[is.finite(v)]
  expect_true(length(vf) > 0)
  expect_true(all(vf > 0))
  # The trend is smooth: second differences are tiny relative to the level.
  expect_true(stats::sd(diff(vf, differences = 2)) < 0.05 * mean(vf))
})

test_that("the CES inversion recovers effective labour", {
  skip_if_not_installed("bimets")
  db    <- synth_db()
  cal   <- ces_calibration(db)
  eff   <- as.numeric(fit_efficiency_trend(db, cal))
  # Reconstruct Y from the harmonic CES with the smoothed EFF; it should track
  # actual Y to within the smoothing error (a few per cent).
  Y    <- as.numeric(stats::as.ts(db$Y))
  K    <- as.numeric(stats::as.ts(db$KIBN)) + as.numeric(stats::as.ts(db$KIBRE))
  LE   <- as.numeric(stats::as.ts(db$LE))
  LHPP <- as.numeric(stats::as.ts(db$LHPP))
  yhat <- cal$gamma / (cal$theta_n / (eff * LHPP * LE) + cal$theta_k / K)
  ok <- is.finite(yhat)
  expect_true(mean(abs(yhat[ok] / Y[ok] - 1)) < 0.05)
})
