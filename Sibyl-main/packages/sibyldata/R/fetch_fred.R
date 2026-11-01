#' Fetch one source's series for a given vintage
#'
#' Internal dispatcher. Looks up the catalogue subset for `source`, calls the
#' source-specific fetcher, normalises to a tidy panel of
#' `(series_id, source, date, value, vintage)`. Writes to cache.
#'
#' @param source A source name.
#' @param vintage A `Date`.
#' @param refresh Logical. If `FALSE` and a cached file exists, returns it
#'   without re-fetching.
#'
#' @return A tibble. Empty if the catalogue has no series for `source`.
#' @keywords internal
fetch_source <- function(source, vintage, refresh = FALSE) {
  cat <- series_catalogue()
  source_rows <- cat[cat$source == source, , drop = FALSE]
  if (nrow(source_rows) == 0L) {
    return(empty_panel())
  }

  if (!isTRUE(refresh)) {
    cached <- cache_read(source, vintage)
    if (!is.null(cached)) return(cached)
  }

  panel <- switch(source,
    fred      = fetch_fred(source_rows$source_id,      vintage = vintage),
    abs       = fetch_abs(source_rows,                 vintage = vintage),
    rba       = fetch_rba(source_rows$source_id,       vintage = vintage),
    oecd      = fetch_oecd(source_rows$source_id,      vintage = vintage),
    worldbank = fetch_worldbank(source_rows,           vintage = vintage),
    bom       = fetch_bom(source_rows$source_id,       vintage = vintage),
    stop("Unknown source: ", source, call. = FALSE)
  )

  cache_write(panel, source, vintage)
  panel
}

#' Fetch FRED series and return a tidy panel
#'
#' Wraps [fredr::fredr()] over a vector of series IDs. Returns the canonical
#' SIBYL panel shape: `(series_id, source, date, value, vintage)`.
#'
#' Requires `FRED_API_KEY` in the environment (set in `.Renviron`).
#'
#' @param series_ids Character vector of FRED series IDs.
#' @param vintage A `Date`. Stamped into every row's `vintage` column.
#' @param observation_start Date string passed through to `fredr()`. Defaults
#'   to `"1959-01-01"` (MARTIN's quarterly data starts mid-1959).
#'
#' @return A tibble of `(series_id, source, date, value, vintage)`.
#' @export
fetch_fred <- function(series_ids,
                       vintage = Sys.Date(),
                       observation_start = "1959-01-01") {
  if (Sys.getenv("FRED_API_KEY") == "") {
    stop("FRED_API_KEY is not set. Add it to .Renviron and restart R.",
         call. = FALSE)
  }
  if (length(series_ids) == 0L) return(empty_panel())

  vintage <- as.Date(vintage)
  observation_start <- as.Date(observation_start)

  fredr::fredr_set_key(Sys.getenv("FRED_API_KEY"))

  rows <- purrr::map(series_ids, function(sid) {
    out <- fredr::fredr(series_id = sid, observation_start = observation_start)
    tibble::tibble(
      series_id = sid,
      source    = "fred",
      date      = as.Date(out$date),
      value     = as.numeric(out$value),
      vintage   = vintage
    )
  })
  dplyr::bind_rows(rows)
}

# Helper: empty panel with the canonical schema
empty_panel <- function() {
  tibble::tibble(
    series_id = character(),
    source    = character(),
    date      = as.Date(character()),
    value     = numeric(),
    vintage   = as.Date(character())
  )
}
