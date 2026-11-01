#' Draft prose describing a projection relative to baseline
#'
#' Closes the round-trip loop: feed the solved projection back to the LLM
#' and let it write a description. If the description says different things
#' from the original narrative, the translation has failed somewhere — and
#' [compare_narrative_to_description()] surfaces that.
#'
#' The describer is **deliberately blind to the input narrative.** It sees
#' only the numerical diff from baseline. If we fed it the narrative it
#' would naturally mirror that framing, which makes the round-trip audit
#' trivially satisfied even when the projection's numbers actually
#' contradict the narrative. The `narrative` argument is retained but
#' ignored (kept for API back-compat, with a one-time deprecation warning).
#'
#' Free-form prose (not structured), since the description is meant to be
#' human-readable. Includes a compact diff-from-baseline summary in the
#' user message so the LLM is grounded in the numbers.
#'
#' @param projection A projection tibble from [martin::solve_martin()].
#' @param baseline   The baseline projection (also from
#'   [martin::solve_martin()]) the new one is being compared to.
#' @param narrative  Deprecated and ignored — the describer is blind by
#'   design. See the description above.
#' @param focus A character vector of variables to emphasise. Defaults to
#'   the SMP-style headline aggregates.
#' @param model Character. The `ellmer` model identifier.
#' @param chat An `ellmer::Chat` object (for testing).
#'
#' @return A character string of prose.
#' @export
describe_projection <- function(projection,
                                baseline,
                                narrative = NULL,
                                focus = c("Y", "RC", "GNE", "LUR", "PTM",
                                          "P", "NCR"),
                                model = "claude-opus-4-7",
                                chat  = NULL) {
  stopifnot(is.data.frame(projection), is.data.frame(baseline))
  if (!is.null(narrative)) {
    warning("`narrative` is deprecated and ignored: the describer is blind ",
            "by design so the round-trip audit can be meaningful.",
            call. = FALSE)
  }

  diff_text <- projection_diff_text(projection, baseline, variables = focus)

  user_msg <- paste(
    "Solved projection (differences from baseline on headline aggregates):",
    "",
    diff_text,
    "",
    "Draft a short, plain-English paragraph (3-6 sentences) describing how",
    "this projection differs from baseline. Lead with the headline numbers;",
    "be specific about quarters and magnitudes; never report a number that",
    "isn't in the diff summary above.",
    sep = "\n"
  )

  sysprompt <- paste(
    "You are SIBYL's projection describer. Given a difference summary,",
    "draft a short readable paragraph that a forecaster could paste into a",
    "round report. Never invent numbers; always reference the diff summary",
    "you were given. You do NOT have access to the narrative that produced",
    "the projection - describe what the numbers say, not what you think the",
    "forecaster intended.",
    sep = " "
  )
  chat <- get_chat(chat, system_prompt = sysprompt, model = model)
  chat$chat(user_msg)
}

#' Round-trip check: does the LLM's description match the narrative?
#'
#' Asks the LLM (with structured output) to compare the input narrative
#' against the description of the solved projection, and return a
#' claim-by-claim verdict. If `overall_match != "agree"`, the round has a
#' translation gap worth flagging in the report.
#'
#' @param narrative   The original narrative.
#' @param description The projection description from [describe_projection()].
#' @param model Character. The `ellmer` model identifier.
#' @param chat An `ellmer::Chat` object (for testing).
#' @return A tibble of `(claim, status, note)` plus an `overall_match`
#'   attribute.
#' @export
compare_narrative_to_description <- function(narrative,
                                             description,
                                             model = "claude-opus-4-7",
                                             chat  = NULL) {
  stopifnot(
    is.character(narrative),   length(narrative)   == 1L, nzchar(narrative),
    is.character(description), length(description) == 1L, nzchar(description)
  )
  prompt <- paste(
    "Narrative (the forecaster's framing of this round):",
    "",
    narrative,
    "",
    "Projection description (what the model actually produced):",
    "",
    description,
    "",
    paste(
      "Identify discrete claims in the narrative and verdict each one",
      "against the description: agree, disagree, or not_addressed. Provide",
      "an overall_match label too."
    ),
    sep = "\n"
  )

  sysprompt <- paste(
    "You are SIBYL's round-trip auditor. Compare a forecaster's narrative",
    "against a description of the solved projection and flag any",
    "translation failures. Be a strict reader: a claim only counts as",
    "'agree' if the description supports it specifically.",
    sep = " "
  )
  chat <- get_chat(chat, system_prompt = sysprompt, model = model)
  result <- chat$chat_structured(prompt, type = comparison_schema())

  # ellmer normalizes `type_array(items = type_object(...))` to a tibble
  # rather than a list-of-lists. Handle both shapes.
  tbl <- if (is.data.frame(result$claims)) {
    tibble::tibble(
      claim  = as.character(result$claims$claim),
      status = as.character(result$claims$status),
      note   = as.character(result$claims$note)
    )
  } else if (length(result$claims) == 0L) {
    tibble::tibble(claim = character(),
                   status = character(),
                   note = character())
  } else {
    tibble::tibble(
      claim  = vapply(result$claims, `[[`, character(1), "claim"),
      status = vapply(result$claims, `[[`, character(1), "status"),
      note   = vapply(result$claims, `[[`, character(1), "note")
    )
  }
  attr(tbl, "overall_match") <- as.character(result$overall_match)
  tbl
}

