# Tests for propose_adjustments(). The unit-test path injects a fake chat
# object that returns a fixed structured response — no network, no API key.
# A live test against Anthropic is provided too, skipped when ANTHROPIC_API_KEY
# isn't set.

# A minimal stand-in for an ellmer Chat object. propose_adjustments() only
# calls chat_structured(); set_system_prompt() is also called by get_chat()
# when chat is provided.
fake_chat <- function(structured_response) {
  structured <- structured_response
  list(
    set_system_prompt = function(p) invisible(NULL),
    chat_structured   = function(prompt, type) structured,
    chat              = function(prompt) {
      stop("fake_chat$chat() not configured for free-form calls.")
    }
  )
}

# Drive review_and_approve()'s interactive gate without a human: mock base
# readline() so the call returns immediately. `on_prompt` (optional) runs at
# the moment the human would be editing files, letting a test splice in an
# edit to the review CSV or exogenize sidecar before the re-read.
with_mocked_readline <- function(expr, on_prompt = NULL) {
  expr <- substitute(expr)
  env <- parent.frame()
  testthat::with_mocked_bindings(
    eval(expr, env),
    readline = function(prompt = "") {
      if (!is.null(on_prompt)) on_prompt()
      ""
    },
    .package = "base"
  )
}

baseline_fixture <- function() {
  tibble::tibble(
    variable = rep(c("Y", "LUR", "PTM"), each = 4),
    quarter  = rep(c("2026Q1", "2026Q2", "2026Q3", "2026Q4"), 3),
    value    = c(100, 101, 102, 103, 4.2, 4.2, 4.1, 4.1, 0.6, 0.6, 0.6, 0.6),
    scenario = "baseline"
  )
}

test_that("propose_adjustments() parses a structured response", {
  skip_if_not_installed("martin")
  response <- list(
    reasoning = "Two adjustments motivated by migration / fiscal narrative",
    adjustments = list(
      list(
        equation        = "PTM",
        horizon_start   = "2026Q1",
        horizon_end     = "2026Q3",
        # PTM is units=log_diff (ceiling 0.02/quarter); use realistic values.
        values          = c(0.001, 0.0008, 0.0005),
        rationale       = "Sustained services-price pressure from migration",
        channel         = "PTM -> P -> PC",
        expected_effect = "+0.15pp headline CPI by 2026Q4",
        confidence      = "medium",
        tail            = "carry"
      ),
      list(
        equation        = "NCR",
        horizon_start   = "2026Q2",
        horizon_end     = "2026Q4",
        values          = c(0.25, 0.25, 0.25),
        rationale       = "Faster rate normalisation than baseline",
        channel         = "NCR -> RCR -> RC",
        expected_effect = "Cash rate 25bp higher through end-2026",
        confidence      = "high",
        tail            = "carry"
      )
    )
  )
  al <- propose_adjustments(
    narrative = paste(
      "Services inflation stays elevated and the RBA hikes faster."
    ),
    baseline  = baseline_fixture(),
    round_id  = "test-round",
    chat      = fake_chat(response)
  )
  expect_s3_class(al, "adjustment_list")
  expect_length(al, 2L)
  expect_equal(al[[1]]$equation, "PTM")
  expect_equal(al[[1]]$horizon, c("2026Q1", "2026Q2", "2026Q3"))
  expect_equal(al[[1]]$source, "llm")
  expect_equal(al[[1]]$round_id, "test-round")
  expect_equal(al[[2]]$equation, "NCR")
  expect_equal(al[[2]]$tail, "carry")
})

test_that("propose_adjustments() returns empty list for empty response", {
  skip_if_not_installed("martin")
  response <- list(reasoning = "narrative is qualitative; no adjustments",
                   adjustments = list())
  al <- propose_adjustments(
    narrative = "Things look broadly on track.",
    baseline  = baseline_fixture(),
    chat      = fake_chat(response)
  )
  expect_s3_class(al, "adjustment_list")
  expect_length(al, 0L)
})

