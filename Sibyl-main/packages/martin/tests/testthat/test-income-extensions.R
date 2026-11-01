# Tests for the income-side completions (docs/income_side_scope.md):
#   I-1  GNI (= NY + NFOY) and the corporate GOS share
#   I-3  corporate balance sheet (RET_EARN, VCORP, LEV_DE)
#   I-2 Phase 2  endogenous household income (automatic stabilisers)

ie_fixture <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}
iev <- function(p, v) { x <- p$value[p$variable == v]; x[is.finite(x)] }
ie_synth <- function(data, share) {
  ny  <- as.numeric(stats::as.ts(data$NY))
  tsp <- stats::tsp(stats::as.ts(data$NY))
  st  <- c(floor(tsp[1] + 1e-9), round((tsp[1] - floor(tsp[1] + 1e-9)) * 4 + 1))
  bimets::TIMESERIES(share * ny, START = st, FREQ = 4)
}

test_that("I-1: GNI is GDP plus net foreign income, baseline-neutral", {
  data <- ie_fixture()
  data$NFOY <- ie_synth(data, -0.03)   # 3% primary-income deficit
  H <- c("2010Q1", "2019Q3")
  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  ext  <- solve_martin(data, NULL, horizon = H,
                       features = "external_accounting", scenario = "ext")
  # GNI < GDP by the income outflow; wedge ~ -3%.
  expect_true(all(iev(ext, "GNI") < iev(ext, "NY")))
  expect_true(all(abs(iev(ext, "GNI_GDP_WEDGE") + 3) < 0.01))
  for (v in c("Y", "RC", "NCR", "PTM")) {
    expect_equal(iev(ext, v), iev(base, v), tolerance = 1e-8, info = v)
  }
})

test_that("I-3: corporate balance sheet produces sane net worth and gearing", {
  data <- ie_fixture()
  data$DCORP <- ie_synth(data, 1.6)   # corporate debt ~ 1.6x quarterly GDP
  p <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                    features = "corporate_accelerator", scenario = "corp")
  expect_true(all(c("RET_EARN", "VCORP", "LEV_DE") %in% p$variable))
  expect_true(all(iev(p, "RET_EARN") > 0))         # corporate saving positive
  expect_true(all(iev(p, "LEV_DE") > 5 & iev(p, "LEV_DE") < 60))  # gearing sane
  # Net worth ~ a couple of years of GDP.
  expect_true(mean(iev(p, "VCORP")) / (4 * mean(iev(p, "NY"))) > 1)
})

test_that("I-2 Phase 2: endogenous_household swaps NHOY and re-baselines RC", {
  data <- ie_fixture()
  H <- c("2010Q1", "2019Q3")

  mt <- paste(apply_model_features(readLines(model_file_path("af")),
                                   "endogenous_household"), collapse = "\n")
  expect_true(grepl("IDENTITY> NHOY", mt, fixed = TRUE))
  expect_false(grepl("BEHAVIORAL> NHOY", mt, fixed = TRUE))

  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  en   <- solve_martin(data, NULL, horizon = H,
                       features = c("household_income", "endogenous_household"),
                       scenario = "en")
  # The feature is opt-in: it DOES move RC (automatic stabilisers), but modestly,
  # and the solve stays sane.
  expect_false(isTRUE(all.equal(iev(en, "RC"), iev(base, "RC"))))
  expect_true(mean(abs(iev(en, "RC") - iev(base, "RC")) / iev(base, "RC")) < 0.10)
  expect_true(all(iev(en, "NHOY") > 0))

  # The default model keeps the NHOY behavioural equation.
  expect_false(is.null(load_martin(data)$behaviorals[["NHOY"]]))
})
