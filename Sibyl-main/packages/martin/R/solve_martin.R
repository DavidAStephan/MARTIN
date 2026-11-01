#' Solve MARTIN over a horizon, optionally with add-factors
#'
#' The public surface of `martin`. Takes a starting database, a list of
#' add-factors (from `judgement::adjustment_list()`), and a horizon; returns
#' a long tidy projection tibble.
#'
#' Pipeline:
#'
#' 1. [load_martin()] the chosen variant against `database`. ESTIMATE
#'    populates the per-equation residual slots used in step 2.
#' 2. **Replay history**: build a baseline `ConstantAdjustment` list from
#'    `model$behaviorals$<EQ>$residuals` so that with no user-provided
#'    adjustment, the simulated path reproduces history to within solver
#'    tolerance (typically ~1e-3 on levels, not bit-exact — the Gauss-Seidel
#'    solver converges to `sim_convergence`, and identities re-aggregate the
#'    fitted components). This is the bimets equivalent of EViews
#'    `addinit(v=n)` from `references/MARTIN-master/Programs/solve_model.prg`.
#' 3. **Inject user adjustments**: expand `adjustments` to numeric vectors
#'    via [judgement::expand_adjustments()] and inject them into the replay
#'    AFs via bimets `[[year, quarter]]<-` per-cell assignment — the same
#'    pattern `references/bimets-main/BIMETS_MARTIN_LOAD.R` uses to deliver
#'    a shock. User values are added on top of the residual; equations not
#'    in `adjustments` keep their unmodified replay AF.
#' 4. Call `bimets::SIMULATE(model, TSRANGE = ..., ConstantAdjustment = ...)`.
#' 5. Pivot the named-list-of-ts result to a long tibble.
#'
#' Horizons that extend past the data end are supported: the replay AFs
#' (residuals) are decayed forward via the EViews `_a = _a(-1) * -0.5`
#' convention so they remain well-defined into the future. Note that
#' bimets still needs every variable's data to extend over `TSRANGE`;
#' caller must extend exogenous variables (PI_TARGET, dummies, etc.)
#' separately when solving past the historical data end.
#'
#' @param database A named list of `bimets::TIMESERIES`, eventually from
#'   [sibyldata::to_martin_database()]; in tests, from [read_fixture()].
#' @param adjustments A `judgement::adjustment_list` (possibly empty or NULL).
#' @param horizon A length-2 character vector of `c("yyyyQq", "yyyyQq")`
#'   identifying the inclusive simulation range.
#' @param coefficients Which estimation sample to use. Both settings run
#'   `bimets::ESTIMATE()`, which re-fits each behavioural equation's free
#'   coefficients (the AF form is genuinely behavioural — see
#'   [load_martin()]); they differ only in the sample end date.
#'   `"frozen"` (default) estimates over the model file's embedded `TSRANGE`
#'   end of 2019Q3, reproducing the originally-published in-sample fit.
#'   `"reestimated"` re-fits every behavioural equation over its embedded
#'   start through `estimation_end`. Use it deliberately: extending the
#'   sample past 2019Q3 re-fits the coefficients ACROSS the COVID break,
#'   which materially changes them and departs from the published model —
#'   the project default is to leave coefficients frozen unless asked.
#' @param estimation_end Optional `"yyyyQq"` string. Required when
#'   `coefficients = "reestimated"`. Ignored under `"frozen"`.
#' @param scenario A label written into the returned tibble.
#' @param sim_convergence Bimets simulation convergence tolerance.
#' @param sim_iter_limit  Bimets simulation iteration limit.
#'
#' @return A long tidy tibble of `(variable, quarter, value, scenario)`,
#'   with attributes `horizon`, `adjustments`, and `scenario`.
#' @export
solve_martin <- function(database,
                         adjustments     = NULL,
                         horizon,
                         coefficients    = c("frozen", "reestimated"),
                         estimation_end  = NULL,
                         scenario        = "baseline",
                         exogenize       = character(0),
                         baseline_for_exogenize = NULL,
                         exogenize_range = NULL,
                         features        = character(0),
                         feature_params  = list(),
                         sim_convergence = 1e-6,
                         sim_iter_limit  = 100) {
  coefficients <- match.arg(coefficients)
  if (coefficients == "reestimated" && is.null(estimation_end)) {
    stop("`coefficients = 'reestimated'` requires `estimation_end` ",
         "(e.g. '2025Q2').", call. = FALSE)
  }
  if (length(horizon) != 2L || !is.character(horizon)) {
    stop("`horizon` must be a length-2 character vector of `yyyyQq`.",
         call. = FALSE)
  }
  if (is.null(adjustments)) {
    adjustments <- judgement::adjustment_list()
  }
  if (!inherits(adjustments, "adjustment_list")) {
    stop("`adjustments` must be a judgement::adjustment_list or NULL.",
         call. = FALSE)
  }
  if (length(exogenize) > 0L) {
    if (is.null(baseline_for_exogenize)) {
      stop("`exogenize` requires `baseline_for_exogenize` ",
           "(a baseline projection tibble whose values will be used as ",
           "the exogenous path).", call. = FALSE)
    }
    if (!is.data.frame(baseline_for_exogenize) ||
        !all(c("variable", "quarter", "value") %in%
             names(baseline_for_exogenize))) {
      stop("`baseline_for_exogenize` must be a tibble with columns ",
           "(variable, quarter, value).", call. = FALSE)
    }
  }

  # Splice the baseline path into the database for any exogenised variable
  # over the exogenisation range. This is what bimets's Exogenize reads
  # back: it uses the database values for exogenised vars in lieu of
  # iterating their equations.
  if (length(exogenize) > 0L) {
    if (is.null(exogenize_range)) exogenize_range <- horizon
    ex_start <- judgement_parse_quarter(exogenize_range[1])
    ex_end   <- judgement_parse_quarter(exogenize_range[2])
    database <- splice_exogenize_baseline(
      database, baseline_for_exogenize, exogenize,
      ex_start, ex_end
    )
  }

  if (length(features)) {
    database <- seed_feature_data(database, features, feature_params)
  }

  model <- load_martin(
    database, variant = "af", estimate = TRUE,
    estimation_end = if (coefficients == "reestimated") estimation_end else NULL,
    features = features, feature_params = feature_params
  )

  start <- judgement_parse_quarter(horizon[1])
  end   <- judgement_parse_quarter(horizon[2])
  tsrange <- c(start$year, start$quarter, end$year, end$quarter)

  replay_afs <- residual_constant_adjustment(model)
  # Extend each replay AF forward via the EViews `_a(-1) * -0.5` rule so
  # the simulator sees a defined value at every period in horizon — even
  # when horizon[2] is past the data end. Cells inside the historical
  # range are untouched.
  replay_afs <- lapply(replay_afs, function(ts) {
    extend_residual_with_decay(ts, end$year, end$quarter)
  })
  user_expanded <- judgement::expand_adjustments(adjustments, horizon)
  afs <- inject_user_adjustments(replay_afs, user_expanded)

  # Build bimets's Exogenize list: each entry is c(start_year, start_q,
  # end_year, end_q) for the period during which that variable is held
  # to the database's (now-baseline-spliced) values.
  exogenize_list <- NULL
  if (length(exogenize) > 0L) {
    if (is.null(exogenize_range)) exogenize_range <- horizon
    ex_start <- judgement_parse_quarter(exogenize_range[1])
    ex_end   <- judgement_parse_quarter(exogenize_range[2])
    exogenize_list <- stats::setNames(
      lapply(exogenize, function(v) c(ex_start$year, ex_start$quarter,
                                       ex_end$year, ex_end$quarter)),
      exogenize
    )
  }

  .suppress_bimets_version_warning({
    model <- bimets::SIMULATE(
      model,
      TSRANGE            = tsrange,
      ConstantAdjustment = afs,
      Exogenize          = exogenize_list,
      simConvergence     = sim_convergence,
      simIterLimit       = sim_iter_limit
    )
  })

  out <- simulation_to_tibble(model, scenario = scenario)
  attr(out, "horizon")     <- horizon
  attr(out, "adjustments") <- adjustments
  attr(out, "exogenize")   <- exogenize
  attr(out, "scenario")    <- scenario
  # Convergence / NaN diagnostics. bimets hard-stops via stop() on numeric
  # overflow, but a soft iteration-limit warning can leave NaN/Inf in the
  # $simulation series and pass them through silently. Surface that here so
  # callers (and the LLM-facing layer) never treat garbage as a clean solve.
  attr(out, "convergence") <- simulation_convergence(model, tsrange)
  out
}

