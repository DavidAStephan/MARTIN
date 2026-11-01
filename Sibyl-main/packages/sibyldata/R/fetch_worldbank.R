#' Fetch World Bank commodity price indices from the bundled xlsx
#'
#' Reads the "Monthly Indices" sheet of the World Bank Pink Sheet (CMO)
#' xlsx bundled at
#' `references/MARTIN-master/Data/CMO-Historical-Data-Monthly.xlsx`. Returns
#' just the columns named in the requested `source_rows$source_id` vector
#' (e.g. `iAGRICULTURE` for WPAG, `iENERGY` for WPCOM).
#'
#' Dates in the source xlsx are `YYYYMnn` strings (e.g. `1960M01`); we parse
#' to first-of-month `Date`s so quarterly aggregation in
#' [to_martin_database()] works correctly.
#'
#' The bundled xlsx is a frozen historical snapshot. A future v0.x will
#' fetch the live World Bank file from
#' `pubdocs.worldbank.org/en/.../CMO-Historical-Data-Monthly.xlsx`; for now
#' the static file keeps the fetcher deterministic.
#'
#' @param source_rows A tibble subset of [series_catalogue()] for
#'   `worldbank`.
#' @param vintage A `Date`.
#' @param xlsx_path Path to the xlsx. Defaults to the bundled fixture.
#' @return A tibble of `(series_id, source, date, value, vintage)`.
#' @export
fetch_worldbank <- function(source_rows,
                             vintage   = Sys.Date(),
                             xlsx_path = worldbank_xlsx_path()) {
  if (!is.data.frame(source_rows) || nrow(source_rows) == 0L) {
    return(empty_panel())
  }
  if (!file.exists(xlsx_path)) {
    stop("World Bank CMO xlsx not found at: ", xlsx_path, call. = FALSE)
  }
  vintage <- as.Date(vintage)

  # Row 10 of the xlsx is the short-code header (iENERGY, iAGRICULTURE, ...);
  # skip the 9 metadata rows above it.
  raw <- suppressMessages(readxl::read_excel(
    xlsx_path, sheet = "Monthly Indices", skip = 9
  ))
  date_col <- names(raw)[1]
  names(raw)[1] <- "date_string"

  # Filter to non-empty data rows (some trailing rows may be blank)
  raw <- raw[!is.na(raw$date_string) &
               grepl("^\\d{4}M\\d{2}$", raw$date_string), , drop = FALSE]
  raw$date <- worldbank_monthly_date(raw$date_string)

  wanted <- source_rows$source_id
  missing <- setdiff(wanted, names(raw))
  if (length(missing)) {
    stop("World Bank xlsx is missing columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  rows <- purrr::map(wanted, function(col) {
    tibble::tibble(
      series_id = col,
      source    = "worldbank",
      date      = raw$date,
      value     = as.numeric(raw[[col]]),
      vintage   = vintage
    )
  })
  dplyr::bind_rows(rows)
}

# Default path to the bundled CMO xlsx (kept under references/).
worldbank_xlsx_path <- function() {
  rel <- file.path("references", "MARTIN-master", "Data",
                   "CMO-Historical-Data-Monthly.xlsx")
  if (file.exists(rel)) return(rel)
  if (requireNamespace("here", quietly = TRUE)) {
    candidate <- file.path(here::here(), rel)
    if (file.exists(candidate)) return(candidate)
  }
  rel
}

# Parse "1960M01" -> 1960-01-01
worldbank_monthly_date <- function(s) {
  year  <- as.integer(substr(s, 1, 4))
  month <- as.integer(substr(s, 6, 7))
  as.Date(sprintf("%04d-%02d-01", year, month))
}
