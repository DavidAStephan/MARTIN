# SIBYL dashboard - narrative-to-projection.
#
# Single-file Shiny app. Loads pre-built pipeline state (baseline,
# database_with_handover, sensitivity_matrix, horizon, estimation_end)
# from the targets cache, then runs the LLM refinement loop and shows
# the result.
#
# Run:  Rscript app/run.R   (or: just dashboard)

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(plotly)
  library(ggplot2)
})

# DT gives us an editable review table for the human-approval gate. It is
# optional: if absent we fall back to a read-only HTML table + an explicit
# Approve button (the gate still functions, just without inline editing).
HAS_DT <- requireNamespace("DT", quietly = TRUE)

# ---- Startup: project root, packages, cache --------------------------------

project_root <- if (dir.exists("packages") && dir.exists("_targets")) {
  getwd()
} else if (dir.exists("../packages") && dir.exists("../_targets")) {
  normalizePath("..")
} else if (dir.exists("../../packages") && dir.exists("../../_targets")) {
  normalizePath("../..")
} else {
  stop("Could not locate the SIBYL project root from getwd()=",
       getwd(), ". Run from the project root or via `just dashboard`.")
}

for (pkg in c("sibyldata", "martin", "nowcast", "judgement")) {
  pkgload::load_all(file.path(project_root, "packages", pkg), quiet = TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

target_store <- file.path(project_root, "_targets")
required <- c("baseline", "database_with_handover", "horizon",
              "estimation_end", "sensitivity_matrix", "round_id")
available <- targets::tar_objects(store = target_store)
missing <- setdiff(required, available)
if (length(missing)) {
  stop("Targets cache missing: ", paste(missing, collapse = ", "),
       ". Run `just pipeline` first (from ", project_root, ").")
}
targets::tar_load(c(baseline, database_with_handover, horizon,
                    estimation_end, sensitivity_matrix, round_id),
                  store = target_store)

# Optional provenance inputs for the honesty footer. `data_source` records
# whether the cache was built from live sources or the bundled fixture;
# absent in older caches, so we load it defensively.
data_source <- if ("data_source" %in% available) {
  targets::tar_load(data_source, store = target_store)
  get("data_source")
} else {
  NA_character_
}

api_key_set <- nzchar(Sys.getenv("ANTHROPIC_API_KEY"))

# ---- Domain constants -------------------------------------------------------

HEADLINE <- c("Y", "RC", "GNE", "LUR", "PTM", "P", "NCR")

HEADLINE_LABELS <- c(
  Y   = "Real GDP",
  RC  = "Real consumption",
  GNE = "Real gross national expenditure",
  LUR = "Unemployment rate",
  PTM = "Trimmed-mean CPI",
  P   = "Headline CPI",
  NCR = "Nominal cash rate"
)

# Whether each headline variable is a rate (we show pp-diff in YoY mode)
# or a level/index (% growth). NCR is always rendered as a level regardless
# of the toggle.
HEADLINE_KIND <- c(
  Y   = "level",
  RC  = "level",
  GNE = "level",
  LUR = "rate",
  PTM = "level",
  P   = "level",
  NCR = "rate-locked"  # always shown as level
)

DEFAULT_NARRATIVE <- paste(
  "We expect Australian services inflation to remain sticky over the",
  "forecast horizon. Trimmed-mean inflation runs roughly 0.2 percentage",
  "points above baseline from 2026Q2 through 2027Q2, fading thereafter",
  "as labour-market conditions ease. The cash-rate path responds",
  "endogenously through the model's Taylor Rule."
)

# Quarter where the genuine projection period begins (just past the last
# quarter of hard data). DATA-DERIVED rather than hardcoded: we read the
# pipeline's documented forecast anchor where it exists, then fall back to a
# data-edge computed from the loaded database, and only then to a literal.
#
#  1. `attr(sensitivity_matrix, "shock_start")` is set by the pipeline to
#     "the start of the projection period (just after the last hard data)"
#     (see _targets.R), so it is the authoritative projection start.
#  2. Otherwise we infer the edge from `database_with_handover`: the modal
#     last-observed quarter of the *non-handover* (hard-data) series, advanced
#     one quarter. (Exogenous series are carried forward to the horizon end,
#     so we use the mode rather than the max to find the genuine data edge.)
#  3. Failing both, the documented literal anchor.

# Advance a "yyyyQq" quarter by `n` quarters (n may be negative).
shift_quarter <- function(q, n = 1L) {
  year <- as.integer(substr(q, 1, 4))
  qnum <- as.integer(substr(q, 6, 6))
  abs_q <- year * 4L + (qnum - 1L) + as.integer(n)
  sprintf("%04dQ%d", abs_q %/% 4L, (abs_q %% 4L) + 1L)
}

# Infer the last quarter of genuine hard data from the loaded database by
# taking the modal last-finite quarter across non-handover series. Returns a
# "yyyyQq" string or NA_character_ if it can't be determined.
infer_data_edge <- function(db, horizon_end) {
  hv <- tryCatch(nowcast::handover_variables(), error = function(e) character(0))
  non_hv <- setdiff(names(db), hv)
  if (length(non_hv) == 0L) return(NA_character_)
  last_finite_dec <- function(ts) {
    if (!inherits(ts, "ts")) return(NA_real_)
    v <- as.numeric(ts)
    t <- as.numeric(stats::time(ts))
    fin <- is.finite(v)
    if (!any(fin)) return(NA_real_)
    max(t[fin])
  }
  edges <- vapply(db[non_hv], last_finite_dec, numeric(1))
  edges <- edges[is.finite(edges)]
  if (length(edges) == 0L) return(NA_character_)
  # Exogenous series are padded to the horizon end; drop those so the mode
  # reflects the genuine data edge of the behavioural inputs.
  he <- quarter_to_decimal(horizon_end)
  inner <- edges[edges < he - 1e-9]
  pool <- if (length(inner) > 0L) inner else edges
  modal_dec <- as.numeric(names(sort(table(pool), decreasing = TRUE))[1])
  decimal_to_quarter(modal_dec)
}

quarter_to_decimal <- function(q) {
  year <- as.integer(substr(q, 1, 4))
  qnum <- as.integer(substr(q, 6, 6))
  year + (qnum - 1) / 4
}

decimal_to_quarter <- function(d) {
  year <- floor(d + 1e-9)
  qnum <- round((d - year) * 4 + 1)
  sprintf("%04dQ%d", year, qnum)
}

PROJECTION_START <- local({
  anchor <- attr(sensitivity_matrix, "shock_start")
  if (!is.null(anchor) && is.character(anchor) && length(anchor) == 1L &&
      nzchar(anchor) && grepl("^[0-9]{4}Q[1-4]$", anchor)) {
    anchor
  } else {
    edge <- infer_data_edge(database_with_handover, horizon[2])
    if (!is.na(edge)) shift_quarter(edge, 1L) else "2026Q1"
  }
})

# Brand palette - inspired by FT/BBG/RBA chart conventions.
COL_INK       <- "#0e1e2c"   # deep ink for text + axes
COL_PAPER     <- "#fbf9f6"   # warm off-white background
COL_RULE      <- "#dcd6cc"   # subtle horizontal rules
COL_MUTED     <- "#5e6b78"
COL_BASELINE  <- "#9aa6b1"
COL_SCENARIO  <- "#0b6a8a"   # deep teal
COL_ACCENT    <- "#c2884a"   # warm tan accent
COL_AGREE     <- "#1d7a3a"
COL_PARTIAL   <- "#b07a00"
COL_DISAGREE  <- "#a33a2a"

# ---- Theme + custom CSS -----------------------------------------------------

sibyl_theme <- bs_theme(
  version = 5,
  bg = COL_PAPER,
  fg = COL_INK,
  primary = COL_SCENARIO,
  secondary = COL_MUTED,
  success = COL_AGREE,
  info = COL_SCENARIO,
  warning = COL_PARTIAL,
  danger = COL_DISAGREE,
  base_font = font_collection(
    "ui-sans-serif", "system-ui", "-apple-system",
    "BlinkMacSystemFont", "Segoe UI", "Roboto",
    "Helvetica Neue", "Arial", "sans-serif"
  ),
  heading_font = font_collection(
    "ui-sans-serif", "system-ui", "-apple-system",
    "BlinkMacSystemFont", "Segoe UI", "Roboto",
    "Helvetica Neue", "Arial", "sans-serif"
  ),
  code_font = font_collection(
    "ui-monospace", "SFMono-Regular", "Menlo", "Monaco",
    "Consolas", "monospace"
  ),
  font_scale = 0.95
)

custom_css <- HTML(sprintf("
:root {
  --sibyl-ink:      %s;
  --sibyl-paper:    %s;
  --sibyl-rule:     %s;
  --sibyl-muted:    %s;
  --sibyl-baseline: %s;
  --sibyl-scenario: %s;
  --sibyl-accent:   %s;
  --sibyl-agree:    %s;
  --sibyl-partial:  %s;
  --sibyl-disagree: %s;
}
body, .navbar, .sidebar { background: var(--sibyl-paper) !important; }
.sibyl-app-header {
  background: var(--sibyl-ink);
  color: #fff;
  padding: 14px 28px 12px 28px;
  display: flex;
  align-items: baseline;
  gap: 18px;
  border-bottom: 3px solid var(--sibyl-accent);
}
.sibyl-app-title {
  font-size: 1.45rem;
  font-weight: 600;
  letter-spacing: 0.02em;
}
.sibyl-app-subtitle {
  font-size: 0.92rem;
  opacity: 0.78;
  font-weight: 400;
  letter-spacing: 0.01em;
}
.sibyl-app-meta {
  margin-left: auto;
  font-size: 0.78rem;
  opacity: 0.65;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}
.sibyl-sidebar-section {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--sibyl-muted);
  margin: 14px 0 6px 0;
  font-weight: 600;
}
.sibyl-status {
  font-size: 0.84rem;
  color: var(--sibyl-muted);
  border-left: 3px solid var(--sibyl-rule);
  padding: 8px 10px;
  background: rgba(0,0,0,0.02);
  border-radius: 0 4px 4px 0;
  min-height: 56px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  line-height: 1.4;
}
.sibyl-status-running {
  border-left-color: var(--sibyl-scenario);
  background: rgba(11,106,138,0.06);
  color: var(--sibyl-ink);
}
.sibyl-status-done {
  border-left-color: var(--sibyl-agree);
  background: rgba(29,122,58,0.06);
  color: var(--sibyl-ink);
}
.sibyl-status-error {
  border-left-color: var(--sibyl-disagree);
  background: rgba(163,58,42,0.08);
  color: var(--sibyl-ink);
}
.sibyl-cache-info {
  font-size: 0.76rem;
  color: var(--sibyl-muted);
  margin-top: 8px;
  line-height: 1.45;
  border-top: 1px dashed var(--sibyl-rule);
  padding-top: 10px;
}
.sibyl-cache-info b { color: var(--sibyl-ink); font-weight: 600; }
.sibyl-badge {
  display: inline-block;
  font-size: 0.72rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  padding: 3px 10px;
  border-radius: 20px;
  border: 1px solid;
}
.sibyl-badge-agree    { color: var(--sibyl-agree);    border-color: var(--sibyl-agree);    background: rgba(29,122,58,0.08); }
.sibyl-badge-partial  { color: var(--sibyl-partial);  border-color: var(--sibyl-partial);  background: rgba(176,122,0,0.10); }
.sibyl-badge-disagree { color: var(--sibyl-disagree); border-color: var(--sibyl-disagree); background: rgba(163,58,42,0.08); }
.sibyl-badge-neutral  { color: var(--sibyl-muted);    border-color: var(--sibyl-rule);    background: rgba(0,0,0,0.03); }
.sibyl-headline-row {
  display: flex;
  gap: 18px;
  flex-wrap: wrap;
  padding: 6px 0 14px 0;
  margin-bottom: 12px;
  border-bottom: 1px solid var(--sibyl-rule);
}
.sibyl-headline-card {
  flex: 1 1 130px;
  min-width: 130px;
  padding: 6px 0;
}
.sibyl-headline-label {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--sibyl-muted);
  font-weight: 600;
}
.sibyl-headline-value {
  font-size: 1.4rem;
  font-weight: 600;
  color: var(--sibyl-ink);
  line-height: 1.15;
  margin-top: 2px;
  font-variant-numeric: tabular-nums;
}
.sibyl-headline-delta {
  font-size: 0.82rem;
  margin-top: 1px;
  font-variant-numeric: tabular-nums;
}
.sibyl-delta-up   { color: var(--sibyl-disagree); }
.sibyl-delta-down { color: var(--sibyl-agree); }
.sibyl-delta-flat { color: var(--sibyl-muted); }
.sibyl-section-title {
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--sibyl-ink);
  margin: 16px 0 8px 0;
}
.sibyl-help-text {
  font-size: 0.84rem;
  color: var(--sibyl-muted);
  line-height: 1.55;
  margin-bottom: 10px;
}
.sibyl-help-text code {
  background: rgba(0,0,0,0.05);
  padding: 1px 5px;
  border-radius: 3px;
  font-size: 0.92em;
  color: var(--sibyl-ink);
}
.sibyl-description {
  font-family: Georgia, 'Times New Roman', serif;
  font-size: 1.05rem;
  line-height: 1.7;
  color: var(--sibyl-ink);
  background: #fff;
  padding: 24px 30px;
  border-left: 4px solid var(--sibyl-scenario);
  border-radius: 0 6px 6px 0;
  box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
.sibyl-narrative-quote {
  font-style: italic;
  color: var(--sibyl-muted);
  border-left: 3px solid var(--sibyl-rule);
  padding: 4px 12px;
  margin: 8px 0 14px 0;
  font-size: 0.9rem;
  line-height: 1.5;
}
.sibyl-tab-content { padding: 18px 4px 4px 4px; }
.nav-tabs .nav-link {
  color: var(--sibyl-muted);
  font-weight: 500;
  border: none;
  border-bottom: 2px solid transparent;
  padding: 10px 16px;
}
.nav-tabs .nav-link:hover { color: var(--sibyl-ink); }
.nav-tabs .nav-link.active {
  color: var(--sibyl-scenario) !important;
  background: transparent !important;
  border-bottom: 2px solid var(--sibyl-scenario) !important;
  font-weight: 600;
}
.card { box-shadow: 0 1px 4px rgba(0,0,0,0.04); border: 1px solid var(--sibyl-rule); }
table.dataframe, .sibyl-table { width: 100%%; }
.sibyl-table {
  font-size: 0.88rem;
  border-collapse: collapse;
}
.sibyl-table th {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--sibyl-muted);
  font-weight: 600;
  border-bottom: 2px solid var(--sibyl-rule);
  padding: 8px 12px 6px 12px;
  text-align: left;
}
.sibyl-table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--sibyl-rule);
  vertical-align: top;
  font-variant-numeric: tabular-nums;
}
.sibyl-table td.text { font-variant-numeric: normal; }
.sibyl-table tr:hover td { background: rgba(11,106,138,0.04); }
.sibyl-table td.num-pos { color: var(--sibyl-disagree); }
.sibyl-table td.num-neg { color: var(--sibyl-agree); }
.sibyl-empty {
  text-align: center;
  padding: 60px 20px;
  color: var(--sibyl-muted);
  font-size: 1rem;
  font-style: italic;
}
.shiny-input-container > label { font-weight: 500; color: var(--sibyl-ink); }
.btn-primary {
  background: var(--sibyl-scenario);
  border-color: var(--sibyl-scenario);
  font-weight: 600;
  letter-spacing: 0.02em;
  padding: 10px 16px;
}
.btn-primary:hover, .btn-primary:focus {
  background: #095878;
  border-color: #095878;
}
.btn-primary:disabled { opacity: 0.55; }
textarea.form-control { font-family: inherit; font-size: 0.93rem; }
",
COL_INK, COL_PAPER, COL_RULE, COL_MUTED, COL_BASELINE,
COL_SCENARIO, COL_ACCENT, COL_AGREE, COL_PARTIAL, COL_DISAGREE
))

