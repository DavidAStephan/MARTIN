#' Pull the public-data panels SIBYL needs
#'
#' Top-level orchestrator. Routes each requested source through
#' [fetch_source()] (which handles caching and source-specific dispatch) and
#' concatenates results into one long tidy tibble.
#'
#' All source fetchers cache their output as parquet under [cache_path()] —
#' a re-run on the same vintage returns instantly. `refresh = TRUE` re-pulls.
#'
#' v0 status: `fred` is implemented end-to-end against the live API;
#' `abs`, `rba`, `oecd`, `worldbank`, `bom` are stubs that throw informative
#' errors when called. The catalogue
#' ([series_catalogue()]) covers all sources so the institutional knowledge
#' is preserved even ahead of the fetchers.
#'
#' @param vintage A `Date` identifying the data vintage. Stamped into every
#'   row's `vintage` column and used as the cache key. Defaults to today.
#' @param sources Character vector of sources to refresh. Default:
#'   `"all"` — every implemented source. Pass an explicit vector to
#'   restrict (e.g. `c("fred")` for FRED-only).
#' @param refresh Logical. If `FALSE` (default), cached vintages are
#'   returned untouched. `TRUE` re-pulls.
#' @param tolerate_failures Logical. If `TRUE` (default), a single
#'   source's failure (typically a transient network error) emits a
#'   warning and the run continues with the surviving sources — the
#'   downstream pipeline can fall back to the fixture via
#'   [merge_with_fallback()]. If `FALSE`, any source failure halts the run.
#'
#' @return A tidy tibble of `(series_id, source, date, value, vintage)`.
#' @export
update_data <- function(vintage = Sys.Date(),
                        sources = "all",
                        refresh = FALSE,
                        tolerate_failures = TRUE) {
  vintage <- as.Date(vintage)
  all_sources <- c("abs", "rba", "fred", "oecd", "worldbank", "bom")
  if (identical(sources, "all")) sources <- all_sources
  bad <- setdiff(sources, all_sources)
  if (length(bad)) {
    stop("Unknown source(s): ", paste(bad, collapse = ", "),
         ". Valid sources: ", paste(all_sources, collapse = ", "), ".",
         call. = FALSE)
  }

  panels <- purrr::map(sources, function(src) {
    if (!tolerate_failures) {
      return(fetch_source(src, vintage = vintage, refresh = refresh))
    }
    tryCatch(
      fetch_source(src, vintage = vintage, refresh = refresh),
      error = function(e) {
        warning("update_data: source '", src, "' failed (",
                conditionMessage(e), "); continuing without it.",
                call. = FALSE)
        NULL
      }
    )
  })
  dplyr::bind_rows(panels)
}

