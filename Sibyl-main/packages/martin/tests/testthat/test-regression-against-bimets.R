# Regression test: martin::solve_martin() must produce the same projection
# as the canonical bimets pipeline from
# references/bimets-main/BIMETS_MARTIN_LOAD.R, given the bundled MARTINDATA
# fixture and no user adjustments.
#
# WHY THE ORIGINAL INLINE-REFERENCE TEST WAS WEAK
# -----------------------------------------------
# The first test below builds its "reference" by calling this package's OWN
# load_martin() and simulation_to_tibble(), then asserts solve_martin()
# matches it. That makes the comparison SELF-REFERENTIAL: it pins the glue
# (replay-AF construction, the SIMULATE call, the pivot) against itself but
# would NOT catch a regression in the shared ESTIMATE / residual pipeline —
# if load_martin() started fitting different coefficients, BOTH sides would
# move together and the test would still pass. It also only exercises the
# in-sample frozen, no-adjustment path (2010-2019Q3), never the forecast
# period the LLM actually operates in. We KEEP that bit-identity check (it is
# still the cleanest guard on the SIMULATE plumbing) but add two stronger
# tests below:
#   (1) pin specific ESTIMATEd coefficient values to expected numbers, so a
#       change in the estimate/residual pipeline is caught directly; and
#   (2) a forecast-period plausibility solve PAST the fixture data end, so the
#       out-of-sample path the round depends on is exercised.
#
# The reference is computed inline rather than loaded from a committed RDS:
# the bundled fixture is deterministic, so both pipelines should produce
# identical numbers in the same R session. The cost (one extra SIMULATE per
# test run) is modest and the alternative — committing a binary blob that
# can silently drift out of sync — is worse.

# Headline variables checked first. If these match, the bulk of the model
# is working; if not, the failure messages are immediately interpretable.
# N2R/N10R are included so the term-structure path is pinned by the
# bit-identity check (the EViews .prg random-walks these; the bimets file we
# solve uses the live expectations-hypothesis form -- see the dedicated
# form-pin test below).
HEADLINE <- c("Y", "RC", "GNE", "LUR", "PTM", "NCR", "N2R", "N10R")

# Demo range from BIMETS_MARTIN_LOAD.R lines 124-127.
HORIZON  <- c("2010Q1", "2019Q3")

bimets_reference <- function(data, tsrange) {
  model <- load_martin(data, variant = "af", estimate = TRUE)
  ca <- lapply(model$behaviorals, function(b) b$residuals)
  ca <- ca[!vapply(ca, is.null, logical(1))]
  model <- bimets::SIMULATE(
    model,
    TSRANGE            = tsrange,
    ConstantAdjustment = ca,
    simConvergence     = 1e-6,
    simIterLimit       = 100
  )
  simulation_to_tibble(model, scenario = "bimets_reference")
}

test_that("solve_martin() with no adjustments matches the bimets reference", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()

  reference <- bimets_reference(data, c(2010, 1, 2019, 3))
  sibyl     <- solve_martin(
    database    = data,
    adjustments = NULL,
    horizon     = HORIZON,
    scenario    = "sibyl"
  )

  # Same variables present
  expect_setequal(unique(reference$variable), unique(sibyl$variable))

  # Per-variable numerical agreement on the headline aggregates
  for (var in HEADLINE) {
    ref_v <- dplyr::filter(reference, variable == var)
    sib_v <- dplyr::filter(sibyl,     variable == var)
    expect_equal(nrow(ref_v), nrow(sib_v),
                 info = paste("row count for", var))
    expect_equal(
      sib_v$value, ref_v$value,
      tolerance = 1e-8,
      info = paste("value column for", var)
    )
    # Quarters must line up too
    expect_equal(sib_v$quarter, ref_v$quarter,
                 info = paste("quarter alignment for", var))
  }
})

test_that("a single add-factor on NCR moves the solve away from baseline", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()

  baseline <- solve_martin(
    database = data, adjustments = NULL,
    horizon = HORIZON, scenario = "baseline"
  )

  # Replicate the demo from BIMETS_MARTIN_LOAD.R lines 133-149: bump NCR by
  # 1pp in 2010Q1 (and three small additional bumps to keep the path
  # smoothly higher). Wrap as a SIBYL adjustment.
  bump <- judgement::adjustment(
    equation       = "NCR",
    horizon        = c("2010Q1", "2010Q2", "2010Q3", "2010Q4"),
    value          = c(1.0, 0.341413, 0.427, 0.5137297),
    rationale      = "Replicate the BIMETS_MARTIN_LOAD.R demo NCR shock.",
    tail           = "zero",
    confidence     = "high",
    source         = "human",
    round_id       = "regression-test"
  )
  shocked <- solve_martin(
    database    = data,
    adjustments = judgement::adjustment_list(bump),
    horizon     = HORIZON,
    scenario    = "shocked"
  )

  base_ncr   <- dplyr::filter(baseline, variable == "NCR")$value
  shock_ncr  <- dplyr::filter(shocked,  variable == "NCR")$value
  expect_true(any(shock_ncr - base_ncr > 0.5),
              info = "NCR should be visibly higher in the shocked scenario")

  # GDP should be lower under the rate hike, at least somewhere in the path
  base_y  <- dplyr::filter(baseline, variable == "Y")$value
  shock_y <- dplyr::filter(shocked,  variable == "Y")$value
  expect_true(any(shock_y < base_y),
              info = "Y should be lower under a positive NCR shock")
})

