# Tests for merge_with_fallback().

ts_q <- function(values, start_year, start_quarter = 1L) {
  bimets::TIMESERIES(values, START = c(start_year, start_quarter), FREQ = 4)
}

test_that("missing-in-primary variables are taken from fallback", {
  primary  <- list(A = ts_q(1:4, 2010))
  fallback <- list(A = ts_q(1:4, 2010), B = ts_q(10:13, 2010))
  out <- merge_with_fallback(primary, fallback)
  expect_setequal(names(out), c("A", "B"))
  expect_equal(as.numeric(out$B), 10:13)
})

test_that("missing-in-fallback variables are taken from primary", {
  primary  <- list(NEW = ts_q(5:8, 2010))
  fallback <- list(OLD = ts_q(1:4, 2010))
  out <- merge_with_fallback(primary, fallback)
  expect_setequal(names(out), c("OLD", "NEW"))
  expect_equal(as.numeric(out$NEW), 5:8)
})

test_that("primary overlays fallback at the overlap, primary extends end", {
  # Both start 2010Q1; primary runs further at the end. Result is the
  # union — primary's values for 1:10 (which are 1..10) over the full span.
  primary  <- list(X = ts_q(seq_len(10), 2010))
  fallback <- list(X = ts_q(seq_len(8), 2010))
  out <- merge_with_fallback(primary, fallback)
  expect_equal(as.numeric(out$X), seq_len(10))
})

test_that("primary's recent quarters splice in past fallback's end", {
  # Live LUR scenario: fallback 1959-2019Q3, primary 1978-2026Q1. Result
  # should cover 1959-2026Q1 (the union), with primary winning where
  # both have data (1978-2019Q3 → primary's values).
  primary  <- list(X = ts_q(seq.int(10, 13), 2018))  # 2018Q1..2018Q4
  fallback <- list(X = ts_q(seq.int(1, 36), 2010))   # 2010Q1..2018Q4
  out <- merge_with_fallback(primary, fallback)
  # Span should be 2010Q1..2018Q4 = 36 quarters.
  expect_equal(length(as.numeric(out$X)), 36L)
  # Last 4 quarters should come from primary (10..13), not fallback (33..36).
  expect_equal(tail(as.numeric(out$X), 4), as.numeric(10:13))
  # Earliest quarters from fallback.
  expect_equal(head(as.numeric(out$X), 4), as.numeric(1:4))
})

test_that("primary at union extends both backward and forward when it overlaps", {
  # Primary covers 2015-2020; fallback covers 2010-2018.
  # Union: 2010-2020 with primary winning at 2015-2018 overlap.
  primary  <- list(X = ts_q(seq.int(100, 123), 2015))  # 2015Q1..2020Q4
  fallback <- list(X = ts_q(seq.int(1, 36), 2010))     # 2010Q1..2018Q4
  out <- merge_with_fallback(primary, fallback)
  # Union span = 2010Q1..2020Q4 = 44 quarters
  expect_equal(length(as.numeric(out$X)), 44L)
  # First 4 from fallback (1..4)
  expect_equal(head(as.numeric(out$X), 4), as.numeric(1:4))
  # 2015Q1 is idx 21, should be from primary (100)
  expect_equal(as.numeric(out$X)[21], 100)
  # Last from primary (123)
  expect_equal(tail(as.numeric(out$X), 1), 123)
})

test_that("primary covers historical gap when fallback starts later", {
  # Primary 2010-2018; fallback 2014-2018. Union: 2010-2018, primary
  # fills 2010-2013, primary wins at 2014-2018 overlap.
  primary  <- list(X = ts_q(seq.int(1, 36), 2010))
  fallback <- list(X = ts_q(seq.int(100, 119), 2014))
  out <- merge_with_fallback(primary, fallback)
  expect_equal(length(as.numeric(out$X)), 36L)
  # Primary values throughout (it spans the full union).
  expect_equal(as.numeric(out$X), as.numeric(1:36))
})

test_that("merge with empty primary returns the fallback unchanged", {
  fallback <- list(A = ts_q(1:4, 2010), B = ts_q(5:8, 2010))
  out <- merge_with_fallback(list(), fallback)
  expect_identical(out, fallback)
})

test_that("merge with empty fallback returns the primary", {
  primary <- list(A = ts_q(1:4, 2010))
  out <- merge_with_fallback(primary, list())
  expect_setequal(names(out), "A")
  expect_equal(as.numeric(out$A), 1:4)
})

test_that("NA-padded fallback gets coalesced with primary cleanly", {
  # Fallback starts 2005 with NA for 30 quarters, then 10 obs from
  # 2012Q3. Primary covers 2010-2014. Coalesce union span = 2005-2014:
  #   2005-2009: NA from fallback
  #   2010-2014: primary's 1..20 (overlays NA and the fallback's 1..10
  #              that start from 2012Q3)
  primary  <- list(X = ts_q(seq_len(20), 2010))
  fallback <- list(X = ts_q(c(rep(NA, 30), seq_len(10)), 2005))
  out <- merge_with_fallback(primary, fallback)
  expect_equal(length(as.numeric(out$X)), 40L)
  # First 20 quarters (2005-2009) should be NA from fallback.
  expect_true(all(is.na(head(as.numeric(out$X), 20))))
  # Last 20 quarters (2010-2014) should be primary's 1..20.
  expect_equal(tail(as.numeric(out$X), 20), seq_len(20))
})
