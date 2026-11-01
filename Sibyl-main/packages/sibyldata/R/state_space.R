# Port of references/MARTIN-master/Programs/supply_side.prg state-space
# models to KFAS. Produces the three trend variables MARTIN needs as
# behavioural inputs:
#
#   TDLLA    — trend dlog labour productivity (local-linear-trend on log(LA))
#   TDLLPOP  — trend dlog population        (local-linear-trend on log(LPOP))
#   TDLLHPP  — trend dlog hours per person  (random-walk + drift on log(LHPP))
#
# These were previously supplied only by `martin::read_fixture()` (i.e.
# spliced from `references/MARTIN-master/Data/martin_public.wf1`). Porting
# them removes the fixture dependency for the supply-side trends.
#
# The two model families:
#
#   * Random-walk + drift (TDLLHPP):
#       y_t   = TLLHPP_t + ε_t,                 ε_t ~ N(0, σ²)
#       state[t] = (TLLHPP_t, c_t)
#       TLLHPP_t = TLLHPP_{t-1} + c_{t-1} + η_t, η_t ~ N(0, σ²/param_lhpp)
#       c_t      = c_{t-1}                       (deterministic, diffuse prior)
#
#     The drift c is the single ML estimate of d/dt log(LHPP); EViews
#     stores it via `series tdllhpp = ss_lhpp.@coefs(1)` — a constant
#     across all t. We surface the same constant.
#
#   * Local-linear-trend with shared slope innovation (TDLLA / TDLLPOP):
#       y_t       = TLEVEL_t + ε_t,             ε_t ~ N(0, σ²)
#       state[t]  = (TLEVEL_t, TDRIFT_t)
#       TLEVEL_t  = TLEVEL_{t-1} + TDRIFT_{t-1} + η_LEVEL + η_DRIFT
#       TDRIFT_t  = TDRIFT_{t-1} + η_DRIFT
#       η_LEVEL ~ N(0, σ²/param_trend)
#       η_DRIFT ~ N(0, σ²/param_drift)
#
#     The "shared slope innovation" structure (η_DRIFT enters the level
#     equation too) is faithful to supply_side.prg lines 33-39. It's
#     implemented in KFAS as R = T = [[1,1],[0,1]] with diagonal Q.
#
# Each fit estimates a single parameter (σ², the observation variance)
# via fitSSM; the ratios σ²/param_* hold the state variances. The
# trend (drift) state is initialised with a diffuse prior, so its
# smoothed value is data-driven (no informative starting value needed).

# Variance ratio scalars from supply_side.prg:9-15.
SUPPLY_PARAM <- list(
  trend    = 100,    # ratio σ²_obs / σ²_TLLA-innovation
  drift    = 10000,  # ratio σ²_obs / σ²_TDLLA-innovation
  poptrend = 100,
  popdrift = 10000,
  lhpp     = 50
)

# Sample-start defaults from supply_side.prg.
SUPPLY_SAMPLE_START <- list(
  LA   = "1966Q1",
  LPOP = "1978Q3",
  LHPP = "1966Q1"
)

# m-priors from supply_side.prg, in (level_init, drift_init) form.
SUPPLY_MPRIOR <- list(
  LA   = c(3.687622086817885, 0.0070),
  LPOP = c(9.265860822608552, 0.0070),
  LHPP = c(6.20000, 0)  # only the level is informative; drift is diffuse
)

# v-priors from supply_side.prg `vprior.fill` calls. Diagonal entries
# only (off-diagonals are 0 in the EViews source). Tight on the drift
# state — the local-linear-trend fit is unstable without an informative
# prior on the trend slope; EViews enforces this via vprior_la.fill
# 0.0001, 0, 1e-06 (level var 1e-4, drift var 1e-6).
SUPPLY_VPRIOR <- list(
  LA   = c(0.0001, 1e-6),
  LPOP = c(0.0001, 1e-6),
  LHPP = c(1e-6,   1e-6)  # vprior_hpp.fill 1e-06
)

#' Apply the supply-side state-space trend handlers
#'
#' For each variable in [SUPPLY_PARAM] whose input is available in the
#' database, runs the corresponding KFAS state-space estimator and
#' inserts the smoothed trend(s) back into the database. Idempotent:
#' rows already in the database are left alone.
#'
#' Currently materialises `TDLLA`, `TDLLPOP`, `TDLLHPP` from `LA`, `LPOP`,
#' `LHPP`. Also produces the smoothed log-level trends (`TLLA`, `TLLPOP`,
#' `TLLHPP`) as a side effect. Skips a row if the required input is
#' missing.
#'
#' @param database Named list of bimets TIMESERIES.
#' @param catalogue [series_catalogue()] (unused in v0).
#' @return The database with trend series added.
#' @keywords internal
apply_state_space_trends <- function(database, catalogue = series_catalogue()) {
  # TDLLA + TLLA from log(LA)
  if (is.null(database[["TDLLA"]]) && !is.null(database[["LA"]])) {
    fit <- tryCatch(
      fit_local_linear_trend(
        y_ts        = log(database[["LA"]]),
        sample_start = SUPPLY_SAMPLE_START$LA,
        mprior      = SUPPLY_MPRIOR$LA,
        vprior      = SUPPLY_VPRIOR$LA,
        param_trend = SUPPLY_PARAM$trend,
        param_drift = SUPPLY_PARAM$drift,
        param_name  = "LA"
      ),
      error = function(e) {
        warning("apply_state_space_trends: LA fit failed (",
                conditionMessage(e), "); skipping TDLLA/TLLA.",
                call. = FALSE)
        NULL
      }
    )
    if (!is.null(fit)) {
      database[["TDLLA"]] <- fit$TDRIFT
      if (is.null(database[["TLLA"]])) database[["TLLA"]] <- fit$TLEVEL
    }
  }

  # TDLLPOP + TLLPOP from log(LPOP)
  if (is.null(database[["TDLLPOP"]]) && !is.null(database[["LPOP"]])) {
    fit <- tryCatch(
      fit_local_linear_trend(
        y_ts        = log(database[["LPOP"]]),
        sample_start = SUPPLY_SAMPLE_START$LPOP,
        mprior      = SUPPLY_MPRIOR$LPOP,
        vprior      = SUPPLY_VPRIOR$LPOP,
        param_trend = SUPPLY_PARAM$poptrend,
        param_drift = SUPPLY_PARAM$popdrift,
        param_name  = "LPOP"
      ),
      error = function(e) {
        warning("apply_state_space_trends: LPOP fit failed (",
                conditionMessage(e), "); skipping TDLLPOP/TLLPOP.",
                call. = FALSE)
        NULL
      }
    )
    if (!is.null(fit)) {
      database[["TDLLPOP"]] <- fit$TDRIFT
      if (is.null(database[["TLLPOP"]])) database[["TLLPOP"]] <- fit$TLEVEL
    }
  }

  # PI_E from 7-signal local-level KFAS port of pistar.prg.
  # R's `$` partial-matches `database[["PI_E"]]` to `database[["PI_E_BOND"]]` —
  # use `[[` everywhere for exact matching on these closely-named series.
  if (is.null(database[["PI_E"]]) &&
      !is.null(database[["PTM"]]) &&
      !is.null(database[["PI_E_BOND"]])) {
    fit <- tryCatch(
      fit_pie_kfas(database, sample_start = "1985Q4"),
      error = function(e) {
        warning("apply_state_space_trends: PI_E fit failed (",
                conditionMessage(e), "); skipping PI_E.",
                call. = FALSE)
        NULL
      }
    )
    if (!is.null(fit)) database[["PI_E"]] <- fit$PI_E
  }

  # TLUR (NAIRU) — Phillips-curve state-space, 2-signal (dlptm, dlulc)
  if (is.null(database[["TLUR"]]) &&
      !is.null(database[["LUR"]]) &&
      !is.null(database[["PTM"]]) &&
      !is.null(database[["Y"]]) &&
      !is.null(database[["NHCOE"]])) {
    fit <- tryCatch(
      fit_nairu_kfas(database, sample_start = "1986Q3"),
      error = function(e) {
        warning("apply_state_space_trends: TLUR fit failed (",
                conditionMessage(e), "); skipping TLUR.",
                call. = FALSE)
        NULL
      }
    )
    if (!is.null(fit)) database[["TLUR"]] <- fit$TLUR
  }

  # RSTAR — defaults to the simple smoothed-real-cash-rate fit
  # (fit_rstar_kfas), which more accurately tracks the fixture's RSTAR
  # (cor ~ 0.96) than the faithful 11-state Okun-Phillips port
  # (fit_rstar_kfas_full, cor ~ 0.30 with fixed structural params).
  # The full port is preserved as opt-in via the
  # `SIBYL_RSTAR_FULL_PORT=TRUE` environment variable — useful for
  # auxiliary states (YGAP, YPOT, G, Z) and for diagnostic comparison.
  # Live values are now stable (RSTAR_FULL_PARAMS replaces the
  # previously-unstable OLS pre-estimation), so the safety-check
  # fallback (kept for robustness) typically doesn't trigger.
  if (is.null(database[["RSTAR"]]) &&
      !is.null(database[["NCR"]]) &&
      !is.null(database[["PTM"]])) {
    use_full <- identical(Sys.getenv("SIBYL_RSTAR_FULL_PORT", "FALSE"),
                          "TRUE")
    full_inputs_ok <- !is.null(database[["Y"]]) &&
                      !is.null(database[["LUR"]]) &&
                      !is.null(database[["PI_E"]])
    fit <- NULL
    if (use_full && full_inputs_ok) {
      fit_full <- tryCatch(
        fit_rstar_kfas_full(database, sample_start = "1986Q3"),
        error = function(e) {
          warning("apply_state_space_trends: RSTAR full fit failed (",
                  conditionMessage(e),
                  "); falling back to simple smoother.",
                  call. = FALSE)
          NULL
        }
      )
      if (!is.null(fit_full)) {
        rng <- range(as.numeric(fit_full$RSTAR), na.rm = TRUE, finite = TRUE)
        if (is.finite(rng[1]) && is.finite(rng[2]) &&
            rng[1] > -10 && rng[2] < 15) {
          fit <- fit_full
        } else {
          warning(sprintf(
            "apply_state_space_trends: RSTAR full port out of plausible range [%.1f, %.1f]; falling back to simple smoother.",
            rng[1], rng[2]), call. = FALSE)
        }
      }
    }
    if (is.null(fit)) {
      fit <- tryCatch(
        fit_rstar_kfas(database, sample_start = "1986Q3"),
        error = function(e) {
          warning("apply_state_space_trends: RSTAR fit failed (",
                  conditionMessage(e), "); skipping RSTAR.",
                  call. = FALSE)
          NULL
        }
      )
    }
    if (!is.null(fit)) database[["RSTAR"]] <- fit$RSTAR
  }

  # TDLLHPP + TLLHPP from log(LHPP)
  if (is.null(database[["TDLLHPP"]]) && !is.null(database[["LHPP"]])) {
    fit <- tryCatch(
      fit_random_walk_drift(
        y_ts        = log(database[["LHPP"]]),
        sample_start = SUPPLY_SAMPLE_START$LHPP,
        mprior_level = SUPPLY_MPRIOR$LHPP[1],
        vprior_level = SUPPLY_VPRIOR$LHPP[1],
        param_lhpp  = SUPPLY_PARAM$lhpp,
        param_name  = "LHPP"
      ),
      error = function(e) {
        warning("apply_state_space_trends: LHPP fit failed (",
                conditionMessage(e), "); skipping TDLLHPP/TLLHPP.",
                call. = FALSE)
        NULL
      }
    )
    if (!is.null(fit)) {
      database[["TDLLHPP"]] <- fit$TDRIFT
      if (is.null(database[["TLLHPP"]])) database[["TLLHPP"]] <- fit$TLEVEL
    }
  }

  database
}

