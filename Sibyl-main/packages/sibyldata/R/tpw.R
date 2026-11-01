# Trading-partner-weighted (TPW) world aggregates.
#
# MARTIN's WY / WP / WPX world variables represent Australia's external
# environment. The v0 catalogue uses FRED US proxies (GDPC1, GDPDEF,
# A020RD3Q086SBEA) which are *coarse* approximations — the US is only
# ~5% of Australia's two-way trade. A proper TPW aggregate weights each
# partner by Australia's bilateral trade share and combines per-partner
# series into a single index.
#
# This module ships:
#   * compute_tpw()         — pure-math weighted aggregate from per-
#                             partner ts + weights
#   * tpw_partner_weights() — the partner-weight vector currently in use
#   * build_tpw_cpi()       — opt-in WP build using OECD partner CPI
#
# The catalogue does **not** route WY/WP/WPX through this layer yet;
# build_tpw_cpi() runs as an opt-in alternative until per-variable OECD
# keys (GDP, export-price) are sorted. See next_session.md.

#' Partner trade-share weights for Australia
#'
#' Returns a named numeric vector of Australia's top trading-partner
#' weights, summing to 1. These are based on ABS table 5368.0 export
#' shares averaged 2022-2024 with small adjustments to renormalise after
#' dropping non-OECD-coverable partners (Taiwan, ASEAN ex-SG/TH). For a
#' v0 build, treat these as fixed. A future iteration would refresh them
#' from live ABS data with a rolling window.
#'
#' @param scheme One of `"goods_exports"` (default) or `"two_way"`.
#'   Goods-exports weights are dominated by China + East Asia commodity
#'   demand. Two-way (imports + exports) is more US/UK heavy.
#' @return Named numeric vector. Names are 3-letter ISO country codes
#'   matching OECD's REF_AREA values.
#' @export
tpw_partner_weights <- function(scheme = c("goods_exports", "two_way")) {
  scheme <- match.arg(scheme)
  if (scheme == "goods_exports") {
    # ABS 5368.0 goods exports by country, 2022-2024 average,
    # renormalised to sum to 1 after dropping Taiwan (no OECD QNA).
    w <- c(
      CHN = 0.41,  # China (~35% raw, +6pp from TWN reallocation)
      JPN = 0.15,
      KOR = 0.09,
      USA = 0.06,
      IND = 0.06,
      NZL = 0.04,
      GBR = 0.03,
      DEU = 0.02,
      OECD_OTHER = 0.14  # residual (FRA, ITA, NLD, SGP, THA, MYS, ...)
    )
  } else {
    # Two-way trade weights (goods + services, both directions),
    # closer to the RBA TWI methodology.
    w <- c(
      CHN = 0.27,
      USA = 0.12,
      JPN = 0.09,
      KOR = 0.05,
      GBR = 0.04,
      DEU = 0.03,
      NZL = 0.03,
      IND = 0.03,
      OECD_OTHER = 0.34
    )
  }
  w / sum(w)
}

#' Compute a trading-partner-weighted aggregate index
#'
#' Given per-partner time series and a partner-weight vector, builds a
#' weighted-average index normalised to 100 at `base_quarter`.
#'
#' Each partner series is independently normalised so that its value at
#' `base_quarter` equals 100; the aggregate is then
#' `sum_i weight_i * partner_i_index_t`. Partners with no observation
#' at `base_quarter` are dropped from the aggregate at that period
#' (their weight reallocated proportionally across remaining partners).
#'
#' @param partner_series Named list of `bimets::TIMESERIES` objects,
#'   one per partner. Names must match the names in `weights`.
#' @param weights Named numeric vector summing to ~1 (see
#'   [tpw_partner_weights()]).
#' @param base_quarter `"yyyyQq"` string identifying the base period for
#'   normalisation. Defaults to `"2010Q1"`.
#'
#' @return A `bimets::TIMESERIES` of the weighted-average index. NA
#'   where no partners contribute.
#' @export
compute_tpw <- function(partner_series, weights, base_quarter = "2010Q1") {
  stopifnot(
    is.list(partner_series), length(partner_series) >= 1L,
    is.numeric(weights), !is.null(names(weights))
  )
  if (abs(sum(weights) - 1) > 0.01) {
    warning(sprintf("[compute_tpw] weights sum to %.3f, not 1; ",
                    sum(weights)), "renormalising.", call. = FALSE)
    weights <- weights / sum(weights)
  }
  partners <- intersect(names(partner_series), names(weights))
  if (length(partners) == 0L) {
    stop("[compute_tpw] no overlap between partner_series and weights.",
         call. = FALSE)
  }

  # Each series's quarterly bimets ts → numeric, indexed by start.
  # Build a per-partner (date -> value) map and a global date set.
  base_yq <- parse_yyyyQq(base_quarter)
  base_year    <- base_yq$year
  base_quarter_i <- base_yq$quarter

  partner_index <- lapply(partners, function(p) {
    ts <- partner_series[[p]]
    if (!inherits(ts, "ts")) {
      warning(sprintf("[compute_tpw] partner %s: not a ts; skipping", p),
              call. = FALSE)
      return(NULL)
    }
    tsp <- stats::tsp(ts)
    s_year <- floor(tsp[1] + 1e-9)
    s_q    <- round((tsp[1] - s_year) * 4 + 1)
    vals   <- as.numeric(ts)
    # Quarter labels for each cell.
    n <- length(vals)
    quarters <- vapply(seq_len(n), function(i) {
      abs_q <- s_year * 4L + (s_q - 1L) + (i - 1L)
      sprintf("%04dQ%d", abs_q %/% 4L, (abs_q %% 4L) + 1L)
    }, character(1))
    base_v <- vals[quarters == base_quarter]
    if (length(base_v) == 0L || !is.finite(base_v) || base_v == 0) {
      warning(sprintf(
        "[compute_tpw] partner %s: no usable observation at %s; dropped.",
        p, base_quarter), call. = FALSE)
      return(NULL)
    }
    setNames(100 * vals / base_v, quarters)
  })
  names(partner_index) <- partners
  partner_index <- partner_index[!vapply(partner_index, is.null,
                                          logical(1))]
  if (length(partner_index) == 0L) {
    stop("[compute_tpw] no partners have data at the base quarter.",
         call. = FALSE)
  }

  all_quarters <- sort(unique(unlist(lapply(partner_index, names))))
  out <- numeric(length(all_quarters))
  for (i in seq_along(all_quarters)) {
    q <- all_quarters[i]
    contributions <- vapply(names(partner_index), function(p) {
      # `[q]` on a named numeric returns NA for missing names (vs `[[q]]`
      # which errors).
      v <- partner_index[[p]][q]
      if (is.na(v) || !is.finite(v)) NA_real_ else unname(v)
    }, numeric(1))
    keep <- !is.na(contributions)
    if (!any(keep)) {
      out[i] <- NA_real_
      next
    }
    w <- weights[names(partner_index)[keep]]
    w <- w / sum(w)
    out[i] <- sum(w * contributions[keep])
  }

  first_q <- all_quarters[1]
  first_yq <- parse_yyyyQq(first_q)
  bimets::TIMESERIES(
    out,
    START = c(first_yq$year, first_yq$quarter),
    FREQ  = 4
  )
}

