# Deterministic dummy/trend/scalar series for MARTIN.
#
# These series are not data — they're functions of calendar date that the
# legacy EViews script (modify_data.prg:558-714) constructs and that the
# MARTIN equations reference by name. We materialise them in sibyldata so
# the live pipeline can solve without depending on the bundled fixture for
# these slots.
#
# Specs live in inst/extdata/{dummies,scalars}.csv. Each row in dummies.csv
# is one of:
#
#   pulse          1 at `from`, 0 elsewhere
#   tristate       1 at `from`, -1 at `to`, 0 elsewhere
#   range_lt       1 if quarter < `to`
#   range_gt       1 if quarter > `from`
#   range_ge       1 if quarter >= `from`
#   range_gt_lt    1 if `from` < quarter < `to`
#   trend_carry    @trend value over [from, to]; NA before; carry past `to`
#   counter_carry  0 before `from`; (1, 2, ...) over [from, to]; carry past `to`
#
# @trend values are pinned to the reference workfile start `1959Q3`
# (the start of the bundled fixture). This is necessary because the
# MARTIN equation coefficients were estimated against that reference;
# shifting the trend's zero point would silently break coefficient scaling.

# Reference workfile start. @trend(REFERENCE_TREND_ZERO) = 0; each
# subsequent quarter adds 1. Pinned to the fixture's first quarter.
REFERENCE_TREND_ZERO <- "1959Q3"

# Default horizon over which dummies are generated when the database is
# empty or has no existing series. The end date covers the longest forecast
# horizons referenced in modify_data.prg (2031Q4 for LUR_DUM, then padding).
DEFAULT_DUMMY_START <- "1959Q3"
DEFAULT_DUMMY_END   <- "2050Q4"

#' Apply deterministic dummy / trend series
#'
#' Reads `inst/extdata/dummies.csv` and materialises each row as a bimets
#' TIMESERIES over the database's existing span (or [DEFAULT_DUMMY_START]
#' to [DEFAULT_DUMMY_END] if the database is empty). Idempotent: rows
#' already in the database are left alone.
#'
#' @param database Named list of bimets TIMESERIES.
#' @param catalogue [series_catalogue()] (unused in v0; reserved for
#'   migrating the spec into the catalogue).
#' @return The database with dummy series added.
#' @keywords internal
apply_dummies <- function(database, catalogue = series_catalogue()) {
  spec <- dummies_spec()
  span <- database_span(database)
  for (i in seq_len(nrow(spec))) {
    mv <- spec$martin_var[i]
    if (!is.null(database[[mv]])) next
    database[[mv]] <- build_dummy_series(
      kind = spec$kind[i],
      from = spec$from[i],
      to   = spec$to[i],
      span = span
    )
  }
  database
}

#' Apply scalar (constant) series
#'
#' Reads `inst/extdata/scalars.csv` and materialises each row as a constant
#' bimets TIMESERIES spanning the database (matching [apply_dummies()]).
#' Only constants referenced symbolically in the model file (e.g.
#' `PI_TARGET` in the NCR Taylor Rule) are needed — most steady-state
#' scalars in `modify_data.prg` are inlined as literals in `MARTINMOD_AF.txt`
#' and not in scope.
#'
#' @inheritParams apply_dummies
#' @keywords internal
apply_scalars <- function(database, catalogue = series_catalogue()) {
  spec <- scalars_spec()
  span <- database_span(database)
  for (i in seq_len(nrow(spec))) {
    mv <- spec$martin_var[i]
    if (!is.null(database[[mv]])) next
    n <- span$n_quarters
    database[[mv]] <- bimets::TIMESERIES(
      rep(spec$value[i], n),
      START = c(span$start_year, span$start_quarter),
      FREQ  = 4
    )
  }
  database
}

# Load the dummy spec from inst/extdata/dummies.csv. Cached after first read.
dummies_spec <- function() {
  path <- system.file("extdata", "dummies.csv", package = "sibyldata")
  if (!nzchar(path)) {
    path <- file.path("inst", "extdata", "dummies.csv")  # pkgload fallback
  }
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
}

# Load the scalar spec from inst/extdata/scalars.csv.
scalars_spec <- function() {
  path <- system.file("extdata", "scalars.csv", package = "sibyldata")
  if (!nzchar(path)) {
    path <- file.path("inst", "extdata", "scalars.csv")  # pkgload fallback
  }
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
}

