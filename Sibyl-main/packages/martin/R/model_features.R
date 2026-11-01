#' Optional MARTIN model features (baseline-neutral by default)
#'
#' The enhancements from `docs/martin_enhancements_plan.md` are delivered as
#' opt-in *features*: load-time transforms of the bimets model text plus the
#' data seeding bimets requires (every endogenous variable must have a series
#' present in the database). With no features requested the model text is
#' returned verbatim, so the frozen, no-adjustment baseline stays bit-identical
#' to the bimets reference (design principle 6).
#'
#' Implemented features:
#' \describe{
#'   \item{`output_gap`}{CES production function inverted EMMA-style. Adds the
#'     identities `KSTAR`, `NSTAR`, `YSTAR`, `YGAP`, `LESTAR`. Requires the
#'     labour-augmenting efficiency trend `EFF` in the database (see
#'     [sibyldata::fit_efficiency_trend()]). Calibration via
#'     `feature_params$ces_*`.}
#'   \item{`external_accounting`}{Net-foreign-liability / current-account stock
#'     accounting. Adds `NTB`, `TB_GDP`, `NCA`, `VNFL`, `NFL_GDP`, `CAD_GDP`.
#'     Uses `NFOY`/`NTRF` if present (else 0) and a `VNFL` seed.}
#'   \item{`fiscal_accounting`}{Government budget-and-debt accounting. Adds
#'     `NREV`, `NSPEND`, `NLEND`, `INTG`, `BG`, `BG_GDP`, `DEF_GDP`.
#'     `feature_params$fiscal_mode = "demo"` (default) uses proxy inputs with a
#'     balanced auto-calibration; `"reconciled"` (I-2) matches the balance to the
#'     realised ABS income account (`NG` + income-account payables = total
#'     outlays, corporate tax on `GOS`), needing the real fiscal series +
#'     `income_side`. Debt is in annual-GDP units. See `docs/income_side_scope.md`.}
#'   \item{`household_income`}{(I-2 household) Baseline-neutral decomposition of
#'     the lumped household non-labour income `NHOY` into income-account parts.
#'     Adds `HH_NONLAB` (non-labour primary income), `NHOY_RESID`, `NHDY_RECON`
#'     and `HH_TAXRATE`, using real ABS household-account series `HH_PRIMARY`
#'     (A2302917X) and `NHTAX` (A2302937J) when present. Leaves `NHOY`/`NHDY`/`RC`
#'     untouched. See `docs/income_side_scope.md`.}
#'   \item{`income_side`}{(I-0) Income side of GDP: the decomposition
#'     `NY = NHCOE + GOS + GMI + TAX_PROD_NET`. Adds `GOS` (gross operating
#'     surplus, as the residual), `PROFIT_SHARE` and `LABOUR_SHARE`. `GMI` and
#'     `TAX_PROD_NET` are real ABS series (5206.0) when present, else share-of-GDP
#'     proxies. See `docs/income_side_scope.md`.}
#'   \item{`corporate_accelerator`}{(I-3, T3) Balance-sheet financial accelerator.
#'     Adds the corporate-leverage identity `LEV` (debt-to-annual-GDP, from ABS
#'     `DCORP` A3427913W or a proxy) and re-estimates the business spread `NBRSP`
#'     with a lagged-leverage term, so a more-indebted corporate sector widens the
#'     external-finance premium (review F1/F5/SF4). Off by default.}
#'   \item{`endogenous_household`}{(I-2 Phase 2, T3) Replaces the `NHOY` ECM with
#'     an identity rebuilt from its components, with household income tax
#'     responding to primary income (`NHTAX_EN`) and transfers to unemployment
#'     (`NTRANSFERS_EN`) -- automatic stabilisers that flow into consumption `RC`.
#'     Needs `household_income`. Opt-in (re-baselines `RC`).}
#'   \item{`fx_premium`}{(T2) Debt-elastic exchange-rate risk premium: adds a
#'     `NFL_GDP` term to the `RTWI` equation. Needs `external_accounting`.}
#'   \item{`fiscal_rule`}{(T2) Debt-stabilising fiscal rule on the effective
#'     household tax rate. Needs `fiscal_accounting`.}
#'   \item{`convex_ptm`}{(T3) Convex Phillips curve: swaps the linear `c7*LURGAP`
#'     gap term in `PTM` for the reciprocal `c7*(LURGAP/LUR)` form (re-estimated).}
#'   \item{`inverted_le`}{(T3) Capital-aware employment: swaps the reduced-form
#'     error-correction target in `LE` for the inverted-production-function
#'     employment `LESTAR` (re-estimated). Needs `output_gap`.}
#'   \item{`elb_floor`}{(T1, fidelity) Restores the EViews effective-lower-bound
#'     floor on the cash rate (`equations.prg` L538, dropped by the bimets port).
#'     Renames the Taylor-rule behavioural to `NCR_RULE` (preserving estimation +
#'     residual handover) and makes `NCR` a floored identity at
#'     `feature_params$elb_floor_value` (default 0.1). Baseline-neutral: the floor
#'     never binds in sample so the solve is unchanged; it only bites in a
#'     forecast that eases below the bound. NB: with this on, cash-rate add-factors
#'     must target `NCR_RULE`, since `NCR` is now an identity.}
#' }
#'
#' @name model_features
NULL

# Order matters: insertions first (so swap-based features can target inserted
# blocks), then swaps.
.MARTIN_FEATURES <- c(
  "output_gap", "external_accounting", "fiscal_accounting", "income_side",
  "household_income", "corporate_accelerator",
  "fx_premium", "fiscal_rule", "convex_ptm", "inverted_le",
  "endogenous_household", "elb_floor"
)

