'Compare IRFs from RBA Public MARTIN and Github Version
'
' Created:
' 20/06/2019 - Daniel Rees
'
' Edited David Stephan
' 1 November 2019
'
' ================================================================
' Set current eviews directory
close @wf
%path = @runpath
cd %path

' Load workfile
load .\data\martin_public.wf1
load .\output\solvedmodel.wf1

%modelnames = "martin m_martin"
%wfname1 = "solvedmodel"
%wfname2 = "martin_public"

' ================================================================
' Set simulation dates
%shock_start = "2019:1" 			' Start date of shocks
%sim1_start = "2019Q1"		' Start date of simulation
%sim1_end  = "2029Q4"		' End of simulation
%last_data = "2018Q2"

smpl @all

'====================================
' Set model baseline 
%baseline = "0"

'Set Scenarios
%scn_num = "_s1 _s2 _s3"
	
'Monetary Policy Shock - 4 quarter
%shock_title_s1    = "Monetary_Policy"			' Name the scenario
%shock_name_s1 = "ncr rstar gc gi"			' List of variables whose values you are fixing in the scenario
%shock_type_s1   ="ppt ppt pct pct"				' The units of the fix, ppt=percentage point / pct=per cent deviation 
%shock_length_s1 = "4 40 40 40" 				' Number of quarters to hold the fix for
%shock_size_s1   = "1 0 0 0"						' Size of the deviation from baseline
%shock_num_s1 = "1 2 3 4"						' Number of shocks

' Exchange Rate Shock - 4 quarter
%shock_title_s2   = "Exchange_Rate"
%shock_name_s2 = "rtwi rstar gc gi"
%shock_type_s2   ="pct ppt pct pct"
%shock_length_s2 = "4 40 40 40"
%shock_size_s2  = "-10 0 0 0"
%shock_num_s2 = "1 2 3 4"

' House Price
%shock_title_s3 = "Housing Price fall"
%shock_name_s3 = "ph rstar gc gi"
%shock_type_s3 = "pct ppt pct pct"
%shock_length_s3 = "4 40 40 40"
%shock_size_s3 =  "-10 0 0 0"
%shock_num_s3	=  "1 2 3 4"

'======================================================================
'logmode all
!i=0
for %modelname {%modelnames}
	!i=!i+1
	wfselect %wfname{!i}
	if %wfname{!i} = "solvedmodel" then
		{%modelname}.append @IDENTITY pi_ptm  = (ptm  / ptm(-4)  - 1)  * 100
		{%modelname}.append @IDENTITY pi_pw  = (pw  / pw(-4)  - 1)  * 100
		{%modelname}.update
	endif
	
	'Solve a baseline scenario 
	smpl {%sim1_start} {%sim1_end}
	{%modelname}.scenario "baseline"
	{%modelname}.solve
	
	'Solve shock scenarios
	
	for %scn {%scn_num}

		scalar shock_count = 0
		for %s {%shock_name{%scn}}
			shock_count = shock_count+1
			%str_count = @str(shock_count)
			string shock{%str_count}{%scn} = %s
		next
	
		scalar shock_count =0 
		for %s {%shock_type{%scn}}
			shock_count = shock_count+1
			%str_count = @str(shock_count)
			string shock{%str_count}_type{%scn} = %s
		next
	
		scalar shock_count =0 
		for %s {%shock_length{%scn}}
			shock_count = shock_count+1
			%str_count = @str(shock_count)
			!shock{%str_count}_length{%scn} = @val(%s)
		next
	
		scalar shock_count =0 
		for %s {%shock_size{%scn}}
			shock_count = shock_count+1
			%str_count = @str(shock_count)
			!shock{%str_count}_size{%scn} = @val(%s)
		next

	next

	for %scn {%scn_num}

		for %s {%shock_num{%scn}}
			'Creates a string corresponding to end of shock
			!shock{%s}_obs{%scn}=@dtoo(%shock_start)
			!shock{%s}_end{%scn} = !shock{%s}_obs{%scn}+!shock{%s}_length{%scn}-1  'subtract one as already including initial quarter
			%shock{%s}_end{%scn} = @otod(!shock{%s}_end{%scn})
		next
	
	'Create group for shocks
	group scn_shocks{%scn}
	
		for %s {%shock_num{%scn}}
			'create back up series of shock variable
			smpl @all
			series {shock{%s}{%scn}}_bac = {shock{%s}{%scn}}
	
			'Add relevant shocks to group to run through scenario
			scn_shocks{%scn}.add {shock{%s}{%scn}}
		next
	
		smpl {%sim1_start} {%sim1_end}
		{%modelname}.scenario(n,a={%scn}) %shock_title{%scn}
	
		for %s {%shock_num{%scn}}
			if shock{%s}_type{%scn} = "ppt" then
				series {shock{%s}{%scn}}={shock{%s}{%scn}}_{%baseline}+{!shock{%s}_size{%scn}} 'add the shock size to the baseline shock variable to create a new series
			else
			if shock{%s}_type{%scn} = "pct" then
				series {shock{%s}{%scn}}={shock{%s}{%scn}}_{%baseline}*(1+{!shock{%s}_size{%scn}}/100)
			else
			if shock{%s}_type{%scn} = "pcy" then
				series {shock{%s}{%scn}}={shock{%s}{%scn}}_{%baseline}+{!shock{%s}_size{%scn}}*y_{%baseline}/(100)	
			else
				@uiprompt(shock{%s}+"error in type of shock, adjust and try again", "O")
			endif
			endif
			endif
	
			smpl {%sim1_start} {%sim1_end}
			{%modelname}.exclude(m) {shock{%s}{%scn}}({%shock_start} {%shock{%s}_end{%scn}})

		next 

		{%modelname}.solve
	next	

