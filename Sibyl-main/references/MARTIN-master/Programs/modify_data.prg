'********************************************************************************
'Create Series for Model
'********************************************************************************
pageselect Rqtly
smpl @all

'************************************************************************************************
'Create Model Variables
'************************************************************************************************

'Extend Inflation Expectations / NAIRU 
	'Extend to end of file
	smpl @all
	!obs = @obs(PI_E)
	smpl if PI_E<>na
	%lastdate=@otods(!obs)
	smpl %lastdate+1 @last
	PI_E=PI_E(-1)

	smpl @all
	!obs = @obs(TLUR)
	smpl if TLUR<>na
	%lastdate=@otods(!obs)
	smpl %lastdate+1 @last
	TLUR = TLUR(-1)

	smpl @all

'Splice Back Cash Rate using Interbank Series
	!obs = @obs(ncr)
	smpl if ncr<>na
	%firstdate = @otods(1)

	for !i=1 to (@dtoo(%firstdate)-1) 	
		smpl %firstdate-!i %firstdate-!i 
		ncr=ncr(+1)*ncr_hist/ncr_hist(+1)
	next

	smpl @all

'Splice Forward old Business Lending Rate
	smpl @all
	!obs = @obs(NBR)
	smpl if NBR<>na
	%lastdate=@otods(!obs)
	smpl %lastdate+1 @last
	NBR=NBR(-1)+NBR_SPLICE-NBR_SPLICE(-1)

	smpl @all

'Adjust PEX for RBA Adjustments in 07q4 -> 10q3
smpl 2007q4 2010q3
PEX =  PEX_MARTIN/PEX_MARTIN(-1)*100-100
smpl 1982Q1 1982Q1
series PEXL = 100
smpl 1982q2 @last
PEXL=PEXL(-1)*(1+PEX/100)
smpl @all
delete(noerr) pex
rename pexl pex

'Create Level Series for Quarterly Inflation
smpl 1982q1 1982q1 
series PL = 100
smpl 1982q2 @last
PL=PL(-1)*(1+P/100)
smpl @all
delete(noerr) p
rename pl p

'Public Demand
series g = gi + gc
series ng = ngi + ngc

'Household Consumption Deflator
series PC = NC / RC*100

'Government Demand Deflator
series PG = ng/g*100

'gross national expenditure deflator
series PGNE = NGNE / GNE*100

'private business investment deflator
series pib= nib/ib*100

'dwelling investment deflator
series PID = NID/ID*100

'import deflator
series PM = NM/M*100
	
'Household Labor Income
series HCOE = NHCOE / PC

'Nominal Other Household Income
series nhoy=nhdy-nhcoe

'Real Household Other Income 
series HOY = NHOY/PC

'Hhold Real Disposable Income
series HDY = NHDY/PC

'Household Non-Financial Assets
series nhnfa=nhnfa_cd+nhnfa_dw

'Net Household Assets
series nha=nhfa+nhnfa

'Household non-labour income
series nhoy = NHDY - NHCOE

'Nominal Household Net Wealth
series nhnw=nha-nhl

'Real Household Net Wealth
series hnw=nhnw/pc

'Household Savings Rate
series NHSR = NHS/(NHDY - KIDC)

'Wage Share of Income
series nhws = nhcoe/ny

'Unemployment Rate
if @isobject("LUR") =0 then
	series LUR = 100*(1-LE/LF)
	'Unemployment Rate
	series LUR_hist = UR_hist/POP_hist*100
	LUR=@recode(LUR=NA,LUR_hist,LUR)
endif

'second hand assets sales
series ATS = IB - IBtot
series NATS = NIB - NIBtot
series PATS = NATS/ATS

'Stocks (Level)
smpl 1980q1 1980q1
series KV = 134865
smpl 1980q2 @last
kv=kv(-1)+v
smpl @all

'Exports - Manufacturs
series XM = XM_MACH + XM_TRNS + XM_OTHR + XM_BEVO
series NXM = NXM_MACH + NXM_TRNS + NXM_OTHR + NXM_BEVO

'Exports - resource
series xre = xre_ores + xre_coal + xre_othm + xre_metl + xre_nonm
series nxre = nxre_ores + nxre_coal + nxre_othm + nxre_metl + nxre_nonm

