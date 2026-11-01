test_that("fetch_bom() returns empty panel for empty input", {
  out <- fetch_bom(character())
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0L)
  expect_setequal(
    names(out),
    c("series_id", "source", "date", "value", "vintage")
  )
})

test_that("fetch_bom() rejects series IDs other than SOI", {
  expect_error(fetch_bom("FOO"), "only knows the SOI series")
})

test_that("parse_soi_plaintext() handles a synthetic minimal payload", {
  txt <- paste(
    "<html><body><pre>",
    " Year    Jan     Feb     Mar     Apr     May     Jun     Jul     Aug     Sep     Oct     Nov     Dec",
    " 1876    11.3    11.0     0.2     9.4     6.8    17.2    -5.6    12.3    10.5    -8.0    -2.7    -3.0",
    " 1877    -9.7    -6.5    -4.7    -9.6     3.6    -16.8   -10.2   -8.2    -17.2   -16.0   -12.6   -12.6",
    "</pre></body></html>",
    sep = "\n"
  )
  out <- sibyldata:::parse_soi_plaintext(txt)
  expect_equal(nrow(out), 24L)
  expect_equal(out$date[1],  as.Date("1876-01-01"))
  expect_equal(out$value[1], 11.3)
  expect_equal(out$date[24], as.Date("1877-12-01"))
  expect_equal(out$value[24], -12.6)
})

test_that("parse_soi_plaintext() pads incomplete final year", {
  txt <- paste(
    "<pre>",
    " 2024    1.0    2.0    3.0    4.0    5.0    6.0    7.0    8.0    9.0    10.0   11.0   12.0",
    " 2025    1.5    2.5    3.5",   # only 3 months
    "</pre>",
    sep = "\n"
  )
  out <- sibyldata:::parse_soi_plaintext(txt)
  # 12 + 3 non-NA values
  expect_equal(nrow(out), 15L)
  expect_equal(tail(out$date, 3), as.Date(c("2025-01-01", "2025-02-01", "2025-03-01")))
})

# Live test against BoM. Skipped on CRAN / offline / when the FTP/HTTP
# endpoint is reachable but slow.
test_that("fetch_bom() round-trips against live BoM", {
  skip_on_cran()
  skip_if_offline()
  withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-test-")), {
    panel <- tryCatch(
      fetch_bom("SOI"),
      error = function(e) {
        skip(paste("BoM unreachable:", conditionMessage(e)))
      }
    )
    expect_s3_class(panel, "tbl_df")
    expect_true(all(panel$source == "bom"))
    expect_true(all(panel$series_id == "SOI"))
    # SOI series starts in 1876 — should give us 1400+ months of data
    expect_gt(nrow(panel), 1400L)
    expect_true(any(panel$date < as.Date("1900-01-01")))
  })
})