# Count non-finite cells across a SIMULATEd model's $simulation series,
# restricted to the simulation TSRANGE, and report a converged flag. Returns
# list(converged = logical, n_nonfinite = integer). `converged` is FALSE when
# any endogenous series carries a NaN/Inf inside the solved window.
simulation_convergence <- function(model, tsrange) {
  sim <- model$simulation
  if (is.null(sim) || length(sim) == 0L) {
    return(list(converged = FALSE, n_nonfinite = NA_integer_))
  }
  is_series <- vapply(sim, function(x) inherits(x, "ts"), logical(1))
  start_dec <- tsrange[1] + (tsrange[2] - 1) / 4
  end_dec   <- tsrange[3] + (tsrange[4] - 1) / 4
  n_nonfinite <- 0L
  for (ts in sim[is_series]) {
    t    <- as.numeric(stats::time(ts))
    vals <- as.numeric(ts)
    inwin <- t >= start_dec - 1e-9 & t <= end_dec + 1e-9
    n_nonfinite <- n_nonfinite + sum(!is.finite(vals[inwin]))
  }
  list(converged = n_nonfinite == 0L, n_nonfinite = as.integer(n_nonfinite))
}

# Build a ConstantAdjustment list from a model's behavioural residuals.
# After ESTIMATE on MARTINMOD_AF.txt (95 behaviourals — only ~51 have
# `RESTRICT> c1=1`, the rest impose real cross-coefficient restrictions, and
# ESTIMATE re-fits the free coefficients), each `$residuals` slot is the
# EViews-style historical AF that makes fitted + AF = actual. Using these as
# the baseline AF means SIMULATE with no user adjustments replays history to
# within solver tolerance (~1e-3, not bit-exact) — the bimets equivalent of
# EViews `addinit(v=n)` from references/MARTIN-master/Programs/solve_model.prg.
residual_constant_adjustment <- function(model) {
  eqs <- names(model$behaviorals)
  out <- vector("list", length(eqs))
  names(out) <- eqs
  for (eq in eqs) {
    res <- model$behaviorals[[eq]]$residuals
    if (!is.null(res)) out[[eq]] <- res
  }
  out[!vapply(out, is.null, logical(1))]
}

