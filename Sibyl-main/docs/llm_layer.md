# How SIBYL's LLM judgement layer works

This document explains what the LLM is actually doing inside SIBYL,
with a worked example from the live pipeline. For the broader system
overview see [DESIGN.md](../DESIGN.md); for runtime details see
[next_session.md](../next_session.md).

The short version: SIBYL uses an LLM as a **translator between human
language and a deterministic econometric model**, not as a forecaster.
The LLM never decides what the economy will do. It takes a forecaster's
narrative ("we think LUR falls 1.5pp by 2025Q4 due to structural shifts")
and converts it into a structured set of numerical add-factors on
specific MARTIN equations. A separate LLM step reads the realised
projection and tells the forecaster whether the model's behaviour
matches their original narrative.

## The four steps

Each forecast round runs four LLM calls (or LLM-orchestrated steps):

```
                    +-----------------+
   sensitivity      |  pre-computed   |
   matrix  ---->    | once per round  |
                    +--------+--------+
                             |
   narrative                 v
       \             +-----------------+
        ----->       |  PROPOSE        |  Sonnet 4.6
       /             |  (LLM call)     |  ~30-60s
   baseline -------> |                 |
                     +--------+--------+
                              |
                              v adjustment_list
                     +-----------------+
                     |   solve_martin  |  no LLM
                     |   (bimets)      |  ~1-3s
                     +--------+--------+
                              |
                              v projection
                     +-----------------+
                     |  DESCRIBE       |  Haiku 4.5
                     |  (LLM call)     |  ~3s
                     |  (blind to      |
                     |   narrative)    |
                     +--------+--------+
                              |
                              v description (prose)
                     +-----------------+
                     |  AUDIT          |  Haiku 4.5
                     |  (LLM call)     |  ~3-4s
                     |  (compares      |
                     |   narrative +   |
                     |   description)  |
                     +--------+--------+
                              |
                              v audit verdict
              +---------------+----------------+
              |  if disagree, REFINE (re-prompt|  Sonnet 4.6
              |  LLM with audit gaps) and loop |  ~30-60s
              +---------------+----------------+
                              |
                              v
                  best-iteration result
```

Each step is implemented as a named function in
[`packages/judgement/R/`](../packages/judgement/R/). The orchestrator
that wires them together is `propose_with_refinement()`.

### Why two different models

Anthropic's pricing/capability ladder runs Haiku < Sonnet < Opus.

- **Propose / refine** is the token-heavy step. The prompt includes
  the equation catalogue, the sensitivity matrix, the narrative, the
  baseline, and (in refine) the prior proposal + audit feedback —
  about 8-10k tokens of input. The model also has to produce
  structured output that calibrates a vector of values across a
  horizon. **Sonnet 4.6** is much more decisive here than Haiku;
  documented live: Haiku misses the need for an NCR canceller AF
  that Sonnet figures out (see "When the round-trip is wrong" below).

- **Describe / audit** are cheap text tasks: read a small diff-vs-
  baseline summary and produce prose, or compare two short paragraphs.
  **Haiku 4.5** is enough and runs in ~3 seconds.

The split is per-step in `propose_with_refinement(model = ...,
model_propose = ..., model_describe = ..., model_audit = ...)`.

## The artifacts the LLM sees

### 1. The sensitivity matrix

Built once per pipeline run by `martin::sensitivity_matrix()`. For
each of the 56 adjustable MARTIN equations, this pre-solves the model
with a small standardized shock and records what happens to seven
headline aggregates at offsets h+1, h+4, h+8, h+16 after the shock.
Standardized shocks per LHS unit-type:

| LHS unit | Shock | Meaning |
|---|---|---|
| `log_diff` | +0.001 | +0.1pp on quarterly inflation/growth rate |
| `level`    | +0.05  | +0.05 on the variable's first difference |
| `percent`  | +0.10  | +10bp on the rate |

These are deliberately small so the simulator doesn't blow up and so
the LLM can scale them linearly. Format in the prompt:

