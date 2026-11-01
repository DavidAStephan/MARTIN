'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'BUILD MODEL EQNS
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
smpl @first %eq_est_end
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'TRENDS
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------

'Trend Productivity
	MARTIN.append tlla  = tlla(-1)  + tdlla
	MARTIN.addassign(i,c) tlla
	'Trend Productivity Growth
		MARTIN.append tdlla  = 0.95  * tdlla(-1)  + ( 0.05  * aasteady_state_la )
		MARTIN.addassign(i,c) tdlla

'Trend Average Hours Worked
	MARTIN.append tllhpp  = tllhpp(-1)  + tdllhpp
	MARTIN.addassign(i,c) tllhpp
	'Trend Average Hours Worked Growth
		MARTIN.append tdllhpp  = 0.95  * tdllhpp(-1)
		MARTIN.addassign(i,c) tdllhpp

	'Log Trend Hours Worked
		MARTIN.append log(lhpp)  = tllhpp
		MARTIN.addassign(i,c) lhpp
'Trend Population
	MARTIN.append tllpop  = tllpop(-1)  + tdllpop
	MARTIN.addassign(i,c) tllpop
	
	'Trend Population Growth
		MARTIN.append tdllpop  = 0.975  * tdllpop (-1)  + ( 0.025  * aasteady_state_pop )
		MARTIN.addassign(i,c) tdllpop
'Trend Inflation Expecatations
	MARTIN.append pi_e  = 0.9  * pi_e(-1)  + 0.1  * pi_target
	MARTIN.addassign(i,c) pi_e	

'Potential Growth Rate
	MARTIN.append @identity TY_POT = TDLLA+TDLLPOP+TDLLHPP
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'HOUSEHOLD SECTOR
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------

	'Household Consumption
	smpl 1989q1 %eq_est_end
	equation _RC.LS(COV=HAC) d(log(rc))=c(1)+c(50)*dum_rc-c(11)*(log(rc(-1))-c(2)*log(hdy(-1))-(1-c(2))*log(hnw(-2)) + 0.5/100*(rcr(-1)) ) + 0.15*d(log(hcoe)) + c(31)*d(log(hoy(-2))) + c(32)*d(log(hnw(-1)))  + (1-0.15-c(31)-c(32))*(tdlla(-1) + tdllpop(-1) + tdllhpp(-1)) + c(60)*d(lur(-2))/100
	MARTIN.merge _RC
	MARTIN.addassign(i,c) RC
	'Household Non-Labor Income
	smpl 1985q1 %eq_est_end
	equation _NHOY.LS(COV=HAC) DLOG(NHOY) = C(1) + C(2)*(LOG(NHOY(-1)) - LOG(NY(-1)-NHCOE(-1))) - C(16)/100*D(NMR) + (TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1) + PI_E/400)
	MARTIN.merge _NHOY	
	MARTIN.addassign(i,c) NHOY

	'Household Other Income
	MARTIN.append @IDENTITY hoy  = nhoy  / pc
	'Nominal Household Disposable Income
	MARTIN.append @IDENTITY nhdy  = nhcoe  + nhoy	

	'Household Disposable Income
	MARTIN.append @IDENTITY hdy  = nhdy  / pc
	'Nominal Household Saving
	MARTIN.append nhs  = nhdy  - nc  - kidc
	MARTIN.addassign(i,c) NHS

	'Nominal Household Saving Ratio
	MARTIN.append @identity nhsr  = nhs  / (nhdy  - kidc)  
	'Household Assets
	MARTIN.append @IDENTITY nha  = nhnfa  + nhfa

		'Household Financial Assets
			smpl 1993q1 %eq_est_end
			equation _NHFA.LS(COV=HAC) D(LOG(NHFA))=C(1)+C(2)*(LOG(NHFA(-1))-LOG(NGNE(-1))) +C(4)*D(LOG(NGNE))+(1-C(4))* (TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1) + PI_E/400) + C(12)*@DURING("2003q3 2007q2") + C(13)*PID_TREND
			MARTIN.merge _NHFA
			MARTIN.addassign(i,c) NHFA
	
		'Household Non-Financial Assets
		MARTIN.append d(log(nhnfa))  = d(log(kid  * ph))
		MARTIN.addassign(i,c) NHNFA

	'Household Liabilities
	smpl 1993q1 %eq_est_end
	equation _NHL.LS(COV=HAC) D(LOG(NHL))=C(1)+C(10)*(LOG(NHL(-1))-C(2)*LOG(NHC(-1))-(1-c(2))*LOG(NY(-1))) + c(3)*dlog(NHL(-1)) + c(4)*dlog(NHC)+(1-c(3)-c(4))*dlog(NY) 
	MARTIN.merge _NHL
	MARTIN.addassign(i,c) NHL
	
		'Household Credit
		smpl 1993q1 %eq_est_end
		equation _NHC.LS(COV=HAC) D(LOG(NHC))=C(1)+C(10)*(LOG(NHC(-1))-LOG(PH(-1))-LOG(KID(-2))-C(6)*RMR(-1))+C(2)*D(LOG(NHC(-1)))+C(3)*D(LOG(PH(-1))) + (1 - C(2))*D(LOG(KID(-2)))+C(5)*D(NMR(-1)) + (1 - C(2) - C(3))*PI_E/400
		MARTIN.merge _NHC
		MARTIN.addassign(i,c) NHC

	'Household Net Worth
	MARTIN.append @IDENTITY nhnw  = nha  - nhl
	'Real Household Net Worth
	MARTIN.append @IDENTITY hnw  = nhnw  / pc

	'Wage Share of Income
	MARTIN.append @identity nhws = nhcoe/ny
	
	'Consumption of Fixed Capital
	MARTIN.append d(log(kidc))  = 0.95  * d(log(kidc(-1)))  + (1  - 0.95)  * (tdlla(-1)  + tdllpop(-1)  + tdllhpp(-1)  + pi_e  / 400)
	MARTIN.addassign(i,c) KIDC	

