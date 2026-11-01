# solve_martin_stochastic(): uncertainty bands around the deterministic solve.
#
# Opt-in path. We keep the horizon short and the draw count small so the
# Monte Carlo stays fast; the assertions lock the contract (column shape,
# bands bracket the central value, central value equals the deterministic
# solve) rather than any particular band width.

HORIZON <- c("2010Q1", "2012Q4")

test_that("solve_martin_stochastic returns the contract columns", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()
  st <- solve_martin_stochastic(
    database = data, adjustments = NULL,
    horizon = HORIZON, scenario = "baseline", n_draws = 25L
  )

  expect_setequal(
    names(st),
    c("variable", "quarter", "value", "lower", "upper", "scenario")
  )
  expect_type(st$value, "double")
  expect_type(st$lower, "double")
  expect_type(st$upper, "double")
  expect_true(all(st$scenario == "baseline"))
  expect_identical(attr(st, "n_draws"), 25L)
  expect_true(attr(st, "band_method") %in%
                c("stochsimulate", "af_perturbation"))
})

test_that("stochastic bands bracket the central value", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()
  st <- solve_martin_stochastic(
    database = data, adjustments = NULL,
    horizon = HORIZON, scenario = "baseline", n_draws = 25L
  )

  finite <- st[is.finite(st$lower) & is.finite(st$upper) &
                 is.finite(st$value), , drop = FALSE]
  expect_true(nrow(finite) > 0L)
  # Allow a small tolerance: the central solve and the band edges come from
  # the same Gauss-Seidel solver and can differ by solver noise.
  tol <- 1e-3 * pmax(1, abs(finite$value))
  expect_true(all(finite$lower <= finite$value + tol),
              info = "lower band must not exceed central value")
  expect_true(all(finite$value <= finite$upper + tol),
              info = "upper band must not be below central value")
  # At least some series must have a non-degenerate band.
  expect_true(any(finite$upper - finite$lower > 0))
})

test_that("stochastic central path matches the deterministic solve", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()
  det <- solve_martin(
    database = data, adjustments = NULL,
    horizon = HORIZON, scenario = "baseline"
  )
  st <- solve_martin_stochastic(
    database = data, adjustments = NULL,
    horizon = HORIZON, scenario = "baseline", n_draws = 25L
  )

  for (v in c("Y", "LUR", "PTM", "NCR")) {
    d <- dplyr::filter(det, variable == v)
    s <- dplyr::filter(st,  variable == v)
    if (nrow(d) == 0L || nrow(s) == 0L) next
    m <- merge(
      d[, c("quarter", "value")],
      s[, c("quarter", "value")],
      by = "quarter", suffixes = c("_det", "_stoch")
    )
    # The stochastic central path is the deterministic (unshocked) realization,
    # so it must match solve_martin() to within solver tolerance.
    expect_equal(m$value_stoch, m$value_det, tolerance = 1e-2,
                 info = paste("central path mismatch for", v))
  }
})

test_that("solve_martin_stochastic validates n_draws and horizon", {
  expect_error(
    solve_martin_stochastic(
      database = list(Y = 1), horizon = c("2010Q1", "2010Q2"), n_draws = 1L
    ),
    "n_draws"
  )
  expect_error(
    solve_martin_stochastic(
      database = list(Y = 1), horizon = "2010Q1"
    ),
    "length-2"
  )
})
