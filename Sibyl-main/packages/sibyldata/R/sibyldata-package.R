#' sibyldata: data pipeline for SIBYL
#'
#' Wraps `readabs`, `readrba`, `fredr`, and the `OECD` package into a single
#' [update_data()] call returning tidy panels with vintage tracking. The
#' rename layer that maps source series IDs to MARTIN variable names lives
#' here too, in [to_martin_database()].
#'
#' Storage is parquet via `arrow`, cached locally under [cache_path()].
#'
#' @keywords internal
"_PACKAGE"
