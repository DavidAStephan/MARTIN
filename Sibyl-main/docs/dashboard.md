# The SIBYL dashboard

A small Shiny app at [`app/app.R`](../app/app.R) lets you type a
narrative, watch the LLM judgement layer turn it into add-factors,
solve MARTIN, and inspect the results in a browser.

For the architectural deep-dive on what the LLM is doing under the
hood see [docs/llm_layer.md](llm_layer.md). This doc is just the
runtime guide.

## Prerequisites

1. The pipeline must have been built once so the targets cache exists:
   ```sh
   just pipeline
   ```
   The dashboard reuses the cached `baseline`, `database_with_handover`,
   `sensitivity_matrix`, `horizon`, and `estimation_end` rather than
   re-running them per click. (Re-running would push every click to
   ~10 minutes; reusing pulls it to ~2-4 minutes.)

2. `ANTHROPIC_API_KEY` must be in `.Renviron`. Without it the "Run
   round" button shows an error.

## Launching

```sh
just dashboard
# equivalent to:
Rscript app/run.R
```

The app starts on `http://localhost:5151` and opens a browser
automatically. To run on a different port:

```sh
PORT=8080 just dashboard
```

To suppress the browser auto-launch (useful when forwarding through
ssh):

```sh
SIBYL_NO_LAUNCH_BROWSER=1 just dashboard
```

## Layout

```
+----------------------------------------------------------------------+
| [ ink-dark header band ]  SIBYL  -  Narrative-to-projection ...      |
|                                       horizon ... | re-est ... | eqs |
+----------------------+-----------------------------------------------+
| SIDEBAR              | MAIN AREA  (cards with tabs)                  |
| Forecast narrative   |                                               |
|  [textarea]          | [ Chart ] [ Adjustments ] [ Description ]     |
| Round configuration  | [ Audit ] [ History ]                         |
|  iter / model        |                                               |
| [ Run round  -> ]    | (selected tab content)                        |
| status panel         |                                               |
| cache info           |                                               |
+----------------------+-----------------------------------------------+
```

### Sidebar inputs

- **Forecast narrative** — paste or type the forecast story. Defaults
  to the canonical sticky-services-inflation example. The LLM uses
  this verbatim as the narrative passed to `propose_adjustments()`.

- **Iterations** — `max_iters` for the agentic loop. Defaults to
  **1 (fast)** for a single propose + solve + describe + audit pass
  (~60s). Bump to 2 or 3 to enable the refinement loop, which
  re-prompts the LLM to revise its proposal when the audit
  disagrees.

- **Propose model** — Sonnet 4.6 (default) or Haiku 4.5. Sonnet is
  more decisive at calibrating magnitudes and figuring out cancelling
  AFs; Haiku is ~5x cheaper and ~3x faster. Describe + audit always
  run on Haiku because they're cheap text tasks.

- **Run round** — fires the propose / solve / describe / audit /
  refine pipeline. A Shiny progress widget appears in the
  bottom-right corner of the browser. The sidebar **Status** panel
  also updates: blue rule while running, green rule on success, red
  rule on error.

### Tabs

- **Chart** — at the top, a strip of seven headline KPIs showing the
  scenario value at the horizon end + its delta vs baseline. Below
  that, the radio toggle **Year-on-year change** (default) vs
  **Levels**:
  - YoY mode, level variables (Y, RC, GNE, PTM, P): % growth
    versus the same quarter a year ago.
  - YoY mode, rate variables (LUR): percentage-point change versus
    a year ago.
  - NCR is **always shown as a level** (a rate, not a change),
    even when the toggle is on YoY.
  Below the chart, a typed diff table shows baseline vs scenario at
  the horizon end with correctly-formatted units (pp for rates, %
  for levels).

- **Proposed adjustments** — the structured add-factors the LLM
  produced. Columns: `equation`, `quarter`, `value`, `tail`,
  `confidence`, `rationale`, `source`. The `source` field shows
  `llm` for an initial proposal and `llm-refined` if the
  refinement loop revised it.

- **Projection description** — the LLM's prose description of the
  solved projection. Note: this LLM call is *blind* to your
  narrative by design — otherwise the round-trip audit becomes
  trivially satisfied. The describer only sees a diff-vs-baseline
  summary.

- **Audit** — at the top a coloured **overall_match** badge
  (green=agree / amber=partial / red=disagree). Then the
  claim-by-claim verdict table with per-claim badges. Then the
  diagnostics table from `judgement::diagnose_audit()` which
  classifies each disagree as:
  - `translation_gap` (red) — LLM didn't deliver a claim's target.
    Iterate or revise.
  - `model_response` (amber) — narrative said "no change" but
    MARTIN's structure responded (Taylor Rule, Phillips curve, ...).
    Accept the trade-off or add a cancelling AF on the responding
    equation.
  - `not_addressed` (grey) — the describer didn't restate this
    claim (often a causal/structural framing absent from a
    numerical description).

