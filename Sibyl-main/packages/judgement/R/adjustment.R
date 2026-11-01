# The adjustment S3 class.
#
# An adjustment is the contract between four parties: a human narrating a
# judgement call, the LLM translating that narrative into specific
# perturbations of MARTIN equations, the bimets-shaped ConstantAdjustment list
# the model consumes, and the round-report prose. It carries enough metadata
# to flow through that whole pipeline.
#
# Tail behaviour governs how a deliberate judgement shock is extended past its
# explicit horizon. This matters because add-factors land on equation
# RESIDUALS, and most MARTIN behaviorals are written in growth-rate / first-
# difference form (TSDELTALOG / TSDELTA). On such an equation a *sustained*
# residual shock shifts the growth rate every quarter, so the LEVEL diverges
# without bound -- which is almost never what a narrative means. A narrative
# like "LUR runs ~1pp below baseline from 2026 onward" is a sustained LEVEL
# deviation: the per-quarter residual must taper once the target level is
# reached so the level CONVERGES rather than runs away.
#
#   - decay_50 (the default): geometric decay of the residual shock past the
#     horizon (the EViews `_a = _a(-1) * -0.5` rule from solve_model.prg). The
#     per-quarter shock tapers to ~0, so on a first-difference equation the
#     level converges to a finite deviation -- the right behaviour for a
#     sustained level target. (The same rule the reference uses to hand
#     historical residuals into the forecast period.)
#   - zero: truncate past the horizon; the level holds exactly at its end-of-
#     horizon deviation. Use for one-off announcements.
#   - carry: hold the last value forward. Correct ONLY for the rare equation
#     whose residual is on the LEVEL itself; on a growth-rate / first-
#     difference equation it makes the level diverge without bound (a sustained
#     LUR carry drove unemployment negative in a live round -- see git history).

#' Construct an adjustment
#'
#' An `adjustment` is a single judgemental perturbation of one MARTIN
#' equation over a horizon, with all the metadata required to flow through
#' SIBYL's pipeline (LLM proposal -> human review -> bimets solve -> report).
#'
#' @param equation Character. MARTIN equation code (e.g. `"PTM"`). Must match
#'   a row in [martin::equation_catalogue()] with `adjustable = TRUE`.
#' @param horizon  Character vector of quarters in `"yyyyQq"` form
#'   (e.g. `c("2026Q1", "2026Q2", "2026Q3")`).
#' @param value    Numeric vector the same length as `horizon` — the additive
#'   value applied to the equation's residual each period.
#' @param rationale Character. The "why" — typically lifted from the narrative
#'   the LLM read.
#' @param channel  Character. The chain of downstream variables the
#'   adjustment is expected to move (e.g. `"PTM -> P -> PC"`). Used in
#'   [describe_projection()] for the round-trip check.
#' @param expected_effect Character. Plain-English description of what the
#'   adjustment should do (e.g. `"+0.2pp CPI by 2027Q4"`).
#' @param confidence One of `"high"`, `"medium"`, `"low"`.
#' @param tail One of `"decay_50"` (default — geometric decay of the residual
#'   shock past the horizon, so a level target on a growth-rate / first-
#'   difference equation converges; reproduces the EViews `_a(-1) * -0.5`
#'   handover rule), `"zero"` (truncate beyond horizon — the level holds at its
#'   end-of-horizon value), or `"carry"` (hold the last value forward — correct
#'   only for equations whose residual is on the level itself; on a growth-rate
#'   / first-difference equation it makes the level diverge). See the note at
#'   the top of this file.
#' @param target_variable Character. The MARTIN variable the adjustment is
#'   primarily expected to move (e.g. `"P"` for a PTM adjustment). Optional;
#'   defaults to `NA`. Used by [mechanical_audit()] for the LLM-independent
#'   fidelity check.
#' @param expected_direction One of `"up"`, `"down"`, `"none"`, or `NA`
#'   (default). The direction `target_variable` is expected to move relative
#'   to baseline. Used by [mechanical_audit()].
#' @param coerced Logical. `TRUE` if the adjustment's `value` length was
#'   silently padded/truncated to match `horizon` during parsing (see
#'   [parse_proposal_to_adjustment()]). Defaults to `FALSE`. Surfaced so a
#'   silent miscount stays visible downstream.
#' @param owner    Character. Who proposed this adjustment.
#' @param round_id Character. The round this adjustment belongs to.
#' @param source   One of `"human"` or `"llm"`.
#'
#' @return An `adjustment` S3 object (a named list with class
#'   `c("adjustment", "list")`).
#'
#' @seealso [adjustment_list()], [validate_adjustment()],
#'   [expand_adjustments()] (numeric expansion onto a quarter range), and
#'   `martin::to_constant_adjustment_list()` (the bimets wrapper).
#' @export
adjustment <- function(equation,
                       horizon,
                       value,
                       rationale,
                       channel        = NA_character_,
                       expected_effect = NA_character_,
                       confidence     = c("medium", "high", "low"),
                       tail           = c("decay_50", "carry", "zero"),
                       target_variable   = NA_character_,
                       expected_direction = NA_character_,
                       coerced        = FALSE,
                       owner          = NA_character_,
                       round_id       = NA_character_,
                       source         = c("human", "llm", "llm-refined")) {
  confidence <- match.arg(confidence)
  tail       <- match.arg(tail)
  source     <- match.arg(source)

  obj <- list(
    equation           = equation,
    horizon            = horizon,
    value              = value,
    rationale          = rationale,
    channel            = channel,
    expected_effect    = expected_effect,
    confidence         = confidence,
    tail               = tail,
    target_variable    = target_variable,
    expected_direction = expected_direction,
    coerced            = isTRUE(coerced),
    owner              = owner,
    round_id           = round_id,
    source             = source
  )
  class(obj) <- c("adjustment", "list")
  validate_adjustment(obj)
}