test_that("propose_adjustments() rejects empty narrative", {
  expect_error(
    propose_adjustments(narrative = "", baseline = baseline_fixture(),
                        chat = fake_chat(list(adjustments = list()))),
    "nzchar"
  )
})

test_that("propose_adjustments() warns + recovers on values length mismatch", {
  skip_if_not_installed("martin")
  # values length mismatch on PTM -- parser is now lenient (warns + pads)
  response <- list(
    reasoning = "test",
    adjustments = list(list(
      equation        = "PTM",
      horizon_start   = "2026Q1",
      horizon_end     = "2026Q3",
      # PTM is units=log_diff; keep within the 0.02 ceiling.
      values          = c(0.001, 0.0005),  # only 2, horizon is 3
      rationale       = "test",
      channel         = NA,
      expected_effect = NA,
      confidence      = "medium",
      tail            = "zero"
    ))
  )
  expect_warning(
    al <- propose_adjustments(
      narrative = "test", baseline = baseline_fixture(),
      chat = fake_chat(response)
    ),
    "PTM.*2 values for 3-quarter horizon"
  )
  expect_length(al, 1L)
  expect_equal(al[[1]]$value, c(0.001, 0.0005, 0.0005))  # padded with last
  expect_true(al[[1]]$coerced)  # silent miscount is now flagged
})

test_that("propose_adjustments() rejects non-adjustable equations", {
  skip_if_not_installed("martin")
  response <- list(
    reasoning = "test",
    adjustments = list(list(
      equation        = "Y",                       # identity -- not adjustable
      horizon_start   = "2026Q1",
      horizon_end     = "2026Q1",
      values          = c(1.0),
      rationale       = "test",
      channel         = NA,
      expected_effect = NA,
      confidence      = "medium",
      tail            = "zero"
    ))
  )
  expect_error(
    propose_adjustments(
      narrative = "test", baseline = baseline_fixture(),
      chat = fake_chat(response)
    ),
    "not adjustable"
  )
})

test_that("review_and_approve() bypasses the gate in non-interactive mode", {
  skip_if_not_installed("martin")
  # PTM is a log_diff equation; keep the value under the 0.02 per-quarter
  # ceiling enforced by validate_adjustment_bounds() at construction.
  a <- adjustment(
    equation = "PTM", horizon = c("2026Q1", "2026Q2"),
    value = c(0.01, 0.005), rationale = "test", tail = "zero",
    confidence = "medium", source = "llm"
  )
  al <- adjustment_list(a)
  expect_message(
    review_and_approve(al, interactive = FALSE),
    "non-interactive"
  )
  out <- suppressMessages(review_and_approve(al, interactive = FALSE))
  expect_identical(out, al)
})

test_that("review_and_approve() returns empty list when given empty list", {
  out <- review_and_approve(adjustment_list(), interactive = TRUE)
  expect_length(out, 0L)
})

test_that("review_and_approve() persists + reattaches the exogenize list", {
  skip_if_not_installed("martin")
  a <- adjustment(
    equation = "PTM", horizon = c("2026Q1", "2026Q2"),
    value = c(0.001, 0.001), rationale = "sticky services inflation",
    tail = "carry", confidence = "medium", source = "llm"
  )
  proposed <- adjustment_list(a)
  attr(proposed, "exogenize") <- c("NCR", "PI_E")

  csv_path <- tempfile("sibyl-review-", fileext = ".csv")
  # Drive the interactive gate non-interactively by stubbing readline(); the
  # human "accepts" without editing.
  approved <- with_mocked_readline(
    review_and_approve(proposed, interactive = TRUE, csv_path = csv_path)
  )
  # Sidecar exists and carries the exogenize variables.
  expect_true(file.exists(paste0(csv_path, ".exogenize")))
  expect_setequal(
    readLines(paste0(csv_path, ".exogenize")), c("NCR", "PI_E")
  )
  # The approved list carries the SAME exogenize attribute as the proposal.
  expect_setequal(attr(approved, "exogenize"), attr(proposed, "exogenize"))
})

