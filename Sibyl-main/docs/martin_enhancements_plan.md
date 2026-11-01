# MARTIN Enhancements — Implementation Plan

Implementation plan for three structural enhancements identified in
[docs/martin_model_review.md](martin_model_review.md):

- **Workstream A** — a CES production function with capital, used the **EMMA
  way**: invert it for the labour input (employment) rather than imposing
  factor-demand first-order conditions, plus a capital-based output gap (review
  recs S1/S2/S5/S6).
- **Workstream B** — fiscal and external sector stock-flow accounting (review
  recs G1–G4, X1–X3).
- **Workstream C** — a non-linear (convex) Phillips curve in the unemployment
  gap, using the `LURGAP/LUR` form (review rec P1).

Each workstream is independent and shippable on its own; they interlock only
where noted (A's `YGAP` is an optional input to C; B's stock ratios feed the
optional FX/fiscal-rule feedback). Read [CLAUDE.md](../CLAUDE.md) first — the
design principles below are binding.

---

## Implementation status (built)

All milestones M0–M5 are implemented as an opt-in **model-feature** mechanism
([packages/martin/R/model_features.R](../packages/martin/R/model_features.R)):
load-time transforms of the bimets model text plus the data seeding bimets
requires, threaded through `load_martin(features=, feature_params=)` and
`solve_martin(...)`. **With no features the model and solve are byte-for-byte
unchanged**, so the frozen no-adjustment baseline stays bit-identical to the
bimets reference (regression test 35/35). Full suite: **786 pass, 0 fail**.

| Feature | Milestone | Tier | Status on the fixture |
|---|---|---|---|
| `output_gap` | M2 | T0 (diagnostic) | CES inverted EMMA-style. `YGAP` in [-1.6,+0.4]%, `LESTAR` tracks `LE` within ~1%. Baseline-neutral. `sibyldata::ces_calibration()` + `fit_efficiency_trend()`. |
| `external_accounting` | M3 | T0 | `CAD_GDP` [-4.1,+2.9]%, `NFL_GDP` [46,77]%. Identities exact, baseline-neutral. |
| `fiscal_accounting` | M3 | T0 | `BG_GDP` [7,32]%, `DEF_GDP` [-2.0,+1.4]%. Identities exact, baseline-neutral. Effective rates auto-calibrated (see below). |
| `fx_premium` | M4 | T2 (off) | Forecast: higher NFL/GDP depreciates `RTWI` (right sign, bounded), via the EC target. |
| `fiscal_rule` | M4 | T2 (off) | Forecast: holds `BG_GDP` at [30.3,31.7]% around target via a transfers rule. |
| `convex_ptm` | M5 | T3 (opt-in) | Swaps `c7*LURGAP` → `c7*(LURGAP/LUR)`, re-estimates PTM. Default keeps the pinned linear fit. |
| `inverted_le` | M5 | T3 (opt-in) | Retargets `LE` to the inverted-PF employment `LESTAR`, re-estimates. Needs `output_gap`. |

Tests: `test-model-features.R`, `test-production.R`, `test-accounting.R`,
`test-feedback.R`, `test-respecification.R`.

**M1 data wiring (done, with one honest caveat).** Real ABS series are now in
the catalogue and feed the features via their fallback hooks (verified live):

- **External (clean win):** `NFOY` = net primary income (ABS 5302.0 SA,
  A3535270A) and `NTRF` = net secondary income (A3535267L). The current account
  now reflects Australia's large primary-income deficit — `CAD_GDP` ~3% of GDP
  vs a ~0 trade balance, the correct economic effect.
- **Fiscal:** real social-assistance benefits (`NTRANSFERS`, A2302919C) feed
  spending; `NGREV`/`NGEXP`/`NGINT` (GG income-account revenue/expenditure/
  interest) are carried as reporting series. Revenue is still auto-calibrated to
  a balanced target so the open-loop debt demo stays bounded (`BG_GDP` [6,32]%,
  `DEF_GDP` [-1.6,+1.4]%).
- **Caveat (genuine, structural):** a *history-matched* deficit/debt path needs
  the ABS general-government **income account** reconciled with MARTIN's
  **expenditure-side** `NG` (they are different accounting bases — the income
  account excludes government investment). That is the income-side-of-GDP gap
  the review itself flags (§4.9 SF3); it is out of scope here, so the fiscal
  *balance* remains the bounded structural demo rather than the realised path.
  The debt seed and IIP-based `VNFL` seed likewise stay proxies (no clean
  quarterly govt-debt / currency-composition series wired yet).

None of this affects the default path or the regression test (the fixture has
none of the new series, so features fall back to proxies there).

