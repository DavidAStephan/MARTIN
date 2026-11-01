'Compare Databases from RBA Public MARTIN and Github Version
'
' Created David Stephan
' 5 November 2019
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
%start = "1985Q1"		' Start date of simulation
%end  = "2019Q1"		' End of simulation

smpl @all

'====================================

wfselect solvedmodel
%modvars=martin.@endoglist

setmaxerrs 100
for %var {%modvars}
	copy(noerr) martin_public::untitled\{%var} solvedmodel::*_rba
next
clearerrs
setmaxerrs 1

'======================================================================
spool data_compare
smpl %start %end

logmode l
%levelvars="LOKLAG LURGAP N10R N2R NBRSP NHS NHSR NSD NSP NV V PI_E RSTAR WR2R V SD TDLLHPP TLUR WRR WRSP R2R RBR RCR W2RSP"

for %var {%modvars}

	if @isobject(%var+"_RBA") then
		if @wfindnc(%levelvars,%var) then
			graph __g.line {%var} {%var}_RBA
			data_compare.append __g	
			delete(noerr) __g
		else
			graph __g.line @PCY({%var}) @PCY({%var}_RBA)
			data_compare.append __g	
			delete(noerr) __g
		endif
	endif

next

show data_compare
