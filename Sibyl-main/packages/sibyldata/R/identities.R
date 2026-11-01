# Handlers for MARTIN's deterministic identity-chain inputs:
#
#   IBCTR   — corporate tax rate (piecewise-constant per
#             references/MARTIN-master/Programs/import_data.prg:535-562)
#   IBNDR   — non-mining business depreciation rate (computed from
#             annual ABS 5204.0 capital-stock and consumption-of-fixed-
#             capital series, interpolated to quarterly)
#   IBNDRA  — annual depreciation rate; identity = IBNDR + 3 lags
#   RBR     — real business rate; identity from IBCTR, NBR, PTM
#   IBCR    — user cost of capital; identity from RBR, IBNDRA, IBCTR,
#             N10R, PIBN, PGNE
#
#   IAD_W_C/I/GI/GC/X — import-adjusted demand weights from ABS
#                       input-output tables (1999, 2002, 2005-2010,
#                       2013-2017), interpolated to quarterly. Vendored
#                       directly from the EViews io_calcs.prg output
#                       (`inst/extdata/iad_weights.csv` = a copy of
#                       references/MARTIN-master/Data/t_iad.csv).
#
# IBCR's identity chain (from MARTINMOD_AF.txt:654-681) cascades:
#   IBCR  = (RBR/100 + IBNDRA/100) * ((1 - IBCTR*X) / (1 - IBCTR)) * (PIBN/PGNE)
#   X     = IBNDRA/100 * (1 + N10R/100) / (N10R/100 + IBNDRA/100)
#   RBR   = (1 + (1 - IBCTR) * NBR/100) / (lag(PTM,1)/lag(PTM,5)) * 100 - 100
#   IBNDRA = IBNDR + lag(IBNDR,1) + lag(IBNDR,2) + lag(IBNDR,3)
#
# So once IBCTR, IBNDR are in the database, IBNDRA, RBR, IBCR all follow
# as derived formula rows.

# Piecewise IBCTR breakpoints from import_data.prg:535-562. Each row:
# (from quarter, value). The series is constant at `value` from `from`
# onward, until the next breakpoint.
IBCTR_BREAKPOINTS <- list(
  list(from = "1959Q3", value = 0.40),   # @first 1963q2 — use first-available as start
  list(from = "1963Q3", value = 0.425),
  list(from = "1967Q3", value = 0.45),
  list(from = "1969Q3", value = 0.475),
  list(from = "1973Q3", value = 0.45),
  list(from = "1974Q3", value = 0.425),
  list(from = "1976Q3", value = 0.46),
  list(from = "1986Q3", value = 0.49),
  list(from = "1988Q3", value = 0.39),
  list(from = "1993Q3", value = 0.33),
  list(from = "1995Q3", value = 0.36),
  list(from = "1999Q3", value = 0.34),
  list(from = "2000Q3", value = 0.30)
)

#' Apply the IBCTR piecewise-constant series
#'
#' Builds IBCTR (Australian corporate tax rate) as a piecewise-constant
#' series over the database's span using the breakpoint table from
#' [import_data.prg:535-562](references/MARTIN-master/Programs/import_data.prg#L535-L562).
#' Idempotent: leaves IBCTR alone if already present.
#'
#' @param database Named list of bimets ts.
#' @param catalogue [series_catalogue()] (unused in v0).
#' @return Database with IBCTR added.
#' @keywords internal
apply_ibctr <- function(database, catalogue = series_catalogue()) {
  if (!is.null(database[["IBCTR"]])) return(database)
  span <- database_span(database)
  n <- span$n_quarters
  y0 <- span$start_year
  q0 <- span$start_quarter

  vals <- rep(NA_real_, n)
  for (bp in IBCTR_BREAKPOINTS) {
    from_yq <- parse_yyyyQq(bp$from)
    from_idx <- (from_yq$year - y0) * 4L + (from_yq$quarter - q0) + 1L
    from_idx <- max(1L, from_idx)
    if (from_idx > n) next
    vals[from_idx:n] <- bp$value
  }
  # Pre-first-breakpoint quarters: carry the earliest value backward.
  first_bp_yq <- parse_yyyyQq(IBCTR_BREAKPOINTS[[1]]$from)
  first_bp_idx <- (first_bp_yq$year - y0) * 4L +
                   (first_bp_yq$quarter - q0) + 1L
  if (first_bp_idx > 1L) {
    vals[seq_len(min(first_bp_idx - 1L, n))] <-
      IBCTR_BREAKPOINTS[[1]]$value
  }

  database[["IBCTR"]] <- bimets::TIMESERIES(
    vals, START = c(y0, q0), FREQ = 4
  )
  database
}