# Compute the (start_year, start_quarter, n_quarters) span covered by all
# series in the database. Falls back to DEFAULT_DUMMY_{START,END} when the
# database is empty. Always extends to at least 2050Q4 to cover dummies
# defined for the forecast horizon (e.g. LUR_DUM activates 2031Q4).
database_span <- function(database) {
  if (length(database) == 0L) {
    s <- parse_yyyyQq(DEFAULT_DUMMY_START)
    e <- parse_yyyyQq(DEFAULT_DUMMY_END)
    n <- quarter_index(e$year, e$quarter, s$year, s$quarter) + 1L
    return(list(
      start_year    = s$year,
      start_quarter = s$quarter,
      n_quarters    = n
    ))
  }
  starts <- sapply(database, function(x) stats::tsp(x)[1])
  ends   <- sapply(database, function(x) stats::tsp(x)[2])
  start_dec <- min(starts)
  end_dec   <- max(ends)

  # Always extend to DEFAULT_DUMMY_END so future-quarter dummies still
  # produce values past the live data's last observation. The model never
  # solves past the data end anyway, but dummies need to exist there for
  # exogenous-path workflows to work.
  default_end <- parse_yyyyQq(DEFAULT_DUMMY_END)
  default_end_dec <- default_end$year + (default_end$quarter - 1) / 4
  end_dec <- max(end_dec, default_end_dec)

  start_year    <- floor(start_dec + 1e-9)
  start_quarter <- round((start_dec - start_year) * 4 + 1)
  end_year      <- floor(end_dec + 1e-9)
  end_quarter   <- round((end_dec - end_year) * 4 + 1)
  n <- quarter_index(end_year, end_quarter,
                     start_year, start_quarter) + 1L
  list(
    start_year    = start_year,
    start_quarter = start_quarter,
    n_quarters    = n
  )
}

# Build one dummy bimets ts spanning [span$start, span$start + span$n - 1].
build_dummy_series <- function(kind, from, to, span) {
  n <- span$n_quarters
  y0 <- span$start_year
  q0 <- span$start_quarter

  # Quarter index of `from` and `to` relative to span start. NA if absent.
  from_idx <- if (is.na(from)) NA_integer_ else
    quarter_index_str(from, y0, q0)
  to_idx   <- if (is.na(to))   NA_integer_ else
    quarter_index_str(to,   y0, q0)

  vals <- switch(kind,
    pulse         = build_pulse(n, from_idx),
    tristate      = build_tristate(n, from_idx, to_idx),
    range_lt      = build_range_lt(n, to_idx),
    range_gt      = build_range_gt(n, from_idx),
    range_ge      = build_range_ge(n, from_idx),
    range_gt_lt   = build_range_gt_lt(n, from_idx, to_idx),
    trend_carry   = build_trend_carry(n, from, to, y0, q0),
    counter_carry = build_counter_carry(n, from_idx, to_idx),
    stop("Unknown dummy kind: ", kind, call. = FALSE)
  )
  bimets::TIMESERIES(vals, START = c(y0, q0), FREQ = 4)
}

# ---- per-kind builders ----------------------------------------------------

build_pulse <- function(n, q_idx) {
  out <- rep(0, n)
  if (!is.na(q_idx) && q_idx >= 1L && q_idx <= n) out[q_idx] <- 1
  out
}

build_tristate <- function(n, q_plus, q_minus) {
  out <- rep(0, n)
  if (!is.na(q_plus)  && q_plus  >= 1L && q_plus  <= n) out[q_plus]  <-  1
  if (!is.na(q_minus) && q_minus >= 1L && q_minus <= n) out[q_minus] <- -1
  out
}

build_range_lt <- function(n, to_idx) {
  # 1 where quarter index < to_idx (strict); 0 elsewhere.
  out <- rep(0, n)
  if (is.na(to_idx)) return(out)
  if (to_idx > 1L) out[1:min(to_idx - 1L, n)] <- 1
  out
}

build_range_gt <- function(n, from_idx) {
  # 1 where quarter index > from_idx (strict); 0 elsewhere.
  out <- rep(0, n)
  if (is.na(from_idx)) return(out)
  if (from_idx < n) out[(from_idx + 1L):n] <- 1
  out
}

