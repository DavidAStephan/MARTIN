'___________________________________________________________________________________________________________________________________________________________________________

'  ESTIMATE NUETRAL INTEREST RATE FOR AUSTRALIA
' email: david.stephan@gmail.com ;
' reference: https://www.rba.gov.au/publications/bulletin/2017/sep/pdf/bu-0917-2-the-neutral-interest-rate.pdf

'___________________________________________________________________________________________________________________________________________________________________________

'Set Estimation Period
delete(noerr) ssest
sample ssest 1986q3 %nataccs_end

'-----------------------------------------------------------------------------
'Data Manipulations
	'Qtly Trimmed Mean Inflation
	series dlptm= dlog(ptm)*100

	'Qtly Real GDP Log Level and Growth
	series lrgdp = log(y)*100
	series dlrgdp = d(y)
	
	'Real Cash Rate (delfated with trimmed mean inflation)
	series rcash = ncr - (dlptm*4)

	'Qtly Inflation Expectations
	series pi_eq = ((1+pi_e/100)^(1/4)-1)*100

	smpl @all

'-----------------------------------------------------------------------------
'Creat initial series for initialzing state space
smpl ssest

lrgdp.hpf(lambda=1600) ypot_ini
LUR.hpf(lambda=1600) nairu_ini
rcash.hpf(lambda=1600) nrate_ini
series ygap_ini = lrgdp - ypot_ini
series g_ini = d(ypot_ini)
series z_ini = nrate_ini - g_ini

vector(11) mprior = 0
mprior(1) = ygap_ini(@ifirst(ygap_ini)+1)
mprior(2) = ygap_ini(@ifirst(ygap_ini))
mprior(3) = ygap_ini(@ifirst(ygap_ini))
mprior(4) = ygap_ini(@ifirst(ygap_ini))
mprior(5) = ypot_ini(@ifirst(ypot_ini)+1)
mprior(6) = g_ini(@ifirst(g_ini)+1)
mprior(7) = nairu_ini(@ifirst(nairu_ini)+1)
mprior(8) = nairu_ini(@ifirst(nairu_ini))
mprior(9) = nrate_ini(@ifirst(nrate_ini)+1)
mprior(10) = nrate_ini(@ifirst(nrate_ini))
mprior(11) = z_ini(@ifirst(z_ini)+1)

'From RBA Paper Posterior Modes
sym(11) vprior = 0
vprior(1,1) = 0.38
vprior(2,2) = 0.38
vprior(3,3) = 0.38
vprior(4,4) = 0.38
vprior(5,5) = 0.54
vprior(6,6) = 0.05
vprior(7,7) = 0.15
vprior(8,8) = 0.15
vprior(9,9) = 0.3
vprior(10,10) = 0.3
vprior(11,11) = 0.22

'-----------------------------------------------------------------------------
'Create Parameters/Starting Values for State Space Model

	' Setup coefficient vectors
	coef(3) delta
	coef(3) alpha
	coef(1) beta
	coef(2) gamma
	coef(10) sigma
	
	'-----------------------------------------------------------------------------
	' Estimate initial coefficients
	
		'***********************************************	
		' Output Gap
		smpl ssest
		equation eq_ygap.ls ygap_ini = alpha(1)*ygap_ini(-1) + alpha(2)*ygap_ini(-2) - _
												alpha(3)/2*(rcash(-1) - nrate_ini(-1) + rcash(-2) - nrate_ini(-2))

		' Store estimates for later use
		!alpha1=alpha(1)
		!alpha2=alpha(2)
		!alpha3=alpha(3)
		!sigma1 = eq_ygap.@se 

		'***********************************************

		'***********************************************	
		' Okun's Law
		smpl ssest
		equation eq_okun.ls LUR = nairu_ini + _
											beta(1)*(0.4*ygap_ini + 0.3*ygap_ini(-1) + 0.2*ygap_ini(-2) + 0.1*ygap_ini(-3))

		' Store estimates for later use
		!beta1=beta(1)
		!sigma2 = eq_okun.@se 

		'***********************************************

		'***********************************************	
		' Phillips Curve
		smpl ssest
		equation eq_ptm.ls dlptm = (1-gamma(1))*pi_eq + _
												gamma(1)/3*(dlptm(-1) + dlptm(-2) + dlptm(-3)) + _
												gamma(2)*(LUR(-1) - nairu_ini(-1))

		' Store estimates for later use
		!gamma1=gamma(1)
		!gamma2=gamma(2)
		!sigma3 = eq_ptm.@se 

		'***********************************************
		
		'***********************************************
		' LUR Trend Rate
		smpl ssest
		equation eq_NRATE.ls d(nairu_ini) = c(1)
		!sigma4=eq_NRATE.@se 

		'***********************************************

		'***********************************************
		' GDP Trend
		smpl ssest
		equation eq_ypot.ls ypot_ini =delta(1)+ypot_ini(-1)
		
		' Store estimates for later use
		!delta1=delta(1)
		!sigma5=eq_ypot.@se

		'***********************************************

		'***********************************************
		' Unexplained Neutral Rate Movements
		smpl ssest
		equation eq_z.ls d(z_ini) = delta(3)
		!delta3=delta(3)
		
		' Store estimates for later use
		!sigma6=eq_z.@se

		'***********************************************
			
		'***********************************************
		' Trend Growth Rate
		smpl ssest
		equation eq_g.ls d(g_ini) = delta(2)
		!delta2=delta(2)
		
		' Store estimates for later use
		!sigma7=eq_g.@se