# --- (1) Pin ESTIMATEd coefficients on the frozen path ----------------------
#
# Directly assert that the frozen (2019Q3 TSRANGE) ESTIMATE produces specific
# coefficient values. This is the test the original self-referential check
# could not provide: it catches a change in the estimate/residual pipeline
# even if both "reference" and "sibyl" sides moved together. The expected
# numbers were captured from the current pipeline and asserted with a
# tolerance loose enough to absorb platform BLAS noise but tight enough to
# flag a real refit.
#
# These also DEMONSTRATE the ground truth that the AF form is genuinely
# behavioural, not a wall of `c1=1` identities: PTM imposes c5+c6=1 (a real
# cross-coefficient restriction) and RC imposes c5=0.15 exactly.
test_that("frozen ESTIMATE pins expected behavioural coefficients", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data  <- read_fixture()
  model <- load_martin(data, variant = "af", estimate = TRUE)

  coef_of <- function(eq) {
    co <- model$behaviorals[[eq]]$coefficients
    stats::setNames(as.numeric(co), rownames(co))
  }

  ptm <- coef_of("PTM")
  expect_equal(unname(ptm["c1"]),  0.16961243, tolerance = 1e-5)
  expect_equal(unname(ptm["c5"]),  0.23014873, tolerance = 1e-5)
  expect_equal(unname(ptm["c6"]),  0.76985127, tolerance = 1e-5)
  # The c5+c6=1 RESTRICT must hold to machine precision regardless of refit.
  expect_equal(unname(ptm["c5"] + ptm["c6"]), 1, tolerance = 1e-8,
               info = "PTM c5+c6=1 cross-coefficient restriction")

  rc <- coef_of("RC")
  expect_equal(unname(rc["c1"]), 0.38775212, tolerance = 1e-5)
  # c5=0.15 is an exact RESTRICT, not an estimated value.
  expect_equal(unname(rc["c5"]), 0.15, tolerance = 1e-8,
               info = "RC c5=0.15 exact restriction")

  le <- coef_of("LE")
  expect_equal(unname(le["c1"]), 0.11129236, tolerance = 1e-5)
  expect_equal(unname(le["c3"]), 0.48376731, tolerance = 1e-5)
})

# --- (3) Pin the term-structure FORM --------------------------------------
#
# The review flagged a live three-way hazard: the EViews .prg random-walks
# N2R/N10R (`N = N(-1) + d(NCR)`), the bimets file we actually solve uses the
# live expectations-hypothesis (EH) form, and the LLM-facing
# equation_catalogue.csv used to describe them as a random walk. The bit-
# identity test above is self-referential (a model-file edit would move both
# sides together), so it CANNOT catch a silent reversion of the yield form.
# This test pins the form directly against the model text + estimated weights.
test_that("the yield curve uses the live expectations-hypothesis form", {
  skip_if_not_installed("bimets")

  lines <- readLines(model_file_path("af"))

  # Extract a behavioural's EQ text: from `BEHAVIORAL> <eq>` to the next COEFF>.
  eq_text <- function(eq) {
    i0 <- which(lines == paste0("BEHAVIORAL> ", eq))
    expect_length(i0, 1L)
    i1 <- i0 + which(grepl("^COEFF>", lines[(i0 + 1):length(lines)]))[1] - 1L
    paste(lines[(i0 + 1):i1], collapse = " ")
  }

  n10r <- eq_text("N10R")
  n2r  <- eq_text("N2R")

  # The EH form references the neutral rate and inflation expectations and a
  # cash-rate gap weight; the random-walk form does neither.
  for (eq in list(n10r, n2r)) {
    expect_match(eq, "RSTAR")
    expect_match(eq, "PI_E")
  }
  expect_match(n10r, "0.25", fixed = TRUE)  # N10R gap weight
  expect_match(n2r,  "0.52", fixed = TRUE)  # N2R gap weight
  # Guard against reversion to the EViews random walk N = N(-1) + d(NCR).
  expect_false(grepl("TSDELTA(NCR", n10r, fixed = TRUE))
  expect_false(grepl("TSDELTA(NCR", n2r,  fixed = TRUE))

  # Pin the estimated EH weights (RESTRICT> c1+c2=1 on N10R, c2+c3=1 on N2R).
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  model <- load_martin(read_fixture(), variant = "af", estimate = TRUE)
  coef_of <- function(eq) {
    co <- model$behaviorals[[eq]]$coefficients
    stats::setNames(as.numeric(co), rownames(co))
  }
  n10 <- coef_of("N10R")
  expect_equal(unname(n10["c1"]),  0.89657041, tolerance = 1e-5)
  expect_equal(unname(n10["c2"]),  0.10342959, tolerance = 1e-5)
  expect_equal(unname(n10["c1"] + n10["c2"]), 1, tolerance = 1e-8,
               info = "N10R c1+c2=1 EH restriction")
  n2 <- coef_of("N2R")
  expect_equal(unname(n2["c2"]),  0.14178270, tolerance = 1e-5)
  expect_equal(unname(n2["c3"]),  0.85821730, tolerance = 1e-5)
  expect_equal(unname(n2["c2"] + n2["c3"]), 1, tolerance = 1e-8,
               info = "N2R c2+c3=1 EH restriction")
})

