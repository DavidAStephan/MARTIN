#' Produce h-quarter-ahead estimates for MARTIN's handover variables
#'
#' For each variable in `variables`, takes the series from `database`, fits a
#' simple univariate model (per `method`), and produces forecasts for the
#' next `h` quarters past the last observed value. Returns a tidy tibble.
#'
#' Method options (delegated to `fable` except `"bridge_monthly"`):
#'
#' - `"arima"`  — `fable::ARIMA()` (default; auto-orders).
#' - `"ets"`    — `fable::ETS()`.
#' - `"naive"`  — random walk (`fable::NAIVE()`).
#' - `"bridge"` — `fable::ARIMA` constrained to AR(1) + seasonal
#'   AR(1) with auto-chosen differencing. Cheaper than full auto
#'   ARIMA but captures within-year persistence + seasonality.
#' - `"bridge_monthly"` — true monthly-indicator bridge: regress the
#'   quarterly target on a quarterly aggregate of a monthly indicator
#'   (e.g. HOURS → Y, RT → RC), then predict the forecast quarter
#'   using a **partial-quarter** average of whatever months of the
#'   indicator are already available. Requires the `bridge_indicators`
#'   argument mapping target codes to indicator codes, and the
#'   monthly indicators themselves in the `monthly_indicators`
#'   argument (typically from
#'   `sibyldata::nowcast_monthly_indicators()`).
#'
#' Ragged-edge handling: each variable is forecast from its own last
#' observed quarter, so series that lag (e.g. National Accounts) get more
#' forecast quarters than series that don't (e.g. exchange rates).
#'
#' @param database A named list of `bimets::TIMESERIES`, from
#'   [sibyldata::to_martin_database()] or [martin::read_fixture()].
#' @param h Integer. Number of quarters past each series' last observation
#'   to forecast. Default `2` (Q+0 + Q+1).
#' @param method One of `"arima"`, `"ets"`, `"naive"`.
#' @param variables Character vector of MARTIN variable codes to nowcast.
#'   Defaults to [handover_variables()] intersected with `names(database)`.
#' @param level Numeric. Forecast-interval coverage in percent. Default `80`.
#'
#' @return A tidy tibble with columns
#'   `(variable, quarter, central, lower, upper, method)`.
#' @export
nowcast_handover <- function(database,
                              h         = 2,
                              method    = c("arima", "ets", "naive",
                                            "bridge", "bridge_monthly"),
                              variables = NULL,
                              level     = 80,
                              bridge_indicators = NULL,
                              monthly_indicators = NULL) {
  method <- match.arg(method)
  if (!is.list(database) || length(database) == 0L) {
    stop("`database` must be a non-empty named list of bimets time series.",
         call. = FALSE)
  }
  if (is.null(variables)) {
    variables <- intersect(handover_variables(), names(database))
  }
  missing_vars <- setdiff(variables, names(database))
  if (length(missing_vars)) {
    stop("Database is missing handover variables: ",
         paste(missing_vars, collapse = ", "), call. = FALSE)
  }
  if (method == "bridge_monthly") {
    if (is.null(bridge_indicators) || is.null(monthly_indicators)) {
      stop("method = 'bridge_monthly' requires both `bridge_indicators` ",
           "(a named list/character vector mapping target codes to ",
           "indicator names) and `monthly_indicators` (a named list of ",
           "monthly bimets ts, typically from ",
           "`sibyldata::nowcast_monthly_indicators()`).", call. = FALSE)
    }
  }

  out_rows <- purrr::map(variables, function(var) {
    ts <- database[[var]]
    if (method == "bridge_monthly") {
      indicator_name <- bridge_indicators[[var]]
      if (is.null(indicator_name) || is.null(monthly_indicators[[indicator_name]])) {
        # No indicator mapped or indicator missing → fall back to ARIMA.
        return(forecast_one(ts, variable = var, h = h,
                            method = "arima", level = level))
      }
      forecast_one_bridge_monthly(
        target_ts = ts, variable = var,
        indicator_ts = monthly_indicators[[indicator_name]],
        indicator_name = indicator_name,
        h = h, level = level
      )
    } else {
      forecast_one(ts, variable = var, h = h, method = method, level = level)
    }
  })
  dplyr::bind_rows(out_rows)
}