next
' ===============================================================
' Consolidate Results

%sim1_start = "2019Q1"		' Start date of simulation
%sim1_end  = "2029Q4"		' End of simulation
wfcreate(WF=compare) q {%sim1_start} {%sim1_end}

copy solvedmodel::*_s* compare::*_s*_git
copy solvedmodel::*_0 compare::*_0_git
copy martin_public::*_s* compare::*_s*_rba
copy martin_public::*_0 compare::*_0_rba

' ===============================================================
' Plot results

' Create IRF series
smpl @all
%version = "git rba"
for %irfname {%version}
	series irf_ncr_ncr_{%irfname} = ncr_s1_{%irfname}-ncr_0_{%irfname}
	series irf_ncr_y_{%irfname} = y_s1_{%irfname}/y_0_{%irfname}*100-100
	series irf_ncr_u_{%irfname} = lur_s1_{%irfname}-lur_0_{%irfname}
	series irf_ncr_p_{%irfname} = pi_ptm_s1_{%irfname}-pi_ptm_0_{%irfname}
	series irf_ncr_w_{%irfname} = pi_pw_s1_{%irfname}-pi_pw_0_{%irfname}
	series irf_ncr_rtwi_{%irfname} = rtwi_s1_{%irfname}/rtwi_0_{%irfname}*100-100
	
	series irf_ncr_rc_{%irfname} = rc_s1_{%irfname}/rc_0_{%irfname}*100-100
	series irf_ncr_id_{%irfname} = id_s1_{%irfname}/id_0_{%irfname}*100-100
	series irf_ncr_ib_{%irfname} = ib_s1_{%irfname}/ib_0_{%irfname}*100-100
	series irf_ncr_xnre_{%irfname} = (x_s1_{%irfname}-xre_s1_{%irfname})/(x_0_{%irfname}-xre_0_{%irfname})*100-100
	series irf_ncr_xre_{%irfname} = xre_s1_{%irfname}/xre_0_{%irfname}*100-100
	series irf_ncr_m_{%irfname} = m_s1_{%irfname}/m_0_{%irfname}*100-100
	
	series irf_rtwi_ncr_{%irfname} = ncr_s2_{%irfname}-ncr_0_{%irfname} 
	series irf_rtwi_y_{%irfname} = y_s2_{%irfname}/y_0_{%irfname}*100-100
	series irf_rtwi_u_{%irfname} = lur_s2_{%irfname}-lur_0_{%irfname}
	series irf_rtwi_p_{%irfname} = pi_ptm_s2_{%irfname}-pi_ptm_0_{%irfname}
	series irf_rtwi_w_{%irfname} = pi_pw_s2_{%irfname}-pi_pw_0_{%irfname}
	series irf_rtwi_rtwi_{%irfname} = rtwi_s2_{%irfname}/rtwi_0_{%irfname}*100-100
	
	series irf_ph_ph_{%irfname} = ph_s3_{%irfname}/ph_0_{%irfname}*100-100
	series irf_ph_y_{%irfname}    = y_s3_{%irfname}/y_0_{%irfname}*100 -100
	series irf_ph_p_{%irfname}    = pi_ptm_s3_{%irfname} - pi_ptm_0_{%irfname}
	series irf_ph_u_{%irfname}    = lur_s3_{%irfname} - lur_0_{%irfname}
	series irf_ph_rc_{%irfname}   = rc_s3_{%irfname}/rc_0_{%irfname}*100-100
	series irf_ph_ncr_{%irfname} = ncr_s3_{%irfname} - ncr_0_{%irfname}
next

