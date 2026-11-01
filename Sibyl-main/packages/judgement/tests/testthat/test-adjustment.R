make_one <- function(...) {
  defaults <- list(
    equation        = "PTM",
    horizon         = c("2026Q1", "2026Q2", "2026Q3"),
    # PTM is units=log_diff (ceiling 0.02/quarter); keep the default value
    # comfortably within bounds so the fixture is usable everywhere.
    value           = c(0.001, 0.001, 0.0005),
    rationale       = "Sustained services-price pressure from migration",
    channel         = "PTM -> P -> PC",
    expected_effect = "+0.2pp CPI by 2027Q4",
    confidence      = "medium",
    tail            = "decay_50",
    owner           = "ds",
    round_id        = "2026Q2_round1",
    source          = "human"
  )
  args <- modifyList(defaults, list(...))
  do.call(adjustment, args)
}

test_that("constructor returns an adjustment with class and fields", {
  a <- make_one()
  expect_true(is_adjustment(a))
  expect_s3_class(a, "adjustment")
  expect_named(
    a,
    c("equation", "horizon", "value", "rationale", "channel",
      "expected_effect", "confidence", "tail", "target_variable",
      "expected_direction", "coerced", "owner", "round_id", "source")
  )
})

test_that("constructor defaults: tail = decay_50, coerced = FALSE, target NA", {
  a <- make_one(tail = NULL)  # drop the fixture tail so the constructor default applies
  expect_equal(a$tail, "decay_50")
  expect_false(a$coerced)
  expect_true(is.na(a$target_variable))
  expect_true(is.na(a$expected_direction))
})

test_that("validator rejects mismatched horizon and value lengths", {
  expect_error(
    make_one(value = c(0.1, 0.2)),
    "same length"
  )
})

test_that("validator rejects malformed horizon strings", {
  expect_error(
    make_one(horizon = c("2026-Q1", "2026Q2", "2026Q3")),
    "yyyyQq"
  )
})

test_that("validator demands a non-empty rationale", {
  expect_error(
    make_one(rationale = ""),
    "rationale"
  )
})

test_that("validator restricts confidence/tail/source to allowed values", {
  expect_error(make_one(confidence = "maybe"), regexp = "should be one of")
  expect_error(make_one(tail       = "explode"), regexp = "should be one of")
  expect_error(make_one(source     = "alien"),   regexp = "should be one of")
})

test_that("validator restricts expected_direction to up/down/none/NA", {
  expect_error(
    make_one(target_variable = "P", expected_direction = "sideways"),
    "expected_direction"
  )
  # NA and the three enums are all accepted.
  expect_silent(make_one(target_variable = "P", expected_direction = "up"))
  expect_silent(make_one(target_variable = "P", expected_direction = NA_character_))
})

# ---- magnitude / horizon guardrails ----

test_that("guardrail accepts an NCR percent shock of 1.0 (regression-test case)", {
  skip_if_not_installed("martin")
  # The martin regression test builds an NCR (units=percent) AF with value
  # 1.0 and tail="zero"; the ceilings MUST allow it.
  expect_silent(
    adjustment(
      equation = "NCR", horizon = c("2026Q1", "2026Q2"),
      value = c(1.0, 1.0), rationale = "regression fixture",
      tail = "zero", confidence = "medium", source = "llm"
    )
  )
})

test_that("guardrail rejects a catastrophic log_diff value (PTM = 0.1)", {
  skip_if_not_installed("martin")
  # PTM is units=log_diff (+10pp/quarter at value 0.1); ceiling is 0.02.
  expect_error(
    make_one(equation = "PTM", value = c(0.1, 0.1, 0.05)),
    "ceiling"
  )
})

test_that("guardrail rejects an implausibly long horizon", {
  skip_if_not_installed("martin")
  long_h <- judgement:::quarter_seq("2026Q1", "2046Q1")  # 81 quarters
  expect_error(
    make_one(equation = "NCR",
             horizon = long_h,
             value   = rep(0.1, length(long_h)),
             tail    = "zero"),
    "horizon"
  )
})