bimets notes discovered during implementation: identities do **not** support
`@recode` (the `.txt` model uses none — confirming the review's ELB-floor
finding); every endogenous variable (incl. new identities) must be seeded with
defined initialisation values (NA fails); the CES is written in the harmonic
`sigma=0.5` form so no power operator is needed.

---

---

## 0. Shared constraints and strategy

Everything here is governed by one hard constraint and one taxonomy.

### 0.1 The reproducibility gate (design principle 6)

`packages/martin/tests/testthat/test-regression-against-bimets.R` asserts that
`solve_martin()` with **frozen** coefficients and **no** adjustments is
bit-identical (max |diff| = 0 on the headline set) to the canonical bimets
reference solve. **No enhancement may break this on the default path.** This is
non-negotiable and is the acceptance gate for every change below.

### 0.2 Change taxonomy (how each edit stays baseline-safe)

Every new piece of model code is classified into one of four tiers. Tiers
T0/T1 are baseline-neutral by construction; T2/T3 are gated OFF by default.

| Tier | What | Baseline impact | How it stays safe |
|---|---|---|---|
| **T0** | Passive *reporting* identities (e.g. `YGAP`, current account `NCA`, debt ratio `BG_GDP`) computed *from* solved variables and feeding *nothing* back. | None — they are extra outputs. | Add as `IDENTITY>` after the blocks they read. Confirm existing headline diffs stay 0. |
| **T1** | New behavioural *terms* whose new coefficient is **0 in frozen mode** (e.g. the debt-elastic FX term). | None when the coefficient is 0. | Ship the term with the coefficient pinned to 0 under `coefficients="frozen"`; only the opt-in path activates it. |
| **T2** | New *feedback* loops (fiscal reaction rule, FX risk premium) that change the solved path. | Changes the path when ON. | Behind an explicit switch (an `options(sibyl.*)` flag or a model-file variant), **default OFF**; default solve reproduces today's baseline. |
| **T3** | Re-specification / re-estimation of existing equations on a new sample (the inverted-PF employment target, the convex Phillips form). | Changes coefficients/equation form. | Only via an explicit opt-in variant (the existing `coefficients="reestimated"` pattern, or a model-file variant). CLAUDE.md: never re-estimate across a non-published sample without asking. |

**Rule of thumb:** build the T0 reporting layer first (it is free and
low-risk), then the T1 inert terms, then wire the T2 feedback behind switches,
and only then offer the T3 re-specifications. Each tier is independently
valuable and independently testable.

### 0.3 Where edits land

| Layer | File(s) | What changes |
|---|---|---|
| Model definition (solved) | [packages/martin/inst/extdata/MARTINMOD_AF.txt](../packages/martin/inst/extdata/MARTINMOD_AF.txt) | New `IDENTITY>`/`BEHAVIORAL>` blocks; opt-in equation variants. The bimets file is the one SIBYL actually solves. |
| EViews parity (reference) | [references/MARTIN-master/Programs/equations.prg](../references/MARTIN-master/Programs/equations.prg) is **read-only**. | Do **not** edit. |
| Data | [packages/sibyldata/inst/extdata/series_catalogue.csv](../packages/sibyldata/inst/extdata/series_catalogue.csv), `R/fetch_*.R`, `R/derived.R`, `R/state_space.R`, `R/transformations.R` | New ABS fetches + derived series + the efficiency-trend state space. |
| Model wrapper | [packages/martin/R/load_martin.R](../packages/martin/R/load_martin.R), `R/solve_martin.R`, `R/sensitivity_matrix.R` | Switch plumbing; calibration constants; opt-in variant selection. |
| LLM-facing catalogue | [packages/martin/inst/extdata/equation_catalogue.csv](../packages/martin/inst/extdata/equation_catalogue.csv) | New rows so the judgement layer can see/adjust the new equations. |
| Pipeline | [_targets.R](../_targets.R) | New data targets; provenance manifest entries. |
| Tests | `packages/*/tests/testthat/` | Baseline-neutrality tests + behaviour tests for each new block. |

### 0.4 Data and provenance

New external inputs must flow through the existing provenance machinery
(`classify_provenance()` / `database_provenance()`), with fixture fallbacks so
runs still complete when a source is unavailable. Annual-only GFS series need
Chow-Lin interpolation to quarterly (the `chowlin` transformation already
exists in `transformations.R`).

### 0.5 Cross-workstream sequencing

```
M0  T0 reporting identities (A: YGAP scaffold; B: CA, NCA, debt, NFL stocks)        <- baseline-neutral, do first
M1  Data: new ABS fetches (GFS revenue/transfers/debt; BoP primary income; IIP seed; hours)
M2  A: CES potential + efficiency trend -> real YGAP diagnostic                      <- baseline-neutral (parallel to TY_POT)
M3  B: fiscal + external identities live (calibrated to history)                     <- baseline-neutral (switches off)
M4  T2 feedback behind switches: debt-elastic FX (X3), fiscal rule (G3)              <- opt-in
M5  T3 re-specifications + validation: inverted-PF employment target (A2); convex PTM (C)  <- opt-in, governed
```