# Inject expanded user adjustments into the replay AFs via bimets per-cell
# assignment. This is the pattern used in
# references/bimets-main/BIMETS_MARTIN_LOAD.R (`Shock$NCR[[2010,1]] <- ...`)
# and preserves the replay over the rest of the historical range.
#
# `replay`        is the list of full-history residual ts.
# `user_expanded` is the named list of numeric vectors from
#                 judgement::expand_adjustments(); it carries `quarters` as
#                 an attribute.
inject_user_adjustments <- function(replay, user_expanded) {
  if (length(user_expanded) == 0L) return(replay)
  qs <- attr(user_expanded, "quarters")
  if (is.null(qs)) {
    stop("`user_expanded` is missing its `quarters` attribute.", call. = FALSE)
  }

  out <- replay
  for (eq in names(user_expanded)) {
    vals <- user_expanded[[eq]]
    if (is.null(out[[eq]])) {
      # No replay AF for this equation (unusual for AF-form). Build a fresh
      # ts at the user's horizon and let bimets handle it.
      start <- judgement_parse_quarter(qs[1])
      out[[eq]] <- bimets::TIMESERIES(
        vals, START = c(start$year, start$quarter), FREQ = 4
      )
      next
    }
    target <- out[[eq]]
    for (i in seq_along(qs)) {
      q <- judgement_parse_quarter(qs[i])
      target[[q$year, q$quarter]] <- target[[q$year, q$quarter]] + vals[i]
    }
    out[[eq]] <- target
  }
  out
}