# Forecast one variable. Returns a tidy tibble with `h` rows.
forecast_one <- function(ts, variable, h, method, level) {
  tsbl <- bimets_to_tsibble(ts, variable = variable)
  if (nrow(tsbl) < 8L) {
    stop("Variable `", variable, "` has fewer than 8 observations; ",
         "nowcast needs more history.", call. = FALSE)
  }

  spec <- switch(method,
    arima  = fable::ARIMA(value),
    ets    = fable::ETS(value),
    naive  = fable::NAIVE(value),
    # bridge: AR(1) + seasonal AR(1) ARIMA with auto-chosen
    # differencing. Captures within-year persistence and year-on-year
    # seasonality cheaply, without ARIMA's full auto-order search.
    # fable::TSLM with lag(value) would be the more natural "linear
    # bridge" framing, but TSLM doesn't propagate the lagged dependent
    # into the forecast horizon — fable wants AR structure inside an
    # ARIMA spec for the lag-of-LHS forecast to chain. Differencing
    # range pdq(1, 0:1, 0) lets the model handle non-stationary series
    # (RC, NC, etc.) without auto-selecting AR order.
    bridge = fable::ARIMA(value ~ pdq(1, 0:1, 0) + PDQ(1, 0:1, 0))
  )

  # fable's ARIMA/ETS auto-selection prints warnings for ill-conditioned
  # series (e.g. effectively-constant series, weird seasonality on short
  # samples). For nowcast — which runs across dozens of series, some of
  # which are smooth and some chaotic — these are informational and
  # uninteresting to a forecast-round user. Muffle them surgically.
  fit <- withCallingHandlers(
    fabletools::model(tsbl, model = spec),
    warning = function(w) invokeRestart("muffleWarning"),
    message = function(m) invokeRestart("muffleMessage")
  )

  fc <- fabletools::forecast(fit, h = h)
  hi_col <- paste0(level, "%")
  hi <- fabletools::hilo(fc, level)
  hi_vec <- hi[[hi_col]]   # a fabletools hilo vector

  central <- hi$.mean
  lower   <- hi_vec$lower
  upper   <- hi_vec$upper

  # Finite guard. fable can silently return NA / NaN / Inf central forecasts
  # when the chosen model degenerates (e.g. an ARIMA that failed to fit a
  # near-constant series). A non-finite central value spliced into MARTIN
  # poisons the whole solve, so we refuse to hand one back.
  if (!all(is.finite(central))) {
    stop("Nowcast for `", variable, "` (method '", method, "') produced a ",
         "non-finite central forecast. Refusing to return an NA/Inf value ",
         "that would poison the MARTIN solve.", call. = FALSE)
  }
  # The interval should bracket the central path; if fable hands back a
  # non-finite or inverted band the central value is still usable but the
  # band is not trustworthy, so flag it loudly.
  if (!all(is.finite(lower) & is.finite(upper) &
           lower <= central & central <= upper)) {
    stop("Nowcast for `", variable, "` (method '", method, "') produced an ",
         "invalid forecast interval (non-finite or not bracketing the ",
         "central path).", call. = FALSE)
  }

  tibble::tibble(
    variable = variable,
    quarter  = hi$quarter,
    central  = central,
    lower    = lower,
    upper    = upper,
    method   = method
  )
}

