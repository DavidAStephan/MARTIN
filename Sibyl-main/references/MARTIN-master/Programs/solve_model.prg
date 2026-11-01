''******************************************************************************************''
'' Test Identities
''  
''******************************************************************************************
if !test_identities=1 then
	smpl %solve_start %nataccs_end
	{%modelname}.addassign(i,c) @identity
	{%modelname}.addinit(v=n) @identity
	string ident = {%modelname}.@identity
	string ident_a = @wcross(ident,"_a")
	show {ident_a}
	stop
endif

''******************************************************************************************
''
'' Solve Baseline (check model is balanced in history (returns actuals)
'	and create add-factors for forecast
''  
''******************************************************************************************
smpl %solve_start %nataccs_end
{%modelname}.scenario "baseline"

'Initialize Add-Factors
string afs=""

freeze(__model,mode=overwrite) martin.text
delete(noerr) ___modcheck
__model.svector ___modcheck

for !i=1 to @rows(___modcheck)
	svector tempsvector=@wsplit(___modcheck(!i))
	%eqname=tempsvector(1)

	if @instr(%eqname,"@ADD") then
		afs = afs + " " + tempsvector(2)
	endif
next

if @wcount(afs)>0 then
	{%modelname}.addinit(v=n) {afs} 'set add factors so fitted value + af = actual
endif

{%modelname}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)

''******************************************************************************************''
'' Extend Historical Add-Factors into the Forecast Period
''  
''******************************************************************************************
smpl %nataccs_end+1 %solve_end

if @wcount(afs)>0 then
	for %var {afs}
	     	series {%var}_a={%var}_a(-1)*-0.5
	Next
endif

''******************************************************************************************
'Create New Scenario
setmaxerrs 2
{%modelname}.scenario(n,a=2,i="baseline",c) "forecast"
{%modelname}.scenario "forecast"
{%modelname}.exclude(actexist=t) 'Ragged Dataset (eg. often have interest rates / lmkt data before GDP)
seterrcount 0
setmaxerrs 1

smpl %solve_start %solve_end
{%modelname}.solve(s=d,d=d,o=g,i=a,c=1e-6,f=t,v=t,g=n)
'{%modelname}.msg

''******************************************************************************************


