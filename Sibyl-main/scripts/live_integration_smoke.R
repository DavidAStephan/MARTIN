# Live-data integration smoke test.
#
# Pulls fresh data from every implemented source, runs it through the
# sibyldata pipeline, reports what materialised and what's still missing,
# and (optionally) attempts a partial MARTIN solve to see how far the
# pipeline gets end-to-end against real-time data.
#
# Run: Rscript scripts/live_integration_smoke.R
# Output: scripts/output/live_integration_report.txt + the report on stdout.

suppressPackageStartupMessages({
  for (p in c("judgement", "martin", "nowcast", "sibyldata")) {
    pkgload::load_all(file.path("packages", p), quiet = TRUE)
  }
})

dir.create("scripts/output", showWarnings = FALSE, recursive = TRUE)
log_path <- "scripts/output/live_integration_report.txt"
log_con <- file(log_path, "w")
say <- function(...) {
  msg <- paste0(..., "\n")
  cat(msg)
  cat(msg, file = log_con, append = TRUE)
}

withr::with_envvar(c(SIBYL_DATA_CACHE = tempfile("sibyl-smoke-")), {

  cat_df <- sibyldata::series_catalogue()
  say("=== SIBYL live-data integration smoke ===")
  say("Catalogue: ", nrow(cat_df), " rows across ",
      length(unique(cat_df$source)), " sources")
  say("Source breakdown:")
  for (src in sort(unique(cat_df$source))) {
    say(sprintf("  %-12s %d rows", src, sum(cat_df$source == src)))
  }
  say("")

  # 1) Fetch from each implemented source, time and report
  panels <- list()
  for (src in c("fred", "rba", "abs", "worldbank", "bom")) {
    n_expected <- sum(cat_df$source == src)
    if (n_expected == 0L) next
    say("Fetching ", src, " (", n_expected, " series expected) ...")
    t0 <- Sys.time()
    panel <- tryCatch(
      sibyldata:::fetch_source(src, vintage = Sys.Date()),
      error = function(e) {
        say("  ERROR: ", conditionMessage(e))
        NULL
      }
    )
    dt <- as.numeric(Sys.time() - t0, units = "secs")
    if (is.null(panel)) {
      say(sprintf("  %s: skipped after %.1fs", src, dt))
      next
    }
    n_obs    <- nrow(panel)
    n_series <- length(unique(panel$series_id))
    say(sprintf("  %s: %d rows, %d series, %.1fs",
                src, n_obs, n_series, dt))
    panels[[src]] <- panel
  }
  raw <- dplyr::bind_rows(panels)
  say("Total raw panel: ", nrow(raw), " rows from ",
      length(unique(raw$series_id)), " series across ",
      length(panels), " sources")
  say("")

  # 2) Pivot to MARTIN database
  say("Running to_martin_database() ...")
  t0 <- Sys.time()
  db <- sibyldata::to_martin_database(raw)
  dt <- as.numeric(Sys.time() - t0, units = "secs")
  say(sprintf("  produced %d MARTIN series in %.1fs", length(db), dt))

  added   <- attr(db, "derived_added")
  skipped <- attr(db, "skipped")
  say("  derived materialised:  ", length(added), " (",
      paste(added, collapse = ", "), ")")
  say("  no_data:               ",
      length(skipped$no_data %||% character()))
  say("  derived_no_inputs:     ",
      length(skipped$derived_no_inputs %||% character()))
  say("  derived_no_formula:    ",
      length(skipped$derived_no_formula %||% character()))
  say("  other_transforms:      ",
      length(skipped$other_transforms %||% character()))

  if (length(skipped$no_data %||% character()) > 0L) {
    say("  Direct rows with no data returned:")
    say("    ", paste(skipped$no_data, collapse = ", "))
  }
  say("")

  # 3) Compare against the fixture's universe so we know how much of MARTIN
  # the catalogue currently reaches.
  fixture <- martin::read_fixture()
  fixture_vars <- names(fixture)
  reachable    <- intersect(fixture_vars, names(db))
  missing      <- setdiff(fixture_vars, names(db))
  say("Fixture has ", length(fixture_vars), " MARTIN series; live pipeline ",
      "covers ", length(reachable), " of them (",
      sprintf("%.0f%%", 100 * length(reachable) / length(fixture_vars)),
      ")")
  say("Series the model needs that live data doesn't yet provide (",
      length(missing), "):")
  say("  ", paste(head(missing, 30), collapse = ", "),
      if (length(missing) > 30L) ", ...")
  say("")

  # 4) Try a real MARTIN solve by patching the live DB with fixture for
  # any missing variables. For series the live pipeline produces but with
  # a shorter history than the fixture, keep the fixture's longer series
  # (MARTIN's behavioural equations have TSRANGE going back to the 1960s
  # for some variables, which live ABS / RBA can't always reach).
  say("Attempting partial solve by merging live data with fixture ...")
  hybrid <- fixture
  for (v in names(db)) {
    if (is.null(hybrid[[v]])) {
      hybrid[[v]] <- db[[v]]
    } else if (length(as.numeric(db[[v]])) >=
                 length(as.numeric(hybrid[[v]]))) {
      hybrid[[v]] <- db[[v]]  # live is at least as long; use it
    }
    # else keep fixture (longer history)
  }
  t0 <- Sys.time()
  result <- tryCatch(
    martin::solve_martin(
      hybrid, NULL,
      horizon = c("2010Q1", "2018Q3"),
      scenario = "live_smoke"
    ),
    error = function(e) {
      say("  SOLVE FAILED: ", conditionMessage(e))
      NULL
    }
  )
  dt <- as.numeric(Sys.time() - t0, units = "secs")
  if (!is.null(result)) {
    say(sprintf("  solve_martin OK: %d rows, %d vars, %.1fs",
                nrow(result), length(unique(result$variable)), dt))
    for (v in c("Y", "RC", "GNE", "LUR", "PTM", "NCR")) {
      sub <- result[result$variable == v, ]
      if (nrow(sub) == 0L) next
      say(sprintf("    %-4s last=%s val=%.3f", v,
                  tail(sub$quarter, 1), tail(sub$value, 1)))
    }
  }

  `%||%` <- function(a, b) if (is.null(a)) b else a
})

say("")
say("Report written to ", log_path)
close(log_con)
