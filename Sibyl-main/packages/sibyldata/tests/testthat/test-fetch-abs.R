test_that("fetch_abs() returns empty panel for empty source_rows", {
  empty_rows <- series_catalogue()[0, , drop = FALSE]
  out <- fetch_abs(empty_rows)
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0L)
  expect_setequal(
    names(out),
    c("series_id", "source", "date", "value", "vintage")
  )
})

test_that("fetch_abs() rejects catalogue rows without source_table", {
  bad <- tibble::tibble(
    martin_var = "FAKE", source = "abs", source_id = "X",
    source_table = NA_character_, source_frequency = "Q",
    aggregation = NA, transformation = "direct",
    description = "test", units = "test"
  )
  expect_error(fetch_abs(bad), "missing source_table")
})

# Live ABS test. Skipped on CRAN / offline. ABS downloads are large and
# slow, so we restrict to a single small catalogue.
test_that("fetch_abs() round-trips against the live ABS API", {
  skip_on_cran()
  skip_if_offline()
  cat <- series_catalogue()
  abs_rows <- cat[cat$source == "abs" & cat$source_table == "6345.0",
                  , drop = FALSE]
  skip_if(nrow(abs_rows) == 0L, "no 6345.0 rows in catalogue")

  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    panel <- fetch_abs(abs_rows)
    expect_s3_class(panel, "tbl_df")
    expect_setequal(
      names(panel),
      c("series_id", "source", "date", "value", "vintage")
    )
    expect_true(all(panel$source == "abs"))
    expect_true(all(panel$series_id %in% abs_rows$source_id))
    expect_gt(nrow(panel), 50L)  # at least a couple of decades of data
  })
})
