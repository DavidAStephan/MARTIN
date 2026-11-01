test_that("update_data() rejects unknown sources", {
  expect_error(update_data(sources = "bogus"), "Unknown source")
})

test_that("fetch_fred() requires FRED_API_KEY", {
  withr::with_envvar(c(FRED_API_KEY = ""), {
    expect_error(fetch_fred("GDPC1"), "FRED_API_KEY")
  })
})

test_that("fetch_fred() returns canonical panel shape (live API)", {
  skip_if(Sys.getenv("FRED_API_KEY") == "", "FRED_API_KEY not set")
  skip_on_cran()
  skip_if_offline()

  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    panel <- fetch_fred("GDPC1", observation_start = "2020-01-01")
    expect_s3_class(panel, "tbl_df")
    expect_setequal(
      names(panel),
      c("series_id", "source", "date", "value", "vintage")
    )
    expect_true(all(panel$source == "fred"))
    expect_true(all(panel$series_id == "GDPC1"))
    expect_true(nrow(panel) >= 4L)  # at least the four 2020 quarters
    expect_type(panel$value, "double")
  })
})

test_that("update_data(sources='fred') caches and re-reads (live API)", {
  skip_if(Sys.getenv("FRED_API_KEY") == "", "FRED_API_KEY not set")
  skip_on_cran()
  skip_if_offline()

  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    vintage <- Sys.Date()
    p1 <- update_data(vintage = vintage, sources = "fred")
    expect_gt(nrow(p1), 0L)

    # Second call should come from the cache (no network).
    p2 <- update_data(vintage = vintage, sources = "fred", refresh = FALSE)
    expect_equal(nrow(p1), nrow(p2))
    expect_setequal(unique(p1$series_id), unique(p2$series_id))
  })
})