#' Pivot a raw tidy panel to MARTIN's variable names
#'
#' Joins the catalogue (`source_id` → `martin_var`), then routes each row
#' through the appropriate transformation handler. Returns a named list of
#' `bimets::TIMESERIES` keyed by MARTIN variable name, ready for
#' [martin::load_martin()].
#'
#' The pipeline (in order):
#'
#' 1. **Direct / level_from_pct / spliced rows** → standard quarterly pivot
#'    via [pivot_quarterly()] (handles monthly→quarterly aggregation per
#'    each row's `aggregation` rule).
#' 2. **Chow-Lin rows** → annual pivot, then disaggregated to quarterly
#'    via [apply_chowlin()] using `tempdisagg::td()`.
#' 3. **`apply_level_from_pct()`** → replaces PTM, P with cumulated level
#'    indices from registered bases (1982Q1).
#' 4. **`apply_splices()`** → forward-extends or backward-fills target
#'    series from spliced sources (NCR_HIST → NCR; NBR_SPLICE → NBR).
#' 5. **`apply_pim()`** → integrates V into KV via the perpetual-inventory
#'    method from a 1980Q1 base.
#' 6. **`add_derived_series()`** → evaluates catalogue formula expressions
#'    (PC, PG, PM, TOT, NHA, NHNW, HCOE, etc.) in a fixed-point loop.
#'
#' Anything that can't be materialised is reported in the `"skipped"`
#' attribute, grouped by reason.
#'
#' @param raw A tibble from [update_data()].
#' @param frequency Target frequency. Only `"Q"` is supported in v0.
#'
#' @return A named list of `bimets::TIMESERIES`, with attributes:
#'   - `skipped`: list of skipped martin_vars grouped by reason.
#'   - `derived_added`: character vector of derived vars that materialised.
#' @export
to_martin_database <- function(raw, frequency = "Q") {
  if (frequency != "Q") {
    stop("Only quarterly target frequency is supported in v0.",
         call. = FALSE)
  }
  cat <- series_catalogue()
  joined <- join_panel_to_catalogue(raw, cat)
  joined <- joined[!is.na(joined$martin_var), , drop = FALSE]

  # Slice 1: quarterly-target rows — direct, level_from_pct, spliced.
  q_rows <- joined[joined$transformation %in%
                     c("direct", "level_from_pct", "spliced"),
                   , drop = FALSE]
  db <- pivot_quarterly(q_rows)

  # Slice 2: annual rows for Chow-Lin disaggregation.
  a_rows <- joined[joined$transformation == "chowlin", , drop = FALSE]
  annual_db <- pivot_annual(a_rows)

  # Apply transformations in dependency order. PIM (KV from V) must come
  # before derived since some formulas reference KV. Chow-Lin must come
  # before derived since IBN = IB - IBRE references IBRE. Dummies and
  # scalars are deterministic calendar series independent of the data
  # slice, so they run last (and consult database_span to size themselves
  # to the data they accompany).
  db <- apply_level_from_pct(db, cat)
  db <- apply_splices(db, cat)
  db <- apply_chowlin(db, annual_db, cat)
  db <- apply_pim(db, cat)
  # IBCTR and IBNDR are deterministic/static inputs needed by the IBCR
  # identity chain; populate before add_derived_series so the IBNDRA /
  # RBR / IBCR formulas can evaluate. apply_ibndr_annual computes IBNDR
  # from the annual CFC/K capital-stock series when available; otherwise
  # apply_ibndr falls back to a static placeholder.
  db <- apply_ibctr(db, cat)
  db <- apply_ibndr_annual(db, annual_db, cat)
  db <- apply_ibndr(db, cat)
  db <- apply_iad_weights(db, cat)
  db <- add_derived_series(db, cat)
  # State-space trends depend on LHPP being derived (HOURS / LE * 3),
  # so they run after add_derived_series.
  db <- apply_state_space_trends(db, cat)
  db <- apply_dummies(db, cat)
  db <- apply_scalars(db, cat)

  derived_added   <- attr(db, "derived_added")
  derived_skipped <- attr(db, "derived_skipped")

  expected_direct  <- cat$martin_var[cat$transformation == "direct"]
  no_formula_rows  <- cat$martin_var[cat$transformation == "derived" &
                                       is.na(cat$formula)]

  # "other_transforms" = catalogue rows tagged with a non-direct
  # transformation that still didn't make it into the database (e.g. no
  # source data was supplied for them).
  transform_keys <- c("spliced", "chowlin", "level_from_pct")
  other_transforms <- cat$martin_var[cat$transformation %in% transform_keys]
  other_transforms <- setdiff(other_transforms, names(db))

  skipped <- list(
    no_data            = setdiff(expected_direct, names(db)),
    derived_no_inputs  = derived_skipped,
    derived_no_formula = no_formula_rows,
    other_transforms   = other_transforms
  )
  attr(db, "skipped")       <- skipped
  attr(db, "derived_added") <- derived_added
  # Provenance: classify every variable that actually made it into the
  # database from the catalogue. At this point the database was built purely
  # from the supplied `raw` panel, so data-backed rows are genuinely "live";
  # merge_with_fallback() later promotes any variable the live path could not
  # supply to "fixture_fallback". Additive only -- the database itself is
  # unchanged. See database_provenance() for the accessor.
  attr(db, "provenance")    <- classify_provenance(names(db), cat)
  db
}