# ---- Helpers ----------------------------------------------------------------

quarter_to_date <- function(q) {
  year <- as.integer(substr(q, 1, 4))
  qnum <- as.integer(substr(q, 6, 6))
  as.Date(sprintf("%04d-%02d-15", year, (qnum - 1) * 3 + 2))
}

# Apply the user-selected view transform to a (variable, quarter, value)
# tibble. `transform`: one of "level" or "yoy".
#   yoy + variable is "rate":         x_t - x_{t-4}          (in pp)
#   yoy + variable is "level":        (x_t/x_{t-4} - 1) * 100 (in %)
#   yoy + variable is "rate-locked":  raw level
#   level + anything:                 raw level
apply_view <- function(df, transform) {
  df <- dplyr::arrange(df, variable, series, quarter)
  out <- df |> dplyr::group_by(variable, series) |>
    dplyr::mutate(
      kind = HEADLINE_KIND[variable],
      value_view = dplyr::case_when(
        transform == "level" | kind == "rate-locked" ~ value,
        kind == "level"                              ~ 100 *
          (value / dplyr::lag(value, 4) - 1),
        kind == "rate"                               ~ value -
          dplyr::lag(value, 4),
        TRUE                                          ~ value
      ),
      unit_view = dplyr::case_when(
        transform == "level" | kind == "rate-locked" ~ "level",
        kind == "level"                              ~ "% YoY",
        kind == "rate"                               ~ "pp YoY",
        TRUE                                          ~ "level"
      )
    ) |>
    dplyr::ungroup()
  out
}

