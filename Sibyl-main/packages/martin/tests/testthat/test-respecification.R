# Tests for the opt-in T3 re-specification features (Workstream A2 / C, M5):
# the convex Phillips curve (convex_ptm) and the inverted-production-function
# employment target (inverted_le). Both re-estimate an existing behavioural
# equation, so they MUST stay off the default path -- the regression test pins
# the linear-PTM and reduced-form-LE coefficients with no features.

fix_or_skip <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

coef_of <- function(model, eq) {
  co <- model$behaviorals[[eq]]$coefficients
  stats::setNames(as.numeric(co), rownames(co))
}

test_that("convex_ptm swaps to the LURGAP/LUR form and re-estimates PTM", {
  data <- fix_or_skip()

  lin <- coef_of(load_martin(data), "PTM")
  cvx <- coef_of(load_martin(data, features = "convex_ptm"), "PTM")

  # Default keeps the published linear fit (the regression test pins these).
  expect_equal(unname(lin["c1"]), 0.16961243, tolerance = 1e-5)
  # Convex form re-estimates: coefficients move.
  expect_false(isTRUE(all.equal(unname(lin), unname(cvx))))

  mt <- paste(apply_model_features(readLines(model_file_path("af")),
                                   "convex_ptm"), collapse = "\n")
  expect_true(grepl("c7*(LURGAP/LUR)", mt, fixed = TRUE))

  # And it still solves to a sane CPI path.
  p <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                    features = "convex_ptm", scenario = "cvx")
  ptm <- p$value[p$variable == "PTM" & is.finite(p$value)]
  expect_true(all(ptm > 80 & ptm < 140))
})

test_that("inverted_le retargets LE to LESTAR and re-estimates", {
  data <- fix_or_skip()
  skip_if_not_installed("sibyldata")

  calib <- sibyldata::ces_calibration(data)
  data$EFF <- sibyldata::fit_efficiency_trend(data, calib)
  fp <- list(ces_gamma = calib$gamma, ces_theta_k = calib$theta_k)

  le_def <- coef_of(load_martin(data), "LE")
  le_inv <- coef_of(load_martin(data, features = c("output_gap", "inverted_le"),
                                feature_params = fp), "LE")
  # Default keeps the published LE fit (regression test pins c1, c3).
  expect_equal(unname(le_def["c1"]), 0.11129236, tolerance = 1e-5)
  # Re-specified LE moves.
  expect_false(isTRUE(all.equal(unname(le_def), unname(le_inv))))

  mt <- paste(apply_model_features(readLines(model_file_path("af")),
                                   "inverted_le"), collapse = "\n")
  expect_true(grepl("LOG(TSLAG(LESTAR,1))", mt, fixed = TRUE))

  # Solves to sane employment / unemployment.
  p <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                    features = c("output_gap", "inverted_le"),
                    feature_params = fp, scenario = "ile")
  lur <- p$value[p$variable == "LUR" & is.finite(p$value)]
  expect_true(all(lur > 2 & lur < 10))
})
