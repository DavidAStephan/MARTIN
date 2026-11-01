#' martin: SIBYL wrapper around the bimets implementation of MARTIN
#'
#' The Reserve Bank of Australia's MARTIN macroeconometric model, solved via
#' the `bimets` package. Built on the code in
#' `references/bimets-main/`; the model definition files are vendored into
#' `inst/extdata/` of this package with attribution.
#'
#' The public surface is small:
#'
#' - [load_martin()] — read the bimets model file and a database, return a
#'   loaded bimets model object.
#' - [solve_martin()] — solve baseline plus add-factor scenarios; returns a
#'   tidy projection tibble.
#' - [equation_catalogue()] — the equation menu the LLM sees, with
#'   plain-English descriptions, sector groupings, and which equations are
#'   eligible for adjustment.
#' - [martin_data_fixture()] — the frozen MARTINDATA_XLSX snapshot used by
#'   regression tests.
#'
#' v0 uses the `MARTINMOD_AF.txt` form. That file holds 95 `BEHAVIORAL>`
#' equations; only ~51 carry a `RESTRICT> c1=1`, and the rest impose real
#' cross-coefficient restrictions (e.g. `c4+c5+c6+c7=1`, `c4=0.5`).
#' `bimets::ESTIMATE()` re-fits the free coefficients on EVERY load — it is
#' not loading the published EViews values as-is. The default ("frozen")
#' only means estimating over the model file's embedded 2019Q3 `TSRANGE`
#' sample; the alternative is re-estimating through a later quarter, which
#' re-fits across the COVID break (see [solve_martin()]'s `coefficients`).
#'
#' @keywords internal
"_PACKAGE"
