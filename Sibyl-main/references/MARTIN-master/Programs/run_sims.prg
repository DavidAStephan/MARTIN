''*******************************************************************
'Run Sims for All Model Variables
''*******************************************************************
logmode all
' Set current eviews directory
close @wf
%path = @runpath
cd %path

' Load workfile
load .\..\output\solvedmodel.wf1

'Add Non-Resource Exports
series xnre = x - xre
MARTIN.append @identity xnre = x - xre
MARTIN.update

' Define model name
%modelname = "martin"

''*******************************************************************

' Set simulation dates
%shock_start = "2019:3" 			' Start date of shocks
string sim1_start = "2019Q3"		' Start date of simulation
string sim1_end  = "2030Q2"		' End of simulation
string last_data = "2019Q2"

smpl @all

''*******************************************************************
'Solve Baseline  
''*******************************************************************
' Simulate model to compute baseline
smpl {sim1_start} {sim1_end}
{%modelname}.scenario "baseline"
{%modelname}.solve

''*******************************************************************
'Endogenous Variables Shock
''*******************************************************************
string endoshocks = {%modelname}.@stochastic

!i=0
for %var {endoshocks}
	!i=!i+1
	if !i<10 then
		%scn="00"+@str(!i)
	else
	if !i<100 then
		%scn="0"+@str(!i)
	else
		%scn=@str(!i)
	endif
	endif

	{%modelname}.scenario(n,a={%scn},i="baseline",c) "Scenario Endo" + " " + @str(!i)
	{%modelname}.scenario "Scenario Endo" + " " + @str(!i)
	{%modelname}.exclude {%excludes}

	smpl @all
	%shockvar=%var

	series {%shockvar}_hold = {%shockvar}_0
	series {%shockvar}_a_hold = {%shockvar}_a	

	'introducing shocks
	smpl {sim1_start} {sim1_end}
	series {%shockvar} = {%shockvar}_0 + 0.01*{%shockvar}_0

	'calculating new addfactor values : introducing shocks to the model through new addfactors
	smpl {sim1_start} {sim1_end}
	{%modelname}.override(m) {%shockvar}_a
	{%modelname}.addinit(v = n) {%shockvar}		'initialize add factors
	series {%shockvar} = {%shockvar}_hold		'retaining the original series using _hold

	smpl {sim1_start} {sim1_end}
	setmaxerrs 2
	!old_count = @errorcount
	{%modelname}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)
	!new_count = @errorcount
	if !new_count > !old_count then	
		logmsg Solve Crashed During Scenario Endog !i
	endif
	clearerrs
	setmaxerrs 1
	
	'Return series to hold values 
	series {%shockvar} = {%shockvar}_hold
	series {%shockvar}_a	= {%shockvar}_a_hold

	%shocknames = %shocknames + " " + %scn
	%chartnames = %chartnames  + " " + %var

next

''*******************************************************************

smpl {last_data} {sim1_end}
string s_charts = %chartnames
svector sv_charts = @wsplit(s_charts)
!z=0

for %shock {%shocknames}
	!z=!z+1

	delete(noerr) {%shock}
	spool __{%shock}
	%temp = sv_charts(!z)
	if @vernum>=10 then
		__{%shock}.title Shock to {%temp}
	endif

	' Responses -> aggregate variables
	delete(noerr) g_r g_y g_u g_p g_w g_rtwi g_shock_1
	graph g_r ncr_{%shock}-ncr_0 0*ncr_0
	graph g_y y_{%shock}/y_0*100-100 0*y_0
	graph g_u lur_{%shock}-lur_0 0*lur_0
	graph g_p @pc(ptm_{%shock})-@pc(ptm_0) 0*ptm_0
	graph g_w @PC(pw_{%shock})-@PC(pw_0) 0*pw_0 
	graph g_rtwi rtwi_{%shock}/rtwi_0*100-100 0*rtwi_0
	
	g_r.addtext(t) "Cash Rate"
	g_y.addtext(t) "GDP"
	g_u.addtext(t) "Unemployment Rate"
	g_p.addtext(t) "Trimmed Mean Inflation"
	g_w.addtext(t) "Wages Growth"
	g_rtwi.addtext(t) "Real TWI"
		
	graph g_shock_1.merge g_r g_y g_u g_p g_w g_rtwi
	__{%shock}.append g_shock_1
	
	' Responses -> expenditure components
	delete(noerr) g_rc g_id g_ib g_xnre g_xre g_m g_shock_2
	graph g_rc rc_{%shock}/rc_0*100-100 0*rc_0
	graph g_id id_{%shock}/id_0*100-100 0*id_0
	graph g_ib ib_{%shock}/ib_0*100-100 0*ib_0
	graph g_xnre xnre_{%shock}/xnre_0*100-100 0*xnre_0
	graph g_xre xre_{%shock}/xre_0*100-100 0*xre_0
	graph g_m m_{%shock}/m_0*100-100 0*m_0
	
	g_rc.addtext(t) "Consumption"
	g_id.addtext(t) "Dwelling Investment"
	g_ib.addtext(t) "Business Investment"
	g_xnre.addtext(t) "Non-resource exports"
	g_xre.addtext(t) "Resource exports"
	g_m.addtext(t) "Imports"
	
	graph g_shock_2.merge g_rc g_id g_ib g_xnre g_xre g_m
	__{%shock}.append g_shock_2

next

show sv_charts


