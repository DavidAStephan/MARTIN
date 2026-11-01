# Tests for the optional model-features mechanism (docs/martin_enhancements_plan.md).
# The cardinal property: with no features requested the model text and the solve
# are unchanged, and "diagnostic" features (output_gap) do not perturb any
# existing endogenous variable.

test_that("apply_model_features() with no features is a no-op", {
  lines <- readLines(model_file_path("af"))
  expect_identical(apply_model_features(lines, character(0)), lines)
})

test_that("apply_model_features() rejects unknown features", {
  lines <- readLines(model_file_path("af"))
  expect_error(apply_model_features(lines, "nonsense"), "unknown")
})

test_that("convex_ptm swaps the PTM gap term in place", {
  lines <- readLines(model_file_path("af"))
  before <- paste(lines, collapse = "\n")
  after  <- paste(apply_model_features(lines, "convex_ptm"), collapse = "\n")
  expect_true(grepl("+c7*LURGAP", before, fixed = TRUE))
  expect_true(grepl("+c7*(LURGAP/LUR)", after, fixed = TRUE))
  expect_false(grepl("+c7*LURGAP\n", after, fixed = TRUE))
})

test_that("inserting feature blocks keeps the trailing END", {
  lines <- readLines(model_file_path("af"))
  out <- apply_model_features(lines, "external_accounting")
  expect_equal(utils::tail(out[nzchar(out)], 1), "END")
  expect_true(any(grepl("IDENTITY> VNFL", out)))
})

test_that("output_gap is baseline-neutral for existing variables", {
  skip_if_not_installed("bimets")
  skip_if_not_installed("sibyldata")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data  <- read_fixture()
  calib <- sibyldata::ces_calibration(data)
  data$EFF <- sibyldata::fit_efficiency_trend(data, calib)
  fp <- list(ces_gamma = calib$gamma, ces_theta_k = calib$theta_k)

  base <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                       scenario = "base")
  gap  <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                       features = "output_gap", feature_params = fp,
                       scenario = "gap")

  # A pure-diagnostic feature must not move ANY existing endogenous variable.
  for (v in c("Y", "RC", "GNE", "LUR", "PTM", "NCR", "LE", "RTWI")) {
    b <- base$value[base$variable == v]
    g <- gap$value[gap$variable == v]
    expect_equal(g, b, tolerance = 1e-8, info = v)
  }

  # YGAP exists, is finite and economically sane (within +/- 15 percent).
  yg <- gap$value[gap$variable == "YGAP"]
  yg <- yg[is.finite(yg)]
  expect_true(length(yg) > 0)
  expect_true(all(abs(yg) < 15))

  # LESTAR (inverted-PF employment) tracks actual employment within ~5 percent.
  le     <- dplyr::filter(gap, variable == "LE")
  lestar <- dplyr::filter(gap, variable == "LESTAR")
  m <- merge(le, lestar, by = "quarter")
  expect_true(all(abs(m$value.y / m$value.x - 1) < 0.05))
})
