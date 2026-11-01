# Bootstrap SIBYL's R environment.
# Run once after cloning: `Rscript scripts/_init.R`
#
# - Initialises renv if it isn't already set up
# - Installs the core CRAN / GitHub dependencies the four packages need
# - Snapshots the lockfile so collaborators see the same versions
#
# Re-running is safe; it skips work already done.

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}

if (!file.exists("renv.lock")) {
  renv::init(bare = TRUE, force = TRUE, restart = FALSE)
}

core_packages <- c(
  # tidyverse + infra
  "tidyverse", "tibble", "dplyr", "tidyr", "purrr", "stringr", "lubridate",
  "fs", "rlang", "glue", "withr", "here",
  # data
  "readabs", "readrba", "fredr", "OECD", "arrow", "tsibble", "tempdisagg",
  "seasonal",
  # modelling
  "bimets", "fable", "fabletools", "feasts", "xts", "zoo",
  # llm
  "ellmer",
  # pipeline
  "targets", "tarchetypes",
  # reporting
  "quarto",
  # dev
  "devtools", "testthat", "lintr", "styler", "roxygen2", "pkgload",
  # excel for the bundled MARTINDATA fixture
  "readxl", "writexl"
)

installed <- rownames(installed.packages())
to_install <- setdiff(core_packages, installed)

if (length(to_install) > 0) {
  message("Installing: ", paste(to_install, collapse = ", "))
  renv::install(to_install)
} else {
  message("All core packages already installed.")
}

# Install the four SIBYL packages locally (in dependency order)
local_packages <- c(
  "packages/judgement",
  "packages/martin",
  "packages/nowcast",
  "packages/sibyldata"
)
for (pkg in local_packages) {
  if (dir.exists(pkg)) {
    message("Loading local package: ", pkg)
    # We use load_all rather than install so changes are picked up immediately
    # during iterative development. `just install` installs them for real.
    try(pkgload::load_all(pkg, quiet = TRUE), silent = TRUE)
  }
}

renv::snapshot(prompt = FALSE)

message("\nSetup complete. Try `just test` to verify, or `just pipeline` to run.")