'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'HOUSING SECTOR
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
	'Dwelling Investment
	smpl 1985q2 %eq_est_end
	equation _ID.LS(COV=HAC) D(LOG(ID))=C(1) + C(2)*(LOG(ID(-1))-LOG(RC(-1)) + 0.3*(NMR(-1)-PI_E(-1))/100 + LOG(PID(-1)/PC(-1))) + C(3)*D_GSTDEC+C(4)*D_GSTSEP+C(5)*D_GSTJUN+C(6)*D_GSTMAR + C(7)/3*(LOG(RPH(-1)/RPH(-4))) + C(8)/400*(NMR(-1)-NMR(-5)) + TDLLPOP(-1) + TDLLHPP(-1) + TDLLA(-1)
	MARTIN.merge _ID
	MARTIN.addassign(i,c) ID

	'Housing Prices
	smpl 1988q3 %eq_est_end
	equation _PH.LS(COV=HAC) DLOG(PH) = C(1) + C(2)*(LOG(PH(-1)) - LOG(PRT(-1)) - C(3)*RMR(-1)) + C(4)*DLOG(PH(-1)) - 0.003*D(NMR(-1)) + (1 - C(4))*PI_E/400
	MARTIN.merge _PH
	MARTIN.addassign(i,c) PH
	'Consumer Price Index - Rents
	smpl 1993q1 %eq_est_end
	equation _PRT.LS(COV=HAC) DLOG(PRT) = C(1) + C(2)*(LOG(PRT(-1)/PC(-1)) - LOG(HCOE(-4)/KID(-5))) + C(3)*DLOG(PRT(-1))  + (1 - C(3) )*PI_E/400 + C(5)/2*LOG(HCOE(-1)/HCOE(-3)) - C(5)*(TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1))
	MARTIN.merge _PRT	
	MARTIN.addassign(i,c) PRT

	'Ownership Transfer Costs
	smpl 1983q1 %eq_est_end
	equation _OTC.LS(COV=HAC) DLOG(OTC) = C(1) + C(2)*(LOG(OTC(-1)) - LOG(ID(-1)) + C(3)*(LOG(POTC(-1)/PID(-1))) ) + C(4) * D(NMR(-1))/400 + C(5) * (DLOG(PH)*100 - PI_TARGET/4) + C(6) * D_GSTSEP + (TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1))
	MARTIN.merge _OTC
	MARTIN.addassign(i,c) OTC
	'Real Housing Prices
	MARTIN.append @identity @IDENTITY rph  = ph  / ptm

	'Dwelling Stock Depreciation Rate
	MARTIN.append iddr  = iddr(-1)
	MARTIN.addassign(i,c) IDDR
	'Dwelling Stock
	MARTIN.append kid  = (1  - iddr  / 100)  * kid(-1)  + id	
	MARTIN.addassign(i,c) KID