# Pivot a SIMULATEd model's $simulation slot to a long tidy tibble.
simulation_to_tibble <- function(model, scenario = "baseline") {
  sim <- model$simulation
  if (is.null(sim) || length(sim) == 0L) {
    stop("Model has no simulation results — did SIMULATE() run?",
         call. = FALSE)
  }
  # bimets stuffs metadata like `__SIM_PARAMETERS__` into $simulation as a
  # list; skip anything that isn't an actual time series.
  is_series <- vapply(sim, function(x) inherits(x, "ts"), logical(1))
  vars <- names(sim)[is_series]
  rows <- lapply(vars, function(var) {
    ts <- sim[[var]]
    if (is.null(ts)) return(NULL)
    # bimets TIMESERIES inherits from ts; stats::time() gives decimal years
    # (e.g. 2010.0, 2010.25). Convert to "yyyyQq".
    t <- as.numeric(stats::time(ts))
    year    <- floor(t + 1e-9)
    quarter <- round((t - year) * 4 + 1)
    tibble::tibble(
      variable = var,
      quarter  = sprintf("%04dQ%d", year, quarter),
      value    = as.numeric(ts),
      scenario = scenario
    )
  })
  dplyr::bind_rows(rows)
}

# Overwrite each exogenised variable's bimets ts with the corresponding
# baseline-projection values over [ex_start, ex_end]. Cells outside that
# range, and variables not in `exogenize`, are left untouched.
#
# Why this is needed: bimets' Exogenize argument doesn't take a path —
# it tells SIMULATE to use the database's existing values for those
# variables instead of iterating their equations. To "hold X at
# baseline" we have to put the baseline values *into* the database
# first.
splice_exogenize_baseline <- function(database, baseline, exogenize,
                                      ex_start, ex_end) {
  ex_lookup <- split(baseline, baseline$variable)
  for (v in exogenize) {
    ts <- database[[v]]
    if (is.null(ts)) {
      stop(sprintf("Cannot exogenise '%s': not in database.", v),
           call. = FALSE)
    }
    base_v <- ex_lookup[[v]]
    if (is.null(base_v) || nrow(base_v) == 0L) {
      stop(sprintf("Cannot exogenise '%s': no baseline values supplied.",
                   v), call. = FALSE)
    }
    base_v <- base_v[order(base_v$quarter), , drop = FALSE]
    ex_start_dec <- ex_start$year + (ex_start$quarter - 1) / 4
    ex_end_dec   <- ex_end$year   + (ex_end$quarter   - 1) / 4

    tsp <- stats::tsp(ts)
    ts_start_year <- floor(tsp[1] + 1e-9)
    ts_start_q    <- round((tsp[1] - ts_start_year) * 4 + 1)
    vals <- as.numeric(ts)
    # Extend ts forward if it ends before ex_end (carry-forward seed).
    cur_end_dec <- tsp[2]
    if (cur_end_dec < ex_end_dec - 1e-9) {
      n_pad <- round((ex_end_dec - cur_end_dec) * 4)
      last_v <- tail(vals[is.finite(vals)], 1)
      if (length(last_v) == 0L) last_v <- 0
      vals <- c(vals, rep(last_v, n_pad))
    }
    # Index each cell by yyyyQq.
    n <- length(vals)
    cell_labels <- vapply(seq_len(n), function(i) {
      abs_q <- ts_start_year * 4L + (ts_start_q - 1L) + (i - 1L)
      sprintf("%04dQ%d", abs_q %/% 4L, (abs_q %% 4L) + 1L)
    }, character(1))
    base_by_q <- stats::setNames(base_v$value, base_v$quarter)

    # Identify which cells fall inside the exogenisation window.
    in_window <- vapply(seq_len(n), function(i) {
      abs_q <- ts_start_year * 4L + (ts_start_q - 1L) + (i - 1L)
      dec <- abs_q %/% 4L + ((abs_q %% 4L)) / 4
      dec >= ex_start_dec - 1e-9 & dec <= ex_end_dec + 1e-9
    }, logical(1))

    for (i in which(in_window)) {
      bv <- base_by_q[[cell_labels[i]]]
      if (!is.null(bv) && is.finite(bv)) vals[i] <- bv
    }

    database[[v]] <- bimets::TIMESERIES(
      vals, START = c(ts_start_year, ts_start_q), FREQ = 4
    )
  }
  database
}