#' Default calibration constants for the optional features
#' @return A named list of calibration parameters.
#' @export
feature_defaults <- function() {
  list(
    # CES (sigma = 0.5 -> rho = -1; identities use the harmonic form so no
    # power operator is needed). theta_k is the Australian capital share;
    # gamma is the CES scale, calibrated from data (NA forces the caller to
    # supply it for output_gap).
    ces_theta_k = 0.38,
    ces_gamma   = NA_real_,
    # Debt-elastic FX premium: semi-elasticity applied (scaled by 1/100 and the
    # RTWI error-correction speed) to the NFL_GDP gap, inside the EC target.
    fx_phi  = 0.1,
    fx_norm = 50,
    # Debt-stabilising fiscal rule.
    fiscal_rho1     = 0.10,
    fiscal_rho2     = 0.10,
    fiscal_bg_target = 30,
    fiscal_etr_direct = 0.16,
    fiscal_transfer_share = 0.11,  # transfers as a share of GDP (proxy)
    fiscal_iirg     = 4,           # implicit interest rate on govt debt (%)
    fiscal_def_target = 0.0,       # target primary balance / GDP for calibration
    # I-2 reconciliation: "demo" (M1 bounded structural demo) or "reconciled"
    # (income-account basis, balance matched to actual NGREV/NGEXP; needs the
    # real fiscal series + income_side for the GOS corporate-tax base).
    fiscal_mode     = "demo",
    fiscal_etr_income = 0.12,       # income-tax rate on household disposable income
    fiscal_etr_gos    = 0.20,       # corporate-tax rate on gross operating surplus
    # External accounting.
    nfl_seed = NA_real_,
    # Income side (I-0): proxy shares of GDP used only when the real ABS
    # series (GMI, TAX_PROD_NET) are absent (e.g. on the fixture).
    income_gmi_share = 0.08,
    income_tax_share = 0.05,
    # Household income account (I-2 household): proxy shares of GDP for
    # HH_PRIMARY / NHTAX when the real ABS series are absent.
    hh_primary_share = 0.42,
    hh_tax_share     = 0.13,
    # Corporate accelerator (I-3): proxy corporate-debt share of GDP when the
    # real ABS series (DCORP) is absent.
    corp_debt_share  = 0.45,
    # Corporate sector (I-1/I-3): corporate share of GOS; retained-earnings
    # share of corporate GOS (after interest/dividends/tax) for net worth;
    # corporate net worth seeded at this multiple of annual GDP.
    corp_gos_share   = 0.75,
    corp_retain_share = 0.30,
    corp_nw_mult     = 2.0,
    # Endogenous household income (I-2 Phase 2): unemployment-benefit
    # sensitivity (per cent of GDP per pp of LUR above normal) and the normal
    # unemployment rate the transfer rule centres on.
    hh_trans_unemp   = 0.30,
    hh_lur_norm      = 5.0,
    # Effective-lower-bound floor on the nominal cash rate (per cent). 0.1
    # reproduces the EViews @recode floor (equations.prg L538) that the bimets
    # port dropped, so the solved NCR cannot go negative when the feature is on.
    elb_floor_value  = 0.1
  )
}

#' Which new endogenous variables each feature introduces
#' @param features Character vector of feature names.
#' @return Character vector of new endogenous variable names.
#' @keywords internal
feature_new_vars <- function(features) {
  v <- character(0)
  if ("output_gap" %in% features)
    v <- c(v, "KSTAR", "NSTAR", "YSTAR", "YGAP", "LESTAR")
  if ("external_accounting" %in% features)
    v <- c(v, "NTB", "TB_GDP", "NCA", "VNFL", "NFL_GDP", "CAD_GDP",
           "GNI", "GNI_GDP_WEDGE")
  if ("fiscal_accounting" %in% features)
    v <- c(v, "NREV", "NSPEND", "NLEND", "INTG", "BG", "BG_GDP", "DEF_GDP")
  if ("income_side" %in% features)
    v <- c(v, "GOS", "PROFIT_SHARE", "LABOUR_SHARE", "GOS_CORP")
  if ("household_income" %in% features)
    v <- c(v, "HH_NONLAB", "NHOY_RESID", "NHDY_RECON", "HH_TAXRATE")
  if ("corporate_accelerator" %in% features)
    v <- c(v, "LEV", "RET_EARN", "VCORP", "LEV_DE")
  if ("endogenous_household" %in% features)
    v <- c(v, "NHTAX_EN", "NTRANSFERS_EN")
  if ("elb_floor" %in% features)
    v <- c(v, "NCR_RULE")
  unique(v)
}

# --- text helpers ----------------------------------------------------------

# Replace `pattern` with `replacement` exactly once; error if not found or not
# unique. The loud failure is deliberate — a silent no-op swap would ship a
# feature that does nothing.
.swap_once <- function(text, pattern, replacement) {
  hits <- gregexpr(pattern, text, fixed = TRUE)[[1]]
  found <- !(length(hits) == 1L && hits[1] == -1L)
  n <- if (found) length(hits) else 0L
  if (n != 1L) {
    stop(sprintf("feature swap matched %d times (need exactly 1): %s",
                 n, pattern), call. = FALSE)
  }
  sub(pattern, replacement, text, fixed = TRUE)
}

.insert_blocks_before_end <- function(lines, blocks) {
  end_i <- which(grepl("^END\\s*$", lines))
  if (!length(end_i)) stop("model text has no END line", call. = FALSE)
  end_i <- max(end_i)
  append(lines, blocks, after = end_i - 1L)
}

# --- feature blocks (inserted identities) ----------------------------------

.block_output_gap <- function(p) {
  if (is.na(p$ces_gamma)) {
    stop("output_gap feature needs feature_params$ces_gamma ",
         "(calibrate via sibyldata::ces_calibration()).", call. = FALSE)
  }
  tk <- p$ces_theta_k
  tn <- 1 - tk
  g  <- p$ces_gamma
  # sigma = 0.5 -> CES collapses to the harmonic form
  #   Y = gamma / ( theta_n/(EFF*LHPP*LE) + theta_k/K )
  # so potential and the inverted employment need only * and / (no powers).
  c(
    "COMMENT> SIBYL output_gap: CES production block (sigma=0.5 harmonic form)",
    "COMMENT> KSTAR  market capital stock",
    "IDENTITY> KSTAR",
    "EQ> KSTAR = KIBN + KIBRE",
    "",
    "COMMENT> NSTAR  employment at the NAIRU (actual participation, v1)",
    "IDENTITY> NSTAR",
    "EQ> NSTAR = LPOP * (LPR/100) * (1 - TLUR/100)",
    "",
    "COMMENT> YSTAR  potential output (CES at trend efficiency, NAIRU employment, actual capital)",
    "IDENTITY> YSTAR",
    sprintf("EQ> YSTAR = %.10g / ( %.10g/(EFF*LHPP*NSTAR) + %.10g/KSTAR )", g, tn, tk),
    "",
    "COMMENT> YGAP  output gap, per cent",
    "IDENTITY> YGAP",
    "EQ> YGAP = (LOG(Y) - LOG(YSTAR)) * 100",
    "",
    "COMMENT> LESTAR  inverted-production-function employment (EMMA Eq 6a)",
    "COMMENT> denom (gamma/Y - theta_k/KSTAR) > 0 holds empirically; a NaN here",
    "COMMENT> is surfaced by solve_martin's convergence diagnostic.",
    "IDENTITY> LESTAR",
    sprintf("EQ> LESTAR = ( %.10g / (%.10g/Y - %.10g/KSTAR) ) / (EFF*LHPP)",
            tn, g, tk),
    ""
  )
}

.block_external <- function(p) {
  c(
    "COMMENT> SIBYL external_accounting: current account + net foreign liability stock",
    "COMMENT> NTB  nominal trade balance",
    "IDENTITY> NTB",
    "EQ> NTB = NX - NM",
    "",
    "COMMENT> TB_GDP  trade balance, per cent of GDP",
    "IDENTITY> TB_GDP",
    "EQ> TB_GDP = NTB / NY * 100",
    "",
    "COMMENT> NCA  current account = trade balance + net foreign income + transfers",
    "COMMENT> NFOY (net primary income) and NTRF (net secondary income) are exogenous inputs (0 if absent)",
    "IDENTITY> NCA",
    "EQ> NCA = NTB + NFOY + NTRF",
    "",
    "COMMENT> VNFL  net foreign liability stock (accumulates the current-account deficit)",
    "IDENTITY> VNFL",
    "EQ> VNFL = TSLAG(VNFL,1) - NCA",
    "",
    "COMMENT> NFL_GDP  net foreign liabilities, per cent of GDP",
    "IDENTITY> NFL_GDP",
    "EQ> NFL_GDP = VNFL / NY * 100",
    "",
    "COMMENT> CAD_GDP  current account deficit, per cent of GDP",
    "IDENTITY> CAD_GDP",
    "EQ> CAD_GDP = -NCA / NY * 100",
    "",
    "COMMENT> GNI  gross national income = GDP + net foreign primary income (I-1)",
    "IDENTITY> GNI",
    "EQ> GNI = NY + NFOY",
    "",
    "COMMENT> GNI_GDP_WEDGE  GDP-GNI gap, per cent (net foreign primary income / GDP)",
    "IDENTITY> GNI_GDP_WEDGE",
    "EQ> GNI_GDP_WEDGE = NFOY / NY * 100",
    ""
  )
}