test_that("guardrail ceilings are overridable via option", {
  skip_if_not_installed("martin")
  # With an explicit, generous ceiling the otherwise-rejected shock passes.
  withr::with_options(
    list(sibyl.af_ceiling = list(log_diff = 1.0, level = 1.0,
                                 percent = 5.0, unknown = 5.0)),
    expect_silent(make_one(equation = "PTM", value = c(0.1, 0.1, 0.05)))
  )
})

test_that("guardrail horizon ceiling is overridable via option", {
  skip_if_not_installed("martin")
  long_h <- judgement:::quarter_seq("2026Q1", "2046Q1")  # 81 quarters
  withr::with_options(
    list(sibyl.af_horizon_ceiling = 200L),
    expect_silent(
      make_one(equation = "NCR", horizon = long_h,
               value = rep(0.1, length(long_h)), tail = "zero")
    )
  )
})

test_that("validator rejects equations not adjustable in the catalogue", {
  # Y is the GDP identity and must not be adjustable
  skip_if_not_installed("martin")
  expect_error(make_one(equation = "Y"), "not adjustable")
})

test_that("validator rejects unknown equation codes", {
  skip_if_not_installed("martin")
  expect_error(make_one(equation = "NONSENSE"), "Unknown MARTIN equation")
})

test_that("print method runs without error and includes key fields", {
  a <- make_one()
  out <- capture.output(print(a))
  expect_true(any(grepl("PTM", out)))
  expect_true(any(grepl("rationale", out)))
  # tail now defaults to decay_50
  expect_true(any(grepl("decay_50", out)))
})

test_that("print method flags coerced adjustments", {
  a <- make_one(coerced = TRUE)
  out <- capture.output(print(a))
  expect_true(any(grepl("coerced", out)))
})

test_that("print method shows target_variable and direction when set", {
  a <- make_one(target_variable = "P", expected_direction = "up")
  out <- capture.output(print(a))
  expect_true(any(grepl("target:", out)))
  expect_true(any(grepl("P \\(up\\)", out)))
})

test_that("adjustment_list constructs, prints, and tibble-coerces", {
  al <- adjustment_list(
    make_one(),
    make_one(equation = "NCR", value = c(0.5, 0.4, 0.3),
             rationale = "Faster rate normalisation than baseline")
  )
  expect_s3_class(al, "adjustment_list")
  expect_length(al, 2L)

  empty_out <- capture.output(print(adjustment_list()))
  expect_true(any(grepl("empty", empty_out)))

  tbl <- as_tibble_adjustments(al)
  expect_s3_class(tbl, "tbl_df")
  # 3 quarters per adjustment, 2 adjustments
  expect_equal(nrow(tbl), 6L)
  expect_setequal(unique(tbl$equation), c("PTM", "NCR"))
})

test_that("empty adjustment_list coerces to an empty tibble", {
  tbl <- as_tibble_adjustments(adjustment_list())
  expect_equal(nrow(tbl), 0L)
  expected_cols <- c("equation", "quarter", "value", "rationale")
  expect_true(all(expected_cols %in% names(tbl)))
})

test_that("validator rejects out-of-order horizon quarters", {
  expect_error(
    make_one(horizon = c("2026Q3", "2026Q1", "2026Q2"),
             value   = c(0.10, 0.10, 0.05)),
    "strictly increasing"
  )
})

# ---- expand_adjustments() ----

range_2yr <- c("2026Q1", "2027Q4")     # 8 quarters
range_q   <- judgement:::quarter_seq(range_2yr[1], range_2yr[2])

test_that("expand_adjustments() on empty list returns empty list", {
  out <- expand_adjustments(adjustment_list(), solve_range = range_2yr)
  expect_length(out, 0L)
  expect_equal(attr(out, "solve_range"), range_2yr)
  expect_equal(attr(out, "quarters"), range_q)
})

