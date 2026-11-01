# Tests for the derived-formula evaluator and the fixed-point loop in
# add_derived_series(). All use synthetic bimets databases so they're fast
# and don't depend on the live data fetchers.

mk_ts <- function(values, start = c(2020, 1)) {
  bimets::TIMESERIES(values, START = start, FREQ = 4)
}

test_that("evaluate_derived_formula() computes a simple ratio", {
  db <- list(NC = mk_ts(c(110, 121, 132, 143)),
             RC = mk_ts(c(100, 110, 120, 130)))
  out <- sibyldata:::evaluate_derived_formula("NC / RC * 100", db)
  expect_s3_class(out, "ts")
  expect_equal(as.numeric(out), c(110, 110, 110, 110))
})

test_that("evaluate_derived_formula() returns try-error on parse failure", {
  out <- sibyldata:::evaluate_derived_formula("this is not R", list())
  expect_s3_class(out, "try-error")
})

test_that("evaluate_derived_formula() returns try-error on missing inputs", {
  out <- sibyldata:::evaluate_derived_formula(
    "ABSENT_VAR / RC * 100",
    list(RC = mk_ts(1:4))
  )
  expect_s3_class(out, "try-error")
})

test_that("evaluate_derived_formula() returns try-error on NA formula", {
  out <- sibyldata:::evaluate_derived_formula(NA_character_, list())
  expect_s3_class(out, "try-error")
})

test_that("add_derived_series() materialises PC, PG and friends", {
  db <- list(
    NC  = mk_ts(c(110, 121, 132, 143)),
    RC  = mk_ts(c(100, 110, 120, 130)),
    NGI = mk_ts(c(50, 50, 50, 50)),
    NGC = mk_ts(c(60, 60, 60, 60)),
    GI  = mk_ts(c(40, 40, 40, 40)),
    GC  = mk_ts(c(50, 50, 50, 50))
  )
  out <- add_derived_series(db)
  expect_true("PC" %in% names(out))
  expect_equal(as.numeric(out$PC), c(110, 110, 110, 110))
  expect_true("PG" %in% names(out))
  expect_equal(as.numeric(out$PG), rep((50 + 60) / (40 + 50) * 100, 4))

  added <- attr(out, "derived_added")
  expect_true(all(c("PC", "PG") %in% added))
})

test_that("add_derived_series() resolves cross-dependencies via fixed point", {
  # PC depends on NC, RC (direct); HCOE depends on NHCOE, PC (derived).
  # The fixed-point loop should compute PC first, then HCOE.
  db <- list(
    NC    = mk_ts(c(200, 210, 220, 230)),
    RC    = mk_ts(c(100, 105, 110, 115)),
    NHCOE = mk_ts(c(80, 84, 88, 92))
  )
  out <- add_derived_series(db)
  expect_true("PC"   %in% names(out))
  expect_true("HCOE" %in% names(out))
  # HCOE = NHCOE / PC. PC = NC/RC*100 = 200/100*100 = 200 etc. -> all 200.
  expect_equal(as.numeric(out$PC), rep(200, 4))
  # HCOE = 80/200, 84/200, 88/200, 92/200
  expect_equal(as.numeric(out$HCOE), c(80, 84, 88, 92) / 200)
})

test_that("add_derived_series() leaves a series alone if already in db", {
  db <- list(
    NC = mk_ts(c(110, 121)),
    RC = mk_ts(c(100, 110)),
    PC = mk_ts(c(999, 999))  # pre-populated; should not be overwritten
  )
  out <- add_derived_series(db)
  expect_equal(as.numeric(out$PC), c(999, 999))
  expect_false("PC" %in% attr(out, "derived_added"))
})

test_that("add_derived_series() reports unresolvable derived rows", {
  # No inputs supplied -> nothing can be derived.
  db <- list(WY = mk_ts(1:4))
  out <- add_derived_series(db)
  skipped <- attr(out, "derived_skipped")
  # Any of the formula-bearing derived rows that need ABS inputs
  expect_true("PC" %in% skipped)
  expect_true("PG" %in% skipped)
})

test_that("to_martin_database() materialises derived vars when inputs are present", {
  # Synthesise an ABS-shaped panel that provides everything PC needs
  panel <- tibble::tibble(
    series_id = rep(c("A2304037L", "A2304081W"), each = 4),  # NC, RC
    source    = "abs",
    date      = rep(seq(as.Date("2020-01-01"), as.Date("2020-10-01"),
                        by = "quarter"), 2),
    value     = c(200, 220, 240, 260,  # NC
                  100, 110, 120, 130),  # RC
    vintage   = Sys.Date()
  )
  out <- to_martin_database(panel)
  expect_true("NC" %in% names(out))
  expect_true("RC" %in% names(out))
  expect_true("PC" %in% names(out))
  expect_equal(as.numeric(out$PC), c(200, 200, 200, 200))
  # The skipped report should NOT include PC any more
  expect_false("PC" %in% attr(out, "skipped")$derived_no_inputs)
})
