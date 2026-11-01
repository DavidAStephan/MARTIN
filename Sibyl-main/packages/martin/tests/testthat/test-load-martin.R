# read_fixture() + load_martin() — the bimets dependency makes these somewhat
# slow, so they live in their own file and are skipped if bimets isn't
# installed.

test_that("read_fixture() returns a named list of bimets ts", {
  skip_if_not_installed("bimets")
  skip_if_not_installed("readxl")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()
  expect_type(data, "list")
  expect_true(length(data) > 100,
              info = "expected 200+ series in the fixture")
  expect_true(all(nzchar(names(data))))

  # Spot-check a series MARTIN definitely needs
  expect_true("Y" %in% names(data))
  expect_s3_class(data$Y, "ts")
  expect_true(length(as.numeric(data$Y)) > 100)
})

test_that("load_martin() loads the AF model and populates residuals", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()
  model <- load_martin(data, variant = "af", estimate = TRUE)

  expect_true("behaviorals" %in% names(model))
  expect_true(length(model$behaviorals) > 0L)

  # After ESTIMATE on AF form, residuals should exist on at least the
  # equations LOAD.R names. Spot-check a few.
  for (eq in c("PTM", "RC", "IBN", "LE", "NCR")) {
    expect_true(eq %in% names(model$behaviorals),
                info = paste("equation missing:", eq))
    expect_true(!is.null(model$behaviorals[[eq]]$residuals),
                info = paste("residuals missing for:", eq))
  }
})

test_that("load_martin() refuses an unnamed database", {
  expect_error(
    load_martin(list(1, 2, 3)),
    "named"
  )
})

test_that("load_martin() refuses an empty database", {
  expect_error(
    load_martin(list()),
    "non-empty"
  )
})

test_that("solve_martin() rejects coefficients='reestimated' without estimation_end", {
  expect_error(
    solve_martin(
      database = list(Y = 1),  # never reached; validation runs first
      horizon  = c("2010Q1", "2010Q2"),
      coefficients = "reestimated"
    ),
    "requires `estimation_end`"
  )
})

test_that("load_martin() rewrite_tsrange_end preserves per-equation start dates", {
  lines <- c(
    "BEHAVIORAL> PTM",
    "TSRANGE 1993 1 2019 3",
    "EQ> ...",
    "BEHAVIORAL> PAE",
    "TSRANGE 1997 4 2019 3",
    "EQ> ..."
  )
  out <- martin:::rewrite_tsrange_end(lines, "2025Q2")
  expect_equal(out[2], "TSRANGE 1993 1 2025 2")
  expect_equal(out[5], "TSRANGE 1997 4 2025 2")
  # Non-TSRANGE lines untouched
  expect_equal(out[1], lines[1])
  expect_equal(out[3], lines[3])
})

test_that("rewrite_tsrange_end rejects malformed estimation_end", {
  expect_error(martin:::rewrite_tsrange_end(c("TSRANGE 1993 1 2019 3"), "2025"),
               "yyyyQq")
  expect_error(martin:::rewrite_tsrange_end(c("TSRANGE 1993 1 2019 3"), "2025Q5"),
               "yyyyQq")
})

test_that("solve_martin() rejects malformed horizon", {
  expect_error(
    solve_martin(
      database = list(Y = 1),
      horizon  = "2010Q1"
    ),
    "length-2"
  )
})

test_that("solve_martin() rejects adjustments that aren't an adjustment_list", {
  expect_error(
    solve_martin(
      database    = list(Y = 1),
      adjustments = list("not an adjustment_list"),
      horizon     = c("2010Q1", "2010Q2")
    ),
    "adjustment_list"
  )
})
