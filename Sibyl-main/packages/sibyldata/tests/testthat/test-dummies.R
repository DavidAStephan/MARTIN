# Unit tests for apply_dummies() and apply_scalars(). Each verifies the
# generated series against the bundled fixture (from packages/martin),
# which is the canonical EViews output. If sibyldata's deterministic
# construction disagrees with the fixture, MARTIN equation coefficients
# (estimated against the fixture's reference) would be silently wrong.

# Helper: slice a sibyldata series down to the fixture's quarter range so
# we can compare element-wise. The sibyldata version typically extends
# further into the future (DEFAULT_DUMMY_END = 2050Q4) than the fixture.
align_to_fixture <- function(sib_ts, fx_ts) {
  fx_tsp  <- stats::tsp(fx_ts)
  sib_tsp <- stats::tsp(sib_ts)
  sib_v <- as.numeric(sib_ts)
  fx_start_dec  <- fx_tsp[1]
  fx_end_dec    <- fx_tsp[2]
  sib_start_dec <- sib_tsp[1]
  offset_lo <- round((fx_start_dec - sib_start_dec) * 4) + 1L
  offset_hi <- round((fx_end_dec   - sib_start_dec) * 4) + 1L
  sib_v[offset_lo:offset_hi]
}

test_that("apply_dummies materialises every spec row over the default span", {
  db <- list()
  db <- apply_dummies(db, sibyldata::series_catalogue())
  spec <- sibyldata:::dummies_spec()
  expect_true(all(spec$martin_var %in% names(db)))
})

test_that("pulse dummies match fixture exactly", {
  skip_if_not_installed("martin")
  fx <- martin::read_fixture()
  db <- apply_dummies(list(), sibyldata::series_catalogue())

  # Pick a representative set spread across the pulse-dummy time span
  for (mv in c("D_OLY", "D_AFC1", "D_GSTSEP", "D_IBRE_3", "D_LE",
               "D_2008Q4", "PIBRE_DUM2")) {
    if (is.null(fx[[mv]])) next
    fx_v <- as.numeric(fx[[mv]])
    # Truncate sibyldata version to the fixture's span before comparing.
    sib <- align_to_fixture(db[[mv]], fx[[mv]])
    expect_equal(sib, fx_v, info = mv)
    # Exactly one 1, rest zeros
    expect_equal(sum(sib == 1, na.rm = TRUE), 1L, info = mv)
    expect_true(all(sib %in% c(0, 1) | is.na(sib)), info = mv)
  }
})

test_that("range dummies match fixture", {
  skip_if_not_installed("martin")
  fx <- martin::read_fixture()
  db <- apply_dummies(list(), sibyldata::series_catalogue())
  for (mv in c("D_CPMCG", "D_NSP", "DUM_RC")) {
    if (is.null(fx[[mv]])) next
    sib <- align_to_fixture(db[[mv]], fx[[mv]])
    expect_equal(sib, as.numeric(fx[[mv]]), info = mv)
  }
})

test_that("tristate D_OLYX matches fixture", {
  skip_if_not_installed("martin")
  fx <- martin::read_fixture()
  if (is.null(fx$D_OLYX)) skip("D_OLYX not in fixture")
  db <- apply_dummies(list(), sibyldata::series_catalogue())
  sib <- align_to_fixture(db$D_OLYX, fx$D_OLYX)
  expect_equal(sib, as.numeric(fx$D_OLYX))
  expect_equal(sum(sib == 1,  na.rm = TRUE), 1L)
  expect_equal(sum(sib == -1, na.rm = TRUE), 1L)
})

test_that("trend_carry dummies match fixture (PC_TREND, TADP, XS_TREND)", {
  skip_if_not_installed("martin")
  fx <- martin::read_fixture()
  db <- apply_dummies(list(), sibyldata::series_catalogue())

  for (mv in c("PC_TREND", "PID_TREND", "PXM_TREND", "XS_TREND", "TADP")) {
    if (is.null(fx[[mv]])) next
    sib <- align_to_fixture(db[[mv]], fx[[mv]])
    fx_v <- as.numeric(fx[[mv]])
    # Compare element-wise tolerating NA/0 quirks (fixture may use 0 where
    # the legacy 'series x = 0' initialiser ran before the smpl reassigned).
    diff_idx <- which(!is.na(sib) & !is.na(fx_v) & sib != fx_v)
    expect_equal(length(diff_idx), 0L,
                 info = paste(mv, "diffs at indices",
                              paste(head(diff_idx, 5), collapse = ",")))
  }
})

test_that("counter_carry dummies match fixture", {
  skip_if_not_installed("martin")
  fx <- martin::read_fixture()
  db <- apply_dummies(list(), sibyldata::series_catalogue())

  for (mv in c("PIBN_TREND_1", "PIBN_TREND_2", "POTC_TREND_1",
               "POTC_TREND_2", "PXS_TREND_1", "PXS_TREND_2",
               "WPX_TREND_1", "WPX_TREND_2")) {
    if (is.null(fx[[mv]])) next
    sib <- align_to_fixture(db[[mv]], fx[[mv]])
    fx_v <- as.numeric(fx[[mv]])
    diff_idx <- which(!is.na(sib) & !is.na(fx_v) & sib != fx_v)
    expect_equal(length(diff_idx), 0L,
                 info = paste(mv, "diffs at indices",
                              paste(head(diff_idx, 5), collapse = ",")))
  }
})

test_that("apply_dummies is idempotent (existing keys are not overwritten)", {
  db <- list()
  db <- apply_dummies(db, sibyldata::series_catalogue())
  # Stamp the D_OLY series with a sentinel to detect overwrite.
  sentinel <- bimets::TIMESERIES(rep(42, 4), START = c(2000, 1), FREQ = 4)
  db$D_OLY <- sentinel
  db <- apply_dummies(db, sibyldata::series_catalogue())
  expect_equal(as.numeric(db$D_OLY), as.numeric(sentinel))
})

test_that("apply_scalars materialises PI_TARGET as 2.5 constant", {
  skip_if_not_installed("martin")
  fx <- martin::read_fixture()
  db <- list()
  db <- apply_scalars(db, sibyldata::series_catalogue())
  expect_true("PI_TARGET" %in% names(db))
  vals <- as.numeric(db$PI_TARGET)
  expect_true(all(vals == 2.5))

  if (!is.null(fx$PI_TARGET)) {
    fx_vals <- as.numeric(fx$PI_TARGET)
    expect_true(all(fx_vals == 2.5))
  }
})

test_that("apply_dummies extends to 2050Q4 even with shorter input data", {
  # Plant a single series that ends in 2010Q4 and check LUR_DUM still
  # activates at 2031Q4 (its trigger quarter).
  fake <- bimets::TIMESERIES(seq_len(40), START = c(2001, 1), FREQ = 4)
  db <- list(FAKE = fake)
  db <- apply_dummies(db, sibyldata::series_catalogue())
  expect_true("LUR_DUM" %in% names(db))
  lur <- db$LUR_DUM
  tsp <- stats::tsp(lur)
  end_year    <- floor(tsp[2] + 1e-9)
  end_quarter <- round((tsp[2] - end_year) * 4 + 1)
  expect_gte(end_year, 2050L)
  # And LUR_DUM is 1 at 2031Q4
  vals <- as.numeric(lur)
  start_dec <- tsp[1]
  start_year    <- floor(start_dec + 1e-9)
  start_quarter <- round((start_dec - start_year) * 4 + 1)
  idx_2031q4 <- (2031L - start_year) * 4L + (4L - start_quarter) + 1L
  expect_equal(vals[idx_2031q4], 1)
})

