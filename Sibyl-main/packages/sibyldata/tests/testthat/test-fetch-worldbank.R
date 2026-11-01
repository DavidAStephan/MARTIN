test_that("fetch_worldbank() returns empty panel for empty source_rows", {
  empty_rows <- series_catalogue()[0, , drop = FALSE]
  out <- fetch_worldbank(empty_rows)
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0L)
  expect_setequal(
    names(out),
    c("series_id", "source", "date", "value", "vintage")
  )
})

test_that("fetch_worldbank() reads bundled CMO xlsx and returns canonical panel", {
  skip_if_not_installed("readxl")
  cat <- series_catalogue()
  wb_rows <- cat[cat$source == "worldbank", , drop = FALSE]
  skip_if(nrow(wb_rows) == 0L, "no worldbank rows in catalogue")
  skip_if(!file.exists(sibyldata:::worldbank_xlsx_path()),
          "bundled World Bank xlsx not in references/")

  panel <- fetch_worldbank(wb_rows)
  expect_s3_class(panel, "tbl_df")
  expect_setequal(
    names(panel),
    c("series_id", "source", "date", "value", "vintage")
  )
  expect_true(all(panel$source == "worldbank"))
  expect_setequal(unique(panel$series_id), wb_rows$source_id)
  # Bundled file ends around 2021; expect at least 60 years of monthly data
  expect_gt(nrow(panel), 60L * 12L * length(wb_rows$source_id))
  expect_true(all(panel$date >= as.Date("1960-01-01")))
})

test_that("worldbank_monthly_date() parses 'YYYYMnn' strings", {
  expect_equal(
    sibyldata:::worldbank_monthly_date(c("1960M01", "2020M12")),
    as.Date(c("1960-01-01", "2020-12-01"))
  )
})

test_that("fetch_worldbank() errors when xlsx columns are missing", {
  bad <- tibble::tibble(
    martin_var = "FAKE", source = "worldbank", source_id = "iNOTHING",
    source_table = "CMO", source_frequency = "M",
    aggregation = "mean", transformation = "direct",
    description = "test", units = "test"
  )
  expect_error(fetch_worldbank(bad), "missing columns")
})