.block_fiscal <- function(p) {
  if (identical(p$fiscal_mode, "reconciled")) return(.block_fiscal_reconciled(p))
  # ETR_DIRECT, ETR_INDIRECT, ETR_CORP, NTRANSFERS, IIRG are exogenous inputs.
  # When fiscal_rule is also requested, ETR_DIRECT is replaced by an identity
  # (see .feature_fiscal_rule). Bases reuse in-model nominal series.
  c(
    "COMMENT> SIBYL fiscal_accounting: government budget + debt accounting",
    "COMMENT> NREV  nominal government revenue (effective-rate x base)",
    "IDENTITY> NREV",
    "EQ> NREV = ETR_DIRECT*NHDY + ETR_INDIRECT*NC + ETR_CORP*(NY - NHCOE)",
    "",
    "COMMENT> NSPEND  nominal government spending (demand + transfers)",
    "IDENTITY> NSPEND",
    "EQ> NSPEND = NG + NTRANSFERS",
    "",
    "COMMENT> INTG  debt interest (annual implicit rate /4 on lagged debt)",
    "IDENTITY> INTG",
    "EQ> INTG = IIRG/400 * TSLAG(BG,1)",
    "",
    "COMMENT> NLEND  government net lending",
    "IDENTITY> NLEND",
    "EQ> NLEND = NREV - NSPEND - INTG",
    "",
    "COMMENT> BG  government debt stock",
    "IDENTITY> BG",
    "EQ> BG = TSLAG(BG,1) - NLEND",
    "",
    "COMMENT> BG_GDP  debt, per cent of annual GDP (4*NY)",
    "IDENTITY> BG_GDP",
    "EQ> BG_GDP = BG / (4*NY) * 100",
    "",
    "COMMENT> DEF_GDP  fiscal deficit, per cent of GDP",
    "IDENTITY> DEF_GDP",
    "EQ> DEF_GDP = -NLEND / NY * 100",
    ""
  )
}

.block_income_side <- function(p) {
  c(
    "COMMENT> SIBYL income_side (I-0): GDP(I) decomposition  NY = NHCOE + GOS + GMI + TAX_PROD_NET",
    "COMMENT> GOS  gross operating surplus + mixed-income residual (incl. the small income-side",
    "COMMENT> statistical discrepancy); GMI and TAX_PROD_NET are exogenous (real ABS or proxy).",
    "IDENTITY> GOS",
    "EQ> GOS = NY - NHCOE - GMI - TAX_PROD_NET",
    "",
    "COMMENT> PROFIT_SHARE  gross operating surplus, per cent of GDP",
    "IDENTITY> PROFIT_SHARE",
    "EQ> PROFIT_SHARE = GOS / NY * 100",
    "",
    "COMMENT> LABOUR_SHARE  compensation of employees, per cent of GDP (= NHWS*100)",
    "IDENTITY> LABOUR_SHARE",
    "EQ> LABOUR_SHARE = NHCOE / NY * 100",
    "",
    "COMMENT> GOS_CORP  corporate share of gross operating surplus (excl. dwellings/govt)",
    "IDENTITY> GOS_CORP",
    sprintf("EQ> GOS_CORP = %.10g * GOS", p$corp_gos_share),
    ""
  )
}

# I-2 reconciled fiscal block (income-account basis; needs income_side for GOS).
# Major taxes are endogenous (rate x base); NREV_OTHER / NGEXP_OTHER are
# exogenous residuals that plug modelled revenue/spending to the actual ABS
# income-account totals, so the balance NLEND = NREV - NSPEND matches history
# while income tax responds to NHDY, corporate tax to GOS, transfers to LUR and
# interest to the debt stock.
.block_fiscal_reconciled <- function(p) {
  c(
    "COMMENT> SIBYL fiscal_accounting (I-2 reconciled): income-account basis",
    "COMMENT> NREV  revenue: income tax(NHDY) + corporate tax(GOS) + production tax + residual",
    "IDENTITY> NREV",
    "EQ> NREV = ETR_DIRECT*NHDY + ETR_GOS*GOS + TAX_PROD_NET + NREV_OTHER",
    "",
    "COMMENT> INTG  debt interest (actual ABS general-government interest payable;",
    "COMMENT> exogenous here so the balance matches history -- a debt-elastic",
    "COMMENT> interest feedback is a later refinement, review G4)",
    "IDENTITY> INTG",
    "EQ> INTG = NGINT",
    "",
    "COMMENT> NSPEND  total outlays: govt demand NG (consumption+investment, model-",
    "COMMENT> endogenous) + transfers + interest + an exogenous income-account",
    "COMMENT> residual (subsidies/other). NG and the income-account payables are",
    "COMMENT> complementary and sum to total expenditure.",
    "IDENTITY> NSPEND",
    "EQ> NSPEND = NG + NTRANSFERS + INTG + NGEXP_OTHER",
    "",
    "COMMENT> NLEND  government net lending (consistent income-account balance)",
    "IDENTITY> NLEND",
    "EQ> NLEND = NREV - NSPEND",
    "",
    "COMMENT> BG  government debt stock",
    "IDENTITY> BG",
    "EQ> BG = TSLAG(BG,1) - NLEND",
    "",
    "COMMENT> BG_GDP  debt, per cent of annual GDP (4*NY)",
    "IDENTITY> BG_GDP",
    "EQ> BG_GDP = BG / (4*NY) * 100",
    "",
    "COMMENT> DEF_GDP  fiscal deficit, per cent of GDP",
    "IDENTITY> DEF_GDP",
    "EQ> DEF_GDP = -NLEND / NY * 100",
    ""
  )
}

# I-2 household income account: a baseline-neutral decomposition of the lumped
# household non-labour income NHOY into its income-account components. NHOY,
# NHDY and consumption RC are untouched (NHOY_RESID plugs the components to the
# existing NHOY); a small residual means the ABS components explain NHOY well.
.block_household_income <- function(p) {
  c(
    "COMMENT> SIBYL household_income (I-2): decompose NHOY into income-account parts",
    "COMMENT> HH_NONLAB  household non-labour primary income (GMI + property income) = HH_PRIMARY - NHCOE",
    "IDENTITY> HH_NONLAB",
    "EQ> HH_NONLAB = HH_PRIMARY - NHCOE",
    "",
    "COMMENT> NHOY_RESID  unexplained residual: NHOY minus the ABS components",
    "IDENTITY> NHOY_RESID",
    "EQ> NHOY_RESID = NHOY - HH_NONLAB + NHTAX - NTRANSFERS",
    "",
    "COMMENT> NHDY_RECON  household disposable income rebuilt from the account (= NHDY by construction)",
    "IDENTITY> NHDY_RECON",
    "EQ> NHDY_RECON = HH_PRIMARY - NHTAX + NTRANSFERS + NHOY_RESID",
    "",
    "COMMENT> HH_TAXRATE  effective household tax rate, per cent of primary income",
    "IDENTITY> HH_TAXRATE",
    "EQ> HH_TAXRATE = NHTAX / HH_PRIMARY * 100",
    ""
  )
}

