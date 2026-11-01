#' The equation menu the LLM is allowed to adjust
#'
#' Reads `inst/extdata/equation_catalogue.csv` and returns a tibble of MARTIN
#' equations with plain-English descriptions, sector groupings, units, an
#' `adjustable` flag (pure identities should be `FALSE`), typical historical
#' add-factor SD, and transmission channel notes.
#'
#' The catalogue is curated, seeded from the English `'comments` in
#' `references/MARTIN-master/Programs/equations.prg` and the `COMMENT>` blocks
#' in `references/bimets-main/MARTINMOD_AF.txt`.
#'
#' @return A tibble with columns: `code`, `name`, `sector`, `equation_type`,
#'   `plain_english`, `units`, `adjustable`, `typical_af_sd`,
#'   `transmission_channel`.
#' @export
equation_catalogue <- function() {
  path <- system.file(
    "extdata", "equation_catalogue.csv",
    package = "martin", mustWork = FALSE
  )
  if (!nzchar(path) || !file.exists(path)) {
    path <- file.path("inst", "extdata", "equation_catalogue.csv")
  }
  readr::read_csv(path, show_col_types = FALSE)
}
