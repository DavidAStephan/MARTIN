# Tests for describe_projection() and compare_narrative_to_description().
# Unit tests use a fake chat; live tests skip without ANTHROPIC_API_KEY.

fake_chat_str <- function(structured = NULL, free = NULL) {
  list(
    set_system_prompt = function(p) invisible(NULL),
    chat_structured   = function(prompt, type) structured,
    chat              = function(prompt) free
  )
}

projection_fixture <- function(scenario, y_offset = 0, lur_offset = 0) {
  tibble::tibble(
    variable = rep(c("Y", "LUR", "PTM"), each = 4),
    quarter  = rep(c("2026Q1", "2026Q2", "2026Q3", "2026Q4"), 3),
    value    = c(100 + y_offset, 101 + y_offset,
                 102 + y_offset, 103 + y_offset,
                 4.2 + lur_offset, 4.2 + lur_offset,
                 4.1 + lur_offset, 4.1 + lur_offset,
                 0.6, 0.6, 0.6, 0.6),
    scenario = scenario
  )
}

test_that("describe_projection() returns the LLM's free-form prose", {
  prose <- "GDP is about 1 unit higher than baseline by 2026Q4 ..."
  chat <- fake_chat_str(free = prose)
  out <- describe_projection(
    projection = projection_fixture("scenario", y_offset = 1),
    baseline   = projection_fixture("baseline"),
    chat       = chat
  )
  expect_identical(out, prose)
})

test_that("describe_projection() warns when a narrative is supplied", {
  chat <- fake_chat_str(free = "ok")
  expect_warning(
    describe_projection(
      projection = projection_fixture("scenario"),
      baseline   = projection_fixture("baseline"),
      narrative  = "anything",
      chat       = chat
    ),
    "deprecated"
  )
})

test_that("describe_projection() works without a narrative", {
  chat <- fake_chat_str(free = "ok")
  out <- describe_projection(
    projection = projection_fixture("scenario"),
    baseline   = projection_fixture("baseline"),
    chat       = chat
  )
  expect_identical(out, "ok")
})

test_that("compare_narrative_to_description() parses claims into a tibble", {
  response <- list(
    overall_match = "partial",
    claims = list(
      list(claim  = "Growth is firmer",
           status = "agree",
           note   = "Y is +1 by 2026Q4"),
      list(claim  = "Unemployment rises",
           status = "disagree",
           note   = "LUR is unchanged")
    )
  )
  out <- compare_narrative_to_description(
    narrative   = "Growth firmer; unemployment rises slightly.",
    description = "GDP up 1 unit; LUR unchanged.",
    chat        = fake_chat_str(structured = response)
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 2L)
  expect_setequal(names(out), c("claim", "status", "note"))
  expect_equal(attr(out, "overall_match"), "partial")
  expect_equal(out$status, c("agree", "disagree"))
})

test_that("compare_narrative_to_description() rejects empty inputs", {
  expect_error(
    compare_narrative_to_description("", "x", chat = fake_chat_str()),
    "nzchar"
  )
  expect_error(
    compare_narrative_to_description("x", "", chat = fake_chat_str()),
    "nzchar"
  )
})

# ---- diagnose_audit() ----------------------------------------------------