# I-3 corporate accelerator: a balance-sheet financial-accelerator hook. Adds a
# corporate-leverage identity LEV (debt-to-annual-GDP) and makes the business
# borrowing spread NBRSP load on lagged leverage, so a more-indebted corporate
# sector raises the external-finance premium (review F1/F5/SF4) -- replacing the
# purely cyclical LURGAP proxy with a genuine leverage channel.
.block_corporate <- function(p) {
  c(
    "COMMENT> SIBYL corporate_accelerator (I-3): corporate balance sheet + leverage",
    "COMMENT> LEV  corporate debt, per cent of annual GDP (the accelerator input)",
    "IDENTITY> LEV",
    "EQ> LEV = DCORP / (4*NY) * 100",
    "",
    "COMMENT> RET_EARN  corporate retained earnings (saving) = retain share of corporate GOS",
    "IDENTITY> RET_EARN",
    sprintf("EQ> RET_EARN = %.10g * GOS_CORP", p$corp_retain_share),
    "",
    "COMMENT> VCORP  corporate net worth (accumulated retained earnings from a seed)",
    "IDENTITY> VCORP",
    "EQ> VCORP = TSLAG(VCORP,1) + RET_EARN",
    "",
    "COMMENT> LEV_DE  corporate gearing: debt-to-net-worth, per cent",
    "IDENTITY> LEV_DE",
    "EQ> LEV_DE = DCORP / VCORP * 100",
    ""
  )
}

.feature_corporate_accelerator <- function(text, p) {
  # Add a lagged-leverage term to NBRSP and free its new coefficient. This
  # re-estimates NBRSP (T3); the default model keeps the published 3-term form.
  .swap_once(
    text,
    "EQ> NBRSP = c1 + c2*TSLAG(NBRSP,1) + c3*LURGAP\nCOEFF> c1 c2 c3",
    "EQ> NBRSP = c1 + c2*TSLAG(NBRSP,1) + c3*LURGAP + c4*TSLAG(LEV,1)\nCOEFF> c1 c2 c3 c4"
  )
}

# I-2 Phase 2: automatic stabilisers in household income. NHTAX_EN responds to
# primary income, NTRANSFERS_EN to unemployment, and NHOY is rebuilt from its
# components (so household disposable income -- hence consumption RC -- carries
# fiscal stabilisers). Opt-in: it replaces the NHOY ECM with an identity.
.block_endogenous_household <- function(p) {
  c(
    "COMMENT> SIBYL endogenous_household (I-2 Phase 2): household automatic stabilisers",
    "COMMENT> NHTAX_EN  household income tax = effective rate x primary income",
    "IDENTITY> NHTAX_EN",
    "EQ> NHTAX_EN = ETR_HH/100 * HH_PRIMARY",
    "",
    "COMMENT> NTRANSFERS_EN  transfers rising with unemployment above the norm",
    "IDENTITY> NTRANSFERS_EN",
    sprintf("EQ> NTRANSFERS_EN = NTRANSFERS + %.10g*(LUR - %.10g)*NY/100",
            p$hh_trans_unemp, p$hh_lur_norm),
    ""
  )
}

# Replace the NHOY behavioural block with an identity rebuilt from its
# income-account components (line-based, to avoid whitespace fragility).
.feature_endogenous_household <- function(text, p) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  i0 <- which(lines == "BEHAVIORAL> NHOY")
  if (length(i0) != 1L)
    stop("endogenous_household: NHOY behavioral not found uniquely", call. = FALSE)
  win <- lines[(i0 + 1):min(i0 + 8, length(lines))]
  rel <- which(win == "RESTRICT>c4=1")[1]
  if (is.na(rel))
    stop("endogenous_household: NHOY block end not found", call. = FALSE)
  i1 <- i0 + rel
  repl <- c("IDENTITY> NHOY",
            "EQ> NHOY = HH_NONLAB - NHTAX_EN + NTRANSFERS_EN + NHOY_RESID")
  paste(c(lines[seq_len(i0 - 1)], repl, lines[(i1 + 1):length(lines)]),
        collapse = "\n")
}

# --- swap-based features ----------------------------------------------------

.feature_fx_premium <- function(text, p) {
  # Inject the debt-elastic premium INSIDE the RTWI error-correction target (the
  # bracket scaled by -0.218928), so a higher net-foreign-liability ratio raises
  # the deviation from fair value and the real exchange rate mean-reverts to a
  # lower (depreciated) level -- gradual and bounded, not a raw dlog kick.
  .swap_once(
    text,
    "- -0.5236049854787135))",
    sprintf("- -0.5236049854787135) + %.10g/100*(TSLAG(NFL_GDP,1) - %.10g))",
            p$fx_phi, p$fx_norm)
  )
}

.feature_inverted_le <- function(text, p) {
  .swap_once(
    text,
    "c2*(LOG(TSLAG(LE,1)) - LOG(TSLAG(Y,1))+0.4*(LOG(TSLAG(RLC,1)) - TSLAG(TLLA,1)) + TSLAG(TLLA,1) + TSLAG(TLLHPP,1) )",
    "c2*(LOG(TSLAG(LE,1)) - LOG(TSLAG(LESTAR,1)) )"
  )
}

.feature_fiscal_rule <- function(text, p) {
  # Debt-stabilising rule on transfers (the spending instrument): when debt is
  # above target, transfers are cut, lifting net lending and pulling debt back.
  # Acting on transfers (not the tax rate) keeps the revenue calibration intact
  # and preserves all the budget identities. Requires fiscal_accounting (which
  # seeds NTRANSFERS_BASE and computes BG_GDP).
  rule <- paste0(
    "\nCOMMENT> SIBYL fiscal_rule: debt-stabilising transfers\n",
    "IDENTITY> NTRANSFERS\n",
    sprintf(paste0("EQ> NTRANSFERS = NTRANSFERS_BASE - ( %.10g*(TSLAG(BG_GDP,1) - %.10g) ",
                   "+ %.10g*TSDELTA(TSLAG(BG_GDP,1),1) )*NY/100\n"),
            p$fiscal_rho1, p$fiscal_bg_target, p$fiscal_rho2)
  )
  .swap_once(text, "COMMENT> SIBYL fiscal_accounting: government budget + debt accounting",
             paste0(rule, "\nCOMMENT> SIBYL fiscal_accounting: government budget + debt accounting"))
}

