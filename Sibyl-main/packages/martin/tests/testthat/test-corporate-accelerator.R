# Tests for the I-3 corporate financial accelerator (docs/income_side_scope.md,
# Tier I-3): the business borrowing spread NBRSP loads on corporate leverage,
# replacing the purely cyclical proxy with a balance-sheet channel (review
# F1/F5/SF4). Opt-in (re-estimates NBRSP); off by default.

ca_data <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  data <- read_fixture()
  # synthetic corporate debt: a rising, cyclical share of GDP so LEV varies and
  # the new coefficient is identified.
  ny  <- as.numeric(stats::as.ts(data$NY)); n <- length(ny)
  tsp <- stats::tsp(stats::as.ts(data$NY))
  st  <- c(floor(tsp[1] + 1e-9), round((tsp[1] - floor(tsp[1] + 1e-9)) * 4 + 1))
  # debt ~ 1.6x quarterly GDP (~40% of annual GDP), with a cycle.
  share <- 1.6 + 0.3 * sin(seq_len(n) / 10)
  data$DCORP <- bimets::TIMESERIES(share * ny, START = st, FREQ = 4)
  data
}

cav <- function(p, v) { x <- p$value[p$variable == v]; x[is.finite(x)] }
nbrsp_coef <- function(model) {
  co <- model$behaviorals[["NBRSP"]]$coefficients
  stats::setNames(as.numeric(co), rownames(co))
}

test_that("corporate_accelerator adds a leverage term to NBRSP, off by default", {
  data <- ca_data()

  def <- nbrsp_coef(load_martin(data))
  acc <- nbrsp_coef(load_martin(data, features = "corporate_accelerator"))

  # Default keeps the published 3-coefficient NBRSP; the accelerator frees c4.
  expect_false("c4" %in% names(def))
  expect_true("c4" %in% names(acc))
  expect_true(is.finite(acc[["c4"]]))

  mt <- paste(apply_model_features(readLines(model_file_path("af")),
                                   "corporate_accelerator"), collapse = "\n")
  expect_true(grepl("c4*TSLAG(LEV,1)", mt, fixed = TRUE))
  expect_true(grepl("IDENTITY> LEV", mt, fixed = TRUE))
})

test_that("LEV is a sane debt-to-GDP ratio and the accelerator solves", {
  data <- ca_data()
  H <- c("2010Q1", "2019Q3")
  p <- solve_martin(data, NULL, horizon = H,
                    features = "corporate_accelerator", scenario = "acc")
  expect_true(all(cav(p, "LEV") > 10 & cav(p, "LEV") < 80))
  expect_true(all(cav(p, "NBRSP") > -2 & cav(p, "NBRSP") < 10))
})

test_that("the leverage channel moves the forecast spread", {
  skip_if_not_installed("sibyldata")
  data <- ca_data()
  data <- sibyldata::extend_exogenous(data, "2021Q2", rules = "carry_all")
  H <- c("2019Q4", "2021Q2")
  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  acc  <- solve_martin(data, NULL, horizon = H,
                       features = "corporate_accelerator", scenario = "acc")
  # The re-specified NBRSP follows a different forecast path than the default.
  expect_false(isTRUE(all.equal(cav(acc, "NBRSP"), cav(base, "NBRSP"))))
})