test_that("diagnose_audit() classifies translation gaps vs model responses", {
  audit <- tibble::tibble(
    claim = c(
      "Employment growth has been persistently stronger than the model predicts",
      "Unemployment rate will fall by roughly 1.5 percentage points",
      "No change to our view on the cash-rate path",
      "No change to inflation outlook"
    ),
    status = c("agree", "disagree", "disagree", "disagree"),
    note   = c("desc covers it", "actual diff smaller",
               "NCR actually moved", "P actually moved")
  )
  attr(audit, "overall_match") <- "disagree"

  baseline <- tibble::tibble(
    variable = c("LUR", "NCR", "P"),
    quarter  = "2025Q4",
    value    = c(5.5, 1.5, 100),
    scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = c("LUR", "NCR", "P"),
    quarter  = "2025Q4",
    value    = c(5.0, 5.3, 100.2),  # LUR -0.5pp (vs -1.5pp target),
                                     # NCR +3.8pp, P +0.2%
    scenario = "scenario"
  )

  out <- diagnose_audit(audit, projection, baseline)
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 4L)
  expect_setequal(
    names(out),
    c("claim", "status", "note", "variable", "diff_at_end",
      "category", "explanation")
  )
  # agree pass-through
  expect_equal(out$category[1], "agree")
  # LUR: quantified target, missed -> translation_gap
  expect_equal(out$variable[2], "LUR")
  expect_equal(out$category[2], "translation_gap")
  # NCR: "no change" but moved -> model_response
  expect_equal(out$variable[3], "NCR")
  expect_equal(out$category[3], "model_response")
  # P/inflation: "no change" but moved -> model_response
  expect_equal(out$variable[4], "P")
  expect_equal(out$category[4], "model_response")
  expect_equal(attr(out, "overall_match"), "disagree")
})

test_that("diagnose_audit() handles empty audit + unmatched variables", {
  empty <- tibble::tibble(claim = character(), status = character(),
                          note = character())
  baseline   <- tibble::tibble(variable = "Y", quarter = "2025Q4",
                                value = 100, scenario = "baseline")
  projection <- tibble::tibble(variable = "Y", quarter = "2025Q4",
                                value = 102, scenario = "scenario")
  expect_equal(nrow(diagnose_audit(empty, projection, baseline)), 0L)

  # Disagree with no recognizable variable -> unclassified.
  weird <- tibble::tibble(
    claim = "Something about widgets",
    status = "disagree", note = "?"
  )
  attr(weird, "overall_match") <- "disagree"
  out <- diagnose_audit(weird, projection, baseline)
  expect_equal(out$category, "unclassified")
  expect_true(is.na(out$variable))
})

test_that("diagnose_audit() detects variables via plain-English keywords", {
  audit <- tibble::tibble(
    claim = c("No change to the policy rate",
              "Headline inflation stays steady"),
    status = c("disagree", "disagree"),
    note   = c("rate moved", "prices moved")
  )
  attr(audit, "overall_match") <- "disagree"
  baseline <- tibble::tibble(
    variable = c("NCR", "P"), quarter = "2025Q4",
    value = c(2, 100), scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = c("NCR", "P"), quarter = "2025Q4",
    value = c(2.5, 100.3), scenario = "scenario"
  )
  out <- diagnose_audit(audit, projection, baseline)
  expect_equal(out$variable, c("NCR", "P"))
  expect_equal(out$category, c("model_response", "model_response"))
})

test_that("detect_variable_in_claim() routes trimmed-mean inflation to PTM", {
  known <- c("LUR", "TLUR", "NCR", "PTM", "P", "Y", "PW")
  # The bug: generic 'inflation' -> P would steal these. PTM phrasings must
  # win because they come first in the keyword map.
  expect_equal(
    judgement:::detect_variable_in_claim("trimmed-mean inflation eases", known),
    "PTM"
  )
  expect_equal(
    judgement:::detect_variable_in_claim("underlying inflation stays high", known),
    "PTM"
  )
  expect_equal(
    judgement:::detect_variable_in_claim("core inflation is sticky", known),
    "PTM"
  )
  # Generic headline inflation still maps to P.
  expect_equal(
    judgement:::detect_variable_in_claim("headline inflation rises", known),
    "P"
  )
  expect_equal(
    judgement:::detect_variable_in_claim("inflation broadly stable", known),
    "P"
  )
})

test_that("detect_variable_in_claim() maps wages and services", {
  known <- c("LUR", "NCR", "PTM", "P", "Y", "PW", "PAE")
  expect_equal(
    judgement:::detect_variable_in_claim("wage growth accelerates", known),
    "PW"
  )
  expect_equal(
    judgement:::detect_variable_in_claim("services inflation stays elevated", known),
    "PTM"
  )
})