#' Validate an adjustment object
#'
#' Checks types, lengths, and that `equation` is a known MARTIN equation
#' flagged adjustable in [martin::equation_catalogue()]. The catalogue check
#' is skipped if the `martin` package isn't loadable (e.g. when judgement is
#' being tested in isolation).
#'
#' Errors carry the field name so messages are easy to chase.
#'
#' @param x An object that should be an `adjustment`.
#' @return `x` invisibly. Throws on failure.
#' @export
validate_adjustment <- function(x) {
  if (!inherits(x, "adjustment")) {
    stop("Not an `adjustment` object.", call. = FALSE)
  }

  required <- c("equation", "horizon", "value", "rationale",
                "channel", "expected_effect", "confidence",
                "tail", "target_variable", "expected_direction",
                "coerced", "owner", "round_id", "source")
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop("adjustment is missing fields: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  if (!is.character(x$equation) || length(x$equation) != 1L || !nzchar(x$equation)) {
    stop("`equation` must be a non-empty single string.", call. = FALSE)
  }
  if (!is.character(x$horizon) || length(x$horizon) < 1L) {
    stop("`horizon` must be a non-empty character vector of `yyyyQq` quarters.",
         call. = FALSE)
  }
  # Reuse the shared parser; it throws on malformed strings with the same
  # "yyyyQq" hint.
  tryCatch(
    parse_quarter(x$horizon),
    error = function(e) stop("`horizon` values must match `yyyyQq` (e.g. `2026Q1`). ",
                             conditionMessage(e), call. = FALSE)
  )
  # Horizon must be strictly increasing — out-of-order quarters would silently
  # collide when expanded onto a continuous range.
  yq <- parse_quarter(x$horizon)
  idx <- quarter_index(yq$year, yq$quarter)
  if (any(diff(idx) <= 0L)) {
    stop("`horizon` quarters must be strictly increasing. Got: ",
         paste(x$horizon, collapse = ", "), call. = FALSE)
  }
  if (!is.numeric(x$value) || length(x$value) != length(x$horizon)) {
    stop("`value` must be numeric and the same length as `horizon`.",
         call. = FALSE)
  }
  if (!is.character(x$rationale) || length(x$rationale) != 1L || !nzchar(x$rationale)) {
    stop("`rationale` must be a non-empty single string. ",
         "Adjustments without a rationale defeat the point of SIBYL.",
         call. = FALSE)
  }
  if (!x$confidence %in% c("high", "medium", "low")) {
    stop("`confidence` must be one of high, medium, low.", call. = FALSE)
  }
  if (!x$tail %in% c("carry", "zero", "decay_50")) {
    stop("`tail` must be one of carry, zero, decay_50.", call. = FALSE)
  }
  if (!is.character(x$target_variable) || length(x$target_variable) != 1L) {
    stop("`target_variable` must be a single string (or NA_character_).",
         call. = FALSE)
  }
  if (!is.character(x$expected_direction) ||
      length(x$expected_direction) != 1L) {
    stop("`expected_direction` must be a single string (or NA_character_).",
         call. = FALSE)
  }
  if (!is.na(x$expected_direction) &&
      !x$expected_direction %in% c("up", "down", "none")) {
    stop("`expected_direction` must be one of up, down, none (or NA).",
         call. = FALSE)
  }
  if (length(x$coerced) != 1L || !is.logical(x$coerced) || is.na(x$coerced)) {
    stop("`coerced` must be a single non-NA logical.", call. = FALSE)
  }
  if (!x$source %in% c("human", "llm", "llm-refined")) {
    stop("`source` must be one of human, llm, llm-refined.", call. = FALSE)
  }

  # Magnitude / horizon guardrails. A naive add-factor of 0.1 on a log_diff
  # equation is +10pp/quarter, which compounds catastrophically; an absurdly
  # long horizon is almost always a miscount. These ceilings are GENEROUS
  # (they still admit any plausible deliberate shock) but catch catastrophe.
  # They are NOT keyed to typical_af_sd, which is documented-unreliable
  # (e.g. 0.1 on a log_diff equation would itself be catastrophic).
  validate_adjustment_bounds(x)

  # Cross-check against the catalogue if available. Soft check: if martin
  # isn't loadable (judgement tested standalone), skip silently.
  cat <- try(martin::equation_catalogue(), silent = TRUE)
  if (!inherits(cat, "try-error")) {
    row <- cat[cat$code == x$equation, , drop = FALSE]
    if (nrow(row) == 0L) {
      stop("Unknown MARTIN equation code: ", x$equation,
           ". See martin::equation_catalogue().", call. = FALSE)
    }
    if (!isTRUE(row$adjustable)) {
      stop("Equation `", x$equation,
           "` is flagged not adjustable in the equation catalogue ",
           "(typically because it's a pure identity).", call. = FALSE)
    }
  }

  invisible(x)
}

