test_that("bare_rba_id() strips Quandl-style prefixes", {
  expect_equal(sibyldata:::bare_rba_id("F02_1_FCMYGBAG2"), "FCMYGBAG2")
  expect_equal(sibyldata:::bare_rba_id("D02_DLCACS"),       "DLCACS")
  expect_equal(sibyldata:::bare_rba_id("G01_GCPIOCPMTMQP"), "GCPIOCPMTMQP")
})

test_that("bare_rba_id() passes through IDs without an underscore", {
  expect_equal(sibyldata:::bare_rba_id("FXRUSD"),   "FXRUSD")
  expect_equal(sibyldata:::bare_rba_id("FLRBFOLBT"), "FLRBFOLBT")
})

test_that("fetch_rba() returns empty panel for empty input", {
  out <- fetch_rba(character())
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0L)
  expect_setequal(
    names(out),
    c("series_id", "source", "date", "value", "vintage")
  )
})

test_that("fetch_rba() returns canonical panel shape (live readrba)", {
  skip_on_cran()
  skip_if_offline()
  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    panel <- fetch_rba("F02_1_FCMYGBAG2")
    expect_s3_class(panel, "tbl_df")
    expect_setequal(
      names(panel),
      c("series_id", "source", "date", "value", "vintage")
    )
    expect_true(all(panel$source == "rba"))
    # series_id preserved as the catalogue's prefixed form
    expect_true(all(panel$series_id == "F02_1_FCMYGBAG2"))
    expect_gt(nrow(panel), 100L)  # decades of monthly data
  })
})

test_that("update_data(sources='rba') round-trips (live readrba)", {
  skip_on_cran()
  skip_if_offline()
  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    panel <- update_data(sources = "rba")
    expect_gt(nrow(panel), 1000L)
    # Cache hit on the second call
    p2 <- update_data(sources = "rba", refresh = FALSE)
    expect_equal(nrow(panel), nrow(p2))
  })
})