#' Solve MARTIN with stochastic uncertainty bands
#'
#' An opt-in companion to [solve_martin()] that propagates coefficient /
#' equation-error uncertainty into the projection via a Monte Carlo
#' simulation, returning a central path plus a lower/upper band per
#' (variable, quarter). The deterministic [solve_martin()] is unchanged and
#' remains the default path; callers opt into bands explicitly by calling
#' this function.
#'
#' Mechanism. When `bimets::STOCHSIMULATE()` is available (it is in the
#' vendored bimets >= 4.x), each behavioural equation's disturbance is
#' perturbed across `n_draws` replicas with mean zero and the equation's own
#' regression standard error
#' (`behaviorals$<EQ>$statistics$StandardErrorRegression`), then the model is
#' re-solved per replica. Bands are the empirical 2.5%/97.5% quantiles of the
#' replica matrix (`model$simulation_MM`); `value` is the deterministic
#' (first-column) solution, identical to [solve_martin()]'s central path.
#'
#' Fallback. If `STOCHSIMULATE` is not exported by the installed bimets, we
#' fall back to a documented coefficient-perturbation scheme: we draw
#' `n_draws` deterministic solves, each re-running [solve_martin()] after
#' jittering every behavioural add-factor by a normal shock scaled to that
#' equation's residual standard deviation. This is coarser (it perturbs the
#' add-factor rather than the regression coefficients directly) but yields a
#' comparable spread without STOCHSIMULATE.
#'
#' @inheritParams solve_martin
#' @param n_draws Integer number of stochastic replicas. Default 200.
#' @param ... Passed through to [solve_martin()] in the fallback path
#'   (e.g. `exogenize`, `baseline_for_exogenize`).
#'
#' @return A tidy tibble with columns
#'   `(variable, quarter, value, lower, upper, scenario)`. `value` is the
#'   central (deterministic) path; `lower`/`upper` are the 2.5%/97.5%
#'   band edges. Attribute `n_draws` records the replica count; attribute
#'   `band_method` is `"stochsimulate"` or `"af_perturbation"`.
#' @export
solve_martin_stochastic <- function(database,
                                    adjustments    = NULL,
                                    horizon,
                                    coefficients   = c("frozen", "reestimated"),
                                    estimation_end = NULL,
                                    scenario       = "baseline",
                                    n_draws        = 200L,
                                    band_start     = NULL,
                                    ...) {
  coefficients <- match.arg(coefficients)
  if (length(horizon) != 2L || !is.character(horizon)) {
    stop("`horizon` must be a length-2 character vector of `yyyyQq`.",
         call. = FALSE)
  }
  n_draws <- as.integer(n_draws)
  if (is.na(n_draws) || n_draws < 2L) {
    stop("`n_draws` must be an integer >= 2.", call. = FALSE)
  }

  has_stoch <- exists("STOCHSIMULATE", where = asNamespace("bimets"),
                      inherits = FALSE)

  if (has_stoch) {
    # STOCHSIMULATE perturbs the model over the band window; an unlucky
    # disturbance can still overflow a behavioural (e.g. XRE), so fall back to
    # the AF-perturbation path rather than failing the whole round.
    out <- tryCatch({
      res <- solve_martin_stochastic_bimets(
        database, adjustments, horizon, coefficients, estimation_end,
        scenario, n_draws, band_start, ...
      )
      attr(res, "band_method") <- "stochsimulate"
      res
    }, error = function(e) {
      warning("solve_martin_stochastic: STOCHSIMULATE failed (",
              conditionMessage(e), "); falling back to AF perturbation.",
              call. = FALSE)
      res <- solve_martin_stochastic_fallback(
        database, adjustments, horizon, coefficients, estimation_end,
        scenario, min(n_draws, 60L), ...
      )
      attr(res, "band_method") <- "af_perturbation (stochsimulate failed)"
      res
    })
  } else {
    out <- solve_martin_stochastic_fallback(
      database, adjustments, horizon, coefficients, estimation_end,
      scenario, n_draws, ...
    )
    attr(out, "band_method") <- "af_perturbation"
  }
  attr(out, "n_draws")  <- n_draws
  attr(out, "scenario") <- scenario
  out
}