```
- LUR (units=level, shock=+0.05 per quarter sustained over 4 quarters, decay_50):
  Y   : h+1=+0.02%, h+4=+0.24%, h+8=+0.52%, h+16=+0.56%
  RC  : h+1=+0.00%, h+4=+0.01%, h+8=+0.22%, h+16=+0.41%
  GNE : h+1=+0.02%, h+4=+0.19%, h+8=+0.50%, h+16=+0.62%
  LUR : h+1=+0.116pp, h+4=+0.227pp, h+8=+0.116pp, h+16=+0.097pp  [own equation]
  PTM : h+1=-0.00%, h+4=-0.02%, h+8=-0.05%, h+16=-0.08%
  P   : h+1=+0.00%, h+4=-0.01%, h+8=-0.04%, h+16=-0.08%
  NCR : h+1=-0.245pp, h+4=-0.603pp, h+8=-0.272pp, h+16=-0.223pp

- TLUR (units=percent, shock=+0.1 per quarter sustained over 4 quarters, decay_50):
  LUR : h+1=+0.002pp, h+4=+0.043pp, h+8=+0.163pp, h+16=+0.239pp
  NCR : h+1=+0.163pp, h+4=+0.468pp, h+8=+0.389pp, h+16=+0.289pp
  ...
```

The whole matrix is ~3.4k tokens; entries with no signal (|deviation
%| < 0.05% at all offsets) are filtered out for compactness. Renderer
is `judgement::format_sensitivity_text()`.

