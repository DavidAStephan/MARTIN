# Quarter-string helpers. Internal — not exported.
#
# Adjustments use plain "yyyyQq" strings to identify quarters (e.g. "2026Q1").
# This is the simplest format that survives JSON round-trips through the LLM,
# is readable in a CSV review table, and doesn't pull tsibble into the
# judgement namespace.
#
# These helpers convert to/from that format and produce inclusive sequences.

# Parse a "yyyyQq" string vector to a data.frame of (year, quarter).
parse_quarter <- function(x) {
  if (!is.character(x)) {
    stop("Quarter must be a character vector of `yyyyQq` strings.", call. = FALSE)
  }
  bad <- !grepl("^\\d{4}Q[1-4]$", x)
  if (any(bad)) {
    stop("Quarter strings must match `yyyyQq` (e.g. `2026Q1`). Got: ",
         paste(unique(x[bad]), collapse = ", "), call. = FALSE)
  }
  list(
    year    = as.integer(substr(x, 1, 4)),
    quarter = as.integer(substr(x, 6, 6))
  )
}

# Format integer (year, quarter) back to "yyyyQq".
format_quarter <- function(year, quarter) {
  sprintf("%04dQ%d", as.integer(year), as.integer(quarter))
}

# Number-line position of a quarter: 1959Q1 -> 1959*4, 1959Q4 -> 1959*4 + 3, etc.
quarter_index <- function(year, quarter) {
  as.integer(year) * 4L + as.integer(quarter) - 1L
}

# Inclusive sequence of "yyyyQq" strings between `from` and `to`.
quarter_seq <- function(from, to) {
  f <- parse_quarter(from)
  t <- parse_quarter(to)
  i_from <- quarter_index(f$year, f$quarter)
  i_to   <- quarter_index(t$year, t$quarter)
  if (i_to < i_from) {
    stop("`to` (", to, ") precedes `from` (", from, ").", call. = FALSE)
  }
  idx <- seq.int(i_from, i_to)
  format_quarter(idx %/% 4L, idx %% 4L + 1L)
}