# --- (2) Forecast-period plausibility past the fixture data end -------------
#
# The fixture data ends 2019Q3 (tsp(Y)[2] == 2019.5). The original tests only
# solved in-sample. Here we extend exogenous variables forward and solve a
# few quarters PAST the data end — the regime the LLM round actually runs in —
# then assert the headline aggregates stay in sane ranges and the solve
# reports convergence (no NaN/Inf leaked through a soft iteration limit).
test_that("a short forecast-period solve stays in sane ranges", {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")

  data <- read_fixture()
  fc_horizon <- c("2019Q4", "2020Q2")
  fc_end     <- "2020Q2"

  # Prefer the real extender if sibyldata is importable; otherwise carry every
  # series forward inline (the same carry-forward rule sibyldata defaults to).
  if (requireNamespace("sibyldata", quietly = TRUE)) {
    data <- sibyldata::extend_exogenous(data, fc_end, rules = "carry_all")
  } else {
    data <- carry_forward_all(data, fc_end)
  }

  p <- solve_martin(
    database    = data,
    adjustments = NULL,
    horizon     = fc_horizon,
    scenario    = "forecast"
  )

  # Solve must converge with no non-finite cells in the window.
  conv <- attr(p, "convergence")
  expect_true(is.list(conv) && isTRUE(conv$converged),
              info = sprintf("forecast solve not converged (n_nonfinite=%s)",
                             conv$n_nonfinite))
  expect_true(all(is.finite(p$value)),
              info = "forecast projection has non-finite values")

  pluck <- function(v) p$value[p$variable == v]

  # Wide-but-meaningful ranges around the late-2019/early-2020 fixture path.
  y <- pluck("Y")
  expect_true(length(y) == 3L && all(y > 3e5 & y < 6e5),
              info = "Y out of plausible range")

  lur <- pluck("LUR")
  expect_true(all(lur > 2 & lur < 10), info = "LUR out of plausible range")

  ptm <- pluck("PTM")
  expect_true(all(ptm > 90 & ptm < 140), info = "PTM out of plausible range")

  ncr <- pluck("NCR")
  expect_true(all(ncr > -1 & ncr < 8), info = "NCR out of plausible range")
})

# Carry every series in a bimets database forward to `end_q` (inclusive),
# holding the last finite value. Local fallback used only when sibyldata is
# not importable; mirrors sibyldata::extend_exogenous(rules = "carry_all").
carry_forward_all <- function(db, end_q) {
  yq <- judgement:::parse_quarter(end_q)
  target_dec <- yq$year + (yq$quarter - 1) / 4
  for (nm in names(db)) {
    ts  <- db[[nm]]
    tsp <- stats::tsp(ts)
    if (target_dec <= tsp[2] + 1e-9) next
    n_new <- round((target_dec - tsp[2]) * 4)
    vals  <- as.numeric(ts)
    li    <- suppressWarnings(max(which(is.finite(vals))))
    seed  <- if (is.finite(li)) vals[li] else 0
    sy    <- floor(tsp[1] + 1e-9)
    sq    <- round((tsp[1] - sy) * 4 + 1)
    db[[nm]] <- bimets::TIMESERIES(
      c(vals, rep(seed, n_new)), START = c(sy, sq), FREQ = 4
    )
  }
  db
}
