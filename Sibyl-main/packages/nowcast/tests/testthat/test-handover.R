test_that("handover_variables() returns a stable curated set", {
  hv <- handover_variables()
  expect_type(hv, "character")
  # The headline aggregates must all be present — these are what every
  # round report leads with.
  for (must_have in c("Y", "RC", "LE", "LUR", "PTM", "NCR", "WPOIL")) {
    expect_true(must_have %in% hv, info = must_have)
  }
  # Derived deflators (PIBN, PIBRE, PXM, etc.) are not in the handover set:
  # they're computed from the nominal/real pairs after the splice.
  expect_false("PIBN" %in% hv)
  expect_false("PXM"  %in% hv)
})

test_that("handover_variables() has no duplicates", {
  expect_equal(anyDuplicated(handover_variables()), 0L)
})
