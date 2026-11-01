' -------------------------------------------------------------------------------------
' -------------------------------------------------------------------------------------
' Inflation Expectations From Survey Data
' Programmer: David Stephan
' Last Updated: 4 November, 2019
' email: david.stephan@gmail.com
' -------------------------------------------------------------------------------------
' -------------------------------------------------------------------------------------

'Create YoY CPI
smpl @all
series DL4PTM = 100*(log(PTM)-log(PTM(-4)))

'Creat initial series for initialzing state space
DL4PTM.hpf(lambda=1600) DL4PTMsmooth

!obs = @obs(PI_E_BOND)
smpl if PI_E_BOND<>na
%firstdate=@otods(1)

delete(noerr) ssest
sample ssest {%firstdate} %nataccs_end

smpl ssest

vector(2) mprior_pie = 0
mprior_pie(1) = @elem(DL4PTMsmooth,"1985q4")
mprior_pie(2) = @elem(DL4PTMsmooth,"1985q4")
sym(2) vprior_pie
vprior_pie(1,1) = 0.5
vprior_pie(2,2) = 0.5

'-----------------------------------------------------------------------------
'Dummy Variables for GST
smpl @all
series d_GBUSEXP=0
smpl 2000q2 2000q2
d_GBUSEXP=1

smpl @all
series d_GUNIEXPY=0
smpl 1999q4 2001q3
d_GUNIEXPY=1

smpl @all
series d_GUNIEXPYY=0
smpl 1999q4 2001q3
d_GUNIEXPYY=1

smpl @all
series d_GMAREXPY=0
smpl 2000q2 2000q3
d_GMAREXPY=1

smpl @all
series d_GMAREXPYY=0
smpl 1999q3 1999q4
d_GMAREXPYY=1

smpl @all

'-----------------------------------------------------------------------------
'Create Parameters/Starting Values for State Space Model

	' Setup coefficient vectors
	coef(1) delta
	coef(6) theta
	coef(6) gamma
	coef(8) sigma
	coef(5) lambda

	'-----------------------------------------------------------------------------
	' Estimate initial coefficients

	'Set Estimation Period
	
		'***********************************************	
		' Inflation Signal Equation
		smpl ssest
		equation eq_DL4PTM.ls DL4PTM = DL4PTMsmooth + delta(1)*(DL4PTM(-1) - DL4PTMsmooth(-1))

		' Store estimates for later use
		!delta1=delta(1)
		!sigma1 = eq_DL4PTM.@se 
		'***********************************************

		'***********************************************	
		' Inflation Expectations
		!x=0
		!y=1
		%zvars = "GBUSEXP GUNIEXPY GUNIEXPYY GMAREXPY GMAREXPYY GBONYLD"

		for %var {%zvars}

			!x=!x+1
			!y=!y+1
	
			smpl ssest
			if %var = "GBONYLD" then
				equation eq_{%var}.ls {%var}= theta(!x) + gamma(!x)*DL4PTMsmooth
			else
				equation eq_{%var}.ls {%var}= theta(!x) + gamma(!x)*DL4PTMsmooth + lambda(!x)*d_{%var}
				!lambda{!x} = lambda(!x)
			endif

			' Store estimates for later use
			!theta{!x} = theta(!x)
			!gamma{!x} = gamma(!x)
			!sigma{!y} = eq_{%var}.@se 

		next

		'***********************************************

		'***********************************************
		' Trend Inflation
		!y=!y+1
		smpl ssest
		equation eq_cpixsmooth.ls d(DL4PTMsmooth) = c(1)
		!sigma{!y} = eq_cpixsmooth.@se 
		'***********************************************

'State Space System of Inflation Expectations
sspace ss_pie
ss_pie.append @param delta(1) !delta1 
ss_pie.append @param theta(1) !theta1 theta(2) !theta2 theta(3) !theta3 theta(4) !theta4 
ss_pie.append @param theta(5) !theta5 theta(6) !theta6
ss_pie.append @param gamma(1) !gamma1 gamma(2) !gamma2 gamma(3) !gamma3 gamma(4) !gamma4 
ss_pie.append @param gamma(5) !gamma5 gamma(6) !gamma6
ss_pie.append @param lambda(1) !lambda1 lambda(2) !lambda2 lambda(3) !lambda3 lambda(4) !lambda4 lambda(5) !lambda5
ss_pie.append @param sigma(1) !sigma1 sigma(2) !sigma2 sigma(3) !sigma3 sigma(4) !sigma4 
ss_pie.append @param sigma(5) !sigma5 sigma(6) !sigma6 sigma(7) !sigma7 sigma(8) !sigma8 

ss_pie.append @signal DL4PTM = cpistar + delta(1)*( DL4PTM(-1) - cpistarL1 ) + [ename = e1, var=(sigma(1)^2)]

ss_pie.append @signal  GBUSEXP = cpistar + lambda(1)*d_GBUSEXP + [ename = e2, var=(sigma(2)^2)]
ss_pie.append @signal  GUNIEXPY = cpistar + lambda(2)*d_GUNIEXPY + [ename = e3, var=(sigma(3)^2)]
ss_pie.append @signal  GUNIEXPYY = cpistar + lambda(3)*d_GUNIEXPYY + [ename = e4, var=(sigma(4)^2)]
ss_pie.append @signal  GMAREXPY = cpistar + lambda(4)*d_GMAREXPY + [ename = e5, var=(sigma(5)^2)]
ss_pie.append @signal  GMAREXPYY = cpistar + lambda(5)*d_GMAREXPYY + [ename = e6, var=(sigma(6)^2)]
ss_pie.append @signal  GBONYLD = cpistar + [ename = e7, var=(sigma(7)^2)] 

ss_pie.append @state cpistar = cpistar(-1) + [ename = e8, var=(sigma(8)^2)]
ss_pie.append @state cpistarL1 = cpistar(-1)

ss_pie.append @mprior mprior_pie
ss_pie.append @vprior vprior_pie

smpl ssest
ss_pie.ml
ss_pie.makestates(t=smooth) pi_e pi_e_lag

'Cleanup Workfile
delete(noerr) eq_cpixsmooth eq_dl4ptm eq_gbonyld eq_gbusexp eq_gmarexpy eq_gmarexpyy eq_guniexpy eq_guniexpyy


