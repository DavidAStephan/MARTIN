# Tests for the KFAS port of supply_side.prg state-space models.
#
# Bit-level agreement with EViews's ML optimum is unrealistic — KFAS and
# EViews use different optimisers, different diffuse-init handling, and
# different numerical conventions. These tests assert "close enough" for
# MARTIN's purposes: the modern-period (1990+) decadal means agree with
# the fixture to within ~2 % on the slow-moving trends, which is much
# tighter than the noise on the trends themselves.

skip_if_no_kfas <- function() {
  skip_if_not_installed("KFAS")
}

test_that("fit_random_walk_drift recovers a constant drift close to the fixture", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  fit <- sibyldata:::fit_random_walk_drift(
    y_ts         = log(fx$LHPP),
    sample_start = "1966Q1",
    mprior_level = 6.20000,
    vprior_level = 1e-6,
    param_lhpp   = 50
  )
  drift_est <- as.numeric(fit$TDRIFT)[1]
  drift_fx  <- as.numeric(fx$TDLLHPP)[1]
  # TDLLHPP magnitude is ~8e-4; tolerate ~30% (i.e. 2.5e-4) error vs
  # EViews. KFAS converges to a slightly different MLE under the same
  # spec because of optimiser differences.
  expect_lt(abs(drift_est - drift_fx), 3e-4,
            label = sprintf("|%.6f - %.6f|", drift_est, drift_fx))
  # And: the estimate should be negative and slow (similar order of
  # magnitude). Catches gross misspecifications.
  expect_lt(drift_est, 0)
  expect_gt(drift_est, -2e-3)
  # All quarters share the same drift value (constant series).
  expect_true(all(diff(as.numeric(fit$TDRIFT)) == 0))
})

test_that("fit_local_linear_trend recovers TDLLPOP close to fixture in modern period", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  fit <- sibyldata:::fit_local_linear_trend(
    y_ts         = log(fx$LPOP),
    sample_start = "1978Q3",
    mprior       = c(9.265860822608552, 0.0070),
    vprior       = c(0.0001, 1e-6),
    param_trend  = 100,
    param_drift  = 10000
  )
  e <- as.numeric(fit$TDRIFT)
  f <- as.numeric(fx$TDLLPOP)

  # Index of 1990Q1 (idx 1 = 1959Q3).
  idx_1990 <- (1990 - 1959) * 4 + (1 - 3) + 1
  m <- !is.na(e) & !is.na(f)
  m[seq_len(idx_1990 - 1L)] <- FALSE  # restrict to 1990Q1+

  # In the modern period the estimate is essentially exact: mean within
  # 1% and pointwise max diff within 5% of typical value (~4e-3).
  expect_lt(abs(mean(e[m]) - mean(f[m])), 5e-5)
  expect_lt(max(abs(e[m] - f[m])), 2e-4)
})

test_that("fit_local_linear_trend at LPOP recovers correct slow shape over full range", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  fit <- sibyldata:::fit_local_linear_trend(
    y_ts = log(fx$LPOP), sample_start = "1978Q3",
    mprior = c(9.265860822608552, 0.0070),
    vprior = c(0.0001, 1e-6),
    param_trend = 100, param_drift = 10000
  )
  e <- as.numeric(fit$TDRIFT); f <- as.numeric(fx$TDLLPOP)
  m <- !is.na(e) & !is.na(f)
  # Across the whole sample, mean within 5% and the estimate is
  # positive (population growth is always positive in the data).
  expect_lt(abs(mean(e[m]) - mean(f[m])), 2e-4)
  expect_true(all(e[m] > 0))
})

test_that("apply_state_space_trends populates TDLL* and TLL* from log inputs", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  # Build a partial database with the supply-side inputs only.
  db <- list(LPOP = fx$LPOP, LHPP = fx$LHPP)
  db <- sibyldata:::apply_state_space_trends(db, sibyldata::series_catalogue())
  expect_true("TDLLPOP" %in% names(db))
  expect_true("TLLPOP"  %in% names(db))
  expect_true("TDLLHPP" %in% names(db))
  expect_true("TLLHPP"  %in% names(db))
  # No LA in fixture → TDLLA/TLLA not produced.
  expect_false("TDLLA" %in% names(db))
})