# Default per-unit, per-quarter magnitude ceilings for add-factor values.
# Derived from the equation's UNITS, not from typical_af_sd (which is
# documented-unreliable). Generous enough to admit any plausible deliberate
# shock, tight enough to catch catastrophe (a naive 0.1 on log_diff is
# +10pp/quarter and compounds explosively). Overridable via
# getOption("sibyl.af_ceiling") or the `ceilings` arg to
# validate_adjustment_bounds().
.default_af_ceilings <- function() {
  list(
    log_diff = 0.02,   # <= 0.02 quarterly log change ~ +8pp annualised
    level    = 1.0,    # <= 1.0 unit per quarter on the LHS difference
    percent  = 5.0,    # <= 5.0 percentage points per quarter
    unknown  = 5.0     # fall back to the loosest ceiling when units unknown
  )
}

# Hard ceiling on horizon length (in quarters). A horizon longer than this is
# almost always an LLM miscount rather than a deliberate decade-plus shock.
.default_horizon_ceiling <- 60L

#' Validate an adjustment's magnitude and horizon length against ceilings
#'
#' Rejects (with an error) any add-factor whose `|value|` exceeds a generous
#' per-unit, per-quarter ceiling, or whose horizon is implausibly long. The
#' per-unit ceiling is keyed to the equation's `units` column in
#' [martin::equation_catalogue()] (try-guarded; if `martin` is unavailable the
#' magnitude check soft-skips and only the horizon-length check runs).
#'
#' Override the ceilings for an intentional extreme shock either by setting
#' `options(sibyl.af_ceiling = list(log_diff = ..., level = ..., percent = ...))`
#' or by passing `ceilings`/`horizon_ceiling` directly.
#'
#' @param x An `adjustment` object.
#' @param ceilings Named list of per-unit ceilings (`log_diff`, `level`,
#'   `percent`). Defaults to `getOption("sibyl.af_ceiling")` then the package
#'   defaults.
#' @param horizon_ceiling Integer. Maximum allowed horizon length in quarters.
#'   Defaults to `getOption("sibyl.af_horizon_ceiling")` then 60.
#' @return `x` invisibly. Throws on failure.
#' @keywords internal
validate_adjustment_bounds <- function(x,
                                       ceilings        = NULL,
                                       horizon_ceiling = NULL) {
  # Horizon-length ceiling first (no martin dependency).
  horizon_ceiling <- horizon_ceiling %||%
    getOption("sibyl.af_horizon_ceiling", .default_horizon_ceiling)
  if (length(x$horizon) > horizon_ceiling) {
    stop(sprintf(
      paste("Adjustment on `%s` has a %d-quarter horizon, exceeding the",
            "ceiling of %d. This is almost always a horizon miscount; set",
            "options(sibyl.af_horizon_ceiling=) to override deliberately."),
      x$equation, length(x$horizon), horizon_ceiling), call. = FALSE)
  }

  ceilings <- ceilings %||% getOption("sibyl.af_ceiling") %||%
    .default_af_ceilings()

  # Resolve the equation's units from the catalogue (soft-skip if martin
  # isn't loadable, so judgement can still be tested standalone).
  units <- NA_character_
  cat <- try(martin::equation_catalogue(), silent = TRUE)
  if (!inherits(cat, "try-error")) {
    row <- cat[cat$code == x$equation, , drop = FALSE]
    if (nrow(row) == 1L && "units" %in% names(row)) {
      units <- as.character(row$units)
    }
  }
  if (is.na(units)) units <- "unknown"

  ceiling <- ceilings[[units]] %||% ceilings[["unknown"]] %||%
    .default_af_ceilings()[["unknown"]]
  worst <- suppressWarnings(max(abs(x$value)))
  if (is.finite(ceiling) && is.finite(worst) && worst > ceiling) {
    stop(sprintf(
      paste("Adjustment on `%s` (units=%s) has |value|=%g, exceeding the",
            "per-quarter ceiling of %g. A value this large on a %s residual",
            "compounds far beyond any plausible narrative. Override with",
            "options(sibyl.af_ceiling=) if this extreme shock is intended."),
      x$equation, units, worst, ceiling, units), call. = FALSE)
  }

  invisible(x)
}

