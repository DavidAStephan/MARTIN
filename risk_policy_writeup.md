# Policy Paths Consistent with a Risk Assessment in MARTIN

**Program:** [`Programs/risk_policy.prg`](Programs/risk_policy.prg) &nbsp;|&nbsp; **Software:** EViews 11 with the `mcontrol` add-in &nbsp;|&nbsp; **Status:** working prototype, run on a scratch copy only

> **In short.** The program takes the MARTIN outlook, simulates it under uncertainty, tilts those simulations towards a stated view of the risks, and scores any cash rate path against the result. A risk narrative is turned into tilts by Claude, using a fixed word scale, with a person approving the table.
>
> On a baseline at target, the tilts move the recommended cash rate by about 0.2-0.3pp in the expected direction. On the current outlook, **the answer depends on the loss function, so the program reports both versions.** If only negative output gaps count, the rate stays near the floor until about 2025. If positive gaps also count, it lifts off about two years earlier. The earlier lift-off is the safer choice while this is undecided, because getting it wrong costs much less. All probabilities and tilts here are placeholders.

## Contents

1. [The exercise](#1-the-exercise)
2. [How the program works](#2-how-the-program-works)
3. [Results](#3-results)
4. [Findings about the model](#4-findings-about-the-model)
5. [Problems found and fixed](#5-problems-found-and-fixed)
6. [What has and hasn't been checked](#6-what-has-and-hasnt-been-checked)
7. [Open decisions](#7-open-decisions)
8. [Running it](#8-running-it)
9. [Appendix: full code](#9-appendix-full-code)

---

## 1. The exercise

Standard stochastic simulations have two limits: shock distributions are fixed over time, and the results may not match staff's view of the risks. The method answers two questions:

1. **Which shocks reflect our risk assessment?** Select a set of simulations that matches the view staff hold.
2. **Which policy path is best given those risks?** Choose the path that minimises expected loss across that fixed set of shocks.

The loss for one simulation over a horizon of $P$ quarters is

$$
\text{loss} = \sqrt{\frac{1}{P}\sum_{i=1}^{P}\left[\left(\pi^{ave}_{t+i-1}-\pi^{target}\right)^2 + \min\left(0,\,y^{gap}_{t+i-1}\right)^2\right]}
$$

and expected loss is its average across the simulations. This version penalises only negative output gaps. The program also runs a version that counts both signs, replacing $\min(0, y^{gap})$ with $y^{gap}$, and reports both.

---

## 2. How the program works

| Stage | What happens |
|---|---|
| **Set-up** | Load `solvedmodel.wf1`, stop if the start date is inside the ragged edge, rebuild the outlook on the actual cash rate, extract residuals, build a scenario |
| **Checks** | Confirm the scenario reproduces the outlook, and that the offset works as designed |
| **Baseline test** | Optional: fit the outlook to target with add factors |
| **Risk scenarios** | Optional: give each draw one of four starting paths |
| **Step 1** | Bootstrap shocks and solve every draw |
| **Step 2** | Sort draws into a 3x3 table of the labour market by inflation |
| **Step 3** | Turn tilts into a full table by raking, then reject draws to match it |
| **Step 4** | `mcontrol` finds an optimal path on the mean simulation, under each loss |
| **Step 5** | Refine each path for the full expected loss, on half of the accepted draws |
| **Step 6** | Replay every path, and score it under both losses on the other half |

### 2.1 Why the Monte Carlo is hand-built

EViews' built-in stochastic solve only saves the mean, standard deviation and bounds (`_2M`, `_2S`, `_2H`, `_2L`). Individual draws are discarded, so there's nothing to accept or reject afterwards. Instead, each draw is solved as a deterministic simulation with its own add factors. This is valid because MARTIN has no leads, so every shock is unanticipated, and it's fast at about 3 to 4 milliseconds per solve.

**Shocks.** Residuals from 48 equations (1998q1 to 2019q4) are recovered with `addinit`, which puts them on the model's own add factor scale. Each draw is built from **four-quarter blocks** of whole historical quarters, which keeps the correlation across equations and over time. Only the drawn dates are stored, so the same shocks can be replayed exactly.

### 2.2 Accept/reject

Each draw goes into a 3x3 table of **the labour market by inflation**. A third variable would mean 27 cells, too many to fill.

- **Labour market:** the unemployment gap, the same measure as the loss function, so a tilt reaches the loss directly. Weak means the gap is more than 0.15pp above outlook.
- **Inflation:** year-ended trimmed mean, with low and high meaning more than 0.10pp from outlook.
- **Both** are averaged over the first 16 quarters.

**From narrative to table.** A tilt multiplies the model's own chance of an outcome, and the mid band takes up the rest. So a tilt of 1 changes nothing, and it doesn't matter how many draws fall in each band to begin with. **Raking** then fills in all nine cells: it scales the rows and columns of the table of draws in turn until both sets of shares hold, which keeps the model's own link between the two variables.

**From table to accepted draws.** The largest sample that matches the table is found: keep every draw from the limiting cell and thin the others.

$$
M = \min_{ij} \frac{n_{ij}}{q_{ij}}, \qquad m_{ij} = \lfloor M\,q_{ij} \rfloor
$$

where $n_{ij}$ is the number of draws in a cell and $q_{ij}$ is its target share. Counts are used rather than a weighted coin flip, so accepted shares land on target apart from rounding. Keeping the first $m_{ij}$ draws of each cell is still a random subset, because draws are independent.

### 2.3 Risk scenarios

Rejection sampling can only select draws that already exist. So a risk tied to a specific cause is better written as a defined path: `TLUR` isn't shocked at all, and a sustained rise in oil is rare in the draws. Each draw is assigned a scenario before its shocks are added, so the probabilities are met exactly.

- **Oil:** a `WPOIL` add factor holds oil 25% above outlook for four quarters, then the equation brings it back.
- **NAIRU:** `TLUR` is overridden with a permanent step of +0.5pp, meaning less spare capacity.

Scenarios are off by default. **Run them with `!use_scen = 1` and `!use_rs = 0`.** With rejection sampling also on, it selects on the outcomes the scenarios move, so the scenario shares no longer hold: a 25% NAIRU risk fell to 18.6%. The program reports the retained shares in that case.

### 2.4 Policy

**Instrument in the draws.** A policy path is a fixed offset to the rule, applied in every draw, so the rate still reacts to shocks. The offset works by shifting `rstar`, which only enters the rule, inside the 0.1 floor. Nothing in `equations.prg` changes.

**Step 4, `mcontrol`.** This add-in minimises a weighted quadratic loss on one path, so it runs on the probability-weighted mean simulation. It runs on a copy of the model with the policy rule dropped, which makes the cash rate itself the control. The floor is a penalty there, and replay caps the path at the floor.

| `mcontrol` target | Trajectory | Weight |
|---|---|---|
| Inflation | 2.5 | 1 |
| Negative output gap, or the whole gap in the both-signs run | 0 | 1 |
| Change in cash rate | 0 | 1 |
| Below the floor | 0 | 100 |

**Step 5, refinement.** Starting from the better of the `mcontrol` path and the floor, this estimates how paths respond to the offset, minimises the expected loss on that approximation, then re-solves the full model and keeps the step only if the objective falls. It uses odd-numbered accepted draws only.

**Step 6, replay.** Any cash rate path is converted to a rule offset one quarter at a time, then replayed over all accepted draws. Paths are scored under both losses on the even-numbered draws, which Step 5 never saw. Every path uses the same draws, so differences come with paired standard errors.

| Path | Meaning |
|---|---|
| `rule` | No offset |
| `oc_neg`, `oc_sym` | The `mcontrol` path under each loss |
| `eloss_neg`, `eloss_sym` | The refined path under each loss |
| `hold` | At the floor on the mean simulation, but the rule still lifts the rate in strong draws |
| `pin` | At the floor in every draw |

To add an alternative, add a line in the "Alternative cash rate paths" block and add its name to `%alt_paths`:

```text
series rs_path_market = ...
%alt_paths = "hold market"
```

### 2.5 Modelling choices

| Item | Choice here | Setting |
|---|---|---|
| Output gap | `-2*lurgap`: MARTIN has no output gap series, and the GI and GC equations use the same factor of 2 | `!okun` |
| Average inflation | Year-ended trimmed mean | `!pi_q` |
| Horizon | 24 quarters for the loss, so policy has time to work through | `%sim_end` |
| "Mode simulation" | Mean of accepted shocks, not a true mode | |
| Shocks | Four-quarter block bootstrap of residuals | `!block` |
| Rate smoothing | A penalty on changes in the cash rate | `!oc_w_dr`, `!lam_dr` |
| 2021q3 cash rate | The actual 0.10, with the outlook rebuilt on it | `!ncr_q0` |

### 2.6 From words to tilts

A narrative like "growth tilted to the downside" contains no numbers, so something has to supply them. Letting an LLM choose would hand it the judgement. Instead the numbers sit in a fixed scale that staff own, and Claude only picks a row.

| Row | Example words | Risk side | Other side |
|---|---|---|---|
| `balanced` | balanced, two-way, no clear skew | 1.00 | 1.00 |
| `slight` | a touch, a tad, modestly | 1.20 | 0.75 |
| `tilted` | tilted, skewed, weighted | 1.35 | 0.60 |
| `strong` | clearly, significantly, materially | 1.65 | 0.45 |
| `heavy` | heavily, dominant | 1.95 | 0.30 |
| `two-sided` | elevated uncertainty, wider risks both ways | 1.20 | 1.20 |

These values are draft placeholders. The `risk-table` skill for Claude Code does the translation:

1. Stops if the narrative has no risk view, such as a change to the central forecast.
2. Quotes the words each choice rests on, then picks a direction and a row.
3. Asks rather than guessing when the variable or the size of the tilt isn't clear.
4. Shows the proposal against the current targets, with flags for what the table can't capture.
5. Stops for a person to approve, then writes `Programs/risk_targets.prg`, recording the narrative beside the numbers.

For "growth tilted to the downside, inflation tilted to the upside due to supply shocks" it gives:

| Variable | Narrative words | Direction | Scale row | Tilts |
|---|---|---|---|---|
| Labour market | "growth tilted to the downside" | Downside | `tilted` | weak 1.35 / strong 0.60 |
| Inflation | "inflation tilted to the upside" | Upside | `tilted` | low 0.60 / high 1.35 |

It flags that "growth" is read as the labour market, and that "due to supply shocks" isn't reflected, because the table sets outcomes rather than causes.

---

## 3. Results

> All tilts and probabilities here are placeholders. Read these as a demonstration of the method, not as a policy view.

All runs have no failed solves, and the scenario reproduces the outlook exactly (a difference of 0 in the output gap, inflation and the cash rate).

### 3.1 The table changes the answer on a baseline at target

The test: add factors put the outlook at 2.5% inflation with a closed gap, so policy isn't already one-sided. Tilts are `strong`, with 2,000 draws.

| Cash rate, `eloss_neg` path | 2022Q4 | 2023Q4 | 2024Q4 | 2026Q4 | E[loss], held-out |
|---|---|---|---|---|---|
| Balanced | 2.00 | 2.53 | 2.76 | 2.84 | 0.498 |
| Inflation upside | 2.28 | 2.88 | 3.01 | 2.91 | 0.529 |
| Labour market downside | 1.83 | 2.31 | 2.47 | 2.70 | 0.507 |
| Inflation downside | 1.59 | 2.16 | 2.54 | 2.98 | 0.466 |

The rate moves in the expected direction in each case, by about 0.2-0.3pp at 2024Q4. A balanced table keeps 1,992 of 2,000 draws, so "balanced" really does mean no tilt. The tilted tables keep 52-57% of draws.

### 3.2 Current outlook with the example narrative

These are the defaults: 3,000 draws, with labour market downside and inflation upside both `tilted`.

| All draws | Inflation low | Mid | High |
|---|---|---|---|
| **Labour market weak** | 4.2% | 4.2% | **6.2%** |
| **Mid** | 18.5% | 20.2% | 19.3% |
| **Strong** | 10.7% | 9.7% | 6.9% |

| Accepted (within 0.1 of target) | Inflation low | Mid | High |
|---|---|---|---|
| **Labour market weak** | 3.3% | 5.8% | **10.5%** |
| **Mid** | 12.5% | 23.8% | 27.7% |
| **Strong** | 4.1% | 6.6% | 5.7% |

1,767 of 3,000 draws were kept, a 41% rejection rate.

### 3.3 Results under both losses

**Every path scored under both losses** (held-out draws, lowest in each column in bold)

| Path | Negative gaps only | Both signs |
|---|---|---|
| `rule` | 0.963 | 1.030 |
| `pin` | 0.722 | 1.713 |
| `hold` | 0.716 | 1.403 |
| `oc_neg` | 0.711 | 1.295 |
| `eloss_neg` | **0.692** | 1.451 |
| `oc_sym` | 0.810 | 0.958 |
| `eloss_sym` | 0.814 | **0.952** |

Paired standard errors against `hold` are 0.006 or less for the negative-gaps column and 0.016 or less for the both-signs column.

**Cash rate on the mean simulation**

| Quarter | Outlook | `rule` | `eloss_neg` | `eloss_sym` |
|---|---|---|---|---|
| 2021Q4 | 0.32 | 0.31 | 0.10 | 0.10 |
| 2022Q4 | 1.33 | 1.39 | 0.10 | 0.15 |
| 2023Q4 | 1.37 | 1.50 | 0.10 | 1.29 |
| 2024Q4 | 1.54 | 1.66 | 0.10 | 1.82 |
| 2025Q4 | 1.74 | 1.86 | 0.46 | 2.08 |
| 2026Q4 | 1.94 | 2.00 | 0.88 | 2.23 |

**The cost of being wrong about the loss.** This is each path's excess over the best path in that column:

| Path | If only negative gaps count | If both signs count | Worst case |
|---|---|---|---|
| `eloss_neg` | 0.000 | +0.499 | +0.499 |
| `hold` | +0.024 | +0.451 | +0.451 |
| `rule` | +0.271 | +0.078 | +0.271 |
| `eloss_sym` | +0.122 | 0.000 | +0.122 |
| `oc_sym` | +0.118 | +0.006 | +0.118 |

The costs are lopsided. Staying near the floor when overshooting does matter costs about four times as much as lifting off early when it doesn't. So while the choice is open, the both-signs paths are the safer ones. This doesn't settle which loss is right, and the penalties aren't included.

The negative-gaps ranking held across three seeds, in runs with one loss at a time:

| Seed | `rule` | `pin` | `hold` | `oc_neg` | `eloss_neg` |
|---|---|---|---|---|---|
| 12345 | 0.963 | 0.722 | 0.716 | 0.711 | 0.692 |
| 2 | 0.960 | 0.721 | 0.715 | 0.711 | 0.692 |
| 3 | 0.961 | 0.727 | 0.718 | 0.714 | 0.696 |

### 3.4 Risk scenarios

3,000 draws, with rejection sampling off, on the negative-gaps loss. Oil is +25% for four quarters with 30% probability, and the NAIRU is +0.5pp with 25% probability.

| Path | E[loss], held-out |
|---|---|
| `rule` | 0.882 |
| `pin` | 0.697 |
| `hold` | 0.669 |
| `oc_neg` | 0.660 |
| `eloss_neg` | **0.650** |

| Scenario (averages under the rule) | Draws | Inflation (%) | Output gap (pp) | Cash rate (%) |
|---|---|---|---|---|
| Neither | 1,575 | 2.01 | -0.30 | 1.69 |
| Oil only | 675 | 1.98 | -0.25 | 1.70 |
| NAIRU only | 525 | 2.11 | +0.20 | 2.21 |
| Both | 225 | 2.10 | +0.23 | 2.24 |

The oil rows barely differ from the rows without oil, for the reason in section 4.1.

---

## 4. Findings about the model

### 4.1 Oil barely reaches trimmed mean inflation

With no shocks, percentage differences from the outlook when oil is held 25% higher for four quarters. This was measured before the changes in section 5, which don't touch these equations.

| Quarter | Oil in AUD | Import prices | Consumer import prices | Headline CPI | Trimmed mean |
|---|---|---|---|---|---|
| 2021Q4 | 25.20 | 0.91 | -0.12 | 0.19 | -0.00 |
| 2022Q3 | 25.17 | 1.16 | -0.74 | 0.30 | -0.01 |
| 2023Q3 | 19.44 | 1.20 | -0.34 | 0.23 | -0.03 |
| 2025Q3 | 11.18 | 0.89 | -0.01 | 0.13 | -0.02 |

Consumer import prices (`PMCG`) *fall* when oil rises, because the estimated oil coefficients in that equation are negative: -0.043 (t = -6.2) and -0.033 (t = -4.2). That equation is the route into trimmed mean. So an oil risk can't currently affect the policy answer. Oil also fades slowly once the add factor offset ends.

### 4.2 Some series stay exogenous throughout

Nine series have data through the whole horizon, so they're always excluded: `PI_E`, `TLUR`, `RTWI_CONST`, `TDLLHPP`, `IBCTR`, `IBNDR`, `IBNDRA`, `IBREDR` and `IDDR`. In particular, inflation expectations don't respond to any shock or policy path. This is confirmed as intended, but it does favour low-for-long paths, because a long period of easy policy can't de-anchor expectations.

### 4.3 Draws aren't centred on the outlook

27% of draws have a strong labour market and only 15% a weak one, using bands of the same width either side of outlook. So the outlook isn't the middle of the distribution. Likely causes are the floor and log-level convexity, but this hasn't been established.

### 4.4 Stagflation draws don't look like an oil shock

An earlier version of the table found that draws with a weak labour market and high inflation have, on average, a lower real TWI and *cheaper* oil. That was measured before the block bootstrap, so the sizes are out of date, but it's why the table is used for general tilts and scenarios for named causes.

### 4.5 GDP growth and unemployment come apart in the draws

The table was first built on GDP growth, and a tilt to weak GDP barely reached the loss, because Okun's law operates only weakly in the draws: about 0.10-0.13pp of unemployment per 1pp of growth, against the 0.5 implied by `!okun = 2`. So the table uses the labour market, and "growth" in a narrative is read as the labour market.

---

## 5. Problems found and fixed

### 5.1 Starting inside the ragged edge

A one-quarter rate spike appeared to give a lasting stimulus, and `mcontrol` exploited it. It came from the start date: `ntwi` and `nusd` have actual data for 2021q3, so the real TWI moved while the nominal TWI couldn't.

| +1pp cash rate for one quarter | Real TWI, impact | Nominal TWI, impact | Nominal TWI, 2030q4 |
|---|---|---|---|
| 2021q3 (inside the ragged edge) | +5.04% | 0.00% | -9.02% |
| 2021q4 | +5.11% | +5.11% | +0.21% |

Shocks and policy now start in 2021q4, and the program stops if any endogenous series has data in the start quarter but not to the end of the horizon. Expect this after data updates, and move `%shk_start` forward when it happens.

### 5.2 From the independent review

| Problem | Effect | Fix |
|---|---|---|
| The 2021q3 cash rate was the rule's 1.03, not the actual 0.10 | `rule` carried a hike that never happened, and the path to the floor needed a large cut | Outlook rebuilt on the actual rate |
| Single-quarter bootstrap | Lost serial correlation, so WY and WP drifted too far (though removing them changed E[loss] by 0.015 or less) | Four-quarter blocks |
| 16-quarter horizon | Nothing counted after 2025q3 | 24 quarters |
| Paths fitted and scored on the same draws | `eloss` flattered | Fit on half, score on the other half |
| No sampling error | Small gaps couldn't be judged | Paired standard errors, and the penalty is reported |
| Step 5 could only start from `mcontrol` | Could stop short | Starts from the better of `mcontrol` and the floor |
| Bands set as thirds of the draws | "Weak" had no fixed meaning | Fixed bands, with tilts on the model's own shares |
| `hold` compared with a true floor | Different things called the same | New `pin` path |
| Floor mapping ignored `ncr_a` | A slow, silent drift | Goal is `!floor + ncr_a`, with a warning if not reached |
| Failed solves handled unevenly | Paths might be scored on different draws | Stops if any draw fails on a path |
| Outlook check only covered the output gap | Weak test | Now covers all three variables |
| Rule constants unchecked | Could drift from `equations.prg` | The program tests the offset and floor |
| Other settings unchecked | Silent errors | Checks on raking, horizon, path names and missing values |

One suggestion from the review was tested and rejected: deleting the line that re-applies exclusions in the risk scenario broke the outlook check by 0.22, so it stays.

### 5.3 Earlier bugs

| Problem | Effect | Fix |
|---|---|---|
| `mcontrol` run through the rule | Stopped early with a poor path | Runs on a copy with the rule dropped |
| `vector(!h)` doesn't clear an existing vector | Wrong scenario table, and a stale optimiser step | Vectors are reset explicitly |
| A scenario with no draws | Division by zero | Skipped |

---

## 6. What has and hasn't been checked

| Check | Result |
|---|---|
| No shocks and no offset reproduces the outlook | Yes, difference of 0 in all three variables |
| The offset moves the rate as designed | Yes: an offset of 0.100 moves it 0.0995, the small gap being same-quarter feedback through the TWI |
| Accepted shares match targets | Yes, within 0.1 percentage points in every cell |
| A balanced table changes nothing | Yes, 1,992 of 2,000 kept |
| The table changes the answer | Yes, on a fitted baseline, in the expected direction |
| Path ranking across seeds | Stable across three seeds, on the negative-gaps loss |
| Running both losses together | Matches the separate runs to the digits reported |
| Ragged edge guard fires | Yes, it names `NTWI NUSD` |
| The skill runs end to end | Yes, including the approval step |

**Not done or not established:**

- The program hasn't been run in place, so `Output\riskmodel.wf1` doesn't exist yet.
- The charts haven't been looked at. They're plain lines, not shaded fans.
- `eloss` isn't proven to be the exact optimum.
- The 3x3 shares hold under the rule only, because draws are classified under the rule. They aren't reported under other paths.
- There's no parameter uncertainty, and the spread of the draws looks narrow against history.
- `mcontrol_qp`, which would enforce the floor exactly, needs R and wasn't tested.
- The `mcontrol` call in the old `3b.runoc.prg` uses options that aren't in the public add-in, so a customised version at the RBA may need the call adjusted.
- The rule knows the true NAIRU in each scenario, which probably understates the policy mistake from misjudging it.

---

## 7. Open decisions

| # | Decision | Why it matters | Recommendation |
|---|---|---|---|
| 1 | **Do positive output gaps count?** | It moves lift-off by about two years, more than any tilt tested | The program now shows both. Until this is decided, quote both, and lean on the both-signs paths because being wrong costs less |
| 2 | **Word scale** | The tilts in `scale.md` are draft placeholders and set every translation | Staff agree the scale once, then change it rarely |
| 3 | **Scenario probabilities** | 30% and 25% are placeholders, and independence is assumed | Set from market pricing, NAIRU estimate uncertainty and staff judgement |
| 4 | **Balance of risks** | Only listed risks enter, so one-sided lists skew the result | Include any downside risks |
| 5 | **Growth measure** | The table reads "growth" as the labour market | Move the loss to a GDP-based gap if GDP matters separately |
| 6 | **Data pipeline** | The 2021q3 rate is set in `!ncr_q0` | Move it into the database at the next data update, then set `!ncr_q0 = NA` |
| 7 | **Build flag** | The program isn't wired into `build_model.prg` | Add a flag like `!run_sims` if wanted |

**Set aside for now:** how oil passes through to inflation, and what oil does after its four quarters.

**Decided:** the NAIRU scenario is `+0.5`, and `PI_E` stays exogenous.

---

## 8. Running it

**Requirements:** EViews 11, an existing `Output\solvedmodel.wf1` from `build_model.prg`, and the `mcontrol` add-in (Add-ins > Download Add-ins).

1. **Set the tilts.** In Claude Code, run `/risk-table` followed by the narrative, then approve the table. You can also edit `Programs\risk_targets.prg` by hand.
2. **Run the program.** Run `Programs\risk_policy.prg`. It takes about 3.5 minutes at the defaults, and longer with scenarios and no rejection because every draw is replayed. It writes `Output\riskmodel.wf1`, leaving `solvedmodel.wf1` untouched.
3. **Check the log.** The check against the outlook should be 0, `mcontrol` should say converged in both runs, and the Accepted block should match the Target block.

**Main settings**

| Setting | Default | Meaning |
|---|---|---|
| `!nsim` | 3000 | Number of draws |
| `%shk_start`, `%sim_end` | 2021q4, 2027q3 | Horizon |
| `!risk_q` | 16 | Quarters the risk table averages over |
| `!ncr_q0` | 0.1 | Actual cash rate before the first solve |
| `!block` | 4 | Bootstrap block length |
| `!base_fit` | 0 | 1 fits the outlook to target |
| `!band_l`, `!band_i` | 0.15, 0.10 | Table bands in pp |
| `!use_rs` | 1 | 1 applies rejection sampling |
| `!use_scen` | 0 | 1 uses the risk scenarios |
| `!p_oil`, `!p_nairu` | 0.30, 0.25 | Scenario probabilities (placeholders) |
| `!oil_up`, `!oil_q` | 0.25, 4 | Oil scenario size and length |
| `!nairu_shift` | 0.5 | NAIRU shift in pp |
| `!tilt_l_weak`, `!tilt_l_strong` | 1.35, 0.60 | Labour market tilts, in `risk_targets.prg` |
| `!tilt_i_low`, `!tilt_i_high` | 0.60, 1.35 | Inflation tilts, in `risk_targets.prg` |
| `!pi_goal` | 2.5 | Inflation target in the loss |
| `!oc_w_pi`, `!oc_w_ygap`, `!oc_w_dr`, `!oc_w_elb` | 1, 1, 1, 100 | `mcontrol` weights |
| `%alt_paths`, `%cmp_path` | hold, hold | Alternative paths, and the path others are compared with |

**Main outputs in `riskmodel.wf1`**

| Object | Contents |
|---|---|
| `rs_t_paths` | Each path's held-out loss under both losses, with paired differences and standard errors, plus penalty and end points |
| `rs_t_scen` | Averages and shares by scenario |
| `rs_t_prob` | Labour market by inflation tables: all draws, target and accepted |
| `rs_gr_risk` | Charts of output gap, inflation and cash rate |
| `rs_ncr_<path>`, `rs_pi_<path>`, `rs_ygap_<path>` | Mean simulation for each path |
| `rs_u_<path>` | Rule offset for each path |
| `rs_ygap_<path>_f_*`, `rs_pi_<path>_f_*`, `rs_ncr_<path>_f_*` | Fan chart bands |
| `mcontrol_stats`, `mcontrol_text` | `mcontrol` iteration log |

---

## 9. Appendix: full code

The listings below are `Programs/risk_targets.prg` and `Programs/risk_policy.prg` exactly as they stand.

<details>
<summary>Show risk_targets.prg</summary>

```text
''*******************************************************************
' Risk targets for this round, read by risk_policy.prg
' Written by the risk-table skill and approved by a person.
'
' Narrative: growth tilted to the downside, inflation tilted to the
' upside due to supply shocks
' Labour market: downside, tilted
' Inflation: upside, tilted
' Flags: "growth" is read as the labour market. The named cause (supply
' shocks) isn't reflected, as the table sets outcomes, not causes.
''*******************************************************************
!tilt_l_weak = 1.35
!tilt_l_strong = 0.60
!tilt_i_low = 0.60
!tilt_i_high = 1.35
```

</details>

<details>
<summary>Show risk_policy.prg (1143 lines)</summary>

```text
''*******************************************************************
' Policy Recommendation Consistent with a Risk Assessment
'
'	Risk scenarios: each draw starts from the outlook or a risk path
'	Step 1: stochastic simulations around those paths
'	Step 2: sort each simulation into a risk outcome
'	Step 3: rejection sampling to hit target outcome probabilities
'	Step 4: optimal control (mcontrol add-in) on the mode simulation
'	Step 5: refine that path for expected loss, on half of the accepted shocks
'	Step 6: every policy path replayed, and scored on the other half
'
' Steps 4 and 5 run twice, once with only negative output gaps in the loss and
' once with both signs, because the choice moves lift-off by more than any
' risk tilt. Every path is scored under both, so neither is taken as given.
'
' Requires the mcontrol add-in (eviews.com/addins).
'
' Eviews' built-in stochastic solve only saves the mean, s.d. and bounds,
' not the individual draws, so nothing could be accepted or rejected
' afterwards. Each draw is therefore solved here as a deterministic
' simulation. MARTIN has no leads, so all shocks are unanticipated.
'
' Everything created here is prefixed rs_ (plus the _s scenario series).
' Reads output\solvedmodel.wf1, saves to output\riskmodel.wf1.
''*******************************************************************
logmode logmsg
mode quiet
close @wf
%path = @runpath
cd %path

' Load workfile
wfopen .\..\output\solvedmodel

' Define model name
%modelname = "martin"

''*******************************************************************
'Settings
''*******************************************************************
rndseed 12345
!nsim = 3000 'number of stochastic simulations (Step 1). With !use_rs = 0 every draw is replayed in Steps 5 and 6

%shk_start = "2021q4" 'first quarter of shocks and policy deviations (and of every solve)
%sim_end = "2027q3" 'end of the loss horizon, long enough for policy to work through
!risk_q = 16 'quarters from %shk_start that the risk table averages over

!ncr_q0 = 0.1 'actual cash rate in the quarter before %shk_start, the outlook is rebuilt on it (NA = keep the outlook)

%res_start = "1998q1" 'window of equation residuals to bootstrap
%res_end = "2019q4"
!block = 4 'quarters in each bootstrap block, which keeps the serial correlation of the residuals

'Equations to shock (cross-section of residuals is resampled by block)
%shocks = "rc nhoy nhfa nhl nhc id ph prt otc ibn ibre kv gi gc xre xm xs xag xo m pw pae pm pmcg ptm p pc pid pibn pibre pg pxre pxm pxs pxo pxag potc le lur nbrsp nsp rtwi wpx wpag wpoil wy wp wpcom"

!okun = 2 'output gap in the loss = -okun*lurgap (same gap as the GI and GC equations)

'Risk scenarios: every draw starts from one of four paths (neither, oil, NAIRU,
'both) with these probabilities, assumed independent, then gets its shocks
!use_scen = 0 '1 = use the risk scenarios, 0 = every draw starts from the outlook
!p_oil = 0.30 'placeholder
!p_nairu = 0.25 'placeholder
!oil_up = 0.25 'oil price this far above outlook
!oil_q = 4 'for this many quarters, then the WPOIL equation takes it back
!nairu_shift = 0.5 'pp, permanent shift in TLUR (positive = less spare capacity)

'Baseline test: moves the outlook onto target with add factors, to show the
'risk table changing the answer on a baseline where policy isn't already one-sided
!base_fit = 0 '1 = fit the outlook to !pi_goal and !base_gap, 0 = use the outlook
!base_gap = 0 'unemployment gap to fit to

'Step 2: each draw goes in a 3x3 table of the labour market by inflation, both
'averaged over !risk_q quarters and relative to outlook. The labour market is the
'unemployment gap, as used in the loss, so weak means a high gap.
!band_l = 0.15 'pp on the unemployment gap either side of outlook
!band_i = 0.10 'pp on inflation either side of outlook

'Step 3: tilts are set in risk_targets.prg. A tilt multiplies the model's own
'chance of that outcome, so 1 means no change and the mid band takes up the rest
!use_rs = 1 '1 = apply the rejection sampling of Step 3, 0 = keep every draw
include .\risk_targets.prg

'Steps 4 and 5: loss function and optimiser
!pi_q = 4 'quarters over which pi_ave is measured (4 = year-ended)
!pi_goal = 2.5 'inflation target in the loss function
!floor = 0.1 'floor on the cash rate, as in the @recode of the policy rule
!lam_dr = 0.02 'penalty on quarterly changes in mean cash rate
!opt_iter = 8 'maximum outer iterations
!opt_tol = 0.0005 'stop when objective improves by less than this
!jac_k = 100 'draws used to estimate policy responses
!jac_eps = 0.25 'size of policy perturbation (pp)

'Step 4: optimal control. mcontrol asks a yes/no question if it reaches m, so keep m high
!oc_w_pi = 1 'weight on inflation less target
!oc_w_ygap = 1 'weight on negative output gaps
!oc_w_dr = 1 'weight on quarterly changes in the cash rate
!oc_w_elb = 100 'weight on the cash rate going below the floor
%oc_opts = "c=1e-7,m=50,p=0.1,g,o=0"

'Step 6: alternative cash rate paths, each defined by a series rs_path_<name> below
%alt_paths = "hold"
%cmp_path = "hold" 'other paths are compared with this one

%solve_opts = "s=d,d=d,o=g,i=a,c=1e-6,f=t,v=f,g=n"

''*******************************************************************
'Subroutines
''*******************************************************************
' Rstar only enters the policy rule, inside the 0.1 floor, with a
' weight of 0.3. Shifting it moves the rule by u without breaching the
' floor, which the ncr add factor (outside the @recode) would.
subroutine set_policy(vector v_u)
	vector rs_v_rstar = rs_v_rstar0 + v_u/0.3
	mtos(rs_v_rstar, rstar_s, rs_ss_shk)
endsub

' Shock matrix for draw !draw (rows = quarters, columns = equations)
subroutine make_shock
	for !q = 1 to !h
		rowplace(rs_m_shk, @rowextract(rs_m_res, rs_m_draw(!draw,!q)), !q)
	next
	!md = rs_v_mode(!draw)
	if !md = 2 or !md = 4 then
		matrix rs_m_shk = rs_m_shk + rs_m_oil
	endif
endsub

' NAIRU path with share sc_f of the shift (1 in the NAIRU scenarios, 0 otherwise,
' the probability weighted share on the mean path)
subroutine set_tlur(scalar sc_f)
	vector rs_v_tlur = rs_v_tlur0 + sc_f*!nairu_shift
	mtos(rs_v_tlur, tlur_s, rs_ss_shk)
endsub

' Solve under shock matrix m_shk, result in rs_m_o (ygap, pi, ncr)
subroutine solve_one(matrix m_shk)
	matrix rs_m_af = rs_m_af0 + m_shk
	mtos(rs_m_af, rs_g_af, rs_ss_shk)
	setmaxerrs 2
	!err0 = @errorcount
	{%modelname}.solve({%solve_opts})
	!solve_ok = 1
	if @errorcount > !err0 then
		!solve_ok = 0
	endif
	clearerrs
	setmaxerrs 1
	stomna(rs_g_out, rs_m_o, rs_ss_shk)
endsub

' Rule offset that puts the mode simulation on cash rate path v_r. Works
' forward a quarter at a time, as the rate only depends on earlier offsets.
' The floor is !floor + ncr_a, as the add factor sits outside the @recode.
subroutine path_to_u(vector v_r, vector v_u)
	v_u = v_u*0
	for !j = 1 to !h
		!goal = v_r(!j)
		if !goal < !floor + rs_v_nca(!j) then
			!goal = !floor + rs_v_nca(!j)
		endif
		!hit = 0
		for !pass = 1 to 40
			call set_policy(v_u)
			call solve_one(rs_m_shkbar)
			!gap = !goal - rs_m_o(!j,3)
			if @abs(!gap) < 1e-5 then
				!hit = 1
				exitloop
			endif
			v_u(!j) = v_u(!j) + !gap
		next
		if !hit = 0 then
			%m = "Warning: path not reached in quarter " + @str(!j)
			logmsg {%m}
		endif
	next
	call set_policy(v_u)
endsub

' Solve a list of draws at the current policy, one row per draw
subroutine run_batch(vector v_ids, matrix m_y, matrix m_pi, matrix m_r)
	!nb = @rows(v_ids)
	matrix(!nb,!h) m_y
	matrix(!nb,!h) m_pi
	matrix(!nb,!h) m_r
	!nfail = 0
	smpl rs_ss_shk
	for !b = 1 to !nb
		!draw = v_ids(!b)
		call make_shock
		!f = 0
		if !md >= 3 then
			!f = 1
		endif
		call set_tlur(!f)
		call solve_one(rs_m_shk)
		if !solve_ok = 0 then
			!nfail = !nfail + 1
			rs_v_fail(!draw) = 1
		endif
		rowplace(m_y, @transpose(@columnextract(rs_m_o,1)), !b)
		rowplace(m_pi, @transpose(@columnextract(rs_m_o,2)), !b)
		rowplace(m_r, @transpose(@columnextract(rs_m_o,3)), !b)
	next
	call set_tlur(!fbar)
endsub

' Loss per draw: square root of the average squared inflation gap and output
' gap (!gap_sym = 0 counts negative gaps only, 1 counts both). Result in
' rs_v_loss, !eloss and !pen
subroutine loss_of(matrix m_y, matrix m_pi, matrix m_r)
	!nb = @rows(m_y)
	matrix m_dev = m_pi - @ones(!nb,1)*@transpose(rs_v_pit)
	matrix m_neg = m_y
	if !gap_sym = 0 then
		matrix m_neg = @emult(m_y, @elt(m_y, @zeros(!nb,!h)))
	endif
	vector rs_v_s = (@epow(m_dev,2) + @epow(m_neg,2))*@ones(!h,1)/!h
	vector rs_v_loss = @epow(rs_v_s,0.5)
	!eloss = @mean(rs_v_loss)
	vector rs_v_rbar = @cmean(m_r)
	vector v_dr = rs_m_d*rs_v_rbar - rs_v_d0
	!pen = !lam_dr*@inner(v_dr,v_dr)
	delete m_dev m_neg v_dr
endsub

' Quantile bands over the horizon for matrix m, as series %pre_*
subroutine fan(matrix m, string %pre)
	matrix(!h,6) rs_m_q
	for !q = 1 to !h
		vector v_c = @columnextract(m,!q)
		rs_m_q(!q,1) = @quantile(v_c,0.125)
		rs_m_q(!q,2) = @quantile(v_c,0.25)
		rs_m_q(!q,3) = @quantile(v_c,0.375)
		rs_m_q(!q,4) = @quantile(v_c,0.625)
		rs_m_q(!q,5) = @quantile(v_c,0.75)
		rs_m_q(!q,6) = @quantile(v_c,0.875)
		rs_m_qm(!q) = @quantile(v_c,0.5)
	next
	smpl rs_ss_shk
	series {%pre}_q125
	series {%pre}_q25
	series {%pre}_q375
	series {%pre}_q625
	series {%pre}_q75
	series {%pre}_q875
	series {%pre}_med
	group {%pre}_g {%pre}_q125 {%pre}_q25 {%pre}_q375 {%pre}_q625 {%pre}_q75 {%pre}_q875
	mtos(rs_m_q, {%pre}_g, rs_ss_shk)
	mtos(rs_m_qm, {%pre}_med, rs_ss_shk)
	delete v_c
endsub

''*******************************************************************
'Set Up: samples, residuals, scenario
''*******************************************************************
tic
sample rs_ss_shk %shk_start %sim_end
sample rs_ss_res %res_start %res_end
smpl rs_ss_shk
!h = @obssmpl
!k = @wcount(%shocks)

' Series with actuals in a quarter are excluded there. Starting inside the
' ragged edge breaks the model: with ntwi still on actuals, a real TWI move
' misses the nominal TWI on the way up but not on the way down, which
' leaves a permanent depreciation from a one-quarter cash rate move
smpl @all
string rs_s_endo = {%modelname}.@endoglist
%ragged = ""
for %v {rs_s_endo}
	if @elem({%v},%shk_start) <> NA and @elem({%v},%sim_end) = NA then
		%ragged = %ragged + " " + %v
	endif
next
if @len(%ragged) > 0 then
	%m = "%shk_start is inside the ragged edge, move it past the data for:" + %ragged
	logmsg {%m}
	seterr %m
endif

' Fill the ragged edge from the outlook, so that every solve (and mcontrol,
' which solves from its first control quarter) starts from complete lags
%q0 = @otod(@dtoo(%shk_start)-1)
smpl %q0-11 %q0-1
for %v {rs_s_endo}
	series {%v} = @nan({%v}, {%v}_2)
next

' The outlook has the rule's forecast for the cash rate in %q0, not what happened.
' Put in the actual rate and solve the outlook again from there.
if !ncr_q0 <> NA then
	smpl %q0 %q0
	series ncr = !ncr_q0
	{%modelname}.scenario "forecast"
	{%modelname}.exclude(actexist=t)
	smpl %q0 %sim_end
	{%modelname}.solve({%solve_opts})
	if @abs(@elem(ncr_2,%q0) - !ncr_q0) > 1e-6 then
		seterr "the outlook did not take the actual cash rate"
	endif
endif
smpl %q0 %q0
for %v {rs_s_endo}
	series {%v} = @nan({%v}, {%v}_2)
next

' mcontrol targets have to be endogenous, so add them to the model
smpl @all
series rs_ygap = -!okun*lurgap
series rs_ygapneg = @recode(rs_ygap<0, rs_ygap, 0)
series rs_pi = ((ptm/ptm(-!pi_q))^(4/!pi_q)-1)*100
series rs_dncr = ncr - ncr(-1)
series rs_elb = @recode(ncr<!floor, ncr-!floor, 0)
{%modelname}.append @identity rs_ygap = -{!okun}*lurgap
{%modelname}.append @identity rs_ygapneg = @recode(rs_ygap<0, rs_ygap, 0)
{%modelname}.append @identity rs_pi = ((ptm/ptm(-{!pi_q}))^(4/{!pi_q})-1)*100
{%modelname}.append @identity rs_dncr = ncr - ncr(-1)
{%modelname}.append @identity rs_elb = @recode(ncr<{!floor}, ncr-{!floor}, 0)
{%modelname}.update
{%modelname}.solveopt({%solve_opts})

' Residuals on the add factor scale: addinit returns the add factor needed
' for each equation to hold in history, which is the equation's residual
{%modelname}.scenario "baseline"
smpl rs_ss_res
for %v {%shocks}
	series rs_h_{%v} = {%v}_a
next
{%modelname}.addinit(v=n) {%shocks}
group rs_g_res
for %v {%shocks}
	series rs_r_{%v} = {%v}_a - @mean({%v}_a)
	rs_g_res.add rs_r_{%v}
	series {%v}_a = rs_h_{%v}
next
stom(rs_g_res, rs_m_res, rs_ss_res)
!t_res = @rows(rs_m_res)

' Block bootstrap: runs of !block historical quarters, whole cross-sections,
' so that the correlation across equations and over time both survive. Single
' quarters would lose the negative serial correlation of residuals such as WY
' and WP, which then compound through their AR terms. Storing the dates rather
' than the shocks keeps the shock set fixed and compact for replaying
matrix(!nsim,!h) rs_m_draw
for !n = 1 to !nsim
	for !q = 1 to !h step !block
		!st = @floor(@rnd*(!t_res-!block+1)) + 1
		for !j = 0 to !block-1
			if !q+!j <= !h then
				rs_m_draw(!n,!q+!j) = !st + !j
			endif
		next
	next
next
vector(!nsim) rs_v_fail

' Scenario with add factors and rstar overridden
{%modelname}.scenario(n,a=s,i="forecast",c) "risk"
{%modelname}.scenario "risk"
smpl rs_ss_shk
{%modelname}.exclude(actexist=t)
smpl @all
series rstar_s = rstar_2
series lurgap_s = lurgap_2
series ptm_s = ptm_2
series ncr_s = ncr_2
series tlur_s = tlur_2
series rs_ygap_s = rs_ygap
series rs_pi_s = rs_pi
%over = "rstar tlur"
group rs_g_af
for %v {%shocks}
	series {%v}_a_s = {%v}_a
	rs_g_af.add {%v}_a_s
	%over = %over + " " + %v + "_a"
next
{%modelname}.override(m) {%over}
{%modelname}.exclude(m) rstar tlur

' Matrices filled by run_batch must exist before the call
for %x rs_m_y rs_m_pi rs_m_r rs_m_ya rs_m_pia rs_m_ra rs_m_yc rs_m_pc rs_m_rc rs_m_yt rs_m_pt rs_m_rt rs_m_y1 rs_m_p1 rs_m_r1 rs_m_y2 rs_m_p2 rs_m_r2
	matrix(1,1) {%x}
next

' Fixed inputs over the horizon
group rs_g_out rs_ygap_s rs_pi_s ncr_s
stom(rs_g_af, rs_m_af0, rs_ss_shk)
stom(rstar_s, rs_v_rstar0, rs_ss_shk)
stom(tlur_s, rs_v_tlur0, rs_ss_shk)
stom(ncr_a, rs_v_nca, rs_ss_shk)
!fbar = 0
vector(!nsim) rs_v_mode
matrix(!h,!k) rs_m_oil
vector(!h) rs_v_pit = !pi_goal
matrix(!h,!k) rs_m_shk
matrix(!h,!k) rs_m_zero
vector(!h) rs_v_zero
vector(!h) rs_m_qm
smpl rs_ss_shk

' Alternative cash rate paths for Step 6: add a series rs_path_<name> here
' and <name> to %alt_paths. Paths below the floor are treated as at the floor.
series rs_path_hold = !floor 'stay at the floor

series rs_ygap_out = -!okun*lurgap_2
series rs_pi_out = ((ptm_2/ptm_2(-!pi_q))^(4/!pi_q)-1)*100
series rs_ncr_out = ncr_2
stom(rs_ygap_out, rs_v_yout, rs_ss_shk)
stom(rs_pi_out, rs_v_piout, rs_ss_shk)
stom(rs_ncr_out, rs_v_rout, rs_ss_shk)

' First difference operator on the cash rate, row 1 relative to last ragged quarter
matrix(!h,!h) rs_m_d
for !q = 1 to !h
	rs_m_d(!q,!q) = 1
	if !q > 1 then
		rs_m_d(!q,!q-1) = -1
	endif
next
vector(!h) rs_v_d0
rs_v_d0(1) = @elem(ncr_2, %q0)

''*******************************************************************
'Check: no shocks and no policy deviation must reproduce the outlook
''*******************************************************************
call set_policy(rs_v_zero)
smpl rs_ss_shk
call solve_one(rs_m_zero)
!chk = 0
for !c = 1 to 3
	vector rs_v_chk = @columnextract(rs_m_o,!c) - rs_v_yout
	if !c = 2 then
		vector rs_v_chk = @columnextract(rs_m_o,!c) - rs_v_piout
	endif
	if !c = 3 then
		vector rs_v_chk = @columnextract(rs_m_o,!c) - rs_v_rout
	endif
	if @max(@epow(rs_v_chk,2))^0.5 > !chk then
		!chk = @max(@epow(rs_v_chk,2))^0.5
	endif
next
%m = "Check against outlook: largest difference in ygap, pi or ncr = " + @str(!chk)
logmsg {%m}
if !chk > 1e-4 then
	seterr "risk scenario does not reproduce the outlook"
endif

' Baseline test: add factors on PTM and LUR that put the outlook on target
if !base_fit = 1 then
	!k_lur = @wfindnc(%shocks, "lur")
	!k_ptm = @wfindnc(%shocks, "ptm")
	matrix(!h,!k) rs_m_fit
	for !q2 = 1 to !h
		for !pass = 1 to 4
			call solve_one(rs_m_fit)
			rs_m_fit(!q2,!k_lur) = rs_m_fit(!q2,!k_lur) + !base_gap + rs_m_o(!q2,1)/!okun
			rs_m_fit(!q2,!k_ptm) = rs_m_fit(!q2,!k_ptm) + (!pi_goal - rs_m_o(!q2,2))/100
		next
	next
	matrix rs_m_af0 = rs_m_af0 + rs_m_fit
	call solve_one(rs_m_zero)
	vector rs_v_yout = @columnextract(rs_m_o,1)
	vector rs_v_piout = @columnextract(rs_m_o,2)
	vector rs_v_rout = @columnextract(rs_m_o,3)
	mtos(rs_v_yout, rs_ygap_out, rs_ss_shk)
	mtos(rs_v_piout, rs_pi_out, rs_ss_shk)
	mtos(rs_v_rout, rs_ncr_out, rs_ss_shk)
	%m = "Baseline fitted: final pi " + @str(rs_v_piout(!h),"f.2") + ", final ygap " + @str(rs_v_yout(!h),"f.2") + ", final ncr " + @str(rs_v_rout(!h),"f.2")
	logmsg {%m}
endif

' The offset has to move the rule one for one, and stop at the floor
if rs_v_rout(!h) > !floor + 0.5 then
	vector rs_v_t = rs_v_zero
	rs_v_t(!h) = 0.1
	call set_policy(rs_v_t)
	call solve_one(rs_m_zero)
	' Not exact: the rate feeds back on itself within the quarter through the TWI
	%m = "Offset of 0.100 moves the cash rate by " + @str(rs_m_o(!h,3) - rs_v_rout(!h),"f.4")
	logmsg {%m}
	if @abs(rs_m_o(!h,3) - rs_v_rout(!h) - 0.1) > 0.02 then
		seterr "rule weight in set_policy does not match the policy rule"
	endif
endif
vector rs_v_t = rs_v_zero - 50
call set_policy(rs_v_t)
call solve_one(rs_m_zero)
if @abs(rs_m_o(!h,3) - !floor - rs_v_nca(!h)) > 1e-4 then
	seterr "!floor does not match the policy rule"
endif
call set_policy(rs_v_zero)

if !risk_q > !h or !oil_q > !h then
	seterr "!risk_q and !oil_q cannot exceed the horizon"
endif
for %pn {%alt_paths}
	if @wfindnc("rule eloss_neg eloss_sym oc_neg oc_sym pin s t out f acc all", %pn) > 0 then
		seterr "that alternative path name is reserved"
	endif
	smpl rs_ss_shk
	if @obs(rs_path_{%pn}) < !h then
		seterr "an alternative path has missing values"
	endif
next
if @wfindnc("rule pin eloss_neg oc_neg eloss_sym oc_sym " + %alt_paths, %cmp_path) = 0 then
	seterr "%cmp_path is not one of the paths"
endif

''*******************************************************************
'Risk scenarios
''*******************************************************************
' WPOIL add factor that puts oil !oil_up above outlook for !oil_q quarters.
' After that the add factor offset is zero and the equation takes it back.
stom(wpoil_2, rs_v_w0, rs_ss_shk)
!k_oil = @wfindnc(%shocks, "wpoil")
if !use_scen = 1 then
	for !q2 = 1 to !oil_q
		for !pass = 1 to 3
			call solve_one(rs_m_oil)
			stom(wpoil_s, rs_v_w, rs_ss_shk)
			!gap = log(rs_v_w0(!q2)*(1+!oil_up)/rs_v_w(!q2))
			rs_m_oil(!q2,!k_oil) = rs_m_oil(!q2,!k_oil) + !gap
		next
	next
endif

' Assign draws to scenarios in random order, as Step 5 uses the first few
vector(!nsim) rs_v_all
for !n = 1 to !nsim
	rs_v_all(!n) = !n
next
vector rs_v_perm = @permute(rs_v_all)
if !use_scen = 0 then
	!p_oil = 0
	!p_nairu = 0
endif
!c1 = !nsim*(1-!p_oil)*(1-!p_nairu)
!c2 = !c1 + !nsim*!p_oil*(1-!p_nairu)
!c3 = !c2 + !nsim*(1-!p_oil)*!p_nairu
for !n = 1 to !nsim
	!rk = rs_v_perm(!n)
	!md = 4
	if !rk <= !c3 then
		!md = 3
	endif
	if !rk <= !c2 then
		!md = 2
	endif
	if !rk <= !c1 then
		!md = 1
	endif
	rs_v_mode(!n) = !md
next

''*******************************************************************
'Step 1: stochastic simulations
''*******************************************************************
call run_batch(rs_v_all, rs_m_y, rs_m_pi, rs_m_r)
!t1 = @toc
!nfail1 = !nfail
%m = "Step 1 done: " + @str(!nsim) + " sims, failed " + @str(!nfail) + ", secs " + @str(!t1)
logmsg {%m}

''*******************************************************************
'Step 2: sort into a table of the labour market (rows) by inflation (columns)
''*******************************************************************
matrix rs_m_dy = @subextract(rs_m_y,1,1,!nsim,!risk_q) - @ones(!nsim,1)*@transpose(@subextract(rs_v_yout,1,1,!risk_q,1))
matrix rs_m_dp = @subextract(rs_m_pi,1,1,!nsim,!risk_q) - @ones(!nsim,1)*@transpose(@subextract(rs_v_piout,1,1,!risk_q,1))
vector rs_v_devl = rs_m_dy*@ones(!risk_q,1)/!risk_q 'output gap, so low = weak
vector rs_v_devp = rs_m_dp*@ones(!risk_q,1)/!risk_q
!l_lo = -!okun*!band_l
!l_hi = !okun*!band_l
!p_lo = -!band_i
!p_hi = !band_i

vector(!nsim) rs_v_cl 'table row of each draw, 0 if it failed to solve
vector(!nsim) rs_v_cp 'table column
matrix(3,3) rs_m_nk
for !n = 1 to !nsim
	if rs_v_fail(!n) = 0 then
		!l = 2
		if rs_v_devl(!n) < !l_lo then
			!l = 1
		endif
		if rs_v_devl(!n) > !l_hi then
			!l = 3
		endif
		!i = 2
		if rs_v_devp(!n) < !p_lo then
			!i = 1
		endif
		if rs_v_devp(!n) > !p_hi then
			!i = 3
		endif
		rs_v_cl(!n) = !l
		rs_v_cp(!n) = !i
		rs_m_nk(!l,!i) = rs_m_nk(!l,!i) + 1
	endif
next
!nok = @sum(rs_m_nk)

''*******************************************************************
'Step 3: rejection sampling
' The tilts give target shares for each variable: the model's own share
' times the tilt, with the mid band taking up the rest. Raking turns these into a full
' table: it scales the rows and columns of the table of draws in turn until
' both sets of shares hold, which keeps the model's own link between the
' labour market and inflation. Then take the largest sample with those cell shares: the
' most tilted-towards cell is kept in full and the others are thinned to
' match. The draws are iid, so keeping the first m of a cell is a random subset.
''*******************************************************************
vector(3) rs_v_tl
rs_v_tl(1) = !tilt_l_weak*@sum(@rowextract(rs_m_nk,1))/!nok
rs_v_tl(3) = !tilt_l_strong*@sum(@rowextract(rs_m_nk,3))/!nok
rs_v_tl(2) = 1 - rs_v_tl(1) - rs_v_tl(3)
vector(3) rs_v_ti
rs_v_ti(1) = !tilt_i_low*@sum(@columnextract(rs_m_nk,1))/!nok
rs_v_ti(3) = !tilt_i_high*@sum(@columnextract(rs_m_nk,3))/!nok
rs_v_ti(2) = 1 - rs_v_ti(1) - rs_v_ti(3)
if rs_v_tl(2) <= 0 or rs_v_ti(2) <= 0 then
	seterr "tilts leave nothing for the mid band, so narrow the bands or lower the tilts"
endif

matrix rs_m_qt = rs_m_nk/!nok
for !it = 1 to 500
	for !l = 1 to 3
		!s = @sum(@rowextract(rs_m_qt,!l))
		if !s > 0 then
			rowplace(rs_m_qt, @rowextract(rs_m_qt,!l)*rs_v_tl(!l)/!s, !l)
		endif
	next
	for !i = 1 to 3
		!s = @sum(@columnextract(rs_m_qt,!i))
		if !s > 0 then
			colplace(rs_m_qt, @columnextract(rs_m_qt,!i)*rs_v_ti(!i)/!s, !i)
		endif
	next
next

!rakeerr = 0
for !l = 1 to 3
	if @abs(@sum(@rowextract(rs_m_qt,!l)) - rs_v_tl(!l)) > !rakeerr then
		!rakeerr = @abs(@sum(@rowextract(rs_m_qt,!l)) - rs_v_tl(!l))
	endif
next
if !rakeerr > 1e-5 then
	seterr "raking did not reach the target shares"
endif

!mstar = 1e20
for !l = 1 to 3
	for !i = 1 to 3
		if rs_m_qt(!l,!i) > 0 then
			if rs_m_nk(!l,!i)/rs_m_qt(!l,!i) < !mstar then
				!mstar = rs_m_nk(!l,!i)/rs_m_qt(!l,!i)
			endif
		endif
	next
next
if !mstar < 1 then
	seterr "too few simulations to reach the target shares"
endif

matrix(3,3) rs_m_mk
for !l = 1 to 3
	for !i = 1 to 3
		rs_m_mk(!l,!i) = @floor(!mstar*rs_m_qt(!l,!i))
		if !use_rs = 0 then
			rs_m_mk(!l,!i) = rs_m_nk(!l,!i)
		endif
	next
next

matrix(3,3) rs_m_seen
vector(!nsim) rs_v_keep
for !n = 1 to !nsim
	!l = rs_v_cl(!n)
	!i = rs_v_cp(!n)
	if !l > 0 then
		if rs_m_seen(!l,!i) < rs_m_mk(!l,!i) then
			rs_m_seen(!l,!i) = rs_m_seen(!l,!i) + 1
			rs_v_keep(!n) = 1
		endif
	endif
next

!nacc = @sum(rs_v_keep)
vector(!nacc) rs_v_ids
!b = 0
for !n = 1 to !nsim
	if rs_v_keep(!n) = 1 then
		!b = !b + 1
		rs_v_ids(!b) = !n
	endif
next

' Mean accepted shock and NAIRU shift: this gives the "mode simulation", which
' with the risk scenarios on is the probability weighted path, so that
' mcontrol sees the risks
matrix(!h,!k) rs_m_shkbar
for !b = 1 to !nacc
	!draw = rs_v_ids(!b)
	call make_shock
	matrix rs_m_shkbar = rs_m_shkbar + rs_m_shk/!nacc
	if !md >= 3 then
		!fbar = !fbar + 1/!nacc
	endif
next

' Accepted paths, no policy deviation
matrix(!nacc,!h) rs_m_ya
matrix(!nacc,!h) rs_m_pia
matrix(!nacc,!h) rs_m_ra
for !b = 1 to !nacc
	!n = rs_v_ids(!b)
	rowplace(rs_m_ya, @rowextract(rs_m_y,!n), !b)
	rowplace(rs_m_pia, @rowextract(rs_m_pi,!n), !b)
	rowplace(rs_m_ra, @rowextract(rs_m_r,!n), !b)
next
call set_tlur(!fbar)

' Odd draws fit the refined path in Step 5, even draws score it in Step 6, so
' that a path isn't marked on the same draws it was fitted to
!nf = @floor((!nacc+1)/2)
vector(!nf) rs_v_idf
vector(!nacc) rs_v_held
for !b = 1 to !nacc
	if !b - 2*@floor(!b/2) = 1 then
		rs_v_idf((!b+1)/2) = rs_v_ids(!b)
	else
		rs_v_held(!b) = 1
	endif
next

%m = "Step 3 done: accepted " + @str(!nacc) + " of " + @str(!nsim) + ", failed " + @str(!nfail1)
logmsg {%m}

for !gap_sym = 0 to 1
%gs = @word("neg sym", !gap_sym+1)

''*******************************************************************
'Step 4: optimal control on the mode simulation
' Mcontrol minimises a weighted quadratic loss on a single path, so it is
' run with the mean accepted shocks in place. It runs on a copy of the
' model without the policy rule, so that the control is the cash rate
' itself: the floor inside the rule is a kink that stops mcontrol
' converging, and at the floor a rule offset has no effect on anything,
' which makes its hessian singular. The floor is a penalty term here.
''*******************************************************************
call set_policy(rs_v_zero)
smpl rs_ss_shk
call solve_one(rs_m_shkbar) 'mean accepted shocks, cash rate from the rule

delete(noerr) rs_oc rs_g_ctl rs_g_tar rs_g_trj rs_g_wgt rs_sv_oc
copy {%modelname} rs_oc
rs_oc.drop ncr
rs_oc.scenario "risk"
rs_oc.solveopt({%solve_opts})

%gap_tar = "rs_ygapneg"
if !gap_sym = 1 then
	%gap_tar = "rs_ygap"
endif
series rs_pi_t = !pi_goal
series {%gap_tar}_t = 0
series rs_dncr_t = 0
series rs_elb_t = 0
series rs_w_pi = !oc_w_pi
series rs_w_ygap = !oc_w_ygap
series rs_w_dr = !oc_w_dr
series rs_w_elb = !oc_w_elb
group rs_g_ctl ncr
group rs_g_tar rs_pi {%gap_tar} rs_dncr rs_elb
group rs_g_trj rs_pi_t {%gap_tar}_t rs_dncr_t rs_elb_t
group rs_g_wgt rs_w_pi rs_w_ygap rs_w_dr rs_w_elb

smpl @all
series rs_h_ncr = ncr
smpl rs_ss_shk
ncr = ncr_s
rs_oc.mcontrol({%oc_opts}) rs_g_ctl rs_g_tar rs_g_trj rs_g_wgt

smpl rs_ss_shk
series rs_path_oc = ncr
smpl @all
series ncr = rs_h_ncr 'mcontrol leaves its solution in the control series
smpl rs_ss_shk
{%modelname}.scenario "risk"
%oc_stat = "converged"
mcontrol_text.svector rs_sv_oc
for !r = 1 to @rows(rs_sv_oc)
	if @instr(rs_sv_oc(!r),"no convergence") > 0 then
		%oc_stat = "NOT CONVERGED"
	endif
next
series rs_path_oc_{%gs} = rs_path_oc
%m = "Step 4 done (" + %gs + "), mcontrol " + %oc_stat + ", secs " + @str(@toc)
logmsg {%m}

''*******************************************************************
'Step 5: refine the optimal control path for expected loss
' Mcontrol sees one path and a quadratic loss, this sees the fitting half of the
' accepted draws and the full loss function. It starts from the better of the
' mcontrol path and the floor (at the floor the responses are zero, so it
' cannot find its own way off it, and it can stop short from higher up).
' Sequential linear-quadratic: estimate how the paths respond to the
' policy offset, minimise the loss on that approximation by iteratively
' reweighted least squares, then re-solve the full model on the fitting
' draws and keep the step only if the true objective falls.
''*******************************************************************
vector rs_v_u = rs_v_zero
if !jac_k > !nf then
	!jac_k = !nf
endif
vector(!jac_k) rs_v_jid
for !b = 1 to !jac_k
	rs_v_jid(!b) = rs_v_idf(!b)
next

matrix(!h,!h) rs_m_jy
matrix(!h,!h) rs_m_jp
matrix(!h,!h) rs_m_jr

vector(!h) rs_v_rp
stom(rs_path_oc, rs_v_rp, rs_ss_shk)
call path_to_u(rs_v_rp, rs_v_u)
call run_batch(rs_v_idf, rs_m_yc, rs_m_pc, rs_m_rc)
call loss_of(rs_m_yc, rs_m_pc, rs_m_rc)
!obj = !eloss + !pen

vector rs_v_fl = rs_v_zero + !floor
vector rs_v_u2 = rs_v_zero
call path_to_u(rs_v_fl, rs_v_u2)
call run_batch(rs_v_idf, rs_m_yt, rs_m_pt, rs_m_rt)
call loss_of(rs_m_yt, rs_m_pt, rs_m_rt)
if !eloss + !pen < !obj then
	!obj = !eloss + !pen
	rs_v_u = rs_v_u2
	matrix rs_m_yc = rs_m_yt
	matrix rs_m_pc = rs_m_pt
	matrix rs_m_rc = rs_m_rt
endif
%m = "Step 5 start (" + %gs + "): objective " + @str(!obj)
logmsg {%m}

for !it = 1 to !opt_iter

	' Responses to the policy offset, averaged over a subset of draws so that
	' the probability of being at the floor is reflected
	for !j = 1 to !h
		vector rs_v_up = rs_v_u
		rs_v_up(!j) = rs_v_up(!j) + !jac_eps
		call set_policy(rs_v_up)
		call run_batch(rs_v_jid, rs_m_y1, rs_m_p1, rs_m_r1)
		rs_v_up(!j) = rs_v_up(!j) - 2*!jac_eps
		call set_policy(rs_v_up)
		call run_batch(rs_v_jid, rs_m_y2, rs_m_p2, rs_m_r2)
		colplace(rs_m_jy, @cmean(rs_m_y1-rs_m_y2)/(2*!jac_eps), !j)
		colplace(rs_m_jp, @cmean(rs_m_p1-rs_m_p2)/(2*!jac_eps), !j)
		colplace(rs_m_jr, @cmean(rs_m_r1-rs_m_r2)/(2*!jac_eps), !j)
	next

	' Iteratively reweighted least squares on the approximation
	vector rs_v_du = rs_v_zero
	matrix rs_m_devc = rs_m_pc - @ones(!nf,1)*@transpose(rs_v_pit)
	vector rs_v_rbc = @cmean(rs_m_rc)
	matrix rs_m_dj = rs_m_d*rs_m_jr
	for !inner = 1 to 25
		matrix rs_m_ones = @ones(!nf,1)
		matrix rs_m_rp = rs_m_devc + rs_m_ones*@transpose(rs_m_jp*rs_v_du)
		matrix rs_m_ry = rs_m_yc + rs_m_ones*@transpose(rs_m_jy*rs_v_du)
		matrix rs_m_act = @elt(rs_m_ry, @zeros(!nf,!h))
		if !gap_sym = 1 then
			matrix rs_m_act = @ones(!nf,!h)
		endif
		matrix rs_m_rym = @emult(rs_m_ry, rs_m_act)
		vector rs_v_sn = (@epow(rs_m_rp,2) + @epow(rs_m_rym,2))*@ones(!h,1)/!h
		vector rs_v_w = @ediv(@ones(!nf,1)/(2*!nf), @epow(rs_v_sn,0.5))
		vector rs_v_wa = @transpose(rs_m_act)*rs_v_w
		vector rs_v_dr = rs_m_d*(rs_v_rbc + rs_m_jr*rs_v_du) - rs_v_d0
		vector rs_v_g = (@transpose(rs_m_jp)*(@transpose(rs_m_rp)*rs_v_w) + @transpose(rs_m_jy)*(@transpose(rs_m_rym)*rs_v_w))/!h + !lam_dr*@transpose(rs_m_dj)*rs_v_dr
		matrix rs_m_h = (@sum(rs_v_w)*@transpose(rs_m_jp)*rs_m_jp + @transpose(rs_m_jy)*@makediagonal(rs_v_wa)*rs_m_jy)/!h + !lam_dr*@transpose(rs_m_dj)*rs_m_dj + 1e-6*@identity(!h)
		vector rs_v_step = @solvesystem(rs_m_h, rs_v_g)
		rs_v_du = rs_v_du - rs_v_step
		if @max(@epow(rs_v_step,2))^0.5 < 1e-5 then
			exitloop
		endif
	next

	' Line search on the full model
	!accepted = 0
	!stepsize = 1
	for !ls = 1 to 5
		vector rs_v_try = rs_v_u + !stepsize*rs_v_du
		call set_policy(rs_v_try)
		call run_batch(rs_v_idf, rs_m_yt, rs_m_pt, rs_m_rt)
		if !nfail = 0 then
			call loss_of(rs_m_yt, rs_m_pt, rs_m_rt)
			if !eloss + !pen < !obj then
				!accepted = 1
				exitloop
			endif
		endif
		!stepsize = !stepsize/2
	next

	if !accepted = 0 then
		%m = "Iteration " + @str(!it) + ": no improving step, stopping"
		logmsg {%m}
		exitloop
	endif

	!gain = !obj - (!eloss + !pen)
	!obj = !eloss + !pen
	rs_v_u = rs_v_try
	matrix rs_m_yc = rs_m_yt
	matrix rs_m_pc = rs_m_pt
	matrix rs_m_rc = rs_m_rt
	%m = "Iteration " + @str(!it) + ": step " + @str(!stepsize) + ", E[loss] " + @str(!eloss) + ", objective " + @str(!obj) + ", secs " + @str(@toc)
	logmsg {%m}
	if !gain < !opt_tol then
		exitloop
	endif

next

vector rs_v_u_{%gs} = rs_v_u

next 'end of the two losses

''*******************************************************************
'Step 6: replay every policy path over the accepted shocks
' Each path is turned into a rule offset on the mode simulation, then that
' offset applies in every draw, so the rule still reacts to the shocks
' and the floor holds. Rule = no offset, the mode simulation. Pin = an
' offset large enough to hold the rate at the floor in every draw, which is
' different from a path at the floor on the mode simulation only.
' Every path is scored under both losses on the held-out draws, which Step 5
' didn't see. The same draws are used throughout, so differences are paired.
''*******************************************************************
%paths = "rule pin eloss_neg oc_neg eloss_sym oc_sym " + %alt_paths
!np = @wcount(%paths)
table(!np+2,11) rs_t_paths
rs_t_paths(1,2) = "Negative gaps only"
rs_t_paths(1,5) = "Both signs"
rs_t_paths(2,1) = "Path"
for !g = 0 to 1
	rs_t_paths(2,2+3*!g) = "E[loss] held-out"
	rs_t_paths(2,3+3*!g) = "Diff vs " + %cmp_path
	rs_t_paths(2,4+3*!g) = "S.E. of diff"
next
rs_t_paths(2,8) = "Penalty"
rs_t_paths(2,9) = "Mean ncr, all draws"
rs_t_paths(2,10) = "Final pi"
rs_t_paths(2,11) = "Final ygap"
vector(!h) rs_v_up
series rs_u
matrix(!nacc,!np) rs_m_lp0
matrix(!nacc,!np) rs_m_lp1

for !p = 1 to !np
	%pn = @word(%paths,!p)
	if %pn = "rule" then
		rs_v_up = rs_v_zero
		call set_policy(rs_v_up)
	else
		if %pn = "eloss_neg" or %pn = "eloss_sym" then
			%gs = @right(%pn,3)
			rs_v_up = rs_v_u_{%gs}
			call set_policy(rs_v_up)
		else
			if %pn = "pin" then
				rs_v_up = rs_v_zero - 50
				call set_policy(rs_v_up)
			else
				stom(rs_path_{%pn}, rs_v_rp, rs_ss_shk)
				call path_to_u(rs_v_rp, rs_v_up)
			endif
		endif
	endif

	' Mode simulation on this path
	smpl rs_ss_shk
	call solve_one(rs_m_shkbar)
	series rs_ygap_{%pn} = rs_ygap_s
	series rs_pi_{%pn} = rs_pi_s
	series rs_ncr_{%pn} = ncr_s
	mtos(rs_v_up, rs_u, rs_ss_shk)
	series rs_u_{%pn} = rs_u

	' Over the accepted shocks
	call run_batch(rs_v_ids, rs_m_yt, rs_m_pt, rs_m_rt)
	if !nfail > 0 then
		seterr "draws failed to solve on a policy path, so the paths wouldn't be compared on the same draws"
	endif
	for !gap_sym = 0 to 1
		call loss_of(rs_m_yt, rs_m_pt, rs_m_rt)
		colplace(rs_m_lp{!gap_sym}, rs_v_loss, !p)
	next
	%x = "rs_ygap_" + %pn + "_f"
	call fan(rs_m_yt, %x)
	%x = "rs_pi_" + %pn + "_f"
	call fan(rs_m_pt, %x)
	%x = "rs_ncr_" + %pn + "_f"
	call fan(rs_m_rt, %x)

	rs_t_paths(!p+2,1) = %pn
	rs_t_paths(!p+2,8) = !pen
	rs_t_paths(!p+2,9) = @mean(rs_v_rbar)
	rs_t_paths(!p+2,10) = @elem(rs_pi_{%pn}, %sim_end)
	rs_t_paths(!p+2,11) = @elem(rs_ygap_{%pn}, %sim_end)
next

!ic = @wfindnc(%paths, %cmp_path)
!nh = @sum(rs_v_held)
for !p = 1 to !np
	%pn = @word(%paths,!p)
	%m = "Path " + %pn + ":"
	for !g = 0 to 1
		vector rs_v_dl = @columnextract(rs_m_lp{!g},!p) - @columnextract(rs_m_lp{!g},!ic)
		vector rs_v_dh = @emult(rs_v_dl, rs_v_held)
		!dm = @sum(rs_v_dh)/!nh
		!ds = ((@inner(rs_v_dh,rs_v_dh) - !nh*!dm^2)/(!nh-1)/!nh)^0.5
		!lh = @inner(@columnextract(rs_m_lp{!g},!p), rs_v_held)/!nh
		rs_t_paths(!p+2,2+3*!g) = !lh
		rs_t_paths(!p+2,3+3*!g) = !dm
		rs_t_paths(!p+2,4+3*!g) = !ds
		%m = %m + " " + @word("neg-only both-signs",!g+1) + " " + @str(!lh,"f.4") + " (vs " + %cmp_path + " " + @str(!dm,"f.4") + ", s.e. " + @str(!ds,"f.4") + ")"
	next
	logmsg {%m}
next

''*******************************************************************
'Results
''*******************************************************************
' Fan charts (25, 50 and 75 per cent intervals)
call fan(rs_m_y, "rs_ygap_all")
call fan(rs_m_pi, "rs_pi_all")
call fan(rs_m_r, "rs_ncr_all")
call fan(rs_m_ya, "rs_ygap_acc")
call fan(rs_m_pia, "rs_pi_acc")
call fan(rs_m_ra, "rs_ncr_acc")

smpl rs_ss_shk
for %v ygap pi ncr
	delete(noerr) rs_gr_{%v}
	group rs_gg_{%v} rs_{%v}_acc_q125 rs_{%v}_acc_q875 rs_{%v}_acc_q25 rs_{%v}_acc_q75 rs_{%v}_acc_med rs_{%v}_out
	for %pn {%paths}
		rs_gg_{%v}.add rs_{%v}_{%pn}
	next
	freeze(rs_gr_{%v}) rs_gg_{%v}.line
	rs_gr_{%v}.addtext(t) {%v}
next
delete(noerr) rs_gr_risk
graph rs_gr_risk.merge rs_gr_ygap rs_gr_pi rs_gr_ncr

' Risk scenarios: averages over the horizon under the rule
table(5,7) rs_t_scen
rs_t_scen(1,1) = "Scenario"
rs_t_scen(1,2) = "Draws"
rs_t_scen(1,3) = "Mean pi"
rs_t_scen(1,4) = "Mean ygap"
rs_t_scen(1,5) = "Mean ncr"
rs_t_scen(1,6) = "Max ncr"
rs_t_scen(1,7) = "Share of draws (%)"
rs_t_scen(2,1) = "Neither"
rs_t_scen(3,1) = "Oil"
rs_t_scen(4,1) = "NAIRU"
rs_t_scen(5,1) = "Both"
for !c = 1 to 4
	vector rs_v_ms1 = rs_v_zero
	vector rs_v_ms2 = rs_v_zero
	vector rs_v_ms3 = rs_v_zero
	!cn = 0
	for !b = 1 to !nacc
		if rs_v_mode(rs_v_ids(!b)) = !c then
			!cn = !cn + 1
			rs_v_ms1 = rs_v_ms1 + @transpose(@rowextract(rs_m_pia,!b))
			rs_v_ms2 = rs_v_ms2 + @transpose(@rowextract(rs_m_ya,!b))
			rs_v_ms3 = rs_v_ms3 + @transpose(@rowextract(rs_m_ra,!b))
		endif
	next
	rs_t_scen(!c+1,2) = !cn
	rs_t_scen(!c+1,7) = 100*!cn/!nacc
	if !cn > 0 then
		rs_t_scen(!c+1,3) = @mean(rs_v_ms1)/!cn
		rs_t_scen(!c+1,4) = @mean(rs_v_ms2)/!cn
		rs_t_scen(!c+1,5) = @mean(rs_v_ms3)/!cn
		rs_t_scen(!c+1,6) = @max(rs_v_ms3)/!cn
		%m = "Scenario " + @str(!c) + ": draws " + @str(!cn) + ", mean pi " + @str(@mean(rs_v_ms1)/!cn,"f.2") + ", mean ygap " + @str(@mean(rs_v_ms2)/!cn,"f.2") + ", mean ncr " + @str(@mean(rs_v_ms3)/!cn,"f.2") + ", peak mean ncr " + @str(@max(rs_v_ms3)/!cn,"f.2")
		logmsg {%m}
	endif
next

' Rejection sampling selects on outcomes that the scenarios move, so with both
' on the retained scenario shares differ from !p_oil and !p_nairu
if !use_scen = 1 and !use_rs = 1 then
	%m = "Note: rejection sampling is on with the risk scenarios, so the scenario shares above are as retained, not as set"
	logmsg {%m}
endif

' Probability tables, labour market by inflation (per cent of draws)
matrix rs_m_p1 = 100*rs_m_nk/!nok
matrix rs_m_p2 = 100*rs_m_qt
matrix rs_m_p3 = 100*rs_m_seen/!nacc
table(19,5) rs_t_prob
!row = 1
for !t = 1 to 3
	%x = @word("All_draws Target Accepted",!t)
	rs_t_prob(!row,1) = %x
	rs_t_prob(!row,3) = "Inflation low"
	rs_t_prob(!row,4) = "Inflation mid"
	rs_t_prob(!row,5) = "Inflation high"
	logmsg {%x}
	for !l = 1 to 3
		%y = @word("weak mid strong",!l)
		rs_t_prob(!row+!l,1) = "Labour market " + %y
		%m = "  Labour market " + %y + ":"
		for !i = 1 to 3
			rs_t_prob(!row+!l,!i+2) = rs_m_p{!t}(!l,!i)
			%m = %m + " " + @str(rs_m_p{!t}(!l,!i),"f.1")
		next
		logmsg {%m}
	next
	!row = !row + 5
next
rs_t_prob(16,1) = "Simulations"
rs_t_prob(16,3) = !nok
rs_t_prob(17,1) = "Accepted"
rs_t_prob(17,3) = !nacc
rs_t_prob(18,1) = "Rejection rate (%)"
rs_t_prob(18,3) = 100*(1-!nacc/!nok)
smpl @all
%m = "Accepted " + @str(!nacc) + " of " + @str(!nok)
logmsg {%m}

%m = "Total secs " + @str(@toc)
logmsg {%m}

{%modelname}.scenario "forecast"
wfsave .\..\output\riskmodel.wf1
```

</details>