# Badge for the OVERALL match verdict. Its domain is agree / partial /
# disagree (compare_narrative_to_description's overall_match attr), so the
# partial branch is live here.
audit_badge_html <- function(verdict) {
  cls <- switch(verdict %||% "neutral",
    "agree"    = "sibyl-badge-agree",
    "partial"  = "sibyl-badge-partial",
    "disagree" = "sibyl-badge-disagree",
    "sibyl-badge-neutral")
  label <- if (is.null(verdict) || !nzchar(verdict)) "Pending" else
    toupper(verdict)
  sprintf('<span class="sibyl-badge %s">%s</span>', cls, label)
}

# Badge for a PER-CLAIM verdict. The per-claim status domain is exactly
# agree / disagree / not_addressed (there is no "partial" at claim level), so
# this map deliberately omits a partial branch.
claim_badge_html <- function(status) {
  cls <- switch(status %||% "neutral",
    "agree"         = "sibyl-badge-agree",
    "disagree"      = "sibyl-badge-disagree",
    "not_addressed" = "sibyl-badge-neutral",
    "sibyl-badge-neutral")
  label <- if (is.null(status) || !nzchar(status)) "PENDING" else
    toupper(gsub("_", " ", status))
  sprintf('<span class="sibyl-badge %s">%s</span>', cls, label)
}

# ---- Human-gate reconstruction ----------------------------------------------

# Rebuild an approved adjustment_list from the proposal and the (optionally
# human-edited) review-table rows. This is the dashboard analogue of
# judgement::review_and_approve(): the proposal is the metadata source of
# truth (channel, target_variable, expected_direction, ...), and the edited
# rows supply the human's value / rationale / tail / confidence / horizon and
# which adjustments survived (deleted rows drop). The exogenize list is
# re-attached so it survives the gate, exactly as the contract requires.
#
# `proposal`   the adjustment_list from propose_adjustments() (carries
#              attr "exogenize").
# `edited_df`  the data.frame from the DT review table (NULL when DT is
#              absent or the human made no edits -> approve the proposal
#              verbatim).
# `exogenize`  the exogenize character vector to re-attach.
collect_approved_adjustments <- function(proposal, edited_df, exogenize) {
  # No editable table (read-only fallback, or nothing edited): approve the
  # proposal verbatim but still re-attach the exogenize list.
  if (is.null(edited_df) || !is.data.frame(edited_df) ||
      nrow(edited_df) == 0L || length(proposal) == 0L) {
    out <- proposal
    attr(out, "exogenize") <- exogenize
    return(out)
  }

  required <- c("equation", "quarter", "value", "rationale",
                "tail", "confidence")
  if (!all(required %in% names(edited_df))) {
    # Shape we don't recognise -> approve verbatim rather than guess.
    out <- proposal
    attr(out, "exogenize") <- exogenize
    return(out)
  }

  # Group edited rows back into adjustments by the stable hidden id we wrote
  # into the table (one id per proposal adjustment, broadcast over its horizon
  # rows). Falls back to (equation, rationale) if the id column was stripped.
  use_ids <- "adjustment_id" %in% names(edited_df) &&
    !all(is.na(edited_df$adjustment_id))
  if (use_ids) {
    meta_lookup <- stats::setNames(
      as.list(proposal), sprintf("af_%03d", seq_along(proposal)))
    edited_df$.group_key <- as.character(edited_df$adjustment_id)
  } else {
    meta_lookup <- list()
    for (a in proposal) {
      meta_lookup[[paste(a$equation, a$rationale, sep = "||")]] <- a
    }
    edited_df$.group_key <- paste(edited_df$equation, edited_df$rationale,
                                  sep = "||")
  }
  key_order <- unique(edited_df$.group_key)
  groups <- split(edited_df, edited_df$.group_key)[key_order]

  built <- lapply(groups, function(g) {
    g <- g[order(g$quarter), , drop = FALSE]
    meta <- meta_lookup[[g$.group_key[1]]]
    judgement::adjustment(
      equation           = g$equation[1],
      horizon            = as.character(g$quarter),
      value              = as.numeric(g$value),
      rationale          = g$rationale[1],
      channel            = if (!is.null(meta)) meta$channel else NA_character_,
      expected_effect    = if (!is.null(meta)) meta$expected_effect
                           else NA_character_,
      confidence         = g$confidence[1],
      tail               = g$tail[1],
      target_variable    = if (!is.null(meta)) meta$target_variable
                           else NA_character_,
      expected_direction = if (!is.null(meta)) meta$expected_direction
                           else NA_character_,
      owner              = if (!is.null(meta)) meta$owner else NA_character_,
      round_id           = if (!is.null(meta)) meta$round_id else NA_character_,
      source             = "human"
    )
  })
  out <- do.call(judgement::adjustment_list, built)
  attr(out, "exogenize") <- exogenize
  out
}

# Solve + describe + audit (+ optional refine) on an ALREADY-APPROVED
# adjustment_list. We seed propose_with_refinement with the approved list so
# the first solve uses exactly what the human signed off; refinement (iters
# > 1) is allowed to adjust magnitudes afterwards. The shape of the returned
# list matches propose_with_refinement so all downstream render code is reused.
run_approved_round <- function(narrative, approved, exogenize, max_iters,
                               round_id, solve_fn, model_propose) {
  projection <- solve_fn(approved, exogenize = exogenize)
  description <- judgement::describe_projection(
    projection = projection, baseline = baseline,
    model = "claude-haiku-4-5")
  audit <- judgement::compare_narrative_to_description(
    narrative = narrative, description = description,
    model = "claude-haiku-4-5")

  history <- list(list(
    iteration = 1L, adjustments = approved, exogenize = exogenize,
    projection = projection, description = description, audit = audit))

  adjustments <- approved
  # Optional refinement: only if the human asked for >1 iteration AND the
  # first audit didn't already agree. Refinement re-proposes from audit
  # feedback (this is post-approval auto-tuning, not a new gate bypass).
  iter <- 1L
  while (iter < max_iters &&
         !isTRUE(attr(audit, "overall_match") == "agree")) {
    iter <- iter + 1L
    adjustments <- judgement::refine_adjustments(
      narrative          = narrative,
      baseline           = baseline,
      prior_adjustments  = adjustments,
      prior_description  = description,
      audit              = audit,
      iteration          = iter,
      round_id           = round_id,
      sensitivity_matrix = sensitivity_matrix,
      model              = model_propose)
    exogenize <- attr(adjustments, "exogenize") %||% exogenize
    projection <- solve_fn(adjustments, exogenize = exogenize)
    description <- judgement::describe_projection(
      projection = projection, baseline = baseline,
      model = "claude-haiku-4-5")
    audit <- judgement::compare_narrative_to_description(
      narrative = narrative, description = description,
      model = "claude-haiku-4-5")
    history[[iter]] <- list(
      iteration = iter, adjustments = adjustments, exogenize = exogenize,
      projection = projection, description = description, audit = audit)
  }

  # Pick the best iteration by audit verdict (agree > partial > disagree),
  # mirroring propose_with_refinement's selection.
  score <- function(it) {
    m <- attr(it$audit, "overall_match")
    if (identical(m, "agree")) 3L
    else if (identical(m, "partial")) 2L
    else if (identical(m, "disagree")) 1L
    else 0L
  }
  best_idx <- which.max(vapply(history, score, integer(1)))
  best <- history[[best_idx]]

  list(
    adjustments = best$adjustments,
    exogenize   = best$exogenize,
    projection  = best$projection,
    description = best$description,
    audit       = best$audit,
    history     = history,
    best_iter   = best_idx
  )
}