#' Test whether an object is an adjustment
#'
#' @param x Any object.
#' @return `TRUE` if `x` inherits from `"adjustment"`.
#' @export
is_adjustment <- function(x) inherits(x, "adjustment")

#' @rdname adjustment
#' @export
format.adjustment <- function(x, ...) {
  hdr <- glue::glue(
    "<adjustment {x$equation}> ",
    "{length(x$horizon)} quarter(s), ",
    "{x$horizon[1]}..{x$horizon[length(x$horizon)]} ",
    "[tail={x$tail}, conf={x$confidence}, src={x$source}",
    "{if (isTRUE(x$coerced)) ', coerced' else ''}]"
  )
  body <- c(
    glue::glue("  value:     {paste(format(x$value, nsmall = 2), collapse = ', ')}"),
    glue::glue("  rationale: {x$rationale}"),
    if (!is.na(x$channel))         glue::glue("  channel:   {x$channel}"),
    if (!is.na(x$expected_effect)) glue::glue("  expected:  {x$expected_effect}"),
    if (!is.na(x$target_variable)) {
      dir <- if (is.na(x$expected_direction)) "NA" else x$expected_direction
      glue::glue("  target:    {x$target_variable} ({dir})")
    },
    if (!is.na(x$owner))           glue::glue("  owner:     {x$owner}"),
    if (!is.na(x$round_id))        glue::glue("  round:     {x$round_id}")
  )
  paste(c(hdr, body), collapse = "\n")
}

#' @rdname adjustment
#' @export
print.adjustment <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}

# -----------------------------------------------------------------------------
# adjustment_list — the collection used by the rest of the pipeline
# -----------------------------------------------------------------------------

#' Construct an adjustment list
#'
#' A typed wrapper around a list of [adjustment()] objects. Multiple
#' adjustments may target the same equation; they are summed when converted
#' to a bimets `ConstantAdjustment` list.
#'
#' @param ... `adjustment` objects.
#' @return An `adjustment_list` S3 object.
#' @export
adjustment_list <- function(...) {
  xs <- list(...)
  for (x in xs) validate_adjustment(x)
  class(xs) <- c("adjustment_list", "list")
  xs
}

#' @rdname adjustment_list
#' @export
print.adjustment_list <- function(x, ...) {
  if (length(x) == 0L) {
    cat("<adjustment_list, empty>\n")
    return(invisible(x))
  }
  cat("<adjustment_list, ", length(x), " item(s)>\n", sep = "")
  for (a in x) {
    cat(format(a), "\n", sep = "")
  }
  invisible(x)
}