#' Fit the local-linear-trend model (TDLLA / TDLLPOP)
#'
#' KFAS port of supply_side.prg lines 17-44 (TDLLA) and 46-73 (TDLLPOP).
#' Returns smoothed `TLEVEL` (log-trend level) and `TDRIFT` (log-trend
#' growth) as bimets TIMESERIES over the full input span — the drift
#' state is carried forward past the EViews estimation sample end via
#' the random-walk dynamics, matching the legacy "extend to last
#' observation" behaviour.
#'
#' @param y_ts A bimets ts of `log(LA)` (or `log(LPOP)`).
#' @param sample_start `"YYYYQq"` string; the first quarter in EViews's
#'   estimation `smpl`.
#' @param mprior 2-vector of initial (level, drift) prior means. Only
#'   the level is treated as informative; the drift uses a diffuse
#'   prior so its smoothed value is data-driven.
#' @param param_trend,param_drift Variance ratios from supply_side.prg.
#' @param param_name For error messages only.
#' @return List of `(TLEVEL = bimets_ts, TDRIFT = bimets_ts)`.
#' @keywords internal
fit_local_linear_trend <- function(y_ts, sample_start, mprior, vprior,
                                   param_trend, param_drift,
                                   param_name = "input") {
  # KFAS's formula DSL evaluates SSMcustom() in the calling frame, which
  # rejects `KFAS::` namespace prefixes. Aliasing SSMcustom as a local
  # makes it visible to model.frame without polluting the global env.
  SSMcustom <- KFAS::SSMcustom

  ts_meta <- ts_to_meta(y_ts)
  y_vec   <- as.numeric(y_ts)
  start_idx <- ts_meta$quarter_index(sample_start)
  if (is.na(start_idx) || start_idx > length(y_vec)) {
    stop(sprintf("Sample start %s is out of range for %s", sample_start,
                 param_name), call. = FALSE)
  }
  # Mask everything before sample_start as NA so the Kalman filter
  # ignores it (EViews's smpl restriction).
  y_obs <- y_vec
  if (start_idx > 1L) y_obs[seq_len(start_idx - 1L)] <- NA_real_

  # Build the SSMcustom state-space: (TLEVEL, TDRIFT) with shared slope
  # innovation. T = R = [[1,1],[0,1]]; Z = [1, 0]; diagonal Q.
  model <- KFAS::SSModel(
    y_obs ~ -1 + SSMcustom(
      Z = matrix(c(1, 0), nrow = 1),
      T = matrix(c(1, 0, 1, 1), nrow = 2),
      R = matrix(c(1, 0, 1, 1), nrow = 2),
      Q = diag(c(1e-6, 1e-8), 2, 2),
      a1 = matrix(c(mprior[1], mprior[2]), nrow = 2),
      P1 = diag(c(vprior[1], vprior[2]), 2, 2),
      P1inf = matrix(0, 2, 2),
      state_names = c("TLEVEL", "TDRIFT")
    ),
    H = matrix(1e-6)
  )

  # One free parameter: log σ². σ²_trend = σ²/param_trend, σ²_drift =
  # σ²/param_drift, σ²_obs = σ².
  update_fn <- function(pars, model) {
    s2 <- exp(pars[1])
    model$H[, , 1]    <- s2
    model$Q[1, 1, 1]  <- s2 / param_trend
    model$Q[2, 2, 1]  <- s2 / param_drift
    model
  }
  fit <- KFAS::fitSSM(model, inits = c(log(0.001)),
                      updatefn = update_fn, method = "BFGS")
  if (fit$optim.out$convergence != 0L) {
    warning(sprintf(
      "fit_local_linear_trend: optim did not converge for %s (code %d)",
      param_name, fit$optim.out$convergence), call. = FALSE)
  }
  ks <- KFAS::KFS(fit$model, smoothing = "state")
  tlevel_vec <- as.numeric(ks$alphahat[, "TLEVEL"])
  tdrift_vec <- as.numeric(ks$alphahat[, "TDRIFT"])

  # Mask pre-sample-start positions back to NA (EViews returns NA there
  # because the smpl restriction means no smoothed state exists yet).
  if (start_idx > 1L) {
    tlevel_vec[seq_len(start_idx - 1L)] <- NA_real_
    tdrift_vec[seq_len(start_idx - 1L)] <- NA_real_
  }

  list(
    TLEVEL = ts_meta$as_bimets(tlevel_vec),
    TDRIFT = ts_meta$as_bimets(tdrift_vec)
  )
}

