# Income Side of GDP — Scoping Document

Scopes the structural prerequisite flagged repeatedly in
[docs/martin_model_review.md](martin_model_review.md) (rec **SF3**) and surfaced
concretely as the open caveat in
[docs/martin_enhancements_plan.md](martin_enhancements_plan.md) M1: **MARTIN
builds nominal GDP only from the expenditure side**, so there is no
operating-surplus / profit flow, no corporate sector, and no income-side
reconciliation. This document scopes building one. It is a *scope*, not an
implementation — it defines the tiers, data, decisions, architecture, effort and
risks so the work can be planned and sequenced.

---

## 1. Why — what an income side unlocks

MARTIN's only build of nominal GDP is the expenditure identity
`NY = NC + NID + NIB + NG + NOTC + NV + NX − NM − NATS + NSD`. There is no
`GDP(I) = COE + GOS + GMI + (taxes − subsidies)` decomposition. Because the
profit/operating-surplus flow does not exist, several things are blocked — and
each is a named review recommendation:

| Unlocked by an income side | Review rec | Today |
|---|---|---|
| A **history-matched fiscal balance & debt path** (revenue/expenditure on a consistent income basis) | G1, G2 | M1 caveat — fiscal balance is a bounded structural demo because the ABS general-government income account can't be reconciled with expenditure-side `NG` |
| A **corporate sector**: operating surplus → tax + dividends + retained earnings | SF3 | absent (no profit flow exists) |
| A **corporate balance sheet + BGG financial accelerator** on firm leverage | SF4, F1, F5 | `NBRSP` keys on the aggregate unemployment gap, a reduced-form proxy |
| **Decompose** the lumped household non-labour income `NHOY` into property income + mixed income − taxes | G2, SF1 | `NHOY` is a single ECM lumping transfers/taxes/interest/dividends |
| A **full stock-flow-consistent sectoral matrix** (net lending sums to zero) | SF1, SF2 | partial SFC; no adding-up constraint |
| A **markup / profit-share channel** into the Phillips curve (mark-up shocks explain ~76% of CPI variance in the RBA DSGE) | prices_wages | no time-varying desired markup; `PEX` constructed to track `PTM` |
| The **GNI-vs-GDP wedge** (net foreign primary income) | external | `NFOY` now wired (M1) but not routed into a GNI/disposable-income build |

Exemplars (both Australian, both profiled in the review): **EMMA**'s four-agent
flow-of-funds "Sudoku" (household / corporate / government / external net lending
sums to zero every period) and **AUS-M**'s income-side reconciliation and
PSBR/debt accounting. The enabling primitive in both is the GDP(I) identity.

---

## 2. Design principles (inherited from the enhancements work)

1. **Feature-gated and baseline-neutral.** Ship as a new `income_side` feature
   (plus corporate sub-features) via the existing model-features mechanism
   ([packages/martin/R/model_features.R](../packages/martin/R/model_features.R));
   default OFF ⇒ the frozen no-adjustment baseline stays bit-identical (design
   principle 6). The household reconciliation in particular must reproduce
   `NHDY`/`NHOY` exactly when the feature is off, because consumption `RC`
   depends on `HDY` — a perturbation there would move the headline.
2. **Reconcile via an explicit statistical discrepancy.** `GDP(I) = NY − SD_I`,
   so the income side ties to the existing expenditure-side `NY` exactly rather
   than competing with it. (ABS publishes GDP(E), GDP(I), GDP(P) with their own
   discrepancies; we mirror that.)
3. **Incremental tiers, each shippable.** I-0 alone delivers the profit flow and
   the indirect-tax base; the corporate sheet is the last tier.
4. **Forecast-projectable, not just history-fitting.** Every income component
   must have a sensible forward rule (effective-rate×base, share-of-GDP, or a
   balance-sheet flow), not only an in-sample identity.
5. **Cross-check, don't double-define.** The labour/profit share from the income
   side should be consistent with the CES capital share `theta_k` calibrated for
   the `output_gap` feature — a useful consistency check, and a potential
   inconsistency to manage (see Decisions).

---

## 3. The tiers

### Tier I-0 — the GDP(I) primitive *(small; baseline-neutral; high enabling value)* — **IMPLEMENTED**