test_that("review_and_approve() honours a human-edited exogenize sidecar", {
  skip_if_not_installed("martin")
  a <- adjustment(
    equation = "PTM", horizon = c("2026Q1", "2026Q2"),
    value = c(0.001, 0.001), rationale = "sticky services inflation",
    tail = "carry", confidence = "medium", source = "llm"
  )
  proposed <- adjustment_list(a)
  attr(proposed, "exogenize") <- c("NCR")

  csv_path <- tempfile("sibyl-review-", fileext = ".csv")
  exo_path <- paste0(csv_path, ".exogenize")
  # The "human" edits the sidecar between write and re-read: drops NCR, adds
  # PI_E. We splice that edit in by overriding readline to rewrite the file.
  approved <- with_mocked_readline(
    review_and_approve(proposed, interactive = TRUE, csv_path = csv_path),
    on_prompt = function() writeLines("PI_E", exo_path)
  )
  expect_setequal(attr(approved, "exogenize"), "PI_E")
})

test_that("reconstruct_adjustments() survives equation+rationale collisions", {
  skip_if_not_installed("martin")
  # Two distinct adjustments, SAME equation AND rationale, DISJOINT horizons.
  # Grouping on (equation, rationale) would merge them and lose values;
  # grouping on the stable adjustment_id must keep both intact.
  a1 <- adjustment(
    equation = "NCR", horizon = c("2026Q1", "2026Q2"),
    value = c(0.25, 0.25), rationale = "same rationale",
    tail = "carry", confidence = "medium", source = "llm"
  )
  a2 <- adjustment(
    equation = "NCR", horizon = c("2027Q1", "2027Q2"),
    value = c(0.50, 0.50), rationale = "same rationale",
    tail = "carry", confidence = "high", source = "llm"
  )
  proposed <- adjustment_list(a1, a2)

  tbl <- as_tibble_adjustments(proposed)
  tbl <- judgement:::add_adjustment_ids(tbl, proposed)
  # Two distinct ids despite identical (equation, rationale).
  expect_length(unique(tbl$adjustment_id), 2L)

  rebuilt <- judgement:::reconstruct_adjustments(tbl, original = proposed)
  expect_length(rebuilt, 2L)
  # Order preserved; both horizons + values intact.
  expect_equal(rebuilt[[1]]$horizon, c("2026Q1", "2026Q2"))
  expect_equal(rebuilt[[1]]$value, c(0.25, 0.25))
  expect_equal(rebuilt[[2]]$horizon, c("2027Q1", "2027Q2"))
  expect_equal(rebuilt[[2]]$value, c(0.50, 0.50))
})

test_that("reconstruct_adjustments() falls back to legacy key without ids", {
  skip_if_not_installed("martin")
  a <- adjustment(
    equation = "NCR", horizon = c("2026Q1", "2026Q2"),
    value = c(0.25, 0.25), rationale = "legacy",
    tail = "carry", confidence = "medium", source = "llm"
  )
  proposed <- adjustment_list(a)
  tbl <- as_tibble_adjustments(proposed)  # no adjustment_id column
  rebuilt <- judgement:::reconstruct_adjustments(tbl, original = proposed)
  expect_length(rebuilt, 1L)
  expect_equal(rebuilt[[1]]$value, c(0.25, 0.25))
})

# ----- refine_adjustments() and propose_with_refinement() -----------------

# A chat fake that returns a queue of structured responses; pops one per
# chat_structured() call. Distinguishes structured vs free-form so the
# orchestrator can interleave propose / describe / audit calls.
fake_chat_queue <- function(structured_queue = list(), free_queue = character()) {
  s_i <- 0L
  f_i <- 0L
  list(
    set_system_prompt = function(p) invisible(NULL),
    chat_structured = function(prompt, type) {
      s_i <<- s_i + 1L
      if (s_i > length(structured_queue)) {
        stop("fake_chat_queue: out of structured responses (call ", s_i, ")")
      }
      structured_queue[[s_i]]
    },
    chat = function(prompt) {
      f_i <<- f_i + 1L
      if (f_i > length(free_queue)) {
        stop("fake_chat_queue: out of free responses (call ", f_i, ")")
      }
      free_queue[[f_i]]
    }
  )
}

