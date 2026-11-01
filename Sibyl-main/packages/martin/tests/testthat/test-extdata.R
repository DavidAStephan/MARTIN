test_that("the vendored MARTINMOD model files are findable", {
  for (variant in c("af", "identity", "est")) {
    path <- model_file_path(variant)
    expect_true(file.exists(path), info = paste("variant =", variant))
    # Each file should be a non-trivial bimets model definition
    txt <- readLines(path, n = 5)
    expect_true(any(grepl("^MODEL", txt)), info = paste("variant =", variant))
  }
})

test_that("the bundled MARTINDATA fixture exists", {
  path <- martin_data_fixture()
  expect_true(file.exists(path))
  expect_match(path, "martin_data_fixture\\.xlsx$")
})

test_that("the equation catalogue loads and has the expected shape", {
  cat <- equation_catalogue()
  expected_cols <- c(
    "code", "name", "sector", "equation_type", "plain_english",
    "units", "adjustable", "typical_af_sd", "transmission_channel"
  )
  expect_setequal(names(cat), expected_cols)
  # At least the big behavioural equations should be present
  must_have <- c("RC", "IBN", "IBRE", "ID", "PTM", "PW", "LUR", "NCR", "RTWI")
  expect_true(all(must_have %in% cat$code))
  # Identities must not be flagged adjustable
  expect_true(all(cat$adjustable[cat$equation_type == "identity"] == FALSE))
})