# STOCHSIMULATE-backed implementation. Builds the same replay AFs +
# user-injected adjustments as solve_martin(), then perturbs each behavioural
# equation's disturbance by its own regression standard error and reads the
# empirical band off the per-variable realization matrix (simulation_MM).
solve_martin_stochastic_bimets <- function(database, adjustments, horizon,
                                           coefficients, estimation_end,
                                           scenario, n_draws,
                                           band_start = NULL, ...) {
  if (is.null(adjustments)) adjustments <- judgement::adjustment_list()

  model <- load_martin(
    database, variant = "af", estimate = TRUE,
    estimation_end = if (coefficients == "reestimated") estimation_end else NULL
  )

  start <- judgement_parse_quarter(horizon[1])
  end   <- judgement_parse_quarter(horizon[2])
  tsrange <- c(start$year, start$quarter, end$year, end$quarter)

  # Restrict the stochastic disturbances to the forecast window so we do not
  # perturb the well-determined in-sample period -- perturbing it can overflow
  # a behavioural (observed: XRE at 2015Q2) and it is not where forecast
  # uncertainty lives. Default window = last 12 quarters of the horizon.
  end_abs   <- end$year * 4L + (end$quarter - 1L)
  start_abs <- start$year * 4L + (start$quarter - 1L)
  bs_abs <- if (is.null(band_start)) {
    max(start_abs, end_abs - 11L)
  } else {
    bq <- judgement_parse_quarter(band_start)
    max(start_abs, bq$year * 4L + (bq$quarter - 1L))
  }
  stoch_range <- c(bs_abs %/% 4L, (bs_abs %% 4L) + 1L, end$year, end$quarter)

  replay_afs <- residual_constant_adjustment(model)
  replay_afs <- lapply(replay_afs, function(ts) {
    extend_residual_with_decay(ts, end$year, end$quarter)
  })
  user_expanded <- judgement::expand_adjustments(adjustments, horizon)
  afs <- inject_user_adjustments(replay_afs, user_expanded)

  # Disturbance structure: zero-mean normal at each behavioural's regression
  # standard error, applied over the forecast (band) window only.
  stoch_structure <- build_stoch_structure(model, stoch_range)

  .suppress_bimets_version_warning({
    model <- suppressWarnings(suppressMessages(bimets::STOCHSIMULATE(
      model,
      TSRANGE            = tsrange,
      ConstantAdjustment = afs,
      StochStructure     = stoch_structure,
      StochReplica       = n_draws,
      simConvergence     = 1e-6,
      simIterLimit       = 100,
      quietly            = TRUE
    )))
  })

  stochastic_simulation_to_tibble(model, tsrange, scenario)
}

# Build a STOCHSIMULATE StochStructure: one zero-mean normal disturbance per
# behavioural equation, with sd = that equation's regression standard error.
# Equations without a usable standard error are skipped (left deterministic).
build_stoch_structure <- function(model, tsrange) {
  eqs <- names(model$behaviorals)
  out <- list()
  for (eq in eqs) {
    se <- tryCatch(
      model$behaviorals[[eq]]$statistics$StandardErrorRegression,
      error = function(e) NULL
    )
    if (is.null(se) || length(se) != 1L || !is.finite(se) || se <= 0) next
    out[[eq]] <- list(
      TSRANGE = tsrange,
      TYPE    = "NORM",
      PARS    = c(0, se)
    )
  }
  out
}

# Pivot a STOCHSIMULATEd model to a (variable, quarter, value, lower, upper,
# scenario) tibble. `value` is the deterministic solve (first column of the
# realization matrix); lower/upper are empirical 2.5%/97.5% quantiles across
# replicas. Rows of simulation_MM correspond to quarters in TSRANGE order.
stochastic_simulation_to_tibble <- function(model, tsrange, scenario) {
  mm <- model$simulation_MM
  if (is.null(mm) || length(mm) == 0L) {
    stop("Model has no simulation_MM — did STOCHSIMULATE() run?",
         call. = FALSE)
  }
  is_mat <- vapply(mm, is.matrix, logical(1))
  vars <- names(mm)[is_mat]
  start_abs <- tsrange[1] * 4L + (tsrange[2] - 1L)
  rows <- lapply(vars, function(var) {
    mat <- mm[[var]]
    nq  <- nrow(mat)
    q_labels <- vapply(seq_len(nq), function(i) {
      abs_q <- start_abs + (i - 1L)
      sprintf("%04dQ%d", abs_q %/% 4L, (abs_q %% 4L) + 1L)
    }, character(1))
    # First column is the deterministic realization (no disturbance).
    central <- mat[, 1L]
    bands <- t(apply(mat, 1L, function(r) {
      r <- r[is.finite(r)]
      if (length(r) == 0L) return(c(NA_real_, NA_real_))
      stats::quantile(r, probs = c(0.025, 0.975), names = FALSE)
    }))
    tibble::tibble(
      variable = var,
      quarter  = q_labels,
      value    = as.numeric(central),
      lower    = bands[, 1L],
      upper    = bands[, 2L],
      scenario = scenario
    )
  })
  dplyr::bind_rows(rows)
}

