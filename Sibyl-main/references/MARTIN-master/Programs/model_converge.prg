'Convergence Charts
smpl %nataccs_end+1 %solve_end

'GDP growth and Supply Side Growth
graph ___gap.line DLOG(Y_2)*100 (TY_POT_2)*100

'Real GDP components
graph __cvm dlog(Y_2)*100 dlog(RC_2)*100 dlog(id_2)*100 dlog(ib_2)*100 dlog(g_2)*100 dlog(otc_2)*100 dlog(x_2)*100 dlog(m_2)*100 TY_POT_2*100

'Consumption
graph __cons dlog(hdy_2)*100 dlog(hnw_2)*100 rcr_2 dlog(hcoe_2)*100 dlog(hoy_2)*100 ty_pot_2*100

'Household Wealth
graph __wealth dlog(hnw_2)*100 dlog(nha_2/pc_2)*100 dlog(nhl_2/pc_2)*100 ty_pot_2*100

'Household Assets
graph __assets dlog(nha_2/pc_2)*100 dlog(nhnfa_2/pc_2)*100 dlog(nhfa_2/pc_2)*100 ty_pot_2*100

'Hhold Liabilities
graph __liab dlog(nhl_2)*100 dlog(ph_2*kid_2)*100 (TY_POT_2*100 + PI_TARGET/4)

'Investments
graph __inv dlog(IB_2)*100 dlog(ID_2)*100 dlog(IBN_2)*100 dlog(IBRE_2)*100 dlog(KV_2)*100

'Public Demand
graph __pubd dlog(GC_2)*100 dlog(GI_2)*100 TY_POT_2*100

'Real Exports
graph __xps dlog(X_2)*100 dlog(XAG_2)*100 dlog(XM_2)*100 dlog(XO_2)*100 dlog(XRE_2)*100 dlog(XS_2)*100 TY_POT_2*100

'Prices and Wages
graph __pwage dlog(PTM_2)*100 (dlog(PAE_2)*100-TDLLA_2*100) dlog(PEX_2)*100 dlog(PMCG_2)*100  pi_target/4

'National Account Deflators
graph __priceNA dlog(PM_2)*100 dlog(PTM_2)*100 dlog(POIL_2)*100 dlog(PC_2)*100 dlog(PID_2)*100 dlog(PIBN_2)*100 dlog(PIBRE_2)*100 dlog(PIBRE_2)*100 dlog(PG_2)*100 dlog(PX_2)*100 dlog(PIB_2)*100 dlog(PDFD_2)*100 dlog(PDPFD_2)*100 dlog(PGNE_2)*100 dlog(PY_2)*100 dlog(POTC_2)*100 

'Export Deflators
graph __pricex dlog(PXRE_2)*100 dlog(PXM_2)*100 dlog(PXS_2)*100 dlog(PXO_2)*100 dlog(PXAG_2)*100 pi_target/4

'World Price Vars
graph __worldp dlog(wp_2)*100 dlog(wpx_2)*100 dlog(wpag_2)*100 dlog(wpcom_2)*100 dlog(wpoil_2)*100 pi_target/4 

'World Volume Measures
graph __worldv dlog(WY_2)*100 TY_POT_2*100

'World Interest Rates
graph __worldr (wrr_2-wrr_target) (wr2r_2-_wr2r.@coef(1))

'Exchange Rates
graph ___er dlog(rtwi_2)*100

'Import Adjusted Demand
graph __iad (dlog(iad_2)*100) (dlog(rc_2)*100) (dlog(ib_2)*100) (dlog(gi_2)*100) (dlog(gc_2)*100) (dlog(x_2)*100)

'PMCG
graph __pmcg dlog(PMCG_2)*100 dlog(pm_2)*100 dlog(poil_2)*100 dlog(poil_2)*100 pi_target/4 

'Import Price
graph __pm dlog(pm_2)*100 dlog(wpx_2)*100 dlog(ntwi_2)*100 dlog(wpoil_2)*100 dlog(poil_2)*100

'Nominal TWI
graph __ntwi dlog(ntwi_2)*100 dlog(rtwi_2)*100 dlog(wp_2)*100 dlog(ptm_2)*100


