#' Path to one of the vendored MARTIN model files
#'
#' The bimets `.txt` model definitions are vendored into `inst/extdata/` from
#' `references/bimets-main/`. This helper returns the absolute path on disk.
#'
#' @param variant One of `"af"` (default — `MARTINMOD_AF.txt`, the behavioural
#'   form with a `ConstantAdjustment` add-factor slot on every equation),
#'   `"identity"` (`MARTINMOD.txt`, pure-identity equivalent), or `"est"`
#'   (`MARTINMOD_EST.txt`, the form intended for re-estimation). Note that
#'   `"af"` is genuinely behavioural: of its 95 `BEHAVIORAL>` equations only
#'   ~51 carry a `RESTRICT> c1=1`; the rest impose real cross-coefficient
#'   restrictions (e.g. `c4+c5+c6+c7=1`, `c4=0.5`). `bimets::ESTIMATE()`
#'   re-fits the free coefficients on every load — it does not replay
#'   published EViews values as-is.
#' @return Absolute path to the `.txt` file.
#' @export
model_file_path <- function(variant = c("af", "identity", "est")) {
  variant <- match.arg(variant)
  fname <- switch(variant,
    af       = "MARTINMOD_AF.txt",
    identity = "MARTINMOD.txt",
    est      = "MARTINMOD_EST.txt"
  )
  path <- system.file("extdata", fname, package = "martin", mustWork = FALSE)
  if (!nzchar(path) || !file.exists(path)) {
    # devtools::load_all() path during development
    path <- file.path("inst", "extdata", fname)
  }
  path
}

#' Path to the bundled MARTINDATA fixture
#'
#' The frozen `MARTINDATA_XLSX.xlsx` copied from
#' `references/bimets-main/`. Used by the regression test that asserts
#' SIBYL's solve matches the bimets reference solve.
#'
#' @return Absolute path to the `.xlsx` file.
#' @export
martin_data_fixture <- function() {
  path <- system.file(
    "extdata", "martin_data_fixture.xlsx",
    package = "martin", mustWork = FALSE
  )
  if (!nzchar(path) || !file.exists(path)) {
    path <- file.path("inst", "extdata", "martin_data_fixture.xlsx")
  }
  path
}

#' Load a MARTIN bimets model with data
#'
#' Wraps the canonical pattern from
#' `references/bimets-main/BIMETS_MARTIN_LOAD.R`:
#'
#' ```r
#' MARTIN <- bimets::LOAD_MODEL("MARTINMOD_AF.txt")
#' MARTIN <- bimets::LOAD_MODEL_DATA(MARTIN, data)
#' MARTIN <- bimets::ESTIMATE(MARTIN)
#' ```
#'
#' For the default `variant = "af"`, ESTIMATE actually re-fits the free
#' coefficients of all 95 behavioural equations on every load — it does NOT
#' merely confirm imposed values. Only ~51 of those equations carry a
#' `RESTRICT> c1=1`; the rest impose genuine cross-coefficient restrictions
#' (e.g. `c4+c5+c6+c7=1`). ESTIMATE also computes each equation's residuals,
#' and those residuals are what the add-factor pipeline consumes downstream.
#' "Frozen" coefficients (the default) means estimating over the model file's
#' embedded 2019Q3 `TSRANGE` sample, not loading published EViews values.
#'
#' @param database A named list of `bimets::TIMESERIES` keyed by MARTIN
#'   variable name. Eventually produced by
#'   [sibyldata::to_martin_database()]; for now, by [read_fixture()] in tests.
#' @param variant Which model file to load. See [model_file_path()].
#' @param estimation_end Optional `"yyyyQq"` string. When set, rewrites
#'   every `TSRANGE` line's end date to this quarter before bimets
#'   loads the model — letting ESTIMATE re-fit the behavioural
#'   coefficients on data through the supplied end (typically the
#'   latest National Accounts release). Per-equation start dates are
#'   preserved. The model file's frozen default is 2019Q3.
#' @param estimate Logical. If `TRUE` (default), call `bimets::ESTIMATE()`
#'   after loading data. Skip only for path-checking; the residual slots
#'   downstream code uses are populated by ESTIMATE.
#'
#' @return A loaded bimets model object.
#' @export
load_martin <- function(database,
                        variant         = c("af", "identity", "est"),
                        estimate        = TRUE,
                        estimation_end  = NULL,
                        features        = character(0),
                        feature_params  = list()) {
  variant <- match.arg(variant)
  if (!is.list(database) || length(database) == 0L) {
    stop("`database` must be a non-empty named list of bimets TIMESERIES.",
         call. = FALSE)
  }
  if (is.null(names(database)) || any(!nzchar(names(database)))) {
    stop("`database` must be named; names are MARTIN variable codes.",
         call. = FALSE)
  }

  model_lines <- readLines(model_file_path(variant))
  if (!is.null(estimation_end)) {
    model_lines <- rewrite_tsrange_end(model_lines, estimation_end)
  }
  if (length(features)) {
    # Seed any series the features introduce (idempotent: only adds what is
    # missing), so load_martin(features=) works standalone, not only via
    # solve_martin().
    database <- seed_feature_data(database, features, feature_params)
    model_lines <- apply_model_features(model_lines, features, feature_params)
  }
  model_text <- paste(model_lines, collapse = "\n")
  .suppress_bimets_version_warning({
    m <- bimets::LOAD_MODEL(modelText = model_text)
    m <- bimets::LOAD_MODEL_DATA(m, database)
    if (isTRUE(estimate)) {
      m <- bimets::ESTIMATE(m)
    }
  })
  m
}

# Rewrite each `TSRANGE <start_year> <start_quarter> <end_year> <end_quarter>`
# line in the model text so the end equals `end_quarter` (a "yyyyQq" string),
# preserving each equation's per-line start date. Used by load_martin's
# `estimation_end` option to re-estimate behavioural coefficients on a
# longer sample than the model file's frozen 2019Q3 default.
rewrite_tsrange_end <- function(lines, end_quarter) {
  if (!grepl("^[0-9]{4}Q[1-4]$", end_quarter)) {
    stop("`estimation_end` must be a 'yyyyQq' string (e.g. '2025Q2').",
         call. = FALSE)
  }
  new_year    <- substr(end_quarter, 1, 4)
  new_quarter <- substr(end_quarter, 6, 6)
  is_tsrange <- grepl("^TSRANGE ", lines)
  lines[is_tsrange] <- vapply(lines[is_tsrange], function(ln) {
    parts <- strsplit(ln, " ")[[1]]
    # Expected: TSRANGE start_year start_q end_year end_q  (5 tokens)
    if (length(parts) != 5L) return(ln)
    paste("TSRANGE", parts[2], parts[3], new_year, new_quarter)
  }, character(1))
  lines
}