---

## 1. Workstream A — CES production function, inverted for employment

### A.1 Objective and approach

Give MARTIN a capital-based supply side **without** building a fully-structural
factor-demand system. Following **EMMA** (Treasury Paper 2021-09, §"Hours
worked", p28), use the CES production function as an *inversion / accounting
device*: output is the driver, and the production function is **inverted to back
out the labour input** consistent with that output, the predetermined capital
stock and a labour-augmenting technology trend. EMMA states it directly: *"The
equilibrium level of total hours worked, NH\*, is obtained by simply inverting
the main production function ... This inverted production function approach links
labour demand to output."*

We deliberately **do not** port the FR-BDF investment (capital) FOC or the
value-added-price (markup) FOC — that is "too structural" for MARTIN's
reduced-form character and would require the user cost of capital and a real-wage
marginal-product condition. Two deliverables:

1. **A capital-based output gap `YGAP`** (potential output from the CES at
   equilibrium inputs) — a diagnostic running parallel to the existing
   unemployment-gap spine `LURGAP` (review S2/S6). **Baseline-neutral (T0).**
2. **A capital-aware employment relationship** — MARTIN's employment equation
   `LE` error-corrects to the *inverted-production-function* employment level, so
   capital deepening shows up as a lower labour intensity of output (review
   S1/S5, EMMA Eq 6/6a). **Opt-in re-specification (T3).**

### A.2 The CES production function

Two-factor (capital + efficiency-augmented labour), constant returns, aggregate
(whole-economy in v1; an industry/market-sector split is a later refinement).
EMMA's form (their Eq A2.1), dropping the fixed factor MARTIN has no analogue for:

```
Y = γ · [ θN·(EFF·LHPP·LE)^ρ + θK·K^ρ ]^(1/ρ),    ρ = (σ−1)/σ,    θN + θK = 1
```

Mapping to MARTIN variables (all in-model except `EFF`):

| EMMA | MARTIN | Source |
|---|---|---|
| `V` (value added) | `Y` (real GDP) | identity |
| `NH` (total hours) | `LE · LHPP` (employment × hours/worker) | in-model |
| `λ^N` (labour-augmenting tech) | **new** `EFF` | new state-space trend |
| `K` (capital) | `KIBN + KIBRE` (non-mining + mining net capital) | accumulate in-model |
| `ξ` (capital utilisation, the slack var) | *implicit* — the inversion residual / cyclical productivity | not separately modelled |
| `A` (Hicks-neutral TFP) | folded into the scale `γ` | calibration |

**Efficiency trend `EFF`** — the one new latent series, the labour-augmenting
(Harrod-neutral) trend. Built like EMMA's λ^N (a **random walk with time-varying
drift** — the *permanent* productivity component, which is exactly the shape of
MARTIN's existing trend state spaces):

1. Invert the CES given observed `Y, K, LE, LHPP` and calibrated `(γ, θK, σ)` to
   get the raw efficiency residual `EFF_raw`.
2. Smooth/detrend with a local-linear-trend Kalman filter (reuse `fit_*_kfas` in
   `packages/sibyldata/R/state_space.R`); project forward by the drift state.

EMMA's cyclical components (Hicks-neutral TFP as AR(1); capital utilisation `ξ`
as the production-function residual) are **not** separately modelled — in MARTIN
they are simply the residual of the inversion, i.e. cyclical labour productivity.
This is the "not too structural" simplification you asked for: one permanent
labour-augmenting trend, everything cyclical absorbed in the residual.

### A.3 Inverting for employment (the headline mechanism)

For the two-factor CES the inversion is **analytic**. Solve the production
function for the effective-labour input `Leff = EFF·LHPP·LE`, given output and
capital:

```
Leff* = { [ (Y/γ)^ρ − θK·K^ρ ] / θN }^(1/ρ)

LE*   = Leff* / ( EFF · LHPP )                         # implied employment (heads)
```

`LE*` is the employment the production function requires to make output `Y` with
capital `K` and efficiency `EFF` — the EMMA Eq 6a target. MARTIN's employment
equation then error-corrects to it (EMMA Eq 6). Concretely, replace the
*long-run / error-correction target* of MARTIN's `LE` equation (currently a
reduced form: `LOG(LE) ~ LOG(Y) − 0.4·(LOG(RLC)−TLLA) − TLLA − TLLHPP`,
equations.prg L500) with `LOG(LE*)`, keeping the existing short-run dynamics
(lags, the `D(LOG(Y))` term) and re-estimating the adjustment coefficients:

