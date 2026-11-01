# Tests for the elb_floor feature: it restores the EViews effective-lower-bound
# floor on the cash rate (equations.prg L538) that the bimets port dropped. It
# renames the Taylor-rule behavioural to NCR_RULE (so estimation + the residual
# handover are preserved) and makes NCR a floored identity via bimets IF>
# branches. It MUST stay off the default path: in sample the floor never binds,
# so the solve is bit-identical to baseline (design principle 6).

fix_or_skip <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

coef_of <- function(model, eq) {
  co <- model$behaviorals[[eq]]$coefficients
  stats::setNames(as.numeric(co), rownames(co))
}

test_that("elb_floor renames NCR to NCR_RULE and adds a floored identity", {
  mt <- paste(apply_model_features(readLines(model_file_path("af")),
                                   "elb_floor"), collapse = "\n")

  # The Taylor rule moves to NCR_RULE; NCR becomes a (twice-declared) identity.
  expect_true(grepl("BEHAVIORAL> NCR_RULE", mt, fixed = TRUE))
  expect_false(grepl("BEHAVIORAL> NCR\n", mt, fixed = TRUE))
  expect_equal(lengths(regmatches(mt, gregexpr("IDENTITY> NCR\n", mt))), 2L)
  expect_true(grepl("IF> NCR_RULE > 0.1", mt, fixed = TRUE))
  expect_true(grepl("IF> NCR_RULE <= 0.1", mt, fixed = TRUE))
  # The renamed rule keeps the self-lag on the (floored) NCR.
  expect_true(grepl("EQ> NCR_RULE  =c1*( 0.7  * TSLAG(NCR,1)", mt,
                    fixed = TRUE))

  expect_true("NCR_RULE" %in% feature_new_vars("elb_floor"))
})

test_that("NCR_RULE inherits NCR's history and estimates identically", {
  data <- fix_or_skip()

  ncr_base <- coef_of(load_martin(data), "NCR")
  m_floor  <- load_martin(data, features = "elb_floor")
  ncr_rule <- coef_of(m_floor, "NCR_RULE")
  expect_equal(unname(ncr_base), unname(ncr_rule), tolerance = 1e-10)
  # NCR is now an identity, not a behavioural.
  expect_null(m_floor$behaviorals[["NCR"]])
})

test_that("elb_floor is baseline-neutral in sample (floor does not bind)", {
  data <- fix_or_skip()

  base  <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                        scenario = "base")
  floor <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                        features = "elb_floor", scenario = "floor")

  for (v in c("NCR", "Y", "RC", "PTM", "N10R")) {
    b <- dplyr::filter(base,  variable == v)$value
    f <- dplyr::filter(floor, variable == v)$value
    expect_equal(f, b, tolerance = 1e-8, info = paste("elb_floor changed", v))
  }
})

test_that("elb_floor clamps the cash rate at the bound when it binds", {
  data <- fix_or_skip()

  pull <- function(p, v) dplyr::filter(p, variable == v)$value

  # Default floor (0.1): never binds in sample, so NCR == NCR_RULE exactly.
  p0 <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                     features = "elb_floor", scenario = "f0")
  expect_equal(pull(p0, "NCR"), pull(p0, "NCR_RULE"), tolerance = 1e-10)

  # Raise the floor to 3pp: the 2010-2019 cash rate falls below it, so the
  # invariant NCR == max(NCR_RULE, 3) must hold and the floor must bind.
  p3 <- solve_martin(data, NULL, horizon = c("2010Q1", "2019Q3"),
                     features = "elb_floor",
                     feature_params = list(elb_floor_value = 3),
                     scenario = "f3")
  ncr  <- pull(p3, "NCR")
  rule <- pull(p3, "NCR_RULE")
  expect_equal(ncr, pmax(rule, 3), tolerance = 1e-8)
  expect_true(any(abs(ncr - 3) < 1e-8), info = "floor at 3 never bound")
  expect_true(all(ncr >= 3 - 1e-8), info = "NCR dipped below the floor")
})