#' Build a trading-partner-weighted CPI index via OECD
#'
#' Fetches monthly CPI growth-rate-over-1-year for each partner from
#' OECD's prices dataflow, aggregates monthly to quarterly, weighted by
#' [tpw_partner_weights()]. Returns a quarterly bimets ts suitable as a
#' WP proxy.
#'
#' **Status:** working v0 for WP only. GDP (WY) and export-price (WPX)
#' equivalents need their OECD QNA / trade dataflow keys figured out
#' (the QNA key shape is a 13-position vector that varies by which
#' measure is selected — see next_session.md item 2).
#'
#' @param weights Optional override for [tpw_partner_weights()].
#' @param observation_start Date passed through to [fetch_oecd()].
#' @param base_quarter Base for the index. Default "2010Q1".
#'
#' @return A `bimets::TIMESERIES` quarterly index ~100 at base_quarter,
#'   or `NULL` if no partner data could be fetched.
#' @export
build_tpw_cpi <- function(weights           = tpw_partner_weights(),
                          observation_start = "2000-01-01",
                          base_quarter      = "2010Q1") {
  # OECD prices dataflow: monthly CPI INDEX (not growth rate) per
  # partner. Index levels compose under weighted averaging the way a
  # "world price index" intuitively should; growth rates do not.
  countries <- setdiff(names(weights), "OECD_OTHER")
  ids <- sprintf(
    "OECD.SDD.TPS,DSD_PRICES@DF_PRICES_ALL,1.0/%s.M.N.CPI.IX._T.N._Z",
    countries
  )
  panel <- fetch_oecd(ids, observation_start = observation_start)
  if (nrow(panel) == 0L) {
    warning("[build_tpw_cpi] no OECD data returned for any partner.",
            call. = FALSE)
    return(NULL)
  }
  # Strip non-data rows (OECD CSV headers leak as the first row).
  panel <- panel[!is.na(panel$value) & is.finite(panel$value), , drop = FALSE]
  # Aggregate monthly -> quarterly: quarter date = first month of quarter.
  panel$quarter <- as.Date(format(panel$date, "%Y-%m-01"))
  panel$quarter <- as.Date(sprintf(
    "%04d-%02d-01",
    as.integer(format(panel$quarter, "%Y")),
    ((as.integer(format(panel$quarter, "%m")) - 1L) %/% 3L) * 3L + 1L
  ))
  agg <- panel |>
    dplyr::group_by(series_id, quarter) |>
    dplyr::summarise(value = mean(value, na.rm = TRUE), .groups = "drop")

  # Map back from series_id to country code (first dot-segment of the key).
  agg$country <- sub("^.*/([A-Z]{3})\\..*$", "\\1", agg$series_id)

  # Build per-partner bimets ts indexed by country.
  partner_series <- list()
  for (cc in unique(agg$country)) {
    sub <- agg[agg$country == cc, ]
    sub <- sub[order(sub$quarter), ]
    if (nrow(sub) < 4L) next
    first <- sub$quarter[1]
    start_year <- as.integer(format(first, "%Y"))
    start_q    <- ((as.integer(format(first, "%m")) - 1L) %/% 3L) + 1L
    partner_series[[cc]] <- bimets::TIMESERIES(
      sub$value, START = c(start_year, start_q), FREQ = 4
    )
  }
  if (length(partner_series) == 0L) {
    warning("[build_tpw_cpi] no partner ts could be built.", call. = FALSE)
    return(NULL)
  }

  compute_tpw(partner_series, weights, base_quarter = base_quarter)
}
