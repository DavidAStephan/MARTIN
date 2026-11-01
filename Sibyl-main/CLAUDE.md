# CLAUDE.md — context for sessions

This file is loaded automatically by Claude Code. Keep it current as the
project evolves.

## What SIBYL is, in one paragraph

SIBYL automates a central-bank-style forecast round using public data only.
The LLM layer is strictly a **translator and drafter**, not a forecaster. It
converts narrative statements into proposed add-factors on specific MARTIN
equations (each with a rationale), and it drafts prose explaining solved
projections. Humans always see and approve numerical adjustments before they
enter a solve. The models produce the numbers; the LLM handles the impedance
mismatch between human language and model inputs.

## Architecture

Four R packages under [packages/](packages/), each independent and properly
namespaced:

| Package | Role |
|---|---|
| [sibyldata](packages/sibyldata/) | Wraps `readabs`, `readrba`, `fredr`, OECD; returns tidy panels with vintage tracking; storage as parquet via `arrow`. |
| [nowcast](packages/nowcast/) | Bridge equations + simple models (likely `fable`) producing Q+0 and Q+1 for the variables MARTIN needs as handover. Deliberately simple. |
| [martin](packages/martin/) | Wraps the `bimets` implementation of MARTIN. Takes (a) starting database, (b) exogenous paths, (c) a list of add-factors keyed by equation and horizon. Returns a solved projection as a tidy data frame. |
| [judgement](packages/judgement/) | LLM-facing. `propose_adjustments(narrative, baseline)` returns structured add-factor proposals with rationales; `describe_projection(projection, baseline)` drafts prose explaining differences from baseline. Uses `ellmer` with structured outputs via `type_object()`. |

Pipeline orchestration lives in [_targets.R](_targets.R). Reports are Quarto
documents under [reports/](reports/).

The full LLM-layer architecture (propose / describe / audit / refine, the
sensitivity matrix, the diagnostic classifier, worked examples) is
documented in detail at [docs/llm_layer.md](docs/llm_layer.md).

## Design principles to enforce

1. **The LLM does not forecast.** Anything that looks like the model
   substituting its own judgement for a numerical model is a bug.
2. **Add-factors are first-class objects with metadata**, not bare numbers.
   The `adjustment` S3 class in [packages/judgement/R/adjustment.R](packages/judgement/R/adjustment.R)
   carries `{equation, horizon, value, rationale, channel, expected_effect,
   confidence, target_variable, expected_direction, owner, round_id}` plus
   tail behaviour (decay_50 / carry / zero). The default tail is **`decay_50`**
   (geometric decay, so a sustained level target on a growth-rate / first-
   difference equation converges instead of diverging; `carry` is for the rare
   level-residual equation). `decay_50` reproduces the EViews
   `_a(-1) * -0.5` rule, which governs *historical residual* handover into the
   forecast — not a deliberate forecaster shock — and oscillates sign quarter
   to quarter, so it is no longer the default. Add-factor magnitudes and
   horizon length are guardrailed against per-unit ceilings in
   `validate_adjustment_bounds()` (override via `options(sibyl.af_ceiling=)` /
   `options(sibyl.af_horizon_ceiling=)`).
3. **Round-trip consistency check.** After the human accepts adjustments and
   MARTIN solves, the LLM reads the solved projection and describes it. If the
   description doesn't match the input narrative, we've caught a translation
   error.
4. **Human-in-the-loop is structural.** Any path from narrative → solved
   forecast must pass through an explicit approval step where proposed
   add-factors are shown as a table with rationales before MARTIN sees them.
   `judgement::review_and_approve()` now defaults `interactive =
   base::interactive()`, so the gate is **ON by default** in any interactive
   session: it writes the proposal CSV, surfaces the `exogenize` list (held at
   baseline) via a sidecar, and blocks for human edits. The exogenize list now
   round-trips through the gate (persisted to `paste0(csv_path, ".exogenize")`
   and re-attached to the approved list). Unattended `_targets.R` runs no
   longer bypass silently: the pipeline **stops** on un-reviewed proposals
   unless an explicit approval token is set (`SIBYL_APPROVE=1` or the
   `approve_token` target). A second, LLM-independent fidelity gate
   `judgement::mechanical_audit()` deterministically checks each adjustment's
   declared `target_variable`/`expected_direction` against the realised
   projection-minus-baseline diff.
5. **Targets-based orchestration from day one.** Use `targets` even though it
   feels heavy.
6. **Reproducibility against the reference repos.** `martin` ships a frozen
   fixture (`packages/martin/inst/extdata/martin_data_fixture.xlsx`) copied
   from `references/bimets-main/MARTINDATA_XLSX.xlsx`. The regression test in
   [packages/martin/tests/testthat/test-regression-against-bimets.R](packages/martin/tests/testthat/test-regression-against-bimets.R)
   asserts SIBYL's `solve_martin()` with no adjustments matches the bimets
   reference solve.