**Linearity probe (don't scale a non-linear deviation).** The propose
prompt tells the LLM that linear scaling of these deviations is
*approximately* valid — but MARTIN is non-linear, and a 4-quarter probe
should not be used to calibrate a 12-20-quarter shock without checking.
`sensitivity_matrix(..., probe_curvature = TRUE)` (the default) therefore
also solves each equation at **3x** the standardised shock and emits three
extra columns: `deviation_3x`, `curvature_ratio` (`= deviation_3x /
(3 * deviation)`, ~1 if linear) and `linearity_ok` (`abs(curvature_ratio -
1) < 0.25`). It also emits a per-equation `converged` flag from the 1x
solve; a non-converged or non-finite probe sets `deviation`/`deviation_3x`
to `NA` so the LLM is never handed garbage. `format_sensitivity_text()`
consumes these columns, and the prompt builder stops inviting linear
scaling on rows where `linearity_ok` is FALSE.

**Why this matters.** Before the sensitivity matrix landed, the LLM
was guessing magnitudes from in-context examples. On the same LUR
narrative across different runs it would flip between LUR (right
equation) and TLUR (slow pass-through, wrong magnitude). Comparing
the two rows above tells the LLM directly that an LUR shock of 0.05
moves LUR by +0.227pp at h+4 but a TLUR shock of 0.10 only moves LUR
by +0.043pp at h+4. The choice becomes obvious.

### 2. The equation catalogue

A 56-row table of which MARTIN equations the LLM is allowed to
adjust. Each row carries:

- `code` — the equation name (`PTM`, `LUR`, etc.)
- `plain_english` — a one-line description
- `units` — what the residual is measured in (`log_diff` / `level` /
  `percent`)
- `typical_af_sd` — a soft scale anchor (not always reliable; the
  sensitivity matrix is the primary calibration source)
- `transmission_channel` — which downstream variables this equation
  affects ("PTM -> P -> PC")
- `adjustable` — whether the LLM may propose an AF on this equation
  (some equations are identities; those aren't adjustable)

`judgement::catalogue_adjustable_text()` renders this as text for the
prompt.

### 3. The system prompt

The system prompt for the propose step assembles:

1. The rules of engagement (LLM is a translator, not a forecaster;
   every AF needs a rationale lifted from the narrative; magnitudes
   should be calibrated against the sensitivity matrix; ...).
2. Three worked examples of past SIBYL rounds (sticky inflation on
   PTM; structural shift on TLUR with documented 5x undershoot; LUR
   direct cyclical).
3. A "critical heuristic" block: AFs on trend / NAIRU / R-star
   equations pass through to the corresponding cyclical variable at
   only ~25-40% of their level shift in typical projection windows.
4. The equation catalogue.
5. The sensitivity matrix.

The whole prompt is around 8-10k tokens. Source: `system_prompt_propose()`
in [`packages/judgement/R/llm_helpers.R`](../packages/judgement/R/llm_helpers.R).

### 4. The user message

The user message for propose is short:

```
Forecast-round narrative:

Employment growth has been persistently stronger than the model
predicts since the post-COVID reopening - possibly reflecting
structural changes in labour-force attachment (long-COVID exits,
care-economy growth, immigration composition). We expect this to
persist, lowering the unemployment rate by roughly 1.5 percentage
points below baseline through 2025Q4. No change to our view on the
cash-rate path or inflation.

Baseline projection (headline aggregates):

Y: ... last 12 quarters of baseline values, summarised ...
LUR: 2023Q1=5.34, 2023Q2=5.42, ..., 2025Q4=5.59
PTM: ...
[... headline glossary ...]

Return a structured proposal. Use an empty adjustments array if the
narrative doesn't justify any specific quantitative changes.
```

### 5. The structured output schema

The LLM is forced to return its response in this schema (via ellmer's
`type_object` / `type_array`):

```r
list(
  reasoning = "<brief overall reasoning>",
  adjustments = list(
    list(
      equation        = "LUR",
      horizon_start   = "2023Q1",
      horizon_end     = "2025Q4",
      values          = c(-0.125, -0.125, ..., -0.125),  # one per quarter
      rationale       = "Employment stronger than model predicts due to ...",
      channel         = "LUR -> NCR -> Y; PTM via Phillips curve",
      expected_effect = "-1.5pp LUR by 2025Q4",
      confidence      = "medium",
      tail            = "carry"
    ),
    ...
  )
)
```

Schema source: `proposal_schema()` in `llm_helpers.R`. The LLM
literally cannot return free-form text here — structured output is
how SIBYL avoids parsing hallucinated JSON.

**Tail default.** The `tail` field defaults to **`"decay_50"`**, with `"zero"`
and `"carry"` available. Add-factors land on equation *residuals*, and most
MARTIN equations are in growth-rate / first-difference form, so a sustained
`"carry"` shock makes the variable's *level* diverge without bound (a live
round with `"carry"` on LUR drove modelled unemployment negative). `"decay_50"`
tapers the per-quarter shock past the horizon so a sustained *level* target
(e.g. "LUR ~1pp below baseline from 2026 onward") converges — and it also
reproduces the EViews `_a(-1) * -0.5` historical-residual handover rule. Use
`"carry"` only for an equation whose residual is on the level itself (e.g. the
TLUR trend); use `"zero"` for a one-off announcement.

**Bounds.** Each proposed value and the horizon length are guardrailed:
`|value|` must stay under per-unit ceilings (`log_diff <= 0.02`, `level
<= 1.0`, `percent <= 5.0` per quarter) and the horizon under 60 quarters,
keyed to the equation's `units`. Override for a deliberate extreme shock via
`options(sibyl.af_ceiling = ...)` / `options(sibyl.af_horizon_ceiling = ...)`.

## A worked example: the labour-market gap narrative

This is captured from a live pipeline run on 2026-05-26. Sonnet 4.6
for propose, Haiku 4.5 for describe + audit.

### Narrative

> Employment growth has been persistently stronger than the model
> predicts since the post-COVID reopening - possibly reflecting
> structural changes in labour-force attachment (long-COVID exits,
> care-economy growth, immigration composition). We expect this to
> persist, lowering the unemployment rate by roughly 1.5 percentage
> points below baseline through 2025Q4. No change to our view on the
> cash-rate path or inflation.

### What the LLM proposed

A single equation, twelve quarters, sustained -0.125 with `decay_50` tail:

```
equation: LUR
horizon:  2023Q1 to 2025Q4 (12 quarters)
values:   rep(-0.125, 12)
tail:     decay_50
rationale:        "Employment growth has been persistently stronger
                   than the model predicts ..."
channel:          "LUR -> NCR -> Y; PTM via Phillips curve"
expected_effect:  "-1.5pp LUR by 2025Q4"
confidence:       medium
```

The LLM correctly picked LUR (cyclical) over TLUR (trend) because
the sensitivity matrix showed it: LUR-shock 0.05 → LUR moves
+0.227pp at h+4; TLUR-shock 0.10 → LUR moves only +0.043pp at h+4.
The cyclical channel is ~5x faster, so for a magnitude-quantified
narrative LUR is the right lever.

The magnitude calibration is roughly right by linear scaling: if
0.05 produces ~0.23pp on LUR at h+4, then 0.125 (2.5x larger) for
12 quarters with decay_50 should produce roughly 1.3-1.5pp
cumulative — matching the narrative target.

### What the model produced

After `solve_martin()`, the projection at 2025Q4:

| Variable | Baseline | Scenario | Diff |
|---|---|---|---|
| LUR | 5.59% | 4.26% | **-1.33pp** |
| NCR | 1.51 | 4.64 | **+3.13pp** |
| P (CPI)   | 468 | 473 | **+1.21 (+0.26%)** |
| Y (real GDP) | 483,924 | ~470,000 | **~-2.8%** |

LUR target hit within tolerance (-1.33pp vs -1.5pp; the audit
accepted "roughly 1.5pp"). NCR and CPI moved — which the narrative
said they shouldn't.

### What the describer wrote (blind to narrative)

The describer sees only the diff-vs-baseline numbers (with a
glossary translating NCR → "nominal cash rate", etc.) and writes:

> This projection shows a sustained economic contraction relative to
> baseline, with real GDP declining by 0.6% in 2024Q1 and
> progressively deepening to 2.8% below baseline by end-2025. The
> weakness is driven by a substantially higher cash rate—reaching
> 3.13 percentage points above baseline by 2025Q4—which dampens real
> household consumption (down 1.2% by 2025Q4) and gross national
> expenditure (down 2.6% by year-end 2025). The tighter monetary
> policy delivers modest disinflationary effects [...] while the
> unemployment rate falls materially below baseline (reaching 4.26%
> by 2025Q4 versus a baseline of 5.59%). [...]

The describer does NOT see the narrative. This is structural — if it
did, the round-trip audit becomes trivially satisfied because the
describer just mirrors the narrative's framing.

### What the audit said

The audit compares narrative against description, claim-by-claim:

| claim | status |
|---|---|
| Employment growth has been persistently stronger than the model predicts | agree |
| Unemployment rate expected to be roughly 1.5 percentage points below baseline | agree |
| This employment strength may reflect structural changes in labour-force attachment | not_addressed |
| No change to our view on the cash-rate path | **disagree** |
| No change to our view on inflation | **disagree** |

`overall_match: disagree` — because two of five claims disagreed.

### What `diagnose_audit()` did

Raw "disagree" is a blunt verdict. `judgement::diagnose_audit()` runs
a heuristic classifier on each row:

| claim | category | variable | diff_at_end | explanation |
|---|---|---|---|---|
| Employment stronger | agree | — | — | Audit accepted. |
| LUR -1.5pp | agree | — | — | Audit accepted. |
| Structural changes | not_addressed | — | — | Description doesn't engage with the causal story. |
| Cash-rate unchanged | **model_response** | NCR | +3.13pp | Narrative asserted no change but NCR moved +3.13pp. Likely a MARTIN endogenous response (Taylor Rule). Add an NCR AF to suppress, or accept. |
| Inflation unchanged | **model_response** | P | +1.21 | Narrative asserted no change but P moved. Likely Phillips-curve response. |

This is the **most important interpretive step**. Without it, the
audit just says "disagree" and the forecaster doesn't know whether:

- the LLM picked the wrong equation,
- it sized the AF wrong, or
- MARTIN's structure is responding to the AF in ways the narrative
  didn't anticipate (which is a feature of using a structural model,
  not a bug of the LLM).