# Internal: left-join raw panel against catalogue to recover MARTIN names.
join_panel_to_catalogue <- function(raw, catalogue) {
  dplyr::left_join(
    raw,
    catalogue[, c("source_id", "source", "martin_var",
                  "source_frequency", "aggregation", "transformation")],
    by = c("series_id" = "source_id", "source")
  )
}

# Internal: pivot panel rows for quarterly-target transformations into a
# named list of bimets ts. Returns empty list on empty input.
pivot_quarterly <- function(rows) {
  if (nrow(rows) == 0L) return(list())
  rows$quarter_date <- to_quarter_date(rows$date)
  agg <- rows |>
    dplyr::group_by(martin_var, quarter_date, source_frequency, aggregation) |>
    dplyr::summarise(
      value = aggregate_to_quarter(value, source_frequency[1], aggregation[1]),
      .groups = "drop"
    ) |>
    dplyr::arrange(martin_var, quarter_date)
  out <- list()
  for (mv in unique(agg$martin_var)) {
    sub <- agg[agg$martin_var == mv, , drop = FALSE]
    if (nrow(sub) == 0L) next
    qd <- sub$quarter_date[1]
    start_year    <- as.integer(format(qd, "%Y"))
    start_quarter <- as.integer(
      (as.integer(format(qd, "%m")) - 1L) %/% 3L + 1L
    )
    out[[mv]] <- bimets::TIMESERIES(
      sub$value, START = c(start_year, start_quarter), FREQ = 4
    )
  }
  out
}

# Internal: pivot annual panel rows into a named list of frequency-1
# bimets ts. One value per year (last observation if multiple).
pivot_annual <- function(rows) {
  if (nrow(rows) == 0L) return(list())
  rows$year <- as.integer(format(rows$date, "%Y"))
  agg <- rows |>
    dplyr::group_by(martin_var, year) |>
    dplyr::summarise(
      value = dplyr::last(value),
      .groups = "drop"
    ) |>
    dplyr::arrange(martin_var, year)
  out <- list()
  for (mv in unique(agg$martin_var)) {
    sub <- agg[agg$martin_var == mv, , drop = FALSE]
    out[[mv]] <- stats::ts(sub$value, start = sub$year[1], frequency = 1)
  }
  out
}

#' Where the local parquet cache lives
#'
#' Honours `SIBYL_DATA_CACHE` if set; otherwise `data/cache/` under the
#' project root (discovered via `here::here()`).
#'
#' @return Character path. Creates the directory if missing.
#' @export
cache_path <- function() {
  override <- Sys.getenv("SIBYL_DATA_CACHE", unset = "")
  path <- if (nzchar(override)) {
    override
  } else {
    file.path(here::here(), "data", "cache")
  }
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  path
}

# Convert any monthly / quarterly / daily Date to the quarter-start Date.
# E.g. 1991-04-15 -> 1991-04-01.
to_quarter_date <- function(d) {
  d <- as.Date(d)
  year    <- as.integer(format(d, "%Y"))
  month   <- as.integer(format(d, "%m"))
  quarter <- (month - 1L) %/% 3L + 1L
  as.Date(sprintf("%04d-%02d-01", year, (quarter - 1L) * 3L + 1L))
}

# Aggregate a vector of within-quarter values to a single quarterly value
# per the catalogue's `aggregation` rule. Quarterly sources pass through.
aggregate_to_quarter <- function(values, source_frequency, aggregation) {
  if (source_frequency == "Q") {
    return(values[length(values)])  # single value per quarter; just take it
  }
  if (is.na(aggregation)) {
    stop("Sub-quarterly source missing aggregation rule.", call. = FALSE)
  }
  switch(aggregation,
    mean  = mean(values, na.rm = TRUE),
    sum   = sum(values,  na.rm = TRUE),
    last  = values[length(values)],
    first = values[1],
    stop("Unknown aggregation rule: ", aggregation, call. = FALSE)
  )
}