'Exports - Other Goods
series XO = XO_CARY + XO_NXOM + XO_NONR - XM_BEVO
series NXO = NXO_CARY + NXO_NXOM + NXO_NONR - NXM_BEVO

'Total Exports
series X = XAG + XM + XRE + XS + XO
series NX = NXAG + NXM + NXRE + NXS + NXO

'Statistical Discrepancy (E and CVM issues)
series sd = y - ( rc  + id  + ib  + g  + otc  - ats + v + x - m )
series nsd = ny  - ( nc  + nid  + nib  + ng  + notc  + nv  + nx  - nm  - nats )

'Average Earnings National Accounts
series lhpp = hours/le*3
series le_hist = le_farm_hist + le_nonfarm_hist

'Backcast Hours
	!obs = @obs(lhpp)
	smpl if lhpp<>na
	%firstdate = @otods(1)

	for !i=1 to (@dtoo(%firstdate)-1) 	
		smpl %firstdate-!i %firstdate-!i 
		lhpp=lhpp(+1)*lhpp_hist/lhpp_hist(+1)
	next
'Backcast Employment
	!obs = @obs(le)
	smpl if le<>na
	%firstdate = @otods(1)

	for !i=1 to (@dtoo(%firstdate)-1) 	
		smpl %firstdate-!i %firstdate-!i 
		le=le(+1)*le_hist/le_hist(+1)
	next

smpl @all

'Historical Aggregate Hours
series hours_hist = lhpp_hist*le_hist/3
'Historical Real GDP per hour worked
series la_hist = y/hours_hist  

'Backcast Labor Productivity
	!obs = @obs(la)
	smpl if la<>na
	%firstdate = @otods(1)

	for !i=1 to (@dtoo(%firstdate)-1) 	
		smpl %firstdate-!i %firstdate-!i 
		la=la(+1)*la_hist/la_hist(+1)
	next

smpl @all

'Average Earnings National Accounts
series pae = nhcoe/(lhpp*le)

'World Variables
'series wrr = wrcr - wp
'series Wr2r = Wn2r - wp
series wrr = ((1  + wrcr  / 100)  / (1  + wp  / wp(-4)  - 1))  * 100  - 100
series wr2r = ((1  + wn2r  / 100)  / (1  + wp  / wp(-4)  - 1))  * 100  - 100

'Interest Rates
series rcr =((1+ncr/100)/(1+ptm/ptm(-4)-1))*100-100
if @isobject("rstar") =0 then
	series RSTAR = @movav(rcr,40)
endif

'Household Credit
series NHC = NTC - NBC

'Domestic Final Demand Deflator
series PDFD = NDFD/DFD*100

'Domestic Final Demand incl. Exports
series DFDX = DFD + X

'Domestic Private Final Demand
series DPFD = RC + ID + IB + OTC - ATS
series ndpfd = nc+nid+nib+notc-nats
series pdpfd  = ndpfd  * 100  / dpfd

'GDP Deflator
series PY = NY/Y*100

'real Business Rate
series rbr =(1+(1-ibctr)*nbr/100)/(ptm(-1)/ptm(-5))*100-100

'Business Rate Spread
series NBRSP = NBR - NCR

'Mortgage Rate Spread
series nsp = nmr-ncr

'Nominal Unit Labor Costs
if @isobject("NULC") =0 then
	series nulc = nhcoe/y
endif

'Nominal Unit Labor Costs (Balassa Sam. Adj)
series nulcbs = nulc*(0.8+ 0.2*exp(0.002746*@trend))

'Real Unit Labor Costs
series rulc = nulc/pgne

'Real Unit Labor Costs (GDP Deflated)
series rulcy = nulc/py

'World Oil Price Local Currency
series poil = wpoil /nusd

'Ownership Transfer Cost Deflator
series POTC = NOTC/OTC*100

'Export Deflator
series PX = NX/X*100

'Agricultre Export Deflator
series PXAG = NXAG/XAG*100

'manufacturing Export Deflator
series PXM = NXM/XM*100

'other export deflator
series PXO = NXO/XO*100

'mining export deflator
series PXRE = NXRE/XRE*100

'service export deflator
series PXS = NXS/XS*100

