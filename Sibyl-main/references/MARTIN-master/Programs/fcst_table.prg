delete(noerr) _smp
table _smp

!startdate = @dateval("2020q4")
%fcst_hist = @str(!startdate)
!enddate = @dateval("2023q2")
!num = @datediff(!enddate, !startdate, "Q")+1

_smp(1,1) = "Forecast Table -- 'Baseline' Scenario"
_smp(2,1) = "Percentage change over year to quarter shown"

_smp(5,1) = "Gross domestic product"
_smp(6,1) = "Household consumption"
_smp(7,1) = "Dwelling Investment"
_smp(8,1) = "Business Investment"
_smp(9,1) = "Public demand"
_smp(10,1) = "Gross national expenditure"
_smp(11,1) = "Imports"
_smp(12,1) = "Exports"
_smp(13,1) = "Real household disposable income"
_smp(14,1) = "Terms of trade"
_smp(15,1) = "USA GDP"
_smp(16,1) = "Unemployment rate (quarterly, %)"
_smp(17,1) = "Employment"
_smp(18,1) = "Wage price index"
_smp(19,1) = "Nominal average earnings per hour"
_smp(20,1) = "Trimmed mean inflation"
_smp(21,1) = "Consumer Price Index"

!z=1
for !i=1 to !num step 2
	!z=!z+1
	%tempQ = @datestr(@dateadd(!startdate, !i-1, "Q"), "Q")

	if %tempQ = 4 then
		_smp(3,!z) = "Dec"
	else
		_smp(3,!z) = "Jun"
	endif
	
	_smp(4,!z) = @datestr(@dateadd(!startdate, !i-1, "Q"), "YYYY")

next

smpl @all

!x=4
for %var Y RC ID IB G GNE M X HDY TOT WY LUR LE PW PAE PTM P
	!x=!x+1
	!z=0
	for !y=2 to 7

		!z=!z+2
		%tempQQ = @datestr(@dateadd(!startdate, !z-2, "Q"), "YYYY Q")	

		if %var<>"LUR" then
			series tempvalues = @pcy({%var}_2)
		else
			series tempvalues = {%var}_2
		endif	
		_smp(!x,!y) = @elem(tempvalues,%tempQQ)

	next

next

smpl @all

_smp.setjust(A) left
_smp.setjust(B:G) right
_smp.setwidth(A) 35
_smp.setformat(B:G) f.1
_smp.setfont(A1:G4) b


