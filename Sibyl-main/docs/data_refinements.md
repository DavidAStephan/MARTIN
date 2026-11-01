# Data refinements: stock seeds and point-in-time vintages

Two remaining data items from the review roadmap and the income-side scope. Both
are honestly assessed here rather than half-built, because each is a *data
availability* limitation, not a modelling gap.

---

## 1. Stock-level seeds (govt debt `BG`, net foreign liabilities `VNFL`)

The fiscal and external stock accounting builds **flows** from real ABS data
(net lending from the reconciled fiscal block; the current account from real BoP
income). Only the **starting level** of each stock is a seed, and the model
accumulates the real flows forward from it.

**Status: calibrated proxies, which are realistic.**

| Stock | Seed | Real level | Verdict |
|---|---|---|---|
| `VNFL` (net foreign liabilities) | `nfl_seed` per cent of GDP (pass ~55) | Australia's net IIP ~55-60% of GDP | the proxy is on the money |
| `BG` (government debt) | `fiscal_bg_target` (default 30%) | Commonwealth+state net debt ~30-45% over the demo window | realistic |

**Why not the exact ABS series.** A clean quarterly **general-government net
debt** series is not published in the national accounts (ABS 5512.0 GFS is
*annual*; the AOFM publishes gross CGS on issue, not consolidated net debt). The
**net IIP level** exists in ABS 5302.0 but under opaque, sub-component series IDs
that did not resolve cleanly. Because the seeds only set the *level* (the changes
are already real) and the calibrated proxies match the real levels, this is a
low-value refinement. The path to do it properly: add the net-IIP-level series
(5302.0) for `VNFL` and a Chow-Lin'd GFS net-debt series (5512.0, annual) for
`BG`, then seed the stock *history* from them rather than the target ratio (the
same pattern the reconciled fiscal block already uses for the debt jump-off).

---

## 2. Point-in-time vintages (review rec D1) — a prospective-data task

The review's D1: "Build a true point-in-time vintage store and a vintage-aware
jump-off." SIBYL's `vintage` column is currently a **download-date stamp**, not a
point-in-time reconstruction, so a past round is not byte-reproducible against
the data as it stood at the time.

**Status: cannot be retro-fitted; it is a forward-accumulation task.** This is a
genuine data-infrastructure workstream, not something completable in one pass,
because the *historical* archives mostly do not exist to fetch:

| Source | Point-in-time availability | What's feasible |
|---|---|---|
| **FRED** (US world proxies) | **Yes** -- ALFRED archives, via `fredr`'s `realtime_start`/`realtime_end`. | A vintage-aware FRED fetch *is* buildable now and would make the FRED subset reproducible. |
| **ABS** (the bulk of MARTIN) | **No** historical real-time archive published. | Vintages can only be **accumulated prospectively** (snapshot each release going forward) -- or sourced from an external real-time database if one exists. |
| **RBA** | Limited. | Same: prospective accumulation. |

**Honest conclusion.** A *complete* point-in-time store is not achievable
retrospectively for the ABS/RBA series that dominate MARTIN — the real-time data
simply was not archived. The deliverable D1 actually implies is:

1. **Now:** a vintage-aware **FRED** fetch (ALFRED `realtime_*`) for the world
   proxies — the one source with a real archive — plus pinning `renv.lock`
   (already done) and the frozen 2019Q3 fixture for the reference path.
2. **Going forward:** snapshot every ABS/RBA release into the parquet cache keyed
   by *true* vintage date, so that *future* rounds become byte-reproducible even
   if past ones cannot be.
3. The add-factor handover (`fitted + af = actual`) should re-pin against the
   as-of data once (1)/(2) exist — the mechanism is ready; only the vintaged data
   is missing.

This is logged as the honest scope rather than implemented, because steps (2)/(3)
require data that accrues over time, and step (1) only covers the FRED minority
of the database. It does not block any current functionality — every feature and
the frozen reference path are unaffected.