'Real Mortgage Rate
series rmr = ( (1+nmr/100)/(ptm/ptm(-4)) -1 )*100

'Real Mortgage Rate (ex-ante)
series rmre=nmr-pi_e

'Real Labor Costs
series rlc = pae/pgne

'Terms of Trade
series tot = px/pm*100

'Import Adjusted Demand
series iad = rc^iad_w_c*ib^iad_w_i*gi^iad_w_gi*gc^iad_w_gc*x^iad_w_x

'************************************************************************************************
'SPLICING AND BACKCASTING
'************************************************************************************************

'House Prices (using martin_public.wf1 to backcast ABS series
	ph.x12
	ph_old.x12
	delete(noerr) ph ph_old
	rename ph_sa ph
	rename ph_old_sa ph_old

	!obs = @obs(PH)
	smpl if PH<>na
	
	%firstdate=@otods(1)
	%lastdate=@otods(!obs)
	
	smpl %firstdate %firstdate
	
	for !i=1 to (@ifirst(ph)-1)
		smpl %firstdate-!i %firstdate-!i
		PH = PH(1)*PH_OLD/PH_OLD(1)
	next

	smpl @all

	'Real House Price
	series rph = ph / ptm

'Government Bond Yields (2yr and 10yr)
	!obs = @obs(N2R)
	smpl if N2R<>na
	
	%firstdate=@otods(1)
	%lastdate=@otods(!obs)
	
	smpl %firstdate %firstdate
	
	for !i=1 to (@ifirst(N2R)-1)
		smpl %firstdate-!i %firstdate-!i
		N2R = N2R(1)+(N2R_MARTIN-N2R_MARTIN(1))
		N10R = N10R(1)+(N10R_MARTIN-N10R_MARTIN(1))
	next

smpl @all

'Real Cash Rate
series r2r = ((1  + n2r  / 100)  / (1  + ptm  / ptm(-4)  - 1))  * 100  - 100

'World Interest Rate Spread to Local Interest Rate
series wr2sp = wr2r-r2r
smpl @all
series wr2sp_gap_avg = -@mean(wr2sp)

'World 2-year Interest Rate Spread to World Interest Rate
series wrsp = wrr - rcr
smpl @all
series wr2gap = @mean(wrsp)

'*****************************CONVERTING ANNUAL TO QTLY FOR INVESTMENT**********************
'Dealing with Eviews interpolation works nicely with calendar but not Fiscal Years
'Mining Investment interpolated using qtly mining CAPEX figures
'Mining Depreciation Rate simple linear interpolation of annual figures

'-----------mining investment-----------------
smpl @all
'Depreciation Rate
	series IBREDRA = 100*(1-(KIBREA2-IBREA2)/KIBREA2(-4))
	IBREDRA = ((1+IBREDRA/100)^(1/4)-1)*100
	IBREDRA.ipolate IBREDR 'interpolate qtlized annual values
	delete(noerr) IBREDRA
	
	'Extend to end of file
	!obs = @obs(IBREDR)
	smpl if IBREDR<>na
	%firstdate=@otods(1)
	%lastdate=@otods(!obs)
	smpl @first %firstdate
	IBREDR = @elem(IBREDR,%firstdate)
	smpl %lastdate+1 @last
	IBREDR=IBREDR(-1)

	smpl @all	

'Investment Series
	series IBRE_CAPEXL2 = IBRE_CAPEX(-2) ' lag indicator to align to a calendar year conversion for Eviews
	series NIBRE_CAPEXL2 = NIBRE_CAPEX(-2) ' lag indicator to align to a calendar year conversion for Eviews
	
	copy(c=chowlins) Rannual\IBRE * @indicator ibre_capexL2
	copy(c=chowlins) Rannual\NIBRE * @indicator nibre_capexL2

	series IBRE = IBRE(2) 'move series to correct quarter for fiscal year
	series NIBRE = NIBRE(2) 'move series to correct quarter for fiscal year
	delete(noerr) IBRE_CAPEXL2 NIBRE_CAPEXL2

	'Private Non-Mining Business Investment
	series IBN = IB - IBRE
	series NIBN = NIB - NIBRE
	series pibn = nibn/ibn*100

	'private mining investment deflator
	series PIBRE = NIBRE/IBRE*100