#' Diagnose disagree claims as translation gaps vs inevitable model responses
#'
#' For each row in `audit` flagged `disagree`, this helper attempts to
#' tell apart two distinct kinds of audit failure:
#'
#' * **translation_gap** — the narrative quantified a target on variable X
#'   and the projection's X didn't move there. Likely indicates an AF
#'   magnitude / equation-choice issue worth iterating on.
#' * **model_response** — the narrative asserted no change to variable X
#'   but the projection's X moved anyway. If X is an endogenous variable
#'   that MARTIN's structure forces to respond (e.g. NCR via the Taylor
#'   Rule when LUR shifts), this is the model behaving as designed, not
#'   a translation failure. The forecaster needs an additional AF on X
#'   to suppress the response, or accept it.
#'
#' Classification is heuristic: scans the claim text for variable names
#' and "no change" / "unchanged" patterns, then compares against the
#' projection-vs-baseline diff for the candidate variable.
#'
#' @param audit       The tibble returned by
#'   [compare_narrative_to_description()].
#' @param projection  A projection tibble from [martin::solve_martin()].
#' @param baseline    The baseline projection tibble.
#' @return A tibble with the audit columns plus:
#'   * `variable` — best-guess MARTIN variable the claim is about (or NA)
#'   * `diff_at_end` — projection - baseline at horizon end on that variable
#'   * `category` — one of `agree`, `not_addressed`, `translation_gap`,
#'     `model_response`, `narrative_conflict`, `unclassified`
#'   * `explanation` — short prose explaining the classification
#' @export
diagnose_audit <- function(audit, projection, baseline) {
  stopifnot(
    is.data.frame(audit),
    is.data.frame(projection),
    is.data.frame(baseline)
  )
  if (nrow(audit) == 0L) {
    return(tibble::tibble(
      claim = character(), status = character(), note = character(),
      variable = character(), diff_at_end = double(),
      category = character(), explanation = character()
    ))
  }

  # Build a quick (variable, last quarter) diff lookup.
  diff_lookup <- diff_at_horizon_end(projection, baseline)

  # Variables we know how to look up (matches the headline glossary).
  known_vars <- c("LUR", "TLUR", "NCR", "PTM", "P", "Y", "RC", "GNE",
                  "LE", "LF", "RBR", "LPR", "NMR", "PI_E", "RSTAR",
                  "PW", "PAE")

  rows <- lapply(seq_len(nrow(audit)), function(i) {
    claim <- audit$claim[i]
    status <- audit$status[i]
    note <- audit$note[i]

    # Quick exits for non-disagree statuses.
    if (identical(status, "agree")) {
      return(tibble::tibble(
        claim = claim, status = status, note = note,
        variable = NA_character_, diff_at_end = NA_real_,
        category = "agree", explanation = "Audit accepted the claim."
      ))
    }
    if (identical(status, "not_addressed")) {
      return(tibble::tibble(
        claim = claim, status = status, note = note,
        variable = NA_character_, diff_at_end = NA_real_,
        category = "not_addressed",
        explanation = paste("Description doesn't address this claim",
                            "(may be a causal/structural framing the",
                            "describer didn't restate).")
      ))
    }

    # disagree: try to identify the variable and classify.
    variable <- detect_variable_in_claim(claim, known_vars)
    asserts_no_change <- claim_asserts_no_change(claim)
    diff <- if (!is.na(variable)) diff_lookup[[variable]] else NA_real_

    category <- "unclassified"
    explanation <- "Could not detect a variable in the claim."
    if (!is.na(variable) && !is.null(diff)) {
      if (asserts_no_change && abs(diff) > 1e-6) {
        category <- "model_response"
        explanation <- sprintf(
          paste("Narrative asserted no change to %s but projection",
                "moved it by %+.3f units. Likely a MARTIN endogenous",
                "response (e.g. Taylor Rule / Phillips curve). Add an",
                "AF on %s to suppress, or accept the move."),
          variable, diff, variable
        )
      } else if (!asserts_no_change) {
        category <- "translation_gap"
        explanation <- sprintf(
          paste("Narrative quantified a target on %s but the projection",
                "shows diff %+.3f at horizon end. Magnitude / equation",
                "choice likely needs revision."),
          variable, diff
        )
      } else {
        # asserts_no_change & |diff| ~ 0, yet the audit marked this claim
        # `disagree`. The variable genuinely did NOT move, so this is most
        # likely an audit artifact: the LLM auditor flagged a disagreement
        # the numbers don't support (e.g. it keyed off framing rather than
        # the realised diff). Surfaced as `narrative_conflict` so a human
        # can reconcile the verbal verdict against the (null) numeric move.
        category <- "narrative_conflict"
        explanation <- sprintf(
          paste("Narrative asserted no change to %s and the projection",
                "agrees (diff %+.3f ~ 0), yet the audit marked this",
                "disagree. Likely an audit artifact -- the LLM verdict is",
                "not supported by the realised diff. Reconcile manually."),
          variable, diff
        )
      }
    }

    tibble::tibble(
      claim = claim, status = status, note = note,
      variable = variable %||% NA_character_,
      diff_at_end = diff %||% NA_real_,
      category = category,
      explanation = explanation
    )
  })

  out <- dplyr::bind_rows(rows)
  attr(out, "overall_match") <- attr(audit, "overall_match")
  out
}