In the LUR case all three "disagreements" except the LUR magnitude
itself are `model_response` — they're the cost of insisting that
unemployment fall 1.5pp without giving the Taylor Rule and Phillips
curve room to respond. The forecaster can either:

1. **Accept the trade-off** — note that LUR -1.5pp comes with NCR
   +3pp and inflation +1.2 (= 0.26%) in this model.
2. **Add cancelling AFs** — propose an additional AF on NCR holding
   the cash-rate path constant, and one on inflation if needed.
   Costs more cross-equation complexity but matches the narrative
   more strictly.
3. **Revise the narrative** — drop the "no change to cash rate"
   stipulation because it's structurally inconsistent with the LUR
   shock.

The diagnostic surfaces the choice; it doesn't make it.

### The LLM-independent fidelity gate: `mechanical_audit()`

The narrative audit above is itself an LLM step and can be fooled by prose.
SIBYL therefore runs a second, fully deterministic check that needs no model
call: `judgement::mechanical_audit(adjustments, projection, baseline)`. For
each adjustment that declares a `target_variable` and an `expected_direction`
(`"up"` / `"down"` / `"none"`), it compares the declared direction against
the realised horizon-end projection-minus-baseline diff and returns a tibble
`(equation, target_variable, expected_direction, realised_diff, agrees)`.
`agrees` is TRUE/FALSE, or NA when there is nothing to check (no declared
target, or the variable is absent from the projection). Because it is
computed straight from the numbers, it catches the case where the prose
audit "agrees" but the model actually moved the target the wrong way. Run it
alongside `diagnose_audit()`; both feed the round report.