# An adjustment_list fixture used as the "prior" input to refine_adjustments.
prior_al_fixture <- function() {
  adjustment_list(
    adjustment(
      equation        = "LUR",
      horizon         = c("2024Q1", "2024Q2"),
      value           = c(-0.05, -0.05),
      rationale       = "First-pass tightening",
      channel         = "LUR -> ...",
      expected_effect = "-0.1pp by 2024Q2",
      confidence      = "medium",
      tail            = "decay_50",
      owner           = "llm",
      round_id        = "test",
      source          = "llm"
    )
  )
}

# A revised proposal the fake LLM returns when refine() is called.
refine_response_fixture <- function() {
  list(
    reasoning = "Magnitude was too small; doubling the values.",
    adjustments = list(
      list(
        equation        = "LUR",
        horizon_start   = "2024Q1",
        horizon_end     = "2024Q2",
        values          = c(-0.10, -0.10),
        rationale       = "Doubled tightening to close the magnitude gap",
        channel         = "LUR -> ...",
        expected_effect = "-0.2pp by 2024Q2",
        confidence      = "medium",
        tail            = "decay_50"
      )
    )
  )
}

# Parsed-tibble shape for refine_adjustments() tests (which consume the
# downstream-of-compare result).
audit_fixture <- function(overall_match) {
  tbl <- tibble::tibble(
    claim  = c("LUR will fall by 0.2pp", "Cash rate unchanged"),
    status = c(if (overall_match == "agree") "agree" else "disagree", "agree"),
    note   = c("realised diff matches", "ok")
  )
  attr(tbl, "overall_match") <- overall_match
  tbl
}

# Raw-LLM shape for the orchestrator's fake chat (which returns this and
# lets compare_narrative_to_description parse it).
raw_audit_response <- function(overall_match) {
  list(
    overall_match = overall_match,
    claims = list(
      list(claim = "LUR will fall by 0.2pp",
           status = if (overall_match == "agree") "agree" else "disagree",
           note = "realised diff matches"),
      list(claim = "Cash rate unchanged",
           status = "agree",
           note = "ok")
    )
  )
}

test_that("refine_adjustments() takes audit feedback and returns revised list", {
  skip_if_not_installed("martin")
  out <- refine_adjustments(
    narrative         = "Tighter labour market lowering LUR by 0.2pp",
    baseline          = baseline_fixture(),
    prior_adjustments = prior_al_fixture(),
    prior_description = "LUR fell by only 0.05pp -- magnitude undershoot.",
    audit             = audit_fixture("disagree"),
    iteration         = 2L,
    chat              = fake_chat(refine_response_fixture())
  )
  expect_s3_class(out, "adjustment_list")
  expect_length(out, 1L)
  expect_equal(out[[1]]$value, c(-0.10, -0.10))
  expect_equal(out[[1]]$source, "llm-refined")
})

test_that("refine_adjustments() rejects bad inputs", {
  skip_if_not_installed("martin")
  expect_error(
    refine_adjustments(
      narrative = "", baseline = baseline_fixture(),
      prior_adjustments = prior_al_fixture(),
      prior_description = "x",
      audit = audit_fixture("disagree"),
      chat = fake_chat(refine_response_fixture())
    ),
    "nzchar"
  )
  expect_error(
    refine_adjustments(
      narrative = "x", baseline = baseline_fixture(),
      prior_adjustments = list(),   # not an adjustment_list
      prior_description = "x",
      audit = audit_fixture("disagree"),
      chat = fake_chat(refine_response_fixture())
    ),
    "adjustment_list"
  )
})