```
DLOG(LE) = c1 + c20·( LOG(LE(-1)) − LOG(LE*(-1)) ) + [existing short-run terms] + ...
```

This is the change that brings capital into employment determination: when the
capital stock rises (an investment boom), `LE*` falls for given output, so the
model delivers the standard capital-deepening result. Because it re-specifies and
re-estimates an existing behavioural equation, it is **T3 (opt-in)**; the frozen
default keeps the published `LE` equation untouched.

**Numeric guard:** with `σ < 1` (so `ρ < 0`) the bracket `(Y/γ)^ρ − θK·K^ρ` must
stay positive for a real root; this holds comfortably in the empirically relevant
range but the `derived.R` helper and the model identity should `@recode`/clamp
against the degenerate case, exactly as MARTIN already guards `IBCR` and the
Taylor rule.

### A.4 Potential output and the output gap (diagnostic, T0)

Potential output is the same CES evaluated at **equilibrium** inputs — employment
at the NAIRU, the actual capital stock (EMMA treats capital as near its long-run
value), and the trend efficiency:

```
IDENTITY> NSTAR    EQ> NSTAR  = LPOP * (LPR_TREND/100) * (1 − TLUR/100)   # employment at the NAIRU
IDENTITY> LYSTAR   EQ> LYSTAR = log( γ·[ θN·(EFF·LHPP·NSTAR)^ρ + θK·(KIBN+KIBRE)^ρ ]^(1/ρ) )
IDENTITY> YGAP     EQ> YGAP   = ( log(Y) − LYSTAR ) * 100
```

- `LPR_TREND` = an HP/Kalman trend of participation `LPR` (small add); `TLUR`,
  `LPOP` exist.
- Keep the existing growth-accounting potential `TY_POT = TDLLA+TDLLPOP+TDLLHPP`
  **as is**; `LYSTAR`/`YGAP` run **in parallel** as the capital-based level
  measure. Surfacing the two measures' disagreement is itself the S6 diagnostic
  value (Okun-relationship drift). Replacing `TY_POT` in the rule/labour block is
  deferred until `YGAP` is validated.

### A.5 Calibration (Australian numbers, EMMA/FR-BDF methodology)

- **`σ` = 0.5** — EMMA and FR-BDF both land near 0.5 (gross complements);
  adopt as the v1 calibration. `ρ = (σ−1)/σ = −1.0`.