'Capital Stock
	smpl 1987q2 1987q2
	series KIBREPIM=KIBREA2

	smpl @all

	for !i=1 to @ilast(IBRE)-1
		smpl 1987q2+!i 1987q2+!i
		KIBREpim = KIBREpim(-1)*(1-IBREDR/100) + IBRE
	next

	smpl @all

	'Move series to align with calendar year
	series KIBREPIMLead1 = KIBREpim(+1)
	
	'Interpolate Annual Dwelling Stock Using Chow-Lin and PIM Kstock measure
	copy(c=chowlinf) Rannual\KIBRE * @indicator kibrepimlead1
	'Move to fiscal year
	series KIBRELag1 = KIBRE(-1)
	delete(noerr) KIBRE
	rename KIBRELag1 KIBRE

	smpl @all
	KIBREA2.ipolate KIBREA3
	KIBRE=@recode(KIBRE=NA,KIBREA3,KIBRE)

'-----------dwelling capital stock-----------------
smpl @all

'Depreciation Rate
	series IDDRA = 100*(1-(KIDA2-IDA2)/KIDA2(-4))
	IDDRA = ((1+IDDRA/100)^(1/4)-1)*100
	IDDRA.ipolate IDDR
	delete(noerr) IDDRA

	'Backcast and Extend to end of file
	!obs = @obs(IDDR)
	smpl if IDDR<>na
	%firstdate=@otods(1)
	%lastdate=@otods(!obs)
	smpl @first %firstdate
	IDDR = @elem(IDDR,%firstdate)
	smpl %lastdate+1 @last
	IDDR=IDDR(-1)
	smpl @all	

'Capital Stock	
	'Perpetual Inventory method for K stock Qtly
	smpl 1960q2 1960q2 
	series KIDpim = KIDA2
	
	smpl @all

	for !i=1 to @ilast(ID)-1
		smpl 1960q2+!i 1960q2+!i
		KIDpim = KIDpim(-1)*(1-IDDR/100) + ID
	next

	smpl @all

	'Move series to align with calendar year
	series KIDPIMLead1 = kidpim(+1)
	
	'Interpolate Annual Dwelling Stock Using Chow-Lin and PIM Kstock measure
	copy(c=chowlinf) Rannual\KID * @indicator kidpimlead1
	'Move to fiscal year
	series KIDLag1 = KID(-1)
	delete(noerr) KID
	rename KIDLag1 KID

'-----------non-mining investment/capital stock-----------------
pageselect Rannual
series KIBN = KTOT - KID - KOTC - KIBRE

pageselect Rqtly
smpl @all
series IBNA2 = ITOTA2 - IDA2 - IOTCA2 - IBREA2
series KIBNA2 = KTOTA2 - KIDA2 - KOTCA2 - KIBREA2
series CFCIBNA2 = CFCTOTA2 - CFCIDA2 - CFCOTCA2 - CFCIBREA2

'Depreciation Rate
	series IBNDRA = 100*(CFCIBNA2/KIBNA2(-4))
	IBNDRA = ((1+IBNDRA/100)^(1/4)-1)*100
	IBNDRA.ipolate IBNDR
	delete(noerr) IBNDRA

	'Backcast and Extend to end of file
	!obs = @obs(IBNDR)
	smpl if IBNDR<>na
	%firstdate=@otods(1)
	%lastdate=@otods(!obs)
	smpl @first %firstdate
	IBNDR = @elem(IBNDR,%firstdate)
	smpl %lastdate+1 @last
	IBNDR=IBNDR(-1)
	smpl @all
	'Annual Depreciation	
	series ibndra  = ibndr  + ibndr(-1)  + ibndr(-2)  + ibndr(-3)