7. **No UI yet.** Quarto reports as output, function calls as input.
8. **Public data only.** No internal-RBA data, no replacement of EA judgement
   processes.

## Where things live: MARTIN_EVIEWS vs MARTIN_BIMETS vs SIBYL

- **[references/MARTIN-master/](references/MARTIN-master/)** — the EViews / R
  implementation. The **canonical reference** for what MARTIN's equations are
  and how its data flow works. Read it when:
  - You need the plain-English description of an equation (the `'comments`
    in [equations.prg](references/MARTIN-master/Programs/equations.prg)
    drive [equation_catalogue.csv](packages/martin/inst/extdata/equation_catalogue.csv)).
  - You need to understand a splicing / backcasting recipe
    ([modify_data.prg](references/MARTIN-master/Programs/modify_data.prg)).
  - You need to understand how add-factors are constructed and decayed
    ([solve_model.prg](references/MARTIN-master/Programs/solve_model.prg)).
  - You need the ABS / RBA / FRED series-ID → MARTIN-variable map
    ([import_data.prg](references/MARTIN-master/Programs/import_data.prg)).

- **[references/bimets-main/](references/bimets-main/)** — the R / `bimets`
  port. SIBYL's `martin` package is built on this. Read it when:
  - You need the model file SIBYL actually uses
    ([MARTINMOD_AF.txt](references/bimets-main/MARTINMOD_AF.txt) — also
    vendored to `packages/martin/inst/extdata/`).
  - You need to see the canonical `ConstantAdjustment` add-factor pipeline
    ([BIMETS_MARTIN_LOAD.R](references/bimets-main/BIMETS_MARTIN_LOAD.R)).

- **[packages/martin/](packages/martin/)** — SIBYL's own MARTIN wrapper. The
  bimets `.txt` files are vendored (copied with attribution) into
  [packages/martin/inst/extdata/](packages/martin/inst/extdata/). The default
  model file is `MARTINMOD_AF.txt`.

  **What "frozen" actually means.** `MARTINMOD_AF.txt` is *not* a set of
  hardcoded identities and it does *not* load published EViews values as-is.
  It defines **95 `BEHAVIORAL>` equations**. Only **~51** carry
  `RESTRICT> c1=1`; the remaining behaviorals impose *real* cross-coefficient
  restrictions (e.g. `c4+c5+c6+c7=1`, `c4=0.5`) and leave free coefficients to
  be fit. `bimets::ESTIMATE` therefore **re-fits the free coefficients on
  every `load_martin()`**. "Frozen" in SIBYL means only that we keep the model
  file's embedded **2019Q3 estimation `TSRANGE`** (the published sample), so
  the re-fit reproduces the published coefficients — it does not mean "no
  estimation happens". Passing `coefficients = "reestimated"` with an
  `estimation_end` rewrites that `TSRANGE` and re-fits across a later (e.g.
  post-COVID) sample; that is the explicit opt-in described in the design
  principles. The pipeline default is **frozen** (`estimation_end = NULL`).
  `MARTINMOD_EST.txt` (true behavioural form for full re-estimation) is a
  future flag.

## Conventions

- R native. Tidyverse, `targets`, `ellmer`, `fable`, `bimets`, `arrow`,
  `testthat`, `quarto`.
- snake_case for code, UPPERCASE for MARTIN variable names (bimets is
  case-sensitive; we follow MARTINMOD_AF.txt).
- Explicit namespacing in package code (`dplyr::filter()`, not `filter()`).
- Tidyverse style guide.
- No emojis in code, files, or commits.
- API keys via [.Renviron](.Renviron.example) — never in source.
- Binary EViews `.wf1` files are not committed.
- The local parquet cache lives at `data/cache/` and is gitignored.

## How to work in this repo

- `just test` — run all package tests (`testthat`).
- `just check` — `R CMD check` each package.
- `just pipeline` — run the full `targets` pipeline.
- `just report` — render the round report.

## What you do NOT do without asking

- Re-estimate MARTIN coefficients across a non-published sample. The default
  is **frozen** (`estimation_end = NULL`): `bimets::ESTIMATE` re-fits the free
  coefficients but on the model file's embedded 2019Q3 `TSRANGE`, reproducing
  the published values. Re-estimating over a later sample (e.g. `"2025Q2"`,
  across the COVID break) is an explicit opt-in via `coefficients =
  "reestimated"`, not the default.
- Add an opinion to the LLM's output beyond what the input narrative says.
- Skip the human-approval step on add-factors.
- Commit `.Renviron`, API keys, or `.wf1` files.
- Move files out of `references/` — those are read-only history.
