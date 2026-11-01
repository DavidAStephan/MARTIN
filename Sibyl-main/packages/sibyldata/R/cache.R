# Local parquet cache for raw fetched panels.
#
# Layout: <cache_path>/<source>/<vintage>.parquet
#
# vintage is an ISO-8601 date string ("2026-05-23"), so the cache is a flat
# read-when-you-need-it store keyed by (source, vintage). Concurrent runs on
# different vintages don't collide.
#
# All cache writes go through cache_write(); all reads through cache_read().
# Treat the cache as content-addressed by vintage — re-fetching the same
# vintage must produce the same bytes.

#' Path on disk where a cached panel would live (whether it exists or not)
#'
#' @param source One of `abs`, `rba`, `fred`, `oecd`, `worldbank`, `bom`.
#' @param vintage A `Date`.
#' @return Character path.
#' @keywords internal
cache_file_path <- function(source, vintage) {
  vintage <- as.Date(vintage)
  source <- match.arg(
    source,
    c("abs", "rba", "fred", "oecd", "worldbank", "bom")
  )
  dir <- file.path(cache_path(), source)
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  file.path(dir, paste0(format(vintage, "%Y-%m-%d"), ".parquet"))
}

#' Read a cached panel
#'
#' Returns `NULL` if the file isn't present — callers can use that as the
#' signal to fetch fresh data.
#'
#' @param source A source name (see [cache_file_path()]).
#' @param vintage A `Date`.
#' @return A tibble, or `NULL` if no cached file exists.
#' @export
cache_read <- function(source, vintage) {
  path <- cache_file_path(source, vintage)
  if (!file.exists(path)) return(NULL)
  arrow::read_parquet(path)
}

#' Write a panel to the cache
#'
#' @param panel A tibble. Must have columns
#'   `(series_id, source, date, value, vintage)`.
#' @param source A source name (see [cache_file_path()]).
#' @param vintage A `Date`.
#' @return The input `panel` invisibly.
#' @export
cache_write <- function(panel, source, vintage) {
  stopifnot(
    is.data.frame(panel),
    all(c("series_id", "source", "date", "value", "vintage") %in% names(panel))
  )
  path <- cache_file_path(source, vintage)
  arrow::write_parquet(panel, path)
  invisible(panel)
}
