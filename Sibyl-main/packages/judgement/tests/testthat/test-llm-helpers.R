# Tests for the prompt construction and parsing helpers. No LLM calls.

test_that("system_prompt_propose() embeds the adjustable catalogue", {
  skip_if_not_installed("martin")
  prompt <- judgement:::system_prompt_propose()
  expect_type(prompt, "character")
  expect_match(prompt, "SIBYL")
  # Spot-check that real equation codes show up
  for (code in c("PTM", "RC", "NCR", "IBN", "RTWI")) {
    expect_match(prompt, code, fixed = TRUE,
                 info = paste("missing", code))
  }
  # And that non-adjustable identities don't (Y, NY, GNE, X, M when identity)
  # Note: GNE is BEHAVIORAL in AF model but flagged not adjustable in
  # the catalogue (it's an identity-equivalent). Check Y which is a true
  # identity.
  expect_false(grepl("- Y \\(", prompt),
               info = "Y is an identity and shouldn't appear as adjustable")
})

test_that("catalogue_adjustable_text() formats each row consistently", {
  skip_if_not_installed("martin")
  text <- judgement:::catalogue_adjustable_text()
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  # Each adjustable equation produces 2 lines (header + indented metadata)
  starts <- grep("^- ", lines)
  expect_true(length(starts) > 30L,
              info = "expected at least 30 adjustable equations")
  # Every header line should have the (sector, equation_type) parenthetical
  for (i in starts[1:5]) {
    expect_match(lines[i], "\\([a-z_]+, [a-z_]+\\)")
  }
})

test_that("baseline_summary_text() handles NULL and empty cases", {
  expect_equal(baseline_summary_text(NULL), "(no baseline provided)")
  empty <- tibble::tibble(variable = character(), quarter = character(),
                          value = numeric())
  expect_equal(baseline_summary_text(empty),
               "(baseline has no headline variables)")
})

test_that("baseline_summary_text() trims to last 12 quarters per variable", {
  set.seed(1)
  many <- tibble::tibble(
    variable = "Y",
    quarter  = sprintf("%04dQ%d",
                       rep(2018:2024, each = 4),
                       rep(1:4, 7)),
    value    = stats::rnorm(28, 100, 5)
  )
  txt <- baseline_summary_text(many, variables = "Y")
  # Count comma-separated quarter=value pairs
  n_pairs <- length(strsplit(txt, ", ", fixed = TRUE)[[1]])
  expect_equal(n_pairs, 12L)
})

test_that("parse_proposal_to_adjustment() round-trips a valid proposal", {
  skip_if_not_installed("martin")
  p <- list(
    equation        = "PTM",
    horizon_start   = "2026Q1",
    horizon_end     = "2026Q3",
    # PTM is units=log_diff; values within the 0.02 ceiling.
    values          = c(0.001, 0.0008, 0.0005),
    rationale       = "Sustained services-price pressure from migration",
    channel         = "PTM -> P -> PC",
    expected_effect = "+0.15pp headline CPI by 2026Q4",
    confidence      = "medium",
    tail            = "carry"
  )
  a <- judgement:::parse_proposal_to_adjustment(
    p, round_id = "test", owner = "llm"
  )
  expect_s3_class(a, "adjustment")
  expect_equal(a$equation, "PTM")
  expect_equal(a$horizon, c("2026Q1", "2026Q2", "2026Q3"))
  expect_equal(a$value, c(0.001, 0.0008, 0.0005))
  expect_equal(a$source, "llm")
  # A well-formed proposal is NOT coerced.
  expect_false(a$coerced)
})

test_that("parse_proposal_to_adjustment() carries optional target fields", {
  skip_if_not_installed("martin")
  p <- list(
    equation = "PTM", horizon_start = "2026Q1", horizon_end = "2026Q1",
    values = c(0.001), rationale = "sticky", confidence = "medium",
    tail = "carry", target_variable = "P", expected_direction = "up"
  )
  a <- judgement:::parse_proposal_to_adjustment(p)
  expect_equal(a$target_variable, "P")
  expect_equal(a$expected_direction, "up")
})

