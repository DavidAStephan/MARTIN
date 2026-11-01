#' Convert an adjustment list to a bimets ConstantAdjustment list
#'
#' Thin wrapper around [judgement::expand_adjustments()] that packages each
#' numeric vector into a `bimets::TIMESERIES`. The bimets coupling lives here
#' so judgement stays bimets-free.
#'
#' Multiple adjustments on the same equation are summed in
#' [judgement::expand_adjustments()]; this function just lifts the result into
#' the shape `bimets::SIMULATE(..., ConstantAdjustment = ...)` expects.
#'
#' @param x A `judgement::adjustment_list` (possibly empty).
#' @param solve_range A length-2 character vector `c("yyyyQq", "yyyyQq")`
#'   identifying the inclusive simulation range.
#'
#' @return A named list of `bimets::TIMESERIES` objects, one per adjusted
#'   equation. Empty list if `x` is empty.
#' @export
to_constant_adjustment_list <- function(x, solve_range) {
  expanded <- judgement::expand_adjustments(x, solve_range)
  if (length(expanded) == 0L) return(list())

  start <- judgement_parse_quarter(solve_range[1])

  out <- lapply(expanded, function(values) {
    bimets::TIMESERIES(
      values,
      START = c(start$year, start$quarter),
      FREQ  = 4
    )
  })
  names(out) <- names(expanded)
  out
}