- **`θK`** — calibrate to the **Australian capital income share**, ≈ `1 − labour
  share`, with labour share ≈ `NHCOE/NY` (MARTIN's `NHWS`) adjusted for
  mixed/self-employed income; expect `θK ≈ 0.35–0.40`. **Do not import France's
  0.21 or impose a particular value blind** — pin it from a base-period average.
  `θN = 1 − θK`.
- **`γ`** — base-year-ratio trick (FR-BDF): with `Leff = K` assumed in a base
  year the CES collapses to `Y = γ·K`, so `γ = exp(mean_base[ log Y − log K ])`.
  Use a recent pre-COVID base (2018–2019).

Store as named scalars in the model file, mirrored/overridable in
`load_martin.R`. Pure calibration — never `ESTIMATE`d in frozen mode.

### A.6 Phasing

- **Phase A1 (T0, baseline-neutral) — the `YGAP` diagnostic.** Ship `EFF`,
  `LYSTAR`, `NSTAR`, `LPR_TREND`, `YGAP` as new series/identities that feed
  nothing. Report `YGAP` next to `LURGAP` each round. Fully reproducible.
- **Phase A2 (T3, opt-in) — invert for employment.** Re-specify the `LE`
  error-correction target as `LOG(LE*)` and re-estimate. Behind the
  `coefficients="reestimated"`-style opt-in; frozen default keeps the published
  `LE`. (This is also the natural moment to let the convex Phillips term use a
  blended gap — see Workstream C.)

### A.7 Data needs

| Series | Status | Source |
|---|---|---|
| `KIBN`, `KIBRE`, `LE`, `LHPP`, `LPOP`, `TLUR`, `LPR`, `NHCOE`, `NY` | in-model | existing |
| Total hours worked (for the `EFF` inversion) | partly (`HOURS` in nowcast handover) | ABS 6202.0 / 5206.0 |
| Net capital stock level (base-year `γ`/`θK` calibration) | new (calibration only) | ABS 5204.0 Table 58 |

No new live-API dependency beyond the total-hours pull (which has a fixture
fallback). The capital stock is already accumulated in-model.

### A.8 Code changes

- `sibyldata/R/state_space.R`: `fit_efficiency_trend()` — CES inversion + LLT
  Kalman; persist the smoothed-state covariance (cheap now, enables review D3
  trend-uncertainty propagation later).
- `sibyldata/R/derived.R` + `series_catalogue.csv`: `KSTAR=KIBN+KIBRE`, `EFF`,
  `LPR_TREND` derived rows; the analytic `LE*` helper.
- `martin/inst/extdata/MARTINMOD_AF.txt`: `NSTAR`, `LYSTAR`, `YGAP` identities +
  calibration scalars (T0); an opt-in `LE`-variant with the inverted target (T3).
- `martin/inst/extdata/equation_catalogue.csv`: rows for `YGAP`, `LYSTAR`, `EFF`
  (`adjustable=FALSE` for the identities).
- `martin/R/load_martin.R`: surface calibration constants; select the `LE`
  variant under the opt-in.
- `_targets.R`: efficiency-trend target + provenance.

### A.9 Acceptance criteria

- **A1:** frozen no-adjustment solve unchanged (regression test green); `YGAP`
  correlates sensibly with `−LURGAP` over history; `EFF` reverts to a stable
  drift in projection; the CES inversion round-trips (`LE*` recovers `LE` when
  `Y` is the fitted output). New `test-production-function.R`.
- **A2:** opt-in only; switch OFF ⇒ baseline bit-identical; switch ON ⇒ an
  investment-boom scenario lowers `LE*`/`YGAP` (more capacity per worker) and is
  mildly disinflationary, as every peer delivers.

---

## 2. Workstream B — Fiscal and external sector accounting

### B.1 Objective

Give MARTIN the two missing balance sheets so fiscal and external scenarios have
stock consequences: a **government budget-and-debt** layer (review G1–G4) and a
**net-foreign-liability / current-account** layer (review X1–X3). The
*identities* fit the existing Gauss-Seidel solver (they are recursive, like the
capital and household-balance-sheet blocks); the *feedbacks* (FX risk premium,
fiscal rule) are T2 opt-ins.

### 2A. Fiscal sub-block

**Identities (T0 → T2).** Build the nominal budget recursively. v1 keeps it
deliberately aggregate (no five-way tax disaggregation until data supports it):

```
IDENTITY> NREV     EQ> NREV   = ETR_DIRECT*NHDY + ETR_INDIRECT*NC + ETR_CORP*NY_corp_base   # effective-rate × base
IDENTITY> NSPEND   EQ> NSPEND = NG + NTRANSFERS                                              # NG exists; transfers new
IDENTITY> NLEND    EQ> NLEND  = NREV − NSPEND − INTG                                         # govt net lending
BEHAVIORAL/IDENTITY> BG       EQ> BG = TSLAG(BG,1) − NLEND + BG_VAL                          # debt stock, perpetual-inventory style
IDENTITY> INTG     EQ> INTG   = IIRG/100 * TSLAG(BG,1)                                       # debt interest, IIRG from N10R
IDENTITY> BG_GDP   EQ> BG_GDP = BG / NY * 100                                                # reporting ratio
IDENTITY> DEF_GDP  EQ> DEF_GDP = −NLEND / NY * 100
```

- `NG` (nominal public demand) exists. `NTRANSFERS`, the effective tax rates
  `ETR_*` and their bases, and the debt seed `BG(0)` are new (data below).
- `IIRG` (implicit interest rate on govt debt) anchors to `N10R` (already
  in-model) plus a calibrated maturity/spread wedge — wires the existing,
  currently-unused monetary→fiscal link (review G4).
- Calibrate the `ETR_*` so the identities **reproduce historical `NLEND`/debt
  in-sample** ⇒ the layer is baseline-neutral as a reporting block (T0).

**Automatic stabiliser + fiscal rule (T2, default OFF).** Make
`NTAX_HH = ETR_DIRECT·NHDY` cyclical through its base, an unemployment transfer
`NTRANSFERS` load on `LUR` (review G2). The **debt-stabilising rule** (review G3,
AUS-M `RTN` / EMMA form) adjusts the swing instrument toward a debt target:

```
ETR_DIRECT = ETR_DIRECT_BASE + RULE_ON * ( ρ1*(BG_GDP(-1) − BG_TARGET) + ρ2*ΔBG_GDP(-1) )
```

`RULE_ON` defaults to 0 (forecasting mode = Treasury-input division of labour);
`ρ1,ρ2 (~0.1)` via `options()`. The `BG(-1)` lag keeps the loop well-behaved.

### 2B. External sub-block

**Identities (T0 → T2).**

```
IDENTITY> NFOY    EQ> NFOY = ...                       # net primary (foreign) income — new data
IDENTITY> NCA     EQ> NCA  = (NX − NM) + NFOY + NTRF   # current account, nominal
IDENTITY> VNFL    EQ> VNFL = TSLAG(VNFL,1) − NCA + NFL_VAL   # net foreign liability stock
IDENTITY> NFL_GDP EQ> NFL_GDP = VNFL / NY * 100        # reporting ratio
IDENTITY> CAD_GDP EQ> CAD_GDP = −NCA / NY * 100        # the free narrative win (review missed-gap)
```

- `NX`, `NM` exist. `NFOY` (net primary income) and `NTRF` (net secondary
  income/transfers) are new BoP fetches; `VNFL(0)` seeds from the IIP.
- `NFL_VAL` = FX valuation on the foreign-currency tranche (review X5):
  `NFL_VAL = FC_SHARE·VNFL(-1)·(NUSD/NUSD(-1) − 1)` — **sign-check** against
  `NUSD`'s AUD/USD convention (a rise = appreciation reduces the AUD value of FC
  liabilities). Default `FC_SHARE` from ABS currency-composition; can be 0
  initially to keep it pure-flow.