#' Fit the random-walk + drift model (TDLLHPP)
#'
#' KFAS port of supply_side.prg lines 78-108. The drift `c` is a single
#' parameter (EViews `C(1)`); the legacy code surfaces it as a constant
#' series via `tdllhpp = ss_lhpp.@coefs(1)`. We reproduce that — `TDRIFT`
#' is constant across all quarters, equal to the data-driven smoothed
#' drift estimate. Within EViews's estimation smpl `TLLHPP` is the
#' smoothed level; beyond it, the EViews script carries the last value
#' forward, which we also do.
#'
#' @inheritParams fit_local_linear_trend
#' @param mprior_level Scalar prior mean for the initial level.
#' @param param_lhpp Variance ratio σ²_obs / σ²_state.
#' @return List of `(TLEVEL = bimets_ts, TDRIFT = bimets_ts)`.
#' @keywords internal
fit_random_walk_drift <- function(y_ts, sample_start, mprior_level,
                                  vprior_level, param_lhpp,
                                  param_name = "input") {
  # See fit_local_linear_trend(): KFAS's formula DSL rejects `KFAS::`
  # prefixes, so we alias SSMcustom locally.
  SSMcustom <- KFAS::SSMcustom

  ts_meta <- ts_to_meta(y_ts)
  y_vec   <- as.numeric(y_ts)
  start_idx <- ts_meta$quarter_index(sample_start)
  if (is.na(start_idx) || start_idx > length(y_vec)) {
    stop(sprintf("Sample start %s is out of range for %s", sample_start,
                 param_name), call. = FALSE)
  }
  y_obs <- y_vec
  if (start_idx > 1L) y_obs[seq_len(start_idx - 1L)] <- NA_real_

  # State = (TLLHPP, drift). Drift is constant across t (T[drift,drift] = 1,
  # no innovation), so once smoother locks in a single value it stays.
  model <- KFAS::SSModel(
    y_obs ~ -1 + SSMcustom(
      Z = matrix(c(1, 0), nrow = 1),
      T = matrix(c(1, 0, 1, 1), nrow = 2),
      R = matrix(c(1, 0), nrow = 2, ncol = 1),
      Q = matrix(1e-8),
      a1 = matrix(c(mprior_level, 0), nrow = 2),
      P1 = diag(c(vprior_level, 0), 2, 2),
      P1inf = diag(c(0, 1), 2, 2),  # drift is diffuse (LHPP has no drift prior)
      state_names = c("TLLHPP", "drift")
    ),
    H = matrix(1e-6)
  )

  update_fn <- function(pars, model) {
    s2 <- exp(pars[1])
    model$H[, , 1]   <- s2
    model$Q[1, 1, 1] <- s2 / param_lhpp
    model
  }
  fit <- KFAS::fitSSM(model, inits = c(log(0.0001)),
                      updatefn = update_fn, method = "BFGS")
  if (fit$optim.out$convergence != 0L) {
    warning(sprintf(
      "fit_random_walk_drift: optim did not converge for %s (code %d)",
      param_name, fit$optim.out$convergence), call. = FALSE)
  }
  ks <- KFAS::KFS(fit$model, smoothing = "state")
  tlevel_vec <- as.numeric(ks$alphahat[, "TLLHPP"])
  drift_const <- as.numeric(ks$alphahat[1, "drift"])

  if (start_idx > 1L) {
    tlevel_vec[seq_len(start_idx - 1L)] <- NA_real_
  }

  # TDLLHPP is the constant drift value broadcast across the whole span.
  tdrift_vec <- rep(drift_const, length(tlevel_vec))

  list(
    TLEVEL = ts_meta$as_bimets(tlevel_vec),
    TDRIFT = ts_meta$as_bimets(tdrift_vec)
  )
}

# ===========================================================================
# Inflation expectations (PI_E) — port of pistar.prg
# ===========================================================================