# Monthly-indicator bridge forecast, specified in GROWTH RATES.
#
# Both the target and the (quarterly-aggregated) indicator are I(1)
# trending series, so a levels-on-levels regression target ~ indicator is
# a spurious regression: it fits the shared trend, not the bridge signal,
# and its standard errors are meaningless. Instead we regress the quarterly
# log-difference of the target on the log-difference of the indicator:
#
#     dlog(target_t) = b0 + b1 * dlog(indicator_t) + e_t
#
# then reconstruct the forecast level by applying the predicted growth to
# the last observed target level (chained over the horizon). The interval
# is a proper prediction interval from stats::predict(interval =
# "prediction") on the growth regression, mapped back to levels, and is
# widened for partial-quarter Q+1 points whose indicator only covers 1-2
# of the 3 months. Falls back to a naive last-value forecast if the fit is
# degenerate or no indicator data covers the forecast horizon.
forecast_one_bridge_monthly <- function(target_ts, variable,
                                        indicator_ts, indicator_name,
                                        h, level) {
  if (is.null(indicator_ts) || length(as.numeric(indicator_ts)) == 0L) {
    return(forecast_one(target_ts, variable, h, "arima", level))
  }

  # ---- Aggregate the monthly indicator into per-quarter buckets ----
  ind_v <- as.numeric(indicator_ts)
  ind_tsp <- stats::tsp(indicator_ts)
  start_y <- floor(ind_tsp[1] + 1e-9)
  start_m <- round((ind_tsp[1] - start_y) * 12 + 1)
  # Build (year, quarter) labels for each monthly observation.
  n_ind <- length(ind_v)
  ind_year <- start_y + (seq_len(n_ind) - 1L + (start_m - 1L)) %/% 12L
  ind_month <- ((start_m - 1L + seq_len(n_ind) - 1L) %% 12L) + 1L
  ind_quarter <- (ind_month - 1L) %/% 3L + 1L
  ind_key <- ind_year * 10L + ind_quarter   # e.g. 20211 = 2021Q1

  # Mean per (year, quarter), tracking the number of months observed so
  # we can mark partial quarters distinctly from full ones.
  ind_buckets <- vapply(unique(ind_key), function(k) {
    sel <- ind_key == k & !is.na(ind_v)
    if (!any(sel)) return(c(NA_real_, 0))
    c(mean(ind_v[sel]), sum(sel))
  }, numeric(2))
  ind_means  <- ind_buckets[1, ]
  ind_nmonth <- ind_buckets[2, ]
  ind_q_keys <- unique(ind_key)

  # ---- Pair with the target's quarterly history ----
  tgt_v <- as.numeric(target_ts)
  tgt_tsp <- stats::tsp(target_ts)
  tgt_start_y <- floor(tgt_tsp[1] + 1e-9)
  tgt_start_q <- round((tgt_tsp[1] - tgt_start_y) * 4 + 1)
  n_tgt <- length(tgt_v)
  tgt_year <- tgt_start_y +
              (seq_len(n_tgt) - 1L + (tgt_start_q - 1L)) %/% 4L
  tgt_q <- ((tgt_start_q - 1L + seq_len(n_tgt) - 1L) %% 4L) + 1L
  tgt_key <- tgt_year * 10L + tgt_q

  # OLS sample: full-month quarters (3 obs) AND both target + indicator
  # non-NA.
  match_pos <- match(tgt_key, ind_q_keys)
  has_ind   <- !is.na(match_pos)
  ind_aligned <- rep(NA_real_, n_tgt)
  ind_nmonth_aligned <- rep(0L, n_tgt)
  ind_aligned[has_ind]        <- ind_means[match_pos[has_ind]]
  ind_nmonth_aligned[has_ind] <- as.integer(ind_nmonth[match_pos[has_ind]])

  # ---- Build growth-rate (log-difference) series for the bridge ----------
  # Use log-differences where the level is strictly positive (the usual case
  # for the macro indicators bridged here); fall back to simple differences
  # for series that can be non-positive (e.g. net balances), so the bridge
  # is still defined. dlog ~= quarterly growth rate; the reconstruction step
  # below is the exact inverse for whichever transform we pick.
  use_log <- all(tgt_v[!is.na(tgt_v)] > 0) &&
             all(ind_aligned[!is.na(ind_aligned)] > 0)
  grow <- function(v) {
    if (use_log) c(NA_real_, diff(log(v))) else c(NA_real_, diff(v))
  }
  d_tgt <- grow(tgt_v)
  d_ind <- grow(ind_aligned)

  # Fit only on full-month quarters (3 obs) with both growth terms defined.
  full_sample <- is.finite(d_tgt) & is.finite(d_ind) &
                 ind_nmonth_aligned == 3L
  if (sum(full_sample) < 8L) {
    # Not enough overlap to fit a growth-rate bridge — degrade gracefully.
    return(forecast_one(target_ts, variable, h, "arima", level))
  }

  df_fit <- data.frame(
    dy = d_tgt[full_sample],
    dx = d_ind[full_sample]
  )
  fit <- tryCatch(stats::lm(dy ~ dx, data = df_fit),
                  error = function(e) NULL)
  # A zero-variance indicator-growth column (collinear with the intercept)
  # gives a rank-deficient fit whose prediction interval is unusable.
  if (is.null(fit) || anyNA(stats::coef(fit))) {
    return(forecast_one(target_ts, variable, h, "arima", level))
  }

  # ---- Forecast the next `h` quarters, chaining growth onto the last level
  last_obs_pos <- max(which(!is.na(tgt_v)))
  last_tgt_key <- tgt_key[last_obs_pos]
  last_level   <- tgt_v[last_obs_pos]   # strictly positive when use_log

  fc_keys <- integer(h)
  ly <- last_tgt_key %/% 10L
  lq <- last_tgt_key %% 10L
  for (i in seq_len(h)) {
    lq <- lq + 1L
    if (lq > 4L) { lq <- 1L; ly <- ly + 1L }
    fc_keys[i] <- ly * 10L + lq
  }

  # Indicator growth feeding each forecast quarter. We need the indicator's
  # quarter level relative to the previous quarter's full level; partial
  # quarters (1-2 months observed) get a partial mean and are flagged so we
  # can widen the interval to reflect the carry-forward uncertainty.
  level_central <- last_level
  rows <- vector("list", h)
  for (i in seq_len(h)) {
    k   <- fc_keys[i]
    pos <- match(k, ind_q_keys)
    partial <- FALSE
    if (is.na(pos)) {
      # No indicator coverage at all for this quarter — carry the last
      # available indicator quarter forward and treat it as fully partial.
      pos <- length(ind_q_keys)
      partial <- TRUE
    } else if (!isTRUE(ind_nmonth[pos] >= 3L)) {
      partial <- TRUE   # 1-2 months observed: partial-quarter indicator
    }

    # Previous quarter's indicator level for the growth denominator: the
    # quarter immediately before k, else the last full indicator quarter.
    prev_key <- {
      pk_q <- (k %% 10L) - 1L; pk_y <- k %/% 10L
      if (pk_q < 1L) { pk_q <- 4L; pk_y <- pk_y - 1L }
      pk_y * 10L + pk_q
    }
    prev_pos <- match(prev_key, ind_q_keys)
    if (is.na(prev_pos)) prev_pos <- max(pos - 1L, 1L)

    ind_now  <- ind_means[pos]
    ind_prev <- ind_means[prev_pos]
    dx_val <- if (use_log) log(ind_now) - log(ind_prev)
              else ind_now - ind_prev
    if (!is.finite(dx_val)) dx_val <- 0  # flat fallback

    pred <- stats::predict(
      fit, newdata = data.frame(dx = dx_val),
      interval = "prediction", level = level / 100
    )
    dy_hat <- pred[1, "fit"]
    dy_lo  <- pred[1, "lwr"]
    dy_hi  <- pred[1, "upr"]

    # Widen the growth interval for partial-quarter points: the indicator
    # we fed in is a carry-forward / partial mean, so the realised quarter
    # could still move. Inflate the half-width by 50% around the central
    # growth before mapping back to levels.
    if (partial) {
      half_lo <- (dy_hat - dy_lo) * 1.5
      half_hi <- (dy_hi - dy_hat) * 1.5
      dy_lo <- dy_hat - half_lo
      dy_hi <- dy_hat + half_hi
    }

    # Reconstruct levels by applying growth to the running central level.
    if (use_log) {
      level_central <- level_central * exp(dy_hat)
      level_lower   <- level_central * exp(dy_lo - dy_hat)
      level_upper   <- level_central * exp(dy_hi - dy_hat)
    } else {
      level_central <- level_central + dy_hat
      level_lower   <- level_central + (dy_lo - dy_hat)
      level_upper   <- level_central + (dy_hi - dy_hat)
    }

    yr <- k %/% 10L; qn <- k %% 10L
    rows[[i]] <- tibble::tibble(
      variable = variable,
      # Match forecast_one()'s `quarter` column type — tsibble yearquarter.
      quarter  = tsibble::yearquarter(sprintf("%d Q%d", yr, qn)),
      central  = unname(level_central),
      lower    = unname(level_lower),
      upper    = unname(level_upper),
      method   = sprintf("bridge_monthly[%s]", indicator_name)
    )
  }
  out <- dplyr::bind_rows(rows)

  # Finite guard — same contract as forecast_one(): never hand a non-finite
  # central value (or inverted band) back to the splice / MARTIN solve.
  if (!all(is.finite(out$central))) {
    stop("bridge_monthly for `", variable, "` produced a non-finite ",
         "central forecast.", call. = FALSE)
  }
  if (!all(is.finite(out$lower) & is.finite(out$upper) &
           out$lower <= out$central & out$central <= out$upper)) {
    stop("bridge_monthly for `", variable, "` produced an invalid forecast ",
         "interval (non-finite or not bracketing the central path).",
         call. = FALSE)
  }
  out
}

