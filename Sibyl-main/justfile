# SIBYL common commands.
# Usage: `just <recipe>`. Run `just` with no args to list recipes.

# List recipes
default:
    @just --list

# Bootstrap renv and install core deps. Run once after cloning.
init:
    Rscript scripts/_init.R

# Run testthat for every package
test:
    Rscript -e 'for (pkg in list.dirs("packages", recursive = FALSE)) {message("\n=== ", pkg, " ==="); devtools::test(pkg)}'

# Test one package: `just test-one martin`
test-one PACKAGE:
    Rscript -e 'devtools::test("packages/{{PACKAGE}}")'

# R CMD check every package
check:
    Rscript -e 'for (pkg in list.dirs("packages", recursive = FALSE)) {message("\n=== ", pkg, " ==="); devtools::check(pkg, error_on = "warning")}'

# Run the full targets pipeline (data -> nowcast -> martin -> judgement -> report)
pipeline:
    Rscript -e 'targets::tar_make()'

# Visualise the targets DAG
pipeline-graph:
    Rscript -e 'targets::tar_visnetwork()'

# Clear pipeline state and rerun from scratch
pipeline-fresh:
    Rscript -e 'targets::tar_destroy(ask = FALSE); targets::tar_make()'

# Render the round report (depends on pipeline output)
report:
    quarto render reports/round.qmd

# Launch the SIBYL dashboard (Shiny app)
dashboard:
    Rscript app/run.R

# Reinstall the four packages locally (without renv::snapshot)
install:
    Rscript -e 'for (pkg in list.dirs("packages", recursive = FALSE)) devtools::install(pkg, upgrade = "never", quick = TRUE)'

# Snapshot the renv lockfile
snapshot:
    Rscript -e 'renv::snapshot()'

# Roxygen-document every package
document:
    Rscript -e 'for (pkg in list.dirs("packages", recursive = FALSE)) devtools::document(pkg)'

# Lint every package using lintr
lint:
    Rscript -e 'for (pkg in list.dirs("packages", recursive = FALSE)) lintr::lint_package(pkg)'
