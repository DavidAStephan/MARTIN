#' Fetch the Southern Oscillation Index from BoM
#'
#' Pulls the plaintext SOI table from BoM's ftp (HTML-wrapped). Parses the
#' fixed-format `YEAR JAN FEB ... DEC` rows into a tidy panel.
#'
#' One series only, `SOI`. The catalogue's `source_id` is `SOI` too.
#'
#' Network-dependent: skips test calls fall through to the caller if BoM
#' is unreachable.
#'
#' @param series_ids Character vector. The only valid value is `"SOI"`;
#'   passed for API uniformity with the other fetchers.
#' @param vintage A `Date`.
#' @param url Source URL. Defaults to BoM's published plaintext table.
#' @return A tibble of `(series_id, source, date, value, vintage)`.
#' @export
fetch_bom <- function(series_ids,
                       vintage = Sys.Date(),
                       url     = "ftp://ftp.bom.gov.au/anon/home/ncc/www/sco/soi/soiplaintext.html") {
  if (length(series_ids) == 0L) return(empty_panel())
  bad <- setdiff(series_ids, "SOI")
  if (length(bad)) {
    stop("fetch_bom() only knows the SOI series; got: ",
         paste(bad, collapse = ", "), call. = FALSE)
  }
  vintage <- as.Date(vintage)

  txt <- paste(readLines(url, warn = FALSE), collapse = "\n")
  parsed <- parse_soi_plaintext(txt)

  tibble::tibble(
    series_id = "SOI",
    source    = "bom",
    date      = parsed$date,
    value     = parsed$value,
    vintage   = vintage
  )
}

# Parse the BoM SOI HTML+plaintext payload into a tidy (date, value) tibble.
# Looks for the <pre> block, splits into rows, treats the first
# whitespace-separated token as the year and the next 12 as monthly values
# (any of which may be `NA` or missing if the year is incomplete).
parse_soi_plaintext <- function(txt) {
  m <- regmatches(txt, regexpr("(?s)<pre>(.*?)</pre>", txt, perl = TRUE))
  if (length(m) == 0L) {
    stop("Could not find <pre>...</pre> block in BoM SOI payload.",
         call. = FALSE)
  }
  body <- sub("<pre>", "", sub("</pre>", "", m, fixed = TRUE), fixed = TRUE)
  lines <- strsplit(body, "\n", fixed = TRUE)[[1]]
  # Keep only lines that start (after whitespace) with a 4-digit year
  data_lines <- lines[grepl("^\\s*\\d{4}\\b", lines)]
  if (length(data_lines) == 0L) {
    stop("Could not find any data rows in BoM SOI payload.", call. = FALSE)
  }

  rows <- lapply(data_lines, function(line) {
    fields <- strsplit(trimws(line), "\\s+")[[1]]
    if (length(fields) < 2L) return(NULL)
    year <- as.integer(fields[1])
    vals <- suppressWarnings(as.numeric(fields[-1]))
    # Pad with NA if year is incomplete (fewer than 12 months)
    if (length(vals) < 12L) {
      vals <- c(vals, rep(NA_real_, 12L - length(vals)))
    }
    vals <- vals[1:12]
    tibble::tibble(
      date  = as.Date(sprintf("%04d-%02d-01", year, 1:12)),
      value = vals
    )
  })
  out <- dplyr::bind_rows(rows)
  out[!is.na(out$value), , drop = FALSE]
}
