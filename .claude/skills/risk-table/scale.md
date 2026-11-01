# Word scale for risk narratives

**Status: draft placeholders, for staff to agree.** This file is where the judgement lives. Claude only picks a row, so change a number here and every future translation changes with it.

A tilt multiplies the model's own chance of an outcome. A tilt of 1.35 on the risk side makes that outcome 1.35 times as likely as in the model's draws, and 0.60 on the other side makes it 0.6 times as likely. The mid band takes up the rest, so `balanced` changes nothing.

| Row | Example words | Risk side | Other side |
|---|---|---|---|
| `balanced` | balanced, two-way, no clear skew, in line | 1.00 | 1.00 |
| `slight` | a touch, a tad, modestly, slightly, leaning | 1.20 | 0.75 |
| `tilted` | tilted, skewed, weighted, more likely than not | 1.35 | 0.60 |
| `strong` | clearly, significantly, materially, strongly tilted | 1.65 | 0.45 |
| `heavy` | heavily, dominant, overwhelmingly | 1.95 | 0.30 |
| `two-sided` | elevated uncertainty, wider risks both ways | 1.20 | 1.20 |

A direction with no degree word ("risks are to the upside") uses `tilted`.

## Expected draws kept

Approximate shares from a 3,000-draw run on the current outlook. They move with the outlook and the bands, and the program's log gives the actual number for every run.

**Risks that pull apart:** weak labour market with high inflation. Also use this table for strong labour market with low inflation, and for any pair with `balanced` or `two-sided`, though it was only calculated for the first.

| Labour market \ Inflation | balanced | slight | tilted | strong | heavy | two-sided |
|---|---|---|---|---|---|---|
| **balanced** | 100% | 81% | 70% | 55% | 45% | 82% |
| **slight** | 81% | 73% | 66% | 56% | 49% | 70% |
| **tilted** | 71% | 65% | 59% | 50% | 44% | 61% |
| **strong** | 58% | 54% | 49% | 41% | 36% | 49% |
| **heavy** | 48% | 47% | 42% | 35% | 31% | 41% |
| **two-sided** | 83% | 67% | 58% | 46% | 37% | 68% |

**Risks that line up:** weak labour market with low inflation, or strong labour market with high inflation. For these pairs, use the table below.

| Labour market \ Inflation | balanced | slight | tilted | strong | heavy |
|---|---|---|---|---|---|
| **balanced** | 100% | 81% | 70% | 55% | 45% |
| **slight** | 81% | 65% | 57% | 46% | 38% |
| **tilted** | 71% | 58% | 50% | 40% | 34% |
| **strong** | 58% | 47% | 41% | 33% | 27% |
| **heavy** | 48% | 39% | 34% | 28% | 23% |