**Net foreign income into household income (review X2, T2).** Route `NFOY` into
nominal income at the **identity level** (into `NHDY`/`NY`), *not* by perturbing
the `DLOG(NHOY)` ECM (avoids log-difference scale issues). Default the routing
weight to reproduce today.

**Debt-elastic FX risk premium (review X3, T1/T2 — the standout small/high
item).** Add a `VNFL`-ratio term to the `RTWI` error-correction *target*:

```
# current (equations.prg L585 / the RTWI append form L594):
#   dlog(RTWI) = const − c2*( log(RTWI(-1)) − c3*log(TOT(-1)) + 3.5/100*(WR2SP(-1) − ...) ) + ...
# add inside the error-correction bracket:
#   ... + PHI_NFL/100 * ( NFL_GDP(-1) − NFL_GDP_NORM )
```

`PHI_NFL` calibrated to the RBA-DSGE semi-elasticity (review cites this), pinned
to **0 in frozen mode** (T1); activated as a small calibrated value (T2) or
estimated. **Critical implementation note from the review:** add the term to
**both** the estimation equation form *and* the `MARTIN.append` model form, or
the coefficient never reaches the solve.

### B.3 Data needs (the real cost of Workstream B)

| Series | For | Source | Notes |
|---|---|---|---|
| General-govt taxation revenue, social benefits, interest payable | fiscal `NREV`, `NTRANSFERS`, `INTG` | ABS 5206.0 Tables 23–27 (quarterly) | preferred over GFS |
| Public debt stock seed `BG(0)` | debt recursion | ABS 5512.0 GFS / AOFM | annual → Chow-Lin; or seed level + accumulate |
| Net primary income `NFOY`, secondary income `NTRF` | external `NCA` | ABS 5302.0 BoP (quarterly) | direct |
| Net foreign liabilities seed `VNFL(0)`, currency composition `FC_SHARE` | NFL stock + valuation | ABS 5302.0 IIP; RBA/ABS currency composition | seed + accumulate |

All via new `series_catalogue.csv` rows + `fetch_abs()` (existing). Each needs a
fixture fallback and a provenance class. This is the "needs-new-data" half the
review flagged; the identities themselves are free.

### B.4 Code changes

- `sibyldata`: new catalogue rows + any Chow-Lin for annual GFS; derived
  current-account/debt seeds; provenance entries.
- `martin/inst/extdata/MARTINMOD_AF.txt`: fiscal + external identity blocks; the
  `PHI_NFL` term on `RTWI` (pinned 0 frozen); calibration + `RULE_ON`/`PHI_NFL`
  switch scalars.
- `martin/inst/extdata/equation_catalogue.csv`: rows for `BG_GDP`, `DEF_GDP`,
  `CAD_GDP`, `NFL_GDP`, `NCA`, `VNFL` (reporting) and the adjustable knobs.
- `martin/R/load_martin.R` / `solve_martin.R`: `options(sibyl.fiscal_rule=)`,
  `options(sibyl.fx_premium=)` plumbing; ensure new identities are in solve
  order and the exogenize machinery.
- `_targets.R`: fiscal + external data targets.

### B.5 Acceptance criteria

- **T0 reporting:** frozen no-adjustment solve bit-identical (identities inert);
  `CAD_GDP`, `BG_GDP`, `NFL_GDP` reproduce published history within calibration
  tolerance. New `test-fiscal-accounting.R`, `test-external-accounting.R`.
- **T2 feedback:** switches OFF ⇒ baseline unchanged; FX premium ON ⇒ a sustained
  current-account deficit gradually depreciates the AUD (sign/magnitude sane vs
  the DSGE); fiscal rule ON ⇒ a debt shock mean-reverts to `BG_TARGET`.

