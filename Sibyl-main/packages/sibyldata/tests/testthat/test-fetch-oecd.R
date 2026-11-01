# Tests for fetch_oecd() and oecd_parse_period().
# Live network test is gated on SIBYL_FETCH_OECD_LIVE=TRUE so CI doesn't
# hit the OECD API.

test_that("oecd_parse_period() handles quarterly, monthly, annual strings", {
  out <- sibyldata:::oecd_parse_period(
    c("2024-Q1", "2024-Q4", "2024-03", "2024", "bogus")
  )
  expect_equal(out[1], as.Date("2024-01-01"))
  expect_equal(out[2], as.Date("2024-10-01"))
  expect_equal(out[3], as.Date("2024-03-01"))
  expect_equal(out[4], as.Date("2024-01-01"))
  expect_true(is.na(out[5]))
})

test_that("fetch_oecd() returns empty panel for empty input", {
  out <- fetch_oecd(character(0))
  expect_s3_class(out, "tbl_df")
  expect_setequal(names(out),
                  c("series_id", "source", "date", "value", "vintage"))
  expect_equal(nrow(out), 0L)
})

test_that("fetch_oecd() warns on malformed series_id", {
  expect_warning(
    out <- fetch_oecd("not_a_dataflow_key"),
    "must be of the form"
  )
  expect_equal(nrow(out), 0L)
})

test_that("fetch_oecd() round-trips against the live OECD API", {
  skip_if(Sys.getenv("SIBYL_FETCH_OECD_LIVE") != "TRUE",
          "Set SIBYL_FETCH_OECD_LIVE=TRUE to run.")
  skip_if_offline()
  skip_on_cran()

  # Australian quarterly real GDP, OECD QNA dataflow.
  sid <- "OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA,1.0/AUS.S1..B1GQ.LR..L.Q?"
  out <- fetch_oecd(sid, observation_start = "2020-01-01")
  expect_s3_class(out, "tbl_df")
  expect_gt(nrow(out), 4L)
  expect_setequal(names(out),
                  c("series_id", "source", "date", "value", "vintage"))
  expect_true(all(out$source == "oecd"))
})
