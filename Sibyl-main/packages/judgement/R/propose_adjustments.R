#' Propose add-factor adjustments from a narrative
#'
#' Calls an LLM (via `ellmer`) with structured output to translate a
#' free-text narrative into a list of [adjustment()] proposals. The LLM is
#' given the [martin::equation_catalogue()] as its menu, the baseline
#' projection so it knows the counterfactual, and (optionally) historical
#' add-factors as in-context examples.
#'
#' The LLM does not forecast. It only proposes which equations to adjust,
#' how much, over what horizon, and why — all grounded in the narrative.
#' Every adjustment is validated against the catalogue before it's returned.
#'
#' @param narrative Character. The forecaster's narrative for this round.
#' @param baseline A baseline projection tibble from
#'   [martin::solve_martin()]. Used to give the LLM the counterfactual it's
#'   nudging.
#' @param round_id Character. Round identifier; propagated to every
#'   proposed adjustment.
#' @param owner   Character. Defaults to `"llm"`.
#' @param historical_afs A tibble of past adjustments (optional). Currently
#'   summarised as a text block appended to the user message; future
#'   versions may serialise more deliberately.
#' @param model Character. Anthropic model identifier passed to
#'   `ellmer::chat_anthropic()`. Defaults to `"claude-opus-4-7"`.
#' @param chat An `ellmer::Chat` object. If supplied, the function uses it
#'   directly (useful for testing with a mock chat). Otherwise a fresh
#'   `chat_anthropic()` is created.
#'
#' @return A [judgement::adjustment_list()].
#' @export
propose_adjustments <- function(narrative,
                                baseline           = NULL,
                                round_id           = NA_character_,
                                owner              = "llm",
                                historical_afs     = NULL,
                                sensitivity_matrix = NULL,
                                model              = "claude-opus-4-7",
                                chat               = NULL) {
  stopifnot(
    is.character(narrative), length(narrative) == 1L, nzchar(narrative)
  )

  prompt <- paste(
    "Forecast-round narrative:",
    "",
    narrative,
    "",
    "Baseline projection (headline aggregates):",
    "",
    baseline_summary_text(baseline),
    if (!is.null(historical_afs)) "" else NULL,
    if (!is.null(historical_afs)) "Historical add-factors (for calibration):" else NULL,
    if (!is.null(historical_afs)) format_historical_afs(historical_afs) else NULL,
    "",
    paste(
      "Return a structured proposal. Use an empty adjustments array if the",
      "narrative doesn't justify any specific quantitative changes."
    ),
    sep = "\n"
  )

  sens_text <- if (!is.null(sensitivity_matrix)) {
    format_sensitivity_text(sensitivity_matrix)
  } else NULL
  chat <- get_chat(
    chat, system_prompt = system_prompt_propose(sensitivity_text = sens_text),
    model = model
  )
  result <- chat$chat_structured(prompt, type = proposal_schema())
  parse_proposal_result(result, round_id = round_id, owner = owner,
                        source = "llm")
}

# Shared parser for chat_structured() results returning a `proposal_schema()`
# shape. Handles the empty-adjustments case + the tibble-vs-list normalisation
# ellmer does, then maps each row to an adjustment(). The proposal's
# `exogenize` list (variables the LLM wants held at baseline) is attached
# as the `"exogenize"` attribute on the returned adjustment_list.
parse_proposal_result <- function(result, round_id, owner, source) {
  exogenize <- extract_exogenize(result)

  if (is.null(result$adjustments) ||
      (is.data.frame(result$adjustments) && nrow(result$adjustments) == 0L) ||
      (!is.data.frame(result$adjustments) &&
       length(result$adjustments) == 0L)) {
    out <- adjustment_list()
    attr(out, "exogenize") <- exogenize
    return(out)
  }

  proposals <- if (is.data.frame(result$adjustments)) {
    lapply(seq_len(nrow(result$adjustments)), function(i) {
      row <- as.list(result$adjustments[i, , drop = FALSE])
      lapply(row, function(x) if (is.list(x) && length(x) == 1L) x[[1]] else x)
    })
  } else {
    result$adjustments
  }

  parsed <- lapply(proposals, function(p) {
    parse_proposal_to_adjustment(p, round_id = round_id, owner = owner,
                                 source = source)
  })
  out <- do.call(adjustment_list, parsed)
  attr(out, "exogenize") <- exogenize
  out
}

