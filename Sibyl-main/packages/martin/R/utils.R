# Internal utilities. Not exported.

# Single source of truth for quarter parsing. Reaches into judgement's
# internal helper rather than re-parsing — keeps the parsing rule in one
# place so changes to the "yyyyQq" format only need to be made once.
judgement_parse_quarter <- function(q) {
  judgement:::parse_quarter(q)
}

# Run an expression while muffling the bimets "outdated BIMETS version"
# warning, which fires on every LOAD_MODEL_DATA / ESTIMATE / SIMULATE call
# against MARTINMOD_AF.txt because the vendored .txt was authored with an
# older bimets release and carries no version stamp. All other warnings
# (including bimets' own legitimate ones) pass through.
.suppress_bimets_version_warning <- function(expr) {
  withCallingHandlers(
    expr,
    warning = function(w) {
      if (grepl("outdated BIMETS version", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
}

# Extend a bimets residual time series forward via the EViews
# `_a = _a(-1) * -0.5` decay convention from
# `references/MARTIN-master/Programs/solve_model.prg`.
#
# Each new period is `previous * decay`, so a positive AF flips sign and
# halves, then flips again and halves, etc. Returns the residual unchanged
# if it already extends to or past (end_year, end_quarter).
#
# Inputs:
#   ts          a bimets/base ts object (the per-equation residual series)
#   end_year    integer
#   end_quarter integer 1..4
#   decay       numeric multiplier applied per quarter; default -0.5
#
# Returns: bimets time series extended to (end_year, end_quarter).
extend_residual_with_decay <- function(ts, end_year, end_quarter,
                                       decay = -0.5) {
  if (is.null(ts)) return(NULL)
  tsp_now <- stats::tsp(ts)
  current_end_dec <- tsp_now[2]
  target_end_dec  <- as.numeric(end_year) + (as.numeric(end_quarter) - 1) / 4

  if (target_end_dec <= current_end_dec + 1e-9) return(ts)

  # Number of new quarters to append
  n_new <- round((target_end_dec - current_end_dec) * 4)

  # Find the last non-NA value to seed the recursion. If the series tail is
  # NA (which can happen if the equation's TSRANGE ended before the data),
  # walk back until we find one; if all NA, treat the seed as 0.
  vals <- as.numeric(ts)
  last_idx <- suppressWarnings(max(which(!is.na(vals))))
  if (!is.finite(last_idx)) {
    seed <- 0
  } else {
    seed <- vals[last_idx]
  }

  # Generate the geometric-decay sequence
  steps     <- seq_len(n_new)
  extension <- seed * decay^steps

  # Build the new full vector and ts
  full_vals <- c(vals, extension)
  start_year    <- floor(tsp_now[1] + 1e-9)
  start_quarter <- round((tsp_now[1] - start_year) * 4 + 1)
  bimets::TIMESERIES(
    full_vals,
    START = c(start_year, start_quarter),
    FREQ  = 4
  )
}
