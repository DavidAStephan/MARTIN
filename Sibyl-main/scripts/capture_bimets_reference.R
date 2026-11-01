# Replays the canonical bimets pipeline from
# references/bimets-main/BIMETS_MARTIN_LOAD.R against the bundled fixture
# and writes the solved projection to disk for inspection.
#
# Not required by the test suite — the regression test
# (packages/martin/tests/testthat/test-regression-against-bimets.R) computes
# its own bimets reference inline. This script exists for two reasons:
#
#   1. To make it easy to inspect the reference solve manually (e.g. open
#      the saved RDS in an interactive session and plot Y).
#   2. To detect divergence between the canonical LOAD.R pattern and the
#      martin::solve_martin() wrapper without running the test suite.
#
# Run: Rscript scripts/capture_bimets_reference.R
# Output: scripts/output/bimets_reference_projection.rds

suppressPackageStartupMessages({
  library(bimets)
  library(xts)
  library(readxl)
  library(dplyr)
  library(tibble)
  library(pkgload)
})

pkgload::load_all("packages/judgement", quiet = TRUE)
pkgload::load_all("packages/martin",    quiet = TRUE)

message("Loading fixture: ", martin::martin_data_fixture())
data <- martin::read_fixture()

message("Loading MARTINMOD_AF.txt and estimating (imposed coefficients)...")
model <- martin::load_martin(data, variant = "af", estimate = TRUE)

# Demo range from BIMETS_MARTIN_LOAD.R lines 124-127
HORIZON <- c("2010Q1", "2019Q3")
message("Solving horizon ", HORIZON[1], "..", HORIZON[2], " (no adjustments)")

# Reference solve via the LOAD.R pattern: build ConstantAdjustment from
# residuals, SIMULATE.
constant_adj <- lapply(model$behaviorals, function(b) b$residuals)
constant_adj <- constant_adj[!vapply(constant_adj, is.null, logical(1))]

ref_model <- bimets::SIMULATE(
  model,
  TSRANGE            = c(2010, 1, 2019, 3),
  ConstantAdjustment = constant_adj,
  simConvergence     = 1e-6,
  simIterLimit       = 100
)

reference <- martin:::simulation_to_tibble(ref_model, scenario = "bimets_reference")

# SIBYL solve via the wrapper
message("Solving via martin::solve_martin() for comparison")
sibyl <- martin::solve_martin(
  database    = data,
  adjustments = NULL,
  horizon     = HORIZON,
  scenario    = "sibyl_baseline"
)

out_dir <- "scripts/output"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
out_path <- file.path(out_dir, "bimets_reference_projection.rds")
saveRDS(
  list(reference = reference, sibyl = sibyl, horizon = HORIZON),
  out_path
)
message("Wrote ", out_path)

# Quick agreement check on a handful of headline variables
HEADLINE <- c("Y", "RC", "GNE", "LUR", "PTM", "NCR")
for (v in HEADLINE) {
  ref_v <- dplyr::filter(reference, variable == v)$value
  sib_v <- dplyr::filter(sibyl,     variable == v)$value
  if (length(ref_v) != length(sib_v)) {
    warning(v, ": length mismatch (ref=", length(ref_v),
            ", sibyl=", length(sib_v), ")")
    next
  }
  diff <- max(abs(ref_v - sib_v), na.rm = TRUE)
  message(sprintf("%-6s max |diff| = %.2e", v, diff))
}