test_that("propose_with_refinement() stops at iter 1 when audit already agrees", {
  skip_if_not_installed("martin")
  initial_response <- list(
    reasoning = "First pass",
    adjustments = list(
      list(
        equation        = "LUR",
        horizon_start   = "2024Q1",
        horizon_end     = "2024Q2",
        values          = c(-0.10, -0.10),
        rationale       = "Initial tightening",
        channel         = "LUR -> ...",
        expected_effect = "-0.2pp by 2024Q2",
        confidence      = "medium",
        tail            = "decay_50"
      )
    )
  )
  audit_agree <- raw_audit_response("agree")
  chat <- fake_chat_queue(
    structured_queue = list(initial_response, audit_agree),
    free_queue       = c("LUR fell by 0.20pp")
  )
  solve_fn <- function(adj, exogenize = character(0)) {
    tibble::tibble(variable = "LUR",
                   quarter  = c("2024Q1", "2024Q2"),
                   value    = c(4.10, 4.10),
                   scenario = "scenario")
  }
  out <- propose_with_refinement(
    narrative = "LUR down 0.2pp by mid-2024",
    baseline  = baseline_fixture(),
    solve_fn  = solve_fn,
    max_iters = 3L,
    chat      = chat
  )
  expect_length(out$history, 1L)
  expect_identical(out$adjustments, out$history[[1]]$adjustments)
})

test_that("propose_with_refinement() iterates when audit disagrees", {
  skip_if_not_installed("martin")
  initial_response <- list(
    reasoning = "First pass (too small)",
    adjustments = list(
      list(
        equation        = "LUR",
        horizon_start   = "2024Q1",
        horizon_end     = "2024Q2",
        values          = c(-0.05, -0.05),
        rationale       = "Initial tightening",
        channel         = "LUR -> ...",
        expected_effect = "-0.1pp by 2024Q2",
        confidence      = "medium",
        tail            = "decay_50"
      )
    )
  )
  audit_disagree <- raw_audit_response("disagree")
  audit_agree    <- raw_audit_response("agree")
  chat <- fake_chat_queue(
    structured_queue = list(
      initial_response,           # propose call
      audit_disagree,             # 1st audit -> disagrees, trigger refine
      refine_response_fixture(),  # refine call returns doubled values
      audit_agree                 # 2nd audit -> agrees, loop exits
    ),
    free_queue = c("LUR fell by 0.05pp (undershoot)",
                   "LUR fell by 0.20pp (matches narrative)")
  )
  solve_fn <- function(adj, exogenize = character(0)) {
    # Return projection magnitude proportional to the AF values, so the
    # refined (doubled) AF produces a bigger effect than the initial.
    multiplier <- mean(adj[[1]]$value)
    tibble::tibble(variable = "LUR",
                   quarter  = c("2024Q1", "2024Q2"),
                   value    = c(4.20 + multiplier, 4.20 + multiplier),
                   scenario = "scenario")
  }
  out <- propose_with_refinement(
    narrative = "LUR down 0.2pp by mid-2024",
    baseline  = baseline_fixture(),
    solve_fn  = solve_fn,
    max_iters = 3L,
    chat      = chat
  )
  expect_length(out$history, 2L)
  expect_equal(out$adjustments[[1]]$value, c(-0.10, -0.10))
  expect_equal(out$adjustments[[1]]$source, "llm-refined")
  expect_identical(attr(out$audit, "overall_match"), "agree")
})

test_that("propose_with_refinement() respects max_iters cap", {
  skip_if_not_installed("martin")
  initial_response <- list(
    reasoning = "First pass",
    adjustments = list(
      list(
        equation        = "LUR",
        horizon_start   = "2024Q1",
        horizon_end     = "2024Q2",
        values          = c(-0.05, -0.05),
        rationale       = "Initial",
        channel         = "LUR -> ...",
        expected_effect = "test",
        confidence      = "medium",
        tail            = "decay_50"
      )
    )
  )
  audit_disagree <- raw_audit_response("disagree")
  # With max_iters=2, expect: propose, audit, refine, audit -- then stop
  # (refine + audit happen on iter 2, no third refine even though audit
  # still disagrees).
  chat <- fake_chat_queue(
    structured_queue = list(
      initial_response,
      audit_disagree,
      refine_response_fixture(),
      audit_disagree
    ),
    free_queue = c("descr 1", "descr 2")
  )
  solve_fn <- function(adj, exogenize = character(0)) {
    tibble::tibble(variable = "LUR",
                   quarter  = c("2024Q1", "2024Q2"),
                   value    = c(4.2, 4.2), scenario = "scenario")
  }
  out <- propose_with_refinement(
    narrative = "test", baseline = baseline_fixture(),
    solve_fn = solve_fn, max_iters = 2L, chat = chat
  )
  expect_length(out$history, 2L)
  expect_identical(attr(out$audit, "overall_match"), "disagree")
})