#' Coerce an adjustment list to a tidy tibble
#'
#' Useful for showing the human reviewer a table before they approve.
#'
#' @param x An `adjustment_list`.
#' @return A tibble: one row per `(adjustment, horizon-quarter)` pair, with
#'   the metadata fields broadcast.
#' @export
as_tibble_adjustments <- function(x) {
  if (!inherits(x, "adjustment_list")) {
    stop("Expected an adjustment_list.", call. = FALSE)
  }
  if (length(x) == 0L) {
    return(tibble::tibble(
      equation = character(), quarter = character(), value = numeric(),
      rationale = character(), channel = character(),
      expected_effect = character(), confidence = character(),
      tail = character(), target_variable = character(),
      expected_direction = character(), coerced = logical(),
      owner = character(), round_id = character(),
      source = character()
    ))
  }
  rows <- purrr::map_dfr(x, function(a) {
    tibble::tibble(
      equation           = a$equation,
      quarter            = a$horizon,
      value              = a$value,
      rationale          = a$rationale,
      channel            = a$channel,
      expected_effect    = a$expected_effect,
      confidence         = a$confidence,
      tail               = a$tail,
      target_variable    = a$target_variable,
      expected_direction = a$expected_direction,
      coerced            = isTRUE(a$coerced),
      owner              = a$owner,
      round_id           = a$round_id,
      source             = a$source
    )
  })
  rows
}

#' Expand an adjustment list onto a continuous quarter range
#'
#' Produces a named list of numeric vectors keyed by MARTIN equation code.
#' Each vector is aligned to the quarters returned by `quarter_seq(solve_range[1],
#' solve_range[2])`. Bimets-shape conversion lives in `martin`; this function
#' deliberately has no bimets dependency.
#'
#' Per-adjustment behaviour:
#'
#' - Explicit horizon values are placed at the matching quarter positions.
#' - Cells before the first horizon quarter are zero.
#' - Cells after the last horizon quarter are filled per the adjustment's
#'   `tail` rule:
#'     - `"carry"`    — hold the last horizon value forward (the default).
#'     - `"zero"`     — zero.
#'     - `"decay_50"` — geometric decay with sign flip, reproducing the EViews
#'                      `_a = _a(-1) * -0.5` rule from
#'                      `references/MARTIN-master/Programs/solve_model.prg`.
#'                      That rule governs handover of *historical residuals*,
#'                      not deliberate shocks; as a sustained-shock tail it
#'                      oscillates sign, so prefer `carry`.
#'
#' Multiple adjustments targeting the same equation are summed element-wise.
#'
#' If an adjustment's entire horizon falls outside `solve_range` a warning is
#' issued and that adjustment contributes nothing. Partial overlap is allowed
#' silently — only the in-range portion is used (the tail rule continues to
#' extend from the last in-range horizon value).
#'
#' @param x An `adjustment_list` (possibly empty).
#' @param solve_range A length-2 character vector `c("yyyyQq", "yyyyQq")`
#'   identifying the inclusive simulation range.
#'
#' @return A named list. Names are equation codes; values are numeric vectors
#'   of length `length(quarter_seq(solve_range[1], solve_range[2]))`. The list
#'   carries `solve_range` and `quarters` attributes so downstream code can
#'   recover the alignment without re-parsing.
#' @export
expand_adjustments <- function(x, solve_range) {
  if (!inherits(x, "adjustment_list")) {
    stop("Expected an `adjustment_list`. Got: ", paste(class(x), collapse = "/"),
         call. = FALSE)
  }
  if (length(solve_range) != 2L || !is.character(solve_range)) {
    stop("`solve_range` must be a length-2 character vector ",
         "of `yyyyQq` strings.", call. = FALSE)
  }

  range_q <- quarter_seq(solve_range[1], solve_range[2])
  n <- length(range_q)

  out <- list()
  attr(out, "solve_range") <- solve_range
  attr(out, "quarters") <- range_q

  if (length(x) == 0L) return(out)

  for (a in x) {
    eq_values <- numeric(n)
    horizon_idx <- match(a$horizon, range_q)
    in_range <- !is.na(horizon_idx)

    if (!any(in_range)) {
      warning("Adjustment on `", a$equation,
              "` has no horizon quarters within solve_range; skipping.",
              call. = FALSE)
      next
    }

    eq_values[horizon_idx[in_range]] <- a$value[in_range]

    last_h_in_range <- max(horizon_idx[in_range])
    if (last_h_in_range < n) {
      last_val <- a$value[max(which(in_range))]
      tail_positions <- seq.int(last_h_in_range + 1L, n)
      step <- seq_along(tail_positions)
      tail_vals <- switch(
        a$tail,
        zero     = rep(0,        length(tail_positions)),
        carry    = rep(last_val, length(tail_positions)),
        decay_50 = last_val * (-0.5)^step
      )
      eq_values[tail_positions] <- tail_vals
    }

    out[[a$equation]] <- if (is.null(out[[a$equation]])) {
      eq_values
    } else {
      out[[a$equation]] + eq_values
    }
  }

  out
}