# ---- Provenance + honesty caveat (computed once at startup) -----------------

# Coefficient basis is data-derived, not assumed: the pipeline re-estimates
# behavioural coefficients when estimation_end is set, and uses the frozen
# 2019Q3 in-sample fit otherwise. (This matters because "frozen" only means
# the file's embedded TSRANGE end; bimets still re-fits free coefficients on
# every load.)
coefficient_basis <- if (is.null(estimation_end)) {
  "frozen (2019Q3 in-sample fit)"
} else {
  sprintf("re-estimated through %s (re-fit across the COVID break)",
          estimation_end)
}

# Per-variable provenance from sibyldata, if the cache carries it. Older
# caches were built before the provenance attribute existed, so this is
# NULL-safe and degrades to "unknown".
provenance_summary <- local({
  prov <- tryCatch(sibyldata::database_provenance(database_with_handover),
                   error = function(e) NULL)
  if (is.null(prov) || !is.data.frame(prov) || nrow(prov) == 0L) {
    return(NULL)
  }
  tab <- sort(table(prov$source_class), decreasing = TRUE)
  paste(sprintf("%d %s", as.integer(tab), names(tab)), collapse = ", ")
})

# A short, always-visible string describing where the loaded data came from.
data_source_label <- if (is.na(data_source)) {
  "unknown (cache predates source tracking)"
} else {
  data_source
}

# ---- UI: header --------------------------------------------------------------

baseline_end_quarter <- horizon[2]
n_equations <- length(unique(sensitivity_matrix$equation))
baseline_scenario <- attr(baseline, "scenario") %||% "baseline"

app_header <- tags$div(
  class = "sibyl-app-header",
  tags$div(class = "sibyl-app-title", "SIBYL"),
  tags$div(class = "sibyl-app-subtitle",
           "Narrative-to-projection workbench  -  MARTIN solve with LLM judgement"),
  tags$div(class = "sibyl-app-meta",
           sprintf("horizon %s -> %s  -  re-est %s  -  %d adj. eqs",
                   horizon[1], horizon[2],
                   estimation_end %||% "frozen",
                   n_equations))
)

# ---- UI: sidebar ------------------------------------------------------------

sidebar_ui <- sidebar(
  width = 400,
  open = "always",
  tags$div(class = "sibyl-sidebar-section", "Forecast narrative"),
  textAreaInput(
    inputId = "narrative", label = NULL,
    value = DEFAULT_NARRATIVE,
    width = "100%", height = "210px",
    placeholder = "Write a forecast narrative..."
  ),
  tags$div(class = "sibyl-help-text",
    "Describe the economic story in plain English. The LLM converts it",
    " into add-factors on specific MARTIN equations and audits the",
    " resulting projection against your claims."),
  tags$div(class = "sibyl-sidebar-section", "Round configuration"),
  fluidRow(
    column(6,
      selectInput("max_iters", label = "Iterations",
                  choices = c("1 - fast" = 1L,
                              "2 - balanced" = 2L,
                              "3 - full refinement" = 3L),
                  selected = 1L)
    ),
    column(6,
      selectInput("propose_model", label = "Propose model",
                  choices = c("Sonnet 4.6" = "claude-sonnet-4-6",
                              "Haiku 4.5"  = "claude-haiku-4-5"),
                  selected = "claude-sonnet-4-6")
    )
  ),
  tags$div(class = "sibyl-help-text",
    "Start with ", tags$b("Iterations = 1"), " for a fast round (~60s).",
    " Bump to 3 once you want the refinement loop to auto-correct ",
    "any disagreed claims after you approve."),

  # Two-step human-in-the-loop gate (design principle #4): PROPOSE first,
  # review the add-factors, then APPROVE & SOLVE. MARTIN never sees an
  # add-factor the human has not explicitly approved.
  tags$div(class = "sibyl-sidebar-section", "Round (human gate)"),
  actionButton("propose", label = tagList("1. Propose add-factors",
                                           tags$span("→")),
               class = "btn-primary btn-lg", width = "100%"),
  tags$div(style = "height: 8px;"),
  actionButton("approve", label = tagList("2. Approve & solve",
                                           tags$span("✓")),
               class = "btn-primary btn-lg", width = "100%"),
  tags$div(class = "sibyl-help-text",
    "Step 1 asks the LLM to translate your narrative into add-factors and",
    " shows them on the ", tags$b("Adjustments"), " tab for review. Nothing",
    " is solved yet. Step 2 solves MARTIN with the (optionally edited)",
    " add-factors you approved, then describes + audits the result."),

  tags$div(class = "sibyl-sidebar-section", "Status"),
  uiOutput("status_ui"),
  tags$div(class = "sibyl-cache-info",
    tags$b("Pipeline cache:"), " baseline solved through ",
    tags$b(baseline_end_quarter),
    ". Sensitivity matrix covers ", tags$b(n_equations), " equations.",
    tags$br(),
    tags$b("Data source:"), " ", data_source_label, ".",
    tags$br(),
    tags$b("Coefficients:"), " ", coefficient_basis, ".",
    if (!is.null(provenance_summary)) tagList(tags$br(),
      tags$b("Provenance:"), " ", provenance_summary, ".") else NULL,
    tags$br(),
    tags$span(style = "color: var(--sibyl-partial);",
      tags$b("Single deterministic path"),
      " - no fan chart / uncertainty band is shown."),
    if (!api_key_set) tagList(tags$br(),
      tags$span(style = "color: var(--sibyl-disagree); font-weight: 600;",
                "ANTHROPIC_API_KEY not set."))
    else NULL
  )
)

# ---- UI: main content -------------------------------------------------------

chart_tab <- nav_panel(
  title = "Chart",
  div(class = "sibyl-tab-content",
    # Persistent honesty caveat: this is a single deterministic solve.
    div(style = paste(
          "margin: 0 0 12px 0; padding: 8px 12px;",
          "background: rgba(176,122,0,0.06);",
          "border-left: 3px solid var(--sibyl-partial);",
          "border-radius: 0 4px 4px 0; font-size: 0.82rem;",
          "color: var(--sibyl-muted); line-height: 1.5;"),
        tags$b(style = "color: var(--sibyl-ink);",
               "Single deterministic path."),
        " The scenario line is one MARTIN solve, not a fan chart - it carries",
        " no uncertainty band. Treat the diffs as a point estimate; coefficient",
        " and equation-error uncertainty are not propagated here."),
    # Headline KPI cards (level diff at horizon end - see label below)
    uiOutput("kpi_strip"),
    # Exogenised-variables pill row (if any)
    uiOutput("exogenize_strip"),
    # View controls
    fluidRow(
      column(8,
        radioButtons("chart_view", label = NULL,
                     choices = c("Year-on-year change" = "yoy",
                                 "Levels"              = "level"),
                     selected = "yoy", inline = TRUE)
      ),
      column(4,
        div(style = "text-align: right;",
            tags$span(class = "sibyl-help-text",
              tags$em("NCR always shown as level (rate, not change)."))
        )
      )
    ),
    plotlyOutput("headline_plot", height = "520px"),
    div(class = "sibyl-section-title", "Level diff at horizon end (",
        baseline_end_quarter, ")"),
    # The KPI strip + this table always report a LEVEL diff at the horizon end,
    # regardless of the chart's YoY / Levels toggle, so they stay consistent
    # with each other even when the line above shows a year-on-year change.
    div(class = "sibyl-help-text",
      tags$em("Headline cards and this table show the level (or rate) diff at",
              " the horizon end, independent of the chart's YoY/Levels toggle.")),
    uiOutput("diff_table_ui")
  )
)

adjustments_tab <- nav_panel(
  title = "Adjustments",
  div(class = "sibyl-tab-content",
    div(class = "sibyl-help-text",
      "The structured add-factors the LLM produced from your narrative.",
      " Source: ", tags$code("llm"), " for an initial proposal,",
      " ", tags$code("llm-refined"), " for revisions after audit feedback.",
      tags$br(),
      tags$b("Human gate:"), " these are reviewed here BEFORE MARTIN solves.",
      if (HAS_DT)
        " Edit values / rationale / tail / confidence inline, delete rows you reject,"
      else
        " (read-only review - DT not installed, so inline editing is disabled;)",
      " then click ", tags$b("Approve & solve"), " in the sidebar."),
    uiOutput("adjustments_ui")
  )
)

