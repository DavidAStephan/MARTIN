# Surface raw monthly catalogue series alongside the quarterly database
# so nowcast's bridge-equation methods can use them as leading indicators
# without re-fetching from source.
#
# The main pipeline (to_martin_database) aggregates monthly series to
# quarterly via pivot_quarterly + aggregate_to_quarter. For a true
# monthly-indicator bridge, nowcast needs the UN-aggregated monthly
# data so it can build a partial-quarter indicator value (e.g. average
# of Oct+Nov for predicting Q4 GDP when December isn't released yet).

#' Return monthly bimets ts for catalogue series with frequency "M"
#'
#' Filters the raw panel down to catalogue rows tagged
#' `source_frequency = "M"`, joins to the catalogue to pick up the
#' `martin_var` name, then pivots each series to a monthly `bimets`
#' time series. Returns a named list keyed by `martin_var`.
#'
#' This is the parallel of `to_martin_database()` for monthly data.
#' It does **not** apply Chow-Lin / splices / derived formulas —
#' those are quarterly-database concerns. Each returned series is the
#' raw monthly observation panel.
#'
#' @param raw A tidy panel from [update_data()] with columns
#'   `(series_id, source, date, value, vintage)`.
#' @param vars Optional character vector of `martin_var` codes to
#'   restrict the result to (e.g. `c("LE", "HOURS", "RT")`). When
#'   `NULL` (the default) returns all monthly catalogue series the
#'   panel covers.
#' @param catalogue Catalogue tibble; defaults to [series_catalogue()].
#'
#' @return Named list of `bimets::TIMESERIES` keyed by `martin_var`.
#'   Empty list if no monthly rows are in scope.
#' @export
nowcast_monthly_indicators <- function(raw,
                                       vars      = NULL,
                                       catalogue = series_catalogue()) {
  monthly_rows <- catalogue[catalogue$source_frequency == "M", , drop = FALSE]
  if (!is.null(vars)) {
    monthly_rows <- monthly_rows[monthly_rows$martin_var %in% vars,
                                 , drop = FALSE]
  }
  if (nrow(monthly_rows) == 0L) return(list())

  joined <- dplyr::left_join(
    raw,
    monthly_rows[, c("source_id", "source", "martin_var")],
    by = c("series_id" = "source_id", "source")
  )
  joined <- joined[!is.na(joined$martin_var), , drop = FALSE]
  if (nrow(joined) == 0L) return(list())

  # Group by (martin_var, month-start date), take last observation in
  # case of duplicates; monthly bimets ts of (n_months) values.
  joined$month_date <- as.Date(format(joined$date, "%Y-%m-01"))
  agg <- joined |>
    dplyr::group_by(martin_var, month_date) |>
    dplyr::summarise(value = dplyr::last(value), .groups = "drop") |>
    dplyr::arrange(martin_var, month_date)

  out <- list()
  for (mv in unique(agg$martin_var)) {
    sub <- agg[agg$martin_var == mv, , drop = FALSE]
    if (nrow(sub) == 0L) next
    md <- sub$month_date[1]
    start_year  <- as.integer(format(md, "%Y"))
    start_month <- as.integer(format(md, "%m"))
    out[[mv]] <- bimets::TIMESERIES(
      sub$value, START = c(start_year, start_month), FREQ = 12
    )
  }
  out
}