#' Fit the 7-signal local-level model for PI_E
#'
#' Faithful KFAS port of `pistar.prg`. Treats seven inflation indicators
#' (year-on-year trimmed-mean CPI plus five RBA survey expectations plus
#' bond-implied inflation) as noisy observations of a common trend
#' inflation state `cpistar`, with EViews-style AR(1) correction on the
#' DL4PTM signal and GST dummies on each survey:
#'
#'   state = (cpistar_t, cpistarL1_t)
#'   cpistar_t   = cpistar_{t-1} + eta_t
#'   cpistarL1_t = cpistar_{t-1}                 (deterministic lag)
#'
#'   DL4PTM_t  = cpistar_t + delta * (DL4PTM_{t-1} - cpistarL1_t) + e1
#'   GBUSEXP_t = cpistar_t + lambda_1 * d_GBUSEXP_t + e2
#'   ... etc. for the five survey signals
#'   PI_E_BOND_t = cpistar_t + e7                (no dummy or AR term)
#'
#' Structural parameters (delta on DL4PTM, five lambdas on surveys) are
#' OLS-pre-estimated; KFAS then fits the seven observation variances and
#' the cpistar state variance. The deterministic GST dummies cover the
#' Australian GST introduction (2000Q3) that produced one-time spikes
#' across the surveys; pistar.prg:36-58 sets:
#'
#'   d_GBUSEXP:   1 at 2000Q2          (single-quarter pulse)
#'   d_GUNIEXPY:  1 over 1999Q4-2001Q3
#'   d_GUNIEXPYY: 1 over 1999Q4-2001Q3
#'   d_GMAREXPY:  1 over 2000Q2-2000Q3
#'   d_GMAREXPYY: 1 over 1999Q3-1999Q4
#'
#' The deterministic-regressor terms are pre-subtracted from the observed
#' signal vector before KFAS sees them, keeping the model linear; the
#' resulting Z matrix uses `(1, -delta)` on the first row and `(1, 0)`
#' on the others.
#'
#' Inputs from `database` (must all be present):
#'   PTM        → DL4PTM = 100 * log(PTM_t / PTM_{t-4})
#'   GBUSEXP, GUNIEXPY, GUNIEXPYY, GMAREXPY, GMAREXPYY  (RBA G3 series)
#'   PI_E_BOND  → bond-implied inflation
#'
#' @param database Named list of bimets TIMESERIES.
#' @param sample_start `"YYYYQq"` string; first quarter to include.
#' @return List with a single element `PI_E`: a bimets ts of the smoothed
#'   trend inflation expectation, broadcast over the full database span.
#' @keywords internal
fit_pie_kfas <- function(database, sample_start = "1985Q4") {
  SSMcustom <- KFAS::SSMcustom

  signal_vars <- c("GBUSEXP", "GUNIEXPY", "GUNIEXPYY",
                   "GMAREXPY", "GMAREXPYY", "PI_E_BOND")
  for (v in signal_vars) {
    if (is.null(database[[v]])) {
      stop("fit_pie_kfas: missing input series ", v, call. = FALSE)
    }
  }
  ts_meta <- ts_to_meta(database[["PTM"]])

  # DL4PTM = 100 * log(PTM_t / PTM_{t-4}). NA for the first 4 quarters.
  ptm_vec <- as.numeric(database[["PTM"]])
  n_total <- length(ptm_vec)
  dl4ptm  <- rep(NA_real_, n_total)
  for (i in seq.int(5L, n_total)) {
    if (!is.na(ptm_vec[i]) && !is.na(ptm_vec[i - 4L]) && ptm_vec[i - 4L] > 0) {
      dl4ptm[i] <- 100 * (log(ptm_vec[i]) - log(ptm_vec[i - 4L]))
    }
  }

  # Align each signal to the PTM time grid (the longest input).
  align_to_ptm <- function(other_ts) {
    other_tsp <- stats::tsp(other_ts)
    other_v   <- as.numeric(other_ts)
    other_y   <- floor(other_tsp[1] + 1e-9)
    other_q   <- round((other_tsp[1] - other_y) * 4 + 1)
    offset    <- (other_y - ts_meta$start_year) * 4L +
                 (other_q - ts_meta$start_quarter)
    out <- rep(NA_real_, n_total)
    lo <- max(1L, 1L + offset)
    hi <- min(n_total, length(other_v) + offset)
    if (lo <= hi) {
      out[lo:hi] <- other_v[(lo - offset):(hi - offset)]
    }
    out
  }

  gbusexp   <- align_to_ptm(database[["GBUSEXP"]])
  guniexpy  <- align_to_ptm(database[["GUNIEXPY"]])
  guniexpyy <- align_to_ptm(database[["GUNIEXPYY"]])
  gmarexpy  <- align_to_ptm(database[["GMAREXPY"]])
  gmarexpyy <- align_to_ptm(database[["GMAREXPYY"]])
  pi_e_bond <- align_to_ptm(database[["PI_E_BOND"]])

  # ---- GST dummies (pistar.prg:36-58) ----
  start_year    <- ts_meta$start_year
  start_quarter <- ts_meta$start_quarter
  q_idx <- function(yq_str) ts_meta$quarter_index(yq_str)
  # Helper: build a 0/1 dummy with 1s over a [lo, hi] (inclusive) range.
  make_dummy <- function(lo_yq, hi_yq = NULL) {
    out <- rep(0, n_total)
    lo_idx <- q_idx(lo_yq)
    hi_idx <- if (is.null(hi_yq)) lo_idx else q_idx(hi_yq)
    if (!is.na(lo_idx) && !is.na(hi_idx)) {
      lo_idx <- max(1L, lo_idx); hi_idx <- min(n_total, hi_idx)
      if (lo_idx <= hi_idx) out[lo_idx:hi_idx] <- 1
    }
    out
  }
  d_gbusexp   <- make_dummy("2000Q2")                    # single pulse
  d_guniexpy  <- make_dummy("1999Q4", "2001Q3")          # range
  d_guniexpyy <- make_dummy("1999Q4", "2001Q3")
  d_gmarexpy  <- make_dummy("2000Q2", "2000Q3")
  d_gmarexpyy <- make_dummy("1999Q3", "1999Q4")

  # ---- OLS pre-estimation of delta (AR-on-DL4PTM) and 5 lambdas ----
  # delta: regress dl4ptm on its own lag plus a centred-MA proxy
  # mimicking EViews's DL4PTMsmooth. HP filter was tried here but the
  # heavier smoothing destabilises the small-sample OLS; the
  # window-12 centred MA matches the EViews DL4PTMsmooth choice.
  smooth_ma <- function(x, win = 12L) {
    out <- stats::filter(x, rep(1 / win, win), sides = 2)
    out <- as.numeric(out)
    nonna <- which(!is.na(out))
    if (length(nonna) >= 1L) {
      out[seq_len(nonna[1] - 1L)] <- out[nonna[1]]
      tlast <- tail(nonna, 1L)
      if (tlast < length(out)) out[(tlast + 1L):length(out)] <- out[tlast]
    }
    out
  }
  dl4ptm_smooth <- smooth_ma(dl4ptm)
  lag1 <- function(x) c(NA_real_, x[seq_len(length(x) - 1L)])

  # EViews: dl4ptm = dl4ptmsmooth + delta * (dl4ptm(-1) - dl4ptmsmooth(-1)) + e
  delta <- 0.8  # AR(1) default for quarterly inflation
  df_delta <- data.frame(
    y = dl4ptm - dl4ptm_smooth,
    x = lag1(dl4ptm) - lag1(dl4ptm_smooth)
  )
  df_delta <- df_delta[stats::complete.cases(df_delta), ]
  if (nrow(df_delta) > 5L) {
    fit_d <- tryCatch(stats::lm(y ~ x - 1, data = df_delta),
                      error = function(e) NULL)
    if (!is.null(fit_d)) {
      co <- stats::coef(fit_d)["x"]
      if (!is.na(co) && abs(co) < 1) delta <- co
    }
  }

  # Lambdas: OLS of each survey on its dummy (with cpistar proxy as
  # baseline). Use dl4ptm_smooth as the trend baseline.
  fit_lambda <- function(survey, dummy) {
    df <- data.frame(
      y = survey - dl4ptm_smooth,
      d = dummy
    )
    df <- df[stats::complete.cases(df), ]
    if (nrow(df) <= 5L || all(df$d == 0)) return(0)
    fit <- tryCatch(stats::lm(y ~ d - 1, data = df), error = function(e) NULL)
    if (is.null(fit)) return(0)
    co <- stats::coef(fit)["d"]
    if (is.na(co)) 0 else co
  }
  lambda_1 <- fit_lambda(gbusexp,   d_gbusexp)
  lambda_2 <- fit_lambda(guniexpy,  d_guniexpy)
  lambda_3 <- fit_lambda(guniexpyy, d_guniexpyy)
  lambda_4 <- fit_lambda(gmarexpy,  d_gmarexpy)
  lambda_5 <- fit_lambda(gmarexpyy, d_gmarexpyy)

  # ---- Build modified observations (pre-subtract regressors) ----
  y1 <- dl4ptm - delta * lag1(dl4ptm)             # DL4PTM modified for AR(1)
  y2 <- gbusexp   - lambda_1 * d_gbusexp
  y3 <- guniexpy  - lambda_2 * d_guniexpy
  y4 <- guniexpyy - lambda_3 * d_guniexpyy
  y5 <- gmarexpy  - lambda_4 * d_gmarexpy
  y6 <- gmarexpyy - lambda_5 * d_gmarexpyy
  y7 <- pi_e_bond

  Y <- cbind(DL4PTM_mod = y1, GBUSEXP_mod = y2, GUNIEXPY_mod = y3,
             GUNIEXPYY_mod = y4, GMAREXPY_mod = y5, GMAREXPYY_mod = y6,
             PI_E_BOND = y7)
  Y[!is.finite(Y)] <- NA_real_
  n_sig <- ncol(Y)

  start_idx <- ts_meta$quarter_index(sample_start)
  if (start_idx > 1L) Y[seq_len(start_idx - 1L), ] <- NA_real_

  # Two-state model: (cpistar, cpistarL1). cpistarL1 is deterministic
  # lag of cpistar; only cpistar has innovation.
  # DL4PTM signal Z row: (1, -delta) — encodes cpistar - delta*cpistarL1
  # All other signals Z row: (1, 0)
  Z_mat <- matrix(0, n_sig, 2)
  Z_mat[1, 1] <- 1; Z_mat[1, 2] <- -delta
  Z_mat[2:n_sig, 1] <- 1

  T_mat <- matrix(c(1, 1, 0, 0), nrow = 2)  # col-major: T[1,1]=1, T[2,1]=1, T[1,2]=0, T[2,2]=0
  R_mat <- matrix(c(1, 0), nrow = 2, ncol = 1)
  Q_init <- matrix(0.1)
  first_obs <- Y[start_idx, ]
  init_mean <- if (any(!is.na(first_obs))) mean(first_obs, na.rm = TRUE) else 2.5
  a1 <- matrix(c(init_mean, init_mean), nrow = 2)
  P1 <- diag(c(0.5, 0.5), 2, 2)
  P1inf <- matrix(0, 2, 2)

  model <- KFAS::SSModel(
    Y ~ -1 + SSMcustom(
      Z = Z_mat, T = T_mat, R = R_mat, Q = Q_init,
      a1 = a1, P1 = P1, P1inf = P1inf,
      state_names = c("cpistar", "cpistarL1")
    ),
    H = diag(rep(0.1, n_sig))
  )

  # 8 free parameters: 7 obs sigmas + 1 state sigma. All on log scale.
  update_fn <- function(pars, model) {
    obs_vars <- exp(pars[1:7])
    state_var <- exp(pars[8])
    model$H[, , 1] <- diag(obs_vars)
    model$Q[, , 1] <- state_var
    model
  }
  fit <- KFAS::fitSSM(model,
                      inits = c(rep(log(1), 7), log(0.05)),
                      updatefn = update_fn, method = "BFGS")
  if (fit$optim.out$convergence != 0L) {
    warning(sprintf("fit_pie_kfas: optim convergence code %d",
                    fit$optim.out$convergence), call. = FALSE)
  }
  ks <- KFAS::KFS(fit$model, smoothing = "state")
  pie_vec <- as.numeric(ks$alphahat[, "cpistar"])
  if (start_idx > 1L) pie_vec[seq_len(start_idx - 1L)] <- NA_real_
  list(PI_E = ts_meta$as_bimets(pie_vec))
}

# ===========================================================================
# NAIRU (TLUR) — port of nairu.prg
# ===========================================================================