description_tab <- nav_panel(
  title = "Description",
  div(class = "sibyl-tab-content",
    div(class = "sibyl-help-text",
      "The LLM's prose description of the solved projection.",
      tags$strong("The describer is blind to your narrative by design"),
      "- it sees only the diff-vs-baseline. If it had access to the",
      " narrative the round-trip audit would be trivially self-satisfied."),
    uiOutput("description_ui")
  )
)

audit_tab <- nav_panel(
  title = "Audit",
  div(class = "sibyl-tab-content",
    uiOutput("audit_header_ui"),
    div(class = "sibyl-section-title", "Claim-by-claim verdict"),
    uiOutput("audit_table_ui"),
    div(class = "sibyl-section-title", "Diagnostics"),
    div(class = "sibyl-help-text",
      tags$ul(
        tags$li(tags$b("translation_gap"), " - the LLM did not deliver a quantified claim. Iterate or revise."),
        tags$li(tags$b("model_response"), " - the narrative asserted no change to a variable that MARTIN endogenously moved (Taylor Rule, Phillips curve, etc.). Add a cancelling AF or accept the trade-off."),
        tags$li(tags$b("not_addressed"), " - the describer did not engage with the claim, often because it's a structural/causal framing absent from a numerical description.")
      )
    ),
    uiOutput("diagnostics_ui")
  )
)

history_tab <- nav_panel(
  title = "History",
  div(class = "sibyl-tab-content",
    div(class = "sibyl-help-text",
      "One row per orchestrator iteration. ",
      tags$b("Best iter"), " marked with a star - selected by audit verdict",
      " (agree > partial > disagree), ties broken by earliest pass."),
    uiOutput("history_ui")
  )
)

ui <- tagList(
  tags$head(tags$style(custom_css)),
  page_fillable(
    theme = sibyl_theme,
    padding = 0,
    fillable_mobile = TRUE,
    app_header,
    layout_sidebar(
      sidebar = sidebar_ui,
      fillable = TRUE,
      navset_card_tab(
        id = "tabs",
        chart_tab,
        adjustments_tab,
        description_tab,
        audit_tab,
        history_tab
      )
    )
  )
)

# ---- Server -----------------------------------------------------------------

