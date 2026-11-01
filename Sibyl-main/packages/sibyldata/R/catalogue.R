#' The series catalogue
#'
#' The institutional knowledge for SIBYL: each row maps a MARTIN variable to
#' a source series ID plus the metadata needed to fetch and shape it. Lifted
#' and extended from
#' `references/MARTIN-master/Programs/import_data.prg`.
#'
#' Columns:
#'
#' - `martin_var` — the MARTIN variable name (uppercase for model endogenous
#'   variables; lowercase for raw imports that get transformed downstream).
#' - `source` — one of `abs`, `rba`, `fred`, `oecd`, `worldbank`, `bom`,
#'   `derived`.
#' - `source_id` — the source's series identifier (`A2304081W` for ABS,
#'   `GDPC1` for FRED, etc.). `NA` for derived series.
#' - `source_table` — catalogue / table reference where it helps (e.g.
#'   `"5206.0"` for ABS, `"F02"` for RBA). `NA` otherwise.
#' - `source_frequency` — `M`, `Q`, `A`, or `D` for monthly / quarterly /
#'   annual / daily.
#' - `aggregation` — how to convert to quarterly (`mean`, `sum`, `last`,
#'   `first`). `NA` when source is already quarterly.
#' - `transformation` — `direct` (just rename), `spliced` (needs
#'   backcasting / splicing), `chowlin` (Chow-Lin annual→quarterly),
#'   `level_from_pct` (cumulate from a base), `derived` (computed from other
#'   catalogue entries), `dummy` (deterministic calendar dummy / trend,
#'   spec in `inst/extdata/dummies.csv`), `scalar` (constant series,
#'   spec in `inst/extdata/scalars.csv`).
#' - `description` — plain English (consumed by the LLM and humans alike).
#' - `units` — free text.
#'
#' @return A tibble of the catalogue.
#' @export
series_catalogue <- function() {
  path <- system.file(
    "extdata", "series_catalogue.csv",
    package = "sibyldata", mustWork = FALSE
  )
  if (!nzchar(path) || !file.exists(path)) {
    path <- file.path("inst", "extdata", "series_catalogue.csv")
  }
  readr::read_csv(path, show_col_types = FALSE)
}

# The canonical provenance taxonomy. Every variable SIBYL hands to MARTIN is
# tagged with exactly one of these classes so downstream provenance reporting
# never conflates a live fetch with a fixture backfill or a vendored .wf1
# splice. Kept in one place so update_data.R and merge.R agree.
#   live            -- materialised from a freshly fetched source panel
#                      (ABS / RBA / FRED / OECD / World Bank / BOM).
#   fixture_fallback-- supplied (wholly or in the historical gap) by the
#                      bundled fixture via merge_with_fallback().
#   vendored_wf1    -- spliced from references/MARTIN-master .wf1 output
#                      (state-space trends we have not re-ported).
#   proxy           -- a stand-in series (e.g. US GDP proxying world GDP).
#   dummy           -- deterministic calendar dummy / trend / scalar.
#   derived         -- computed from other catalogue entries (formula/identity).
#   unknown         -- in the database but absent from the catalogue.
.provenance_classes <- c(
  "live", "fixture_fallback", "vendored_wf1", "proxy", "dummy",
  "derived", "unknown"
)

#' Classify catalogue variables into provenance source classes
#'
#' Maps each MARTIN variable named in `variables` to its intended
#' [provenance][database_provenance] `source_class`, derived purely from the
#' catalogue's `transformation` / `source` / `description` columns. This is the
#' *intended* class as built by [to_martin_database()] from a freshly fetched
#' panel; [merge_with_fallback()] later promotes individual variables to
#' `"fixture_fallback"` when the live path supplied no value.
#'
#' Mapping rules (first match wins):
#'   - `transformation` in {`dummy`, `scalar`} -> `"dummy"`.
#'   - `transformation` in {`derived`, `identity`} -> `"derived"`.
#'   - `transformation` == `state_space` -> `"vendored_wf1"`.
#'   - a real data row whose `description` mentions "proxy" -> `"proxy"`.
#'   - any other real data row (direct / spliced / chowlin / level_from_pct
#'     from abs / rba / fred / oecd / worldbank / bom) -> `"live"`.
#'   - a variable not present in the catalogue -> `"unknown"`.
#'
#' @param variables Character vector of MARTIN variable names.
#' @param catalogue The catalogue tibble. Defaults to [series_catalogue()].
#' @return A tibble `(variable, source_class)`, one row per input variable,
#'   in input order. `source_class` is one of
#'   `r paste(sibyldata:::.provenance_classes, collapse = ", ")`.
#' @export
classify_provenance <- function(variables, catalogue = series_catalogue()) {
  variables <- as.character(variables)
  if (length(variables) == 0L) {
    return(tibble::tibble(
      variable = character(0), source_class = character(0)
    ))
  }
  idx <- match(variables, catalogue$martin_var)
  classes <- vapply(seq_along(variables), function(i) {
    j <- idx[i]
    if (is.na(j)) {
      return("unknown")
    }
    transformation <- catalogue$transformation[j]
    description    <- catalogue$description[j]
    if (isTRUE(transformation %in% c("dummy", "scalar"))) {
      return("dummy")
    }
    if (isTRUE(transformation %in% c("derived", "identity"))) {
      return("derived")
    }
    if (isTRUE(transformation == "state_space")) {
      return("vendored_wf1")
    }
    if (!is.na(description) && grepl("proxy", description, ignore.case = TRUE)) {
      return("proxy")
    }
    # A genuine fetched data row (direct / spliced / chowlin / level_from_pct).
    "live"
  }, character(1))
  tibble::tibble(variable = variables, source_class = classes)
}

#' Read a database's provenance table
#'
#' Accessor for the `"provenance"` attribute attached by
#' [to_martin_database()] (and refined by [merge_with_fallback()]). The table
#' records, for each MARTIN variable in the database, where its values actually
#' came from -- so a report never has to guess whether a series was a live
#' fetch, a fixture backfill, a vendored `.wf1` splice, or a proxy.
#'
#' @param db A MARTIN database (named list of bimets `TIMESERIES`) produced by
#'   [to_martin_database()] / [merge_with_fallback()].
#' @return A tibble `(variable, source_class)`, or `NULL` when no provenance
#'   attribute is present (e.g. a hand-built database). `source_class` is one
#'   of `r paste(sibyldata:::.provenance_classes, collapse = ", ")`.
#' @export
database_provenance <- function(db) {
  attr(db, "provenance")
}
