# Extend exogenous variables forward into a forecast horizon.
#
# Companion to martin::extend_residual_with_decay() — that handler covers
# the replay add-factors, but bimets::SIMULATE() also needs every variable
# in TSRANGE to have a defined value. For genuinely future horizons that
# means we need to populate exogenous variables (dummies, anchors, the
# tail of any variable we treat as given) past their data end.
#
# Three modes per variable:
#
#   "carry"    — hold the last observed value forward (good for dummies
#                 at zero, anchored series like PI_TARGET).
#   "constant" — fill with a specified scalar.
#   "linear"   — extrapolate the linear trend of the last `n` periods
#                 (good for time-trend variables like PIBN_TREND_1).

#' Extend variables in a database forward to a target quarter
#'
#' For each named entry in `rules`, extends the matching series in
#' `database` so it covers up to `end_quarter`. Quarters that already have
#' data are not overwritten. Series not in `rules` are left untouched —
#' the caller chooses which variables get extended.
#'
#' @param database Named list of bimets/base TIMESERIES.
#' @param end_quarter Character `"yyyyQq"` — the inclusive end of the
#'   extension range.
#' @param rules Named list keyed by martin_var. Each entry is a list with
#'   at least `mode` ∈ \{`"carry"`, `"constant"`, `"linear"`\}; mode
#'   `"constant"` also takes `value`; mode `"linear"` takes optional
#'   `lookback` (default 4 quarters). If `rules = "carry_all"`, every
#'   series in `database` is carried forward.
#' @return The database with extended series.
#' @export
extend_exogenous <- function(database, end_quarter,
                              rules = "carry_all") {
  stopifnot(is.character(end_quarter), length(end_quarter) == 1L)
  yq <- parse_yyyyQq(end_quarter)
  target_dec <- yq$year + (yq$quarter - 1) / 4

  if (identical(rules, "carry_all")) {
    rules <- stats::setNames(
      lapply(names(database), function(.) list(mode = "carry")),
      names(database)
    )
  }
  if (!is.list(rules) || is.null(names(rules))) {
    stop("`rules` must be 'carry_all' or a named list keyed by martin_var.",
         call. = FALSE)
  }

  for (mv in names(rules)) {
    ts <- database[[mv]]
    if (is.null(ts)) next
    rule <- rules[[mv]]
    mode <- rule$mode %||% "carry"
    database[[mv]] <- extend_one(ts, target_dec, rule, mode)
  }
  database
}

# Extend one ts to `target_dec` per `rule`. Returns ts unchanged if
# target_dec is already reached.
extend_one <- function(ts, target_dec, rule, mode) {
  tsp <- stats::tsp(ts)
  cur_end_dec <- tsp[2]
  if (target_dec <= cur_end_dec + 1e-9) return(ts)

  n_new <- round((target_dec - cur_end_dec) * 4)
  vals <- as.numeric(ts)
  # Use the last non-NA value as the carry / linear seed
  last_idx <- suppressWarnings(max(which(!is.na(vals))))
  seed <- if (is.finite(last_idx)) vals[last_idx] else 0

  ext <- switch(mode,
    carry    = rep(seed, n_new),
    constant = rep(rule$value %||% seed, n_new),
    linear   = linear_extrapolate(vals, n_new, rule$lookback %||% 4L),
    stop("Unknown extension mode: ", mode, call. = FALSE)
  )

  start_year    <- floor(tsp[1] + 1e-9)
  start_quarter <- round((tsp[1] - start_year) * 4 + 1)
  bimets::TIMESERIES(c(vals, ext),
                     START = c(start_year, start_quarter), FREQ = 4)
}

linear_extrapolate <- function(vals, n_new, lookback) {
  last_idx <- suppressWarnings(max(which(!is.na(vals))))
  if (!is.finite(last_idx) || last_idx < 2L) {
    return(rep(if (is.finite(last_idx)) vals[last_idx] else 0, n_new))
  }
  hist_start <- max(1L, last_idx - lookback + 1L)
  hist_vals  <- vals[hist_start:last_idx]
  # Average per-period change
  slope <- mean(diff(hist_vals), na.rm = TRUE)
  if (!is.finite(slope)) slope <- 0
  vals[last_idx] + slope * seq_len(n_new)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
