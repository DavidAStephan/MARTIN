# Merge a live MARTIN database with a fallback (typically the bundled
# fixture). The live pipeline's behavioural equations need histories
# going back to the 1960s for some series — longer than live ABS / RBA
# data can reach. The fallback fills those gaps without overriding live
# data where it's at least as long.

#' Merge a primary MARTIN database with a fallback
#'
#' For each MARTIN variable, splice `primary` into `fallback`
#' quarter-by-quarter: take primary's value where primary has data,
#' fall back to fallback's value where primary is NA, and union the
#' time spans so the resulting series covers `min(primary_start,
#' fallback_start)` to `max(primary_end, fallback_end)`.
#'
#' This handles three real cases on Australian data:
#'
#'   (1) Live RBA series that start later than the fixture but extend
#'       past it — e.g. LUR live 1978-2026Q1 vs fixture LUR 1959-2019Q3.
#'       Older rule (primary wins only if it covers fallback's full
#'       range) discarded the 6+ years of recent LUR data; coalesce
#'       keeps fixture for 1959-1977 and live for 1978-2026Q1.
#'   (2) Live series that the agency stopped updating before the
#'       fixture's end — e.g. D02 credit ending 2019Q2 vs fixture's
#'       2019Q3. Coalesce takes live through 2019Q2 and fixture's
#'       2019Q3 value for the last quarter, then nothing past.
#'   (3) Live series whose values just don't reach back as far as
#'       MARTIN's behavioural-equation TSRANGEs need — coalesce fills
#'       the historical gap from fixture so estimation works.
#'
#' For LEVEL series with vintage drift (e.g. PTM, GDP), the splice
#' point can show a small step. This is bounded (typically <1-2 % of
#' the level) and economically harmless; for ratio / rate series
#' (LUR, NCR) the splice is seamless. Variables present only in
#' `primary` are added; variables present only in `fallback` are kept.
#'
#' Provenance is refined here, not guessed: when `primary` carries a
#' `"provenance"` attribute (as produced by [to_martin_database()]), the
#' merged database carries a refined one. A variable keeps its live class only
#' if the live path actually supplied a value; a variable that exists only in
#' `fallback`, or whose live series contributed no non-NA value to the union,
#' is recorded as `"fixture_fallback"`. When `primary` carries no provenance
#' attribute (e.g. a hand-built list in tests), the output is a plain list with
#' no provenance attached -- behaviour is otherwise unchanged.
#'
#' @param primary A named list of bimets TIMESERIES (typically a live
#'   sibyldata-produced database, carrying a `"provenance"` attribute).
#' @param fallback A named list of bimets TIMESERIES (typically
#'   `martin::read_fixture()`).
#' @return A named list of bimets TIMESERIES with the spliced union
#'   per variable. When `primary` carries provenance, the result carries a
#'   refined `"provenance"` attribute (see [database_provenance()]).
#' @export
merge_with_fallback <- function(primary, fallback) {
  out <- fallback
  # Track, per variable, whether the live (primary) path actually supplied a
  # value. live_supplied[[v]] is TRUE when primary has the variable with at
  # least one non-NA observation; such variables keep their live class, all
  # others are recorded as fixture_fallback below.
  live_supplied <- character(0)
  for (v in names(primary)) {
    if (any(!is.na(as.numeric(primary[[v]])))) {
      live_supplied <- c(live_supplied, v)
    }
    if (is.null(out[[v]])) {
      out[[v]] <- primary[[v]]
      next
    }
    out[[v]] <- coalesce_ts(primary[[v]], out[[v]])
  }

  # Only refine provenance when the caller handed us a classified primary;
  # this keeps the bare-list test path (and its expect_identical) untouched.
  prov <- attr(primary, "provenance")
  if (!is.null(prov)) {
    attr(out, "provenance") <- refine_provenance(prov, names(out),
                                                 live_supplied)
  }
  out
}

# Build the merged-database provenance from the primary's classification.
# Every variable in `vars` (the merged database's names) gets a class:
#   - a primary variable that supplied a non-NA value keeps its primary class;
#   - any other variable (fixture-only, or primary present but all-NA over the
#     union) is recorded as "fixture_fallback".
refine_provenance <- function(primary_prov, vars, live_supplied) {
  class_for <- primary_prov$source_class[match(vars, primary_prov$variable)]
  is_live <- vars %in% live_supplied & !is.na(class_for)
  class_for[!is_live] <- "fixture_fallback"
  tibble::tibble(variable = vars, source_class = class_for)
}

# Splice `primary` into `fallback`: union the time spans, use primary
# where it has a non-NA value, fall back to fallback elsewhere. The
# resulting bimets ts covers min(primary_start, fallback_start) to
# max(primary_end, fallback_end).
coalesce_ts <- function(primary, fallback) {
  p_tsp <- stats::tsp(primary)
  f_tsp <- stats::tsp(fallback)
  start_dec <- min(p_tsp[1], f_tsp[1])
  end_dec   <- max(p_tsp[2], f_tsp[2])
  start_year    <- floor(start_dec + 1e-9)
  start_quarter <- round((start_dec - start_year) * 4 + 1)
  n_total <- round((end_dec - start_dec) * 4 + 1)

  p_offset <- round((p_tsp[1] - start_dec) * 4)
  f_offset <- round((f_tsp[1] - start_dec) * 4)
  p_v <- as.numeric(primary)
  f_v <- as.numeric(fallback)

  out <- rep(NA_real_, n_total)
  # Fill fallback first
  if (length(f_v) > 0L) {
    f_idx <- seq(f_offset + 1L, length.out = length(f_v))
    keep <- f_idx >= 1L & f_idx <= n_total
    out[f_idx[keep]] <- f_v[keep]
  }
  # Then overlay primary where it has non-NA values
  if (length(p_v) > 0L) {
    p_idx <- seq(p_offset + 1L, length.out = length(p_v))
    keep <- p_idx >= 1L & p_idx <= n_total & !is.na(p_v)
    out[p_idx[keep]] <- p_v[keep]
  }
  bimets::TIMESERIES(out, START = c(start_year, start_quarter), FREQ = 4)
}

# Return c(first_nonna_quarter, last_nonna_quarter) as decimal years
# (e.g. 1959.5 = 1959Q3). c(NA, NA) if the series is all-NA. Kept for
# tests that exercised the old coverage-based rule.
nonna_range <- function(ts) {
  vals <- as.numeric(ts)
  nonna_pos <- which(!is.na(vals))
  if (length(nonna_pos) == 0L) return(c(NA_real_, NA_real_))
  tsp <- stats::tsp(ts)
  c(tsp[1] + (nonna_pos[1] - 1L) / 4,
    tsp[1] + (tail(nonna_pos, 1L) - 1L) / 4)
}