# These arithmetic tests use NCR (units=percent, ceiling 5.0/quarter) so the
# round numbers exercising the expansion logic clear the magnitude guardrail;
# the guardrail itself is tested separately above.

test_that("expand_adjustments() zero tail places values and zeros tail", {
  a <- make_one(
    equation = "NCR",
    horizon = c("2026Q1", "2026Q2"),
    value   = c(0.10, 0.05),
    tail    = "zero"
  )
  out <- expand_adjustments(adjustment_list(a), solve_range = range_2yr)
  expect_named(out, "NCR")
  expect_equal(out$NCR, c(0.10, 0.05, 0, 0, 0, 0, 0, 0))
})

test_that("expand_adjustments() carry tail holds last value forward", {
  a <- make_one(
    equation = "NCR",
    horizon = c("2026Q1", "2026Q2"),
    value   = c(0.10, 0.05),
    tail    = "carry"
  )
  out <- expand_adjustments(adjustment_list(a), solve_range = range_2yr)
  expect_equal(out$NCR, c(0.10, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05))
})

test_that("expand_adjustments() decay_50 matches EViews `_a(-1)*-0.5`", {
  a <- make_one(
    equation = "NCR",
    horizon = c("2026Q1", "2026Q2"),
    value   = c(0.10, 0.04),
    tail    = "decay_50"
  )
  out <- expand_adjustments(adjustment_list(a), solve_range = range_2yr)
  # last in-range value is 0.04 at position 2; positions 3..8 get
  # 0.04 * (-0.5)^k for k in 1..6
  expected_tail <- 0.04 * (-0.5)^(1:6)
  expect_equal(out$NCR, c(0.10, 0.04, expected_tail))
})

test_that("expand_adjustments() sums multiple adjustments on the same equation", {
  a1 <- make_one(equation = "NCR",
                 horizon  = c("2026Q1", "2026Q2"),
                 value    = c(0.10, 0.05),
                 tail     = "zero",
                 rationale = "first nudge")
  a2 <- make_one(equation = "NCR",
                 horizon  = c("2026Q1", "2026Q3"),
                 value    = c(0.02, 0.03),
                 tail     = "zero",
                 rationale = "second nudge")
  out <- expand_adjustments(adjustment_list(a1, a2), solve_range = range_2yr)
  # Position-by-position sum
  expect_equal(out$NCR, c(0.12, 0.05, 0.03, 0, 0, 0, 0, 0))
})

test_that("expand_adjustments() warns when horizon is fully out of range", {
  a <- make_one(
    equation = "NCR",
    horizon = c("2030Q1", "2030Q2", "2030Q3"),
    value   = c(0.1, 0.1, 0.05)
  )
  expect_warning(
    out <- expand_adjustments(adjustment_list(a), solve_range = range_2yr),
    "no horizon quarters within solve_range"
  )
  expect_length(out, 0L)
})

test_that("expand_adjustments() handles partial overlap with tail rule", {
  # Horizon ends past the solve_range; only the in-range portion is used,
  # tail rule continues from the last in-range value.
  a <- make_one(
    equation = "NCR",
    horizon = c("2027Q3", "2027Q4", "2028Q1"),
    value   = c(0.10, 0.20, 0.30),
    tail    = "carry"
  )
  out <- expand_adjustments(adjustment_list(a), solve_range = range_2yr)
  # Last in-range value is 0.20 at position 8 (2027Q4); nothing past it.
  expect_equal(out$NCR, c(0, 0, 0, 0, 0, 0, 0.10, 0.20))
})

test_that("expand_adjustments() rejects malformed solve_range", {
  a <- make_one()
  expect_error(
    expand_adjustments(adjustment_list(a), solve_range = "2026Q1"),
    "length-2"
  )
  expect_error(
    expand_adjustments(adjustment_list(a), solve_range = c("2026", "2027")),
    "yyyyQq"
  )
})
