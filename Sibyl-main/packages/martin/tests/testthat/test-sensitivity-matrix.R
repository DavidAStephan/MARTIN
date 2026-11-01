# sensitivity_matrix(): convergence + linearity-curvature columns.
#
# The bimets solves make these slow, so we restrict to a single equation and
# two offsets and a short in-sample horizon. The point is to lock the new
# contract columns (converged, deviation_3x, curvature_ratio, linearity_ok),
# not to re-benchmark the whole matrix.

HORIZON <- c("2010Q1", "2019Q3")

build_baseline <- function() {
  data <- read_fixture()
  base <- solve_martin(
    database = data, adjustments = NULL,
    horizon = HORIZON, scenario = "baseline"
  )
  list(data = data, baseline = base)
}

test_that("sensitivity_matrix emits convergence + curvature columns by default", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  ctx <- build_baseline()
  sm <- sensitivity_matrix(
    ctx$data, ctx$baseline, HORIZON,
    equations       = "NCR",
    measure_offsets = c(1L, 4L),
    probe_curvature = TRUE,
    progress        = FALSE
  )

  expect_true(all(
    c("deviation", "converged", "deviation_3x",
      "curvature_ratio", "linearity_ok") %in% names(sm)
  ))
  expect_type(sm$converged, "logical")
  expect_type(sm$linearity_ok, "logical")
  expect_type(sm$deviation_3x, "double")
  expect_type(sm$curvature_ratio, "double")

  # A small NCR shock should solve cleanly and stay near-linear.
  expect_true(all(sm$converged), info = "NCR probe should converge")
  # curvature_ratio ~ deviation_3x / (3 * deviation): close to 1 when linear.
  good <- sm[is.finite(sm$curvature_ratio), , drop = FALSE]
  expect_true(nrow(good) > 0L)
  expect_true(all(abs(good$curvature_ratio - 1) < 0.5),
              info = "NCR response should be roughly linear at the probe size")
  # deviation_3x must be finite and roughly 3x deviation where both exist.
  expect_true(all(is.finite(good$deviation_3x)))
})

test_that("sensitivity_matrix(probe_curvature = FALSE) blanks curvature cols", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  ctx <- build_baseline()
  sm <- sensitivity_matrix(
    ctx$data, ctx$baseline, HORIZON,
    equations       = "NCR",
    measure_offsets = c(1L),
    probe_curvature = FALSE,
    progress        = FALSE
  )

  # The curvature columns still exist (stable schema) but are all NA.
  expect_true(all(
    c("converged", "deviation_3x", "curvature_ratio", "linearity_ok")
    %in% names(sm)
  ))
  expect_true(all(is.na(sm$deviation_3x)))
  expect_true(all(is.na(sm$curvature_ratio)))
  expect_true(all(is.na(sm$linearity_ok)))
  # The 1x deviation and convergence flag are still populated.
  expect_true(any(is.finite(sm$deviation)))
  expect_type(sm$converged, "logical")
})

test_that("solve_martin attaches a convergence attribute", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()
  p <- solve_martin(
    database = data, adjustments = NULL,
    horizon = HORIZON, scenario = "baseline"
  )
  conv <- attr(p, "convergence")
  expect_true(is.list(conv))
  expect_true(all(c("converged", "n_nonfinite") %in% names(conv)))
  expect_type(conv$converged, "logical")
  # In-sample baseline must converge cleanly.
  expect_true(isTRUE(conv$converged))
  expect_identical(conv$n_nonfinite, 0L)
})
