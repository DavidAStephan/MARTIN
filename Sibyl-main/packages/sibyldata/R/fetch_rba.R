#' Fetch RBA series and return a tidy panel
#'
#' Wraps `readrba::read_rba(series_id = ...)` over a vector of catalogue
#' source IDs. The catalogue uses Quandl-style prefixed IDs (e.g.
#' `"F02_1_FCMYGBAG2"`, `"D02_DLCACS"`, `"G01_GCPIOCPMTMQP"`) so that the
#' RBA table prefix is preserved as institutional metadata; the readrba
#' package takes only the bare series ID after the last underscore. This
#' function strips the prefix at fetch time and keeps the original catalogue
#' ID in the returned panel's `series_id` column so the
#' [to_martin_database()] join still resolves.
#'
#' Series without an underscore are passed through unchanged (these are the
#' bare IDs the catalogue uses for newer RBA series like `FXRUSD`,
#' `FXRTWI`, `FLRBFOLBT`).
#'
#' @param series_ids Character vector of catalogue source IDs.
#' @param vintage A `Date`. Stamped into every row's `vintage` column.
#'
#' @return A tibble of `(series_id, source, date, value, vintage)`.
#' @export
fetch_rba <- function(series_ids, vintage = Sys.Date()) {
  if (length(series_ids) == 0L) return(empty_panel())
  vintage <- as.Date(vintage)

  rows <- purrr::map(series_ids, function(catalogue_id) {
    bare_id <- bare_rba_id(catalogue_id)
    # readrba calls lubridate::parse_date_time on RBA's xlsx tables, which
    # emits "All formats failed to parse" warnings on the metadata rows.
    # Cosmetic — muffle to keep test output readable.
    out <- withCallingHandlers(
      readrba::read_rba(series_id = bare_id),
      warning = function(w) {
        if (grepl("All formats failed to parse", conditionMessage(w),
                  fixed = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }
    )
    tibble::tibble(
      series_id = catalogue_id,
      source    = "rba",
      date      = as.Date(out$date),
      value     = as.numeric(out$value),
      vintage   = vintage
    )
  })
  dplyr::bind_rows(rows)
}

# Strip a Quandl-style table prefix from an RBA series ID, e.g.
# "F02_1_FCMYGBAG2" -> "FCMYGBAG2". Returns input unchanged if no
# underscore present.
bare_rba_id <- function(x) {
  pos <- regexpr("_[^_]*$", x)
  ifelse(pos > 0L, substr(x, pos + 1L, nchar(x)), x)
}