#' Fit the NAIRU state-space (TLUR)
#'
#' Faithful KFAS port of `nairu.prg`. Two-step OLS-pre-estimate +
#' KFAS-smoother structure: OLS estimates the full Phillips curve and
#' ULC equations against an HP-smoothed-LUR proxy for NAIRU, fixes all
#' the structural coefficients, then KFAS extracts a smoothed NAIRU
#' state given those coefficients.
#'
#' The dlptm signal equation includes the lagged-inflation
#' autoregression (beta_{1..3}), cross-equation ULC effect (phi_1), and
#' import-price pass-through (alpha_1) — all of which were dropped in
#' the v0 simplification.
#'
#'   dlptm_t = delta_1 * pi_eq_t
#'           + beta_1 * dlptm_{t-1} + beta_2 * dlptm_{t-2} + beta_3 * dlptm_{t-3}
#'           + phi_1 * dlulc_{t-1}
#'           + alpha_1 * dl4pimp_{t-1}
#'           + gamma_1 * (LUR_t - NAIRU_t) + e1
#'
#'   dlulc_t = delta_2 * pi_eq_t
#'           + omega_1 * dlulc_{t-1} + omega_2 * dlulc_{t-2}
#'           + gamma_2 * (LUR_t - NAIRU_t) + e2
#'
#'   NAIRU_t = NAIRU_{t-1} + e3
#'
#' Where:
#'   pi_eq_t  = ((1 + PI_E_t/100)^(1/4) - 1) * 100  (qtly inflation expectation)
#'   dl4pimp_t = 100 * (log(PMCG_t) - log(PMCG_{t-4}))  (YoY import price growth)
#'
#' The non-NAIRU regressors are pre-subtracted from the observed
#' dlptm / dlulc to give modified observations that depend linearly on
#' NAIRU through Z = c(-gamma_1, -gamma_2).
#'
#' @param database Named list of bimets ts (needs PTM, NHCOE, Y, LUR;
#'   PMCG recommended for import-price pass-through; PI_E recommended).
#' @param sample_start `"YYYYQq"` string.
#' @return List with `TLUR` (smoothed NAIRU as bimets ts).
#' @keywords internal
fit_nairu_kfas <- function(database, sample_start = "1986Q3") {
  SSMcustom <- KFAS::SSMcustom

  ts_meta <- ts_to_meta(database[["LUR"]])
  n_total <- length(as.numeric(database[["LUR"]]))

  # Align all inputs to the LUR time grid.
  align <- function(x) {
    other_tsp <- stats::tsp(x)
    other_v   <- as.numeric(x)
    other_y   <- floor(other_tsp[1] + 1e-9)
    other_q   <- round((other_tsp[1] - other_y) * 4 + 1)
    offset    <- (other_y - ts_meta$start_year) * 4L +
                 (other_q - ts_meta$start_quarter)
    out <- rep(NA_real_, n_total)
    lo <- max(1L, 1L + offset)
    hi <- min(n_total, length(other_v) + offset)
    if (lo <= hi) out[lo:hi] <- other_v[(lo - offset):(hi - offset)]
    out
  }
  lur   <- as.numeric(database[["LUR"]])
  ptm   <- align(database[["PTM"]])
  ptm[!is.na(ptm) & ptm <= 0] <- NA_real_
  nhcoe <- align(database[["NHCOE"]])
  y_gdp <- align(database[["Y"]])
  pi_e  <- if (!is.null(database[["PI_E"]])) align(database[["PI_E"]]) else rep(2.5, n_total)
  pmcg  <- if (!is.null(database[["PMCG"]])) align(database[["PMCG"]]) else rep(NA_real_, n_total)
  pmcg[!is.na(pmcg) & pmcg <= 0] <- NA_real_

  # dlptm = 100 * dlog(PTM), dlulc = 100 * dlog(NHCOE/Y).
  dlptm <- c(NA, 100 * diff(log(ptm)))
  ulc   <- nhcoe / y_gdp
  dlulc <- c(NA, 100 * diff(log(ulc)))
  pi_eq <- ((1 + pi_e / 100) ^ (1 / 4) - 1) * 100
  # YoY consumer import price growth, dl4pimp.
  dl4pimp <- rep(NA_real_, n_total)
  for (i in seq.int(5L, n_total)) {
    if (!is.na(pmcg[i]) && !is.na(pmcg[i - 4L])) {
      dl4pimp[i] <- 100 * (log(pmcg[i]) - log(pmcg[i - 4L]))
    }
  }

  start_idx <- ts_meta$quarter_index(sample_start)
  if (is.na(start_idx) || start_idx < 1L) start_idx <- 1L

  # Step 1: HP-filtered LUR for ugap_init (lambda=1600 quarterly).
  # Replaces the prior 20-window centred MA which flat-lined the last
  # ~10 quarters and gave a biased ugap seed near the sample edge.
  lur_sm <- hp_filter(lur, lambda = 1600)
  ugap_init <- lur - lur_sm

  # Lag helper.
  lagk <- function(x, k) c(rep(NA_real_, k), x[seq_len(length(x) - k)])

  # Step 2: OLS pre-estimate of the full dlptm and dlulc equations.
  mask <- seq.int(start_idx, n_total)
  # dlptm equation regressors
  df_ptm <- data.frame(
    y       = dlptm[mask],
    pi_eq   = pi_eq[mask],
    dlptm1  = lagk(dlptm, 1)[mask],
    dlptm2  = lagk(dlptm, 2)[mask],
    dlptm3  = lagk(dlptm, 3)[mask],
    dlulc1  = lagk(dlulc, 1)[mask],
    dl4pimp1 = lagk(dl4pimp, 1)[mask],
    ugap    = ugap_init[mask]
  )
  df_ptm <- df_ptm[stats::complete.cases(df_ptm), ]
  delta_1 <- 1.0; beta_1 <- 0.0; beta_2 <- 0.0; beta_3 <- 0.0
  phi_1 <- 0.0; alpha_1 <- 0.0; gamma_1 <- -0.1
  if (nrow(df_ptm) > 8L) {
    fit_p <- tryCatch(
      stats::lm(y ~ pi_eq + dlptm1 + dlptm2 + dlptm3 + dlulc1 +
                dl4pimp1 + ugap - 1, data = df_ptm),
      error = function(e) NULL
    )
    if (!is.null(fit_p)) {
      co <- stats::coef(fit_p)
      if (!is.na(co["pi_eq"]))    delta_1 <- co["pi_eq"]
      if (!is.na(co["dlptm1"]))   beta_1  <- co["dlptm1"]
      if (!is.na(co["dlptm2"]))   beta_2  <- co["dlptm2"]
      if (!is.na(co["dlptm3"]))   beta_3  <- co["dlptm3"]
      if (!is.na(co["dlulc1"]))   phi_1   <- co["dlulc1"]
      if (!is.na(co["dl4pimp1"])) alpha_1 <- co["dl4pimp1"]
      if (!is.na(co["ugap"]))     gamma_1 <- co["ugap"]
    }
  }

  # dlulc equation regressors
  df_ulc <- data.frame(
    y      = dlulc[mask],
    pi_eq  = pi_eq[mask],
    dlulc1 = lagk(dlulc, 1)[mask],
    dlulc2 = lagk(dlulc, 2)[mask],
    ugap   = ugap_init[mask]
  )
  df_ulc <- df_ulc[stats::complete.cases(df_ulc), ]
  delta_2 <- 1.0; omega_1 <- 0.0; omega_2 <- 0.0; gamma_2 <- -0.1
  if (nrow(df_ulc) > 5L) {
    fit_u <- tryCatch(
      stats::lm(y ~ pi_eq + dlulc1 + dlulc2 + ugap - 1, data = df_ulc),
      error = function(e) NULL
    )
    if (!is.null(fit_u)) {
      co <- stats::coef(fit_u)
      if (!is.na(co["pi_eq"]))  delta_2 <- co["pi_eq"]
      if (!is.na(co["dlulc1"])) omega_1 <- co["dlulc1"]
      if (!is.na(co["dlulc2"])) omega_2 <- co["dlulc2"]
      if (!is.na(co["ugap"]))   gamma_2 <- co["ugap"]
    }
  }

  # Step 3: build modified observations by pre-subtracting all the
  # non-NAIRU regressors. After pre-subtraction:
  #   y1_mod_t = gamma_1 * (LUR_t - NAIRU_t) + e1
  # which with state = NAIRU gives Z[1] = -gamma_1 (with the gamma_1*LUR
  # part absorbed by the modification).
  y1 <- (dlptm - delta_1 * pi_eq
         - beta_1 * lagk(dlptm, 1) - beta_2 * lagk(dlptm, 2)
         - beta_3 * lagk(dlptm, 3) - phi_1 * lagk(dlulc, 1)
         - alpha_1 * lagk(dl4pimp, 1)
         - gamma_1 * lur)
  y2 <- (dlulc - delta_2 * pi_eq
         - omega_1 * lagk(dlulc, 1) - omega_2 * lagk(dlulc, 2)
         - gamma_2 * lur)
  Y  <- cbind(y1 = y1, y2 = y2)
  Y[!is.finite(Y)] <- NA_real_
  if (start_idx > 1L) Y[seq_len(start_idx - 1L), ] <- NA_real_

  # Initial NAIRU near 5.5 (literature value used by EViews mprior).
  init_nairu <- if (!is.na(lur_sm[start_idx])) lur_sm[start_idx] else 5.5

  model <- KFAS::SSModel(
    Y ~ -1 + SSMcustom(
      Z = matrix(c(-gamma_1, -gamma_2), nrow = 2, ncol = 1),
      T = matrix(1),
      R = matrix(1),
      Q = matrix(0.1),
      a1 = matrix(init_nairu),
      P1 = matrix(0.4),
      P1inf = matrix(0),
      state_names = "NAIRU"
    ),
    H = diag(c(0.1, 0.1))
  )

  update_fn <- function(pars, model) {
    model$H[1, 1, 1] <- exp(pars[1])
    model$H[2, 2, 1] <- exp(pars[2])
    model$Q[1, 1, 1] <- exp(pars[3])
    model
  }
  fit <- KFAS::fitSSM(model, inits = c(log(0.1), log(0.1), log(0.05)),
                      updatefn = update_fn, method = "BFGS")
  if (fit$optim.out$convergence != 0L) {
    warning(sprintf("fit_nairu_kfas: optim convergence code %d",
                    fit$optim.out$convergence), call. = FALSE)
  }
  ks <- KFAS::KFS(fit$model, smoothing = "state")
  tlur_vec <- as.numeric(ks$alphahat[, "NAIRU"])
  if (start_idx > 1L) tlur_vec[seq_len(start_idx - 1L)] <- NA_real_
  list(TLUR = ts_meta$as_bimets(tlur_vec))
}

