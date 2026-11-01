# Evaluate the `derived` slice of the catalogue.
#
# Each catalogue row tagged `transformation = "derived"` with a non-NA
# `formula` carries an R expression (string) that computes the MARTIN
# variable from other variables already in the database. The evaluator
# parses the expression and runs it against the database — bimets
# TIMESERIES objects support arithmetic via base R's ts methods, so an
# expression like `NC / RC * 100` produces a time-aligned bimets ts.
#
# Cross-dependencies between derived rows (e.g. NHA depends on NHNFA, which
# depends on NHNFA_CD + NHNFA_DW) are resolved by iterating until no row's
# formula references an unavailable variable — a simple fixed-point loop.

#' Evaluate one derived formula against the current database
#'
#' Returns the computed bimets time series, or a `try-error` if the formula
#' is malformed or any input is missing. The function does not insert the
#' result back into the database; the caller is expected to do that.
#'
#' @param formula Character. An R expression (e.g. `"NC / RC * 100"`).
#' @param database A named list of bimets TIMESERIES.
#' @return A bimets ts, or a `try-error` object on failure.
#' @keywords internal
evaluate_derived_formula <- function(formula, database) {
  if (is.na(formula) || !nzchar(formula)) {
    return(structure(
      list(message = "empty formula"),
      class = c("try-error", "condition")
    ))
  }
  expr <- try(parse(text = formula)[[1]], silent = TRUE)
  if (inherits(expr, "try-error")) return(expr)

  env <- list2env(database, parent = baseenv())
  try(eval(expr, envir = env), silent = TRUE)
}

#' Add derived series to a MARTIN-shape database
#'
#' Iterates over the catalogue's derived rows (those with a non-NA
#' formula), computing each one against the current database and inserting
#' the result. Variables whose formulas reference still-missing inputs are
#' retried each pass; the loop terminates when no progress is made.
#'
#' @param database A named list of bimets TIMESERIES (the direct-slice
#'   output of [to_martin_database()]).
#' @param catalogue A tibble from [series_catalogue()]. Defaults to the
#'   bundled catalogue.
#'
#' @return The database with derived series added. Two attributes record
#'   what happened:
#'   * `derived_added`   — character vector of newly-materialised vars
#'   * `derived_skipped` — character vector of derived rows whose formula
#'                          couldn't be evaluated (typically because an
#'                          upstream non-direct dependency is missing).
#' @export
add_derived_series <- function(database, catalogue = series_catalogue()) {
  derived <- catalogue[catalogue$transformation == "derived" &
                         !is.na(catalogue$formula), , drop = FALSE]
  if (nrow(derived) == 0L) {
    attr(database, "derived_added")   <- character()
    attr(database, "derived_skipped") <- character()
    return(database)
  }

  remaining <- derived
  added <- character()
  repeat {
    progress <- FALSE
    for (i in seq_len(nrow(remaining))) {
      mv      <- remaining$martin_var[i]
      formula <- remaining$formula[i]
      if (!is.null(database[[mv]])) next  # already present
      result <- evaluate_derived_formula(formula, database)
      if (!inherits(result, "try-error") && inherits(result, "ts")) {
        database[[mv]] <- result
        added <- c(added, mv)
        progress <- TRUE
      }
    }
    # Drop ones we managed to add
    remaining <- remaining[!remaining$martin_var %in% added, , drop = FALSE]
    if (!progress || nrow(remaining) == 0L) break
  }

  attr(database, "derived_added")   <- added
  attr(database, "derived_skipped") <- remaining$martin_var
  database
}