#' Splice nowcast forecasts back into a MARTIN-shape database
#'
#' Writes the `central` forecast value into the matching `[year, quarter]`
#' cells of each handover variable. Uses bimets per-cell assignment, the
#' same pattern `martin::solve_martin()` uses to inject add-factors.
#'
#' By default a forecast does **not** clobber an already-observed (non-NA)
#' cell — only NA cells and genuinely new (extended) forecast quarters are
#' filled. This protects historical data from being silently overwritten by
#' a model estimate. Pass `overwrite = TRUE` to force the old behaviour
#' (overwrite even observed cells), e.g. when nowcast was deliberately run
#' to *replace* cells known to be stale provisional prints.
#'
#' If a forecast quarter is past the end of the existing bimets ts, the ts
#' is extended via `bimets::TSEXTEND`. The first forecast quarter must be
#' contiguous with the series' last observation: if there is a gap (a
#' missing quarter between the last observation and the first forecast),
#' that's an error — the caller has a sequencing bug, and silently carrying
#' a value across the gap would corrupt the database.
#'
#' @param database A named list of `bimets::TIMESERIES`.
#' @param handover A tibble from [nowcast_handover()].
#' @param overwrite Logical. If `FALSE` (default), already-observed non-NA
#'   cells are left untouched and only NA / new forecast cells are filled.
#'   If `TRUE`, observed cells are overwritten too.
#' @return The updated database.
#' @export
splice_handover <- function(database, handover, overwrite = FALSE) {
  required <- c("variable", "quarter", "central")
  missing <- setdiff(required, names(handover))
  if (length(missing)) {
    stop("`handover` is missing required columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  for (var in unique(handover$variable)) {
    if (is.null(database[[var]])) {
      stop("Database has no series for `", var, "`. ",
           "Add it before splicing.", call. = FALSE)
    }
    sub <- handover[handover$variable == var, , drop = FALSE]
    sub <- sub[order(sub$quarter), , drop = FALSE]
    database[[var]] <- splice_one(database[[var]], sub, variable = var,
                                  overwrite = overwrite)
  }
  database
}

# Splice one variable's forecasts into one bimets ts. Extends the ts if the
# forecast quarters run past the current end. Refuses to (a) write a
# non-finite central value, (b) carry a value across a gap between the last
# observation and the first forecast quarter, or (c) clobber an observed
# non-NA cell unless `overwrite = TRUE`.
splice_one <- function(ts, sub, variable, overwrite = FALSE) {
  out <- ts
  vals    <- as.numeric(out)
  obs_idx <- which(!is.na(vals))
  if (length(obs_idx) == 0L) {
    stop("Series `", variable, "` is entirely NA; nothing to splice onto.",
         call. = FALSE)
  }

  # Decimal-time index of the last observation, and the contiguous gap
  # check for the first forecast quarter.
  t_idx       <- as.numeric(stats::time(out))
  last_obs_dec <- t_idx[max(obs_idx)]
  first_q      <- sub$quarter[1]
  first_year   <- as.integer(format(first_q, "%Y"))
  first_qnum   <- as.integer(substr(format(first_q), 7, 7))
  first_dec    <- first_year + (first_qnum - 1) / 4
  # The first forecast quarter must be the last observation itself
  # (re-nowcasting a provisional print) or the very next quarter. A larger
  # jump means a missing quarter in between — a sequencing bug.
  if (first_dec > last_obs_dec + 0.25 + 1e-9) {
    stop("Splice for `", variable, "` would carry a value across a gap: ",
         "the first forecast quarter (", format(first_q), ") is not ",
         "contiguous with the series' last observation. The caller ",
         "probably has a sequencing bug.", call. = FALSE)
  }

  for (i in seq_len(nrow(sub))) {
    q       <- sub$quarter[i]
    year    <- as.integer(format(q, "%Y"))
    qnum    <- as.integer(substr(format(q), 7, 7))
    val     <- sub$central[i]

    # Never write a non-finite central value into the database.
    if (!is.finite(val)) {
      stop("Refusing to splice a non-finite forecast for `", variable,
           "` at ", format(q), ".", call. = FALSE)
    }

    tsp_now    <- stats::tsp(out)
    end_dec    <- tsp_now[2]
    target_dec <- year + (qnum - 1) / 4

    if (target_dec > end_dec + 1e-9) {
      # Genuinely new quarter past the series end: extend storage and write
      # the value in one step. (No observed value can exist here.)
      out <- bimets::TSEXTEND(
        out,
        UPTO    = c(year, qnum),
        EXTMODE = "MYCONST",
        FACTOR  = val
      )
      next  # TSEXTEND with MYCONST = central already wrote the value
    }

    # In-range cell: respect the overwrite guard. Skip if a non-NA value is
    # already present and we are not in overwrite mode.
    if (!overwrite) {
      existing <- out[[year, qnum]]
      if (!is.na(existing)) next
    }
    out[[year, qnum]] <- val
  }
  out
}
