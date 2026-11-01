# Tests for the switchable feedback features (Workstream B feedback / M4):
# the debt-elastic FX premium (fx_premium) and the debt-stabilising fiscal rule
# (fiscal_rule). These are T2 features: OFF by default (regression test covers
# baseline-neutrality) and active only in the forecast period (in-sample the
# replay add-factors absorb them).

m4_data <- function() {
  skip_if_not_installed("bimets")
  skip_if_not_installed("sibyldata")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  sibyldata::extend_exogenous(read_fixture(), "2021Q2", rules = "carry_all")
}

fv <- function(p, v) { x <- p$value[p$variable == v]; x[is.finite(x)] }

test_that("fx_premium depreciates the AUD when net foreign liabilities exceed the norm", {
  data <- m4_data()
  H <- c("2019Q4", "2021Q2")
  fp <- list(nfl_seed = 55, fx_phi = 0.1, fx_norm = 30)  # NFL ~ 55 > norm 30
  base <- solve_martin(data, NULL, horizon = H, features = "external_accounting",
                       feature_params = fp, scenario = "b")
  fx   <- solve_martin(data, NULL, horizon = H,
                       features = c("external_accounting", "fx_premium"),
                       feature_params = fp, scenario = "fx")
  rb <- fv(base, "RTWI"); rf <- fv(fx, "RTWI")
  # Real TWI is lower (depreciated) with the premium on, and the move is small.
  expect_true(utils::tail(rf, 1) < utils::tail(rb, 1))
  expect_true(abs(utils::tail(rf, 1) / utils::tail(rb, 1) - 1) < 0.05)
})

test_that("fiscal_rule keeps the debt ratio near target in the forecast", {
  data <- m4_data()
  H <- c("2019Q4", "2021Q2")
  ruled <- solve_martin(data, NULL, horizon = H,
                        features = c("fiscal_accounting", "fiscal_rule"),
                        feature_params = list(fiscal_bg_target = 30,
                                              fiscal_rho1 = 0.1, fiscal_rho2 = 0.1),
                        scenario = "ruled")
  bg <- fv(ruled, "BG_GDP")
  expect_true(all(bg > 20 & bg < 45),
              info = "debt ratio should stay near the 30% target under the rule")
})