---

## 3. Workstream C — Non-linear Phillips curve (`LURGAP/LUR`)

### C.1 Objective

Make trimmed-mean inflation `PTM` respond **convexly** to the unemployment gap so
the model steepens in a hot economy and flattens as slack returns (review P1),
using the **`LURGAP/LUR` form** — which also harmonises `PTM` with the convex
form MARTIN's **wage** equation `PW` already uses
(`C(2)*(LURGAP(-1)/LUR(-1))`, equations.prg L355).

### C.2 The convex term

Current `PTM` (MARTINMOD_AF.txt, from equations.prg L397) closes with a **linear**
gap term `C(7)*LURGAP`:

```
D(LOG(PTM)) = C(1) + C(2)*( LOG(PEX(-1)) − C(3)*LOG(NULCBS(-1)) − (1−C(3))*LOG(PMCG(-1)) )
            + C(4)*D(LOG(PTM(-1))) + (1−C(4))*PI_E(-1)/400 + C(7)*LURGAP
```

Replace the linear term with the reciprocal/convex form:

```
            ... + C(7)*( LURGAP / LUR )
```

Mechanics: `LURGAP/LUR = (LUR−TLUR)/LUR = 1 − TLUR/LUR`. As unemployment `LUR`
falls (a tightening economy), the term grows in magnitude → the inflation
response **steepens convexly** in the gap, while it flattens as slack returns —
the empirically-documented convexity the linear curve misses. `C(7) < 0`
(more slack ⇒ lower inflation). It leaves `PTM`'s existing `RESTRICT` block (the
`(1−C(4))` homogeneity card) untouched. This is the same functional device
already trusted in `PW`, so it is conservative, not exotic.

### C.3 Baseline-neutrality and re-estimation

Because `LURGAP/LUR` **replaces** the regressor `LURGAP` (you can't recover the
linear term by zeroing a coefficient), the convex form is a **T3
re-specification**, handled as an opt-in variant:

- **Frozen default** keeps the published **linear** `C(7)*LURGAP` ⇒ the
  regression-against-bimets test stays bit-identical. (No change on the default
  path.)
- **Convex variant** swaps in `C(7)*(LURGAP/LUR)` and re-estimates `C(7)` on a
  sample that includes the 2021–23 inflation episode — selected via a model-file
  variant / the `coefficients="reestimated"`-style opt-in (the same pattern as
  the planned `MARTINMOD_EST.txt`). Per CLAUDE.md this is explicit and ask-first,
  surfaced as a diagnostic/sensitivity (estimate + SE + out-of-sample fit), never
  a silent default change.

### C.4 Interactions

- If Workstream A's `YGAP` is available, optionally form the gap on a blended
  measure (`LURGAP/LUR` plus a `YGAP` term), `λ=1` default ⇒ pure `LURGAP/LUR`.
  Keeps C independent of A by default.
- `martin::sensitivity_matrix(probe_curvature=TRUE)` (already shipped) becomes
  genuinely informative once `PTM` is convex — its `curvature_ratio`/
  `linearity_ok` columns will flag the `PTM` channel, which the LLM
  propose-prompt already consumes. Confirm the probe scales the convex term.
- Optionally extend the asymmetry to `PW`'s change-in-unemployment term (review
  P2, `pos()` device) as a follow-on; not required for C.

### C.5 Code changes

- `martin/inst/extdata/MARTINMOD_AF.txt`: the convex `PTM` variant form (default
  file keeps the linear term).
- `martin/R/load_martin.R`: select the convex `PTM` variant under the opt-in;
  frozen path keeps the linear form.
- `martin/inst/extdata/equation_catalogue.csv`: update `PTM`'s `plain_english` /
  `transmission_channel` to state the non-linearity so the LLM layer stops
  describing a linear curve.
- Tests: `test-phillips-nonlinear.R`.

### C.6 Acceptance criteria

- Frozen no-adjustment solve bit-identical (linear form retained on the default
  path).
- Convex variant: `C(7)` significant and correctly signed on the post-COVID
  sample; **out-of-sample 2021–25** RMSE for year-ended trimmed-mean inflation
  beats the linear curve; a "hot economy" scenario (low `LUR`, negative `LURGAP`)
  produces a visibly stronger inflation response than the linear model. Report
  linear-vs-convex slope stability as the P5 diagnostic.

---

## 4. Milestones (dependency-ordered)

