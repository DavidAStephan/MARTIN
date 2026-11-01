# Conversion between bimets time series (the shape sibyldata produces and
# martin consumes) and tsibble (the shape fable consumes). Both directions
# preserve the quarterly index exactly.

#' Convert a bimets TIMESERIES to a tsibble
#'
#' Trailing NAs (the benign ragged edge — a series that simply hasn't
#' printed its latest quarters yet) are dropped silently. Interior NAs (a
#' hole in the middle of the history) are a different animal: `fable` will
#' happily fit through an implicit gap and then return an all-`NA` central
#' forecast, which poisons the downstream MARTIN solve without warning. We
#' therefore detect interior NAs / implicit time gaps explicitly and stop
#' with a clear message rather than letting them flow through.
#'
#' @param ts A bimets time series (which inherits from base ts).
#' @param variable Character. The name to store in the `variable` column.
#' @return A tsibble keyed by `variable` and indexed by `quarter`
#'   (yearquarter).
#' @keywords internal
bimets_to_tsibble <- function(ts, variable) {
  t <- as.numeric(stats::time(ts))
  year    <- floor(t + 1e-9)
  quarter <- round((t - year) * 4 + 1)
  vals    <- as.numeric(ts)

  # Identify the observed span: first to last non-NA cell. Anything NA
  # *inside* that span is an interior hole; anything NA before the first
  # or after the last is leading / trailing and benign.
  obs_idx <- which(!is.na(vals))
  if (length(obs_idx) == 0L) {
    stop("Variable `", variable, "` is entirely NA; cannot nowcast.",
         call. = FALSE)
  }
  first_obs <- min(obs_idx)
  last_obs  <- max(obs_idx)
  interior  <- seq.int(first_obs, last_obs)
  if (anyNA(vals[interior])) {
    n_holes <- sum(is.na(vals[interior]))
    stop("Variable `", variable, "` has ", n_holes, " interior NA(s) ",
         "between its first and last observation. fable would fit through ",
         "the implicit gap and return an NA forecast. Fill or trim the ",
         "series before nowcasting.", call. = FALSE)
  }

  out <- tibble::tibble(
    variable = variable,
    quarter  = tsibble::make_yearquarter(year = year, quarter = quarter),
    value    = vals
  )
  # Keep only the contiguous observed span (drops leading/trailing NAs).
  out <- out[interior, , drop = FALSE]
  tsbl <- tsibble::as_tsibble(out, key = "variable", index = "quarter")

  # Defensive: even on a contiguous numeric span, a malformed bimets tsp
  # could yield duplicate/gapped yearquarters. tsibble::has_gaps catches
  # that an implicit gap remains; treat it the same as an interior hole.
  gaps <- tsibble::has_gaps(tsbl)
  if (isTRUE(any(gaps$.gaps))) {
    stop("Variable `", variable, "` has an implicit time gap after ",
         "conversion to a tsibble; cannot nowcast a gapped index.",
         call. = FALSE)
  }
  tsbl
}

#' Convert a tibble of quarterly values to a bimets TIMESERIES
#'
#' Expects the input to be sorted by quarter ascending; the resulting ts
#' starts at the first quarter and ends at the last.
#'
#' @param df A tibble with at least `quarter` (yearquarter) and `value`
#'   columns.
#' @return A bimets TIMESERIES.
#' @keywords internal
quarterly_tibble_to_bimets <- function(df) {
  df <- df[order(df$quarter), , drop = FALSE]
  first_q <- df$quarter[1]
  year    <- as.integer(format(first_q, "%Y"))
  qnum    <- as.integer(substr(format(first_q), 7, 7))
  bimets::TIMESERIES(
    df$value,
    START = c(year, qnum),
    FREQ  = 4
  )
}

#' Get the last observed quarter of a bimets time series
#'
#' Skips trailing NA cells.
#'
#' @param ts A bimets TIMESERIES.
#' @return A tsibble yearquarter.
#' @keywords internal
last_observed_quarter <- function(ts) {
  vals <- as.numeric(ts)
  last_idx <- max(which(!is.na(vals)))
  t <- as.numeric(stats::time(ts))[last_idx]
  year <- floor(t + 1e-9)
  quarter <- round((t - year) * 4 + 1)
  tsibble::make_yearquarter(year = year, quarter = quarter)
}