'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'BUSINESS INVESTMENT
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
	'Non-mining Investment
	smpl 1979q4 %eq_est_end
	equation _IBN.LS(COV=HAC) d(log(ibn)) = c(1)+c(2)*(log(ibn(-1))-log(gne(-1))+0.4*log((ibcr(-1)*pgne(-1)/pibn(-1))) + log(pibn(-1)/pgne(-1)) - log(tdlla(-1) + tdllpop(-1) + tdllhpp(-1) + ibndr(-1)/100) - c(3)*log(nibre(-1)/ny(-1))  ) + 1/2*log(gne(-1)/gne(-3)) + (1 - 1)*(tdlla(-1) +tdllpop(-1) + tdllhpp(-1) ) +c(8)*d_oly
	MARTIN.merge _IBN
	MARTIN.addassign(i,c) IBN
	
	'Mining Investment
	smpl 1986q3 %eq_est_end
	equation _IBRE.LS(COV=HAC) D(LOG(IBRE)) = C(1) - C(2)*(LOG(IBRE(-1)) - LOG(Y(-1)) - C(3)*(LOG(PXRE(-1)) - LOG(PGNE(-1)))  + (LOG(PIBRE(-1)) - LOG(PGNE(-1))) - LOG((TDLLA(-1) +TDLLPOP(-1) + TDLLHPP(-1) + IBREDR(-1)/100)) ) + C(4)/4*(LOG(PXRE)-LOG(PXRE(-4)) - LOG(PGNE)+LOG(PGNE(-4)))  + C(5)/2*LOG(IBRE(-1)/IBRE(-3)) + (1 - C(5))*(TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1) )  + C(91)*D_IBRE_1 + C(92)*D_IBRE_2 + C(93)*D_IBRE_3 + C(94)*D_IBRE_4 + C(95)*D_IBRE_5
	MARTIN.merge _IBRE
	MARTIN.addassign(i,c) IBRE
	'Private Business Investment
	MARTIN.append @IDENTITY ib  = ibre  + ibn

	'Cost of Capital
	MARTIN.append @IDENTITY ibcr  = @recode((rbr/100+ibndra/100)*((1-ibctr*(ibndra/100*(1+n10r/100)/(n10r/100+ibndra/100)))/(1-ibctr))*(pibn/pgne)>0.01,(rbr/100+ibndra/100)*((1-ibctr*(ibndra/100*(1+n10r/100)/(n10r/100+ibndra/100)))/(1-ibctr))*(pibn/pgne),0.01)
	'Corporate Tax Rate
	MARTIN.append ibctr  = ibctr(-1)
	MARTIN.addassign(i,c) IBCTR

	'Non-mining capital stock
	MARTIN.append kibn  = (1  - ibndr  / 100)  * kibn(-1)  + ibn
	MARTIN.addassign(i,c) KIBN
	'Non-Mining Depreciation Rate
	MARTIN.append ibndr  = ibndr(-1)
	MARTIN.addassign(i,c) IBNDR
		'Annual
		MARTIN.append @IDENTITY ibndra  = ibndr  + ibndr(-1)  + ibndr(-2)  + ibndr(-3)
	
	'Mining Capital Stock
	MARTIN.append kibre  = (1  - ibredr  / 100)  * kibre(-1)  + ibre
	MARTIN.addassign(i,c) KIBRE

	'Mining Depreciation Rate
	MARTIN.append ibredr  = ibredr(-1)
	MARTIN.addassign(i,c) IBREDR
	'Inventories
	smpl 1959q3 %eq_est_end
	equation _KV.LS(COV=HAC) D(LOG(KV))=C(1)-C(2)*(LOG(KV(-1))-LOG(Y(-1)))+C(3)*D(LOG(KV(-1)))+(1 - C(3))*(TDLLA + TDLLHPP + TDLLPOP) + C(15)*PC_TREND
	MARTIN.merge _KV
	MARTIN.addassign(i,c) KV

		'Change in inventories
		MARTIN.append V = d(KV)
		MARTIN.addassign(i,c) V
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'PUBLIC SECTOR
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------

	'Public Investment
	smpl 1986q1 %eq_est_end
	equation _GI.LS(COV=HAC) D(LOG(GI))= C(1)+C(2)*(LOG(GI(-1))-LOG(Y(-1)/(1-2*LURGAP(-1)/100)))+C(3)*D(LOG(GI(-1))) + (1-C(3))*(TDLLA + TDLLHPP + TDLLPOP)
	MARTIN.merge _GI
	MARTIN.addassign(i,c) GI
	'Public Consumption
	smpl 1985q3 %eq_est_end
	equation _GC.LS(COV=HAC) D(LOG(GC))= C(1)+C(2)*(LOG(GC(-1))-LOG(Y(-1)/(1-2*LURGAP(-1)/100)))+C(3)*D(LOG(GC(-1))) + (1-C(3))*(TDLLA + TDLLHPP + TDLLPOP)
	MARTIN.merge _GC
	MARTIN.addassign(i,c) GC

	'Public Demand
	MARTIN.append g  = gi  + gc
	MARTIN.addassign(i,c) G
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'FOREIGN TRADE
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------

	'Mining Exports
	smpl 1959q3 %eq_est_end
	equation _XRE.LS(COV=HAC) D(LOG(XRE)) =  c(10) + C(2)*(LOG(XRE(-1)) - LOG(KIBRE(-6))) + C(3)*D(LOG(XRE(-1))) + C(4)*D_RBAGOLD + (1 - C(3))*(TDLLPOP(-1) + TDLLHPP(-1) + TDLLA(-1)) 
	MARTIN.merge _XRE
	MARTIN.addassign(i,c) XRE
	'Manufactured Exports
	smpl 1986q2 %eq_est_end
	equation _XM.LS(COV=HAC) D(LOG(XM)) = c(10) + C(2)*(LOG(XM(-1)) -LOG(WY(-1)) + c(3)*LOG(REWI(-1)))+C(4)*D(LOG(WY(-1)))+C(5)*D(LOG(WY(-2)))+(1-C(4)-C(5))*(TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1)) + c(10) + c(11)*xs_trend
	MARTIN.merge _XM
	MARTIN.addassign(i,c) XM
	
	'Service Exports
	smpl 1988q1 %eq_est_end
	equation _XS.LS(COV=HAC) D(LOG(XS)) = C(1)*(LOG(XS(-1))-LOG(WY(-1)) + C(3)*LOG(REWI(-1)))+C(3)*D_OLYX+C(4)/4*(LOG(WY)-LOG(WY(-4)))+C(5)*D(LOG(REWI))+ (1 - C(4))*(TDLLPOP(-1) + TDLLHPP(-1) + TDLLA(-1)) + C(10)+ C(11)*XS_TREND
	MARTIN.merge _XS
	MARTIN.addassign(i,c) XS
	'Agricultural Exports
	smpl 1985q3 %eq_est_end
	equation _XAG.LS(COV=HAC) D(LOG(XAG-RAIN)) = C(1)+C(2)*(LOG(XAG(-1)-RAIN(-1))-LOG(WY(-1))+c(3)*LOG(REWI(-1)))+C(4)*D(LOG(XAG(-4)-RAIN(-4)))+ (1-C(4))*(TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1)) + c(11)*pc_trend
	MARTIN.merge _XAG
	MARTIN.addassign(i,c) XAG

	'Other Exports
	smpl 1986q2 %eq_est_end
	equation _XO.LS(COV=HAC) D(LOG(XO)) = C(1)+C(2)*(LOG(XO(-1))-LOG(WY(-1))-C(3)*LOG(REWI(-1)))+C(4)/2*(LOG(XO(-1)/XO(-3)))+(1-C(4))*(TDLLA(-1) + TDLLPOP(-1) + TDLLHPP(-1)) + c(11)*xs_trend
	MARTIN.merge _XO
	MARTIN.addassign(i,c) XO
	'Export Volumes
	MARTIN.append @IDENTITY x  = xm  + xag  + xo  + xre  + xs

	'Imports
	smpl 1986q2 %eq_est_end
	equation _M.LS(COV=HAC) D(LOG(M)) = C(1)+C(2)*(LOG(M(-1))-LOG(IAD(-1))-C(3)*1/4*(LOG(PM(-1)/PDFD(-1))+LOG(PM(-2)/PDFD(-2))+LOG(PM(-3)/PDFD(-3))+LOG(PM(-4)/PDFD(-4))))+C(4)*D(LOG(IAD))+C(5)*D(LOG(IAD(-1)))+C(6)*D(LOG(IAD(-2))) +(1- (C(4) + C(5) + C(6) ))*(TDLLPOP(-1) + TDLLHPP(-1) + TDLLA(-1))-C(7)*D(LOG(PM(-1)/PDFD(-1))) + c(11)*pc_trend
	MARTIN.merge _M
	MARTIN.addassign(i,c) M	
		'Import-Adjusted Demand
		MARTIN.append iad  = rc^iad_w_c  * ib^iad_w_i  * gi^iad_w_gi  * gc^iad_w_gc  * x^iad_w_x
		MARTIN.addassign(i,c) IAD	
			'Deflator
			MARTIN.append @IDENTITY piad  = pc^iad_w_c  * pib^iad_w_i  * pg^iad_w_gi  * pg^iad_w_gc  * px^iad_w_x
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'National Accounts Aggregates
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------

	'Second Hand Asset Sales
	MARTIN.append ATS = ATS(-1)
	MARTIN.addassign(i,c) ATS
	'Domestic Final Demand
	MARTIN.append dfd  = rc  + id  + ib  + g  + otc  - ats
	MARTIN.addassign(i,c) DFD

	'Domestic Final Demand incl. Exports	
	MARTIN.append @IDENTITY dfdx  = dfd + x
	'Domestic Final Private Demand
	MARTIN.append @identity dpfd  = rc  + id  + ib  + otc  - ats

	'Gross National Expenditure
	MARTIN.append gne  = dfd  + v	
	MARTIN.addassign(i,c) GNE
	'Gross Domestic Product
	MARTIN.append @IDENTITY y = rc  + id  + ib  + g  + otc  - ats + v + x - m + sd
		'Statistical Discrepancy
		MARTIN.append sd=sd(-1)
		MARTIN.addassign(i,c) sd
	'Nominal Household Consumption
	MARTIN.append @IDENTITY nc  = pc  * rc  / 100
	
	'Nominal Dwelling Investment
	MARTIN.append @IDENTITY nid  = pid  * id  / 100
	'Nominal Ownership Costs
	MARTIN.append @IDENTITY notc  = potc  * otc  / 100
	
	'Nominal Private Investment
	MARTIN.append @IDENTITY nib  = nibn  + nibre
	'Nominal Private Business Investment
	MARTIN.append @IDENTITY nibn  = pibn  * ibn  / 100
	
	'Nominal Mining Investment
	MARTIN.append @IDENTITY nibre  = pibre  * ibre  / 100
	
	'Nominal Public Demand
	MARTIN.append @IDENTITY ng  = pg  * g  / 100

	'Nominal Change in Inventories
	MARTIN.append nv  = pg  * v  / 100
	MARTIN.addassign(i,c) NV
	'Nominal Resource Exports
	MARTIN.append @IDENTITY nxre  = pxre  * xre  / 100

	'Nominal Manufacturing Exports
	MARTIN.append @IDENTITY nxm  = pxm  * xm  / 100
	'Nominal Services Exports
	MARTIN.append @IDENTITY nxs  = pxs  * xs  / 100

	'Nominal Other Exports
	MARTIN.append @IDENTITY nxo  = pxo  * xo  / 100
	'Nominal Agricultural Exports
	MARTIN.append @IDENTITY nxag  = pxag  * xag  / 100

	'Nominal Exports
	MARTIN.append @IDENTITY nx  = nxm  + nxs  + nxo  + nxre  + nxag
	'Nominal Imports
	MARTIN.append @IDENTITY nm  = pm  * m  / 100
	
	'Nominal second-hand asset sales
	MARTIN.append nats = nats(-1)
	MARTIN.addassign(i,c) nats
	'Nominal Domestic Final Demand
	MARTIN.append ndfd  = nc  + nid  + nib  + ng  + notc  - nats
	MARTIN.addassign(i,c) NDFD

	'Nominal Domestic Private Final Demand
	MARTIN.append @IDENTITY ndpfd  = nc  + nid  + nib  + notc  - nats
	'Nominal Gross National Expenditure
	MARTIN.append ngne  = ndfd  + nv
	MARTIN.addassign(i,c) NGNE

	'Nominal Statistical Discrepancy
	MARTIN.append nsd  = nsd(-1)
	MARTIN.addassign(i,c) NSD
	'Nominal GDP
	MARTIN.append @IDENTITY ny  = nc  + nid  + nib  + ng  + notc  + nv  + nx  - nm  - nats  + nsd