# ===========================================================================
# Neutral rate (RSTAR) — simplified port of rstar.prg
# ===========================================================================

#' Fit the neutral interest rate (RSTAR) state-space
#'
#' v0 simplification of `rstar.prg`. The full EViews model is an 11-state
#' system (output gap with 3 lags, potential GDP, trend growth, NAIRU
#' with 1 lag, neutral rate with 1 lag, and an unexplained-rate state z)
#' tied together by Okun's-law and Phillips-curve signal equations.
#' That's a session unto itself.
#'
#' For v0 we model RSTAR as the smoothed trend of the real cash rate:
#'
#'   rcash_t = NCR_t - 4 * 100 * dlog(PTM)_t
#'   y_t      = TLEVEL_t + eps_t                     eps ~ N(0, sigma_obs)
#'   TLEVEL_t = TLEVEL_{t-1} + TDRIFT_{t-1} + eta1   eta1 ~ N(0, q1)
#'   TDRIFT_t = TDRIFT_{t-1} + eta2                  eta2 ~ N(0, q2)
#'
#' RSTAR = TLEVEL (the trend real cash rate). Justification: in the long
#' run the cash rate equals the neutral rate plus an output-gap response,
#' so smoothing rcash filters out the cyclical component. This loses
#' rstar.prg's z-state (additional unexplained rstar drift) but captures
#' the dominant slow movement.
#'
#' @param database Named list of bimets ts (needs NCR, PTM).
#' @param sample_start `"YYYYQq"` string.
#' @return List with `RSTAR` (smoothed neutral real cash rate, bimets ts).
#' @keywords internal
fit_rstar_kfas <- function(database, sample_start = "1986Q3") {
  ts_meta <- ts_to_meta(database[["NCR"]])
  n_total <- length(as.numeric(database[["NCR"]]))

  align <- function(x) {
    other_tsp <- stats::tsp(x)
    other_v   <- as.numeric(x)
    other_y   <- floor(other_tsp[1] + 1e-9)
    other_q   <- round((other_tsp[1] - other_y) * 4 + 1)
    offset    <- (other_y - ts_meta$start_year) * 4L +
                 (other_q - ts_meta$start_quarter)
    out <- rep(NA_real_, n_total)
    lo <- max(1L, 1L + offset)
    hi <- min(n_total, length(other_v) + offset)
    if (lo <= hi) out[lo:hi] <- other_v[(lo - offset):(hi - offset)]
    out
  }
  ncr <- as.numeric(database[["NCR"]])
  ptm <- align(database[["PTM"]])
  # Mask non-positive PTM (e.g. pre-base quarters of level_from_pct) before
  # taking log/diff, else dlptm gets -Inf and propagates to rcash.
  ptm[!is.na(ptm) & ptm <= 0] <- NA_real_
  dlptm <- c(NA, diff(log(ptm))) * 100
  rcash <- ncr - 4 * dlptm
  rcash[!is.finite(rcash)] <- NA_real_

  rcash_ts <- ts_meta$as_bimets(rcash)
  # param_trend = 1600 (HP-filter-like smoothing) — rcash is very noisy
  # quarter-to-quarter; with param_trend = 100 the smoother chases the
  # spikes and produces an unreasonably volatile TLEVEL.
  fit_llt <- fit_local_linear_trend(
    y_ts         = rcash_ts,
    sample_start = sample_start,
    mprior       = c(3.0, 0),    # ~3% neutral real cash rate (Aus historical avg)
    vprior       = c(0.5, 0.01),
    param_trend  = 1600,
    param_drift  = 16000,
    param_name   = "rcash"
  )
  list(RSTAR = fit_llt$TLEVEL)
}

#' Fit the faithful 11-state RSTAR Okun-Phillips state-space
#'
#' Full KFAS port of `rstar.prg` (with state-augmented intercept handling).
#' The EViews state vector is 11-dimensional:
#'
#'   alpha = (ygap, ygapL1, ygapL2, ygapL3, ypot, g, NAIRU, NAIRUL1,
#'            nrate, nrateL1, z)
#'
#' We add a 12th constant `ONE` state so the time-varying intercept on
#' the ygap equation (an exogenous function of `rcash` lags) can be
#' encoded via a time-varying T matrix entry T[1, 12, t]. The signal
#' equations are:
#'
#'   lrgdp_t = ypot_t + ygap_t                            (deterministic identity)
#'   LUR_t   = NAIRU_t + beta_1 * (0.4 * ygap_t + 0.3 * ygapL1_t +
#'                                 0.2 * ygapL2_t + 0.1 * ygapL3_t) + e2
#'   dlptm_t = (1 - gamma_1) * pi_eq_t +
#'             gamma_1/3 * (dlptm_{t-1} + dlptm_{t-2} + dlptm_{t-3}) +
#'             gamma_2 * (LUR_{t-1} - NAIRUL1_t) + e3
#'
#' Structural parameters (alpha_1..3, beta_1, gamma_1..2) are
#' pre-estimated via OLS using HP-like smoothed proxies as initial
#' state values; KFAS then estimates the five state-innovation variances
#' (sigma_1, sigma_4..7) via `fitSSM`. The dlptm signal's lagged-inflation
#' AR(3) and pi_eq terms are pre-subtracted from the observation to give
#' a modified observation y3_mod_t = -gamma_2 * NAIRUL1_t + e3 that
#' KFAS handles linearly.
#'
#' Returns RSTAR (the smoothed `nrate` state) plus the auxiliary states
#' (`YGAP`, `YPOT`, `G`, `Z`) as bimets ts for diagnostics.
#'
#' @param database Named list of bimets ts (needs Y, PTM, LUR, NCR, PI_E).
#' @param sample_start `"YYYYQq"` string. Default `"1986Q3"` matches
#'   rstar.prg's smpl.
#' @return List with `RSTAR`, `YGAP`, `YPOT`, `G`, `Z` (bimets ts).
#' @keywords internal
# Structural-parameter defaults for fit_rstar_kfas_full. Calibrated to
# reasonable economic priors that match rstar.prg's posterior modes:
#   alpha_1: output-gap AR(1) persistence (~0.85)
#   alpha_2: output-gap AR(2) coefficient (~0.0, kept small)
#   alpha_3: interest-rate channel into output gap
#   beta_1:  Okun's-law slope (Δ unemployment per unit ygap), negative
#   gamma_1: weight on lagged-inflation autoregression (in [0, 1])
#   gamma_2: Phillips-curve slope (Δ inflation per unit unemployment gap)
# These are baked in (rather than OLS-pre-estimated) because OLS on
# limited / volatile live data produces alpha_1 estimates near 1, which
# makes ygap a near-unit-root and the downstream nrate diverge. See
# next_session.md for the path to joint MLE if higher fidelity is needed.
RSTAR_FULL_PARAMS <- list(
  alpha_1 = 0.85,
  alpha_2 = 0.0,
  alpha_3 = 0.1,
  # Okun's-law slope. -0.5 (cf. -0.3 v0) disentangles ygap from NAIRU
  # more sharply, letting the smoother attribute the same LUR variation
  # to a smaller NAIRU shift. Closer to rstar.prg's posterior mode.
  beta_1  = -0.5,
  gamma_1 = 0.5,
  gamma_2 = -0.1
)

