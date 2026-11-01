'___________________________________________________________________________________________________________________________________________________________________________

'  ESTIMATE NAIRU FOR AUSTRALIA
' email: david.stephan@gmail.com ;
' reference: https://www.rba.gov.au/publications/bulletin/2017/jun/pdf/bu-0617-2-estimating-the-nairu-and-the-unemployment-gap.pdf
' last update 4 November, 2019
'___________________________________________________________________________________________________________________________________________________________________________

'Set Estimation Period
delete(noerr) ssest
sample ssest 1986q3 %nataccs_end

'-----------------------------------------------------------------------------
'Data Manipulations
	smpl @all

	'Qtly Trimmed Mean Inflation
	series dlptm= dlog(ptm)*100

	'Qtly Non-Farm Unit Labor Costs
	smpl @all
	series nulc = nhcoe/y
	series dlulc = dlog(nulc)*100
	
	'Year-ended Growth in Consumer Import Prices
	series dl4pimp = (log(pmcg)-log(pmcg(-4)))*100

	'Qtly Inflation Expectations
	series pi_eq = ((1+pi_e/100)^(1/4)-1)*100

	'Qtly Growth in WTI Oil Price (use WTI because longer publicly available series)
	series dlwti = dlog(wpoil)*100
	
	'Dummy Variable for 1997
	series dum_nairu = 0
	smpl @first 1976q4 
	dum_nairu =1 

	'Unemployment Rate
	smpl @all
	series LUR = 100*(1-LE/LF)
	'Unemployment Rate
	series LUR_hist = UR_hist/POP_hist*100
	LUR=@recode(LUR=NA,LUR_hist,LUR)	

'-----------------------------------------------------------------------------
'Creat initial series for initialzing state space
smpl ssest
lur.hpf(lambda=1600) unrsmooth
series unrgap_ini = lur-unrsmooth

vector(1) mprior = 0
mprior(1) = 5.5 ' Calibrated to get similar values to RBA Paper for NAIRU
sym(1) vprior = 0.4 'Using RBA Paper Value

'-----------------------------------------------------------------------------
'Create Parameters/Starting Values for State Space Model

	' Setup coefficient vectors
	coef(2) delta
	coef(3) beta
	coef(1) phi
	coef(2) gamma
	coef(2) lambda
	coef(1) alpha
	coef(2) omega
	coef(3) sigma
	
	'-----------------------------------------------------------------------------
	' Estimate initial coefficients
	
		'***********************************************	
		' Trimmed Mean Inflation
		smpl ssest
		equation eq_ptm.ls dlptm = delta(1)*pi_eq + _
											beta(1)*dlptm(-1) + beta(2)*dlptm(-2) + beta(3)*dlptm(-3) + _
											phi(1)*dlulc(-1) + _
											gamma(1)*unrgap_ini/LUR + _
											lambda(1)*(d(LUR(-1))/LUR) + _
											alpha(1)*dl4pimp(-1)

		' Store estimates for later use
		!delta1=delta(1)
		!beta1=beta(1)
		!beta2=beta(2)
		!beta3=beta(3)
		!phi1=phi(1)
		!gamma1=gamma(1)
		!lambda1=lambda(1)
		!alpha1=alpha(1)
		!sigma1 = eq_ptm.@se 
		'***********************************************

		'***********************************************	
		' ULC Growth
		smpl ssest
		equation eq_ulc.ls dlulc = delta(2)*pi_eq + _
											omega(1)*dlulc(-1) + omega(2)*dlulc(-2) + _
											gamma(2)*unrgap_ini/LUR + _
											lambda(2)*(d(LUR(-1))/LUR)

		' Store estimates for later use
		!delta2=delta(2)
		!omega1=omega(1)
		!omega2=omega(2)
		!gamma2=gamma(2)
		!lambda2=lambda(2)
		!sigma2 = eq_ptm.@se 
		'***********************************************
		
		'***********************************************
		' LUR Trend Rate
		smpl ssest
		equation eq_unrsmooth.ls d(unrsmooth) = c(1)
		!sigma3=eq_unrsmooth.@se 
		'***********************************************
	

'-----------------------------------------------------------------------------------------------------------------------------------------------
'State Space System of NAIRU Using Inflation and ULC Equations

	'********Estimate System Using RBA Estimated Inflation Expectations*********
	sspace ss_nairu
	ss_nairu.append @param delta(1) !delta1 delta(2) !delta2 
	ss_nairu.append @param gamma(1) !gamma1 gamma(2) !gamma2 
	ss_nairu.append @param lambda(1) !lambda1 lambda(2) !lambda2
	ss_nairu.append @param beta(1) !beta1 beta(2) !beta2 beta(3) !beta3
	ss_nairu.append @param omega(1) !omega1 omega(2) !omega2
	ss_nairu.append @param phi(1) !phi1
	ss_nairu.append @param alpha(1) !alpha1 
	ss_nairu.append @param sigma(1) !sigma1 sigma(2) !sigma2 sigma(3) !sigma3
	
	ss_nairu.append @signal dlptm = delta(1)*pi_eq + _
												beta(1)*dlptm(-1) + beta(2)*dlptm(-2) + beta(3)*dlptm(-3) + _
												phi(1)*dlulc(-1) + _
												gamma(1)*(LUR-NAIRU)/LUR + _
												lambda(1)*(d(LUR(-1))/LUR) + _
												alpha(1)*dl4pimp(-1) + _
												[ename = e1, var = (sigma(1)^2)]
	
	ss_nairu.append @signal dlulc = delta(2)*pi_eq + _
												omega(1)*dlulc(-1) + omega(2)*dlulc(-2) + _
												gamma(2)*(LUR-NAIRU)/LUR + _
												lambda(2)*(d(LUR(-1))/LUR) + _
												[ename = e2, var = (sigma(2)^2)]
	
	ss_nairu.append @state NAIRU = NAIRU(-1) + [ename = e3, var = (sigma(3)^2)]
	
	ss_nairu.append @mprior mprior
	ss_nairu.append @vprior vprior
	
	smpl ssest
	ss_nairu.ml(optmethod=legacy)
	ss_nairu.makestates(t=smooth) *

	copy NAIRU TLUR