'Capital Stock	
	'Perpetual Inventory method for K stock Qtly
	smpl 1987q2 1987q2 
	series KIBNpim = KIBNA2
	
	smpl @all

	for !i=1 to @ilast(ID)-1
		smpl 1987q2+!i 1987q2+!i
		KIBNpim = KIBNpim(-1)*(1-IBNDR/100) + IBN
	next

	smpl @all

	'Move series to align with calendar year
	series KIBNpimLead1 = KIBNpim(+1)
	
	'Interpolate Annual Dwelling Stock Using Chow-Lin and PIM Kstock measure
	copy(c=chowlinf) Rannual\KIBN * @indicator KIBNpimlead1
	'Move to fiscal year
	series KIBNLag1 = KIBN(-1)
	delete(noerr) KIBN
	rename KIBNLag1 KIBN

	smpl @all
	KIBNA2.ipolate KIBNA3
	KIBN=@recode(KIBN=NA,KIBNA3,KIBN)

	'User Cost of Capital
	smpl @all
	series ibcr = (rbr/100+ibndra/100)*((1-ibctr*(ibndra/100*(1+n10r/100)/(n10r/100+ibndra/100)))/(1-ibctr))*(pibn/pgne)

	'Unemployment Rate Gap
	smpl @all
	series lurgap = lur - tlur

	'Import Adjusted Demand Deflator
	series piad  = pc^iad_w_c  * pib^iad_w_i  * pg^iad_w_gi  * pg^iad_w_gc  * px^iad_w_x

	'Rainfall - Extend
	!obs = @obs(RAIN)
	smpl if RAIN<>na
	%lastdate=@otods(!obs)
	smpl %lastdate+1 @last
	RAIN=0
	smpl @all
	
'************************************************************************************************
'Dummies / Trends / Constants / Scalars
'************************************************************************************************
smpl @all


series rtwi_const_dum = @recode(@date>@dateval("2031q4"),1,0)
series d_oly = @recode(@date=@dateval("2004:4"), 1,0)
series d_afc1 = @recode(@date=@dateval("1997:3"), 1,0)
series d_afc2 = @recode(@date=@dateval("1997:4"), 1,0)
series d_afc3 = @recode(@date=@dateval("1998:1"), 1,0)
series d_afc4 = @recode(@date=@dateval("1998:2"), 1,0)
series d_afc5 = @recode(@date=@dateval("1998:3"), 1,0)
series d_cpmcg = @recode(@date<@dateval("2000:2"), 1,0)
series d_gstdec = @recode(@date=@dateval("2000:4"), 1,0)
series d_gstjun = @recode(@date=@dateval("2000:2"), 1,0)
series d_gstmar = @recode(@date=@dateval("2000:1"), 1,0)
series d_gstsep = @recode(@date=@dateval("2000:3"), 1,0)
series d_ibre_1= @recode(@date=@dateval("1999q4"), 1,0)
series d_ibre_2= @recode(@date=@dateval("2001q4"), 1,0)
series d_ibre_3= @recode(@date=@dateval("2002q1"), 1,0)
series d_ibre_4= @recode(@date=@dateval("2002q2"), 1,0)
series d_ibre_5= @recode(@date=@dateval("2002q3"), 1,0)
series d_le= @recode(@date=@dateval("2003q2"), 1,0)
series d_nsp=@recode(@date>@dateval("1997q4") and @date<@dateval("2008q1"),1,0)
series d_rbagold = @recode(@date=@dateval("1997:2"), 1,0)
series d_2008q4= @recode(@date=@dateval("2008q4"), 1,0)
series dum_rc= @recode(@date<@dateval("2008:1"), 1,0)
series dum_2008q4= @recode(@date=@dateval("2008q4"), 1,0)

smpl @all
series d_olyx=0
smpl 2000q3 2000q3
d_olyx=1
smpl 2000q4 2000q4
d_olyx=-1

smpl @all
series pc_trend=NA
smpl 1982Q1 2022Q2
pc_trend=@trend
smpl 2022Q3 2118Q4
pc_trend=pc_trend(-1)

smpl 1959Q1 2118Q4
series pibn_trend_1 = 0
smpl 1985Q1 2012Q4
pibn_trend_1=pibn_trend_1(-1)+1
smpl 2013Q1 2118Q4
pibn_trend_1=pibn_trend_1(-1)

smpl 1959Q1 2118Q4
series pibn_trend_2 = 0
smpl 2013Q1 2022Q2
pibn_trend_2=pibn_trend_2(-1)+1
smpl 2022Q3 2118Q4
pibn_trend_2 = pibn_trend_2(-1)

