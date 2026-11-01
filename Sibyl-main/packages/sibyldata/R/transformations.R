# Transformation handlers for non-`direct` catalogue rows.
#
# Each handler takes a partially-built database (named list of bimets
# TIMESERIES) and the catalogue, mutates the database, and returns it.
# The post-direct pipeline in to_martin_database() composes them in order:
#
#   direct pivot -> level_from_pct -> spliced -> chow_lin -> PIM -> derived
#
# Each handler is responsible for:
#   * resolving its slice of the catalogue (by `transformation` tag),
#   * pulling whatever upstream inputs it needs from the database,
#   * writing the resulting bimets ts back to the database under the
#     correct `martin_var` key.
#
# All handlers are intentionally idempotent: if their output is already in
# the database, they leave it alone. This makes them safe to call multiple
# times (which the fixed-point loop in add_derived_series() exploits) and
# safe to compose with user-supplied data that's already cumulated/spliced.

# ---- level_from_pct -------------------------------------------------------

# Base values lifted from
# references/MARTIN-master/Programs/modify_data.prg. The script there
# replaces the percent-change series with a level series cumulated forward
# from the base quarter; we do the same.
LEVEL_FROM_PCT_BASES <- list(
  PTM = list(base = 29.83452468, base_quarter = "1982Q1"),
  P   = list(base = 100,         base_quarter = "1982Q1"),
  # PEX is cumulated from a 1982Q1 base of 100 in modify_data.prg:54-58
  # (the PEXL series, which then replaces PEX via `rename pexl pex`).
  PEX = list(base = 100,         base_quarter = "1982Q1")
)

#' Convert percent-change series to level series
#'
#' For every row tagged `transformation = "level_from_pct"` whose
#' `martin_var` matches an entry in [LEVEL_FROM_PCT_BASES], replaces the
#' percent-change series with a level index cumulated from the base.
#'
#' @param database Named list of bimets TIMESERIES.
#' @param catalogue [series_catalogue()] subset (or full catalogue).
#' @return The database with PTM and P (where present) replaced by level
#'   series.
#' @keywords internal
apply_level_from_pct <- function(database, catalogue) {
  rows <- catalogue[catalogue$transformation == "level_from_pct",
                    , drop = FALSE]
  for (i in seq_len(nrow(rows))) {
    mv <- rows$martin_var[i]
    base_cfg <- LEVEL_FROM_PCT_BASES[[mv]]
    if (is.null(base_cfg)) next  # no registered base; leave as pct
    if (is.null(database[[mv]])) next  # not in database
    database[[mv]] <- cumulate_pct_to_level(
      database[[mv]],
      base         = base_cfg$base,
      base_quarter = base_cfg$base_quarter
    )
  }
  database
}

# Cumulate a quarterly percent-change ts into a level ts starting at a
# given (base, base_quarter). Quarters strictly before base_quarter become
# NA; the base quarter takes the base value; subsequent quarters multiply
# by (1 + pct/100) compounded.
#
# When `base_quarter` falls before the start of `pct_ts` (e.g. live data
# starts after the catalogued base), we still cumulate the level: the
# first quarter of `pct_ts` is treated as if the base value had been
# compounded forward by the first pct change. This loses information for
# the gap quarters between base_quarter and ts start (we have no pct
# values there) but keeps the index consistent with the catalogued base.
cumulate_pct_to_level <- function(pct_ts, base, base_quarter) {
  yq <- parse_yyyyQq(base_quarter)
  base_dec <- yq$year + (yq$quarter - 1) / 4

  tsp <- stats::tsp(pct_ts)
  start_dec <- tsp[1]
  end_dec   <- tsp[2]

  times <- seq(start_dec, end_dec, by = 1 / 4)
  n     <- length(times)
  vals  <- as.numeric(pct_ts)

  out <- rep(NA_real_, n)
  base_idx <- which(abs(times - base_dec) < 1e-6)

  if (length(base_idx) > 0L) {
    # Standard case: base_quarter is in the ts.
    out[base_idx] <- base
    start_recursion <- base_idx + 1L
  } else if (base_dec < start_dec) {
    # base_quarter precedes the ts: cumulate from start_dec as base *
    # (1 + first_pct/100) — pretend the gap quarters had no contribution.
    if (!is.na(vals[1])) {
      out[1] <- base * (1 + vals[1] / 100)
      start_recursion <- 2L
    } else {
      return(pct_ts)
    }
  } else {
    # base_quarter is after the ts end — can't cumulate from inside the ts.
    return(pct_ts)
  }

  for (i in seq(start_recursion, n)) {
    pct <- vals[i]
    out[i] <- if (is.na(pct) || is.na(out[i - 1])) NA_real_
              else out[i - 1] * (1 + pct / 100)
  }

  start_year    <- floor(start_dec + 1e-9)
  start_quarter <- round((start_dec - start_year) * 4 + 1)
  bimets::TIMESERIES(out, START = c(start_year, start_quarter), FREQ = 4)
}

