# Tests for the exogenize argument on solve_martin().
# Runs a real solve (slow-ish) only when the bimets fixture is available.

test_that("solve_martin() errors helpfully on missing baseline_for_exogenize", {
  expect_error(
    martin::solve_martin(
      database    = list(Y = 1),
      horizon     = c("2010Q1", "2010Q4"),
      exogenize   = "NCR"
    ),
    "baseline_for_exogenize"
  )
})

test_that("solve_martin() errors when baseline_for_exogenize is malformed", {
  expect_error(
    martin::solve_martin(
      database = list(Y = 1), horizon = c("2010Q1", "2010Q4"),
      exogenize = "NCR",
      baseline_for_exogenize = list(not = "a tibble")
    ),
    "tibble.*variable.*quarter.*value"
  )
})

test_that("splice_exogenize_baseline() overwrites in-window cells only", {
  skip_if_not_installed("bimets")
  ts1 <- bimets::TIMESERIES(seq(1, 20),
                            START = c(2020, 1), FREQ = 4)
  baseline <- tibble::tibble(
    variable = "NCR",
    quarter  = sprintf("%dQ%d", rep(2020:2024, each = 4), rep(1:4, 5)),
    value    = seq(101, 120)   # baseline values "+ 100" to be distinguishable
  )
  out <- martin:::splice_exogenize_baseline(
    list(NCR = ts1), baseline, "NCR",
    ex_start = list(year = 2022, quarter = 1),
    ex_end   = list(year = 2023, quarter = 4)
  )
  vals <- as.numeric(out$NCR)
  # 2020-2021 unchanged (1..8); 2022Q1-2023Q4 overwritten with 109..116
  expect_equal(vals[1:8], 1:8)
  expect_equal(vals[9:16], 109:116)
  expect_equal(vals[17:20], 17:20)
})

test_that("solve_martin() exogenises NCR at baseline on the fixture", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin::martin_data_fixture()),
              "MARTINDATA fixture missing")
  data <- martin::read_fixture()
  horizon <- c("2010Q1", "2015Q4")

  baseline <- suppressMessages(suppressWarnings(
    martin::solve_martin(database = data, horizon = horizon,
                         scenario = "baseline")
  ))

  # Apply an LUR shock that normally moves NCR via the Taylor Rule.
  shock <- judgement::adjustment_list(
    judgement::adjustment(
      equation = "LUR",
      horizon  = c("2012Q1", "2012Q2", "2012Q3", "2012Q4"),
      value    = rep(-0.1, 4), rationale = "test",
      channel  = "LUR -> NCR", expected_effect = "test",
      confidence = "medium", tail = "decay_50",
      owner = "test", round_id = "test", source = "human"
    )
  )
  with_exog <- suppressMessages(suppressWarnings(
    martin::solve_martin(
      database = data, horizon = horizon,
      adjustments = shock, scenario = "with-exog",
      exogenize = "NCR", baseline_for_exogenize = baseline,
      exogenize_range = c("2012Q1", "2015Q4")
    )
  ))

  base_ncr <- baseline$value[baseline$variable == "NCR"]
  base_q   <- baseline$quarter[baseline$variable == "NCR"]
  exog_ncr <- with_exog$value[with_exog$variable == "NCR"]
  exog_q   <- with_exog$quarter[with_exog$variable == "NCR"]
  joined <- merge(
    data.frame(quarter = base_q, base = base_ncr),
    data.frame(quarter = exog_q, exog = exog_ncr),
    by = "quarter"
  )
  in_window <- joined$quarter >= "2012Q1" & joined$quarter <= "2015Q4"
  # Inside the exogenisation window, NCR should match baseline exactly
  # (or within tiny numerical tolerance).
  expect_lt(max(abs(joined$exog[in_window] - joined$base[in_window])), 1e-6)
})
