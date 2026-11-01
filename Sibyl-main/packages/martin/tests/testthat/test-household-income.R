# Tests for the household income-account decomposition (docs/income_side_scope.md,
# Tier I-2 household). A baseline-neutral reporting layer: it decomposes the
# lumped household non-labour income NHOY into income-account components
# (non-labour primary income, taxes, transfers, residual) without touching NHOY,
# NHDY or consumption RC.

hh_fixture_or_skip <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

hhv <- function(p, v) { x <- p$value[p$variable == v]; x[is.finite(x)] }

test_that("household_income is baseline-neutral and reconciles disposable income", {
  data <- hh_fixture_or_skip()
  H <- c("2010Q1", "2019Q3")
  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  hh   <- solve_martin(data, NULL, horizon = H, features = "household_income",
                       scenario = "hh")

  expect_true(all(c("HH_NONLAB", "NHOY_RESID", "NHDY_RECON", "HH_TAXRATE")
                  %in% hh$variable))

  # The decomposition must not move NHOY / NHDY / HDY / RC (or the headline).
  for (v in c("Y", "RC", "NHOY", "NHDY", "HDY", "PTM", "NCR")) {
    expect_equal(hhv(hh, v), hhv(base, v), tolerance = 1e-8, info = v)
  }

  # NHDY rebuilt from the account equals NHDY (by construction via the residual).
  gv <- function(v) { x <- dplyr::filter(hh, variable == v)
                      stats::setNames(x$value, x$quarter) }
  nr <- gv("NHDY_RECON"); nd <- gv("NHDY")
  q <- intersect(names(nr), names(nd))
  q <- q[is.finite(nr[q]) & is.finite(nd[q])]
  expect_equal(unname(nr[q]), unname(nd[q]), tolerance = 1e-6)

  # Effective household tax rate is finite and in a plausible range.
  tr <- hhv(hh, "HH_TAXRATE")
  expect_true(all(tr > 0 & tr < 50))
})