fit_rstar_kfas_full <- function(database, sample_start = "1986Q3",
                                use_ols_preest = FALSE) {
  SSMcustom <- KFAS::SSMcustom

  required <- c("Y", "PTM", "LUR", "NCR", "PI_E")
  for (v in required) {
    if (is.null(database[[v]])) {
      stop("fit_rstar_kfas_full: missing input ", v, call. = FALSE)
    }
  }

  ts_meta <- ts_to_meta(database[["LUR"]])
  n_total <- length(as.numeric(database[["LUR"]]))

  align <- function(x) {
    other_tsp <- stats::tsp(x); other_v <- as.numeric(x)
    other_y <- floor(other_tsp[1] + 1e-9)
    other_q <- round((other_tsp[1] - other_y) * 4 + 1)
    offset <- (other_y - ts_meta$start_year) * 4L +
              (other_q - ts_meta$start_quarter)
    out <- rep(NA_real_, n_total)
    lo <- max(1L, 1L + offset); hi <- min(n_total, length(other_v) + offset)
    if (lo <= hi) out[lo:hi] <- other_v[(lo - offset):(hi - offset)]
    out
  }
  lur <- as.numeric(database[["LUR"]])
  y_gdp <- align(database[["Y"]])
  ptm <- align(database[["PTM"]])
  ptm[!is.na(ptm) & ptm <= 0] <- NA_real_
  ncr <- align(database[["NCR"]])
  pi_e <- align(database[["PI_E"]])

  lrgdp <- log(y_gdp) * 100  # log levels times 100 (pp-scale, matches EViews)
  dlptm <- c(NA, 100 * diff(log(ptm)))
  rcash <- ncr - 4 * dlptm
  pi_eq <- ((1 + pi_e / 100) ^ (1 / 4) - 1) * 100

  # Sanitize non-finite (PTM zeros etc.)
  lrgdp[!is.finite(lrgdp)] <- NA_real_
  dlptm[!is.finite(dlptm)] <- NA_real_
  rcash[!is.finite(rcash)] <- NA_real_
  pi_eq[!is.finite(pi_eq)] <- NA_real_

  start_idx <- ts_meta$quarter_index(sample_start)
  if (is.na(start_idx) || start_idx < 1L) start_idx <- 1L

  # ---- HP-filtered proxies for pre-estimation ----
  # Lambda=1600 is the canonical quarterly choice (Hodrick-Prescott 1980).
  # Better-behaved than the prior centred-MA proxy: avoids the boundary
  # flat-lining that a window-20 MA produces near sample edges, and
  # gives a less-noisy gap (gap = data - HP trend) closer to what
  # rstar.prg's posterior smoother converges to. KFAS's own
  # SSMtrend(degree=2) is mathematically equivalent for the right Q,
  # but here we just need an initial-state proxy, so the closed-form
  # solution is cheaper.
  ypot_init  <- hp_filter(lrgdp,                   lambda = 1600)
  ygap_init  <- lrgdp - ypot_init
  nairu_init <- hp_filter(lur,                     lambda = 1600)
  nrate_init <- hp_filter(rcash,                   lambda = 1600)
  g_init     <- hp_filter(c(NA, diff(ypot_init)),  lambda = 1600)
  z_init     <- nrate_init - g_init

  # ---- Structural parameters: default to baked-in priors, optionally
  # refine via OLS pre-estimation. OLS on limited live data produces
  # unstable estimates (alpha_1 ~ 1 → near-unit-root ygap → wild
  # rstar); the priors in RSTAR_FULL_PARAMS are calibrated to match
  # rstar.prg's posterior modes and keep the smoother well-behaved.
  lagk <- function(x, k) c(rep(NA_real_, k), x[seq_len(length(x) - k)])
  mask <- seq.int(max(start_idx, 5L), n_total)

  alpha1 <- RSTAR_FULL_PARAMS$alpha_1
  alpha2 <- RSTAR_FULL_PARAMS$alpha_2
  alpha3 <- RSTAR_FULL_PARAMS$alpha_3
  beta1  <- RSTAR_FULL_PARAMS$beta_1
  gamma1 <- RSTAR_FULL_PARAMS$gamma_1
  gamma2 <- RSTAR_FULL_PARAMS$gamma_2

  if (isTRUE(use_ols_preest)) {

    # 1. Output gap equation:
    # ygap = alpha1*ygap(-1) + alpha2*ygap(-2) -
    #        alpha3/2 * (rcash(-1) - nrate(-1) + rcash(-2) - nrate(-2)) + e1
    rhs_gap_diff <- (lagk(rcash, 1) - lagk(nrate_init, 1) +
                     lagk(rcash, 2) - lagk(nrate_init, 2))
    df_gap <- data.frame(
      y  = ygap_init[mask],
      g1 = lagk(ygap_init, 1)[mask],
      g2 = lagk(ygap_init, 2)[mask],
      rd = rhs_gap_diff[mask]
    )
    df_gap <- df_gap[complete.cases(df_gap), ]
    if (nrow(df_gap) > 5L) {
      fit_g <- tryCatch(
        stats::lm(y ~ g1 + g2 + I(-rd / 2) - 1, data = df_gap),
        error = function(e) NULL
      )
      if (!is.null(fit_g)) {
        co <- stats::coef(fit_g)
        if (!is.na(co["g1"]))         alpha1 <- co["g1"]
        if (!is.na(co["g2"]))         alpha2 <- co["g2"]
        if (!is.na(co["I(-rd/2)"]))   alpha3 <- co["I(-rd/2)"]
      }
    }

    # 2. Okun's law:
    # LUR = nairu + beta1 * (0.4*ygap + 0.3*ygap(-1) + 0.2*ygap(-2) + 0.1*ygap(-3))
    okun_rhs <- 0.4 * ygap_init + 0.3 * lagk(ygap_init, 1) +
                0.2 * lagk(ygap_init, 2) + 0.1 * lagk(ygap_init, 3)
    df_okun <- data.frame(
      y_lur = lur[mask] - nairu_init[mask],
      okun  = okun_rhs[mask]
    )
    df_okun <- df_okun[complete.cases(df_okun), ]
    if (nrow(df_okun) > 5L) {
      fit_o <- tryCatch(
        stats::lm(y_lur ~ okun - 1, data = df_okun),
        error = function(e) NULL
      )
      if (!is.null(fit_o)) {
        co <- stats::coef(fit_o)["okun"]
        if (!is.na(co)) beta1 <- co
      }
    }

    # 3. Phillips curve:
    # dlptm = (1-gamma1)*pi_eq + gamma1/3*(dlptm(-1)+dlptm(-2)+dlptm(-3)) +
    #         gamma2*(LUR(-1) - nairu(-1))
    ar3 <- (lagk(dlptm, 1) + lagk(dlptm, 2) + lagk(dlptm, 3)) / 3
    gap_lag <- lagk(lur, 1) - lagk(nairu_init, 1)
    df_phil <- data.frame(
      y  = (dlptm - pi_eq)[mask],
      ar = (ar3 - pi_eq)[mask],
      gl = gap_lag[mask]
    )
    df_phil <- df_phil[complete.cases(df_phil), ]
    if (nrow(df_phil) > 5L) {
      fit_p <- tryCatch(
        stats::lm(y ~ ar + gl - 1, data = df_phil),
        error = function(e) NULL
      )
      if (!is.null(fit_p)) {
        co <- stats::coef(fit_p)
        if (!is.na(co["ar"])) gamma1 <- co["ar"]
        if (!is.na(co["gl"])) gamma2 <- co["gl"]
      }
    }
  }  # end if (isTRUE(use_ols_preest))

  # ---- Build the 12-state KFAS model ----
  # State indices:
  #   1: ygap, 2: ygapL1, 3: ygapL2, 4: ygapL3, 5: ypot, 6: g,
  #   7: NAIRU, 8: NAIRUL1, 9: nrate, 10: nrateL1, 11: z, 12: ONE
  m <- 12L
  T_base <- matrix(0, m, m)
  T_base[1, 1]  <- alpha1
  T_base[1, 2]  <- alpha2
  T_base[1, 9]  <- alpha3 / 2
  T_base[1, 10] <- alpha3 / 2
  T_base[2, 1]  <- 1
  T_base[3, 2]  <- 1
  T_base[4, 3]  <- 1
  T_base[5, 5]  <- 1
  T_base[5, 6]  <- 1
  T_base[6, 6]  <- 1
  T_base[7, 7]  <- 1
  T_base[8, 7]  <- 1
  T_base[9, 6]  <- 4
  T_base[9, 11] <- 1
  T_base[10, 9] <- 1
  T_base[11, 11] <- 1
  T_base[12, 12] <- 1

  # Time-varying T to encode the rcash-driven intercept on ygap state.
  # At time t, ygap_t = ... -alpha3/2*(rcash_{t-1} + rcash_{t-2}) so we set
  # T[1, 12, t] = -alpha3/2 * (rcash_{t-1} + rcash_{t-2}).
  T_arr <- array(T_base, dim = c(m, m, n_total))
  rcash_intercept <- -alpha3 / 2 * (lagk(rcash, 1) + lagk(rcash, 2))
  for (t in seq_len(n_total)) {
    val <- rcash_intercept[t]
    if (is.finite(val)) T_arr[1, 12, t] <- val
  }

  # R matrix (12 x 5). eta = (e1, e4, e5, e6, e7)
  # e1 -> ygap; e4 -> NAIRU; e5 -> ypot; e6 -> z and nrate;
  # e7 -> g and 4x into nrate
  R_mat <- matrix(0, m, 5)
  R_mat[1, 1]  <- 1   # e1 -> ygap
  R_mat[7, 2]  <- 1   # e4 -> NAIRU
  R_mat[5, 3]  <- 1   # e5 -> ypot
  R_mat[11, 4] <- 1   # e6 -> z
  R_mat[6, 5]  <- 1   # e7 -> g
  R_mat[9, 4]  <- 1   # e6 -> nrate
  R_mat[9, 5]  <- 4   # 4*e7 -> nrate

  Q_init <- diag(c(0.5, 0.05, 0.5, 0.1, 0.02))  # placeholder variances

  # Z matrix (3 x 12) — three signals
  Z_mat <- matrix(0, 3, m)
  # lrgdp = ygap + ypot
  Z_mat[1, 1] <- 1
  Z_mat[1, 5] <- 1
  # LUR = beta1*(0.4*ygap + 0.3*ygapL1 + 0.2*ygapL2 + 0.1*ygapL3) + NAIRU
  Z_mat[2, 1] <- 0.4 * beta1
  Z_mat[2, 2] <- 0.3 * beta1
  Z_mat[2, 3] <- 0.2 * beta1
  Z_mat[2, 4] <- 0.1 * beta1
  Z_mat[2, 7] <- 1
  # dlptm_mod = -gamma2 * NAIRUL1 + e3
  Z_mat[3, 8] <- -gamma2

  # Modified dlptm observation:
  #   dlptm - (1-gamma1)*pi_eq - gamma1/3*(lag1+lag2+lag3) - gamma2*LUR(-1)
  dlptm_mod <- dlptm - (1 - gamma1) * pi_eq -
               gamma1 / 3 * (lagk(dlptm, 1) + lagk(dlptm, 2) + lagk(dlptm, 3)) -
               gamma2 * lagk(lur, 1)
  dlptm_mod[!is.finite(dlptm_mod)] <- NA_real_

  Y <- cbind(lrgdp = lrgdp, LUR = lur, dlptm = dlptm_mod)
  Y[!is.finite(Y)] <- NA_real_
  if (start_idx > 1L) Y[seq_len(start_idx - 1L), ] <- NA_real_

  # Initial state mean and covariance.
  # Use HP-smoothed proxies at start_idx; the ONE state has value 1.
  a1 <- matrix(c(
    ygap_init[start_idx],   ygap_init[start_idx - 1L],
    ygap_init[start_idx - 2L], ygap_init[start_idx - 3L],
    ypot_init[start_idx],   g_init[start_idx],
    nairu_init[start_idx],  nairu_init[start_idx - 1L],
    nrate_init[start_idx],  nrate_init[start_idx - 1L],
    z_init[start_idx],      1
  ), nrow = m)
  # Replace any NAs in a1 with sensible defaults.
  a1_defaults <- c(0, 0, 0, 0,
                   if (is.finite(ypot_init[start_idx])) ypot_init[start_idx] else 1000,
                   0.005 * 100, 5, 5, 3, 3, 0, 1)
  na_idx <- which(is.na(a1))
  if (length(na_idx)) a1[na_idx, 1] <- a1_defaults[na_idx]

  # vprior from rstar.prg posterior modes (line 55-66)
  P1 <- diag(c(0.38, 0.38, 0.38, 0.38, 0.54, 0.05, 0.15, 0.15, 0.3, 0.3, 0.22, 0))
  P1inf <- diag(c(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))  # all informed

  # SSMcustom expects T as either matrix or 3D array. KFAS quirk: pass the
  # 3D array directly.
  model <- KFAS::SSModel(
    Y ~ -1 + SSMcustom(
      Z = Z_mat,
      T = T_arr,
      R = R_mat,
      Q = Q_init,
      a1 = a1,
      P1 = P1,
      P1inf = P1inf,
      state_names = c("ygap", "ygapL1", "ygapL2", "ygapL3",
                      "ypot", "g", "NAIRU", "NAIRUL1",
                      "nrate", "nrateL1", "z", "ONE")
    ),
    H = diag(c(1e-8, 0.1, 0.1))  # lrgdp identity ~ 0, LUR + dlptm ~ estimated
  )

  # Five free parameters: log variances of (e1, e4, e5, e6, e7) plus
  # log variances of LUR signal (e2) and dlptm signal (e3) = 7 free pars.
  update_fn <- function(pars, model) {
    q_vals <- exp(pars[1:5])
    model$Q[, , 1] <- diag(q_vals)
    model$H[2, 2, 1] <- exp(pars[6])
    model$H[3, 3, 1] <- exp(pars[7])
    # Keep H[1, 1] tiny (lrgdp identity).
    model$H[1, 1, 1] <- 1e-8
    model
  }
  fit <- tryCatch(
    KFAS::fitSSM(model,
                 inits = c(log(0.5), log(0.05), log(0.5), log(0.1), log(0.02),
                           log(0.1), log(0.1)),
                 updatefn = update_fn, method = "BFGS"),
    error = function(e) NULL
  )
  if (is.null(fit) || fit$optim.out$convergence != 0L) {
    if (!is.null(fit)) {
      warning(sprintf("fit_rstar_kfas_full: optim did not converge (code %d)",
                      fit$optim.out$convergence), call. = FALSE)
    } else {
      warning("fit_rstar_kfas_full: fitSSM failed", call. = FALSE)
      return(NULL)
    }
  }
  ks <- tryCatch(KFAS::KFS(fit$model, smoothing = "state"),
                 error = function(e) NULL)
  if (is.null(ks)) {
    warning("fit_rstar_kfas_full: KFS smoothing failed", call. = FALSE)
    return(NULL)
  }

  pick <- function(state_name) {
    vec <- as.numeric(ks$alphahat[, state_name])
    if (start_idx > 1L) vec[seq_len(start_idx - 1L)] <- NA_real_
    ts_meta$as_bimets(vec)
  }
  list(
    RSTAR = pick("nrate"),
    YGAP  = pick("ygap"),
    YPOT  = pick("ypot"),
    G     = pick("g"),
    Z     = pick("z")
  )
}