# Coefficient-perturbation fallback used when STOCHSIMULATE is unavailable.
# We re-run solve_martin() n_draws times, each time adding a zero-mean normal
# shock to every behavioural add-factor over the horizon, scaled to that
# equation's residual standard deviation. The central path is the unperturbed
# solve_martin(); bands are empirical quantiles across the perturbed draws.
solve_martin_stochastic_fallback <- function(database, adjustments, horizon,
                                             coefficients, estimation_end,
                                             scenario, n_draws, ...) {
  if (is.null(adjustments)) adjustments <- judgement::adjustment_list()

  central <- solve_martin(
    database, adjustments = adjustments, horizon = horizon,
    coefficients = coefficients, estimation_end = estimation_end,
    scenario = scenario, ...
  )

  # Estimate each equation's residual sd once, from a frozen load.
  model0 <- load_martin(
    database, variant = "af", estimate = TRUE,
    estimation_end = if (coefficients == "reestimated") estimation_end else NULL
  )
  res_sd <- vapply(names(model0$behaviorals), function(eq) {
    r <- as.numeric(model0$behaviorals[[eq]]$residuals)
    r <- r[is.finite(r)]
    if (length(r) < 2L) NA_real_ else stats::sd(r)
  }, numeric(1))
  res_sd <- res_sd[is.finite(res_sd) & res_sd > 0]

  qs <- quarter_seq(horizon[1], horizon[2])

  draws <- vector("list", n_draws)
  for (d in seq_len(n_draws)) {
    shock_adjs <- lapply(names(res_sd), function(eq) {
      judgement::adjustment(
        equation        = eq,
        horizon         = qs,
        value           = stats::rnorm(length(qs), 0, res_sd[[eq]]),
        rationale       = "stochastic band draw (af perturbation)",
        tail            = "zero",
        confidence      = "medium",
        source          = "human",
        round_id        = "stochastic-fallback"
      )
    })
    al <- do.call(judgement::adjustment_list, shock_adjs)
    draws[[d]] <- tryCatch(
      solve_martin(
        database, adjustments = al, horizon = horizon,
        coefficients = coefficients, estimation_end = estimation_end,
        scenario = scenario, ...
      )[, c("variable", "quarter", "value")],
      error = function(e) NULL
    )
  }
  draws <- draws[!vapply(draws, is.null, logical(1))]

  band <- dplyr::summarise(
    dplyr::group_by(
      dplyr::bind_rows(draws), rlang::.data$variable, rlang::.data$quarter
    ),
    lower = stats::quantile(rlang::.data$value, 0.025,
                            names = FALSE, na.rm = TRUE),
    upper = stats::quantile(rlang::.data$value, 0.975,
                            names = FALSE, na.rm = TRUE),
    .groups = "drop"
  )

  out <- dplyr::left_join(
    central[, c("variable", "quarter", "value", "scenario")],
    band, by = c("variable", "quarter")
  )
  out[, c("variable", "quarter", "value", "lower", "upper", "scenario")]
}

# Inclusive "yyyyQq" sequence from `from` to `to`.
quarter_seq <- function(from, to) {
  f <- judgement_parse_quarter(from)
  t <- judgement_parse_quarter(to)
  a <- f$year * 4L + (f$quarter - 1L)
  b <- t$year * 4L + (t$quarter - 1L)
  abs_q <- seq.int(a, b)
  sprintf("%04dQ%d", abs_q %/% 4L, (abs_q %% 4L) + 1L)
}

