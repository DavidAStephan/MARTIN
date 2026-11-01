test_that("series_catalogue() loads cleanly with expected columns", {
  cat <- series_catalogue()
  expect_s3_class(cat, "tbl_df")
  expected_cols <- c(
    "martin_var", "source", "source_id", "source_table",
    "source_frequency", "aggregation", "transformation",
    "description", "units", "formula"
  )
  expect_setequal(names(cat), expected_cols)
  expect_gt(nrow(cat), 50L)  # institutional knowledge is non-trivial
})

test_that("series_catalogue() parses with zero readr problems", {
  # Guards against unquoted commas inside formula / description fields,
  # which silently shift columns and mangle rows (e.g. the D_OLYX Olympics
  # dummy, and the RBR / IBNDRA formulas with TSLAG(x, n) lag arguments).
  cat <- series_catalogue()
  problems <- readr::problems(cat)
  expect_equal(nrow(problems), 0L,
               info = paste("readr parse problems on rows:",
                            paste(problems$row, collapse = ", ")))
  # Every column must be present and all ten fields populated per row.
  expect_equal(ncol(cat), 10L)
})

test_that("every non-NA catalogue formula is a parseable R expression", {
  # A quoting bug truncates a formula mid-expression; a truncated formula
  # fails to parse, so this catches the regression directly on content.
  cat <- series_catalogue()
  formulas <- cat$formula[!is.na(cat$formula)]
  expect_gt(length(formulas), 0L)
  unparseable <- formulas[!vapply(formulas, function(s) {
    tryCatch({
      parse(text = s)
      TRUE
    }, error = function(e) FALSE)
  }, logical(1))]
  expect_equal(length(unparseable), 0L,
               info = paste("unparseable formulas:",
                            paste(unparseable, collapse = " | ")))
})

test_that("catalogue source values are from the allowed enum", {
  cat <- series_catalogue()
  allowed <- c("abs", "rba", "fred", "oecd", "worldbank", "bom", "derived")
  expect_true(all(cat$source %in% allowed),
              info = paste("Unexpected sources:",
                           paste(setdiff(cat$source, allowed),
                                 collapse = ", ")))
})

test_that("catalogue transformation values are from the allowed enum", {
  cat <- series_catalogue()
  allowed <- c("direct", "spliced", "chowlin", "level_from_pct", "derived",
               "dummy", "scalar", "state_space", "identity")
  expect_true(all(cat$transformation %in% allowed))
})

test_that("source_id is populated for non-derived rows and NA for derived", {
  cat <- series_catalogue()
  expect_true(all(!is.na(cat$source_id[cat$source != "derived"])))
  expect_true(all(is.na(cat$source_id[cat$source == "derived"])))
})

test_that("monthly catalogue rows have aggregation rules", {
  cat <- series_catalogue()
  monthly <- cat[cat$source_frequency == "M", , drop = FALSE]
  expect_true(all(!is.na(monthly$aggregation)),
              info = paste("missing aggregation for monthly rows:",
                           paste(monthly$martin_var[is.na(monthly$aggregation)],
                                 collapse = ", ")))
})

test_that("aggregation rule is present for sub-quarterly sources", {
  cat <- series_catalogue()
  sub_q <- cat[cat$source_frequency %in% c("M", "D") &
                 cat$transformation == "direct", , drop = FALSE]
  expect_true(all(!is.na(sub_q$aggregation)),
              info = paste("missing aggregation for:",
                           paste(sub_q$martin_var[is.na(sub_q$aggregation)],
                                 collapse = ", ")))
})

test_that("catalogue MARTIN variables are unique", {
  cat <- series_catalogue()
  expect_equal(anyDuplicated(cat$martin_var), 0L,
               info = paste("duplicate martin_var:",
                            paste(cat$martin_var[duplicated(cat$martin_var)],
                                  collapse = ", ")))
})

# ------ Coverage cross-check against martin::equation_catalogue() ------
# Every adjustable equation MARTIN exposes to the LLM must have an upstream
# data path — either a direct catalogue entry or one we can derive from
# catalogue entries. Anything missing here is a gap in the data layer that
# the judgement layer would expose to the LLM without a corresponding way
# to feed it.
test_that("every adjustable MARTIN equation has an upstream data path", {
  skip_if_not_installed("martin")
  cat <- series_catalogue()
  eq  <- martin::equation_catalogue()
  adjustable <- eq$code[eq$adjustable]

  # Catalogue lists either by martin_var (exact code) or as a derived row
  # whose description names the variable.
  covered <- union(
    cat$martin_var[cat$transformation %in% c("direct", "spliced",
                                              "chowlin", "level_from_pct")],
    cat$martin_var[cat$transformation == "derived"]
  )

  # MARTIN uses uppercase canonical names; catalogue also uses lowercase
  # for some raw imports. Compare case-insensitively.
  missing <- setdiff(toupper(adjustable), toupper(covered))

  # Known gaps in v0:
  #   - State-space trend variables (TDLLA, TDLLPOP, TDLLHPP, PI_E, TLUR,
  #     RSTAR) are produced by KFAS state-space code we haven't ported yet;
  #     in v0 we splice them from references/MARTIN-master/Data/martin_public.wf1
  #     so they're covered de-facto.
  #   - Several derived deflators MARTIN's equations imply but the legacy
  #     code computes inside modify_data.prg rather than read directly.
  known_v0_gaps <- toupper(c(
    "TDLLA", "TDLLPOP", "TDLLHPP", "PI_E", "TLUR", "RSTAR",
    "PEX",                # CPI excluding volatile from RBA already covered
    "NULCBS",             # derived from NULC in modify_data
    "RTWI_CONST", "WRR", "WR2R"
  ))
  unexpected <- setdiff(missing, known_v0_gaps)
  expect_equal(
    length(unexpected), 0L,
    info = paste("unexpected MARTIN adjustables without an upstream:",
                 paste(unexpected, collapse = ", "))
  )
})