test_that("propose_with_refinement() keeps the best iteration when LLM over-corrects", {
  skip_if_not_installed("martin")
  initial_response <- list(
    reasoning = "First pass (good)",
    adjustments = list(
      list(
        equation        = "LUR",
        horizon_start   = "2024Q1",
        horizon_end     = "2024Q2",
        values          = c(-0.10, -0.10),
        rationale       = "Initial",
        channel         = "LUR -> ...",
        expected_effect = "-0.2pp",
        confidence      = "medium",
        tail            = "decay_50"
      )
    )
  )
  # First audit: partial (good). Refinement returns over-correction.
  # Second audit: disagree (worse). Orchestrator should still return iter 1.
  chat <- fake_chat_queue(
    structured_queue = list(
      initial_response,
      raw_audit_response("partial"),   # iter 1 audit: partial -> trigger refine
      refine_response_fixture(),       # over-corrected refinement
      raw_audit_response("disagree")   # iter 2 audit: worse -> stop
    ),
    free_queue = c("descr 1 good", "descr 2 over-corrected")
  )
  solve_fn <- function(adj, exogenize = character(0)) {
    tibble::tibble(variable = "LUR", quarter = c("2024Q1", "2024Q2"),
                   value = c(4.2, 4.2), scenario = "scenario")
  }
  out <- propose_with_refinement(
    narrative = "test", baseline = baseline_fixture(),
    solve_fn = solve_fn, max_iters = 2L, chat = chat
  )
  # Best is iter 1 (partial > disagree), even though loop ran 2 iters.
  expect_equal(out$best_iter, 1L)
  expect_identical(attr(out$audit, "overall_match"), "partial")
  expect_equal(out$adjustments[[1]]$value, c(-0.10, -0.10))
})

test_that("propose_with_refinement() exits early on empty initial proposal", {
  skip_if_not_installed("martin")
  empty_response <- list(reasoning = "narrative is qualitative",
                         adjustments = list())
  chat <- fake_chat_queue(structured_queue = list(empty_response))
  solve_fn <- function(adj, exogenize = character(0)) stop("solve_fn should not be called")
  out <- propose_with_refinement(
    narrative = "Things look fine.", baseline = baseline_fixture(),
    solve_fn = solve_fn, max_iters = 3L, chat = chat
  )
  expect_length(out$history, 1L)
  expect_length(out$adjustments, 0L)
  expect_null(out$projection)
})

# Live test: round-trips a real narrative through Anthropic Claude. Skipped
# when ANTHROPIC_API_KEY isn't set; expensive otherwise. The bar is "the
# pipeline runs and returns at least one valid adjustment on a narrative
# that obviously implies one", not "the LLM picks the best adjustment".
test_that("propose_adjustments() round-trips with live Anthropic Claude", {
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "",
          "ANTHROPIC_API_KEY not set")
  skip_on_cran()
  skip_if_not_installed("martin")
  skip_if_offline()

  al <- propose_adjustments(
    narrative = paste(
      "Services inflation has been persistently sticky in our latest data.",
      "We think trimmed-mean inflation stays roughly 0.1pp higher than",
      "baseline through 2026Q3, fading thereafter as labour-market slack",
      "opens up. No change to our view on the cash-rate path."
    ),
    baseline  = baseline_fixture(),
    round_id  = "live-test",
    model     = "claude-haiku-4-5"  # cheaper for tests
  )
  expect_s3_class(al, "adjustment_list")
  expect_gte(length(al), 1L)
  # Should propose a PTM adjustment given the narrative explicitly names it
  expect_true(any(vapply(al, function(a) a$equation == "PTM",
                         logical(1))),
              info = "expected at least one PTM adjustment for this narrative")
})