server <- function(input, output, session) {
  state <- reactiveValues(
    # proposal: the un-approved adjustment_list from step 1 (Propose),
    #           carrying its "exogenize" attribute. NULL until proposed.
    proposal = NULL,
    proposal_exogenize = character(0),
    proposal_round_id = NULL,
    approved = FALSE,            # did the human click Approve & solve?
    # result: the solved + described + audited round from step 2. NULL until
    #         approved & solved.
    result = NULL,
    status_message = "Ready. Edit the narrative and click 1. Propose add-factors.",
    status_class = "",
    last_narrative = NULL
  )

  # The live (human-edited) review tibble for the DT gate. Seeded from the
  # proposal on Propose, mutated by inline cell edits, read on Approve. Held
  # outside `state` so DT's cell-edit events update it without re-rendering
  # the table from scratch.
  review_data <- reactiveVal(NULL)

  output$status_ui <- renderUI({
    div(class = paste("sibyl-status", state$status_class),
        state$status_message)
  })

  # Shared MARTIN solve closure (same wiring the pipeline uses).
  solve_fn <- function(adj, exogenize = character(0)) {
    martin::solve_martin(
      database       = database_with_handover,
      adjustments    = adj,
      horizon        = horizon,
      coefficients   = if (is.null(estimation_end)) "frozen"
                       else "reestimated",
      estimation_end = estimation_end,
      scenario       = "dashboard-run",
      exogenize              = exogenize,
      baseline_for_exogenize = if (length(exogenize) > 0L) baseline
                               else NULL
    )
  }

  # ----- Step 1: PROPOSE (no solve). Translate narrative -> add-factors -----
  # This is the FIRST half of the human-in-the-loop gate. We call
  # judgement::propose_adjustments() directly (NOT propose_with_refinement,
  # which would solve + describe + audit internally and bypass the gate). The
  # proposal is rendered for review; nothing reaches MARTIN until the human
  # clicks Approve & solve.
  observeEvent(input$propose, {
    narrative_text <- trimws(input$narrative)
    if (!nzchar(narrative_text)) {
      state$status_message <- "Please enter a narrative first."
      state$status_class <- "sibyl-status-error"
      return()
    }
    if (!api_key_set) {
      state$status_message <- paste(
        "ANTHROPIC_API_KEY is not set in .Renviron.",
        "Add it and restart the dashboard.")
      state$status_class <- "sibyl-status-error"
      return()
    }

    # A fresh proposal invalidates any prior approved solve.
    state$result <- NULL
    state$approved <- FALSE
    state$status_message <- paste(
      "Step 1/2: proposing add-factors with", input$propose_model,
      "(no solve yet). Allow ~30-60s.")
    state$status_class <- "sibyl-status-running"

    progress <- shiny::Progress$new(session, min = 0, max = 1)
    on.exit(progress$close())
    progress$set(value = 0.1, message = "Proposing add-factors",
                 detail = "narrative -> add-factors (no solve)")

    round_id <- paste0("dash-", format(Sys.time(), "%Y%m%d-%H%M%S"))
    proposal <- tryCatch(
      judgement::propose_adjustments(
        narrative          = narrative_text,
        baseline           = baseline,
        round_id           = round_id,
        sensitivity_matrix = sensitivity_matrix,
        model              = input$propose_model
      ),
      error = function(e) {
        state$status_message <- paste("Propose failed:", conditionMessage(e))
        state$status_class <- "sibyl-status-error"
        NULL
      }
    )
    progress$set(value = 1)
    if (is.null(proposal)) return()

    exog <- attr(proposal, "exogenize") %||% character(0)
    state$proposal <- proposal
    state$proposal_exogenize <- exog
    state$proposal_round_id <- round_id
    state$last_narrative <- narrative_text
    # Seed the editable review tibble (DT path); NULL when there are no
    # add-factors to edit.
    review_data(if (length(proposal) > 0L)
                  proposal_review_tibble(proposal) else NULL)

    n_adj <- length(proposal)
    state$status_message <- sprintf(
      paste("Proposed %d add-factor(s)%s. REVIEW on the Adjustments tab,",
            "then click 2. Approve & solve."),
      n_adj,
      if (length(exog)) sprintf(" + %d exogenised var(s)", length(exog)) else "")
    state$status_class <- "sibyl-status-done"
    bslib::nav_select("tabs", "Adjustments")
  })

  # ----- Step 2: APPROVE & SOLVE. Only now does MARTIN see the AFs -----
  # The SECOND half of the gate. We reconstruct the (possibly human-edited)
  # adjustment_list from the review table, re-attach the exogenize list, then
  # solve + describe + audit (+ optional refine). Approval is explicit and
  # recorded (state$approved) so the UI can show that the gate was crossed.
  observeEvent(input$approve, {
    if (is.null(state$proposal)) {
      state$status_message <- "Propose add-factors first (step 1)."
      state$status_class <- "sibyl-status-error"
      return()
    }
    if (!api_key_set) {
      state$status_message <- paste(
        "ANTHROPIC_API_KEY is not set in .Renviron.",
        "Add it and restart the dashboard.")
      state$status_class <- "sibyl-status-error"
      return()
    }

    approved_adj <- tryCatch(
      collect_approved_adjustments(state$proposal,
                                   if (HAS_DT) review_data() else NULL,
                                   state$proposal_exogenize),
      error = function(e) {
        state$status_message <- paste("Could not read the edited table:",
                                       conditionMessage(e))
        state$status_class <- "sibyl-status-error"
        NULL
      }
    )
    if (is.null(approved_adj)) return()
    exog <- attr(approved_adj, "exogenize") %||% character(0)

    if (length(approved_adj) == 0L && length(exog) == 0L) {
      state$status_message <- paste(
        "Nothing approved: no add-factors and no exogenised variables.",
        "Edit or re-propose.")
      state$status_class <- "sibyl-status-error"
      return()
    }

    state$approved <- TRUE
    state$status_message <- paste(
      "Step 2/2: solving MARTIN with approved add-factors, then describe +",
      "audit (Haiku). Allow ~60s per iteration.")
    state$status_class <- "sibyl-status-running"

    progress <- shiny::Progress$new(session, min = 0, max = 1)
    on.exit(progress$close())
    progress$set(value = 0.05, message = "Solving approved round",
                 detail = "solve -> describe -> audit")

    narrative_text <- state$last_narrative %||% trimws(input$narrative)
    t0 <- Sys.time()
    result <- tryCatch(
      run_approved_round(
        narrative   = narrative_text,
        approved    = approved_adj,
        exogenize   = exog,
        max_iters   = as.integer(input$max_iters),
        round_id    = state$proposal_round_id %||% "dash-approved",
        solve_fn    = solve_fn,
        model_propose = input$propose_model
      ),
      error = function(e) {
        state$status_message <- paste("Solve failed:", conditionMessage(e))
        state$status_class <- "sibyl-status-error"
        NULL
      }
    )
    dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    progress$set(value = 1)
    if (is.null(result)) return()

    state$result <- result
    conv <- attr(result$projection, "convergence")
    conv_note <- if (!is.null(conv) && isFALSE(conv$converged)) {
      sprintf(" [WARN: %s non-finite cells in solve]",
              conv$n_nonfinite %||% "?")
    } else ""
    state$status_message <- sprintf(
      "Approved & solved in %.0fs. Best iter: %d of %d. Audit: %s.%s",
      dt, result$best_iter %||% 1L, length(result$history),
      attr(result$audit, "overall_match") %||% "n/a", conv_note
    )
    state$status_class <- "sibyl-status-done"
    bslib::nav_select("tabs", "Chart")
  })

  # ----- KPI strip -----
  output$kpi_strip <- renderUI({
    res <- state$result
    if (is.null(res) || is.null(res$projection)) return(NULL)
    df <- dplyr::inner_join(
      baseline       |> dplyr::select(variable, quarter, baseline = value),
      res$projection |> dplyr::select(variable, quarter, scenario = value),
      by = c("variable", "quarter")
    ) |>
      dplyr::filter(variable %in% HEADLINE,
                    quarter == baseline_end_quarter) |>
      dplyr::mutate(
        diff_abs = scenario - baseline,
        diff_pct = 100 * diff_abs / pmax(abs(baseline), 1e-9),
        label    = HEADLINE_LABELS[variable]
      )
    cards <- lapply(HEADLINE, function(v) {
      row <- df[df$variable == v, ]
      if (nrow(row) == 0L) return(NULL)
      kind <- HEADLINE_KIND[v]
      # Always a LEVEL (or rate) diff at the horizon end, so the headline
      # number stays consistent with the diff table below regardless of the
      # chart's YoY/Levels toggle.
      if (kind %in% c("rate", "rate-locked")) {
        value_str <- sprintf("%.2f%%", row$scenario)
        delta_str <- sprintf("%+.2f pp at %s", row$diff_abs,
                             baseline_end_quarter)
      } else {
        big <- abs(row$scenario) >= 1000
        value_str <- if (big) format(round(row$scenario), big.mark = ",")
                     else sprintf("%.2f", row$scenario)
        delta_str <- sprintf("%+.2f%% at %s", row$diff_pct,
                             baseline_end_quarter)
      }
      sign_class <- if (row$diff_abs > 1e-6) "sibyl-delta-up"
                    else if (row$diff_abs < -1e-6) "sibyl-delta-down"
                    else "sibyl-delta-flat"
      div(class = "sibyl-headline-card",
          div(class = "sibyl-headline-label", row$label),
          div(class = "sibyl-headline-value", value_str),
          div(class = paste("sibyl-headline-delta", sign_class), delta_str))
    })
    div(class = "sibyl-headline-row", cards)
  })

  # ----- Chart -----
  output$headline_plot <- renderPlotly({
    res <- state$result
    if (is.null(res) || is.null(res$projection)) {
      p <- ggplot() +
        annotate("text", x = 1, y = 1,
                 label = "Propose, then Approve & solve to see the chart.",
                 size = 5, colour = COL_MUTED) +
        theme_void() +
        theme(plot.background = element_rect(fill = COL_PAPER,
                                              colour = NA))
      return(ggplotly(p) |>
               plotly::layout(paper_bgcolor = COL_PAPER,
                              plot_bgcolor  = COL_PAPER))
    }
    df_raw <- dplyr::bind_rows(
      baseline       |> dplyr::mutate(series = "baseline"),
      res$projection |> dplyr::mutate(series = "scenario")
    ) |>
      dplyr::filter(variable %in% HEADLINE)
    df <- apply_view(df_raw, input$chart_view)
    df <- df |>
      dplyr::mutate(qdate = quarter_to_date(quarter),
                    label = HEADLINE_LABELS[variable]) |>
      dplyr::filter(qdate >= as.Date("2018-01-01"))

    if (input$chart_view == "yoy") {
      subtitle <- "Year-on-year change (% for levels, pp for rates; NCR shown as level). Dashed vertical = projection start."
    } else {
      subtitle <- "Quarterly levels. Dashed vertical = projection start."
    }

    df$tooltip <- sprintf(
      "%s<br>%s: %.3f %s<br>series: %s",
      df$quarter, df$label, df$value_view, df$unit_view, df$series
    )

    # Vertical reference at the start of the genuine projection
    # period (just past the last quarter of hard data).
    proj_start <- quarter_to_date(PROJECTION_START)

    p <- ggplot(df, aes(x = qdate, y = value_view, colour = series,
                        group = series, text = tooltip)) +
      geom_vline(xintercept = as.numeric(proj_start),
                 linetype = "dashed", colour = COL_ACCENT,
                 linewidth = 0.4, alpha = 0.7) +
      geom_line(linewidth = 0.7) +
      facet_wrap(~ label, scales = "free_y", ncol = 4) +
      scale_colour_manual(values = c(baseline = COL_BASELINE,
                                     scenario = COL_SCENARIO),
                          labels = c(baseline = "Baseline",
                                     scenario = "Scenario")) +
      scale_x_date(date_breaks = "2 years", date_labels = "'%y") +
      labs(x = NULL, y = NULL, colour = NULL,
           subtitle = subtitle) +
      theme_minimal(base_size = 11) +
      theme(
        plot.background    = element_rect(fill = COL_PAPER, colour = NA),
        panel.background   = element_rect(fill = COL_PAPER, colour = NA),
        panel.grid.major.x = element_blank(),
        panel.grid.minor   = element_blank(),
        panel.grid.major.y = element_line(colour = COL_RULE, linewidth = 0.3),
        strip.text         = element_text(face = "bold", colour = COL_INK,
                                           size = 10, hjust = 0),
        strip.background   = element_blank(),
        axis.text          = element_text(colour = COL_MUTED, size = 9),
        legend.position    = "bottom",
        plot.subtitle      = element_text(colour = COL_MUTED, size = 10,
                                           margin = margin(b = 8))
      )

    suppressWarnings(
      ggplotly(p, tooltip = "text") |>
        plotly::layout(paper_bgcolor = COL_PAPER,
                       plot_bgcolor  = COL_PAPER,
                       margin = list(t = 36, b = 30, l = 24, r = 10),
                       legend = list(orientation = "h", x = 0.5, y = -0.12,
                                     xanchor = "center"))
    )
  })

  # ----- Diff table -----
  output$diff_table_ui <- renderUI({
    res <- state$result
    if (is.null(res) || is.null(res$projection)) {
      return(div(class = "sibyl-empty",
                  "No solved round yet. Approve & solve first."))
    }
    df <- dplyr::inner_join(
      baseline       |> dplyr::select(variable, quarter, baseline = value),
      res$projection |> dplyr::select(variable, quarter, scenario = value),
      by = c("variable", "quarter")
    ) |>
      dplyr::filter(variable %in% HEADLINE,
                    quarter == baseline_end_quarter) |>
      dplyr::mutate(
        diff_abs = scenario - baseline,
        diff_pct = 100 * diff_abs / pmax(abs(baseline), 1e-9),
        label    = HEADLINE_LABELS[variable]
      ) |>
      dplyr::arrange(match(variable, HEADLINE))
    rows <- lapply(seq_len(nrow(df)), function(i) {
      r <- df[i, ]
      kind <- HEADLINE_KIND[r$variable]
      base_fmt <- if (kind %in% c("rate", "rate-locked"))
                    sprintf("%.2f%%", r$baseline)
                  else if (abs(r$baseline) >= 1000)
                    format(round(r$baseline), big.mark = ",")
                  else sprintf("%.2f", r$baseline)
      scen_fmt <- if (kind %in% c("rate", "rate-locked"))
                    sprintf("%.2f%%", r$scenario)
                  else if (abs(r$scenario) >= 1000)
                    format(round(r$scenario), big.mark = ",")
                  else sprintf("%.2f", r$scenario)
      diff_unit <- if (kind %in% c("rate", "rate-locked")) "pp" else
                   sprintf("(%+.2f%%)", r$diff_pct)
      diff_fmt <- sprintf("%+.3f %s", r$diff_abs, diff_unit)
      cls <- if (r$diff_abs > 1e-6) "num-pos"
             else if (r$diff_abs < -1e-6) "num-neg" else ""
      tags$tr(
        tags$td(class = "text", r$label),
        tags$td(class = "text", style = "color: var(--sibyl-muted);",
                r$variable),
        tags$td(base_fmt),
        tags$td(scen_fmt),
        tags$td(class = cls, diff_fmt)
      )
    })
    tags$table(class = "sibyl-table",
      tags$thead(tags$tr(
        tags$th("Variable"), tags$th("Code"),
        tags$th("Baseline"), tags$th("Scenario"),
        tags$th("Difference")
      )),
      tags$tbody(rows)
    )
  })

  # ----- Exogenize strip (Chart tab) -----
  output$exogenize_strip <- renderUI({
    res <- state$result
    exog <- res$exogenize %||% character(0)
    if (is.null(res) || length(exog) == 0L) return(NULL)
    pills <- lapply(exog, function(v) {
      label <- HEADLINE_LABELS[v] %||% v
      tags$span(class = "sibyl-badge sibyl-badge-partial",
                style = "margin-right: 8px;",
                paste0(v, " held at baseline"))
    })
    div(style = "margin: 0 0 10px 0; padding: 8px 12px; background: rgba(176,122,0,0.05); border-left: 3px solid var(--sibyl-partial); border-radius: 0 4px 4px 0;",
        tags$span(style = "font-size: 0.78rem; color: var(--sibyl-muted); margin-right: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em;",
                  "Exogenised:"),
        pills)
  })

  # ----- Exogenize review block (shared by proposal + solved views) -----
  exogenize_block <- function(exog) {
    if (length(exog) == 0L) return(NULL)
    pills <- lapply(exog, function(v) {
      label <- HEADLINE_LABELS[v] %||% v
      tags$span(class = "sibyl-badge sibyl-badge-partial",
                style = "margin-right: 6px;",
                paste0(v, "  -  ", label))
    })
    tagList(
      div(class = "sibyl-section-title",
          "Exogenised variables (held at baseline path)"),
      div(class = "sibyl-help-text",
          "These variables' equations are switched off over the projection; ",
          "their values are taken from the baseline solve. ",
          "This list is shown to you here and carried through the approval ",
          "gate unchanged."),
      div(style = "margin-bottom: 18px;", pills)
    )
  }

  # Read-only add-factor table (for the SOLVED view).
  adjustments_readonly_table <- function(adj_list) {
    if (length(adj_list) == 0L) return(NULL)
    tbl <- judgement::as_tibble_adjustments(adj_list) |>
      dplyr::select(equation, quarter, value, tail, confidence,
                    rationale, source) |>
      dplyr::arrange(equation, quarter)
    rows <- lapply(seq_len(nrow(tbl)), function(i) {
      r <- tbl[i, ]
      val_cls <- if (r$value > 1e-9) "num-pos"
                 else if (r$value < -1e-9) "num-neg" else ""
      tags$tr(
        tags$td(class = "text", tags$b(r$equation)),
        tags$td(r$quarter),
        tags$td(class = val_cls, sprintf("%+.4f", r$value)),
        tags$td(class = "text", r$tail),
        tags$td(class = "text", r$confidence),
        tags$td(class = "text",
                style = "max-width: 480px; white-space: normal;",
                r$rationale),
        tags$td(class = "text", tags$code(r$source))
      )
    })
    tags$table(class = "sibyl-table",
      tags$thead(tags$tr(
        tags$th("Equation"), tags$th("Quarter"), tags$th("Value"),
        tags$th("Tail"), tags$th("Confidence"),
        tags$th("Rationale"), tags$th("Source")
      )),
      tags$tbody(rows)
    )
  }

  # Build the editable review tibble for a proposal (DT path). Carries the
  # hidden stable adjustment_id so collect_approved_adjustments() can regroup
  # rows even after edits, and exposes only the human-editable columns plus
  # the id.
  proposal_review_tibble <- function(proposal) {
    tbl <- judgement::as_tibble_adjustments(proposal)
    ids <- unlist(lapply(seq_along(proposal), function(i) {
      rep(sprintf("af_%03d", i), length(proposal[[i]]$horizon))
    }))
    if (length(ids) != nrow(tbl)) {
      ids <- sprintf("af_%03d", seq_len(nrow(tbl)))
    }
    tbl$adjustment_id <- ids
    tbl[, c("adjustment_id", "equation", "quarter", "value",
            "tail", "confidence", "rationale")]
  }

  # The editable DT review table (only registered when DT is installed). We
  # render the table from review_data() but ISOLATE that read so inline edits
  # (which mutate review_data) don't trigger a full re-render; edits are
  # pushed back into review_data by the cell-edit observer below and mirrored
  # into the widget via a proxy.
  if (HAS_DT) {
    output$adjustments_table <- DT::renderDT({
      # Re-render only when a NEW proposal arrives; the edited contents are
      # read with isolate() so per-cell edits don't re-render the table.
      state$proposal
      df <- isolate(review_data())
      if (is.null(df) || nrow(df) == 0L) return(NULL)
      DT::datatable(
        df,
        rownames = FALSE,
        editable = list(target = "cell",
                        # Keep the stable id and equation read-only; the human
                        # edits value / tail / confidence / rationale / quarter.
                        disable = list(columns = c(0L, 1L))),
        selection = "none",
        options = list(dom = "t", paging = FALSE, ordering = FALSE,
                       columnDefs = list(list(visible = FALSE, targets = 0L)))
      )
    }, server = TRUE)

    # Persist inline edits into review_data() so Approve reads the latest
    # values. DT reports 1-based row, 0-based col in the visible frame.
    observeEvent(input$adjustments_table_cell_edit, {
      info <- input$adjustments_table_cell_edit
      df <- review_data()
      if (is.null(df)) return()
      df <- as.data.frame(df, stringsAsFactors = FALSE)
      r <- info$row
      col <- info$col + 1L  # rownames = FALSE -> visible col 0 == df col 1
      if (r >= 1L && r <= nrow(df) && col >= 1L && col <= ncol(df)) {
        df[r, col] <- DT::coerceValue(info$value, df[r, col])
        review_data(tibble::as_tibble(df))
      }
    })
  }

  # ----- Adjustments tab: proposal review (pre-solve) + solved view -----
  output$adjustments_ui <- renderUI({
    proposal <- state$proposal
    res <- state$result

    # Nothing proposed yet.
    if (is.null(proposal) && is.null(res)) {
      return(div(class = "sibyl-empty",
        "Click 1. Propose add-factors to translate your narrative."))
    }

    # ----- SOLVED view: show the approved adjustments + mechanical audit -----
    if (state$approved && !is.null(res)) {
      exog <- res$exogenize %||% character(0)
      have_adj <- length(res$adjustments) > 0L
      if (!have_adj && length(exog) == 0L) {
        return(div(class = "sibyl-empty",
          "Approved with no add-factors and no exogenisations."))
      }
      approved_banner <- div(
        style = paste("margin-bottom: 14px; padding: 8px 12px;",
                      "background: rgba(29,122,58,0.07);",
                      "border-left: 3px solid var(--sibyl-agree);",
                      "border-radius: 0 4px 4px 0;"),
        HTML(claim_badge_html("agree")),
        tags$span(style = "margin-left: 10px; font-size: 0.86rem;",
          "Approved by human and solved. The add-factors below are exactly",
          " what MARTIN saw."))
      mech_block <- mechanical_audit_block(res)
      tagList(
        approved_banner,
        exogenize_block(exog),
        if (have_adj) div(class = "sibyl-section-title",
                          "Approved add-factor adjustments") else NULL,
        adjustments_readonly_table(res$adjustments),
        mech_block
      )
    } else {
      # ----- REVIEW view (pre-solve): the human gate -----
      exog <- state$proposal_exogenize %||% character(0)
      have_adj <- length(proposal) > 0L
      if (!have_adj && length(exog) == 0L) {
        return(div(class = "sibyl-empty",
          "The LLM proposed no adjustments and no exogenisations for this ",
          "narrative. Nothing to approve."))
      }
      gate_banner <- div(
        style = paste("margin-bottom: 14px; padding: 8px 12px;",
                      "background: rgba(176,122,0,0.07);",
                      "border-left: 3px solid var(--sibyl-partial);",
                      "border-radius: 0 4px 4px 0; font-size: 0.86rem;"),
        tags$b("Awaiting your approval."),
        " MARTIN has NOT solved with these yet.",
        if (HAS_DT)
          " Double-click a cell to edit; delete is not supported inline, set a value to 0 to neutralise a row."
        else
          " (Inline editing needs the DT package, which is not installed; this is a read-only review.)",
        " Then click ", tags$b("2. Approve & solve"), " in the sidebar.")
      review_tbl <- if (have_adj) {
        if (HAS_DT) {
          tagList(
            div(class = "sibyl-section-title",
                "Proposed add-factors (editable - review before solving)"),
            DT::DTOutput("adjustments_table"))
        } else {
          tagList(
            div(class = "sibyl-section-title",
                "Proposed add-factors (read-only review)"),
            adjustments_readonly_table(proposal))
        }
      } else NULL
      tagList(gate_banner, exogenize_block(exog), review_tbl)
    }
  })

  # Deterministic, LLM-independent fidelity check on the APPROVED add-factors:
  # did MARTIN actually move each declared target_variable in the declared
  # direction? Rendered alongside the solved adjustments.
  mechanical_audit_block <- function(res) {
    if (is.null(res$adjustments) || length(res$adjustments) == 0L ||
        is.null(res$projection)) {
      return(NULL)
    }
    ma <- tryCatch(
      judgement::mechanical_audit(res$adjustments, res$projection, baseline),
      error = function(e) NULL)
    if (is.null(ma) || nrow(ma) == 0L) return(NULL)
    rows <- lapply(seq_len(nrow(ma)), function(i) {
      r <- ma[i, ]
      badge <- if (is.na(r$agrees)) claim_badge_html("not_addressed")
               else if (isTRUE(r$agrees)) claim_badge_html("agree")
               else claim_badge_html("disagree")
      tags$tr(
        tags$td(class = "text", tags$b(r$equation)),
        tags$td(class = "text", r$target_variable),
        tags$td(class = "text",
                if (is.na(r$expected_direction)) tags$em("—")
                else r$expected_direction),
        tags$td(if (is.na(r$realised_diff)) tags$em("—")
                else sprintf("%+.4f", r$realised_diff)),
        tags$td(HTML(badge))
      )
    })
    tagList(
      div(class = "sibyl-section-title", "Mechanical fidelity check"),
      div(class = "sibyl-help-text",
          "LLM-independent: compares each add-factor's declared target and ",
          "direction against the realised projection-minus-baseline diff at ",
          "the horizon end. No model opinion involved."),
      tags$table(class = "sibyl-table",
        tags$thead(tags$tr(
          tags$th("Equation"), tags$th("Target"), tags$th("Expected dir."),
          tags$th("Realised diff"), tags$th("Agrees")
        )),
        tags$tbody(rows)))
  }

  # ----- Description -----
  output$description_ui <- renderUI({
    res <- state$result
    if (is.null(res) || is.null(res$description)) {
      return(div(class = "sibyl-empty",
        "Approve & solve to see the LLM's projection description."))
    }
    desc_html <- gsub("\n", "<br/>", res$description, fixed = TRUE)
    tagList(
      if (!is.null(state$last_narrative))
        tagList(
          div(class = "sibyl-section-title", "Original narrative"),
          div(class = "sibyl-narrative-quote", state$last_narrative))
      else NULL,
      div(class = "sibyl-section-title", "LLM description of the solved projection"),
      div(class = "sibyl-description", HTML(desc_html))
    )
  })

  # ----- Audit -----
  output$audit_header_ui <- renderUI({
    res <- state$result
    if (is.null(res) || is.null(res$audit)) return(NULL)
    verdict <- attr(res$audit, "overall_match")
    div(style = "display: flex; gap: 12px; align-items: center; margin-bottom: 8px;",
        tags$span(style = "font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--sibyl-muted); font-weight: 600;",
                  "Overall match:"),
        HTML(audit_badge_html(verdict))
    )
  })

  output$audit_table_ui <- renderUI({
    res <- state$result
    if (is.null(res) || is.null(res$audit)) {
      return(div(class = "sibyl-empty", "No audit yet."))
    }
    aud <- res$audit
    rows <- lapply(seq_len(nrow(aud)), function(i) {
      # Per-claim status domain is agree / disagree / not_addressed only
      # (no "partial" at claim level), so use the claim-specific badge.
      verdict <- aud$status[i]
      tags$tr(
        tags$td(HTML(claim_badge_html(verdict))),
        tags$td(class = "text", style = "max-width: 520px; white-space: normal;",
                aud$claim[i]),
        tags$td(class = "text", style = "max-width: 320px; white-space: normal; color: var(--sibyl-muted);",
                aud$note[i])
      )
    })
    tags$table(class = "sibyl-table",
      tags$thead(tags$tr(
        tags$th("Verdict"), tags$th("Claim"), tags$th("Audit note")
      )),
      tags$tbody(rows)
    )
  })

  output$diagnostics_ui <- renderUI({
    res <- state$result
    if (is.null(res) || is.null(res$audit) || is.null(res$projection)) {
      return(div(class = "sibyl-empty", "No diagnostics yet."))
    }
    diag <- judgement::diagnose_audit(res$audit, res$projection, baseline)
    cat_palette <- c(
      agree              = "sibyl-badge-agree",
      not_addressed      = "sibyl-badge-neutral",
      translation_gap    = "sibyl-badge-disagree",
      model_response     = "sibyl-badge-partial",
      unclassified       = "sibyl-badge-neutral",
      narrative_conflict = "sibyl-badge-partial"
    )
    rows <- lapply(seq_len(nrow(diag)), function(i) {
      r <- diag[i, ]
      cat <- as.character(r$category)
      cls <- cat_palette[[cat]] %||% "sibyl-badge-neutral"
      badge <- sprintf('<span class="sibyl-badge %s">%s</span>',
                       cls, gsub("_", " ", cat))
      tags$tr(
        tags$td(HTML(badge)),
        tags$td(class = "text",
                if (is.na(r$variable)) tags$em("—") else tags$b(r$variable)),
        tags$td(if (is.na(r$diff_at_end)) tags$em("—")
                else sprintf("%+.3f", r$diff_at_end)),
        tags$td(class = "text", style = "max-width: 540px; white-space: normal;",
                r$explanation)
      )
    })
    tags$table(class = "sibyl-table",
      tags$thead(tags$tr(
        tags$th("Category"), tags$th("Variable"),
        tags$th("Diff @ horizon"), tags$th("Explanation")
      )),
      tags$tbody(rows)
    )
  })

  # ----- History -----
  output$history_ui <- renderUI({
    res <- state$result
    if (is.null(res) || length(res$history) == 0L) {
      return(div(class = "sibyl-empty",
                 "Approve & solve to see iteration history."))
    }
    best_i <- res$best_iter %||% NA
    rows <- lapply(seq_along(res$history), function(i) {
      it <- res$history[[i]]
      adj_tbl <- if (length(it$adjustments) > 0L) {
        judgement::as_tibble_adjustments(it$adjustments)
      } else NULL
      eqs <- if (!is.null(adj_tbl))
        paste(unique(adj_tbl$equation), collapse = ", ") else ""
      n_afs <- if (!is.null(adj_tbl)) length(adj_tbl$equation) else 0L
      verdict <- attr(it$audit, "overall_match")
      tags$tr(
        tags$td(class = "text",
                tags$b(paste0("Iteration ", it$iteration))),
        tags$td(class = "text", eqs),
        tags$td(n_afs),
        tags$td(HTML(audit_badge_html(verdict))),
        tags$td(class = "text",
                if (identical(i, best_i))
                  tags$span(class = "sibyl-badge sibyl-badge-agree",
                            style = "padding: 2px 8px; font-size: 0.65rem;",
                            "BEST")
                else "")
      )
    })
    tags$table(class = "sibyl-table",
      tags$thead(tags$tr(
        tags$th("Iter"), tags$th("Equations"),
        tags$th("# AFs"), tags$th("Audit"), tags$th("")
      )),
      tags$tbody(rows)
    )
  })
}

shinyApp(ui, server)