smpl @all
series PIBRE_DUM1 = @recode(@date=@dateval("2000q4"), 1,0)
series PIBRE_DUM2 = @recode(@date=@dateval("2001q1"), 1,0)
series PIBRE_DUM3 = @recode(@date=@dateval("2001q2"), 1,0)
series PIBRE_DUM4 = @recode(@date=@dateval("2001q3"), 1,0)
series PTM_DUM = @recode(@date>@dateval("2019q1"), 1,0)

smpl 1959Q1 2011Q4
series tadp = @trend
smpl 2012Q1 @last
tadp = @elem(tadp, 2011q4)

smpl 1982Q1 2022Q2
series pid_trend=@trend
smpl 2022Q3 2118Q4
pid_trend=pid_trend(-1)

smpl 1959Q1 2118Q4
series potc_trend_1 = 0
smpl 1992Q1 2007Q4
potc_trend_1 = potc_trend_1(-1)+1
smpl 2008Q1 2118Q4
potc_trend_1 = potc_trend_1(-1)

smpl 1959Q1 2118Q4
series potc_trend_2 = 0
smpl 2008Q1 2022Q2
potc_trend_2 = potc_trend_2(-1)+1
smpl 2022Q3 2118Q4
potc_trend_2 = potc_trend_2(-1)

smpl 1986Q1 2000Q4
series pxm_trend=@trend
smpl 2001Q1 2118Q4
pxm_trend=pxm_trend(-1)

smpl 1959Q1 2118Q4
series pxs_trend_1 = 0
smpl 1986Q1 2000Q4
pxs_trend_1=pxs_trend_1(-1) + 1
smpl 2001Q1 2118Q4
pxs_trend_1=pxs_trend_1(-1)

smpl 1959Q1 2118Q4
series pxs_trend_2 = 0
smpl 2001Q1 2022Q2
pxs_trend_2 = pxs_trend_2(-1) + 1
smpl 2022Q3 2118Q4
pxs_trend_2 = pxs_trend_2(-1)

smpl 1959Q1 2118Q4
series wpx_trend_1 = 0
smpl 1980Q1 2000Q4
wpx_trend_1 = wpx_trend_1(-1)+1
smpl 2001Q1 2022Q2
wpx_trend_1 = wpx_trend_1(-1)
smpl 2022Q3 2118Q4
wpx_trend_1 = wpx_trend_1(-1)

smpl 1959Q1 2118Q4
series wpx_trend_2 = 0
smpl 2001Q1 2022Q2
wpx_trend_2 = wpx_trend_2(-1)+1
smpl 2022Q3 2118Q4
wpx_trend_2 = wpx_trend_2(-1)

smpl 1959Q1 2118Q4
series lur_dum=0
smpl 2031Q4 2118Q4
lur_dum=1

smpl @first @last
series xs_trend = @trend
smpl 2001q4 @last
xs_trend=xs_trend(-1)

smpl @all

'************************************************************************************************
'Set Important Model Scalars
'************************************************************************************************
smpl @all

'Steady State Potential Growth
	scalar AASTEADY_STATE_LA = 0.00372215312343764 'steady-state labor productivity growth
	scalar AASTEADY_STATE_POP = 0.003105629999639278 'steady-state population growth

'Monetary Policy
	series PI_TARGET = 2.5
	scalar tr_lurgap = 2 'weight on unemployment in Taylor Rule
	scalar tr_ptm = 2 'weight on inflation in Taylor Rule
	scalar TR_DLUR = 2 'weight on change in unemployment rate in Taylor Rule
	scalar RCR_TARGET = (AASTEADY_STATE_LA+AASTEADY_STATE_POP)*100 'Steady-state Real Cash Rate

'World Assumptions
	smpl 1990q1 %nataccs_end
	scalar wr2r_gap_avg = @mean(wr2r-r2r) ' Spread Between Australian and World Bond Rates
	scalar WRR_TARGET = -1 'Steady State Real Cash Rate

'	smpl @first %nataccs_end
'	equation _wpcomconst.ls log(wpcom)=log(wp)+c(1)
'	scalar RWPCOM_LR = _wpcomconst.@coef(1) 'long run steady state real world price of commodities
'	delete(noerr) _wpcomconst
	scalar RWPCOM_LR = 0.54

smpl @all

'Save Workfile After Modifying Data
wfsave .\..\output\modifieddata.wf1


