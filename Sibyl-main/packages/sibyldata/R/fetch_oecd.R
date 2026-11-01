#' Fetch OECD series and return a tidy panel
#'
#' Hits the OECD SDMX REST API (`https://sdmx.oecd.org/public/rest/data/...`)
#' and parses the returned CSV. Each catalogue row's `source_id` is
#' expected to be a fully-qualified SDMX key of the form
#' `"<dataflow>/<key>"`, e.g. `"OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA,1.0/AUS.S1..B1GQ.LR..L.Q?"`.
#' The function passes the segment after the slash as the SDMX key and
#' the segment before as the dataflow identifier.
#'
#' The OECD API does not require an API key for public data; default
#' rate limits are around 20 requests per minute per IP. Cached per
#' vintage via the usual sibyldata parquet store so repeated runs are
#' fast.
#'
#' **Status (v0):** this is a working *single-series* fetcher. The
#' trading-partner-weighted world-aggregate computation that MARTIN's
#' WY / WP / WPX expect is **not** implemented yet -- the catalogue
#' continues to use FRED US proxies for those. A proper TPW build would
#' need:
#'   1. Fetch OECD quarterly GDP / CPI / export-price series for each
#'      of Australia's top trading partners (CN, JP, US, KR, SG, IN,
#'      NZ, GB, ...).
#'   2. Source partner export-share weights (ABS table 5368.0).
#'   3. Combine: WY = sum_i weight_i * partner_i_GDP_index.
#' That's a separate workstream; this function is the first piece.
#'
#' @param series_ids Character vector of OECD SDMX keys (see above).
#' @param vintage A `Date`. Stamped into every row's `vintage` column.
#' @param observation_start Date string passed through as the
#'   `startPeriod` parameter. Default `"1959-01-01"` matches MARTIN's
#'   horizon start.
#' @param base_url SDMX endpoint root. Override for testing.
#' @param timeout_s Per-series timeout (seconds). Default 60.
#'
#' @return A tibble of `(series_id, source, date, value, vintage)`.
#'   Empty when `series_ids` has length 0.
#' @export
fetch_oecd <- function(series_ids,
                       vintage           = Sys.Date(),
                       observation_start = "1959-01-01",
                       base_url          = "https://sdmx.oecd.org/public/rest/data",
                       timeout_s         = 60) {
  if (length(series_ids) == 0L) return(empty_panel())
  stopifnot(is.character(series_ids))

  rows <- lapply(series_ids, function(sid) {
    parts <- strsplit(sid, "/", fixed = TRUE)[[1]]
    if (length(parts) < 2L) {
      warning(sprintf("[fetch_oecd] series_id '%s' must be of the form ",
                      "'<dataflow>/<key>'; skipping", sid), call. = FALSE)
      return(NULL)
    }
    dataflow <- parts[1]
    key      <- paste(parts[-1], collapse = "/")
    # Strip any trailing '?' the caller might have copied in from
    # OECD's docs (the URL-builder adds its own query string).
    key <- sub("\\?$", "", key)
    # Do NOT URL-encode the dataflow or key: OECD SDMX expects literal
    # commas, '@', '+', '.' in the path. Only the query-string values
    # (startPeriod, format) need encoding, which is just ASCII alnum.
    url <- sprintf(
      "%s/%s/%s?startPeriod=%s&format=csvfilewithlabels",
      base_url, dataflow, key, substr(observation_start, 1L, 7L)
    )

    txt <- tryCatch(
      {
        con <- url(url, open = "r")
        on.exit(try(close(con), silent = TRUE), add = TRUE)
        old_to <- options(timeout = timeout_s)
        on.exit(options(old_to), add = TRUE)
        readLines(con, warn = FALSE)
      },
      error = function(e) {
        warning(sprintf("[fetch_oecd] failed to fetch %s: %s",
                        sid, conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
    if (is.null(txt) || length(txt) < 2L) return(NULL)

    df <- tryCatch(
      utils::read.csv(textConnection(txt), stringsAsFactors = FALSE),
      error = function(e) {
        warning(sprintf("[fetch_oecd] CSV parse failed for %s: %s",
                        sid, conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
    if (is.null(df) || nrow(df) == 0L) return(NULL)

    # OECD SDMX CSV columns include TIME_PERIOD (e.g. "2024-Q1" or
    # "2024-01") and OBS_VALUE. Be lenient about column casing.
    cols <- tolower(names(df))
    tp_col <- which(cols %in% c("time_period", "time", "period"))[1]
    ov_col <- which(cols %in% c("obs_value", "value"))[1]
    if (is.na(tp_col) || is.na(ov_col)) {
      warning(sprintf("[fetch_oecd] no TIME_PERIOD / OBS_VALUE in %s",
                      sid), call. = FALSE)
      return(NULL)
    }

    date <- oecd_parse_period(df[[tp_col]])
    value <- suppressWarnings(as.numeric(df[[ov_col]]))
    keep <- !is.na(date) & !is.na(value)
    if (!any(keep)) return(NULL)

    tibble::tibble(
      series_id = sid,
      source    = "oecd",
      date      = date[keep],
      value     = value[keep],
      vintage   = vintage
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0L) return(empty_panel())
  dplyr::bind_rows(rows)
}

# Parse OECD's TIME_PERIOD strings ("2024-Q1", "2024-01", "2024") to Dates
# (start of quarter / month / year).
oecd_parse_period <- function(x) {
  x <- as.character(x)
  out <- rep(as.Date(NA), length(x))

  q_m <- regmatches(x, regexpr("^([0-9]{4})-Q([1-4])$", x, perl = TRUE))
  is_q <- nchar(q_m) > 0L
  if (any(is_q)) {
    y <- as.integer(substr(x[is_q], 1L, 4L))
    q <- as.integer(substr(x[is_q], 7L, 7L))
    out[is_q] <- as.Date(sprintf("%04d-%02d-01", y, (q - 1L) * 3L + 1L))
  }
  is_m <- grepl("^[0-9]{4}-[0-9]{2}$", x)
  if (any(is_m)) {
    out[is_m] <- as.Date(paste0(x[is_m], "-01"))
  }
  is_y <- grepl("^[0-9]{4}$", x)
  if (any(is_y)) {
    out[is_y] <- as.Date(paste0(x[is_y], "-01-01"))
  }
  out
}
