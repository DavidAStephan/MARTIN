# SIBYL end-to-end pipeline.
#
# Stages: data -> nowcast -> martin (baseline) -> judgement (propose AFs)
#         -> human review -> martin (with AFs) -> judgement (describe + audit)
#         -> Quarto report
#
# Runnable-offline caveat. The DEFAULT path is "live" (data_source = "live"),
# which fetches every implemented public source and merges the result against
# the bundled fixture. A fully offline / no-network run requires switching the
# `data_source` config target to "fixture" (reads only
# packages/martin/inst/extdata/martin_data_fixture.xlsx, synthesises a ragged
# edge, and reconstructs handover via nowcast — exercising the data path with
# no live access). Either way:
#   - Coefficients are FROZEN by default (estimation_end = NULL): every
#     behavioural equation is ESTIMATEd over the model file's embedded 2019Q3
#     sample end, reproducing the originally-published in-sample fit. Set
#     `estimation_end` to a quarter to deliberately re-estimate (see below).
#   - `propose_adjustments()` is bypassed (returns an empty adjustment list)
#     when ANTHROPIC_API_KEY is unset; the round shows the no-adjustment
#     baseline + a notice.
#   - The human-approval gate is ON by default. In an interactive session it
#     blocks on review; non-interactively it REQUIRES an explicit approval
#     token (SIBYL_APPROVE=1 or the `approve_token` config target) or it stops.
#
# Run with: `targets::tar_make()` or `just pipeline`.
# Visualise: `targets::tar_visnetwork()`.

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c(
    "tibble", "dplyr", "tidyr", "purrr",
    "sibyldata", "nowcast", "martin", "judgement"
  ),
  format   = "rds",
  error    = "stop"
)

