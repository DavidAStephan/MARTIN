'*********************************************************************************
'Supply Side MARTIN Model
'Estimates State Space Models for use in the MARTIN model
'Created David Stephan (david.stephan@gmail.com)
'Last Updated: 5 November

'*********************************************************************************
'Set Model Scalars
scalar param_trend = 100
scalar param_drift = 10000

scalar param_poptrend = 100
scalar param_popdrift = 10000

scalar param_lhpp = 50

'------------------------------------
'Trend Productivity
'------------------------------------
	smpl 1966q1 %NATACCS_end
	delete(noerr) ss_la
	delete(noerr) tlla
	delete(noerr) tdlla
	sspace SS_LA
	
	vector(2) mprior_la
	mprior_la(1) = 3.687622086817885
	mprior_la(2) = 0.0070

	sym(2) vprior_la
	vprior_la.fill 0.0001,0,1e-06

	ss_la.append @SIGNAL LOG(LA) = TLLA + [VAR=EXP(C(99))]
	ss_la.append @STATE TLLA = TDLLA(-1) + TLLA(-1) + E_TDLLA + E_TLLA
	ss_la.append @STATE TDLLA = TDLLA(-1) + E_TDLLA
	ss_la.append @ENAME E_TLLA
	ss_la.append @ENAME E_TDLLA
	ss_la.append @EVAR VAR(E_TLLA) = EXP(C(99))/PARAM_TREND
	ss_la.append @EVAR VAR(E_TDLLA) = EXP(C(99))/PARAM_DRIFT
	ss_la.append @MPRIOR mprior_la
	ss_la.append @VPRIOR vprior_la

	ss_la.ml
	ss_la.makestates(t=smooth) *

'------------------------------------
'Trend Population
'------------------------------------
	smpl 1978Q3 %NATACCS_end
	delete(noerr) SS_LPOP
	delete(noerr) tllpop
	delete(noerr) tdllpop
	sspace SS_LPOP

	vector(2) mprior_pop
	mprior_pop(1) = 9.265860822608552
	mprior_pop(2) = 0.0070

	sym(2) vprior_pop
	vprior_pop.fill 0.0001,0,1e-06

	SS_LPOP.append @SIGNAL LOG(LPOP) = TLLPOP + [VAR=EXP(C(99))]
	SS_LPOP.append @STATE TLLPOP = TDLLPOP(-1) + TLLPOP(-1) + E_TDLLPOP + E_TLLPOP
	SS_LPOP.append @STATE TDLLPOP = TDLLPOP (-1) + E_TDLLPOP
	SS_LPOP.append @ENAME E_TLLPOP
	SS_LPOP.append @ENAME E_TDLLPOP
	SS_LPOP.append @EVAR VAR(E_TLLPOP) = EXP(C(99))/PARAM_POPTREND
	SS_LPOP.append @EVAR VAR(E_TDLLPOP) = EXP(C(99))/PARAM_POPDRIFT
	SS_LPOP.append @MPRIOR MPRIOR_POP
	SS_LPOP.append @VPRIOR VPRIOR_POP

	SS_LPOP.ml
	ss_lpop.makestates(t=smooth) *

'------------------------------------
'Trend Hours Worked
'------------------------------------

	smpl 1966q1 %NATACCS_end
	delete(noerr) ss_lhpp
	delete(noerr) tllhpp
	sspace ss_lhpp

	vector(1) mprior_hpp
	mprior_hpp(1) = 6.20000

	sym(1) vprior_hpp
	vprior_hpp.fill 1e-06

	ss_lhpp.append @SIGNAL LOG(LHPP) = TLLHPP + [VAR=EXP(C(99))]
	ss_lhpp.append @STATE TLLHPP = C(1) + TLLHPP(-1) + E_TLLHPP
	ss_lhpp.append @ENAME E_TLLHPP
	ss_lhpp.append @EVAR VAR(E_TLLHPP) = EXP(C(99))/PARAM_LHPP
	ss_lhpp.append @MPRIOR MPRIOR_HPP
	ss_lhpp.append @VPRIOR VPRIOR_HPP

	SS_LHPP.ml
	ss_LHPP.makestates(t=smooth) *

	smpl @all
	series tdllhpp = ss_lhpp.@coefs(1)

	'Extend to end of file
	!obs = @obs(tdllhpp)
	smpl if tdllhpp<>na
	%lastdate=@otods(!obs)
	smpl %lastdate @last
	tdllhpp=tdllhpp(-1)

	smpl @all

'Potential Growth Rate
series TY_POT = TDLLA+TDLLPOP+TDLLHPP

'------------------------------------
'Trend Unemployment Rate
'------------------------------------
	smpl 1959Q3 %NATACCS_end
	delete(noerr) SS_LUR
	delete(noerr) LOKLAG
	delete(noerr) TY
	sspace SS_LUR

	vector(2) mprior_lur
	mprior_lur(1) = 0
	mprior_lur(2) = 0.01

	sym(2) vprior_lur
	vprior_lur.fill 1,0,0.000125

	ss_LUR.append @param c(2) -19.95240 C(3) 7.908193 C(9) 0.239001 C(11) -0.030451 C(12) 0.000285 
	SS_LUR.append @signal D(LUR) = LOKLAG*D(LUR(-1)) + C(2)*( ((LOG(Y)-LOG(Y(-2)))/2) - TY ) + C(3)*( (LOG(RULC(-2))-LOG(RULC(-4)))/2 )  + [VAR = (C(9)^2)]
	SS_LUR.append @STATE LOKLAG = LOKLAG(-1) + E_LOKLAG
	SS_LUR.append @STATE TY = TY(-1) + E_TY
	SS_LUR.append @ENAME E_LOKLAG
	SS_LUR.append @EVAR VAR(E_LOKLAG) = ((C(11))^2)
	SS_LUR.append @ENAME E_TY
	SS_LUR.append @EVAR VAR(E_TY) = (C(12)^2)
	SS_LUR.append @MPRIOR MPRIOR_LUR
	SS_LUR.append @VPRIOR VPRIOR_LUR

	SS_LUR.ml
	ss_LUR.makestates(t=filt) *

'Save Workfile After Running State Space Models
wfsave .\..\output\supplieddata.wf1


