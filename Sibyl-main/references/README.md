# references/

These are **read-only reference implementations** of MARTIN, kept in-tree so
SIBYL's design choices stay anchored to what came before.

- [`MARTIN-master/`](MARTIN-master/) — the EViews / R implementation. Canonical
  source for the equations themselves, the data flow, the splicing /
  backcasting recipes, and the English equation descriptions. SIBYL does not
  lift EViews code, but the data manipulation logic in
  [`Programs/modify_data.prg`](MARTIN-master/Programs/modify_data.prg) and the
  series-ID map in
  [`Programs/import_data.prg`](MARTIN-master/Programs/import_data.prg) are the
  templates for `packages/sibyldata/`. The English comments in
  [`Programs/equations.prg`](MARTIN-master/Programs/equations.prg) seed the
  equation catalogue the LLM sees.

- [`bimets-main/`](bimets-main/) — the R / `bimets` implementation. SIBYL's
  `packages/martin/` is built on this. The model definition files
  ([`MARTINMOD_AF.txt`](bimets-main/MARTINMOD_AF.txt) and friends) are vendored
  with attribution into
  [`../packages/martin/inst/extdata/`](../packages/martin/inst/extdata/). The
  driver pattern in
  [`BIMETS_MARTIN_LOAD.R`](bimets-main/BIMETS_MARTIN_LOAD.R) is the template
  for `martin::solve_martin()`.

## Do not modify these directories.

If something here needs to change, fork the relevant logic into the SIBYL
packages. Treat `references/` as a frozen historical record.

## Why these are in-tree rather than gitignored or submoduled

- They are not actively maintained upstream — they're snapshots of David
  Stephan's earlier work on MARTIN.
- The whole point of SIBYL is to be reproducible against them, and having
  them in-tree makes that comparison trivial.
- They're modest in size (a few hundred KB of text + a couple of MB of
  binary EViews workfiles and an xlsx).

## Provenance

- `MARTIN-master/` — David Stephan, 2019–2021. See
  [`MARTIN-master/README.md`](MARTIN-master/README.md).
- `bimets-main/` — David Stephan, 2024. See
  [`bimets-main/README.md`](bimets-main/README.md).