# Internal helper duplicated locally; the judgement::: variant would be
# cleaner but creating a sibyldata->judgement dep just for this is
# disproportionate.
parse_yyyyQq <- function(x) {
  list(
    year    = as.integer(substr(x, 1, 4)),
    quarter = as.integer(substr(x, 6, 6))
  )
}

# ---- spliced --------------------------------------------------------------

# Hardcoded splice operations from modify_data.prg. Simpler than encoding
# direction + target in the catalogue, and the set is small enough to live
# in code.
#
# `target`: the series to be (re-)created from the splice
# `source`: the catalogue entry providing the splice payload
# `direction`: 'forward' extends target by changes in source from target's
#              last observation; 'backward' fills target's missing past
#              by scaling source's values to align at the first overlap.
SPLICE_REGISTRY <- list(
  list(target = "NCR", source = "NCR_HIST",   direction = "backward"),
  list(target = "NBR", source = "NBR_SPLICE", direction = "forward"),
  # PH from ABS 6416 starts ~2002; PH_OLD (the legacy established-house-price
  # series) reaches back to ~1986. Backward-splice for compatibility with
  # MARTIN's ID, PH, OTC equations which need RPH = PH / PTM back into the
  # 1980s. Lifted from modify_data.prg's PH backcast loop.
  list(target = "PH",  source = "PH_OLD",     direction = "backward")
)

#' Apply registered splice operations
#'
#' For each entry in [SPLICE_REGISTRY], reads the source series and either
#' backfills the target's earlier-than-data history or extends it
#' forward, using the standard EViews splice rules from
#' `modify_data.prg`. The resulting series replaces the target in the
#' database. If the source is missing, the splice is skipped.
#'
#' @param database Named list of bimets ts.
#' @param catalogue [series_catalogue()] (unused for now but reserved for
#'   future registry-from-catalogue migration).
#' @keywords internal
apply_splices <- function(database, catalogue) {
  for (op in SPLICE_REGISTRY) {
    src <- database[[op$source]]
    if (is.null(src)) next
    tgt <- database[[op$target]]
    if (is.null(tgt)) {
      # No existing target. Treat the source as the target (rename-style
      # splice — what happens when the legacy direct series for the target
      # is deprecated, e.g. NBR's F05_FILRLBWAV).
      database[[op$target]] <- src
      next
    }
    database[[op$target]] <- splice_series(tgt, src, direction = op$direction)
  }
  database
}

