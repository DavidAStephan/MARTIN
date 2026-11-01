# Tests for the fiscal and external stock-flow accounting features
# (docs/martin_enhancements_plan.md, Workstream B, M3). The identities are
# baseline-neutral reporting layers: they must hold exactly, produce
# economically sane ratios, and perturb no existing endogenous variable.

fixture_or_skip <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

solved_value <- function(p, v) {
  x <- p$value[p$variable == v]
  x[is.finite(x)]
}

test_that("external_accounting is consistent, sane and baseline-neutral", {
  data <- fixture_or_skip()
  H <- c("2010Q1", "2019Q3")
  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  ext  <- solve_martin(data, NULL, horizon = H,
                       features = "external_accounting",
                       feature_params = list(nfl_seed = 55), scenario = "ext")

  expect_true(all(c("NTB", "NCA", "VNFL", "NFL_GDP", "CAD_GDP") %in% ext$variable))

  # NCA == NTB exactly when NFOY = NTRF = 0.
  nca <- dplyr::filter(ext, variable == "NCA")
  ntb <- dplyr::filter(ext, variable == "NTB")
  m <- merge(nca, ntb, by = "quarter")
  expect_equal(m$value.x, m$value.y, tolerance = 1e-6)

  # Economically sane Australian ranges.
  expect_true(all(abs(solved_value(ext, "CAD_GDP")) < 10))
  expect_true(all(solved_value(ext, "NFL_GDP") > 0 & solved_value(ext, "NFL_GDP") < 120))

  # Baseline-neutral.
  for (v in c("Y", "RC", "LUR", "PTM", "NCR", "RTWI")) {
    expect_equal(solved_value(ext, v), solved_value(base, v),
                 tolerance = 1e-8, info = v)
  }
})

test_that("external_accounting incorporates net foreign income (M1 wiring)", {
  data <- fixture_or_skip()
  # Inject a synthetic primary-income deficit of 3% of GDP (as the real ABS
  # net primary income, A3535270A, supplies in the live pipeline).
  ny  <- stats::as.ts(data$NY)
  tsp <- stats::tsp(ny)
  st  <- c(floor(tsp[1] + 1e-9), round((tsp[1] - floor(tsp[1] + 1e-9)) * 4 + 1))
  data$NFOY <- bimets::TIMESERIES(-0.03 * as.numeric(ny), START = st, FREQ = 4)

  ext <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                      features = "external_accounting", scenario = "ext")
  # NCA = NTB + NFOY, so CAD_GDP = -TB_GDP + 3 (the income deficit adds ~3pp).
  cad <- solved_value(ext, "CAD_GDP")
  tb  <- solved_value(ext, "TB_GDP")
  expect_true(abs(mean(cad) - (-mean(tb) + 3)) < 0.5)
})

test_that("fiscal_accounting is consistent, bounded and baseline-neutral", {
  data <- fixture_or_skip()
  H <- c("2010Q1", "2019Q3")
  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  fis  <- solve_martin(data, NULL, horizon = H,
                       features = "fiscal_accounting", scenario = "fis")

  expect_true(all(c("NREV", "NSPEND", "NLEND", "INTG", "BG", "BG_GDP", "DEF_GDP")
                  %in% fis$variable))

  # NLEND == NREV - NSPEND - INTG exactly.
  gv <- function(v) {
    x <- dplyr::filter(fis, variable == v)
    stats::setNames(x$value, x$quarter)
  }
  nl <- gv("NLEND"); nr <- gv("NREV"); ns <- gv("NSPEND"); ig <- gv("INTG")
  q <- names(nl)
  resid <- nl[q] - (nr[q] - ns[q] - ig[q])
  resid <- resid[is.finite(resid)]
  expect_true(max(abs(resid)) < 1e-6)

  # Debt and deficit stay in plausible ranges over the demo window (the
  # open-loop path is only bounded because it is seeded at target; the
  # debt-stabilising rule is fiscal_rule, M4).
  expect_true(all(solved_value(fis, "BG_GDP") > -20 & solved_value(fis, "BG_GDP") < 80))
  expect_true(all(abs(solved_value(fis, "DEF_GDP")) < 10))

  # Baseline-neutral.
  for (v in c("Y", "RC", "LUR", "PTM", "NCR")) {
    expect_equal(solved_value(fis, v), solved_value(base, v),
                 tolerance = 1e-8, info = v)
  }
})