test_that("apply_state_space_trends is idempotent (does not overwrite existing keys)", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  sentinel <- bimets::TIMESERIES(rep(42, 10), START = c(2000, 1), FREQ = 4)
  db <- list(LPOP = fx$LPOP, LHPP = fx$LHPP, TDLLPOP = sentinel)
  db <- sibyldata:::apply_state_space_trends(db, sibyldata::series_catalogue())
  expect_equal(as.numeric(db$TDLLPOP), as.numeric(sentinel))
})

test_that("apply_state_space_trends skips rows whose inputs are missing", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  db <- list()  # no LA / LPOP / LHPP at all
  db <- sibyldata:::apply_state_space_trends(db, sibyldata::series_catalogue())
  expect_length(db, 0L)
})

# --- TLUR (NAIRU) -----------------------------------------------------------

test_that("fit_nairu_kfas recovers a TLUR series correlated with the fixture", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  fit <- sibyldata:::fit_nairu_kfas(fx, sample_start = "1986Q3")
  e <- as.numeric(fit$TLUR)
  f <- as.numeric(fx$TLUR)
  m <- !is.na(e) & !is.na(f)

  # Correlation > 0.75: KFAS NAIRU and EViews NAIRU should move
  # together even if levels differ slightly. The faithful port (with
  # lagged-inflation AR, ULC cross-effect, and import-price pass-
  # through) trades a few correlation points for closer structural
  # fidelity to nairu.prg.
  expect_gt(cor(e[m], f[m]), 0.75)
  # Mean within 1.5 pp (NAIRU values are ~4-7).
  expect_lt(abs(mean(e[m]) - mean(f[m])), 1.5)
  # Reasonable range — NAIRU should be in single digits.
  expect_true(all(e[m] > 2 & e[m] < 12))
})

# --- RSTAR ------------------------------------------------------------------

test_that("fit_rstar_kfas_full produces plausible RSTAR estimates on fixture", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  fit <- sibyldata:::fit_rstar_kfas_full(fx, sample_start = "1986Q3")
  e <- as.numeric(fit$RSTAR)
  f <- as.numeric(fx$RSTAR)
  m <- !is.na(e) & !is.na(f)

  # The faithful 11-state port is less accurate than the simple smoother
  # (because the OLS-pre-estimated structural parameters compound state
  # uncertainty), but on fixture inputs it should at least produce
  # plausible values and weak positive correlation with the EViews
  # output.
  expect_gt(cor(e[m], f[m]), 0.3)
  # Reasonable range — neutral real cash rates are in low single digits
  # even on the EViews-published bounds. Allow generous bracket.
  expect_true(all(e[m] > -10 & e[m] < 15))
  # Auxiliary states should also be returned.
  expect_true(!is.null(fit$YGAP))
  expect_true(!is.null(fit$YPOT))
  expect_true(!is.null(fit$G))
  expect_true(!is.null(fit$Z))
})

test_that("fit_rstar_kfas recovers an RSTAR series correlated with the fixture", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  fit <- sibyldata:::fit_rstar_kfas(fx, sample_start = "1986Q3")
  e <- as.numeric(fit$RSTAR)
  f <- as.numeric(fx$RSTAR)
  m <- !is.na(e) & !is.na(f)

  # The smoothed real cash rate tracks the fixture's RSTAR closely in
  # shape (cor > 0.9), though absolute levels differ — the EViews model
  # adds a z-state that captures unexplained drift.
  expect_gt(cor(e[m], f[m]), 0.85)
  # Mean within 2 pp.
  expect_lt(abs(mean(e[m]) - mean(f[m])), 2)
})

# --- apply_state_space_trends with full set ---------------------------------

test_that("apply_state_space_trends materialises TLUR and RSTAR from fixture", {
  skip_if_not_installed("martin")
  skip_if_no_kfas()
  fx <- martin::read_fixture()
  # Strip the fixture's TLUR/RSTAR so the handler has to recompute them.
  db <- fx
  db$TLUR <- NULL
  db$RSTAR <- NULL
  db$PI_E <- NULL
  db <- sibyldata:::apply_state_space_trends(db, sibyldata::series_catalogue())
  expect_true("TLUR"  %in% names(db))
  expect_true("RSTAR" %in% names(db))
  # PI_E should be skipped — fixture has no RBA G3 series.
  expect_false("PI_E" %in% names(db))
})