test_that("parse_proposal_to_adjustment() treats empty optional fields as NA", {
  skip_if_not_installed("martin")
  p <- list(
    equation = "PTM", horizon_start = "2026Q1", horizon_end = "2026Q1",
    values = c(0.001), rationale = "sticky", confidence = "medium",
    tail = "carry", target_variable = "", expected_direction = NA
  )
  a <- judgement:::parse_proposal_to_adjustment(p)
  expect_true(is.na(a$target_variable))
  expect_true(is.na(a$expected_direction))
})

test_that("parse_proposal_to_adjustment() warns, pads, and flags coerced", {
  skip_if_not_installed("martin")
  p <- list(
    equation = "PTM",
    horizon_start = "2026Q1", horizon_end = "2026Q3",
    values = c(0.001, 0.0005),  # length 2, horizon length 3
    rationale = "test", confidence = "medium", tail = "zero"
  )
  expect_warning(
    a <- judgement:::parse_proposal_to_adjustment(p),
    "2 values for 3-quarter horizon"
  )
  expect_equal(a$value, c(0.001, 0.0005, 0.0005))  # padded with last
  expect_true(a$coerced)  # silent miscount now surfaced
})

test_that("parse_proposal_to_adjustment() warns, truncates, and flags coerced", {
  skip_if_not_installed("martin")
  p <- list(
    equation = "PTM",
    horizon_start = "2026Q1", horizon_end = "2026Q3",
    values = c(0.001, 0.0005, 0.0003, 0.0002),  # length 4, horizon length 3
    rationale = "test", confidence = "medium", tail = "zero"
  )
  expect_warning(
    a <- judgement:::parse_proposal_to_adjustment(p),
    "4 values for 3-quarter horizon"
  )
  expect_equal(a$value, c(0.001, 0.0005, 0.0003))  # truncated
  expect_true(a$coerced)
})

test_that("parse_proposal_to_adjustment() errors on missing fields", {
  expect_error(
    judgement:::parse_proposal_to_adjustment(
      list(equation = "PTM")
    ),
    "missing fields"
  )
})

test_that("projection_diff_text() computes per-variable diff strings", {
  baseline <- tibble::tibble(
    variable = rep(c("Y", "LUR"), each = 3),
    quarter  = rep(c("2026Q1", "2026Q2", "2026Q3"), 2),
    value    = c(100, 101, 102, 4.5, 4.4, 4.3),
    scenario = "baseline"
  )
  projection <- baseline
  projection$value <- projection$value + c(rep(1.0, 3), rep(0.1, 3))
  txt <- projection_diff_text(projection, baseline, variables = c("Y", "LUR"))
  # Y is a level variable: emits absolute diff + percent change.
  expect_match(txt, "Y\\b.*diff=\\+1\\.00")
  # LUR is a rate variable: emits diff in pp (the "(-5.2%)" form would be
  # percent-change-of-a-percent, which the describer has misread as pp).
  expect_match(txt, "LUR\\b.*diff=\\+0\\.10 pp")
  # Both heads include the plain-English glossary label.
  expect_match(txt, "Y \\[Real GDP")
  expect_match(txt, "LUR \\[Unemployment rate")
})

# ---- format_sensitivity_text() ------------------------------------------

sensitivity_fixture <- function() {
  tibble::tibble(
    equation       = c("PTM", "PTM", "PTM", "PTM",
                       "LUR", "LUR", "LUR",
                       "TLUR", "TLUR"),
    units          = c(rep("log_diff", 4), rep("level", 3), rep("percent", 2)),
    typical_af_sd  = c(rep(0.1, 4), rep(0.15, 3), rep(0.1, 2)),
    shock_value    = c(rep(0.001, 4), rep(0.05, 3), rep(0.1, 2)),
    shock_quarters = 4L,
    target         = c("PTM", "P", "Y", "NCR",
                       "LUR", "Y", "PTM",
                       "LUR", "NCR"),
    offset_q       = c(1L, 4L, 8L, 16L,
                       4L, 8L, 4L,
                       8L, 4L),
    deviation      = c(0.30, 2.86, -500, 0.5,
                       0.23, 1100, 0.00,
                       0.16, 0.47),
    deviation_pct  = c(0.26, 0.75, -0.10, 12.0,
                       4.43, 0.24, 0.00,
                       3.23, 14.0)
  )
}

