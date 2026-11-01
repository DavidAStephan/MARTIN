#' CES production-function calibration and labour-augmenting efficiency trend
#'
#' Implements the supply-side primitives for the `output_gap` MARTIN feature
#' (see `docs/martin_enhancements_plan.md`, Workstream A): a CES value-added
#' function in capital and efficiency-augmented labour, used the EMMA way
#' (inverted for employment). With the elasticity of substitution fixed at
#' `sigma = 0.5` the CES collapses to the harmonic form
#'
#'   Y = gamma / ( theta_n/(EFF * LHPP * LE) + theta_k / KSTAR )
#'
#' where `KSTAR = KIBN + KIBRE`, `LE` is employment, `LHPP` hours per worker,
#' and `EFF` the labour-augmenting efficiency trend. `theta_k` is the
#' Australian capital share; `gamma` is the scale, calibrated by normalising
#' `EFF = 1` at a base period.
#'
#' @name production
NULL

# Pull a database series (bimets TIMESERIES or ts) as a plain numeric vector
# aligned to a common time index with the other series. Returns a list of
# aligned numeric vectors plus the shared start/length.
.align_series <- function(db, names) {
  ts_list <- lapply(names, function(nm) {
    x <- db[[nm]]
    if (is.null(x)) stop("series '", nm, "' not in database", call. = FALSE)
    stats::as.ts(x)
  })
  # Intersect on overlapping window.
  starts <- vapply(ts_list, function(x) stats::tsp(x)[1], numeric(1))
  ends   <- vapply(ts_list, function(x) stats::tsp(x)[2], numeric(1))
  lo <- max(starts); hi <- min(ends)
  win <- lapply(ts_list, function(x) stats::window(x, start = lo, end = hi))
  mat <- do.call(cbind, lapply(win, as.numeric))
  colnames(mat) <- names
  sy <- floor(lo + 1e-9); sq <- round((lo - sy) * 4 + 1)
  list(mat = mat, start = c(sy, sq), n = nrow(mat))
}

#' Calibrate the CES production block
#'
#' @param db A MARTIN database (named list of bimets TIMESERIES) containing
#'   `Y`, `KIBN`, `KIBRE`, `LE`, `LHPP`.
#' @param sigma Elasticity of substitution (default 0.5 — the harmonic form).
#' @param theta_k Capital share. Default 0.38 (the Australian capital share;
#'   the review explicitly cautions against importing France's 0.21).
#' @param base Length-2 character `c("yyyyQq","yyyyQq")` base window over which
#'   `EFF` is normalised to 1 and `gamma` is calibrated.
#' @return A list `list(sigma, theta_k, theta_n, gamma)`.
#' @export
ces_calibration <- function(db, sigma = 0.5, theta_k = 0.38,
                            base = c("2017Q1", "2019Q3")) {
  if (abs(sigma - 0.5) > 1e-9) {
    stop("ces_calibration: only sigma = 0.5 (harmonic form) is implemented; ",
         "a general-sigma version would need power terms in the identities.",
         call. = FALSE)
  }
  a <- .align_series(db, c("Y", "KIBN", "KIBRE", "LE", "LHPP"))
  m <- a$mat
  kstar <- m[, "KIBN"] + m[, "KIBRE"]
  leff  <- m[, "LHPP"] * m[, "LE"]               # effective labour with EFF = 1
  theta_n <- 1 - theta_k

  # base-window index
  dates <- a$start[1] + (a$start[2] - 1) / 4 + (seq_len(a$n) - 1) / 4
  b0 <- .yq_to_dec(base[1]); b1 <- .yq_to_dec(base[2])
  inb <- dates >= b0 - 1e-9 & dates <= b1 + 1e-9
  if (!any(inb)) stop("ces_calibration: base window not in data span",
                      call. = FALSE)

  # gamma from the harmonic CES with EFF = 1 at the base window (averaged).
  gamma_t <- m[, "Y"] * (theta_n / leff + theta_k / kstar)
  gamma <- mean(gamma_t[inb], na.rm = TRUE)

  list(sigma = sigma, theta_k = theta_k, theta_n = theta_n, gamma = gamma)
}

#' Fit the labour-augmenting efficiency trend EFF
#'
#' Inverts the CES for the efficiency residual, then extracts a smooth trend
#' (HP filter on logs — the standard, less-structural trend device, matching
#' the EMMA/RBA convention; an LLT Kalman smoother is the more sophisticated
#' alternative noted in the plan).
#'
#' @param db A MARTIN database (named list of bimets TIMESERIES).
#' @param calib Output of [ces_calibration()]; computed from `db` if `NULL`.
#' @param lambda HP smoothing parameter (1600 for quarterly data).
#' @return A bimets TIMESERIES `EFF` aligned to the common Y/K/LE/LHPP window.
#' @export
fit_efficiency_trend <- function(db, calib = NULL, lambda = 1600) {
  if (is.null(calib)) calib <- ces_calibration(db)
  a <- .align_series(db, c("Y", "KIBN", "KIBRE", "LE", "LHPP"))
  m <- a$mat
  kstar <- m[, "KIBN"] + m[, "KIBRE"]
  leff  <- m[, "LHPP"] * m[, "LE"]

  # Invert harmonic CES for EFF:  EFF = theta_n / ((gamma/Y - theta_k/KSTAR) * LHPP * LE)
  denom <- calib$gamma / m[, "Y"] - calib$theta_k / kstar
  denom[!is.finite(denom) | denom <= 0] <- NA_real_
  eff_raw <- calib$theta_n / (denom * leff)

  eff_trend <- exp(.hp_filter(log(eff_raw), lambda = lambda))
  bimets::TIMESERIES(eff_trend, START = a$start, FREQ = 4)
}

# Hodrick-Prescott trend of the finite stretch of `x` (NA elsewhere).
.hp_filter <- function(x, lambda = 1600) {
  x <- as.numeric(x)
  n <- length(x)
  ok <- is.finite(x)
  if (sum(ok) < 5L) return(x)
  idx <- which(ok)
  # require a contiguous finite block for the second-difference operator
  idx <- seq(min(idx), max(idx))
  xi <- x[idx]
  if (anyNA(xi)) xi <- stats::approx(seq_along(xi), xi, seq_along(xi))$y
  m <- length(xi)
  D <- diff(diag(m), differences = 2)
  trend_i <- solve(diag(m) + lambda * crossprod(D), xi)
  out <- rep(NA_real_, n)
  out[idx] <- trend_i
  out
}

.yq_to_dec <- function(q) {
  y <- as.integer(substr(q, 1, 4))
  qq <- as.integer(substr(q, 6, 6))
  y + (qq - 1) / 4
}
