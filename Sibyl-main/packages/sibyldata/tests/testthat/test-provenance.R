# Tests for the provenance contract: classify_provenance(),
# database_provenance(), and merge_with_fallback()'s live-vs-fallback
# recording. The whole point is that a report can tell a live fetch apart
# from a fixture backfill, a vendored .wf1 splice, a proxy, a dummy, and a
# derived series -- without guessing.

ts_q <- function(values, start_year, start_quarter = 1L) {
  bimets::TIMESERIES(values, START = c(start_year, start_quarter), FREQ = 4)
}

test_that("classify_provenance() maps each transformation to its class", {
  cat <- series_catalogue()
  # One representative variable per class, looked up from the real catalogue.
  pick <- function(predicate) {
    hit <- cat$martin_var[predicate]
    hit[!is.na(hit)][1]
  }
  live_var    <- pick(cat$transformation == "direct" &
                        cat$source != "derived" &
                        !grepl("proxy", cat$description, ignore.case = TRUE))
  proxy_var   <- pick(grepl("proxy", cat$description, ignore.case = TRUE) &
                        cat$transformation == "direct")
  dummy_var   <- pick(cat$transformation == "dummy")
  scalar_var  <- pick(cat$transformation == "scalar")
  derived_var <- pick(cat$transformation == "derived")
  ident_var   <- pick(cat$transformation == "identity")
  ss_var      <- pick(cat$transformation == "state_space")

  vars <- c(live_var, proxy_var, dummy_var, scalar_var,
            derived_var, ident_var, ss_var, "TOTALLY_MADE_UP")
  prov <- classify_provenance(vars, cat)

  expect_s3_class(prov, "tbl_df")
  expect_setequal(names(prov), c("variable", "source_class"))
  expect_equal(prov$variable, vars)  # input order preserved

  lookup <- stats::setNames(prov$source_class, prov$variable)
  expect_equal(unname(lookup[live_var]),    "live")
  expect_equal(unname(lookup[proxy_var]),   "proxy")
  expect_equal(unname(lookup[dummy_var]),   "dummy")
  expect_equal(unname(lookup[scalar_var]),  "dummy")
  expect_equal(unname(lookup[derived_var]), "derived")
  expect_equal(unname(lookup[ident_var]),   "derived")
  expect_equal(unname(lookup[ss_var]),      "vendored_wf1")
  expect_equal(unname(lookup[["TOTALLY_MADE_UP"]]), "unknown")
})

test_that("classify_provenance() only ever emits known classes", {
  cat <- series_catalogue()
  prov <- classify_provenance(cat$martin_var, cat)
  allowed <- c("live", "fixture_fallback", "vendored_wf1", "proxy",
               "dummy", "derived", "unknown")
  expect_true(all(prov$source_class %in% allowed),
              info = paste("unexpected classes:",
                           paste(setdiff(prov$source_class, allowed),
                                 collapse = ", ")))
  expect_equal(nrow(prov), nrow(cat))
})

test_that("classify_provenance() handles the empty case", {
  prov <- classify_provenance(character(0))
  expect_s3_class(prov, "tbl_df")
  expect_equal(nrow(prov), 0L)
  expect_setequal(names(prov), c("variable", "source_class"))
})

test_that("to_martin_database() attaches a provenance table over its names", {
  # GDPC1 -> WY, which is a US-GDP *proxy* for world GDP, so the data-backed
  # row is classed 'proxy'; the deterministic dummy/scalar/derived rows that
  # always materialise are classed accordingly.
  panel <- tibble::tibble(
    series_id = "GDPC1",
    source    = "fred",
    date      = seq(as.Date("2020-01-01"), as.Date("2020-10-01"),
                    by = "quarter"),
    value     = c(100, 101, 102, 103),
    vintage   = as.Date("2026-05-23")
  )
  out  <- to_martin_database(panel)
  prov <- database_provenance(out)

  expect_s3_class(prov, "tbl_df")
  expect_setequal(names(prov), c("variable", "source_class"))
  # One provenance row per database variable, exactly.
  expect_setequal(prov$variable, names(out))
  expect_equal(nrow(prov), length(names(out)))

  lookup <- stats::setNames(prov$source_class, prov$variable)
  expect_equal(unname(lookup[["WY"]]), "proxy")
  # Deterministic calendar series are present and classed 'dummy'.
  dummy_rows <- prov$variable[prov$source_class == "dummy"]
  expect_true(length(dummy_rows) > 0L)
})

test_that("database_provenance() returns NULL for a hand-built database", {
  db <- list(X = ts_q(1:4, 2010))
  expect_null(database_provenance(db))
})

test_that("merge_with_fallback() records live vs fixture provenance", {
  # Primary supplies LIVEVAR (real data) and ALLNA (present but all-NA).
  # Fallback additionally supplies ONLYFIX. Expectation:
  #   LIVEVAR -> keeps its primary class (live)
  #   ALLNA   -> fixture_fallback (live path contributed nothing)
  #   ONLYFIX -> fixture_fallback (fixture-only)
  primary <- list(
    LIVEVAR = ts_q(1:4, 2010),
    ALLNA   = ts_q(rep(NA_real_, 4), 2010)
  )
  attr(primary, "provenance") <- tibble::tibble(
    variable     = c("LIVEVAR", "ALLNA"),
    source_class = c("live", "live")
  )
  fallback <- list(
    LIVEVAR = ts_q(91:94, 2010),
    ALLNA   = ts_q(81:84, 2010),
    ONLYFIX = ts_q(71:74, 2010)
  )

  out  <- merge_with_fallback(primary, fallback)
  prov <- database_provenance(out)

  expect_s3_class(prov, "tbl_df")
  expect_setequal(prov$variable, names(out))
  lookup <- stats::setNames(prov$source_class, prov$variable)
  expect_equal(unname(lookup[["LIVEVAR"]]), "live")
  expect_equal(unname(lookup[["ALLNA"]]),   "fixture_fallback")
  expect_equal(unname(lookup[["ONLYFIX"]]), "fixture_fallback")
})

test_that("merge_with_fallback() preserves the bare-list path (no provenance)", {
  # When the primary carries no provenance attribute, the merge must not
  # invent one -- the existing list-identity behaviour is sacred.
  primary  <- list(A = ts_q(1:4, 2010))
  fallback <- list(A = ts_q(1:4, 2010), B = ts_q(10:13, 2010))
  out <- merge_with_fallback(primary, fallback)
  expect_null(database_provenance(out))
})
