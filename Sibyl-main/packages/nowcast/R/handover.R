#' Variables nowcast covers by default
#'
#' The set of MARTIN observables that nowcast produces Q+0/Q+1 estimates for.
#' These are the headline macro aggregates that lag in real time — National
#' Accounts components, the labour-market headline numbers, the headline
#' price indices, and the financial-market series MARTIN takes as starting
#' values.
#'
#' Curated rather than derived from the catalogue: nowcast only needs the
#' subset that bridges between observed data and MARTIN's first solved
#' quarter. Many catalogue entries (derived deflators, sub-components of
#' exports, capital-stock interpolations) are computed from these and don't
#' need their own nowcast.
#'
#' @return Character vector of MARTIN variable codes.
#' @export
handover_variables <- function() {
  c(
    # Real expenditure components
    "RC", "ID", "IB", "V", "X", "M", "G", "GC", "GI",
    # Real GDP and the discrepancy
    "Y", "SD",
    # Nominal components
    "NC", "NID", "NIB", "NV", "NX", "NM", "NG",
    # Nominal GDP
    "NY",
    # Labour market
    "LE", "LF", "LUR", "LPR", "LPOP",
    # Prices
    "PTM", "P", "PC", "PG", "PID",
    # Wages
    "PW", "PAE",
    # Interest rates
    "NCR", "NMR", "N2R", "N10R",
    # Exchange rates
    "NTWI", "NUSD", "RTWI", "REWI",
    # World
    "WY", "WP", "WPX", "WPOIL", "WPCOM"
  )
}