'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'PRICES AND WAGES
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
	'Wage Price Index	
	smpl 1998q1 %eq_est_end
	equation _PW.LS(COV=HAC) D(LOG(PW)) = C(1)*(TDLLA*(C(4)+C(5))) + C(2)*(LURGAP(-1)/LUR(-1)) + C(3)*D(LUR(-1)) + C(4)*PI_E/400  + C(5)*( LOG(PY(-1))-LOG(PY(-9)) )/8 + (1-C(4)-C(5))*D(LOG(PW(-1)))
	MARTIN.merge _PW
	MARTIN.addassign(i,c) PW

	'Average Earnings National Accounts
	smpl 1997q4 %eq_est_end
	equation _PAE.LS(COV=HAC) D(LOG(PAE)) = TDLLA + PI_E/400 + C(2)*(D(LOG(PW)) - _PW.@COEF(1)*TDLLA - PI_E/400)
	MARTIN.merge _PAE
	MARTIN.addassign(i,c) PAE
	'Nominal household compensation of employees
	MARTIN.append @IDENTITY d(log(nhcoe))  = d(log(pae))  + d(log(le))  + d(log(lhpp))

	'Compensation of Employees
	MARTIN.append @IDENTITY hcoe  = nhcoe  / pc
	'Nominal Unit Labor Cost
	MARTIN.append @IDENTITY d(log(nulc))  = d(log(nhcoe))  - d(log(y))

	'Nominal unit labour cost - Balassa Samuelson adj.
	MARTIN.append nulcbs  = nulc  / nulc(-1)  * nulcbs(-1)
	MARTIN.addassign(i,c) NULCBS
	'Real Labor Cost
	MARTIN.append @IDENTITY rlc  = pae  / pgne

	'Real unit labour cost
	MARTIN.append @IDENTITY rulc  = nulc  / pgne
	'Real Unit Labor Costs (GDP Deflated)
	MARTIN.append @identity rulcy = nulc/py
	
	'Import Price
	smpl 1984q1 %eq_est_end
	equation _PM.LS D(LOG(PM)) = C(1) + C(2)*(LOG(PM(-1)) - C(3)*LOG(WPX(-1)) + LOG(NTWI(-1)) - (1-C(3))*LOG(WPOIL(-1)) - C(4)*TADP ) + C(5)*D(LOG(PM(-1))) + C(6)*D(LOG(NTWI)) + C(7)*D(LOG(NTWI(-1))) + C(8)*D(LOG(WPX)) + C(9)*D(LOG(WPX(-1))) + C(10)*D(LOG(POIL)) + (1 - C(5) - C(8) - C(9) - C(10))*D(LOG(POIL(-1))) + C(12)*D_AFC1 + C(13)*D_AFC2 + C(14)*D_AFC3 + C(15)*D_AFC4 + C(16)*D_AFC5
	MARTIN.merge _PM
	MARTIN.addassign(i,c) PM

	'Consumer good import price
	smpl 1984q1 %eq_est_end
	equation _PMCG.LS(COV=HAC) D(LOG(PMCG)) = C(2)*D(LOG(PM)) + (1-C(2)-C(3)-C(4))*D(LOG(PMCG(-1))) + C(3)*D(LOG(POIL)) + C(4)*D(LOG(POIL(-1))) + C(5)*D_CPMCG
	MARTIN.merge _PMCG
	MARTIN.addassign(i,c) PMCG

	'Trimmed Mean Inflation
	smpl 1993q1 %eq_est_end
	equation _PTM.LS(COV=HAC) D(LOG(PTM)) = C(1) + C(2) * (LOG(PEX(-1)) - C(3)*LOG(NULCBS(-1)) - (1 - C(3)) * LOG(PMCG(-1)) ) +  C(4)*D(LOG(PTM(-1))) + (1-C(4))*PI_E(-1)/400 + C(7)*LURGAP
	MARTIN.merge _PTM
	MARTIN.addassign(i,c) PTM
	'Consumer Price Index
	smpl 1987q1 %eq_est_end
	equation _P.LS(COV=HAC) D(LOG(P)) = (1-C(3)-C(4))*D(LOG(PTM)) + C(3)*D(LOG(POIL)) + C(4)*D(LOG(POIL(-1)))
	MARTIN.merge _P
	MARTIN.addassign(i,c) P

	'Consumer Price Index excl volatile items
	MARTIN.append pex  = pex(-1)  * (ptm  / ptm(-1))
	MARTIN.addassign(i,c) PEX
	'Domestic Oil Price
	MARTIN.append @IDENTITY poil  = wpoil  / nusd

	'Household Consumption Deflator
	smpl 1982q1 %eq_est_end
	equation _PC.LS(COV=HAC) D(LOG(PC))=C(1)+C(99)*(LOG(PC(-1)) -LOG(PTM(-1))-(1-1)*LOG(PM(-1))- C(3)*PC_TREND/100)+C(31)*D(LOG(PTM))+(1-C(31))*D(LOG(PM)) + C(33)*D_GSTSEP
	MARTIN.merge _PC
	MARTIN.addassign(i,c) PC
	'Dwelling Investment Deflator
	smpl 1985q1 %eq_est_end
	equation _PID.LS D(LOG(PID))=C(1)+C(99)*(LOG(PID(-1))-C(2)*LOG(PC(-1))-(1-C(2))*LOG(PM(-1))-C(44)*PID_TREND/100)+C(21)*D(LOG(PID(-1)))+(1-C(21))*PI_E/400 + C(22)*D_GSTSEP + C(23)*D_GSTDEC
	MARTIN.merge _PID
	MARTIN.addassign(i,c) PID

	'Non-mining business investment deflator
	smpl 1986q1 %eq_est_end
	equation _PIBN.LS(COV=HAC) D(LOG(PIBN))=C(1)+C(99)*(LOG(PIBN(-1))-1*LOG(PC(-1))+(1-1)*LOG(PM(-1))- C(3)*PIBN_TREND_1 - C(4)*PIBN_TREND_2)+C(21)*D(LOG(PIBN(-1)))+C(22)*D(LOG(PIBN(-2)))+(1-C(21)-C(22))*D(LOG(PM))+C(23)*D_GSTSEP
	MARTIN.merge _PIBN
	MARTIN.addassign(i,c) PIBN
	'Mining Investment Deflator
	smpl 1990q1 %eq_est_end
	equation _PIBRE.LS(COV=HAC) D(LOG(PIBRE)) = C(1) + C(99)*( LOG(PIBRE(-1)) - LOG(PC(-1)) -(1-1)*LOG(PM(-1)) ) + C(31)*D(LOG(PC)) + (1 - C(31) )*D(LOG(PIBRE(-1))) + C(51)*PIBRE_DUM1 + C(52)*PIBRE_DUM2 + C(53)*PIBRE_DUM3+ C(54)*PIBRE_DUM4
	MARTIN.merge _PIBRE
	MARTIN.addassign(i,c) PIBRE

	'Public Demand Deflator
	smpl 1986q1 %eq_est_end
	equation _PG.LS(COV=HAC) D(LOG(PG))=C(1)+C(99)*( LOG(PG(-1))- 1*LOG(PC(-1))-(1-1)*LOG(PM(-1)))+C(21)*D(LOG(PG(-1)))+(1-C(21))*D(LOG(PC))
	MARTIN.merge _PG
	MARTIN.addassign(i,c) PG
	'Export Deflator
	MARTIN.append @IDENTITY px  = nx  * 100  / x

	'Private business investment deflator
	MARTIN.append @IDENTITY pib  = nib  * 100  / ib
	'Domestic Final demand deflator
	MARTIN.append @IDENTITY pdfd  = ndfd  * 100  / dfd

	'Domestic Private Final Demand Deflator
	MARTIN.append @IDENTITY pdpfd  = ndpfd  * 100  / dpfd
	'Gross National Expenditure
	MARTIN.append @IDENTITY pgne  = ngne  * 100  / gne

	'Gross Domestic Product Deflator
	MARTIN.append @IDENTITY py  = ny  * 100  / y

	'Resource Export Deflator
	smpl 1985q1 %eq_est_end
	equation _PXRE.LS(COV=HAC) D(LOG(PXRE))=C(1)+C(99)* (LOG(PXRE(-1))- LOG(WPCOM(-1))+LOG(NUSD(-1))) +C(31)*D(LOG(NUSD))+C(41)*D(LOG(WPCOM)) + (1 - C(41))*PI_E(-1)/400
	MARTIN.merge _PXRE
	MARTIN.addassign(i,c) PXRE

	'Manufactured exports deflator
	smpl 1985q1 %eq_est_end
	equation _PXM.LS(COV=HAC) D(LOG(PXM))=C(1)+C(99)*(LOG(PXM(-1))-LOG(PM(-1))- C(3)*PXM_TREND/100)+C(4)*D(LOG(PM))+(1-C(4))*PI_E(-1)/400
	MARTIN.merge _PXM
	MARTIN.addassign(i,c) PXM

	'Exports Services Deflator
	smpl 1985q1 %eq_est_end
	equation _PXS.LS(COV=HAC) D(LOG(PXS))=C(1)+C(99)*( LOG(PXS(-1))-1*LOG(PC(-1))-(1-1)*LOG(PM(-1))- C(3)*PXS_TREND_1/100- C(4)*PXS_TREND_2/100)+C(31)*D(LOG(PC))+(1 - C(31))*D(LOG(PXS(-1)))
	MARTIN.merge _PXS
	MARTIN.addassign(i,c) PXS

	'Exports Other Deflator
	smpl 1990q1 %eq_est_end
	equation _PXO.LS(COV=HAC) D(LOG(PXO))=C(1)+C(99)*(LOG(PXO(-1)) -C(2)*LOG(PC(-1))-(1-C(2))*(LOG(WPCOM(-1))-LOG(NUSD(-1)))) + C(3)*D(LOG(PC)) + (1-C(3))*(DLOG(WPCOM)-DLOG(NUSD))
	MARTIN.merge _PXO
	MARTIN.addassign(i,c) PXO

	'Exports Agricultural Deflator
	smpl 1985q2 %eq_est_end
	equation _PXAG.LS(COV=HAC) D(LOG(PXAG))=C(1)+C(99)*(LOG(PXAG(-1))- 1*LOG(WPAG(-1))+1*LOG(NUSD) )+C(31)*D(LOG(NUSD))+C(41)*D(LOG(WPAG)) + C(42)*D(LOG(WPAG(-1))) + (1 - C(41) - C(42))*PI_E(-1)/400
	MARTIN.merge _PXAG
	MARTIN.addassign(i,c) PXAG

	'Ownership transfer costs deflator
	smpl 1992q1 %eq_est_end
	equation _POTC.LS(COV=HAC) D(LOG(POTC))=C(1)+C(99)*( LOG(POTC(-1))- 1*LOG(PC(-1))-(1-1)*LOG(PM(-1)) +C(3)*POTC_TREND_1/100 + C(4)*POTC_TREND_2/100) + PI_E(-1)/400
	MARTIN.merge _POTC
	MARTIN.addassign(i,c) POTC
	'Terms of Trade
	MARTIN.append @IDENTITY tot  = px  / pm  * 100

