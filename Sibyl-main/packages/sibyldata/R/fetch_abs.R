#' Fetch ABS series and return a tidy panel
#'
#' Pulls every ABS catalogue (cat_no) listed in `source_rows`, then filters
#' to the requested series IDs. `readabs::read_abs()` accepts a `cat_no`
#' plus a tables argument; for v0 we pull every table of each catalogue
#' since per-table targeting isn't captured in the catalogue yet
#' (institutional knowledge for which-table-by-series lives in the legacy
#' [import_data.prg](../../../references/MARTIN-master/Programs/import_data.prg)
#' and could be lifted as a v0.1 column if download time becomes an issue).
#'
#' All downloads are cached at the source-and-vintage level via the
#' caller (`fetch_source()`), so a re-run within the same vintage is a
#' no-op.
#'
#' @param source_rows A tibble subset of [series_catalogue()] for `abs`.
#' @param vintage A `Date`.
#' @return A tibble of `(series_id, source, date, value, vintage)`.
#' @export
fetch_abs <- function(source_rows, vintage = Sys.Date()) {
  if (!is.data.frame(source_rows) || nrow(source_rows) == 0L) {
    return(empty_panel())
  }
  vintage <- as.Date(vintage)

  # Group requested series by ABS catalogue number. NA cat_nos are a bug in
  # the catalogue — fail loudly.
  if (any(is.na(source_rows$source_table))) {
    bad <- source_rows$martin_var[is.na(source_rows$source_table)]
    stop("ABS catalogue rows missing source_table for: ",
         paste(bad, collapse = ", "), call. = FALSE)
  }
  by_cat <- split(source_rows, source_rows$source_table)

  rows <- purrr::imap(by_cat, function(rows_for_cat, cat_no) {
    # read_abs's xlsx parser emits "All formats failed to parse" warnings
    # on metadata rows (same as readrba). Cosmetic — muffle.
    raw <- withCallingHandlers(
      readabs::read_abs(cat_no = cat_no, tables = "all"),
      warning = function(w) {
        if (grepl("All formats failed to parse", conditionMessage(w),
                  fixed = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }
    )

    wanted <- rows_for_cat$source_id
    keep   <- raw[raw$series_id %in% wanted, , drop = FALSE]
    if (nrow(keep) == 0L) {
      warning("ABS catalogue ", cat_no, " returned no rows matching ",
              length(wanted), " requested series IDs.", call. = FALSE)
      return(empty_panel())
    }

    tibble::tibble(
      series_id = keep$series_id,
      source    = "abs",
      date      = as.Date(keep$date),
      value     = as.numeric(keep$value),
      vintage   = vintage
    )
  })

  dplyr::bind_rows(rows)
}