# Splice `src` into `tgt` (`forward` or `backward`). Returns a bimets ts
# covering the union of tgt's and src's time spans where data is available.
splice_series <- function(tgt, src, direction = c("forward", "backward")) {
  direction <- match.arg(direction)
  tgt_v <- as.numeric(tgt)
  src_v <- as.numeric(src)

  tgt_t <- as.numeric(stats::time(tgt))
  src_t <- as.numeric(stats::time(src))

  # Build aligned union grid
  all_t <- sort(union(tgt_t, src_t))
  tgt_aligned <- rep(NA_real_, length(all_t))
  src_aligned <- rep(NA_real_, length(all_t))
  tgt_aligned[match(tgt_t, all_t)] <- tgt_v
  src_aligned[match(src_t, all_t)] <- src_v

  out <- tgt_aligned

  if (direction == "backward") {
    # Find the first index where target is observed
    first_obs <- suppressWarnings(min(which(!is.na(out))))
    if (!is.finite(first_obs)) return(tgt)
    # Walk backward filling from src using a constant ratio at first_obs
    if (first_obs > 1L && !is.na(src_aligned[first_obs]) &&
        src_aligned[first_obs] != 0) {
      ratio <- out[first_obs] / src_aligned[first_obs]
      for (i in seq(first_obs - 1L, 1L)) {
        if (is.na(src_aligned[i])) next
        out[i] <- src_aligned[i] * ratio
      }
    }
  } else {  # forward
    last_obs <- suppressWarnings(max(which(!is.na(out))))
    if (!is.finite(last_obs)) return(tgt)
    # Extend by changes in src from the source value at last_obs
    if (last_obs < length(out) && !is.na(src_aligned[last_obs])) {
      for (i in seq(last_obs + 1L, length(out))) {
        if (is.na(src_aligned[i]) || is.na(src_aligned[i - 1L])) next
        out[i] <- out[i - 1L] + (src_aligned[i] - src_aligned[i - 1L])
      }
    }
  }

  start_dec <- all_t[1]
  start_year    <- floor(start_dec + 1e-9)
  start_quarter <- round((start_dec - start_year) * 4 + 1)
  bimets::TIMESERIES(out, START = c(start_year, start_quarter), FREQ = 4)
}

# ---- PIM (perpetual inventory method) ------------------------------------

# Hardcoded PIM-style accumulations. KV (the only one for v0) accumulates
# the change-in-inventories series V from a base value at a base quarter.
# Lifted from modify_data.prg:
#   smpl 1980q1 1980q1
#   series KV = 134865
#   smpl 1980q2 @last
#   kv=kv(-1)+v
PIM_REGISTRY <- list(
  KV = list(input = "V", base = 134865, base_quarter = "1980Q1")
)

#' Apply perpetual-inventory accumulations
#'
#' For each entry in [PIM_REGISTRY], constructs the level series by
#' integrating the change series from the registered base. Skips if the
#' input is missing or the output is already in the database.
#'
#' @param database Named list of bimets ts.
#' @param catalogue [series_catalogue()] (unused for now).
#' @keywords internal
apply_pim <- function(database, catalogue) {
  for (mv in names(PIM_REGISTRY)) {
    if (!is.null(database[[mv]])) next  # already there
    cfg <- PIM_REGISTRY[[mv]]
    inp <- database[[cfg$input]]
    if (is.null(inp)) next
    database[[mv]] <- pim_accumulate(inp, base = cfg$base,
                                     base_quarter = cfg$base_quarter)
  }
  database
}

# Integrate a change series into a level series from a base. Quarters
# before base_quarter become NA.
pim_accumulate <- function(change_ts, base, base_quarter) {
  yq <- parse_yyyyQq(base_quarter)
  base_dec <- yq$year + (yq$quarter - 1) / 4

  tsp <- stats::tsp(change_ts)
  start_dec <- tsp[1]
  end_dec   <- tsp[2]
  times <- seq(start_dec, end_dec, by = 1 / 4)
  vals  <- as.numeric(change_ts)

  out <- rep(NA_real_, length(times))
  base_idx <- which(abs(times - base_dec) < 1e-6)
  if (length(base_idx) == 0L) return(NULL)
  out[base_idx] <- base
  if (base_idx < length(times)) {
    for (i in seq(base_idx + 1L, length(times))) {
      out[i] <- if (is.na(out[i - 1L]) || is.na(vals[i])) NA_real_
                else out[i - 1L] + vals[i]
    }
  }
  start_year    <- floor(start_dec + 1e-9)
  start_quarter <- round((start_dec - start_year) * 4 + 1)
  bimets::TIMESERIES(out, START = c(start_year, start_quarter), FREQ = 4)
}