'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'LABOR MARKET
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
	'Employment
	smpl 1980q1 %eq_est_end
	equation _LE.TSLS(COV=HAC) DLOG(LE) = C(1) + C(20)*(LOG(LE(-1)) - LOG(Y(-1))+0.4*(LOG(RLC(-1)) - TLLA(-1)) + TLLA(-1) + TLLHPP(-1) ) + C(31)*D(LOG(LE(-1))) + C(40)*(D(LOG(Y(-1)))) - C(40)*(TDLLA(-1)+TDLLPOP(-1)+TDLLHPP(-1))+(1-C(31))*(TDLLPOP(-1)) + C(50)*(D(LOG(RLC)) - TDLLA(-1)) + C(39)*(DLOG(Y) - TDLLA(-1) - TDLLPOP(-1) - TDLLHPP(-1)) + C(6)*D_LE  @  LOG(LE(-1)) LOG(Y(-1)) LOG(RLC(-1)) TLLA(-1) TLLHPP(-1) DLOG(LE(-1)) DLOG(Y(-1)) TDLLA(-1) TDLLPOP(-1) TDLLHPP(-1) DLOG(RLC(-1)) D(LUR(-1)) D(LUR(-2)) DLOG(LE(-2)) DLOG(RLC(-2)) D_LE
	MARTIN.merge _LE
	MARTIN.addassign(i,c) LE

	'Unemployment Rate
	smpl 1964q1 %eq_est_end
	equation _LUR.LS(COV=HAC) D(LUR) = LOKLAG*D(LUR(-1)) + C(2)*( ((LOG(Y)-LOG(Y(-2)))/2) - TY ) + C(3)*( (LOG(RULC(-2))-LOG(RULC(-4)))/2 ) - LUR_DUM*0.025*(LUR(-1)-TLUR(-1))
	MARTIN.merge _LUR
	MARTIN.addassign LUR
		'Time-varying constant
		MARTIN.append loklag  = loklag(-1)
		MARTIN.addassign(i,c) loklag

		'Growth Rate of output that keeps unemployment rate constant
		MARTIN.append ty  = tdlla  + tdllpop  + tdllhpp  + 0.95  * (ty(-1)  - tdlla(-1)  - tdllhpp(-1)  - tdllpop(-1) )
		MARTIN.addassign(i,c) ty
	'NAIRU
	MARTIN.append tlur  = tlur(-1)
	MARTIN.addassign(i,c) TLUR

		'Unemployment Rate Gap
		MARTIN.append @IDENTITY lurgap  = lur  - tlur
	'Labor Force
	MARTIN.append @IDENTITY lf  = le  / (1  - (lur  / 100))

	'Labor Force Participation Rate
	MARTIN.append lpr  = lf  / lpop  * 100
	MARTIN.addassign(i,c) LPR

	'Working Age Population
	MARTIN.append d(log(lpop))  = tdllpop  - 0.005  * (log(lpop(-1))  - tllpop(-1))
	MARTIN.addassign(i,c) LPOP
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'Interest and Exchange Rates
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'Nominal Cash Rate
	MARTIN.append ncr  = @recode(0.7  * ncr(-1)  + 0.3  * ( rstar  + (ptm  / ptm(-4)  * 100  - 100)  + (tr_ptm  - 1)  * (ptm  / ptm(-4)  * 100  - 100  - pi_target)  - tr_lurgap  * lurgap)  - tr_dlur  / 2  * (lur  - lur(-2))>0.1,0.7  * ncr(-1)  + 0.3  * ( rstar  + (ptm  / ptm(-4)  * 100  - 100)  + (tr_ptm  - 1)  * (ptm  / ptm(-4)  * 100  - 100  - pi_target)  - tr_lurgap  * lurgap)  - tr_dlur  / 2  * (lur  - lur(-2)),0.1)
	MARTIN.addassign(i,c) ncr