> **Status: shipped.** Implemented as the `income_side` model feature
> (`packages/martin/R/model_features.R`). On the fixture with real ABS `GMI`
> (A2303377R) and `TAX_PROD_NET` (A2303381F): `PROFIT_SHARE` 38–42%,
> `LABOUR_SHARE` 46–49% — both spot-on for Australia; the GDP(I) identity holds
> and the layer is baseline-neutral. `GOS` is the residual (absorbing the small
> income-side discrepancy, since ABS does not publish a clean SA SD(I)).
> Tests: `test-income-side.R`. Tiers I-1/I-2/I-3 below remain to scope/build.


The foundational identity. New reporting identities:

```
TAX_PROD_NET   (data: ABS 5206.0 A2303381F, taxes less subsidies on production & imports, SA)
GMI            (data: A2303377R, gross mixed income, SA)  -- or model as a share of GDP
GOS = NY - NHCOE - GMI - TAX_PROD_NET - SD_I              -- gross operating surplus, residual
PROFIT_SHARE = GOS / NY * 100                              -- reporting
LABOUR_SHARE = NHCOE / NY * 100                            -- = MARTIN's NHWS
```

`NHCOE` (compensation of employees) already exists. `GOS` falls out as the
residual (absorbing the income-side statistical discrepancy `SD_I`, or `SD_I`
carried explicitly — see Decisions). **Unlocks:** the operating-surplus/profit
flow (the primitive every later tier needs); the indirect-tax base for the
fiscal block; the profit/labour-share split for the markup channel.

- **Data:** 1 new direct series (`TAX_PROD_NET`); optionally `GMI` (else fold
  into GOS). All verified available (5206.0, SA).
- **Effort:** small. Pure identities + 1–2 data series; baseline-neutral.

### Tier I-1 — sectoral primary income *(medium)*

Allocate factor income to institutional sectors and build Gross National Income:

```
GOS_CORP   = GOS - GOS_DWELLINGS - GOS_GENGOV     (corporate operating surplus)
HH_PRIMARY = NHCOE + GMI + PROP_INC_HH            (household primary income: labour + mixed + property received)
GNI        = NY + NFOY                            (GNI = GDP + net foreign primary income; NFOY wired in M1)
```

Property-income flows (interest, dividends) between sectors come from the
sectoral income accounts (ABS 5206.0 household/corporate income accounts;
dividend series e.g. A85125848A verified available). **Unlocks:** household
primary income properly built (the input to the I-2 disposable-income
reconciliation); the GNI wedge; corporate operating surplus (input to the
corporate sector).

- **Data:** sectoral GOS split + household property income (dividends/interest
  receivable). Several new direct series.
- **Effort:** medium.

### Tier I-2 — secondary income: the fiscal & household reconciliation *(large — the core)* — **GOVERNMENT PART IMPLEMENTED**

> **Status: the fiscal reconciliation is shipped** (`fiscal_mode = "reconciled"`).
> It resolves the M1 caveat: total outlays = MARTIN's endogenous `NG`
> (consumption+investment) **plus** the ABS income-account payables (transfers +
> interest + subsidies) — the two are complementary, not the same basis (the M1
> bug subtracted `NG`, cancelling them). Revenue is endogenous (income tax on
> `NHDY`, corporate tax on the income-side `GOS`, production tax) with a residual
> plug to actual `NGREV`; interest uses the actual ABS series; debt is reported
> in annual-GDP units. On real ABS data 2010–19: `DEF_GDP` mean ~2.7% (peaking
> ~6.7% post-GFC, falling) and `BG_GDP` rising 31→43% — the realised Australian
> trajectory. Tests: `test-fiscal-reconciled.R`.
>
> **Household side (Phase 1) also shipped** as the `household_income` feature: a
> *baseline-neutral* decomposition of `NHOY` into income-account components
> (`HH_NONLAB` non-labour primary income, `NHTAX` taxes, `NTRANSFERS`,
> `NHOY_RESID`) plus the effective household tax rate `HH_TAXRATE` (18-22% on real
> ABS data, from HH_PRIMARY A2302917X and NHTAX A2302937J). `NHOY`/`NHDY`/`RC`
> stay untouched (the residual plugs to the existing `NHOY`). `NHOY_RESID` is
> ~35% of `NHOY` (~14% of `NHDY`) -- the definitional gap between MARTIN's
> modelled `NHDY` and the ABS household account, a useful diagnostic. Tests:
> `test-household-income.R`. **Still to do in I-2:** *Phase 2* -- make `NHOY` the
> sum of endogenous components (taxes responding to income, transfers to
> unemployment), which re-baselines `RC` (opt-in); and corporate retained
> earnings (feeds I-3).