# Effective-lower-bound floor on the cash rate. EViews floors the Taylor rule at
# 0.1 via @recode (equations.prg L538); the bimets port dropped it, so the solved
# NCR can go negative. We restore it WITHOUT touching the bit-identical default:
# rename the NCR behavioural to NCR_RULE (so it keeps estimating + carrying its
# residual/add-factor handover), then add a floored NCR identity using bimets
# IF> conditional branches (only one IF> per identity group, so the two branches
# repeat `IDENTITY> NCR`). When the rule sits above the floor -- always, in
# sample -- NCR == NCR_RULE, so the solve is unchanged; the floor only bites in a
# forecast that eases the cash rate below the bound.
.feature_elb_floor <- function(text, p) {
  floor_val <- p$elb_floor_value
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  ib <- which(lines == "BEHAVIORAL> NCR")
  if (length(ib) != 1L)
    stop("elb_floor: NCR behavioral not found uniquely", call. = FALSE)
  lines[ib] <- "BEHAVIORAL> NCR_RULE"
  ieq <- which(startsWith(lines, "EQ> NCR ") & seq_along(lines) > ib)[1]
  if (is.na(ieq))
    stop("elb_floor: NCR equation line not found", call. = FALSE)
  lines[ieq] <- sub("EQ> NCR ", "EQ> NCR_RULE ", lines[ieq], fixed = TRUE)
  blk <- c(
    "COMMENT> SIBYL elb_floor: effective-lower-bound floor on the cash rate (EViews @recode parity)",
    "IDENTITY> NCR",
    "EQ> NCR = NCR_RULE",
    sprintf("IF> NCR_RULE > %.10g", floor_val),
    "IDENTITY> NCR",
    sprintf("EQ> NCR = %.10g", floor_val),
    sprintf("IF> NCR_RULE <= %.10g", floor_val))
  lines <- .insert_blocks_before_end(lines, blk)
  paste(lines, collapse = "\n")
}

#' Apply requested features to MARTIN model text lines
#' @param lines Character vector of model-file lines.
#' @param features Character vector of feature names (subset of
#'   [model_features]). Empty returns `lines` unchanged.
#' @param feature_params Calibration overrides; merged over [feature_defaults()].
#' @return Transformed character vector of model lines.
#' @export
apply_model_features <- function(lines, features = character(0),
                                 feature_params = list()) {
  if (!length(features)) return(lines)
  unknown <- setdiff(features, .MARTIN_FEATURES)
  if (length(unknown)) {
    stop("unknown model feature(s): ", paste(unknown, collapse = ", "),
         call. = FALSE)
  }
  p <- utils::modifyList(feature_defaults(), feature_params)

  # 1. insert new equation blocks before END
  blocks <- character(0)
  if ("output_gap" %in% features)
    blocks <- c(blocks, .block_output_gap(p))
  if ("external_accounting" %in% features)
    blocks <- c(blocks, .block_external(p))
  if ("fiscal_accounting" %in% features)
    blocks <- c(blocks, .block_fiscal(p))
  if ("income_side" %in% features)
    blocks <- c(blocks, .block_income_side(p))
  if ("household_income" %in% features)
    blocks <- c(blocks, .block_household_income(p))
  if ("corporate_accelerator" %in% features)
    blocks <- c(blocks, .block_corporate(p))
  if ("endogenous_household" %in% features)
    blocks <- c(blocks, .block_endogenous_household(p))
  if (length(blocks)) lines <- .insert_blocks_before_end(lines, blocks)

  # 2. text swaps (operate on the full text, incl. inserted blocks)
  text <- paste(lines, collapse = "\n")
  if ("fiscal_rule" %in% features)  text <- .feature_fiscal_rule(text, p)
  if ("fx_premium" %in% features)   text <- .feature_fx_premium(text, p)
  if ("convex_ptm" %in% features)
    text <- .swap_once(text, "+c7*LURGAP", "+c7*(LURGAP/LUR)")
  if ("inverted_le" %in% features)  text <- .feature_inverted_le(text, p)
  if ("corporate_accelerator" %in% features)
    text <- .feature_corporate_accelerator(text, p)
  if ("endogenous_household" %in% features)
    text <- .feature_endogenous_household(text, p)
  if ("elb_floor" %in% features)
    text <- .feature_elb_floor(text, p)

  strsplit(text, "\n", fixed = TRUE)[[1]]
}