# Extract the `exogenize` character vector from a chat_structured() result.
# ellmer may return the array as either a list/character vector or (when
# items are simple strings) a base atomic vector.
extract_exogenize <- function(result) {
  ex <- result$exogenize
  if (is.null(ex) || (is.list(ex) && length(ex) == 0L) ||
      (is.atomic(ex) && length(ex) == 0L)) {
    return(character(0))
  }
  if (is.list(ex)) ex <- vapply(ex, as.character, character(1))
  ex <- as.character(ex)
  ex <- ex[nzchar(ex) & !is.na(ex)]
  unique(ex)
}

#' Refine an adjustment proposal using audit feedback
#'
#' Second-pass LLM call: takes the prior proposal, the projection it
#' produced, and the round-trip audit's verdict, and asks the LLM to
#' revise the adjustments to close the gaps the audit flagged.
#'
#' This is what closes the iterative-calibration loop:
#' [propose_adjustments()] → solve → [describe_projection()] →
#' [compare_narrative_to_description()] → if disagree, refine() → repeat.
#'
#' @param narrative   The forecaster's narrative (unchanged across iterations).
#' @param baseline    Baseline projection tibble (unchanged across iterations).
#' @param prior_adjustments The previous `adjustment_list` that produced
#'   `prior_description`.
#' @param prior_description The projection description from the prior solve.
#' @param audit       The round-trip audit tibble from
#'   [compare_narrative_to_description()], with its `overall_match` attr.
#' @param iteration   Integer ≥ 2; the iteration number being attempted.
#' @param round_id,owner,model,chat   See [propose_adjustments()].
#' @return A revised [adjustment_list()].
#' @export
refine_adjustments <- function(narrative,
                               baseline,
                               prior_adjustments,
                               prior_description,
                               audit,
                               iteration          = 2L,
                               round_id           = NA_character_,
                               owner              = "llm",
                               sensitivity_matrix = NULL,
                               model              = "claude-opus-4-7",
                               chat               = NULL) {
  stopifnot(
    is.character(narrative), length(narrative) == 1L, nzchar(narrative),
    inherits(prior_adjustments, "adjustment_list"),
    is.character(prior_description), length(prior_description) == 1L,
    is.data.frame(audit)
  )

  prompt <- paste(
    sprintf("Refinement pass (iteration %d).", as.integer(iteration)),
    "",
    "Forecast-round narrative (unchanged):",
    "",
    narrative,
    "",
    "Baseline projection (headline aggregates):",
    "",
    baseline_summary_text(baseline),
    "",
    "Your previous proposal:",
    "",
    format_prior_adjustments(prior_adjustments),
    "",
    "What the model actually produced with those adjustments:",
    "",
    prior_description,
    "",
    "Round-trip audit verdict:",
    "",
    sprintf("Overall: %s", attr(audit, "overall_match") %||% "unknown"),
    format_audit_table(audit),
    "",
    paste(
      "Revise your proposal to close the gaps the audit flagged. You may",
      "(a) adjust magnitudes on existing equations, (b) extend or shorten",
      "the horizon, (c) add additional add-factors on other equations to",
      "suppress unwanted endogenous responses (e.g. an NCR adjustment to",
      "hold the cash-rate path when the narrative says it shouldn't move),",
      "or (d) drop adjustments that produced unintended side effects.",
      "",
      "Return the COMPLETE revised proposal as a structured response - not",
      "just the changes. Do not abandon a working adjustment just because",
      "an audit claim it didn't address was marked not_addressed; only",
      "revise the parts the audit flagged as disagree."
    ),
    sep = "\n"
  )

  sens_text <- if (!is.null(sensitivity_matrix)) {
    format_sensitivity_text(sensitivity_matrix)
  } else NULL
  chat <- get_chat(
    chat, system_prompt = system_prompt_propose(sensitivity_text = sens_text),
    model = model
  )
  result <- chat$chat_structured(prompt, type = proposal_schema())
  parse_proposal_result(result, round_id = round_id, owner = owner,
                        source = "llm-refined")
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Render a prior adjustment_list as a compact text block for the refinement
# prompt - one line per adjustment plus its rationale.
format_prior_adjustments <- function(adjs) {
  if (length(adjs) == 0L) return("(none)")
  lines <- vapply(adjs, function(a) {
    sprintf(
      "- %s | horizon %s..%s (%d quarters) | values=%s | tail=%s\n    rationale: %s",
      a$equation, a$horizon[1], a$horizon[length(a$horizon)],
      length(a$horizon),
      paste(format(round(a$value, 4)), collapse = ","),
      a$tail, a$rationale
    )
  }, character(1))
  paste(lines, collapse = "\n")
}

# Render the audit tibble as a compact verdict block.
format_audit_table <- function(audit) {
  if (nrow(audit) == 0L) return("(no claims to verdict)")
  lines <- vapply(seq_len(nrow(audit)), function(i) {
    sprintf("- [%s] %s\n    note: %s",
            audit$status[i], audit$claim[i], audit$note[i])
  }, character(1))
  paste(lines, collapse = "\n")
}

#' Propose adjustments with iterative refinement against the round-trip audit
#'
#' The full agentic loop: [propose_adjustments()] gives an initial proposal,
#' the caller-supplied `solve_fn` produces a projection,
#' [describe_projection()] drafts a description (blind to the narrative),
#' [compare_narrative_to_description()] audits. If `overall_match != "agree"`
#' and we have iterations left, [refine_adjustments()] re-prompts the LLM
#' with the audit feedback and the loop repeats.
#'
#' Returns the **final** adjustment_list plus a per-iteration log so the
#' caller can inspect how the proposal evolved. The `solve_fn` callback
#' decouples this function from `martin::solve_martin()`'s signature -
#' callers wire in their own database, horizon, etc.
#'
#' @param narrative Character. The forecaster's narrative.
#' @param baseline  Baseline projection tibble.
#' @param solve_fn  Function taking an `adjustment_list` and returning a
#'   projection tibble. Typically a closure over a database + horizon.
#' @param max_iters Max number of total iterations (initial + refinements).
#'   Default 3 - one initial propose + up to two refinements.
#' @param round_id,owner,historical_afs,sensitivity_matrix Forwarded to
#'   [propose_adjustments()] / [refine_adjustments()].
#' @param model  Default Anthropic model identifier. Used when a more
#'   specific `model_*` argument is not provided.
#' @param model_propose,model_describe,model_audit  Per-step model
#'   overrides. The propose/refine step is the most token-heavy (full
#'   catalogue + sensitivity matrix + narrative); describe/audit are
#'   cheap. Typical config: `model_propose = "claude-sonnet-4-6"`,
#'   `model = "claude-haiku-4-5"` to keep describe + audit on Haiku.
#' @param chat An `ellmer::Chat` object (for testing).
#' @return A list with:
#'   * `adjustments`: the final `adjustment_list`.
#'   * `projection`: the final projection.
#'   * `description`: the final description.
#'   * `audit`: the final audit tibble.
#'   * `history`: a list of per-iteration entries, each with the same fields.
#'   * `provenance`: per-step model ids and whether a chat was supplied
#'     (test path) vs fresh role-specific chats (production), for auditability.
#' @export
propose_with_refinement <- function(narrative,
                                    baseline,
                                    solve_fn,
                                    max_iters          = 3L,
                                    round_id           = NA_character_,
                                    owner              = "llm",
                                    historical_afs     = NULL,
                                    sensitivity_matrix = NULL,
                                    model              = "claude-opus-4-7",
                                    model_propose      = NULL,
                                    model_describe     = NULL,
                                    model_audit        = NULL,
                                    chat               = NULL) {
  stopifnot(
    is.character(narrative), length(narrative) == 1L, nzchar(narrative),
    is.function(solve_fn),
    is.numeric(max_iters), max_iters >= 1L
  )
  # Per-step model overrides default to `model`. Allows e.g. Sonnet for the
  # token-heavy propose/refine step, Haiku for the cheap describe/audit.
  model_propose  <- model_propose  %||% model
  model_describe <- model_describe %||% model
  model_audit    <- model_audit    %||% model

  history <- list()
  adjustments <- propose_adjustments(
    narrative          = narrative,
    baseline           = baseline,
    round_id           = round_id,
    owner              = owner,
    historical_afs     = historical_afs,
    sensitivity_matrix = sensitivity_matrix,
    model              = model_propose,
    chat               = chat
  )

  for (iter in seq_len(as.integer(max_iters))) {
    exogenize <- attr(adjustments, "exogenize") %||% character(0)
    if (length(adjustments) == 0L && length(exogenize) == 0L) {
      history[[iter]] <- list(
        iteration = iter, adjustments = adjustments,
        exogenize = exogenize, projection = NULL,
        description = NULL, audit = NULL
      )
      break
    }
    projection <- solve_fn(adjustments, exogenize = exogenize)
    description <- describe_projection(
      projection = projection, baseline = baseline,
      model = model_describe, chat = chat
    )
    audit <- compare_narrative_to_description(
      narrative = narrative, description = description,
      model = model_audit, chat = chat
    )
    history[[iter]] <- list(
      iteration = iter, adjustments = adjustments,
      exogenize = exogenize, projection = projection,
      description = description, audit = audit
    )

    if (!isTRUE(attr(audit, "overall_match") == "agree") &&
        iter < as.integer(max_iters)) {
      adjustments <- refine_adjustments(
        narrative          = narrative,
        baseline           = baseline,
        prior_adjustments  = adjustments,
        prior_description  = description,
        audit              = audit,
        iteration          = iter + 1L,
        round_id           = round_id,
        owner              = owner,
        sensitivity_matrix = sensitivity_matrix,
        model              = model_propose,
        chat               = chat
      )
    } else {
      break
    }
  }

  # Pick the *best* iteration, not the last. The refinement LLM can
  # over-correct: it sees the audit flag a side effect (e.g. Taylor Rule
  # response) and adds an AF to suppress it that overshoots, producing a
  # worse audit on the next pass. Score by audit verdict, breaking ties
  # toward the earliest iteration (fewest AFs, simplest explanation).
  best_idx <- pick_best_iteration(history)
  best <- history[[best_idx]]
  # Provenance: the exact per-step model ids used, plus a note that in
  # production each step runs on a FRESH role-specific chat (chat = NULL),
  # so the blind describer is genuinely isolated from the proposer. Additive
  # and non-breaking -- callers that ignore it are unaffected.
  provenance <- list(
    model_propose  = model_propose,
    model_describe = model_describe,
    model_audit    = model_audit,
    supplied_chat  = !is.null(chat),
    note = if (is.null(chat)) {
      paste("Production path: propose / describe / audit each used a fresh",
            "role-specific chat (chat = NULL); the describer was blind to",
            "the narrative and to the proposer's context.")
    } else {
      paste("A chat object was supplied (test path); describe / audit shared",
            "the injected mock rather than fresh isolated chats.")
    }
  )
  list(
    adjustments = best$adjustments,
    exogenize   = best$exogenize,
    projection  = best$projection,
    description = best$description,
    audit       = best$audit,
    history     = history,
    best_iter   = best_idx,
    provenance  = provenance
  )
}

# Rank iterations by audit verdict (agree > partial > disagree), preferring
# the earliest iter on ties (simpler proposal). An iteration with no audit
# (empty proposals + early exit) ranks below any iteration that has one.
pick_best_iteration <- function(history) {
  if (length(history) == 1L) return(1L)
  score <- function(it) {
    if (is.null(it$audit)) return(-1L)
    m <- attr(it$audit, "overall_match")
    if (identical(m, "agree"))    return(3L)
    if (identical(m, "partial"))  return(2L)
    if (identical(m, "disagree")) return(1L)
    0L
  }
  scores <- vapply(history, score, integer(1))
  # Prefer earliest iter at the top score (tied -> simplest proposal).
  which.max(scores)
}

format_historical_afs <- function(historical_afs) {
  if (!is.data.frame(historical_afs) || nrow(historical_afs) == 0L) {
    return("(none)")
  }
  required <- c("equation", "value", "rationale")
  if (!all(required %in% names(historical_afs))) {
    return("(unrecognised shape; expected columns include equation, value, rationale)")
  }
  rows <- vapply(seq_len(nrow(historical_afs)), function(i) {
    r <- historical_afs[i, ]
    sprintf("- %s: value=%s, rationale=%s",
            r$equation, format(r$value), r$rationale)
  }, character(1))
  paste(rows, collapse = "\n")
}

#' Human-in-the-loop approval step
#'
#' Renders a proposed [adjustment_list()] as a tibble for human review. In
#' interactive mode, writes the table to a CSV path and blocks until the
#' user signs off; in non-interactive mode (or with `interactive = FALSE`),
#' returns the proposed list unchanged with a one-time message.
#'
#' The CSV round-trips through [as_tibble_adjustments()] (write) and a
#' validating reader (read). Edits to `value`, `rationale`, `tail`,
#' `confidence`, and `horizon` are honoured; the row order is preserved.
#' Deleting a row drops that adjustment.
#'
#' A hidden, non-editable `adjustment_id` column is written into the CSV so
#' rows are regrouped by a stable key on read (not by the user-editable
#' `(equation, rationale)` pair, which collides when two adjustments share an
#' equation and rationale over disjoint horizons).
#'
#' The proposal's `"exogenize"` attribute (variables to hold at baseline) is
#' persisted to a sidecar file (`paste0(csv_path, ".exogenize")`), shown to
#' the human, and re-attached to the approved list so it survives the gate.
#'
#' @param proposed An `adjustment_list`.
#' @param interactive Logical. Set `FALSE` to bypass the human gate (e.g. in
#'   tests or unattended pipelines).
#' @param csv_path Path to write the review CSV. Defaults to a tempfile.
#' @return An `adjustment_list` containing only the approved subset, carrying
#'   the same `"exogenize"` attribute as `proposed`.
#' @export
review_and_approve <- function(proposed,
                               interactive = base::interactive(),
                               csv_path    = NULL) {
  if (!inherits(proposed, "adjustment_list")) {
    stop("`proposed` must be an adjustment_list.", call. = FALSE)
  }
  if (length(proposed) == 0L) {
    return(proposed)
  }

  exogenize <- attr(proposed, "exogenize") %||% character(0)

  if (!isTRUE(interactive)) {
    message("review_and_approve: non-interactive mode; ",
            "returning proposed adjustments unchanged.")
    return(proposed)
  }

  if (is.null(csv_path)) {
    csv_path <- tempfile("sibyl-review-", fileext = ".csv")
  }

  # Write proposals with a hidden stable id keyed to the original list index
  # (one id per adjustment, broadcast over its horizon rows). The human edits
  # values / rationales / horizons but should not touch adjustment_id; it is
  # how reconstruct_adjustments regroups rows back into adjustments.
  tbl <- as_tibble_adjustments(proposed)
  tbl <- add_adjustment_ids(tbl, proposed)
  utils::write.csv(tbl, csv_path, row.names = FALSE)

  # Persist the exogenize list to a sidecar so it survives the round-trip.
  exo_path <- paste0(csv_path, ".exogenize")
  writeLines(exogenize, exo_path)

  cat("\n--- SIBYL review gate ----------------------------------------\n")
  cat("Proposed adjustments written to:\n  ", csv_path, "\n", sep = "")
  if (length(exogenize)) {
    cat("Variables to EXOGENISE (held at baseline) -- edit in:\n  ",
        exo_path, "\n", sep = "")
    cat("  ", paste(exogenize, collapse = ", "), "\n", sep = "")
  } else {
    cat("No variables exogenised this round.\n")
  }
  cat("Edit values / rationales / horizon, delete rows you reject,\n")
  cat("(leave the adjustment_id column alone), save, then press Enter.\n")
  readline(prompt = "Press Enter when ready: ")

  # Re-read and reconstruct adjustments, then re-attach the (possibly
  # human-edited) exogenize list from its sidecar.
  edited <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
  approved <- reconstruct_adjustments(edited, original = proposed)
  attr(approved, "exogenize") <- read_exogenize_sidecar(exo_path, exogenize)
  approved
}

# Broadcast a stable per-adjustment id onto the tibble's rows. The id is the
# original list position, zero-padded so lexical sort == numeric order. We
# join by the (equation, quarter) pair each row carries, but the canonical
# source of truth is the order of `proposed` -- so we build the id column by
# replaying the same expansion as_tibble_adjustments() used (one block of
# length(horizon) rows per adjustment, in list order).
add_adjustment_ids <- function(tbl, proposed) {
  ids <- unlist(lapply(seq_along(proposed), function(i) {
    rep(sprintf("af_%03d", i), length(proposed[[i]]$horizon))
  }))
  # as_tibble_adjustments() emits rows in the same order, so a direct bind is
  # correct and order-preserving.
  if (length(ids) != nrow(tbl)) {
    # Defensive: should never happen, but fall back to row index rather than
    # silently misaligning ids.
    ids <- sprintf("af_%03d", seq_len(nrow(tbl)))
  }
  tbl$adjustment_id <- ids
  tbl
}

# Read the exogenize sidecar back, falling back to `default` if the file is
# missing (e.g. a human deleted it). Empty file -> character(0).
read_exogenize_sidecar <- function(exo_path, default = character(0)) {
  if (!file.exists(exo_path)) return(default)
  lines <- readLines(exo_path, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]
  unique(lines)
}

# Reconstruct an adjustment_list from an edited review CSV.
#
# Rows are regrouped by the hidden `adjustment_id` column written at review
# time (see add_adjustment_ids()), NOT by (equation, rationale): two distinct
# adjustments can legitimately share an equation AND a rationale over disjoint
# horizons, and grouping on those user-editable fields would silently merge
# them and lose values. Grouping order follows the id order so the approved
# list preserves the proposal order.
#
# If `adjustment_id` is absent (e.g. a CSV written by an older version, or a
# hand-built fixture), we fall back to the legacy (equation, rationale) key.
# Per-adjustment metadata that isn't user-editable (channel, expected_effect,
# target_variable, expected_direction, round_id, owner) is recovered from the
# matching original proposal.
reconstruct_adjustments <- function(edited, original) {
  required <- c("equation", "quarter", "value", "rationale",
                "tail", "confidence")
  missing <- setdiff(required, names(edited))
  if (length(missing)) {
    stop("Edited CSV is missing columns: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  if (nrow(edited) == 0L) {
    return(adjustment_list())
  }

  use_ids <- "adjustment_id" %in% names(edited) &&
    !all(is.na(edited$adjustment_id))

  if (use_ids) {
    # Stable-id metadata lookup: id "af_001" -> original[[1]], etc.
    meta_lookup <- stats::setNames(
      as.list(original), sprintf("af_%03d", seq_along(original))
    )
    edited$.group_key <- as.character(edited$adjustment_id)
    # Preserve id order (numeric within "af_###") rather than split()'s sort.
    key_order <- unique(edited$.group_key)
  } else {
    # Legacy fallback: group on (equation, rationale).
    meta_lookup <- list()
    for (a in original) {
      key <- paste(a$equation, a$rationale, sep = "||")
      meta_lookup[[key]] <- a
    }
    edited$.group_key <- paste(edited$equation, edited$rationale, sep = "||")
    key_order <- unique(edited$.group_key)
  }

  groups <- split(edited, edited$.group_key)
  # Reorder split() output to the order keys first appear in the CSV.
  groups <- groups[key_order]

  result <- lapply(groups, function(g) {
    g <- g[order(g$quarter), , drop = FALSE]
    key <- g$.group_key[1]
    base_meta <- meta_lookup[[key]]
    adjustment(
      equation        = g$equation[1],
      horizon         = g$quarter,
      value           = as.numeric(g$value),
      rationale       = g$rationale[1],
      channel         = if (!is.null(base_meta)) base_meta$channel
                        else NA_character_,
      expected_effect = if (!is.null(base_meta)) base_meta$expected_effect
                        else NA_character_,
      confidence         = g$confidence[1],
      tail               = g$tail[1],
      target_variable    = if (!is.null(base_meta)) base_meta$target_variable
                           else NA_character_,
      expected_direction = if (!is.null(base_meta))
                             base_meta$expected_direction else NA_character_,
      owner           = if (!is.null(base_meta)) base_meta$owner
                        else NA_character_,
      round_id        = if (!is.null(base_meta)) base_meta$round_id
                        else NA_character_,
      source          = "human"
    )
  })
  do.call(adjustment_list, result)
}