The "Sudoku": secondary distribution of income (taxes and transfers) maps
primary income to disposable income, consistently across sectors.

```
Household:    NHDY = HH_PRIMARY - NTAX_HH + NTRANSFERS        (reconcile with the existing NHDY = NHCOE + NHOY;
                                                               i.e. decompose NHOY = PROP_INC_HH + GMI - NTAX_HH + NTRANSFERS)
Government:   NGREV = NTAX_HH + NTAX_CORP + TAX_PROD_NET + property income
              NGEXP = NG + NTRANSFERS + INTG + subsidies + other
              NLEND_G = NGREV - NGEXP                          (the *consistent-basis* balance -> resolves the M1 caveat)
Corporate:    RET_EARN = GOS_CORP - INT_CORP - DIV_CORP - NTAX_CORP   (corporate saving / retained earnings)
External:     net lending = -NCA                              (already from external_accounting)
```

**Unlocks:** the history-matched fiscal deficit/debt path the M1 work could not
deliver (because government revenue and expenditure are now on the same income
basis as `NHDY` and corporate income); the household income decomposition;
corporate retained earnings (input to I-3). The hard part is making the household
reconciliation **reproduce the existing `NHDY`** when the feature is off, and
project sensibly when on (taxes as effective-rate×base, transfers on `LUR`).

- **Data:** household & corporate income-tax series; corporate dividends/interest
  paid (sectoral accounts).
- **Effort:** large. The intricate reconciliation; ABS sector accounts carry
  their own discrepancies that must be parked somewhere.

### Tier I-3 — corporate balance sheet + financial accelerator *(large — caps the SFC agenda)* — **ACCELERATOR IMPLEMENTED**

> **Status: the financial accelerator is shipped** as the `corporate_accelerator`
> feature (the high-value F1/F5/SF4 payoff). It adds a corporate-leverage identity
> `LEV` (debt-to-annual-GDP, from ABS `DCORP` = private NFC loans A3427913W, or a
> proxy) and re-estimates the business borrowing spread `NBRSP` with a
> lagged-leverage term, so a more-indebted corporate sector raises the
> external-finance premium -- a genuine balance-sheet channel replacing the purely
> cyclical `LURGAP` proxy. On real ABS data `LEV` is 36-47% of GDP and the
> estimated leverage coefficient is positive (higher leverage -> wider spread, the
> BGG sign). Opt-in (re-estimates `NBRSP`); off by default. Tests:
> `test-corporate-accelerator.R`. **Still to do in I-3:** the full corporate
> balance sheet (`VCORP` from accumulated retained earnings, a consolidated
> debt-to-equity `LEV`, the SF2 net-lending adding-up identity) -- the accelerator
> currently uses a debt-to-GDP leverage proxy from the dominant private-NFC
> sub-sector rather than a fully consolidated D/E.


```
Corporate net worth:  VCORP = VCORP(-1) + RET_EARN + net capital formation + revaluation
Corporate debt:       DCORP = DCORP(-1) + (borrowing flow)
Leverage:             LEV = DCORP / VCORP
Accelerator:          NBRSP = c1 + c2*NBRSP(-1) + c3*LURGAP + c4*LEV(-1)   (BGG external-finance premium on firm leverage)
Adding-up (SF2):      net_lending(HH) + net_lending(CORP) + NLEND_G + (-NCA) = 0
```

