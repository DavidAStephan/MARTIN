test_that("to_martin_database() pivots the FRED slice to bimets ts", {
  # Synthetic quarterly panel matching the FRED catalogue entry for wy
  panel <- tibble::tibble(
    series_id = "GDPC1",
    source    = "fred",
    date      = seq(as.Date("2020-01-01"), as.Date("2020-10-01"), by = "quarter"),
    value     = c(100, 101, 102, 103),
    vintage   = as.Date("2026-05-23")
  )

  out <- to_martin_database(panel)
  expect_type(out, "list")
  expect_true("WY" %in% names(out))
  expect_s3_class(out$WY, "ts")
  expect_equal(as.numeric(out$WY), c(100, 101, 102, 103))
  expect_equal(stats::tsp(out$WY)[1], 2020.0)
  expect_equal(stats::tsp(out$WY)[3], 4)
})

test_that("to_martin_database() aggregates monthly series to quarterly", {
  # WPOIL is monthly in the catalogue with aggregation='mean'
  panel <- tibble::tibble(
    series_id = "MCOILWTICO",
    source    = "fred",
    date      = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01",
                          "2020-04-01", "2020-05-01", "2020-06-01")),
    value     = c(50, 60, 70, 80, 90, 100),
    vintage   = as.Date("2026-05-23")
  )
  out <- to_martin_database(panel)
  expect_true("WPOIL" %in% names(out))
  # 2020Q1 mean = 60; 2020Q2 mean = 90
  expect_equal(as.numeric(out$WPOIL), c(60, 90))
})

test_that("to_martin_database() reports derived rows it couldn't materialise", {
  panel <- tibble::tibble(
    series_id = "GDPC1",
    source    = "fred",
    date      = seq(as.Date("2020-01-01"), as.Date("2020-10-01"), by = "quarter"),
    value     = c(100, 101, 102, 103),
    vintage   = Sys.Date()
  )
  out <- to_martin_database(panel)
  skipped <- attr(out, "skipped")
  expect_type(skipped, "list")
  # PC needs NC and RC; this input only provides WY (FRED GDPC1).
  expect_true("PC" %in% skipped$derived_no_inputs)
  # Non-direct, non-derived rows (Chow-Lin etc.) are reported separately.
  expect_true(length(skipped$other_transforms) > 0L)
})

test_that("to_martin_database() ignores series not in the catalogue", {
  panel <- tibble::tibble(
    series_id = "NOT_IN_CATALOGUE",
    source    = "fred",
    date      = seq(as.Date("2020-01-01"), as.Date("2020-10-01"), by = "quarter"),
    value     = c(1, 2, 3, 4),
    vintage   = Sys.Date()
  )
  out <- to_martin_database(panel)
  # No data-derived series should materialise from an unknown source_id.
  # The deterministic calendar series (dummies / scalars / identity-chain
  # rows like IBCTR, IBNDR, IAD weights) all appear, plus any derived
  # rows whose inputs are themselves deterministic (e.g. IBNDRA = sum of
  # IBNDR lags is computable from the static IBNDR placeholder).
  cat <- series_catalogue()
  calendar_only <- cat$martin_var[cat$transformation %in%
                                    c("dummy", "scalar", "identity")]
  expect_true(all(calendar_only %in% names(out)),
              info = paste("missing calendar rows:",
                           paste(setdiff(calendar_only, names(out)),
                                 collapse = ", ")))
  expect_false("NC" %in% names(out))  # nothing from the data panel itself
})