'-----------------------------------------------------------------------------------------------------------------------------------------------
'State Space System of GDP/ UR Rate and Part Rate
sspace ss_nrate
ss_nrate.append @param delta(1) !delta1 delta(2) !delta2 delta(3) !delta3
ss_nrate.append @param alpha(1) !alpha1 alpha(2) !alpha2 alpha(3) !alpha3
ss_nrate.append @param beta(1) !beta1
ss_nrate.append @param gamma(1) !gamma1 gamma(2) !gamma2
ss_nrate.append @param sigma(1) !sigma1 sigma(2) !sigma2 sigma(3) !sigma3 sigma(4) !sigma4 sigma(5) !sigma5 sigma(6) !sigma6 sigma(7) !sigma7

ss_nrate.append @signal lrgdp = ypot + ygap

ss_nrate.append @signal LUR = nairu + _
											beta(1)*(0.4*ygap + 0.3*ygapL1 + 0.2*ygapL2 + 0.1*ygapL3) + _
											[ename = e2, var = (sigma(2)^2)]

ss_nrate.append @signal dlptm = (1-gamma(1))*pi_eq + _
												gamma(1)/3*(dlptm(-1) + dlptm(-2) + dlptm(-3)) + _
												gamma(2)*(LUR(-1) - nairuL1) + _
												[ename = e3, var = (sigma(3)^2)]

ss_nrate.append @state ygap = alpha(1)*ygap(-1) + alpha(2)*ygapL1(-1) - _
												alpha(3)/2*(rcash(-1) - nrate(-1) + rcash(-2) - nrateL1(-1)) + _
												[ename = e1, var = (sigma(1)^2)]
ss_nrate.append @state ygapL1 = ygap(-1) 
ss_nrate.append @state ygapL2 = ygapL1(-1)
ss_nrate.append @state ygapL3 = ygapL2(-1)

ss_nrate.append @state ypot = ypot(-1) + g(-1) + [ename = e5, var = (sigma(5)^2)]
ss_nrate.append @state g = g(-1) + [ename = e7, var = (sigma(7)^2)]

ss_nrate.append @state NAIRU = NAIRU(-1) + [ename = e4, var = (sigma(4)^2)]
ss_nrate.append @state NAIRUL1 = NAIRU(-1)

ss_nrate.append @state nrate = 4*(g(-1) + e7) + (z(-1) + e6)
ss_nrate.append @state nrateL1 = nrate(-1)
ss_nrate.append @state z = z(-1) + [ename = e6, var = (sigma(6)^2)]

ss_nrate.append @mprior mprior
ss_nrate.append @vprior vprior

smpl ssest
ss_nrate.ml(optmethod=legacy)
ss_nrate.makestates(t=smooth) *

delete(noerr) rstar
delete(noerr) eq_*
rename nrate rstar


