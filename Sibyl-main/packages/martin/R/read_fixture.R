#' Load the bundled MARTINDATA fixture into bimets shape
#'
#' Reads the frozen `MARTINDATA_XLSX.xlsx` snapshot copied from
#' `references/bimets-main/` into a named list of `bimets::TIMESERIES` keyed
#' by MARTIN variable name. This is the deterministic data input the
#' regression test compares against — see
#' [tests/testthat/test-regression-against-bimets.R].
#'
#' The xlsx layout: column 1 is `Dates` (the bimets `read_excel` driver
#' renames the unnamed first column to "Dates"), columns 2+ are quarterly
#' series at quarter-start dates.
#'
#' @param path Path to the xlsx. Defaults to [martin_data_fixture()].
#'
#' @return A named list of `bimets::TIMESERIES`, ready for
#'   [bimets::LOAD_MODEL_DATA()].
#' @export
read_fixture <- function(path = martin_data_fixture()) {
  if (!file.exists(path)) {
    stop("MARTINDATA fixture not found at ", path, call. = FALSE)
  }
  raw <- readxl::read_excel(path)
  names(raw)[1] <- "Dates"
  raw$Dates <- as.Date(raw$Dates)

  series_names <- setdiff(names(raw), "Dates")
  out <- vector("list", length(series_names))
  names(out) <- series_names
  for (nm in series_names) {
    out[[nm]] <- bimets::as.bimets(
      xts::xts(raw[[nm]], order.by = raw$Dates)
    )
  }
  out
}