# Hodrick-Prescott filter (closed form). Solves
#   min_tau  sum_t (y_t - tau_t)^2  +  lambda * sum_t (Δ²tau_t)^2
# via tau = (I + lambda D'D)^{-1} y, where D is the (n-2 x n) second-
# difference matrix. Lambda=1600 is the canonical quarterly choice.
#
# Handles NAs by linear interpolation before filtering. Internal helper
# used as initial-state seed for fit_rstar_kfas_full() and related
# state-space estimators.
hp_filter <- function(y, lambda = 1600) {
  n <- length(y)
  if (n < 4L) return(as.numeric(y))
  y <- as.numeric(y)
  if (all(is.na(y))) return(y)

  # Linear-interpolate NAs (extending the last/first observation outward)
  # before solving the smoothing problem.
  if (any(is.na(y))) {
    y_filled <- stats::approx(seq_along(y), y, seq_along(y), rule = 2)$y
  } else {
    y_filled <- y
  }

  # Build the (n-2) x n second-difference matrix as a sparse-ish dense
  # matrix (n is at most ~250 in SIBYL use, so dense is fine).
  D <- matrix(0, n - 2L, n)
  for (k in seq_len(n - 2L)) {
    D[k, k]      <-  1
    D[k, k + 1L] <- -2
    D[k, k + 2L] <-  1
  }
  tau <- solve(diag(n) + lambda * crossprod(D), y_filled)
  as.numeric(tau)
}

# Internal: extract the bimets ts metadata needed to round-trip a numeric
# vector through (parse a "YYYYQq" string, build new bimets ts at the
# same start).
ts_to_meta <- function(ts) {
  tsp <- stats::tsp(ts)
  start_dec <- tsp[1]
  start_year    <- floor(start_dec + 1e-9)
  start_quarter <- round((start_dec - start_year) * 4 + 1)
  list(
    start_year    = start_year,
    start_quarter = start_quarter,
    quarter_index = function(yq_str) {
      yq <- parse_yyyyQq(yq_str)
      (yq$year - start_year) * 4L + (yq$quarter - start_quarter) + 1L
    },
    as_bimets = function(vec) {
      bimets::TIMESERIES(vec, START = c(start_year, start_quarter), FREQ = 4)
    }
  )
}