#' Seed the database with series required by the requested features
#'
#' bimets requires every endogenous variable to have a series in the database.
#' Non-lagged new identities are seeded with NA over the database span (bimets
#' computes them inside TSRANGE); lagged stocks (`VNFL`, `BG`) and exogenous
#' inputs (`EFF`, `NFOY`, `NTRF`, `ETR_*`, `NTRANSFERS`, `IIRG`) must carry real
#' values and are seeded if absent.
#'
#' @param database Named list of bimets TIMESERIES.
#' @param features Character vector of feature names.
#' @param feature_params Calibration overrides; merged over [feature_defaults()].
#' @return The database with the required series added/seeded.
#' @export
seed_feature_data <- function(database, features = character(0),
                              feature_params = list()) {
  if (!length(features)) return(database)
  p <- utils::modifyList(feature_defaults(), feature_params)

  span <- .db_span(database)
  na_series  <- function() bimets::TIMESERIES(rep(NA_real_, span$n),
                                              START = span$start, FREQ = 4)
  zero_series <- function() bimets::TIMESERIES(rep(0, span$n),
                                               START = span$start, FREQ = 4)
  ensure_exog <- function(db, nm, fill = 0) {
    if (is.null(db[[nm]])) db[[nm]] <- bimets::TIMESERIES(
      rep(fill, span$n), START = span$start, FREQ = 4)
    db
  }

  if ("output_gap" %in% features) {
    if (is.null(database[["EFF"]])) {
      stop("output_gap feature requires `EFF` in the database ",
           "(sibyldata::fit_efficiency_trend()).", call. = FALSE)
    }
    if (is.na(p$ces_gamma)) {
      stop("output_gap feature requires feature_params$ces_gamma.",
           call. = FALSE)
    }
    # bimets needs defined initialisation values for every endogenous series,
    # so compute the CES block historically rather than NA-seeding.
    ser <- .compute_output_gap_series(database, p)
    for (nm in names(ser)) {
      if (is.null(database[[nm]])) database[[nm]] <- ser[[nm]]
    }
  }

  if ("external_accounting" %in% features) {
    database <- ensure_exog(database, "NFOY", 0)
    database <- ensure_exog(database, "NTRF", 0)
    ser <- .compute_external_series(database, p)
    for (nm in names(ser)) if (is.null(database[[nm]])) database[[nm]] <- ser[[nm]]
  }

  # income_side seeds GOS / TAX_PROD_NET before fiscal, because the reconciled
  # fiscal mode uses GOS as the corporate-tax base.
  if ("income_side" %in% features) {
    # GMI and TAX_PROD_NET: real ABS series when present (M1 catalogue), else
    # share-of-GDP proxies so the block works on the fixture too.
    if (is.null(database[["GMI"]]))
      database <- .seed_proportional(database, "GMI", p$income_gmi_share)
    if (is.null(database[["TAX_PROD_NET"]]))
      database <- .seed_proportional(database, "TAX_PROD_NET", p$income_tax_share)
    ser <- .compute_income_side(database, p)
    for (nm in names(ser)) if (is.null(database[[nm]])) database[[nm]] <- ser[[nm]]
  }

  if ("household_income" %in% features) {
    if (is.null(database[["HH_PRIMARY"]]))
      database <- .seed_proportional(database, "HH_PRIMARY", p$hh_primary_share)
    if (is.null(database[["NHTAX"]]))
      database <- .seed_proportional(database, "NHTAX", p$hh_tax_share)
    if (is.null(database[["NTRANSFERS"]]))
      database <- .seed_proportional(database, "NTRANSFERS", p$fiscal_transfer_share)
    ser <- .compute_household_income(database, p)
    for (nm in names(ser)) if (is.null(database[[nm]])) database[[nm]] <- ser[[nm]]
  }

  if ("endogenous_household" %in% features) {
    need <- c("HH_PRIMARY", "NHTAX", "NTRANSFERS", "HH_NONLAB", "NHOY_RESID", "LUR", "NY")
    miss <- need[vapply(need, function(n) is.null(database[[n]]), logical(1))]
    if (length(miss)) {
      stop("endogenous_household needs household_income; missing: ",
           paste(miss, collapse = ", "), call. = FALSE)
    }
    # Effective household tax rate calibrated to the historical mean, so the
    # in-sample level matches and the forecast response is to the income base.
    a <- .align_db(database, c("NHTAX", "HH_PRIMARY"))
    etr_hh <- mean(a$mat[, "NHTAX"] / a$mat[, "HH_PRIMARY"], na.rm = TRUE) * 100
    if (is.null(database[["ETR_HH"]])) database <- .seed_const(database, "ETR_HH", etr_hh)
    b <- .align_db(database, c("HH_PRIMARY", "NTRANSFERS", "LUR", "NY", "ETR_HH"))
    m <- b$mat
    mk <- function(v) bimets::TIMESERIES(v, START = b$start, FREQ = 4)
    if (is.null(database[["NHTAX_EN"]]))
      database[["NHTAX_EN"]] <- mk(m[, "ETR_HH"] / 100 * m[, "HH_PRIMARY"])
    if (is.null(database[["NTRANSFERS_EN"]]))
      database[["NTRANSFERS_EN"]] <- mk(m[, "NTRANSFERS"] +
        p$hh_trans_unemp * (m[, "LUR"] - p$hh_lur_norm) * m[, "NY"] / 100)
  }

  if ("corporate_accelerator" %in% features) {
    if (is.null(database[["DCORP"]]))
      database <- .seed_proportional(database, "DCORP", p$corp_debt_share)
    if (is.null(database[["GOS_CORP"]]))  # proxy if income_side off (~27% of GDP)
      database <- .seed_proportional(database, "GOS_CORP", 0.27)
    ser <- .compute_corporate(database, p)
    for (nm in names(ser)) if (is.null(database[[nm]])) database[[nm]] <- ser[[nm]]
  }

  if ("fiscal_accounting" %in% features) {
    if (identical(p$fiscal_mode, "reconciled")) {
      database <- .seed_fiscal_reconciled(database, p)
    } else {
      database <- ensure_exog(database, "ETR_DIRECT",   p$fiscal_etr_direct)
      database <- ensure_exog(database, "ETR_INDIRECT", 0.10)
      database <- ensure_exog(database, "ETR_CORP",     0.05)
      database <- ensure_exog(database, "IIRG",         p$fiscal_iirg)
      if (is.null(database[["NTRANSFERS"]])) {  # transfers proportional to GDP
        nyts <- stats::as.ts(database[["NY"]])
        tsp  <- stats::tsp(nyts)
        sy <- floor(tsp[1] + 1e-9); sq <- round((tsp[1] - sy) * 4 + 1)
        database[["NTRANSFERS"]] <- bimets::TIMESERIES(
          p$fiscal_transfer_share * as.numeric(nyts), START = c(sy, sq), FREQ = 4)
      }
      # Base transfers level the debt-stabilising rule (fiscal_rule) adjusts from.
      if (is.null(database[["NTRANSFERS_BASE"]])) {
        database[["NTRANSFERS_BASE"]] <- database[["NTRANSFERS"]]
      }
      # Until real GFS revenue is wired, auto-calibrate the effective rates so
      # the budget balances to the target at the base, keeping the demo debt
      # path bounded and plausible.
      database <- .calibrate_fiscal_rates(database, p)
      ser <- .compute_fiscal_series(database, p)
      for (nm in names(ser)) if (is.null(database[[nm]])) database[[nm]] <- ser[[nm]]
    }
  }

  if ("elb_floor" %in% features) {
    # The renamed Taylor-rule behavioural NCR_RULE inherits NCR's history so it
    # estimates identically (and carries the same residual into the forecast);
    # NCR itself becomes the floored identity. Floor never binds in sample, so
    # NCR_RULE == NCR there and the seed is exact.
    if (is.null(database[["NCR"]]))
      stop("elb_floor feature requires `NCR` in the database.", call. = FALSE)
    if (is.null(database[["NCR_RULE"]]))
      database[["NCR_RULE"]] <- database[["NCR"]]
  }

  database
}

