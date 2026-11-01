# Monthly-indicator bridge equation demonstration.
#
# Shows how nowcast's method = "bridge_monthly" uses a partial-quarter
# monthly indicator to nowcast a quarterly target before its quarter
# closes. Two bridges are demonstrated against live ABS data:
#
#   RC (real household consumption, quarterly) ← RT (retail trade
#                                                   turnover, monthly)
#   Y  (real GDP, quarterly)                   ← HOURS (hours worked,
#                                                       monthly)
#
# Both indicators get released ~6 weeks earlier than the National
# Accounts they nowcast, so a partial-quarter retail-trade or
# hours-worked observation gives an earlier read on the quarterly
# aggregate than waiting for the National Accounts release.
#
# Run:
#   Rscript scripts/monthly_bridge_demo.R

suppressPackageStartupMessages({
  for (p in c("judgement", "martin", "nowcast", "sibyldata")) {
    pkgload::load_all(file.path("packages", p), quiet = TRUE)
  }
})

dir.create("scripts/output", showWarnings = FALSE, recursive = TRUE)
log_path <- "scripts/output/monthly_bridge_demo.txt"
log_con  <- file(log_path, "w")
say <- function(...) {
  msg <- paste0(..., "\n")
  cat(msg); cat(msg, file = log_con, append = TRUE)
}

say("=== Monthly-indicator bridge demo ===")
say("Pulling live ABS / RBA / FRED panel ...")
panel <- suppressWarnings(sibyldata::update_data(sources = "all"))
db    <- suppressWarnings(sibyldata::to_martin_database(panel))

# Get the monthly indicators (RT, HOURS, LE) as raw monthly bimets ts.
mi <- sibyldata::nowcast_monthly_indicators(
  panel, vars = c("RT", "HOURS", "LE")
)
for (v in names(mi)) {
  x <- mi[[v]]; tsp <- stats::tsp(x)
  say(sprintf("  %-6s monthly: %.2f-%.2f  n=%d",
              v, tsp[1], tsp[2], length(as.numeric(x))))
}
say("")

# Configure bridges
indicator_map <- list(RC = "RT", Y = "HOURS", LE = "LE")
targets       <- c("RC", "Y", "LE")
horizons      <- 2

# Helper: show last-observed quarter of target and the partial-quarter
# coverage of its mapped indicator.
say("Last observed target quarter and indicator coverage:")
for (tgt in targets) {
  ind_name <- indicator_map[[tgt]]
  tgt_ts   <- db[[tgt]]
  ind_ts   <- mi[[ind_name]]
  if (is.null(tgt_ts) || is.null(ind_ts)) {
    say(sprintf("  %-3s : input missing", tgt))
    next
  }
  tgt_v <- as.numeric(tgt_ts); tgt_tsp <- stats::tsp(tgt_ts)
  last_tgt_idx <- max(which(!is.na(tgt_v)))
  last_tgt_dec <- tgt_tsp[1] + (last_tgt_idx - 1) / 4
  ind_tsp <- stats::tsp(ind_ts)
  say(sprintf("  %-3s : target ends %.2f  | %-5s ends %.2f (%d months past target)",
              tgt, last_tgt_dec, ind_name, ind_tsp[2],
              round((ind_tsp[2] - last_tgt_dec) * 12)))
}
say("")

# Run bridge_monthly forecasts
say("Bridge-monthly nowcasts (2-quarter horizon):")
say("")
out_bridge <- nowcast::nowcast_handover(
  db, h = horizons, method = "bridge_monthly",
  variables = targets,
  bridge_indicators  = indicator_map,
  monthly_indicators = mi
)
print(out_bridge[, c("variable", "quarter", "central", "method")])
say("")

# Compare against the ARIMA baseline (univariate, no monthly info)
say("ARIMA baseline (univariate, ignores monthly indicators):")
say("")
out_arima <- nowcast::nowcast_handover(
  db, h = horizons, method = "arima", variables = targets
)
print(out_arima[, c("variable", "quarter", "central", "method")])
say("")

# Side-by-side
say("Side-by-side (bridge vs ARIMA):")
say("")
m <- merge(
  out_bridge[, c("variable", "quarter", "central", "method")],
  out_arima[,  c("variable", "quarter", "central", "method")],
  by = c("variable", "quarter"),
  suffixes = c("_bridge", "_arima")
)
m$diff_pct <- 100 * (m$central_bridge - m$central_arima) / abs(m$central_arima)
print(m[, c("variable", "quarter", "central_bridge", "central_arima",
            "diff_pct")])
say("")
say(sprintf("Report saved to %s", log_path))
close(log_con)