### The human-approval gate and `exogenize` round-trip

Before any of the LLM audit steps, the proposal passes through
`review_and_approve()`, which is interactive by default (`interactive =
base::interactive()`). It writes the proposal to a review CSV (with a hidden,
non-editable `adjustment_id` keying each row back to its adjustment so
human edits regroup correctly), surfaces the list of variables to
**exogenise** — hold at the baseline path — and blocks for human edits. The
exogenize list is persisted to a sidecar (`paste0(csv_path, ".exogenize")`)
and re-attached to the approved list, so it survives the gate and is not
silently dropped when a human edits the table. Unattended `_targets.R` runs
require an explicit approval token (`SIBYL_APPROVE=1` or the `approve_token`
target), or the pipeline stops on un-reviewed proposals; calling
`review_and_approve(interactive = FALSE)` directly still bypasses (for tests).

## When the round-trip is wrong: the refinement loop

If `overall_match != "agree"` and we have iterations left,
`propose_with_refinement()` re-prompts the LLM with the prior proposal +
realised description + audit verdict, asking for revisions. Default
`max_iters = 3` (one initial + up to two refinements).

The LLM can:
- adjust magnitudes on existing equations,
- extend/shorten the horizon,
- add cancelling AFs (e.g. NCR canceller for the labour-market case),
- drop side-effect-laden AFs.

### Over-correction: why we use best-iter selection

In practice the LLM over-corrects. A live example from the LUR
narrative on Haiku (the cheaper model):

| Iter | AFs | LUR end | NCR end | Audit |
|---|---|---|---|---|
| 1 | LUR -0.12 | -1.28pp | +3.00pp | partial |
| 2 | + NCR -0.25 + PTM -0.0005 (cancellers) | -3.21pp | -2.38pp | disagree (over-corrected!) |
| 3 | LUR -0.19 + NCR -0.75 | -2.13pp | -0.34pp | disagree |

The cancelling AFs the LLM added in iter 2 moved NCR below baseline
(it was supposed to suppress the Taylor Rule, not invert it). Iter 3
over-corrected further. `pick_best_iteration()` scores by audit
verdict (agree > partial > disagree), prefers the earliest on ties,
and returns iter 1 here — the cleanest proposal.

Without best-iter selection, the orchestrator would return the worst
iteration. With it, the loop becomes "find the simplest proposal
that meets the most claims."

Sonnet 4.6 on the same narrative figures out the canceller without
overshooting:

| Iter | AFs | LUR end | NCR end | Audit |
|---|---|---|---|---|
| 1 | LUR -0.125 | -1.33pp | +3.13pp | disagree |
| 2 | (cancellers, over-corrected) | varies | — | — |
| 3 | LUR + NCR canceller correctly sized | -1.03pp | +1.05pp | **partial** |

Best-iter picks 3 (partial beats disagree).

## Failure modes

### LLM non-determinism on equation choice

On consecutive runs of the same narrative, the LLM can pick different
equations. The sensitivity matrix substantially narrows this (it told
the LLM to prefer LUR over TLUR) but doesn't eliminate it. Symptoms:
the multi-narrative coherence check
([`scripts/multi_narrative_coherence_check.R`](../scripts/multi_narrative_coherence_check.R))
shows ~100% rate of picking the right *channel* (PTM for inflation,
LUR/TLUR for labour, IBN for capex) but the exact equation within
that channel can vary.

Mitigation: the refinement loop catches gross mistakes; the audit's
`disagree` verdict + `diagnose_audit()` surfaces them to the
forecaster.

### Over-constrained narratives

Some narratives are logically inconsistent in MARTIN's framework.
"LUR falls 1.5pp AND cash rate unchanged AND inflation unchanged"
cannot be satisfied: the Taylor Rule and Phillips curve must respond
to a labour-market shock of that size. The audit will always return
`disagree` here, and the right answer is to either accept the
trade-off or revise the narrative — not to keep iterating.

The `diagnose_audit()` `model_response` category exists exactly to
surface this distinction to the forecaster.

### Magnitude undershoot/overshoot

Even with the sensitivity matrix the LLM doesn't always size AFs
correctly first try. The refinement loop helps. Failing that, the
forecaster reviews `proposed_adjustments` (interactive mode of
`review_and_approve()`) and edits the values manually before MARTIN
solves.