test_that("format_sensitivity_text() renders per-equation blocks", {
  txt <- format_sensitivity_text(sensitivity_fixture())
  # Each equation header appears.
  expect_match(txt, "- PTM \\(units=log_diff")
  expect_match(txt, "- LUR \\(units=level")
  expect_match(txt, "- TLUR \\(units=percent")
  # Own-equation marker.
  expect_match(txt, "PTM.*own equation")
  # Rate variables use pp; level/log_diff variables use %.
  expect_match(txt, "LUR\\s*:.*h\\+4=\\+0\\.230pp")
  expect_match(txt, "PTM\\s*:.*h\\+4=\\+0\\.75%")
})

test_that("format_sensitivity_text() drops entries below pct_threshold", {
  # PTM -> PTM(0.26%) and PTM -> P(0.75%) survive a 0.05 threshold; the
  # PTM -> Y entry (-0.10%) is kept; the TLUR -> PTM entry (0.00%) drops
  # because it has no signal and isn't own-equation.
  fixture <- sensitivity_fixture()
  txt <- format_sensitivity_text(fixture, pct_threshold = 0.5)
  # Entries below threshold are absent.
  expect_false(grepl("LUR:.*PTM:.*h\\+4=\\+0\\.00%", txt))
})

test_that("format_sensitivity_text() handles empty + malformed inputs", {
  expect_match(
    format_sensitivity_text(tibble::tibble()),
    "no sensitivity matrix"
  )
  expect_match(
    format_sensitivity_text(tibble::tibble(equation = "PTM", target = "P")),
    "missing fields"
  )
})

test_that("format_sensitivity_text() ignores linearity columns when absent", {
  # The legacy matrix shape (no linearity_ok / converged) must still render
  # without caveats and without error.
  txt <- format_sensitivity_text(sensitivity_fixture())
  expect_false(grepl("NONLINEAR", txt))
  expect_false(grepl("NON-CONVERGED", txt))
})

test_that("format_sensitivity_text() surfaces a NONLINEAR caveat when flagged", {
  fixture <- sensitivity_fixture()
  # martin's new columns: flag the PTM -> P propagation as nonlinear.
  fixture$deviation_3x    <- fixture$deviation * 3
  fixture$curvature_ratio <- 1.0
  fixture$linearity_ok    <- TRUE
  fixture$converged       <- TRUE
  is_ptm_p <- fixture$equation == "PTM" & fixture$target == "P"
  fixture$linearity_ok[is_ptm_p]    <- FALSE
  fixture$curvature_ratio[is_ptm_p] <- 2.40
  txt <- format_sensitivity_text(fixture)
  expect_match(txt, "NONLINEAR")
  expect_match(txt, "curvature~2.40")
  # The header reflects the probe's decay_50 tail (the default for AF shocks).
  expect_match(txt, "decay_50")
})

test_that("format_sensitivity_text() surfaces a NON-CONVERGED caveat", {
  fixture <- sensitivity_fixture()
  fixture$converged <- TRUE
  is_lur_y <- fixture$equation == "LUR" & fixture$target == "Y"
  fixture$converged[is_lur_y] <- FALSE
  txt <- format_sensitivity_text(fixture)
  expect_match(txt, "NON-CONVERGED")
})

test_that("system_prompt_propose() includes sensitivity block when text given", {
  skip_if_not_installed("martin")
  with_sens <- system_prompt_propose(
    sensitivity_text = "- PTM (units=log_diff, ...):\n  PTM: h+4=+0.75%"
  )
  expect_match(with_sens, "Sensitivity matrix")
  expect_match(with_sens, "PTM: h\\+4=\\+0\\.75%")

  without_sens <- system_prompt_propose()
  expect_false(grepl("Sensitivity matrix", without_sens))
})