test_that("detect_variable_in_claim() returns NA when no variable present", {
  known <- c("LUR", "NCR", "PTM", "P", "Y")
  expect_true(is.na(
    judgement:::detect_variable_in_claim("the outlook is broadly benign", known)
  ))
  # Non-scalar / non-character inputs are NA too.
  expect_true(is.na(judgement:::detect_variable_in_claim(NA, known)))
})

test_that("diagnose_audit() routes a trimmed-mean claim to PTM, not P", {
  audit <- tibble::tibble(
    claim  = "Trimmed-mean inflation will rise by 0.3pp",
    status = "disagree",
    note   = "undershoot"
  )
  attr(audit, "overall_match") <- "disagree"
  baseline <- tibble::tibble(
    variable = c("PTM", "P"), quarter = "2025Q4",
    value = c(0.6, 100), scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = c("PTM", "P"), quarter = "2025Q4",
    value = c(0.65, 100.5), scenario = "scenario"
  )
  out <- diagnose_audit(audit, projection, baseline)
  expect_equal(out$variable, "PTM")          # not P
  expect_equal(out$category, "translation_gap")
  expect_equal(out$diff_at_end, 0.05, tolerance = 1e-9)
})

test_that("diagnose_audit() flags an audit artifact as narrative_conflict", {
  # Claim asserts no change, the variable genuinely did NOT move, yet the
  # audit marked disagree -> narrative_conflict (likely an audit artifact).
  audit <- tibble::tibble(
    claim  = "No change to the cash rate path",
    status = "disagree",
    note   = "auditor disagreed despite no move"
  )
  attr(audit, "overall_match") <- "disagree"
  baseline <- tibble::tibble(
    variable = "NCR", quarter = "2025Q4", value = 3.0, scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = "NCR", quarter = "2025Q4", value = 3.0, scenario = "scenario"
  )
  out <- diagnose_audit(audit, projection, baseline)
  expect_equal(out$variable, "NCR")
  expect_equal(out$category, "narrative_conflict")
  expect_match(out$explanation, "audit artifact")
})

# ---- mechanical_audit() --------------------------------------------------

test_that("mechanical_audit() agrees when the realised diff matches direction", {
  skip_if_not_installed("martin")
  a <- adjustment(
    equation = "PTM", horizon = c("2026Q1", "2026Q2"),
    value = c(0.001, 0.001), rationale = "sticky inflation",
    tail = "carry", confidence = "medium", source = "llm",
    target_variable = "P", expected_direction = "up"
  )
  adjustments <- adjustment_list(a)
  baseline <- tibble::tibble(
    variable = "P", quarter = c("2026Q1", "2026Q2"),
    value = c(100, 100), scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = "P", quarter = c("2026Q1", "2026Q2"),
    value = c(100.2, 100.5), scenario = "scenario"  # P up at horizon end
  )
  out <- mechanical_audit(adjustments, projection, baseline)
  expect_s3_class(out, "tbl_df")
  expect_setequal(
    names(out),
    c("equation", "target_variable", "expected_direction",
      "realised_diff", "agrees")
  )
  expect_equal(out$target_variable, "P")
  expect_equal(out$realised_diff, 0.5, tolerance = 1e-9)
  expect_true(out$agrees)
})

test_that("mechanical_audit() disagrees on a contradicted direction", {
  skip_if_not_installed("martin")
  a <- adjustment(
    equation = "LUR", horizon = c("2026Q1", "2026Q2"),
    value = c(-0.05, -0.05), rationale = "tightening labour market",
    tail = "carry", confidence = "medium", source = "llm",
    target_variable = "LUR", expected_direction = "down"
  )
  adjustments <- adjustment_list(a)
  baseline <- tibble::tibble(
    variable = "LUR", quarter = c("2026Q1", "2026Q2"),
    value = c(4.0, 4.0), scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = "LUR", quarter = c("2026Q1", "2026Q2"),
    value = c(4.0, 4.2), scenario = "scenario"  # LUR rose -> contradicts down
  )
  out <- mechanical_audit(adjustments, projection, baseline)
  expect_false(out$agrees)
  expect_equal(out$realised_diff, 0.2, tolerance = 1e-9)
})