# ---- Chow-Lin (annual -> quarterly) --------------------------------------

#' Apply Chow-Lin annual-to-quarterly interpolation
#'
#' For each row tagged `transformation = "chowlin"`, takes the annual panel
#' (one observation per fiscal year) and produces a quarterly series via
#' `tempdisagg::td()`. When a related quarterly series is available as an
#' indicator (e.g. IBRE_CAPEX for IBRE), Chow-Lin uses it; otherwise falls
#' back to a constant-indicator Denton interpolation.
#'
#' @param database Named list of bimets ts.
#' @param annual_rows Tibble of `(martin_var, source_id, ...)` for the
#'   chowlin slice, already pivoted to bimets ts in `annual_db` (one cell
#'   per year).
#' @param annual_db Named list of annual bimets ts keyed by `martin_var`.
#' @param catalogue [series_catalogue()].
#' @keywords internal
apply_chowlin <- function(database, annual_db, catalogue) {
  if (length(annual_db) == 0L) return(database)
  if (!requireNamespace("tempdisagg", quietly = TRUE)) {
    warning("tempdisagg not installed; Chow-Lin rows will be skipped.",
            call. = FALSE)
    return(database)
  }

  # Map of annual martin_var -> quarterly indicator martin_var (where
  # known). Lifted from references/MARTIN-master/Programs/modify_data.prg.
  CHOWLIN_INDICATORS <- list(
    IBRE  = "IBRE_CAPEX",
    NIBRE = "NIBRE_CAPEX",
    KIBRE = NULL,
    KID   = NULL,
    KTOT  = NULL,
    KOTC  = NULL
  )

  for (mv in names(annual_db)) {
    if (!is.null(database[[mv]])) next
    annual_ts <- annual_db[[mv]]
    indicator_mv <- CHOWLIN_INDICATORS[[mv]]
    indicator_ts <- if (!is.null(indicator_mv)) database[[indicator_mv]] else NULL

    qrt <- try(chowlin_one(annual_ts, indicator_ts), silent = TRUE)
    if (!inherits(qrt, "try-error")) database[[mv]] <- qrt
  }
  database
}

# Disaggregate one annual ts to quarterly. If indicator is supplied and
# overlaps, use Chow-Lin; otherwise constant-indicator Denton.
chowlin_one <- function(annual_ts, indicator_ts = NULL) {
  # tempdisagg expects ts of frequency 1 for annual input; convert.
  vals <- as.numeric(annual_ts)
  tsp <- stats::tsp(annual_ts)
  start_year <- floor(tsp[1] + 1e-9)
  annual <- stats::ts(vals[!is.na(vals)],
                      start = start_year + sum(is.na(vals[seq_along(vals)]) &
                                                 cumprod(is.na(vals)) > 0L),
                      frequency = 1)
  if (length(annual) < 3L) return(NULL)

  fit <- if (!is.null(indicator_ts)) {
    tryCatch(
      tempdisagg::td(annual ~ indicator_ts, to = "quarterly",
                     method = "chow-lin-fixed", fixed.rho = 0.5),
      error = function(e) NULL
    )
  } else NULL

  if (is.null(fit)) {
    fit <- tempdisagg::td(annual ~ 1, to = "quarterly",
                          method = "denton-cholette",
                          conversion = "sum")
  }
  q_ts <- predict(fit)
  # Wrap as bimets ts; tempdisagg returns a base ts already.
  ttsp <- stats::tsp(q_ts)
  sy <- floor(ttsp[1] + 1e-9)
  sq <- round((ttsp[1] - sy) * 4 + 1)
  bimets::TIMESERIES(as.numeric(q_ts), START = c(sy, sq), FREQ = 4)
}