# I-2 reconciled fiscal seeding: requires the real ABS income-account series
# (NGREV/NGEXP/NGINT, M1 catalogue) plus income_side (GOS, TAX_PROD_NET).
.seed_fiscal_reconciled <- function(db, p) {
  need <- c("NGREV", "NGEXP", "NGINT", "NHDY", "GOS", "TAX_PROD_NET", "NY")
  miss <- need[vapply(need, function(n) is.null(db[[n]]), logical(1))]
  if (length(miss)) {
    stop("fiscal_mode='reconciled' needs real fiscal data + income_side; missing: ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  if (is.null(db[["ETR_DIRECT"]])) db <- .seed_const(db, "ETR_DIRECT", p$fiscal_etr_income)
  if (is.null(db[["ETR_GOS"]]))    db <- .seed_const(db, "ETR_GOS",    p$fiscal_etr_gos)
  if (is.null(db[["IIRG"]]))       db <- .seed_const(db, "IIRG",       p$fiscal_iirg)
  if (is.null(db[["NTRANSFERS"]]))
    db <- .seed_proportional(db, "NTRANSFERS", p$fiscal_transfer_share)
  if (is.null(db[["NTRANSFERS_BASE"]])) db[["NTRANSFERS_BASE"]] <- db[["NTRANSFERS"]]
  ser <- .compute_fiscal_series_reconciled(db, p)
  for (nm in names(ser)) if (is.null(db[[nm]])) db[[nm]] <- ser[[nm]]
  db
}

# Reconciled fiscal series, income-account basis. NGEXP_OTHER is defined against
# the MODELLED interest so NSPEND collapses to actual NGEXP in history; NREV_OTHER
# plugs the modelled taxes to actual NGREV. Hence NLEND = NGREV - NGEXP (the
# realised balance) in history, while the components stay endogenous forward.
.compute_fiscal_series_reconciled <- function(db, p) {
  a <- .align_db(db, c("NY", "NHDY", "GOS", "TAX_PROD_NET", "NTRANSFERS",
                       "NG", "NGREV", "NGEXP", "NGINT", "ETR_DIRECT", "ETR_GOS"))
  m <- a$mat; n <- nrow(m)
  intg   <- m[, "NGINT"]                              # actual interest (exogenous)
  nrev_other  <- m[, "NGREV"] - m[, "ETR_DIRECT"] * m[, "NHDY"] -
                 m[, "ETR_GOS"] * m[, "GOS"] - m[, "TAX_PROD_NET"]
  ngexp_other <- m[, "NGEXP"] - m[, "NTRANSFERS"] - intg   # income-payable residual
  nrev   <- m[, "ETR_DIRECT"] * m[, "NHDY"] + m[, "ETR_GOS"] * m[, "GOS"] +
            m[, "TAX_PROD_NET"] + nrev_other         # = NGREV
  nspend <- m[, "NG"] + m[, "NTRANSFERS"] + intg + ngexp_other  # = NG + NGEXP (total outlays)
  nlend  <- nrev - nspend                            # = NGREV - NG - NGEXP (realised balance)
  # Seed the debt history at the target ratio (no clean quarterly govt-debt
  # series wired); the model accumulates BG = BG(-1) - NLEND over the solve
  # window from this realistic jump-off. Interest is the actual series (does not
  # compound the debt), so the path stays bounded and history-shaped.
  bg <- p$fiscal_bg_target / 100 * 4 * m[, "NY"]
  mk <- function(v) bimets::TIMESERIES(v, START = a$start, FREQ = 4)
  list(NREV_OTHER = mk(nrev_other), NGEXP_OTHER = mk(ngexp_other),
       NREV = mk(nrev), INTG = mk(intg), NSPEND = mk(nspend),
       NLEND = mk(nlend), BG = mk(bg),
       BG_GDP = mk(bg / (4 * m[, "NY"]) * 100), DEF_GDP = mk(-nlend / m[, "NY"] * 100))
}

# Seed `nm` as a constant value over NY's span.
.seed_const <- function(db, nm, value) {
  nyts <- stats::as.ts(db[["NY"]])
  tsp  <- stats::tsp(nyts)
  sy <- floor(tsp[1] + 1e-9); sq <- round((tsp[1] - sy) * 4 + 1)
  db[[nm]] <- bimets::TIMESERIES(rep(value, length(as.numeric(nyts))),
                                 START = c(sy, sq), FREQ = 4)
  db
}

# Seed `nm` as a constant share of nominal GDP over NY's span.
.seed_proportional <- function(db, nm, share) {
  nyts <- stats::as.ts(db[["NY"]])
  tsp  <- stats::tsp(nyts)
  sy <- floor(tsp[1] + 1e-9); sq <- round((tsp[1] - sy) * 4 + 1)
  db[[nm]] <- bimets::TIMESERIES(share * as.numeric(nyts), START = c(sy, sq), FREQ = 4)
  db
}

# Corporate balance sheet + leverage, computed historically. Net worth is seeded
# at a multiple of annual GDP (the model accumulates VCORP = VCORP(-1) + RET_EARN
# over the solve window from this jump-off).
.compute_corporate <- function(db, p) {
  a <- .align_db(db, c("DCORP", "NY", "GOS_CORP"))
  m <- a$mat
  lev      <- m[, "DCORP"] / (4 * m[, "NY"]) * 100
  ret_earn <- p$corp_retain_share * m[, "GOS_CORP"]
  vcorp    <- p$corp_nw_mult * 4 * m[, "NY"]
  mk <- function(v) bimets::TIMESERIES(v, START = a$start, FREQ = 4)
  list(LEV = mk(lev), RET_EARN = mk(ret_earn), VCORP = mk(vcorp),
       LEV_DE = mk(m[, "DCORP"] / vcorp * 100))
}

# Household income-account decomposition computed historically.
.compute_household_income <- function(db, p) {
  a <- .align_db(db, c("NHCOE", "NHOY", "HH_PRIMARY", "NHTAX", "NTRANSFERS"))
  m <- a$mat
  hh_nonlab <- m[, "HH_PRIMARY"] - m[, "NHCOE"]
  nhoy_resid <- m[, "NHOY"] - hh_nonlab + m[, "NHTAX"] - m[, "NTRANSFERS"]
  nhdy_recon <- m[, "HH_PRIMARY"] - m[, "NHTAX"] + m[, "NTRANSFERS"] + nhoy_resid
  mk <- function(v) bimets::TIMESERIES(v, START = a$start, FREQ = 4)
  list(HH_NONLAB = mk(hh_nonlab), NHOY_RESID = mk(nhoy_resid),
       NHDY_RECON = mk(nhdy_recon),
       HH_TAXRATE = mk(m[, "NHTAX"] / m[, "HH_PRIMARY"] * 100))
}

# GDP(I) decomposition computed historically (GOS as the residual).
.compute_income_side <- function(db, p) {
  a <- .align_db(db, c("NY", "NHCOE", "GMI", "TAX_PROD_NET"))
  m <- a$mat
  gos <- m[, "NY"] - m[, "NHCOE"] - m[, "GMI"] - m[, "TAX_PROD_NET"]
  mk <- function(v) bimets::TIMESERIES(v, START = a$start, FREQ = 4)
  list(GOS = mk(gos),
       PROFIT_SHARE = mk(gos / m[, "NY"] * 100),
       LABOUR_SHARE = mk(m[, "NHCOE"] / m[, "NY"] * 100),
       GOS_CORP = mk(p$corp_gos_share * gos))
}

# Align named db series on their common window; returns matrix + start/length.
.align_db <- function(db, names) {
  tss <- lapply(names, function(n) {
    if (is.null(db[[n]])) stop("series '", n, "' not in database", call. = FALSE)
    stats::as.ts(db[[n]])
  })
  lo <- max(vapply(tss, function(x) stats::tsp(x)[1], 0))
  hi <- min(vapply(tss, function(x) stats::tsp(x)[2], 0))
  mat <- do.call(cbind, lapply(tss, function(x)
    as.numeric(stats::window(x, start = lo, end = hi))))
  colnames(mat) <- names
  sy <- floor(lo + 1e-9); sq <- round((lo - sy) * 4 + 1)
  list(mat = mat, start = c(sy, sq))
}

# Current account + net-foreign-liability stock, computed historically so
# bimets has defined initialisation values.
.compute_external_series <- function(db, p) {
  a <- .align_db(db, c("NX", "NM", "NY", "NFOY", "NTRF"))
  m <- a$mat; n <- nrow(m)
  ntb <- m[, "NX"] - m[, "NM"]
  nca <- ntb + m[, "NFOY"] + m[, "NTRF"]
  # The stock recursion must stay finite from the first usable period; treat a
  # missing flow as zero (no accumulation) so an early NA doesn't poison the
  # whole path, and seed off the first finite GDP.
  nca_acc <- ifelse(is.finite(nca), nca, 0)
  ny1 <- m[which(is.finite(m[, "NY"]))[1], "NY"]
  seed <- if (!is.na(p$nfl_seed)) p$nfl_seed else 0
  vnfl <- numeric(n)
  vnfl[1] <- seed / 100 * (if (is.finite(m[1, "NY"])) m[1, "NY"] else ny1)
  for (t in seq_len(n)[-1]) vnfl[t] <- vnfl[t - 1] - nca_acc[t]
  mk <- function(v) bimets::TIMESERIES(v, START = a$start, FREQ = 4)
  list(NTB = mk(ntb), TB_GDP = mk(ntb / m[, "NY"] * 100),
       NCA = mk(nca), VNFL = mk(vnfl),
       NFL_GDP = mk(vnfl / m[, "NY"] * 100),
       CAD_GDP = mk(-nca / m[, "NY"] * 100),
       GNI = mk(m[, "NY"] + m[, "NFOY"]),
       GNI_GDP_WEDGE = mk(m[, "NFOY"] / m[, "NY"] * 100))
}

# Scale the effective tax-rate series so that, over the last 5 years of finite
# data, mean revenue = mean(spending + target primary deficit). A placeholder
# for true calibration against ABS GFS revenue (M1).
.calibrate_fiscal_rates <- function(db, p) {
  a <- .align_db(db, c("NY", "NHDY", "NC", "NHCOE", "NG",
                       "ETR_DIRECT", "ETR_INDIRECT", "ETR_CORP", "NTRANSFERS"))
  m <- a$mat; n <- nrow(m)
  nrev_raw <- m[, "ETR_DIRECT"] * m[, "NHDY"] +
              m[, "ETR_INDIRECT"] * m[, "NC"] +
              m[, "ETR_CORP"] * (m[, "NY"] - m[, "NHCOE"])
  nspend   <- m[, "NG"] + m[, "NTRANSFERS"]
  # Revenue covers spending plus the interest on the target debt, so at the
  # target debt the primary balance is ~0 and the (open-loop, unstable) debt
  # recursion stays near the seed over the demo window. With real transfers
  # (NTRANSFERS from ABS) `nspend` reflects actual social benefits; the
  # debt-stabilising rule (fiscal_rule, M4) is what genuinely pins the path.
  # NOTE: a history-matched deficit/debt path would need the ABS general-
  # government INCOME account reconciled with MARTIN's expenditure-side NG (the
  # income-side-of-GDP gap the review flags); out of scope here, so NGREV/NGEXP
  # are carried as reporting series rather than forced into the balance.
  ss_interest <- (p$fiscal_iirg / 100) * (p$fiscal_bg_target / 100) * m[, "NY"]
  target   <- nspend + ss_interest + p$fiscal_def_target * m[, "NY"]
  ok <- is.finite(nrev_raw) & is.finite(target) & nrev_raw > 0
  scale <- if (any(ok)) sum(target[ok]) / sum(nrev_raw[ok]) else 1
  for (nm in c("ETR_DIRECT", "ETR_INDIRECT", "ETR_CORP")) {
    ts  <- stats::as.ts(db[[nm]])
    tsp <- stats::tsp(ts)
    sy <- floor(tsp[1] + 1e-9); sq <- round((tsp[1] - sy) * 4 + 1)
    db[[nm]] <- bimets::TIMESERIES(as.numeric(ts) * scale, START = c(sy, sq), FREQ = 4)
  }
  db
}

# Government revenue/spending/debt, computed historically (recursive debt).
.compute_fiscal_series <- function(db, p) {
  a <- .align_db(db, c("NY", "NHDY", "NC", "NHCOE", "NG",
                       "ETR_DIRECT", "ETR_INDIRECT", "ETR_CORP",
                       "NTRANSFERS", "IIRG"))
  m <- a$mat; n <- nrow(m)
  nrev   <- m[, "ETR_DIRECT"] * m[, "NHDY"] +
            m[, "ETR_INDIRECT"] * m[, "NC"] +
            m[, "ETR_CORP"] * (m[, "NY"] - m[, "NHCOE"])
  nspend <- m[, "NG"] + m[, "NTRANSFERS"]
  # Seed the *history* of the debt stock at the target ratio rather than
  # accumulating the (open-loop unstable) recursion over 60 years -- otherwise
  # a tiny early imbalance compounds at the interest rate into an astronomical
  # jump-off. The model enforces BG = BG(-1) - NLEND over the solve window from
  # this sensible seed; over a short horizon the no-rule path stays bounded.
  bg   <- p$fiscal_bg_target / 100 * 4 * m[, "NY"]
  bg_lag <- c(bg[1], bg[-n])
  intg <- m[, "IIRG"] / 400 * bg_lag
  nlend <- nrev - nspend - intg
  mk <- function(v) bimets::TIMESERIES(v, START = a$start, FREQ = 4)
  list(NREV = mk(nrev), NSPEND = mk(nspend), INTG = mk(intg),
       NLEND = mk(nlend), BG = mk(bg),
       BG_GDP = mk(bg / (4 * m[, "NY"]) * 100),
       DEF_GDP = mk(-nlend / m[, "NY"] * 100))
}

# Compute the CES output-gap block historically (harmonic form, sigma=0.5) on
# the window common to its inputs, returning bimets TIMESERIES for seeding.
.compute_output_gap_series <- function(db, p) {
  need <- c("Y", "KIBN", "KIBRE", "LPOP", "LPR", "TLUR", "LHPP", "EFF")
  miss <- need[vapply(need, function(n) is.null(db[[n]]), logical(1))]
  if (length(miss))
    stop("output_gap needs series: ", paste(miss, collapse = ", "), call. = FALSE)
  tss <- lapply(need, function(n) stats::as.ts(db[[n]]))
  lo <- max(vapply(tss, function(x) stats::tsp(x)[1], 0))
  hi <- min(vapply(tss, function(x) stats::tsp(x)[2], 0))
  w  <- lapply(tss, function(x) as.numeric(stats::window(x, start = lo, end = hi)))
  names(w) <- need
  tk <- p$ces_theta_k; tn <- 1 - tk; g <- p$ces_gamma
  kstar  <- w$KIBN + w$KIBRE
  nstar  <- w$LPOP * (w$LPR / 100) * (1 - w$TLUR / 100)
  ystar  <- g / (tn / (w$EFF * w$LHPP * nstar) + tk / kstar)
  ygap   <- (log(w$Y) - log(ystar)) * 100
  lestar <- (tn / (g / w$Y - tk / kstar)) / (w$EFF * w$LHPP)
  sy <- floor(lo + 1e-9); sq <- round((lo - sy) * 4 + 1)
  mk <- function(v) bimets::TIMESERIES(v, START = c(sy, sq), FREQ = 4)
  list(KSTAR = mk(kstar), NSTAR = mk(nstar), YSTAR = mk(ystar),
       YGAP = mk(ygap), LESTAR = mk(lestar))
}

# Span (start year/quarter + length) of the longest series in the database.
.db_span <- function(database) {
  lens <- vapply(database, function(x) length(as.numeric(x)), integer(1))
  ref  <- database[[which.max(lens)]]
  tsp  <- stats::tsp(ref)
  sy   <- floor(tsp[1] + 1e-9)
  sq   <- round((tsp[1] - sy) * 4 + 1)
  list(start = c(sy, sq), n = length(as.numeric(ref)))
}