- **History** — one row per orchestrator iteration. Each row shows
  which equations were touched at that pass, the audit verdict
  (badged), and a green **BEST** marker on the iteration the
  orchestrator picked as best (highest audit verdict, earliest on
  ties).

## What the run costs

Per click:

| Step | Model | Approx tokens | Approx cost |
|---|---|---|---|
| Propose | Sonnet 4.6 | 9k in / 1k out | ~$0.03 |
| Describe (per iter) | Haiku 4.5 | 1k / 0.3k | ~$0.002 |
| Audit (per iter) | Haiku 4.5 | 1k / 0.3k | ~$0.002 |
| Refine (per iter ≥ 2) | Sonnet 4.6 | 9k / 1k | ~$0.03 |

A typical 3-iteration round is ~$0.05-0.10 and takes ~2-4 minutes
of wall clock.

## Demo narratives to try

These all produce coherent rounds; the audit verdicts vary by how
internally consistent the narrative is in MARTIN's framework.

**Sticky services inflation (audit usually agrees):**

> Services inflation has been persistently sticky in our latest
> data. We think trimmed-mean inflation stays roughly 0.1
> percentage points higher than baseline through 2025Q2, fading
> thereafter as labour-market slack opens up. No change to our
> view on the cash-rate path.

**Labour-market structural shift (audit usually says "partial" or
"disagree" because the LUR shock forces Taylor Rule + Phillips
curve responses):**

> Employment growth has been persistently stronger than the model
> predicts since the post-COVID reopening — possibly reflecting
> structural changes in labour-force attachment (long-COVID exits,
> care-economy growth, immigration composition). We expect this
> to persist, lowering the unemployment rate by roughly 1.5
> percentage points below baseline through 2025Q4. No change to
> our view on the cash-rate path or inflation.

**Capex slowdown with consistent monetary response:**

> Business investment intentions have softened materially in the
> latest NAB capex survey. We expect non-mining business
> investment to run roughly 4% below baseline through 2025Q4,
> with knock-on weakness for real GDP and labour demand. The RBA
> is expected to respond by cutting the cash rate ~50bp lower
> than baseline by end-2025.

## Failure modes

- **"Run round" returns instantly with an error.** Either
  `ANTHROPIC_API_KEY` is unset or the targets cache is incomplete.
  Both errors appear in the status line at the bottom of the sidebar.

- **The LLM produces an empty adjustment list.** The narrative is
  too qualitative ("we're worried about the economy" with no
  numbers). The `Adjustments` tab will say "no adjustments";
  re-write the narrative with at least one quantitative claim and
  re-run.

- **The audit says "disagree" on every claim.** Often the narrative
  is over-constrained against MARTIN — see the `Audit` tab's
  diagnostics. `model_response` flags mean MARTIN is correctly
  responding to the AFs you accepted; the audit is doing its job.

- **The chart looks unchanged from baseline.** The LLM proposed
  near-zero values, or the audit picked iter 1 which was the
  initial (cleanest) proposal. Inspect the `Iteration history` tab.

## Limitations vs the full pipeline

The dashboard runs a one-shot LLM round. It does NOT:

- Re-fetch data (uses the cached `database_with_handover`).
- Re-build the sensitivity matrix (uses the cached one).
- Re-solve the baseline (uses the cached one).
- Apply a human-in-the-loop approval step. `review_and_approve()` is
  interactive by default (`interactive = base::interactive()`), but the
  dashboard deliberately runs it non-interactively — what the LLM proposes is
  what gets solved — because a browser session has no R console to block on
  the CSV edit. The deterministic `mechanical_audit()` still runs, so a
  wrong-direction add-factor is still flagged. For a gated round with the
  add-factor table edited by hand, use the targets pipeline with the
  `approved_adjustments` target set to `interactive = TRUE`.

For a full production round (fresh data + interactive approval +
report rendering), use `just pipeline` followed by `just report`.

## Visual design notes

The dashboard ships with a custom theme tuned for analytical work:

- **Palette** is ink-dark + warm paper, with a deep teal accent
  for the scenario series and grey for the baseline. Status colours
  follow agree=green, partial=amber, disagree=red.
- **Typography** uses the system sans-serif stack
  (`ui-sans-serif` -> `-apple-system` -> `Segoe UI` -> ...) so it
  matches the host OS conventions, with serif Georgia for the
  LLM's free-form description block (it reads more like a research
  note that way).
- **Tabular numbers** (`font-variant-numeric: tabular-nums`)
  throughout the tables and KPI strip so digits align vertically.
- **The header band** is fixed ink with a warm tan accent rule and
  a monospaced metadata strip on the right (horizon, re-estimation
  end, equation count).
- **No external font / icon dependencies**: everything renders
  offline from the host's system fonts. The dashboard works in an
  airgapped environment provided the targets cache and
  `ANTHROPIC_API_KEY` are available.

All theme tokens are defined as CSS variables (`--sibyl-ink`,
`--sibyl-paper`, etc.) at the top of `app/app.R`, so re-skinning is
a single block of edits.