'Real Cash Rate
	MARTIN.append @identity rcr  = ((1  + ncr  / 100)  / (1  + ptm  / ptm(-4)  - 1))  * 100  - 100
'Nominal 2year Bond Yield
	smpl 1993q1 %eq_est_end
'	equation _N2R.LS N2R= (1-C(1))*(C(2)+ RSTAR+PI_E+0.52*(NCR-RSTAR-PI_E))+C(1)*N2R(-1)
	MARTIN.append n2r = @recode(n2r(-1)+d(ncr)>0.01,n2r(-1)+d(ncr),0.01)
	MARTIN.addassign(i,c) N2R

'Real 2year Bond Yield
	MARTIN.append @IDENTITY r2r  = ((1  + n2r  / 100)  / (1  + ptm  / ptm(-4)  - 1))  * 100  - 100
'Nominal 10year Bond Yield
	smpl 1993q1 %eq_est_end
'	equation _N10R.LS(COV=HAC) N10R = C(1)*N10R(-1)+(1-C(1))*(C(2)+RSTAR+PI_E+0.25*(NCR-PI_E-RSTAR))
	MARTIN.append n10r = @recode(n10r(-1)+d(ncr)>0.01,n10r(-1)+d(ncr),0.01)
	MARTIN.addassign(i,c) N10R