# Pick the first known MARTIN variable that appears as a whole word in the
# claim, preferring longer matches (TLUR before LUR) so we don't grab the
# wrong one. Falls back to a plain-English keyword map.
#
# CRITICAL ordering: the keyword map is scanned in order and returns on the
# first hit, so the SPECIFIC inflation phrasings (trimmed-mean / underlying /
# core -> PTM) MUST precede the generic "inflation" -> P. Otherwise a claim
# about "trimmed-mean inflation" would be misrouted to headline P and the
# diff lookup would compare the wrong variable.
detect_variable_in_claim <- function(claim, known_vars) {
  if (!is.character(claim) || length(claim) != 1L) return(NA_character_)
  # Order by descending name length so TLUR matches before LUR, etc.
  ordered <- known_vars[order(-nchar(known_vars))]
  for (v in ordered) {
    pat <- sprintf("(?<![A-Z_])%s(?![A-Z_])", v)
    if (grepl(pat, claim, perl = TRUE)) return(v)
  }
  # Plain-English keyword -> variable mapping. ORDER MATTERS: most specific
  # phrasings first. Trimmed-mean / underlying / core inflation -> PTM must
  # come before the generic "inflation" -> P.
  keyword_map <- c(
    "unemployment rate"       = "LUR",
    "jobless rate"            = "LUR",
    "cash rate"               = "NCR",
    "cash-rate"               = "NCR",
    "policy rate"             = "NCR",
    "mortgage rate"           = "NMR",
    "participation rate"      = "LPR",
    "trimmed-mean"            = "PTM",
    "trimmed mean"            = "PTM",
    "underlying inflation"    = "PTM",
    "core inflation"          = "PTM",
    "services inflation"      = "PTM",
    "headline inflation"      = "P",
    "consumer prices"         = "P",
    "consumer price"          = "P",
    "inflation"               = "P",
    "wage growth"             = "PW",
    "wage price"              = "PW",
    "wages"                   = "PW",
    "real output"             = "Y",
    "real gdp"                = "Y",
    "gdp"                     = "Y",
    "employment"              = "LE",
    "labour force"            = "LF"
  )
  claim_lower <- tolower(claim)
  for (kw in names(keyword_map)) {
    if (grepl(kw, claim_lower, fixed = TRUE)) return(unname(keyword_map[kw]))
  }
  NA_character_
}