test_that("mechanical_audit() returns NA agreement when nothing to check", {
  skip_if_not_installed("martin")
  # One adjustment declares no target (skipped: no row); one declares a
  # target absent from the projection (row with agrees = NA).
  a_no_target <- adjustment(
    equation = "PTM", horizon = "2026Q1", value = 0.001,
    rationale = "no target declared", tail = "carry",
    confidence = "medium", source = "llm"
  )
  a_missing_var <- adjustment(
    equation = "NCR", horizon = "2026Q1", value = 0.25,
    rationale = "target not in projection", tail = "carry",
    confidence = "medium", source = "llm",
    target_variable = "RBR", expected_direction = "up"
  )
  adjustments <- adjustment_list(a_no_target, a_missing_var)
  baseline <- tibble::tibble(
    variable = "NCR", quarter = "2026Q1", value = 3.0, scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = "NCR", quarter = "2026Q1", value = 3.5, scenario = "scenario"
  )
  out <- mechanical_audit(adjustments, projection, baseline)
  # Only the target-declaring adjustment yields a row; RBR isn't in the
  # projection so agreement is NA.
  expect_equal(nrow(out), 1L)
  expect_equal(out$target_variable, "RBR")
  expect_true(is.na(out$realised_diff))
  expect_true(is.na(out$agrees))
})

test_that("mechanical_audit() handles 'none' direction and empty lists", {
  skip_if_not_installed("martin")
  expect_equal(
    nrow(mechanical_audit(adjustment_list(),
                          tibble::tibble(variable = character(),
                                         quarter = character(),
                                         value = numeric()),
                          tibble::tibble(variable = character(),
                                         quarter = character(),
                                         value = numeric()))),
    0L
  )
  a <- adjustment(
    equation = "NCR", horizon = "2026Q1", value = 0.0,
    rationale = "held flat", tail = "carry",
    confidence = "medium", source = "llm",
    target_variable = "NCR", expected_direction = "none"
  )
  baseline <- tibble::tibble(
    variable = "NCR", quarter = "2026Q1", value = 3.0, scenario = "baseline"
  )
  projection <- tibble::tibble(
    variable = "NCR", quarter = "2026Q1", value = 3.0, scenario = "scenario"
  )
  out <- mechanical_audit(adjustment_list(a), projection, baseline)
  expect_true(out$agrees)  # no move, direction none -> agrees
})

# Live tests
test_that("describe_projection() round-trips with live Anthropic Claude", {
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "",
          "ANTHROPIC_API_KEY not set")
  skip_on_cran()
  skip_if_offline()

  out <- describe_projection(
    projection = projection_fixture("scenario", y_offset = 2),
    baseline   = projection_fixture("baseline"),
    model      = "claude-haiku-4-5"
  )
  expect_type(out, "character")
  expect_gt(nchar(out), 50L)  # non-trivial paragraph
})

test_that("compare_narrative_to_description() works with live Anthropic", {
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "",
          "ANTHROPIC_API_KEY not set")
  skip_on_cran()
  skip_if_offline()

  out <- compare_narrative_to_description(
    narrative   = "Growth firmer; unemployment rises.",
    description = "GDP is about 2 units higher than baseline by 2026Q4. Unemployment is unchanged.",
    model       = "claude-haiku-4-5"
  )
  expect_s3_class(out, "tbl_df")
  expect_true(nrow(out) >= 1L)
  expect_true(attr(out, "overall_match") %in% c("agree", "partial", "disagree"))
})
