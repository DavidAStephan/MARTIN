test_that("cache_read() returns NULL when the file is absent", {
  # Use a throwaway directory so we don't depend on project state.
  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    expect_null(cache_read("fred", as.Date("1900-01-01")))
  })
})

test_that("cache_write -> cache_read round-trips a panel", {
  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    vintage <- as.Date("2026-05-23")
    panel <- tibble::tibble(
      series_id = c("GDPC1", "GDPC1"),
      source    = "fred",
      date      = as.Date(c("2020-01-01", "2020-04-01")),
      value     = c(18861.5, 17302.5),
      vintage   = vintage
    )
    cache_write(panel, "fred", vintage)
    rt <- cache_read("fred", vintage)
    expect_equal(rt, panel, ignore_attr = TRUE)
  })
})

test_that("cache_write rejects panels with missing canonical columns", {
  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    bad <- tibble::tibble(series_id = "X", date = Sys.Date(), value = 1)
    expect_error(cache_write(bad, "fred", Sys.Date()))
  })
})

test_that("cache_file_path errors for an unknown source", {
  expect_error(sibyldata:::cache_file_path("bogus", Sys.Date()))
})

test_that("cache_path honours SIBYL_DATA_CACHE override", {
  override <- tempfile("sibyl-override-")
  withr::with_envvar(c(SIBYL_DATA_CACHE = override), {
    p <- cache_path()
    expect_equal(normalizePath(p), normalizePath(override))
    expect_true(dir.exists(p))
  })
})