'Nominal Business Rate
	MARTIN.append @IDENTITY nbr  = ncr  + nbrsp
'Nominal Business Rate Spread
	smpl 1993q1 %eq_est_end
	equation _NBRSP.LS(COV=HAC) NBRSP = C(1) + C(2)*NBRSP(-1) + C(3)*LURGAP
	MARTIN.merge _NBRSP
	MARTIN.addassign(i,c) NBRSP

'Real Business Rate
	MARTIN.append @IDENTITY rbr  = (1  + (1  - ibctr)  * nbr  / 100)  / (ptm(-1)  / ptm(-5))  * 100  - 100
'Mortgage Rate Spread
	smpl 1998q1 %eq_est_end
	equation _NSP.LS(COV=WHITE) NSP = (1-C(3))*(C(1) + C(2)*D_NSP) + C(3)*NSP(-1)
	MARTIN.merge _NSP
	MARTIN.addassign(i,c) NSP

'Mortgage Rate
	MARTIN.append @IDENTITY nmr  = ncr  + nsp
'Real Mortgage Rate
	MARTIN.append @IDENTITY rmr  = ( (1  + nmr  / 100)  / (ptm  / ptm(-4))  - 1 )  * 100
	'ex-ante
	MARTIN.append @IDENTITY rmre  = nmr  - pi_e