**Unlocks:** a genuine balance-sheet financial accelerator (review F1/F5/SF4)
replacing the reduced-form `LURGAP` proxy in `NBRSP`; the sectoral net-lending
adding-up identity (SF2); a near-complete SFC matrix. The accelerator term
re-estimates `NBRSP` (so it's a T3 opt-in, like `convex_ptm`/`inverted_le`).

- **Data:** corporate financial accounts (debt stock, borrowing) — ABS 5232.0
  (financial accounts) / 5206.0 corporate income account.
- **Effort:** large; the accelerator hook is the high-value payoff.

---

## 4. Key design decisions (need an owner call)

1. **GOS: residual vs modelled.** Residual (GOS = NY − COE − GMI − taxes − SD_I)
   reconciles exactly and is simplest. Modelling the profit share / desired
   markup enables a markup-shock channel into `PTM` (review prices_wages) but
   needs estimation and risks a second, inconsistent profit measure. *Recommend:*
   residual for I-0; revisit a modelled markup only alongside the Phillips work.
2. **Statistical discrepancy.** Fold `SD_I` into GOS (keeps `GDP(I)=NY` exact but
   contaminates the profit measure) vs carry an explicit `SD_I` series (cleaner
   profit measure, one more series). *Recommend:* explicit `SD_I` (it is real ABS
   data and keeps GOS interpretable).
3. **Reconciling with `NHOY`.** Replace the single `NHOY` ECM with the income-side
   build, or keep `NHOY` as a top-level consistency check and decompose
   underneath. The forecast behaviour of `NHOY` (which feeds `NHDY → HDY → RC`)
   must be preserved or re-derived — this is the main baseline-neutrality risk.
   *Recommend:* keep `NHOY` as-is when the feature is off; under the feature,
   `NHOY` becomes an identity of its components and `RC` is re-baselined.
4. **CES share consistency.** The income-side `PROFIT_SHARE` and the CES
   `theta_k` (`output_gap`) describe the same capital share two ways. Decide
   whether to (a) leave them independent (cross-check), or (b) calibrate
   `theta_k` *from* the income-side share. *Recommend:* (a) initially, as a
   diagnostic; unify later.
5. **Forecast rules.** Fix the forward rule for each component: COE from the
   model, taxes effective-rate×base, GMI as a share, GOS residual, property
   income = rate×stock (needs the balance sheets, I-3), dividends =
   payout-ratio×corporate profit.

---

## 5. Architecture & integration

- A new `income_side` feature (and `corporate_sector` for I-3) via the same
  load-time model-text + seeding mechanism as the existing seven features;
  default OFF, baseline-neutral.
- **Builds on the existing features:** `fiscal_accounting` gains the
  consistent-basis balance (I-2 resolves its M1 caveat); `external_accounting`
  supplies `NFOY` for GNI (I-1); `output_gap` supplies the CES share cross-check
  (Decision 4). The new corporate accelerator feeds `NBRSP` (I-3).
- **Data:** ABS 5206.0 income & sectoral income accounts (verified available:
  `A2303377R` GMI, `A2303381F` taxes−subsidies, `A2303379V` total factor income,
  sectoral dividend/interest flows) and ABS 5232.0 financial accounts for the
  corporate balance sheet (I-3). Wired through the catalogue + provenance
  machinery exactly as M1.
- **Tests:** the reconciliation identities (`GDP(I) = NY − SD_I`; sectoral net
  lending sums to zero); baseline-neutrality (off ⇒ headline unchanged);
  `NHDY` reproduced when off.

---

## 6. Risks

- **Largest single change to MARTIN's accounting.** The I-2 Sudoku is intricate;
  ABS sector accounts carry their own statistical discrepancies that have to be
  parked deliberately, not hidden.
- **Baseline-neutrality of the household reconciliation.** Re-expressing `NHOY` /
  `NHDY` risks perturbing `RC`. Mitigation: strict feature-gating + a test that
  the off-path reproduces `NHDY` to machine precision.
- **Forecast coherence over history-fit.** The income side must project sanely;
  a residual GOS can behave oddly if COE/taxes/GMI projections drift.
- **Share inconsistency** between the income-side profit share and the CES
  `theta_k` if both are active (Decision 4).
- **Data revisions / vintage.** Sectoral accounts revise; ties into the
  point-in-time vintage gap (review D1).

---

## 7. Effort & recommended sequence

| Tier | Scope | Effort | Baseline impact |
|---|---|---|---|
| **I-0** | GDP(I) identity, GOS residual, profit/labour share | ~0.5 session | T0, baseline-neutral |
| **I-1** | sectoral primary income, GNI, corporate GOS | ~1 session | T0/T1 |
| **I-2** | secondary income, fiscal + household reconciliation | ~2 sessions | T1/T2 (resolves M1 fiscal caveat) |
| **I-3** | corporate balance sheet + financial accelerator | ~2 sessions | T3 (re-estimates `NBRSP`) |

**Recommended order:** **I-0 first** — cheap, baseline-neutral, and it unlocks
the profit flow, the indirect-tax base, and the share decomposition immediately
(and is a clean input to the prices_wages markup work). Then **I-2** to resolve
the M1 fiscal-balance caveat (the concrete thing that motivated this doc). Then
**I-1 → I-3** for the corporate/SFC agenda, where the BGG financial accelerator
(I-3) is the high-value payoff that closes review recs F1/F5/SF4.

---

*Scope prepared 2026-06. Data availability spot-checked live against ABS 5206.0
(income and sectoral income accounts). Builds on the seven model features and the
M1 data wiring already shipped; same feature-gated, baseline-neutral, reproducible
discipline applies.*