# Make the local packages importable; pkgload::load_all picks up edits.
for (pkg in c("packages/judgement", "packages/martin",
              "packages/nowcast",   "packages/sibyldata")) {
  if (dir.exists(pkg)) try(pkgload::load_all(pkg, quiet = TRUE), silent = TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Helper: synthesise a ragged-edge database from a "complete" fixture so
# nowcast has something to do. Drops the last `n_chop` quarters from each
# handover variable; leaves non-handover series intact.
chop_for_ragged_edge <- function(db, n_chop = 2L) {
  hv <- intersect(nowcast::handover_variables(), names(db))
  for (v in hv) {
    full <- as.numeric(db[[v]])
    n <- length(full)
    if (n < (n_chop + 8L)) next  # skip short series
    tsp <- stats::tsp(db[[v]])
    yr <- floor(tsp[1] + 1e-9)
    q  <- round((tsp[1] - yr) * 4 + 1)
    db[[v]] <- bimets::TIMESERIES(
      full[1:(n - n_chop)],
      START = c(yr, q), FREQ = 4
    )
  }
  db
}

# Helper: best-effort provenance table for a database. to_martin_database()
# (live path) and merge_with_fallback() attach a "provenance" attribute; the
# bare fixture does not. When it's absent (fixture mode, or a hand-built db),
# classify the variable names from the catalogue so round metadata still has a
# source-class breakdown. Returns tibble(variable, source_class).
database_provenance_table <- function(db) {
  prov <- sibyldata::database_provenance(db)
  if (is.null(prov)) {
    prov <- sibyldata::classify_provenance(names(db))
  }
  prov
}

list(

  # ---------------------------------------------------------------------------
  # 1. Round configuration
  # ---------------------------------------------------------------------------
  tar_target(round_id,
    paste0(format(Sys.Date(), "%Y"), "Q",
           ((as.integer(format(Sys.Date(), "%m")) - 1) %/% 3) + 1,
           "_round1")
  ),

  # "live" (default) fetches from every implemented public source, pivots via
  # sibyldata::to_martin_database() (which includes the deterministic
  # dummy/scalar handlers), and merges the result against the fixture so
  # MARTIN's behavioural-equation TSRANGEs still have full histories for series
  # the live data can't reach back to. Switch to "fixture" for a no-network run
  # that reads packages/martin/inst/extdata/martin_data_fixture.xlsx directly.
  tar_target(data_source, "live"),

  # Data vintage. Stamped into every fetched row and used as sibyldata's cache
  # key; recorded in round_metadata so a round documents which vintage it read.
  # NOTE: under the current sibyldata, "vintage" is a fetch-date stamp, not a
  # true realtime/as-of pull — a live round is reproducible only insofar as the
  # parquet cache for this date is preserved.
  tar_target(data_vintage, Sys.Date()),

  # Non-interactive approval token. The human-approval gate (design principle
  # #4) blocks on review in an interactive session. For an UNATTENDED run the
  # gate auto-passes ONLY when this token is "1" (or env var SIBYL_APPROVE=1);
  # otherwise it stops, refusing to let proposals reach MARTIN unapproved.
  # Default "" = no auto-approval. Set to "1" here, or run with
  # SIBYL_APPROVE=1, to authorise an unattended round.
  tar_target(approve_token, Sys.getenv("SIBYL_APPROVE", unset = "")),

  # The narrative the round is built on. Plain string; edit in this file
  # or read from `narrative.txt` if you prefer.
  tar_target(narrative,
    paste(
      "We expect Australian employment growth to outpace the baseline",
      "model over the coming two years, reflecting persistent structural",
      "labour-supply tightness (long-COVID exits, care-economy demand,",
      "immigration composition). Unemployment runs roughly 1 percentage",
      "point below baseline from 2026Q2 onward, drifting further by",
      "end-2027. Cash-rate path is broadly unchanged; trimmed-mean",
      "inflation is consistent with the RBA's 2-3% target band."
    )
  ),

  # Solve horizon. Goes ~2.5 years past the data end, so the second
  # half of the run is a genuine endogenous projection (MARTIN solving
  # forward from the last quarter of hard data). Exogenous variables
  # are carried forward via `extend_exogenous()` so SIMULATE has a
  # value for every cell in TSRANGE. The judgement layer should place
  # AFs in this projection period (2026Q1 onward) to translate a
  # forecaster's narrative about the future into model-consistent
  # numbers.
  tar_target(horizon, c("2010Q1", "2028Q2")),

  # Re-estimation sample end. FROZEN BY DEFAULT (NULL): every behavioural
  # equation is ESTIMATEd over the model file's embedded 2019Q3 sample end,
  # reproducing the originally-published in-sample fit (design principle #6 —
  # "do not re-estimate coefficients without asking").
  #
  # To DELIBERATELY re-estimate, set this to a "yyyyQq" string, e.g.
  #   tar_target(estimation_end, "2025Q2")
  # Re-fitting past 2019Q3 re-estimates the free coefficients ACROSS the COVID
  # break, which materially changes them and departs from the published model.
  # The baseline / sensitivity_matrix / projection targets below all key their
  # `coefficients` argument off this value: NULL => "frozen", non-NULL =>
  # "reestimated".
  tar_target(estimation_end, NULL),

  # Number of stochastic replicas for the optional uncertainty-band target.
  # Set to 0L to skip the band solve entirely (the default-path deterministic
  # projection is unaffected either way).
  tar_target(n_band_draws, 200L),

  # ---------------------------------------------------------------------------
  # 2. Data — sibyldata (or fixture in v0)
  # ---------------------------------------------------------------------------
  tar_target(raw_database,
    {
      base_db <- if (data_source == "fixture") {
        martin::read_fixture()
      } else {
        # Pull every implemented source. Transient failures (e.g. ABS
        # download glitches) emit warnings via update_data()'s
        # tolerate_failures path; the merge step below backfills any
        # series that didn't materialise from live data.
        panel <- sibyldata::update_data(sources = "all", vintage = data_vintage)
        live  <- sibyldata::to_martin_database(panel)
        sibyldata::merge_with_fallback(live, martin::read_fixture())
      }
      # Extend exogenous variables to the solve horizon end. Required
      # because some fixture-only series (RAIN, NHFA-style dummies)
      # stop at the fixture's 2019Q3 end and need to be carried forward
      # so SIMULATE has values across the full horizon. Carry-forward is
      # safe for the cases this hits (dummies at 0, anchored constants);
      # variables MARTIN solves endogenously aren't affected.
      out <- sibyldata::extend_exogenous(base_db, end_quarter = horizon[2])
      # Preserve the provenance attribute through extend_exogenous so
      # round_metadata can report the live-vs-fixture breakdown.
      attr(out, "provenance") <- database_provenance_table(base_db)
      out
    }
  ),

  # Live-vs-fixture provenance breakdown for this round's database. A tibble
  # (variable, source_class) consumed by round_metadata (and the report). In
  # fixture mode every row classifies from the catalogue; in live mode the
  # source_class distinguishes genuine live fetches from fixture_fallback.
  tar_target(data_provenance, database_provenance_table(raw_database)),

  # The raw panel (tidy (series_id, source, date, value, vintage)) is
  # held separately from the bimets database so the monthly-indicator
  # bridge in step 3 can use un-aggregated monthly observations.
  # Re-runs update_data() (cached by sibyldata's parquet store), so
  # cold cost is ~10 min but only the first time per vintage.
  tar_target(raw_panel,
    if (data_source == "fixture") {
      NULL
    } else {
      sibyldata::update_data(sources = "all", vintage = data_vintage)
    }
  ),

  # Synthesise a ragged edge so nowcast has work to do; matches what
  # production looks like the moment after data refresh.
  tar_target(ragged_database, chop_for_ragged_edge(raw_database, n_chop = 2L)),

  # ---------------------------------------------------------------------------
  # 3. Nowcast — bridge the missing quarters using monthly indicators
  #    (`bridge_monthly`) where available, falling back to ARIMA otherwise.
  #    Bridge regressions:
  #      RC <- RT      (retail trade  -> household consumption)
  #      Y  <- HOURS   (hours worked  -> real GDP)
  #      LE <- LE_M    (LFS monthly LE -> quarterly LE; trivial bridge)
  # ---------------------------------------------------------------------------
  tar_target(monthly_indicators,
    if (is.null(raw_panel)) {
      list()  # fixture mode: no monthly indicators available
    } else {
      sibyldata::nowcast_monthly_indicators(
        raw  = raw_panel,
        vars = c("RT", "HOURS", "LE")
      )
    }
  ),

  tar_target(handover_forecasts,
    if (length(monthly_indicators) == 0L) {
      # Fixture mode or no monthly data: fall back to ARIMA.
      nowcast::nowcast_handover(ragged_database, h = 2L, method = "arima")
    } else {
      nowcast::nowcast_handover(
        ragged_database, h = 2L,
        method             = "bridge_monthly",
        bridge_indicators  = list(RC = "RT", Y = "HOURS", LE = "LE"),
        monthly_indicators = monthly_indicators
      )
    }
  ),

  tar_target(database_with_handover,
    nowcast::splice_handover(ragged_database, handover_forecasts)
  ),

  # ---------------------------------------------------------------------------
  # 4. MARTIN baseline solve — no add-factors. Frozen coefficients by default
  #    (estimation_end = NULL => "frozen"). attr(baseline,"convergence") is a
  #    list(converged, n_nonfinite) surfaced by baseline_convergence below.
  # ---------------------------------------------------------------------------
  tar_target(baseline,
    martin::solve_martin(
      database       = database_with_handover,
      adjustments    = NULL,
      horizon        = horizon,
      coefficients   = if (is.null(estimation_end)) "frozen" else "reestimated",
      estimation_end = estimation_end,
      scenario       = "baseline"
    )
  ),

  # Surface the baseline solve's convergence diagnostics as a first-class
  # target so the report never assumes a clean solve. Reads the attribute
  # attached by solve_martin().
  tar_target(baseline_convergence,
    attr(baseline, "convergence") %||%
      list(converged = NA, n_nonfinite = NA_integer_)
  ),

  # ---------------------------------------------------------------------------
  # 4b. Sensitivity matrix — pre-compute the realised propagation of a
  #     standardized unit shock on each adjustable equation, so the LLM
  #     can reason about magnitudes from observed numbers rather than
  #     guesses. Cached as a long tibble; only re-builds when database /
  #     horizon / estimation_end change. ~30s build on 56 equations.
  #
  #     probe_curvature = TRUE (explicit) also solves each equation at 3x the
  #     standardized shock and emits curvature_ratio / linearity_ok columns, so
  #     the propose prompt knows where linear scaling of a 4-quarter probe to a
  #     12-20-quarter shock is safe (MARTIN is nonlinear). The per-row
  #     `converged` flag blanks any shock whose solve left NaN/Inf, so garbage
  #     is never handed to the LLM.
  # ---------------------------------------------------------------------------
  tar_target(sensitivity_matrix,
    martin::sensitivity_matrix(
      database        = database_with_handover,
      baseline        = baseline,
      horizon         = horizon,
      estimation_end  = estimation_end,
      # Anchor shocks at the start of the projection period (just after
      # the last hard data) so the LLM sees forecast-period propagation
      # rather than in-sample backcast propagation. measure_offsets are
      # cropped to what fits the remaining horizon.
      shock_start     = "2026Q1",
      shock_quarters  = 4L,
      measure_offsets = c(1L, 4L, 8L),
      probe_curvature = TRUE,
      progress        = FALSE
    )
  ),

  # ---------------------------------------------------------------------------
  # 5. Judgement — narrative -> add-factor proposals, with iterative
  #    refinement against the round-trip audit. The orchestrator
  #    `propose_with_refinement()` runs:
  #      propose -> solve -> describe -> audit
  #      -> if audit disagrees, refine (re-prompt LLM with audit feedback)
  #      -> repeat up to max_iters times.
  #    The sensitivity_matrix is threaded into the propose + refine prompts
  #    so the LLM can pick AF magnitudes from observed propagation rather
  #    than guessing.
  #    ANTHROPIC_API_KEY absent => empty adjustment list (degraded but
  #    complete pipeline run).
  # ---------------------------------------------------------------------------
  tar_target(refined_round,
    if (nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
      solve_fn <- function(adj, exogenize = character(0)) {
        martin::solve_martin(
          database       = database_with_handover,
          adjustments    = adj,
          horizon        = horizon,
          coefficients   = if (is.null(estimation_end)) "frozen"
                           else "reestimated",
          estimation_end = estimation_end,
          scenario       = "refinement-iter",
          exogenize              = exogenize,
          baseline_for_exogenize = if (length(exogenize) > 0L) baseline
                                   else NULL
        )
      }
      judgement::propose_with_refinement(
        narrative          = narrative,
        baseline           = baseline,
        solve_fn           = solve_fn,
        max_iters          = 3L,
        round_id           = round_id,
        sensitivity_matrix = sensitivity_matrix,
        model              = "claude-haiku-4-5",
        # Sonnet 4.6 is more decisive on the token-heavy propose/refine
        # step (catalogue + sensitivity matrix in-context); describe and
        # audit stay on Haiku because they're cheap simple-text tasks.
        model_propose      = "claude-sonnet-4-6"
      )
    } else {
      message("[targets] ANTHROPIC_API_KEY not set; ",
              "skipping LLM refinement loop.")
      list(adjustments = judgement::adjustment_list(),
           exogenize = character(0),
           projection = NULL, description = NULL,
           audit = NULL, history = list())
    }
  ),

  tar_target(proposed_adjustments,
    {
      adj <- refined_round$adjustments
      # propose_with_refinement returns the best iteration's exogenize list
      # separately; re-attach it as the attribute review_and_approve reads
      # and persists across the gate.
      attr(adj, "exogenize") <-
        refined_round$exogenize %||% attr(adj, "exogenize") %||% character(0)
      adj
    }
  ),

  tar_target(refinement_history, refined_round$history),

  # ---------------------------------------------------------------------------
  # 6. Human-in-the-loop approval (design principle #4 — structural, ON by
  #    default). Interactive sessions block on review_and_approve(), which
  #    writes the proposals (and the exogenize sidecar) for the human to edit,
  #    then re-reads the approved subset. For an UNATTENDED run the gate
  #    auto-passes ONLY when an explicit approval token is present
  #    (approve_token == "1" / SIBYL_APPROVE=1); otherwise it stops, so
  #    proposals never reach MARTIN unapproved by accident.
  #
  #    The "exogenize" attribute survives the gate: review_and_approve persists
  #    it to a sidecar and re-attaches it to the returned approved list.
  # ---------------------------------------------------------------------------
  tar_target(approved_adjustments,
    {
      is_interactive <- base::interactive()
      if (!is_interactive && !identical(approve_token, "1")) {
        if (length(proposed_adjustments) == 0L &&
            length(attr(proposed_adjustments, "exogenize") %||%
                   character(0)) == 0L) {
          # Nothing to approve (e.g. no API key / empty proposal): the empty
          # list is trivially safe to pass through.
          message("[targets] No proposed adjustments to approve; ",
                  "passing the empty list through the gate.")
          proposed_adjustments
        } else {
          stop(
            "Human-approval gate (design principle #4) is ON and this is a ",
            "non-interactive run. Proposed adjustments must be reviewed ",
            "before MARTIN solves with them. To authorise an unattended ",
            "round, set the approve_token target to \"1\" or run with ",
            "SIBYL_APPROVE=1; for a real round, run targets::tar_make() in ",
            "an interactive R session to review them.",
            call. = FALSE
          )
        }
      } else {
        # Interactive: block on the real review gate. Non-interactive WITH the
        # token: review_and_approve(interactive = FALSE) returns the proposals
        # unchanged (still carrying the exogenize attribute).
        judgement::review_and_approve(
          proposed_adjustments,
          interactive = is_interactive
        )
      }
    }
  ),

  # ---------------------------------------------------------------------------
  # 7. MARTIN solve with approved adjustments. Frozen by default; the
  #    exogenize attribute (now surviving the approval gate) is read back here.
  # ---------------------------------------------------------------------------
  tar_target(projection,
    {
      exogenize <- attr(approved_adjustments, "exogenize") %||% character(0)
      martin::solve_martin(
        database       = database_with_handover,
        adjustments    = approved_adjustments,
        horizon        = horizon,
        coefficients   = if (is.null(estimation_end)) "frozen"
                         else "reestimated",
        estimation_end = estimation_end,
        scenario       = "with_adjustments",
        exogenize              = exogenize,
        baseline_for_exogenize = if (length(exogenize) > 0L) baseline
                                 else NULL
      )
    }
  ),

  # Surface the with-adjustments solve's convergence diagnostics, mirroring
  # baseline_convergence. The report should flag a non-converged projection
  # rather than presenting it as a clean number.
  tar_target(projection_convergence,
    attr(projection, "convergence") %||%
      list(converged = NA, n_nonfinite = NA_integer_)
  ),

  # ---------------------------------------------------------------------------
  # 7b. OPTIONAL uncertainty bands around the projection. Opt-in: gated on
  #     n_band_draws >= 2. Uses bimets::STOCHSIMULATE when available, else a
  #     documented add-factor-perturbation fallback (see attr "band_method").
  #     A missing STOCHSIMULATE or a solve failure degrades to NULL rather than
  #     failing the round — the deterministic projection is the substantive
  #     output. Frozen coefficients by default.
  # ---------------------------------------------------------------------------
  tar_target(projection_bands,
    if (is.numeric(n_band_draws) && n_band_draws >= 2L) {
      exogenize <- attr(approved_adjustments, "exogenize") %||% character(0)
      tryCatch(
        martin::solve_martin_stochastic(
          database       = database_with_handover,
          adjustments    = approved_adjustments,
          horizon        = horizon,
          coefficients   = if (is.null(estimation_end)) "frozen"
                           else "reestimated",
          estimation_end = estimation_end,
          scenario       = "with_adjustments",
          n_draws        = as.integer(n_band_draws),
          exogenize              = exogenize,
          baseline_for_exogenize = if (length(exogenize) > 0L) baseline
                                   else NULL
        ),
        error = function(e) {
          message("[targets] solve_martin_stochastic failed (",
                  conditionMessage(e), "); skipping uncertainty bands.")
          NULL
        }
      )
    } else {
      NULL
    }
  ),

  # ---------------------------------------------------------------------------
  # 7c. Round metadata — a single tibble/list documenting how this round was
  #     produced, for the report's provenance block. Captures coefficient mode,
  #     estimation_end, data vintage + source, approval status + approver, which
  #     sources failed (inferred from the live-vs-fixture provenance split), and
  #     the source-class breakdown.
  # ---------------------------------------------------------------------------
  tar_target(round_metadata,
    {
      is_interactive  <- base::interactive()
      coefficient_mode <- if (is.null(estimation_end)) "frozen" else "reestimated"
      approval_status <- if (is_interactive) {
        "interactive_review"
      } else if (identical(approve_token, "1")) {
        "token_auto_approved"
      } else {
        "not_required_empty"  # gate let an empty proposal through
      }
      approver <- if (is_interactive) {
        Sys.getenv("USER", unset = Sys.getenv("USERNAME", unset = "unknown"))
      } else if (identical(approve_token, "1")) {
        paste0("token:", Sys.getenv("USER",
                                    unset = Sys.getenv("USERNAME",
                                                       unset = "unattended")))
      } else {
        NA_character_
      }

      # Source-class breakdown. In live mode, a class of "fixture_fallback"
      # marks a MARTIN variable the live fetch could not supply (the merge
      # backfilled it). We summarise counts per class and, for live runs, list
      # the variables that fell back so the report can flag thin live coverage.
      prov <- data_provenance
      class_counts <- as.data.frame(
        table(factor(prov$source_class)),
        stringsAsFactors = FALSE
      )
      names(class_counts) <- c("source_class", "n")
      fell_back <- prov$variable[prov$source_class == "fixture_fallback"]

      list(
        round_id         = round_id,
        data_source      = data_source,
        data_vintage     = data_vintage,
        horizon          = horizon,
        coefficient_mode = coefficient_mode,
        estimation_end   = estimation_end %||% NA_character_,
        approval_status  = approval_status,
        approver         = approver,
        approved         = approval_status != "not_required_empty" ||
                           length(proposed_adjustments) == 0L,
        n_adjustments    = length(approved_adjustments),
        exogenize        = attr(approved_adjustments, "exogenize") %||%
                           character(0),
        baseline_converged   = isTRUE(baseline_convergence$converged),
        projection_converged = isTRUE(projection_convergence$converged),
        band_method      = if (!is.null(projection_bands)) {
                             attr(projection_bands, "band_method")
                           } else NA_character_,
        provenance_counts = class_counts,
        fixture_fallback_vars = fell_back
      )
    }
  ),

  # ---------------------------------------------------------------------------
  # 8. Judgement — describe the projection, round-trip check
  # ---------------------------------------------------------------------------
  tar_target(projection_description,
    if (nzchar(Sys.getenv("ANTHROPIC_API_KEY")) && length(approved_adjustments) > 0L) {
      judgement::describe_projection(
        projection = projection,
        baseline   = baseline,
        model      = "claude-haiku-4-5"
      )
    } else {
      paste(
        "(no description; either no adjustments were applied or",
        "ANTHROPIC_API_KEY is not set.)"
      )
    }
  ),

  tar_target(round_trip_check,
    if (nzchar(Sys.getenv("ANTHROPIC_API_KEY")) &&
        nzchar(projection_description) &&
        !startsWith(projection_description, "(no description")) {
      judgement::compare_narrative_to_description(
        narrative   = narrative,
        description = projection_description,
        model       = "claude-haiku-4-5"
      )
    } else {
      tibble::tibble(claim = character(),
                     status = character(),
                     note = character())
    }
  ),

  # Deterministic, LLM-independent fidelity gate. mechanical_audit() compares
  # each adjustment's declared target/direction against the realised
  # projection-minus-baseline diff — a check that holds even when no API key is
  # set, run alongside the LLM round-trip audit.
  tar_target(mechanical_audit,
    if (length(approved_adjustments) > 0L) {
      judgement::mechanical_audit(
        adjustments = approved_adjustments,
        projection  = projection,
        baseline    = baseline
      )
    } else {
      tibble::tibble(
        equation = character(), target_variable = character(),
        expected_direction = character(), realised_diff = numeric(),
        agrees = logical()
      )
    }
  ),

  # ---------------------------------------------------------------------------
  # 9. Render the round report. Uses quarto::quarto_render() inside a
  # regular target so a missing Quarto CLI is a soft skip rather than a
  # pipeline failure (the rest of the targets are the substantive output;
  # the report is downstream presentation).
  # ---------------------------------------------------------------------------
  tar_target(round_report,
    {
      # Force re-build whenever any consumed target changes.
      force(list(round_id, narrative, baseline, projection,
                 projection_description, round_trip_check,
                 round_metadata, mechanical_audit))
      qmd <- "reports/round.qmd"
      out <- "reports/round.html"
      qpath <- tryCatch(quarto::quarto_path(),
                        error = function(e) NULL)
      if (!requireNamespace("quarto", quietly = TRUE) ||
          is.null(qpath) || !nzchar(qpath)) {
        message("[targets] Quarto CLI not found; skipping report render. ",
                "Install via `brew install --cask quarto` and re-run.")
        return(list(path = out, rendered = FALSE))
      }
      quarto::quarto_render(qmd, quiet = TRUE)
      list(path = out, rendered = TRUE)
    }
  )
)