'Neutral Interest Rate
	MARTIN.append rstar  = 0.95  * rstar(-1)  + 0.05  * rcr_target
	MARTIN.addassign(i,c) rstar

'Real Trade Weighted Index
	smpl 1990q1 %eq_est_end
	equation _RTWI.LS DLOG(RTWI) = C(1) -C(2)*(LOG(RTWI(-1)) - C(3)*LOG(TOT(-1)) + 3.5/100*(WR2SP(-1)-WR2R_GAP_AVG)) + C(20)*DLOG(TOT) -5/100*D(WR2SP)
	smpl @all
	series rtwi_const = _rtwi.@coef(1)
	smpl @first %eq_est_end
	'RWTI Constant 
	MARTIN.append rtwi_const  = rtwi_const(-1)  + (0.0005  * (rcr(-1)  - rcr_target))*rtwi_const_dum
	MARTIN.addassign(i,c) rtwi_const
	
	'Real TWI Equation for the Model
	MARTIN.append dlog(rtwi)  = rtwi_const  - _rtwi.@coef(2)  * (log(rtwi(-1))  - _rtwi.@coef(3)  * log(tot(-1))  + 3.5  / 100  * (wr2sp(-1)  - wr2r_gap_avg))  + _rtwi.@coef(4)  * d(log(tot))  - 5  / 100  * d(wr2sp)
	MARTIN.addassign(i,c) RTWI
'Nominal Trade Weighted Index
	MARTIN.append d(log(ntwi))  = d(log(rtwi))  + d(log(wp))  - d(log(ptm))
	MARTIN.addassign(i,c) NTWI

'Nominal AUD/USD Rate
	MARTIN.append d(log(nusd))  = d(log(ntwi))
	MARTIN.addassign(i,c) NUSD
'Real Export Weighted Index
	MARTIN.append rewi  = rewi(-1)  * rtwi  / rtwi(-1)
	MARTIN.addassign(i,c) REWI

'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
'WORLD
'------------------------------------------------------------------------------------------------------------------------------------------------------
'------------------------------------------------------------------------------------------------------------------------------------------------------
	'Major Trading Partner Growth
	smpl 1980q1 %eq_est_end
	MARTIN.append d(log(wy))  = aasteady_state_pop  + aasteady_state_la  + 0.9  * (d(log(wy(-1)))  - (aasteady_state_pop  + aasteady_state_la))
	MARTIN.addassign(i,c) WY

	'Major Trading Partner CPI
	MARTIN.append d(log(wp))  = 0.9  * d(log(wp(-1)))  + 0.1  * pi_target  / 400
	MARTIN.addassign(i,c) WP
	'World Export Price	
	c=-0.1
	smpl 1985q1 %eq_est_end
	equation _WPX.LS(COV=HAC) D(LOG(WPX)) = C(1) + C(2)*(LOG(WPX(-1)/WP(-1)) -C(90)*WPX_TREND_1 - C(91)*WPX_TREND_2) + C(3)*DLOG(WPX(-1)) + (1 - C(3))*DLOG(WP) + C(4)*D_2008Q4
	MARTIN.merge _WPX
	MARTIN.addassign(i,c) WPX

	'World Agricultural Price
	smpl 1985q1 %eq_est_end
	equation _WPAG.LS(COV=HAC) D(LOG(WPAG)) = C(1)+ C(2)*(LOG(WPAG(-1))-LOG(WP(-1)))+C(3)*D(LOG(WPAG(-1)))+(1-C(3))*PI_E/400
	MARTIN.merge _WPAG
	MARTIN.addassign(i,c) WPAG
	'World Commodity Price
	smpl 1982q1 %eq_est_end
	MARTIN.append log(wpcom)  = log(wpcom(-1))  + 0.2  * log(wpcom(-1)  / wpcom(-5))  / 4  + 0.8  * pi_target  / 400  - 0.05  * ( log(wpcom(-1))  - log(wp(-1))  - log(rwpcom_lr))
	MARTIN.addassign(i,c) WPCOM

	'World Oil Price
	smpl 1985q1 %eq_est_end
	equation _WPOIL.LS(COV=HAC) D(LOG(WPOIL)) = C(1)+C(2)*(LOG(WPOIL(-1))-LOG(WP(-1)))+C(3)*D(LOG(WPOIL(-1)))+(1-C(3))*(PI_E/400)
	MARTIN.merge _WPOIL
	MARTIN.addassign(i,c) WPOIL
	'World Real Policy Rate
	MARTIN.append wrr  = 0.95  * wrr(-1)  + 0.05  * wrr_target
	MARTIN.addassign(i,c) WRR
		'Spread
		MARTIN.append @IDENTITY wrsp  = wrr  - rcr
	'World Real 2-Year Rate
	smpl 1993q1 %eq_est_end
	equation _WR2R.LS WR2R =  WRR + C(1)*(WR2R(-1)-WRR(-1)) + C(2)*(1 - C(1))
	MARTIN.append wr2r  = (0.99)  * (wr2r(-1)  - wrr(-1))  + wrr  + (1  - 0.99)  * _wr2r.@coef(1)
	MARTIN.addassign(i,c) WR2R
		'Spread
		MARTIN.append @IDENTITY wr2sp  = wr2r  - r2r


