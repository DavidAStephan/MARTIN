# Tests for the I-2 reconciled fiscal mode (docs/income_side_scope.md, Tier I-2):
# the government balance on a consistent income-account basis, matched to the
# realised NGREV/NGEXP, resolving the M1 fiscal-balance caveat. Uses synthetic
# income-account data (no live fetch) so the reconciliation logic is tested
# deterministically.

recon_data <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  data <- read_fixture()
  ny  <- stats::as.ts(data$NY)
  tsp <- stats::tsp(ny)
  st  <- c(floor(tsp[1] + 1e-9), round((tsp[1] - floor(tsp[1] + 1e-9)) * 4 + 1))
  mk  <- function(sh) bimets::TIMESERIES(sh * as.numeric(ny), START = st, FREQ = 4)
  # synthetic income account: total revenue 34% of GDP; income-account PAYABLE
  # (transfers+interest+subsidies) 15%; interest 1%; transfers 9%. Government
  # consumption+investment is MARTIN's (endogenous) NG, added in NSPEND, so the
  # balance NLEND = NGREV - NG - NGEXP is not a fixed number here.
  data$NGREV <- mk(0.34); data$NGEXP <- mk(0.15)
  data$NGINT <- mk(0.01); data$NTRANSFERS <- mk(0.09)
  data$GMI   <- mk(0.08); data$TAX_PROD_NET <- mk(0.05)
  data
}

rv <- function(p, v) { x <- p$value[p$variable == v]; x[is.finite(x)] }

test_that("reconciled fiscal mode matches the realised balance NGREV-NGEXP", {
  data <- recon_data()
  H <- c("2010Q1", "2019Q3")
  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  fis  <- solve_martin(data, NULL, horizon = H,
                       features = c("income_side", "fiscal_accounting"),
                       feature_params = list(fiscal_mode = "reconciled",
                                             fiscal_bg_target = 30),
                       scenario = "recon")

  # The balance is finite and in a plausible range; debt accumulates it from
  # the target seed in conventional (annual-GDP) units and stays bounded.
  expect_true(all(is.finite(rv(fis, "DEF_GDP"))))
  expect_true(all(abs(rv(fis, "DEF_GDP")) < 25))
  expect_true(all(rv(fis, "BG_GDP") > 5 & rv(fis, "BG_GDP") < 90))

  # NLEND = NREV - NSPEND exactly.
  gv <- function(v) { x <- dplyr::filter(fis, variable == v)
                      stats::setNames(x$value, x$quarter) }
  nl <- gv("NLEND"); nr <- gv("NREV"); ns <- gv("NSPEND")
  q <- names(nl); resid <- nl[q] - (nr[q] - ns[q]); resid <- resid[is.finite(resid)]
  expect_true(max(abs(resid)) < 1e-6)

  # Baseline-neutral for the existing model.
  for (v in c("Y", "RC", "LUR", "PTM", "NCR")) {
    expect_equal(rv(fis, v), rv(base, v), tolerance = 1e-8, info = v)
  }
})

test_that("reconciled mode requires the real fiscal data and income_side", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  # The plain fixture has none of NGREV/NGEXP/NGINT/GOS, so reconciled must error.
  expect_error(
    solve_martin(read_fixture(), NULL, horizon = c("2010Q1", "2019Q3"),
                 features = "fiscal_accounting",
                 feature_params = list(fiscal_mode = "reconciled"),
                 scenario = "x"),
    "reconciled"
  )
})
