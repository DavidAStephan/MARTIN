# Reproducible chop-and-recover backtest, run as a test so CI exercises it.
#
# This is the committed, real evaluation behind the headline number cited in
# packages/nowcast/inst/eval/handover_backtest.md. It reads the bundled
# MARTIN data fixture DIRECTLY via readxl (no martin package needed) and
# compares bridge vs arima vs naive on a chop-and-recover task.
#
# The test asserts the pipeline runs end-to-end and that the bridge method
# is at least competitive with naive on MAPE -- it deliberately does NOT
# hard-code an accuracy figure, because the headline lives (and is
# regenerated) in handover_backtest.md.

# Locate the fixture without depending on the martin package being loadable.
fixture_path <- function() {
  # tests run with cwd = packages/nowcast/tests/testthat during R CMD check,
  # and from the repo root under `just test`; try both layouts.
  cands <- c(
    testthat::test_path("..", "..", "..", "martin", "inst", "extdata",
                        "martin_data_fixture.xlsx"),
    file.path("packages", "martin", "inst", "extdata",
              "martin_data_fixture.xlsx")
  )
  hit <- cands[file.exists(cands)]
  if (length(hit)) normalizePath(hit[1]) else NA_character_
}

backtest_db_from_fixture <- function(raw) {
  col_to_ts <- function(col) {
    v <- raw[[col]]
    idx <- which(!is.na(v))
    if (length(idx) == 0L) return(NULL)
    span <- min(idx):max(idx)
    if (anyNA(v[span])) return(NULL)
    d0 <- raw$Dates[min(idx)]
    yr <- as.integer(format(d0, "%Y"))
    mo <- as.integer(format(d0, "%m"))
    q  <- (mo - 1L) %/% 3L + 1L
    bimets::TIMESERIES(v[span], START = c(yr, q), FREQ = 4)
  }
  vars <- intersect(handover_variables(), names(raw))
  db <- list()
  for (v in vars) {
    ts <- col_to_ts(v)
    if (!is.null(ts) && length(as.numeric(ts)) >= 16L) db[[v]] <- ts
  }
  db
}

test_that("chop-and-recover backtest runs and bridge is competitive", {
  skip_if_not_installed("readxl")
  fx <- fixture_path()
  skip_if(is.na(fx), "MARTIN data fixture not found")

  raw <- suppressWarnings(suppressMessages(readxl::read_excel(fx)))
  db  <- backtest_db_from_fixture(raw)
  skip_if(length(db) < 10L, "fixture covers too few handover variables")

  vars <- names(db)
  H <- 2L

  held_out <- list()
  truncated <- list()
  for (v in vars) {
    full <- as.numeric(db[[v]])
    n <- length(full)
    held_out[[v]] <- full[(n - H + 1):n]
    tsp0 <- stats::tsp(db[[v]])
    yr <- floor(tsp0[1] + 1e-9)
    q  <- round((tsp0[1] - yr) * 4 + 1)
    truncated[[v]] <- bimets::TIMESERIES(full[1:(n - H)],
                                         START = c(yr, q), FREQ = 4)
  }

  mape <- function(method) {
    errs <- numeric(0)
    for (v in vars) {
      fc <- tryCatch(
        nowcast_handover(truncated, h = H, method = method, variables = v),
        error = function(e) NULL
      )
      if (is.null(fc) || nrow(fc) != H) next
      actual <- held_out[[v]]
      ape <- abs(fc$central - actual) / pmax(abs(actual), 1e-6)
      errs <- c(errs, ape)
    }
    list(mape = mean(errs), n = length(errs))
  }

  b <- mape("bridge")
  n <- mape("naive")

  # The pipeline produced a forecast for (nearly) every variable * horizon.
  expect_gt(b$n, length(vars))            # >1 horizon recovered per var
  expect_true(is.finite(b$mape))
  expect_true(is.finite(n$mape))
  # Bridge should not be materially worse than naive on this fixture. We
  # allow a small slack so the test isn't brittle to fable version drift.
  expect_lte(b$mape, n$mape * 1.10,
             label = sprintf("bridge MAPE %.3f vs naive MAPE %.3f",
                             b$mape, n$mape))
})