#' Apply the IAD weights from vendored io_calcs.prg output
#'
#' Reads `inst/extdata/iad_weights.csv` (a verbatim copy of
#' `references/MARTIN-master/Data/t_iad.csv` — the output of EViews's
#' `io_calcs.prg`, which interpolates ABS input-output table omega
#' values across 13 years) and inserts each of the five IAD weight
#' series into the database.
#'
#' Vendoring the CSV avoids reimplementing the IO-table extraction (13
#' year-specific XLS files with year-specific cell ranges) — a session
#' unto itself with limited additional fidelity since the omega values
#' only update when ABS releases new IO tables. A separate follow-up
#' could add a `update_iad_weights()` that reads fresh IO tables.
#'
#' @inheritParams apply_ibctr
#' @return Database with IAD_W_C, IAD_W_GC, IAD_W_GI, IAD_W_I, IAD_W_X
#'   added.
#' @keywords internal
apply_iad_weights <- function(database, catalogue = series_catalogue()) {
  path <- system.file("extdata", "iad_weights.csv", package = "sibyldata")
  if (!nzchar(path)) {
    path <- file.path("inst", "extdata", "iad_weights.csv")  # pkgload fallback
  }
  weights <- utils::read.csv(path, check.names = FALSE)
  # First column is the quarter label (e.g. "1959Q3"); read.csv may give
  # it an empty name, so use positional index. The remaining columns are
  # the five weights.
  qs    <- weights[[1]]
  vars  <- c("IAD_W_C", "IAD_W_GC", "IAD_W_GI", "IAD_W_I", "IAD_W_X")
  for (v in vars) {
    if (!is.null(database[[v]])) next
    if (!(v %in% names(weights))) next  # column missing; skip
    yq <- parse_yyyyQq(qs[1])
    database[[v]] <- bimets::TIMESERIES(
      as.numeric(weights[[v]]),
      START = c(yq$year, yq$quarter), FREQ = 4
    )
  }
  database
}

#' Apply a static IBNDR placeholder series
#'
#' Builds a constant `IBNDR` (quarterly depreciation rate, percent) at
#' the value `IBNDR_STATIC` (currently 1.5, the midpoint of the
#' fixture's [1.14, 1.65] range). This is a v0 placeholder; a faithful
#' port would compute IBNDR from annual ABS 5204.0 capital-stock and
#' consumption-of-fixed-capital series via:
#'
#'   CFCIBN_annual = CFCTOT - CFCID - CFCOTC - CFCIBRE
#'   KIBN_annual   = KTOT   - KID   - KOTC   - KIBRE
#'   IBNDRA_annual = 100 * (CFCIBN / lag(KIBN, 1))
#'   IBNDR_quarterly = ((1 + IBNDRA_annual/100)^(1/4) - 1) * 100
#'                     then linearly interpolated annual→quarterly
#'
#' The four CFC* catalogue rows are present (annual ABS series via
#' Chow-Lin) so a future iteration can flip from this static value to
#' the proper interpolation.
#'
#' @inheritParams apply_ibctr
#' @keywords internal
IBNDR_STATIC <- 1.5

apply_ibndr <- function(database, catalogue = series_catalogue()) {
  if (!is.null(database[["IBNDR"]])) return(database)
  span <- database_span(database)
  database[["IBNDR"]] <- bimets::TIMESERIES(
    rep(IBNDR_STATIC, span$n_quarters),
    START = c(span$start_year, span$start_quarter),
    FREQ  = 4
  )
  database
}

