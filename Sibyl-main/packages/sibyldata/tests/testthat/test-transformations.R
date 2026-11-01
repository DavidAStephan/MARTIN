# Tests for the transformation handlers (level_from_pct, splices, PIM,
# Chow-Lin). Synthetic bimets databases throughout — no network.

mk_ts <- function(values, start = c(1982, 1)) {
  bimets::TIMESERIES(values, START = start, FREQ = 4)
}

# ---- level_from_pct -------------------------------------------------------

test_that("cumulate_pct_to_level() cumulates from a base", {
  pct <- mk_ts(c(0, 1.0, 0.5, 2.0), start = c(1982, 1))
  out <- sibyldata:::cumulate_pct_to_level(
    pct, base = 100, base_quarter = "1982Q1"
  )
  # 1982Q1: 100 (base); Q2: 100*(1+1.0/100)=101; Q3: 101.505; Q4: 103.535
  expect_equal(as.numeric(out),
               c(100, 101, 101.505, 103.5351),
               tolerance = 1e-3)
})

test_that("cumulate_pct_to_level() NAs quarters before base", {
  pct <- mk_ts(c(0, 0, 0, 1, 1), start = c(1981, 1))
  out <- sibyldata:::cumulate_pct_to_level(
    pct, base = 100, base_quarter = "1981Q3"
  )
  vals <- as.numeric(out)
  expect_true(is.na(vals[1]))
  expect_true(is.na(vals[2]))
  expect_equal(vals[3], 100)
  expect_equal(vals[4], 101)
  expect_equal(vals[5], 102.01, tolerance = 1e-4)
})

test_that("apply_level_from_pct() replaces PTM with level series", {
  db <- list(PTM = mk_ts(c(0, 1.0, 0.5), start = c(1982, 1)))
  cat <- tibble::tibble(
    martin_var     = "PTM",
    transformation = "level_from_pct"
  )
  out <- sibyldata:::apply_level_from_pct(db, cat)
  # First cell = 29.83452468 (registered base)
  expect_equal(as.numeric(out$PTM)[1], 29.83452468, tolerance = 1e-6)
  # Second = base * (1 + 1/100)
  expect_equal(as.numeric(out$PTM)[2], 29.83452468 * 1.01, tolerance = 1e-6)
})

# ---- splices --------------------------------------------------------------

test_that("splice_series() forward extends target using source changes", {
  tgt <- mk_ts(c(5.0, 5.5, 6.0, NA, NA), start = c(2020, 1))
  src <- mk_ts(c(NA, NA, 100, 101, 103), start = c(2020, 1))
  out <- sibyldata:::splice_series(tgt, src, direction = "forward")
  vals <- as.numeric(out)
  # 2020Q1..Q3 unchanged; Q4 = 6.0 + (101 - 100) = 7.0; Q1 21 = 7.0 + (103-101) = 9.0
  expect_equal(vals[1:3], c(5.0, 5.5, 6.0))
  expect_equal(vals[4], 7.0)
  expect_equal(vals[5], 9.0)
})

test_that("splice_series() backward fills target using source ratio", {
  # tgt observed only from Q3 onwards; backfill using src scaled by ratio
  tgt <- mk_ts(c(NA, NA, 10, 12, 14), start = c(2020, 1))
  src <- mk_ts(c(2, 3, 5, 6, 7), start = c(2020, 1))
  out <- sibyldata:::splice_series(tgt, src, direction = "backward")
  vals <- as.numeric(out)
  # Ratio at Q3 = 10 / 5 = 2.0
  expect_equal(vals[1], 2 * 2.0)
  expect_equal(vals[2], 3 * 2.0)
  expect_equal(vals[3:5], c(10, 12, 14))
})

test_that("apply_splices() forward-extends NBR using NBR_SPLICE", {
  db <- list(
    NBR        = mk_ts(c(5.0, 5.5, 6.0, NA, NA), start = c(2020, 1)),
    NBR_SPLICE = mk_ts(c(NA, NA, 100, 101, 103), start = c(2020, 1))
  )
  out <- sibyldata:::apply_splices(db, NULL)
  vals <- as.numeric(out$NBR)
  expect_equal(vals[1:3], c(5.0, 5.5, 6.0))
  expect_equal(vals[4], 7.0)
})

