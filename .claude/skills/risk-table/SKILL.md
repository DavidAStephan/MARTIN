---
name: risk-table
description: Convert a narrative about the balance of risks ("growth tilted to the downside, inflation tilted to the upside") into tilts for the rejection sampling in Programs/risk_policy.prg. Use when the user gives risk language for a forecast round, or asks to set or change the risk targets.
argument-hint: "[risk narrative]"
---

# Risk narrative to tilts

Translate a narrative into tilts using the word scale in [scale.md](scale.md), get a person's approval, then write `Programs/risk_targets.prg`.

**You are a translator, not a forecaster.** Every number comes from `scale.md`. Never invent, interpolate or adjust a tilt, and never add a view the narrative doesn't contain.

## Steps

1. **Get the narrative.** Use `$ARGUMENTS`. If it's empty, ask for it.
2. **Read** `scale.md`, the current `Programs/risk_targets.prg`, and the settings at the top of `Programs/risk_policy.prg` (`%shk_start`, `%sim_end`, `!risk_q`, `!nsim`, `!use_rs`).
3. **Check it's a risk view.** If the narrative has no view on the balance of risks, stop and write nothing. See "When to stop".
4. **Translate each variable** (labour market, inflation): quote the exact words, pick a direction, and pick a row using "Choosing a row".
5. **Show the proposal** with a comparison to the current file, and any flags. Always say the scale is a draft if `scale.md` still says so.
6. **Stop for approval.** Ask with AskUserQuestion: approve, or change a row. Offer one row stronger and one row weaker for each variable where a move exists, and `balanced` for any silent variable. If that's too many options, offer approve plus "change something".
7. **Write `Programs/risk_targets.prg`** in the format below, replacing the file. Write it even if the tilts are unchanged, so the file records this round's narrative.
8. **Tell the user** to run `Programs/risk_policy.prg`, and to check that the Accepted block in the log matches the Target block. If `!use_rs` is 0, say the tilts won't be applied. If the program stops saying the tilts leave nothing for the mid band, a row needs to be lower or the bands narrower.

**Asking always means stopping.** Wherever this skill says to ask, put the question to the user before going further, and don't propose or write anything until it's answered. If you can't ask, because you're running unattended or the tool isn't available, stop and write nothing.

## When to stop

Stop and ask or explain, and write nothing, if:

- **There's no risk view.** "We now expect growth of 3%" changes the central case and belongs in the add factors, not here.
- **The variable or the view isn't clear.** "Risks are to the downside" and "uncertainty is high" don't say which variable, so ask whether they apply to the labour market, inflation or both. "The economy is on a knife edge" doesn't give a direction either, so ask what the view is. Uncertainty confirmed for a variable uses `two-sided`.
- **The user wants a number off the scale.** Don't write it. Explain that tilts multiply the model's own chances, and offer a row, a change to `scale.md`, or a hand edit of `risk_targets.prg`.

## Choosing a row

Apply these in order, and stop at the first that fits:

1. The word is listed in `scale.md`: use that row.
2. A plain statement of direction with no degree word ("risks are to the upside"): use `tilted` and flag it.
3. Not listed, but clearly the same as a listed word: use that row and flag it.
4. Otherwise ask. Don't guess a degree. "Could well" and "the main risk" speak of possibility or rank, not size, so they aren't plain statements of direction. Offer the neighbouring rows and ask.

**Hedges.** With "tilted, perhaps strongly", use the main claim and flag the hedge.

**Silent variables.** If the narrative doesn't mention a variable, keep its current tilts from `risk_targets.prg` and say so, using the row named in that file. Offer `balanced` as the alternative in the approval question, since silence might mean either. If the current tilts aren't a row on the scale, ask.

## Mapping rules

**Variables**
- Growth, activity, demand, GDP, employment and unemployment all map to the **labour market**, because the table is sorted on the unemployment gap. Say so whenever the narrative's word isn't literally about the labour market.
- Inflation, prices and cost pressures map to **inflation**.
- Higher unemployment is a *downside* labour market risk. Lower unemployment is an *upside* one.

**Direction.** A scale row gives a `risk side` and an `other side` tilt.
- Labour market downside: `!tilt_l_weak` = risk side, `!tilt_l_strong` = other side. Upside swaps them.
- Inflation upside: `!tilt_i_high` = risk side, `!tilt_i_low` = other side. Downside swaps them.
- `balanced` and `two-sided` have the same tilt on both sides, so write their direction as "balanced" or "two-sided".

**Moving a row.** The order is balanced, slight, tilted, strong, heavy. `two-sided` isn't part of it, so it has no stronger or weaker row, and `heavy` has no stronger row.

## Things to flag

- **A named cause.** "Due to supply shocks", "because of oil" and similar can't be captured, as the table sets outcomes, not causes. Say the cause isn't reflected. If it's a specific event with a path you could write down, suggest a risk scenario (`!use_scen`).
- **Wider risks both ways.** The `two-sided` row widens the distribution, it doesn't shift it.
- **A view on one cell.** "Stagflation is the main risk" is a view on the link between the two variables. The table takes a view on each one separately, and raking keeps the model's own link. Offer rows for each variable and say what's lost.
- **Time.** Near-term or fading risks can't be captured, because the table averages over `!risk_q` quarters from `%shk_start`. Translate the words as they are, and flag it.
- **A date outside the risk window.** Compare any date in the narrative with the model's dates, not today's: if it's before `%shk_start` or after the `!risk_q` window, ask what was meant.
- **Few draws left.** If the scale's table shows under 30% kept, warn the user and suggest raising `!nsim` from its current value in `risk_policy.prg`.

## Proposal format

```markdown
| Variable | Narrative words | Direction | Scale row | Tilts | Now |
|---|---|---|---|---|---|
| Labour market | "growth tilted to the downside" | Downside | tilted | weak 1.35 / strong 0.60 | weak 1.00 / strong 1.00 |
| Inflation | "inflation tilted to the upside" | Upside | tilted | low 0.60 / high 1.35 | low 1.00 / high 1.00 |

Expected draws kept: about 59%.
```

Read the kept share from the table in `scale.md` that matches the pair, and don't compute a new number. Then list any flags.

## File format

```text
''*******************************************************************
' Risk targets for this round, read by risk_policy.prg
' Written by the risk-table skill and approved by a person.
'
' Narrative: <narrative, wrapped at about 70 characters, each line starting with an apostrophe>
' Labour market: <direction>, <scale row>
' Inflation: <direction>, <scale row>
' Flags: <flags, or none, wrapped the same way>
''*******************************************************************
!tilt_l_weak = 1.35
!tilt_l_strong = 0.60
!tilt_i_low = 0.60
!tilt_i_high = 1.35
```

Keep this exact layout and these four setting names.
