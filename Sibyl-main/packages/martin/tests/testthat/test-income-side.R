# Tests for the income side of GDP (docs/income_side_scope.md, Tier I-0):
# the GDP(I) decomposition NY = NHCOE + GOS + GMI + TAX_PROD_NET, with GOS the
# residual. A baseline-neutral reporting layer delivering the operating-surplus
# flow and the profit/labour-share split.

inc_fixture_or_skip <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

iv <- function(p, v) { x <- p$value[p$variable == v]; x[is.finite(x)] }

test_that("income_side decomposes GDP into sane shares and is baseline-neutral", {
  data <- inc_fixture_or_skip()
  H <- c("2010Q1", "2019Q3")
  base <- solve_martin(data, NULL, horizon = H, scenario = "base")
  inc  <- solve_martin(data, NULL, horizon = H, features = "income_side",
                       scenario = "inc")

  expect_true(all(c("GOS", "PROFIT_SHARE", "LABOUR_SHARE") %in% inc$variable))

  # Operating surplus positive; shares in plausible Australian ranges.
  expect_true(all(iv(inc, "GOS") > 0))
  expect_true(all(iv(inc, "PROFIT_SHARE") > 20 & iv(inc, "PROFIT_SHARE") < 55))
  expect_true(all(iv(inc, "LABOUR_SHARE") > 40 & iv(inc, "LABOUR_SHARE") < 60))

  # Pure reporting layer: perturbs no existing endogenous variable.
  for (v in c("Y", "RC", "LUR", "PTM", "NCR", "LE", "NY")) {
    expect_equal(iv(inc, v), iv(base, v), tolerance = 1e-8, info = v)
  }
})

test_that("the GDP(I) identity holds and labour share equals NHCOE/NY", {
  data <- inc_fixture_or_skip()
  inc <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                      features = "income_side", scenario = "inc")
  gv <- function(v) {
    x <- dplyr::filter(inc, variable == v)
    stats::setNames(x$value, x$quarter)
  }
  ny <- gv("NY"); co <- gv("NHCOE"); gos <- gv("GOS"); ls <- gv("LABOUR_SHARE")
  q <- intersect(names(ny), names(gos))
  q <- q[is.finite(ny[q]) & is.finite(gos[q])]

  # NY - NHCOE - GOS = GMI + TAX_PROD_NET > 0 (the non-COE, non-GOS components).
  rest <- ny[q] - co[q] - gos[q]
  expect_true(all(rest > 0))

  # LABOUR_SHARE == NHCOE / NY * 100 to machine precision.
  expect_equal(unname(ls[q]), unname(co[q] / ny[q] * 100), tolerance = 1e-6)
})