## Where each artifact lives in code

| Artifact | Path |
|---|---|
| `propose_adjustments()` | [`packages/judgement/R/propose_adjustments.R`](../packages/judgement/R/propose_adjustments.R) |
| `refine_adjustments()`, `propose_with_refinement()`, `pick_best_iteration()` | same file |
| `describe_projection()`, `compare_narrative_to_description()`, `diagnose_audit()`, `mechanical_audit()` | [`packages/judgement/R/describe_projection.R`](../packages/judgement/R/describe_projection.R) |
| `review_and_approve()`, `reconstruct_adjustments()` (human gate + exogenize round-trip) | [`packages/judgement/R/propose_adjustments.R`](../packages/judgement/R/propose_adjustments.R) |
| `solve_martin_stochastic()` (opt-in uncertainty bands) | [`packages/martin/R/solve_martin.R`](../packages/martin/R/solve_martin.R) |
| `system_prompt_propose()`, `format_sensitivity_text()`, `projection_diff_text()`, schemas | [`packages/judgement/R/llm_helpers.R`](../packages/judgement/R/llm_helpers.R) |
| `adjustment()` S3 class + validator + `expand_adjustments()` | [`packages/judgement/R/adjustment.R`](../packages/judgement/R/adjustment.R) |
| `sensitivity_matrix()` (pre-compute) | [`packages/martin/R/sensitivity_matrix.R`](../packages/martin/R/sensitivity_matrix.R) |
| Pipeline wiring (targets) | [`_targets.R`](../_targets.R) |
| Round report (renders all of this) | [`reports/round.qmd`](../reports/round.qmd) |
| Demo scripts | [`scripts/lur_gap_walkthrough.R`](../scripts/lur_gap_walkthrough.R) (manual AF construction), [`scripts/multi_narrative_coherence_check.R`](../scripts/multi_narrative_coherence_check.R) (3-narrative probe) |

## How to extend it

### Add a new MARTIN equation as adjustable

1. Add the row to `packages/martin/inst/extdata/equation_catalogue.csv`
   with `adjustable = TRUE`, a `plain_english` description, the
   `units` of the equation's LHS residual, and a `transmission_channel`
   sketch.
2. Rebuild the sensitivity matrix (`tar_invalidate(sensitivity_matrix)
   ; tar_make()`).
3. The new equation appears in the propose prompt automatically. No
   judgement-package code changes needed.

### Add a new headline aggregate to the diff_text glossary

If the LLM keeps misinterpreting a variable, add a row to
`.variable_glossary` in `llm_helpers.R`. The describer will use the
plain-English label.

### Tune the prompt

`system_prompt_propose()` is plain text — edit it directly. Examples
of changes that worked:
- The "scale guidance" block: spell out what `value=0.001` means on a
  `log_diff` equation. Stopped the LLM proposing catastrophic shocks.
- The few-shot worked examples block (Examples A/B/C): three concrete
  rounds with realised values and lessons. Stopped the LLM
  hallucinating that TLUR's pass-through is fast.
- The sensitivity-matrix preamble: tells the LLM that linear scaling
  is approximately valid. Lets it do magnitude arithmetic instead of
  guessing.

### Add a new diagnostic category

`diagnose_audit()` currently has five categories (`agree`,
`not_addressed`, `translation_gap`, `model_response`, `unclassified`,
`narrative_conflict`). Add cases via `detect_variable_in_claim()` and
`claim_asserts_no_change()` — both are pattern-matching functions in
`describe_projection.R`.

## Cost and latency

A typical round runs in ~3-4 minutes wall clock. Breakdown:

| Step | Model | Tokens (approx) | Cost (approx) |
|---|---|---|---|
| Sensitivity matrix (one-shot, cached) | — | — | ~30s solver, no LLM |
| Propose | Sonnet 4.6 | 9k in / 1k out | ~$0.03 |
| Solve (in-loop) | — | — | ~2s each |
| Describe (per iter) | Haiku 4.5 | 1k in / 0.3k out | ~$0.002 |
| Audit (per iter) | Haiku 4.5 | 1k in / 0.3k out | ~$0.002 |
| Refine (per iter ≥ 2) | Sonnet 4.6 | 9k in / 1k out | ~$0.03 |

Total per round: ~$0.05-0.10 across three iterations. Cheap enough
to run interactively during forecast preparation.