# True if the claim asserts no change / unchanged / steady-state. Catches
# common wordings; not exhaustive.
claim_asserts_no_change <- function(claim) {
  if (!is.character(claim) || length(claim) != 1L) return(FALSE)
  patterns <- c(
    "no change",       "unchanged",      "no shift",
    "constant",        "remain the same", "remain steady",
    "stays? steady",   "stays? the same", "stays? constant",
    "stays? at",       "stays? unchanged", "remains? unchanged",
    "no movement",     "no impact on",    "no effect on",
    "kept at",         "held at",         "hold(s|ing)? steady",
    "no view change",  "no revision"
  )
  any(vapply(patterns, function(p) grepl(p, claim, ignore.case = TRUE,
                                          perl = TRUE),
             logical(1)))
}

# Build a (variable -> diff_at_horizon_end) named list.
diff_at_horizon_end <- function(projection, baseline) {
  q <- intersect(unique(projection$quarter), unique(baseline$quarter))
  if (length(q) == 0L) return(list())
  q_end <- max(q)
  p <- projection[projection$quarter == q_end, c("variable", "value"),
                  drop = FALSE]
  b <- baseline[baseline$quarter == q_end, c("variable", "value"),
                drop = FALSE]
  joined <- merge(p, b, by = "variable", suffixes = c("_p", "_b"))
  setNames(joined$value_p - joined$value_b, joined$variable)
}

#' Deterministic, LLM-independent fidelity check on an adjustment set
#'
#' For each adjustment that declares a `target_variable` and
#' `expected_direction`, compares the *declared* expectation against the
#' *realised* projection-minus-baseline diff (at horizon end) on that
#' variable. Unlike [compare_narrative_to_description()] this involves no LLM
#' call at all: it is a mechanical cross-check that the model actually moved
#' the variable the adjustment claimed to move, in the claimed direction.
#'
#' A row's `agrees` is:
#' * `TRUE`  if the realised diff's sign matches `expected_direction`
#'   (`up` -> positive, `down` -> negative, `none` -> within tolerance);
#' * `FALSE` if it contradicts the declared direction;
#' * `NA`    if the adjustment declared no target/direction, or the variable
#'   isn't present in the projection (nothing to check against).
#'
#' Adjustments with no declared `target_variable` are skipped (no row), since
#' there is nothing deterministic to audit.
#'
#' @param adjustments An [adjustment_list()] (the *approved* set, ideally).
#' @param projection  A projection tibble from `martin::solve_martin()`.
#' @param baseline    The baseline projection tibble.
#' @param tol Numeric tolerance below which a diff counts as "none"/no-move.
#'   Default 1e-6.
#' @return A tibble with columns `equation`, `target_variable`,
#'   `expected_direction`, `realised_diff`, `agrees`.
#' @seealso [diagnose_audit()] (the LLM-audit-driven classifier).
#' @export
mechanical_audit <- function(adjustments, projection, baseline, tol = 1e-6) {
  if (!inherits(adjustments, "adjustment_list")) {
    stop("`adjustments` must be an adjustment_list.", call. = FALSE)
  }
  stopifnot(is.data.frame(projection), is.data.frame(baseline))

  empty <- tibble::tibble(
    equation           = character(),
    target_variable    = character(),
    expected_direction = character(),
    realised_diff      = double(),
    agrees             = logical()
  )
  if (length(adjustments) == 0L) return(empty)

  diff_lookup <- diff_at_horizon_end(projection, baseline)

  rows <- lapply(adjustments, function(a) {
    tgt <- a$target_variable
    dir <- a$expected_direction
    # Skip adjustments that declared nothing to audit.
    if (is.null(tgt) || length(tgt) != 1L || is.na(tgt) || !nzchar(tgt)) {
      return(NULL)
    }
    realised <- if (tgt %in% names(diff_lookup)) {
      unname(diff_lookup[[tgt]])
    } else {
      NA_real_
    }
    agrees <- mechanical_direction_agrees(dir, realised, tol)
    tibble::tibble(
      equation           = a$equation,
      target_variable    = tgt,
      expected_direction = if (is.na(dir)) NA_character_ else as.character(dir),
      realised_diff      = realised,
      agrees             = agrees
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0L) return(empty)
  dplyr::bind_rows(rows)
}

# Compare a declared direction against a realised diff. Returns NA when there
# is nothing to compare (no direction declared, or the variable wasn't in the
# projection); otherwise a logical agreement.
mechanical_direction_agrees <- function(direction, realised, tol = 1e-6) {
  if (is.null(direction) || length(direction) != 1L || is.na(direction)) {
    return(NA)
  }
  if (is.na(realised)) return(NA)
  switch(
    as.character(direction),
    up   = realised >  tol,
    down = realised < -tol,
    none = abs(realised) <= tol,
    NA
  )
}