test_that("apply_splices() falls through to rename when no NBR direct", {
  db <- list(NBR_SPLICE = mk_ts(c(5, 6, 7), start = c(2020, 1)))
  out <- sibyldata:::apply_splices(db, NULL)
  expect_true("NBR" %in% names(out))
  expect_equal(as.numeric(out$NBR), c(5, 6, 7))
})

# ---- PIM ------------------------------------------------------------------

test_that("pim_accumulate() integrates change-in-stocks from a base", {
  v <- mk_ts(c(0, 100, -50, 200, 0), start = c(1980, 1))
  out <- sibyldata:::pim_accumulate(
    v, base = 1000, base_quarter = "1980Q1"
  )
  # 1980Q1=1000 (base); Q2=1000+100=1100; Q3=1050; Q4=1250; 1981Q1=1250
  expect_equal(as.numeric(out), c(1000, 1100, 1050, 1250, 1250))
})

test_that("apply_pim() builds KV from V using the 1980Q1 base of 134865", {
  v <- mk_ts(c(0, 50, 30, 20), start = c(1980, 1))
  db <- list(V = v)
  out <- sibyldata:::apply_pim(db, NULL)
  expect_true("KV" %in% names(out))
  expect_equal(as.numeric(out$KV),
               c(134865, 134915, 134945, 134965))
})

test_that("apply_pim() skips when V is missing", {
  out <- sibyldata:::apply_pim(list(), NULL)
  expect_false("KV" %in% names(out))
})

# ---- Chow-Lin -------------------------------------------------------------

test_that("apply_chowlin() produces quarterly series from annual input", {
  skip_if_not_installed("tempdisagg")
  annual <- stats::ts(c(100, 105, 110, 115, 120),
                      start = 2000, frequency = 1)
  out <- sibyldata:::apply_chowlin(
    list(), list(KID = annual), NULL
  )
  expect_true("KID" %in% names(out))
  expect_s3_class(out$KID, "ts")
  expect_equal(stats::frequency(out$KID), 4)
  # 5 annual obs -> 20 quarterly obs
  expect_length(as.numeric(out$KID), 20L)
})

test_that("apply_chowlin() leaves existing entries alone", {
  skip_if_not_installed("tempdisagg")
  annual <- stats::ts(c(100, 105, 110), start = 2000, frequency = 1)
  existing <- mk_ts(rep(999, 12), start = c(2000, 1))
  out <- sibyldata:::apply_chowlin(
    list(KID = existing), list(KID = annual), NULL
  )
  expect_equal(as.numeric(out$KID), rep(999, 12))
})

# ---- end-to-end via to_martin_database ------------------------------------

test_that("to_martin_database() flows PTM through level_from_pct", {
  # Synthetic RBA panel: PTM as quarterly percent inflation from 1982Q1
  panel <- tibble::tibble(
    series_id = "G01_GCPIOCPMTMQP",
    source    = "rba",
    date      = seq(as.Date("1982-01-01"),
                    as.Date("1982-10-01"), by = "quarter"),
    value     = c(0, 1.0, 0.5, 2.0),
    vintage   = Sys.Date()
  )
  out <- to_martin_database(panel)
  expect_true("PTM" %in% names(out))
  # First cell should be the registered base, not 0
  expect_equal(as.numeric(out$PTM)[1], 29.83452468, tolerance = 1e-6)
})

test_that("to_martin_database() flows annual capex through Chow-Lin", {
  skip_if_not_installed("tempdisagg")
  # KIBRE is annual ABS data (catalogue source_id A3347284T)
  panel <- tibble::tibble(
    series_id = "A3347284T",
    source    = "abs",
    date      = as.Date(c("2000-06-30", "2001-06-30", "2002-06-30",
                          "2003-06-30", "2004-06-30")),
    value     = c(100, 110, 120, 130, 140),
    vintage   = Sys.Date()
  )
  out <- to_martin_database(panel)
  expect_true("KIBRE" %in% names(out))
  expect_equal(stats::frequency(out$KIBRE), 4)
})