| Milestone | Contents | Tier | Reproducible? | Effort |
|---|---|---|---|---|
| **M0** | Reporting-identity scaffolds: `YGAP` placeholder; `NCA`/`CAD_GDP`/`VNFL`/`BG_GDP` skeletons | T0 | yes (inert) | S |
| **M1** | New ABS data: GFS revenue/transfers/debt; BoP primary income; IIP seed; total hours | data | yes | M |
| **M2** | CES potential + efficiency-trend state space; real `YGAP` (parallel to `TY_POT`) | T0 | yes | L |
| **M3** | Fiscal identities live (calibrated to history); external identities live | T0 | yes | M |
| **M4** | T2 feedback behind switches: debt-elastic FX (X3), fiscal rule (G3) | T2 | yes (off) | M |
| **M5** | Opt-in T3 + validation: inverted-PF employment target for `LE` (A2); convex `PTM` (`LURGAP/LUR`) | T3 | n/a (opt-in) | L |

Do M0–M3 first: individually shippable, all baseline-neutral, delivering the new
diagnostics (parallel `YGAP`, CA/debt/NFL reporting) with zero risk to the frozen
default. M4–M5 turn on the economics.

---

## 5. Risks and open decisions

1. **`θK` calibration (AU, not France).** Calibrate to the Australian capital
   income share (~0.35–0.40); decide the mixed-income/self-employed treatment.
   *Owner decision.*
2. **CES inversion numeric guard.** With `σ<1` (`ρ<0`) the inversion bracket must
   stay positive; clamp the degenerate case (`@recode`), as MARTIN already does
   for `IBCR`/the Taylor rule.
3. **`LYSTAR` vs `TY_POT` reconciliation.** v1 runs both in parallel
   (recommended). Replacing `TY_POT` in the rule/labour block is deferred until
   `YGAP` is validated.
4. **Re-specifying `LE` changes a TSLS equation.** MARTIN's `LE` is the one TSLS
   equation; swapping its long-run target to `LOG(LE*)` re-estimates it — keep it
   strictly opt-in, and re-baseline `LE` together with the wage block (`RLC` feeds
   `PAE→NHCOE`) it interacts with.
5. **Whole-economy vs market-sector CES.** v1 uses whole-economy `Y` and total
   capital; EMMA models market branches per-industry. A split is a later
   refinement once the block is trusted.
6. **GFS quarterly availability.** Quarterly general-government income/outlay is
   in ABS 5206.0; the *debt stock* may be annual (5512.0) needing Chow-Lin.
   Confirm before promising quarterly debt dynamics.
7. **Re-estimation governance.** The inverted-PF `LE` and the convex `PTM` cross
   the COVID break ⇒ CLAUDE.md requires asking; ship as opt-in diagnostics, never
   the default.
8. **Efficiency-trend covariance.** Persist the Kalman smoothed-state covariance
   now (cheap) so review rec D3 (trend-uncertainty propagation) can reuse it.
9. **Provenance honesty.** Every new ABS pull needs a fixture fallback and a
   provenance class so degraded runs still complete and the manifest stays honest.

---

## 6. Test plan summary

| Test file | Asserts |
|---|---|
| `test-regression-against-bimets.R` (existing) | **Unchanged green** on every frozen no-adjustment path — the global gate. |
| `test-production-function.R` (new) | CES identity numerics; `EFF` inversion round-trips; `LE*` recovers `LE` at fitted output; `YGAP` ≈ sensible vs `LURGAP`; `γ` reproduces the base-year ratio; the `ρ<0` guard fires on the degenerate case. |
| `test-fiscal-accounting.R` (new) | Identities reproduce historical `NLEND`/`BG`/`CAD` within tolerance; rule OFF ⇒ baseline-neutral; rule ON ⇒ debt mean-reverts. |
| `test-external-accounting.R` (new) | `NCA`/`VNFL` reproduce history; FX premium OFF ⇒ baseline-neutral; ON ⇒ CAD depreciates the AUD with the right sign. |
| `test-phillips-nonlinear.R` (new) | Linear form retained ⇒ frozen bit-identical; convex variant ⇒ correct sign, beats linear out-of-sample 2021–25; hot-economy scenario more inflationary. |
| `test-baseline-neutrality.R` (new, cross-cutting) | For every T1/T2 switch and T3 variant, the default/OFF path reproduces the pre-change baseline exactly. |

---

*Plan prepared 2026-06-13. Grounds: the verified gap analysis in
[docs/martin_model_review.md](martin_model_review.md); the EMMA inverted-
production-function approach (Treasury Paper 2021-09, §"Hours worked", p28, and
Appendix C); and the FR-BDF supply block (Banque de France WP #1044, §3.1) for
the CES form and calibration methodology. Equation forms above are specification
sketches in bimets/MARTIN notation — exact `COEFF>`/`RESTRICT>` cards and
calibration values are to be finalised against the live database at
implementation time.*