' ******** Monetary Policy Shock **********************

smpl 2019 2028

' Monetary policy shock - aggregate variables
graph g_ncr_r irf_ncr_ncr_rba irf_ncr_ncr_git 0
graph g_ncr_y irf_ncr_y_rba irf_ncr_y_git 0
graph g_ncr_u irf_ncr_u_rba irf_ncr_u_git 0
graph g_ncr_p irf_ncr_p_rba irf_ncr_p_git 0
graph g_ncr_w irf_ncr_w_rba irf_ncr_w_git 0
graph g_ncr_rtwi irf_ncr_rtwi_rba irf_ncr_rtwi_git 0

g_ncr_r.addtext(t) "Cash Rate"
g_ncr_y.addtext(t) "GDP"
g_ncr_u.addtext(t) "Unemployment Rate"
g_ncr_p.addtext(t) "Trimmed Mean Inflation"
g_ncr_w.addtext(t) "Wages Growth"
g_ncr_rtwi.addtext(t) "Real TWI"

graph g_ncr_shock_1.merge g_ncr_r g_ncr_y g_ncr_u g_ncr_p g_ncr_w g_ncr_rtwi

show g_ncr_shock_1

' Monetary policy shock - expenditure components
graph g_ncr_rc irf_ncr_rc_rba irf_ncr_rc_git 0
graph g_ncr_id irf_ncr_id_rba irf_ncr_id_git 0
graph g_ncr_ib irf_ncr_ib_rba irf_ncr_ib_git 0
graph g_ncr_xnre irf_ncr_xnre_rba irf_ncr_xnre_git 0
graph g_ncr_xre irf_ncr_xre_rba irf_ncr_xre_git 0
graph g_ncr_m irf_ncr_m_rba irf_ncr_m_git 0

g_ncr_rc.addtext(t) "Consumption"
g_ncr_id.addtext(t) "Dwelling Investment"
g_ncr_ib.addtext(t) "Business Investment"
g_ncr_xnre.addtext(t) "Non-resource exports"
g_ncr_xre.addtext(t) "Resource exports"
g_ncr_m.addtext(t) "Imports"

graph g_ncr_shock_2.merge g_ncr_rc g_ncr_id g_ncr_ib g_ncr_xnre g_ncr_xre g_ncr_m

show g_ncr_shock_2

' ******** Exchange Rate Shock **********************

'Exchange rate shock - aggregate variables
graph g_rtwi_r irf_rtwi_ncr_rba irf_rtwi_ncr_git 0
graph g_rtwi_y irf_rtwi_y_rba irf_rtwi_y_git 0
graph g_rtwi_u irf_rtwi_u_rba irf_rtwi_u_git 0
graph g_rtwi_p irf_rtwi_p_rba irf_rtwi_p_git 0
graph g_rtwi_w irf_rtwi_w_rba irf_rtwi_w_git 0
graph g_rtwi_rtwi irf_rtwi_rtwi_rba irf_rtwi_rtwi_git 0

g_rtwi_r.addtext(t) "Cash Rate"
g_rtwi_y.addtext(t) "GDP"
g_rtwi_u.addtext(t) "Unemployment Rate"
g_rtwi_p.addtext(t) "Trimmed Mean Inflation"
g_rtwi_w.addtext(t) "Wages Growth"
g_rtwi_rtwi.addtext(t) "Real TWI"

graph g_rtwi_shock_1.merge g_rtwi_rtwi g_rtwi_y g_rtwi_u g_rtwi_p g_rtwi_w g_rtwi_r

show g_rtwi_shock_1

' ******** Housing Price Shock **********************

'Exchange rate shock - aggregate variables
graph g_ph_ph irf_ph_ph_rba irf_ph_ph_git 0
graph g_ph_y irf_ph_y_rba irf_ph_y_git 0
graph g_ph_p irf_ph_p_rba irf_ph_p_git 0
graph g_ph_u irf_ph_u_rba irf_ph_u_git 0
graph g_ph_rc irf_ph_rc_rba irf_ph_rc_git 0
graph g_ph_ncr irf_ph_ncr_rba irf_ph_ncr_git 0

g_rtwi_r.addtext(t) "House Prices"
g_rtwi_y.addtext(t) "GDP"
g_rtwi_p.addtext(t) "Trimmed Mean Inflation"
g_rtwi_u.addtext(t) "Unemployment Rate"
g_rtwi_w.addtext(t) "Real Consumption"
g_rtwi_rtwi.addtext(t) "Cash Rate"

graph g_ph_shock_1.merge g_ph_ph g_ph_y g_ph_p g_ph_u g_ph_rc g_ph_ncr

show g_ph_shock_1