build_range_ge <- function(n, from_idx) {
  # 1 where quarter index >= from_idx; 0 elsewhere.
  out <- rep(0, n)
  if (is.na(from_idx)) return(out)
  if (from_idx <= n) out[max(from_idx, 1L):n] <- 1
  out
}

build_range_gt_lt <- function(n, from_idx, to_idx) {
  # 1 where from_idx < quarter index < to_idx (strict both sides).
  out <- rep(0, n)
  if (is.na(from_idx) || is.na(to_idx)) return(out)
  lo <- from_idx + 1L
  hi <- to_idx   - 1L
  if (lo <= hi && lo <= n && hi >= 1L) {
    out[max(lo, 1L):min(hi, n)] <- 1
  }
  out
}

build_trend_carry <- function(n, from, to, y0, q0) {
  # @trend value over [from, to]: NA before, increment 1/quarter within,
  # then carry the value at `to` past it. @trend is pinned to
  # REFERENCE_TREND_ZERO -> 0, so the absolute calendar quarter determines
  # the value (not the database's start).
  ref <- parse_yyyyQq(REFERENCE_TREND_ZERO)
  from_q <- parse_yyyyQq(from)
  to_q   <- parse_yyyyQq(to)

  # Value at the `to` quarter, used for the carry tail.
  to_value <- quarter_index(to_q$year, to_q$quarter, ref$year, ref$quarter)

  from_idx <- quarter_index_str(from, y0, q0)
  to_idx   <- quarter_index_str(to,   y0, q0)

  out <- rep(NA_real_, n)
  # Body: assign @trend value at each quarter in [from_idx, to_idx]. Each
  # such quarter q corresponds to calendar (y0, q0) + (q-1) quarters, and
  # has @trend value = (calendar_q - REFERENCE_TREND_ZERO) in quarters.
  body_lo <- max(from_idx, 1L)
  body_hi <- min(to_idx, n)
  if (!is.na(body_lo) && !is.na(body_hi) && body_lo <= body_hi) {
    span_indices <- body_lo:body_hi
    out[span_indices] <- vapply(span_indices, function(q) {
      cal <- advance_quarter(y0, q0, q - 1L)
      quarter_index(cal$year, cal$quarter, ref$year, ref$quarter)
    }, double(1))
  }
  # Carry tail: indices past to_idx get the value at `to`.
  if (!is.na(to_idx) && to_idx < n) {
    tail_lo <- max(to_idx + 1L, 1L)
    out[tail_lo:n] <- to_value
  }
  out
}

build_counter_carry <- function(n, from_idx, to_idx) {
  # 0 before `from`; (1, 2, ...) over [from, to]; then carry the to-value.
  out <- rep(0, n)
  if (is.na(from_idx) || is.na(to_idx)) return(out)
  body_lo <- max(from_idx, 1L)
  body_hi <- min(to_idx, n)
  # Counter value at quarter q within [from, to] = (q - from + 1) in the
  # absolute index space (negative values are clipped to 0 since we never
  # assign before from).
  if (body_lo <= body_hi) {
    out[body_lo:body_hi] <- (body_lo:body_hi) - from_idx + 1L
  }
  # Carry tail.
  if (!is.na(to_idx) && to_idx < n) {
    to_value <- to_idx - from_idx + 1L
    tail_lo <- max(to_idx + 1L, 1L)
    out[tail_lo:n] <- to_value
  }
  out
}

# ---- quarter arithmetic ---------------------------------------------------

# Return the integer number of quarters from (y0, q0) to (y, q). Negative
# if (y, q) precedes the base. Quarters are 1..4.
quarter_index <- function(y, q, y0, q0) {
  as.integer((y - y0) * 4L + (q - q0))
}

# Same, but takes a "YYYYQQ" string for the target.
quarter_index_str <- function(yq_str, y0, q0) {
  yq <- parse_yyyyQq(yq_str)
  quarter_index(yq$year, yq$quarter, y0, q0) + 1L  # 1-indexed
}

# Advance (y, q) by k quarters and return new (y, q).
advance_quarter <- function(y, q, k) {
  abs_idx <- (y * 4L + (q - 1L)) + k
  list(
    year    = abs_idx %/% 4L,
    quarter = (abs_idx %% 4L) + 1L
  )
}
