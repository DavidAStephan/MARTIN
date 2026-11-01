# SIBYL

**Structured Inference, Bayesian Yarns, and Likelihoods.**

SIBYL automates a central-bank-style forecast round using public data only, and
explores whether LLMs can shift forecaster time away from mechanical
number-tweaking and toward narrative and judgement.

A forecast round usually goes: update data → nowcast / nearcast the current and
next quarter → hand off to a macro model (MARTIN) that extends the projection
into the medium term → apply judgemental adjustments ("add-factors") to reflect
things the model cannot see. Most of that work is mechanical. SIBYL automates
the mechanical parts and uses an LLM strictly as a translator and drafter:

- it converts narrative statements like "we think the output gap stays open
  longer than last round" into proposed add-factors on specific MARTIN
  equations, with rationales;
- it drafts prose descriptions of solved projections so a human can sanity-check
  that the numbers say what the narrative implied.

**The LLM does not forecast.** The macro model and the nowcasts produce
numbers. The LLM handles the impedance mismatch between human language and
model inputs, and every proposed numerical adjustment is shown to a human as a
table with rationales before MARTIN sees it.

The name nods to the classical Sibyls, who interpreted rather than pronounced.

---

## Repository layout

```
Sibyl/
├── packages/
│   ├── sibyldata/      data: readabs / readrba / fredr / OECD → tidy panels (parquet)
│   ├── nowcast/        bridge equations + simple models (fable) for Q+0, Q+1
│   ├── martin/         MARTIN wrapped around bimets; solves baseline + add-factors
│   └── judgement/      LLM-facing: propose_adjustments() and describe_projection()
├── references/
│   ├── MARTIN-master/  the EViews / R implementation (canonical equations + data flow)
│   └── bimets-main/    the bimets implementation that martin/ is built on
├── _targets.R          end-to-end pipeline: data → nowcast → martin → judgement → report
├── reports/            Quarto outputs of a round
├── data/cache/         local parquet cache (gitignored)
├── scripts/            ad-hoc / setup scripts
├── DESIGN.md           longer-form thinking on the four modules
├── CLAUDE.md           context for Claude Code sessions
└── justfile            common commands (test, check, pipeline, report)
```

Each package under `packages/` is a proper R package with `DESCRIPTION`,
`NAMESPACE`, `R/`, and `tests/testthat/`.

## Quick start

```sh
# 1. Clone, then copy the env example and fill in your API keys
cp .Renviron.example .Renviron
$EDITOR .Renviron

# 2. Bootstrap renv and install core dependencies
Rscript scripts/_init.R

# 3. Run the test suite for every package
just test

# 4. Run the end-to-end targets pipeline (data → nowcast → martin → judgement → report)
just pipeline
```

You'll need R ≥ 4.3, a recent Quarto, and the API keys listed in
[.Renviron.example](.Renviron.example) (FRED is required; Anthropic is required
for the judgement module).

## What's in the box

The pipeline runs end-to-end. A round goes:

1. **Data** — `sibyldata::update_data()` pulls live ABS, RBA, FRED, OECD,
   World Bank, and BoM panels, splices them onto MARTIN's variable schema,
   and applies derived formulas + identity chains + state-space-smoothed
   trends (PI_E, TLUR, RSTAR). `to_martin_database()` attaches a **provenance
   manifest** (`database_provenance(db)`) classifying every variable as
   `live` / `fixture_fallback` / `vendored_wf1` / `proxy` / `dummy` /
   `derived`, so coverage is read off the manifest rather than a single
   headline percentage. Note the catalogue "vintage" is a fetch-date stamp,
   not a point-in-time vintage (a past round is not yet bit-reproducible until
   realtime fetch args are added); `renv.lock` is committed to pin the R
   dependency set.
2. **Nowcast** — `nowcast::nowcast_handover()` bridges the ragged edge
   between the last quarterly observation and the projection start using
   monthly indicators (`bridge_monthly`, working on growth rates) with an
   ARIMA fallback. A committed chop-and-recover backtest on the bundled
   fixture posts a bridge MAPE of 9.8% (82% of points within 5%); see
   [packages/nowcast/inst/eval/handover_backtest.md](packages/nowcast/inst/eval/handover_backtest.md).
3. **Baseline solve** — `martin::solve_martin()` runs `bimets::SIMULATE`
   against MARTIN with no add-factors. The default is **frozen**
   coefficients: `bimets::ESTIMATE` re-fits MARTIN's free coefficients on
   every load, but on the model file's published 2019Q3 estimation sample, so
   it reproduces the published values. Re-estimating across a later sample is
   an explicit opt-in (`coefficients = "reestimated"` + `estimation_end`).
   `solve_martin_stochastic()` adds opt-in Monte-Carlo uncertainty bands.
4. **Sensitivity pre-compute** — `martin::sensitivity_matrix()`
   simulates a standardised unit shock on each of the 56 adjustable
   equations once, recording propagation onto headline aggregates.
5. **LLM round** — `judgement::propose_with_refinement()` does the
   agentic loop: propose add-factors against the narrative + sensitivity
   matrix (which carries a linearity probe so deviations aren't scaled
   blindly through MARTIN's non-linearity), solve, describe (blind), audit,
   refine if needed, pick the best iteration. Proposed add-factors pass
   through `review_and_approve()` (interactive by default) before MARTIN
   solves, and a deterministic `mechanical_audit()` checks each adjustment's
   declared target/direction against the realised diff.
6. **Report** — `reports/round.qmd` renders the full round with
   narrative coherence diagnostics.

The LLM-layer architecture is documented in
[docs/llm_layer.md](docs/llm_layer.md) with a worked example. For
interactive use, the Shiny dashboard at
[`app/app.R`](app/app.R) takes a narrative and runs the round
end-to-end with a live chart of the result — see
[docs/dashboard.md](docs/dashboard.md). Launch with `just dashboard`.

See [DESIGN.md](DESIGN.md) for the longer architectural story and
[CLAUDE.md](CLAUDE.md) for context to load into a coding session.
[next_session.md](next_session.md) is the live TODO list.

## Relationship to the reference repos

`references/MARTIN-master/` and `references/bimets-main/` are previous
implementations of MARTIN (the RBA's macroeconometric model of Australia) on
public data. They are kept in-tree as **read-only references** — the canonical
source for what MARTIN's equations are, what add-factors look like in practice,
and how the data flow has historically been organised. SIBYL's `martin` package
ships the bimets model definition files copied from `bimets-main/` (with
attribution); the EViews `.prg` files are not lifted but inform how `sibyldata`
and `martin` are structured.

## License

TBD. The reference repos are MIT (bimets) and unspecified (MARTIN-master);
SIBYL's own code will be released under a permissive open-source license to
match.