#' Apply the annual-data-driven IBNDR depreciation rate
#'
#' Faithful port of [modify_data.prg:487-500](references/MARTIN-master/Programs/modify_data.prg#L487-L500).
#' Computes annual non-mining business depreciation rate from the four
#' annual ABS 5204.0 series (CFCTOT, CFCID, CFCOTC, CFCIBRE for
#' consumption-of-fixed-capital; KTOT, KID, KOTC, KIBRE for capital
#' stock), converts to a quarterly compounding rate, linearly
#' interpolates to the quarterly grid, then backcasts to the start of
#' the database and forward-fills to the end.
#'
#'   CFCIBN_annual  = CFCTOT - CFCID - CFCOTC - CFCIBRE
#'   KIBN_annual    = KTOT   - KID   - KOTC   - KIBRE
#'   IBNDRA_annual  = 100 * (CFCIBN_t / KIBN_{t-1})       # annual rate
#'   IBNDR_quarterly = ((1 + IBNDRA_annual/100)^(1/4) - 1) * 100
#'
#' Replaces the static [apply_ibndr] placeholder when the annual inputs
#' are available; falls back to the placeholder if any input is missing.
#'
#' @param database Named list of bimets ts (quarterly).
#' @param annual_db Named list of `ts` (annual, frequency 1).
#' @inheritParams apply_ibctr
#' @keywords internal
apply_ibndr_annual <- function(database, annual_db,
                               catalogue = series_catalogue()) {
  if (!is.null(database[["IBNDR"]])) return(database)
  required <- c("CFCTOT", "CFCID", "CFCOTC", "CFCIBRE",
                "KTOT", "KID", "KOTC", "KIBRE")
  for (v in required) {
    if (is.null(annual_db[[v]])) {
      # At least one input missing — fall through to static handler.
      return(database)
    }
  }
  # Align annual series to the smallest common range.
  starts <- sapply(annual_db[required], function(x) stats::tsp(x)[1])
  ends   <- sapply(annual_db[required], function(x) stats::tsp(x)[2])
  start_year <- floor(max(starts) + 1e-9)
  end_year   <- floor(min(ends) + 1e-9)
  if (start_year >= end_year) return(database)

  align_annual <- function(x) {
    tsp <- stats::tsp(x); s <- floor(tsp[1] + 1e-9)
    lo <- start_year - s + 1L
    hi <- end_year   - s + 1L
    as.numeric(x)[lo:hi]
  }
  cfctot  <- align_annual(annual_db$CFCTOT)
  cfcid   <- align_annual(annual_db$CFCID)
  cfcotc  <- align_annual(annual_db$CFCOTC)
  cfcibre <- align_annual(annual_db$CFCIBRE)
  ktot    <- align_annual(annual_db$KTOT)
  kid     <- align_annual(annual_db$KID)
  kotc    <- align_annual(annual_db$KOTC)
  kibre   <- align_annual(annual_db$KIBRE)

  cfcibn <- cfctot - cfcid - cfcotc - cfcibre
  kibn   <- ktot   - kid   - kotc   - kibre

  # Annual depreciation rate using lag-1 (previous year's stock).
  # Year-1 entry has no lag, so it's NA.
  n_ann <- length(cfcibn)
  ibndra_ann <- rep(NA_real_, n_ann)
  for (i in seq.int(2L, n_ann)) {
    if (!is.na(kibn[i - 1L]) && kibn[i - 1L] > 0 && !is.na(cfcibn[i])) {
      ibndra_ann[i] <- 100 * cfcibn[i] / kibn[i - 1L]
    }
  }
  # Annual rate to quarterly compounding rate.
  ibndr_qrate_ann <- ((1 + ibndra_ann / 100) ^ (1 / 4) - 1) * 100

  # Interpolate annual rates to quarterly grid. Each annual value applies
  # to its fiscal-year-end (typically Q2). We place the value at Q2 of
  # each year and linearly interpolate between, then backcast and
  # forward-fill.
  qspan <- database_span(database)
  qn <- qspan$n_quarters
  qy0 <- qspan$start_year
  qq0 <- qspan$start_quarter

  # Annual anchor positions: year y maps to quarter index (y - qy0)*4 + 2
  # (interpret as Q2 of year y), with adjustment for the database's
  # starting offset.
  ibndr_q <- rep(NA_real_, qn)
  ann_years <- seq(start_year, end_year)
  for (i in seq_along(ann_years)) {
    yr <- ann_years[i]
    # Quarter index in database grid for Q2 of yr:
    idx <- (yr - qy0) * 4L + (2L - qq0) + 1L
    if (idx >= 1L && idx <= qn && !is.na(ibndr_qrate_ann[i])) {
      ibndr_q[idx] <- ibndr_qrate_ann[i]
    }
  }
  # Linear interpolation between non-NA anchors.
  nonna_pos <- which(!is.na(ibndr_q))
  if (length(nonna_pos) >= 2L) {
    for (k in seq_len(length(nonna_pos) - 1L)) {
      lo <- nonna_pos[k]
      hi <- nonna_pos[k + 1L]
      if (hi - lo > 1L) {
        ibndr_q[(lo + 1L):(hi - 1L)] <- seq(
          ibndr_q[lo], ibndr_q[hi],
          length.out = hi - lo + 1L
        )[-c(1, hi - lo + 1L)]
      }
    }
  }
  if (length(nonna_pos) >= 1L) {
    # Backcast: carry first non-NA value backward.
    first <- nonna_pos[1]
    if (first > 1L) ibndr_q[seq_len(first - 1L)] <- ibndr_q[first]
    # Forward-fill: carry last non-NA value forward.
    last <- nonna_pos[length(nonna_pos)]
    if (last < qn) ibndr_q[(last + 1L):qn] <- ibndr_q[last]
  }

  if (all(is.na(ibndr_q))) return(database)  # fell through

  database[["IBNDR"]] <- bimets::TIMESERIES(
    ibndr_q, START = c(qy0, qq0), FREQ = 4
  )
  database
}
