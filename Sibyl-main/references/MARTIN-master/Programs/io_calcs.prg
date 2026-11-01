'***********************************************************************
' Calcualte Import Propensity of Final Demand Components 
' Using Input-Output Tables of the National Accounts (ABS 5209)
' Reference: Lovicu G-P (2017), RBA
'***********************************************************************

close @all
%path = @runpath
cd %path 

'***********************************************************************

%datapath = %path + "absdata\IO_tables\"

'Create Workfile'
wfcreate(wf="io_calcs", page="iad") q 1959q3 2099q4

'Loop Over ABS Input-Output Tables for the following years (1999 -> 2017)

%years="1999 2002 2005 2006 2007 2008 2009 2010 2013 2014 2015 2016 2017"

for %year {%years}

	'------------------------------------------------
	'Import Input-Output Tables
	'------------------------------------------------
	
		'TABLE3 - IMPORTS - SUPPLY BY PRODUCT GROUP AND INPUTS BY INDUSTRY AND FINAL USE CATEGORY
			'Imports -> Intermediate and Final Use 
			%tb3path = %datapath + %year + "\" + "520905500103" + "_" + %year+".xls" 
			if %year="2017" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DN4:DT117" 
			else
			if %year="2016" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DN13:DT126"
			else
			if %year="2015" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DN13:DT126"
			else
			if %year="2014" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DN13:DT126"
			else
			if %year="2013" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DN13:DT126"
			else
			if %year="2010" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DN13:DT126" 
			else
			if %year="2009" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DK13:DQ123" 
			else
			if %year="2008" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DK13:DQ123" 
			else
			if %year="2007" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DK13:DQ123" 
			else
			if %year="2006" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DI13:DO121" 
			else
			if %year="2005" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DI13:DO121" 
			else
			if %year="2002" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DI12:DO120" 
			else
			if %year="1999" then
				importtbl(name=table3_{%year}) {%tb3path} range="Table 3!DF12:DL117" 
			endif	
			endif
			endif 
			endif
			endif
			endif
			endif
			endif
			endif			
			endif
			endif
			endif
			endif
	
		'TABLE 5 - INDUSTRY BY INDUSTRY FLOW TABLE (DIRECT ALLOCATION OF IMPORTS)
			'Domestic Final Demand
			%tb5path = %datapath + %year + "\" + "520905500105" + "_" + %year+".xls" 
			if %year="2017" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DN4:DT117" 
			else
			if %year="2016" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DN13:DT126"
			else
			if %year="2015" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DN13:DT126"
			else
			if %year="2014" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DN13:DT126"
			else
			if %year="2013" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DN13:DT126"
			else
			if %year="2010" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DN13:DT126"
			else

			if %year="2009" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DK13:DQ123"
			else
			if %year="2008" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DK13:DQ123"
			else
			if %year="2007" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DK13:DQ123"
			else

			if %year="2006" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DI13:DO121"
			else
			if %year="2005" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DI14:DO122"
			else
			if %year="2002" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DI13:DO121"
			else
			if %year="1999" then
				importtbl(name=table5_{%year}) {%tb5path} range="Table 5!DF12:DL117"
			endif	
			endif 
			endif
			endif
			endif
			endif
			endif
			endif
			endif			
			endif
			endif
			endif
			endif

		'TABLE 6 - DIRECT REQUIREMENT COEFFICIENTS (DIRECT ALLOCATION OF IMPORTS)
			'Domestic Direct Requirement Coefficients
			%tb6path = %datapath + %year + "\" + "520905500106" + "_" + %year+".xls" 
			if %year="2017" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C4:DL117"
			else
			if %year="2016" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DL126" 
			else
			if %year="2015" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DL126" 
			else
			if %year="2014" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DL126" 
			else
			if %year="2013" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DL126" 
			else
			if %year="2010" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DL126" 
			else
			if %year="2009" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DI123" 
			else
			if %year="2008" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DI123" 
			else
			if %year="2007" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DI123" 
			else
			if %year="2006" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DG121" 
			else
			if %year="2005" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C14:DG122" 
			else
			if %year="2002" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C13:DG121" 
			else
			if %year="1999" then
				importtbl(name=table6_{%year}) {%tb6path} range="Table 6!C12:DD117" 
			endif	
			endif 
			endif
			endif
			endif
			endif
			endif
			endif			
			endif
			endif
			endif
			endif
			endif

		'TABLE 9 - DIRECT REQUIREMENT COEFFICIENTS (INDIRECT ALLOCATION OF IMPORTS)
			'Table 9 - Table 6 = Indirect Requirements Coefs Between Industries
			%tb9path = %datapath + %year + "\" + "520905500109" + "_" + %year+".xls" 
			if %year="2017" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C4:DL117"
			else
			if %year="2016" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DL126"	
			else
			if %year="2015" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DL126"		
			else
			if %year="2014" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DL126"		
			else
			if %year="2013" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DL126"		
			else
			if %year="2010" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DL126"		
			else
			if %year="2009" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DI123"		
			else
			if %year="2008" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DI123"		
			else
			if %year="2007" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DI123"		
			else
			if %year="2006" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DG121"		
			else
			if %year="2005" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C14:DG122"		
			else
			if %year="2002" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C13:DG121"		
			else
			if %year="1999" then
				importtbl(name=table9_{%year}) {%tb9path} range="Table 9!C12:DD117" 
			endif	
			endif 
			endif
			endif
			endif
			endif
			endif
			endif
			endif			
			endif
			endif
			endif
			endif

	'------------------------------------------------
	'Parameters
	'------------------------------------------------
	
	!s = @rows(table3_{%year}) 'number of sectors in table3
	!n3 = @columns(table3_{%year}) 'total columns (FD + inter industry) in table3
	!k = 7 'number of final demand components
	
	'------------------------------------------------
	'Calculations
	'------------------------------------------------
	
	'*************************************
	'Calculate Final Demand Imports
	'*************************************
		ttom(table3_{%year},Fm_{%year})
		matrix Mdir_{%year} = Fm_{%year}
	
	'*************************************
	'Leontief Inverse Matrix
	'*************************************
		'Scale table 6 values to sum to 1 not 100
		ttom(table6_{%year},m_table6_{%year})
		m_table6_{%year} = m_table6_{%year}/100
		
		matrix(!s,!s) LAd_{%year}
		LAd_{%year} = @inverse((@identity(!s)-m_table6_{%year}))
	
	'*************************************
	'Domestic Output Matrix
	'*************************************	
		'Domestic Final Demand Matrix
		ttom(table5_{%year},FD_{%year})
	
		'Domestic Output Matrix
		matrix X_{%year} = LAd_{%year}*Fd_{%year}
	
	'*************************************
	'Intermediate Imports
	'*************************************	
		'Scale table 9 values to sum to 1 not 100
		ttom(table9_{%year},m_table9_{%year})
		m_table9_{%year} = m_table9_{%year}/100
	
		'Imported Direct Requirement for intermediate use
		matrix(!s,!s) Am_{%year} = m_table9_{%year} - m_table6_{%year}
	
		'Indirect Imports of Final Demand
		matrix(!s,!k) Mind_{%year} = Am_{%year}*X_{%year}
	
	'*************************************
	'Total Imports
	'*************************************	
	
		matrix M_{%year} = Mdir_{%year} + Mind_{%year}
	
	'*************************************
	'Import Content of Final Demand
	'************************************
	
	for !i=1 to !k
		scalar omega_{%year}_{!i} = (@sum(@subextract(Mdir_{%year},1,!i,!s,!i)) + @sum(@subextract(Mind_{%year},1,!i,!s,!i))) / (@sum(@subextract(Fm_{%year},1,!i,!s,!i)) + @sum(@subextract(Fd_{%year},1,!i,!s,!i)))
	next
	
next

'----------------------------------------------------------------
'Construct the Weighting Series for the Model
'---------------------------------------------------------------


	'*************************************
	''Create Empty Series for Cons, Cons Govt, Investment, Govt Investment and Exports
	'************************************
	series iad_w_c
	series iad_w_gc
	series iad_w_i
	series iad_w_gi
	series iad_w_x

	smpl 2017q2 2017q2
	iad_w_c = omega_2017_1
	iad_w_gc = omega_2017_2
	iad_w_i = omega_2017_3
	iad_w_gi = omega_2017_5
	iad_w_x = omega_2017_7
	
	smpl 2016q2 2016q2
	iad_w_c = omega_2016_1
	iad_w_gc = omega_2016_2
	iad_w_i = omega_2016_3
	iad_w_gi = omega_2016_5
	iad_w_x = omega_2016_7
	
	smpl 2015q2 2015q2
	iad_w_c = omega_2015_1
	iad_w_gc = omega_2015_2
	iad_w_i = omega_2015_3
	iad_w_gi = omega_2015_5
	iad_w_x = omega_2015_7
	
	smpl 2014q2 2014q2
	iad_w_c = omega_2014_1
	iad_w_gc = omega_2014_2
	iad_w_i = omega_2014_3
	iad_w_gi = omega_2014_5
	iad_w_x = omega_2014_7
	
	smpl 2013q2 2013q2
	iad_w_c = omega_2013_1
	iad_w_gc = omega_2013_2
	iad_w_i = omega_2013_3
	iad_w_gi = omega_2013_5
	iad_w_x = omega_2013_7
	
	smpl 2010q2 2010q2
	iad_w_c = omega_2010_1
	iad_w_gc = omega_2010_2
	iad_w_i = omega_2010_3
	iad_w_gi = omega_2010_5
	iad_w_x = omega_2010_7
	
	smpl 2009q2 2009q2
	iad_w_c = omega_2009_1
	iad_w_gc = omega_2009_2
	iad_w_i = omega_2009_3
	iad_w_gi = omega_2009_5
	iad_w_x = omega_2009_7
	
	smpl 2008q2 2008q2
	iad_w_c = omega_2008_1
	iad_w_gc = omega_2008_2
	iad_w_i = omega_2008_3
	iad_w_gi = omega_2008_5
	iad_w_x = omega_2008_7
	
	smpl 2007q2 2007q2
	iad_w_c = omega_2007_1
	iad_w_gc = omega_2007_2
	iad_w_i = omega_2007_3
	iad_w_gi = omega_2007_5
	iad_w_x = omega_2007_7
	
	smpl 2006q2 2006q2
	iad_w_c = omega_2006_1
	iad_w_gc = omega_2006_2
	iad_w_i = omega_2006_3
	iad_w_gi = omega_2006_5
	iad_w_x = omega_2006_7
	
	smpl 2005q2 2005q2
	iad_w_c = omega_2005_1
	iad_w_gc = omega_2005_2
	iad_w_i = omega_2005_3
	iad_w_gi = omega_2005_5
	iad_w_x = omega_2005_7
	
	smpl 2002q2 2002q2
	iad_w_c = omega_2002_1
	iad_w_gc = omega_2002_2
	iad_w_i = omega_2002_3
	iad_w_gi = omega_2002_5
	iad_w_x = omega_2002_7
	
	smpl 1999q2 1999q2
	iad_w_c = omega_1999_1
	iad_w_gc = omega_1999_2
	iad_w_i = omega_1999_3
	iad_w_gi = omega_1999_5
	iad_w_x = omega_1999_7

'	smpl 2017q2 2017q2
'	iad_w_c = omega_2017_1/(omega_2017_1+omega_2017_2+omega_2017_3+omega_2017_5+omega_2017_7)
'	iad_w_gc = omega_2017_2/(omega_2017_1+omega_2017_2+omega_2017_3+omega_2017_5+omega_2017_7)
'	iad_w_i = omega_2017_3/(omega_2017_1+omega_2017_2+omega_2017_3+omega_2017_5+omega_2017_7)
'	iad_w_gi = omega_2017_5/(omega_2017_1+omega_2017_2+omega_2017_3+omega_2017_5+omega_2017_7)
'	iad_w_x = omega_2017_7/(omega_2017_1+omega_2017_2+omega_2017_3+omega_2017_5+omega_2017_7)
'	
'	smpl 2016q2 2016q2
'	iad_w_c = omega_2016_1/(omega_2016_1+omega_2016_2+omega_2016_3+omega_2016_5+omega_2016_7)
'	iad_w_gc = omega_2016_2/(omega_2016_1+omega_2016_2+omega_2016_3+omega_2016_5+omega_2016_7)
'	iad_w_i = omega_2016_3/(omega_2016_1+omega_2016_2+omega_2016_3+omega_2016_5+omega_2016_7)
'	iad_w_gi = omega_2016_5/(omega_2016_1+omega_2016_2+omega_2016_3+omega_2016_5+omega_2016_7)
'	iad_w_x = omega_2016_7/(omega_2016_1+omega_2016_2+omega_2016_3+omega_2016_5+omega_2016_7)
'	
'	smpl 2015q2 2015q2
'	iad_w_c = omega_2015_1/(omega_2015_1+omega_2015_2+omega_2015_3+omega_2015_5+omega_2015_7)
'	iad_w_gc = omega_2015_2/(omega_2015_1+omega_2015_2+omega_2015_3+omega_2015_5+omega_2015_7)
'	iad_w_i = omega_2015_3/(omega_2015_1+omega_2015_2+omega_2015_3+omega_2015_5+omega_2015_7)
'	iad_w_gi = omega_2015_5/(omega_2015_1+omega_2015_2+omega_2015_3+omega_2015_5+omega_2015_7)
'	iad_w_x = omega_2015_7/(omega_2015_1+omega_2015_2+omega_2015_3+omega_2015_5+omega_2015_7)
'	
'	smpl 2014q2 2014q2
'	iad_w_c = omega_2014_1/(omega_2014_1+omega_2014_2+omega_2014_3+omega_2014_5+omega_2014_7)
'	iad_w_gc = omega_2014_2/(omega_2014_1+omega_2014_2+omega_2014_3+omega_2014_5+omega_2014_7)
'	iad_w_i = omega_2014_3/(omega_2014_1+omega_2014_2+omega_2014_3+omega_2014_5+omega_2014_7)
'	iad_w_gi = omega_2014_5/(omega_2014_1+omega_2014_2+omega_2014_3+omega_2014_5+omega_2014_7)
'	iad_w_x = omega_2014_7/(omega_2014_1+omega_2014_2+omega_2014_3+omega_2014_5+omega_2014_7)
'	
'	smpl 2013q2 2013q2
'	iad_w_c = omega_2013_1/(omega_2013_1+omega_2013_2+omega_2013_3+omega_2013_5+omega_2013_7)
'	iad_w_gc = omega_2013_2/(omega_2013_1+omega_2013_2+omega_2013_3+omega_2013_5+omega_2013_7)
'	iad_w_i = omega_2013_3/(omega_2013_1+omega_2013_2+omega_2013_3+omega_2013_5+omega_2013_7)
'	iad_w_gi = omega_2013_5/(omega_2013_1+omega_2013_2+omega_2013_3+omega_2013_5+omega_2013_7)
'	iad_w_x = omega_2013_7/(omega_2013_1+omega_2013_2+omega_2013_3+omega_2013_5+omega_2013_7)
'	
'	smpl 2010q2 2010q2
'	iad_w_c = omega_2010_1/(omega_2010_1+omega_2010_2+omega_2010_3+omega_2010_5+omega_2010_7)
'	iad_w_gc = omega_2010_2/(omega_2010_1+omega_2010_2+omega_2010_3+omega_2010_5+omega_2010_7)
'	iad_w_i = omega_2010_3/(omega_2010_1+omega_2010_2+omega_2010_3+omega_2010_5+omega_2010_7)
'	iad_w_gi = omega_2010_5/(omega_2010_1+omega_2010_2+omega_2010_3+omega_2010_5+omega_2010_7)
'	iad_w_x = omega_2010_7/(omega_2010_1+omega_2010_2+omega_2010_3+omega_2010_5+omega_2010_7)
'	
'	smpl 2009q2 2009q2
'	iad_w_c = omega_2009_1/(omega_2009_1+omega_2009_2+omega_2009_3+omega_2009_5+omega_2009_7)
'	iad_w_gc = omega_2009_2/(omega_2009_1+omega_2009_2+omega_2009_3+omega_2009_5+omega_2009_7)
'	iad_w_i = omega_2009_3/(omega_2009_1+omega_2009_2+omega_2009_3+omega_2009_5+omega_2009_7)
'	iad_w_gi = omega_2009_5/(omega_2009_1+omega_2009_2+omega_2009_3+omega_2009_5+omega_2009_7)
'	iad_w_x = omega_2009_7/(omega_2009_1+omega_2009_2+omega_2009_3+omega_2009_5+omega_2009_7)
'	
'	smpl 2008q2 2008q2
'	iad_w_c = omega_2008_1/(omega_2008_1+omega_2008_2+omega_2008_3+omega_2008_5+omega_2008_7)
'	iad_w_gc = omega_2008_2/(omega_2008_1+omega_2008_2+omega_2008_3+omega_2008_5+omega_2008_7)
'	iad_w_i = omega_2008_3/(omega_2008_1+omega_2008_2+omega_2008_3+omega_2008_5+omega_2008_7)
'	iad_w_gi = omega_2008_5/(omega_2008_1+omega_2008_2+omega_2008_3+omega_2008_5+omega_2008_7)
'	iad_w_x = omega_2008_7/(omega_2008_1+omega_2008_2+omega_2008_3+omega_2008_5+omega_2008_7)
'	
'	smpl 2007q2 2007q2
'	iad_w_c = omega_2007_1/(omega_2007_1+omega_2007_2+omega_2007_3+omega_2007_5+omega_2007_7)
'	iad_w_gc = omega_2007_2/(omega_2007_1+omega_2007_2+omega_2007_3+omega_2007_5+omega_2007_7)
'	iad_w_i = omega_2007_3/(omega_2007_1+omega_2007_2+omega_2007_3+omega_2007_5+omega_2007_7)
'	iad_w_gi = omega_2007_5/(omega_2007_1+omega_2007_2+omega_2007_3+omega_2007_5+omega_2007_7)
'	iad_w_x = omega_2007_7/(omega_2007_1+omega_2007_2+omega_2007_3+omega_2007_5+omega_2007_7)
'	
'	smpl 2006q2 2006q2
'	iad_w_c = omega_2006_1/(omega_2006_1+omega_2006_2+omega_2006_3+omega_2006_5+omega_2006_7)
'	iad_w_gc = omega_2006_2/(omega_2006_1+omega_2006_2+omega_2006_3+omega_2006_5+omega_2006_7)
'	iad_w_i = omega_2006_3/(omega_2006_1+omega_2006_2+omega_2006_3+omega_2006_5+omega_2006_7)
'	iad_w_gi = omega_2006_5/(omega_2006_1+omega_2006_2+omega_2006_3+omega_2006_5+omega_2006_7)
'	iad_w_x = omega_2006_7/(omega_2006_1+omega_2006_2+omega_2006_3+omega_2006_5+omega_2006_7)
'	
'	smpl 2005q2 2005q2
'	iad_w_c = omega_2005_1/(omega_2005_1+omega_2005_2+omega_2005_3+omega_2005_5+omega_2005_7)
'	iad_w_gc = omega_2005_2/(omega_2005_1+omega_2005_2+omega_2005_3+omega_2005_5+omega_2005_7)
'	iad_w_i = omega_2005_3/(omega_2005_1+omega_2005_2+omega_2005_3+omega_2005_5+omega_2005_7)
'	iad_w_gi = omega_2005_5/(omega_2005_1+omega_2005_2+omega_2005_3+omega_2005_5+omega_2005_7)
'	iad_w_x = omega_2005_7/(omega_2005_1+omega_2005_2+omega_2005_3+omega_2005_5+omega_2005_7)
'	
'	smpl 2002q2 2002q2
'	iad_w_c = omega_2002_1/(omega_2002_1+omega_2002_2+omega_2002_3+omega_2002_5+omega_2002_7)
'	iad_w_gc = omega_2002_2/(omega_2002_1+omega_2002_2+omega_2002_3+omega_2002_5+omega_2002_7)
'	iad_w_i = omega_2002_3/(omega_2002_1+omega_2002_2+omega_2002_3+omega_2002_5+omega_2002_7)
'	iad_w_gi = omega_2002_5/(omega_2002_1+omega_2002_2+omega_2002_3+omega_2002_5+omega_2002_7)
'	iad_w_x = omega_2002_7/(omega_2002_1+omega_2002_2+omega_2002_3+omega_2002_5+omega_2002_7)
'	
'	smpl 1999q2 1999q2
'	iad_w_c = omega_1999_1/(omega_1999_1+omega_1999_2+omega_1999_3+omega_1999_5+omega_1999_7)
'	iad_w_gc = omega_1999_2/(omega_1999_1+omega_1999_2+omega_1999_3+omega_1999_5+omega_1999_7)
'	iad_w_i = omega_1999_3/(omega_1999_1+omega_1999_2+omega_1999_3+omega_1999_5+omega_1999_7)
'	iad_w_gi = omega_1999_5/(omega_1999_1+omega_1999_2+omega_1999_3+omega_1999_5+omega_1999_7)
'	iad_w_x = omega_1999_7/(omega_1999_1+omega_1999_2+omega_1999_3+omega_1999_5+omega_1999_7)

	'*************************************
	'''Splice Backwards Using Busierre
	'************************************
	'Busierre et al. (2013) values for C, C govt, INV, Exports (1985, 1990, 1995, 2000, 2005)
	!cp_1985=0.144368455
	!cp_1990=0.132989038
	!cp_1995=0.169620647
	!cp_2000=0.185925869
	!cp_2005=0.184094747
	
	!cg_1985=0.08999936
	!cg_1990=0.089725207
	!cg_1995=0.089908561
	!cg_2000=0.099576328
	!cg_2005=0.099214828
	
	!inv_1985=0.271494391
	!inv_1990=0.258787254
	!inv_1995=0.265391025
	!inv_2000=0.265974058
	!inv_2005=0.259804541
	
	!exp_1985=0.103707189
	!exp_1990=0.102847902
	!exp_1995=0.139913545
	!exp_2000=0.14142683
	!exp_2005=0.140155262
	
	'Scaling To Sum Weights to 1
'	!1985=!cp_1985+!cg_1985+!inv_1985+!exp_1985
'	!1990=!cp_1990+!cg_1990+!inv_1990+!exp_1990
'	!1995=!cp_1995+!cg_1995+!inv_1995+!exp_1995
'	!2000=!cp_2000+!cg_2000+!inv_2000+!exp_2000
'	!2005=!cp_2005+!cg_2005+!inv_2005+!exp_2005
'	
'	'Rescale Weights to Sum to 1
'	!cp_1985=!cp_1985/!1985
'	!cp_1990=!cp_1990/!1985
'	!cp_1995=!cp_1995/!1995
'	!cp_2000=!cp_2000/!2000
'	!cp_2005=!cp_2005/!2005
'
'	!cg_1985=!cg_1985/!1985
'	!cg_1990=!cg_1990/!1990
'	!cg_1995=!cg_1995/!1995
'	!cg_2000=!cg_2000/!2000
'	!cg_2005=!cg_2005/!2005
'	
'	!inv_1985=!inv_1985/!1985
'	!inv_1990=!inv_1990/!1990
'	!inv_1995=!inv_1995/!1995
'	!inv_2000=!inv_2000/!2000
'	!inv_2005=!inv_2005/!2005
'	
'	!exp_1985=!exp_1985/!1985
'	!exp_1990=!exp_1990/!1990
'	!exp_1995=!exp_1995/!1995
'	!exp_2000=!exp_2000/!2000
'	!exp_2005=!exp_2005/!2005

	'Backcast Values using Change in Values
	smpl 1995q2 1995q2
	iad_w_c = omega_1999_1+(!cp_1995-!cp_2000)
	iad_w_gc = omega_1999_2+(!cg_1995-!cg_2000)
	iad_w_i = omega_1999_3+(!inv_1995-!inv_2000)
	iad_w_gi = omega_1999_5+(!inv_1995-!inv_2000)
	iad_w_x = omega_1999_7+(!exp_1995-!exp_2000)
	
	smpl 1990q2 1990q2
	iad_w_c = @elem(iad_w_c,"1995q2") + (!cp_1990-!cp_1995)
	iad_w_gc = @elem(iad_w_gc,"1995q2")+(!cg_1990-!cg_1995)
	iad_w_i = @elem(iad_w_i,"1995q2") + (!inv_1990-!inv_1995)
	iad_w_gi = @elem(iad_w_gi,"1995q2") + (!inv_1990-!inv_1995)
	iad_w_x = @elem(iad_w_c,"1995q2")+(!exp_1990-!exp_1995)
	
	smpl 1985q2 1985q2
	iad_w_c = @elem(iad_w_c,"1990q2") + (!cp_1985-!cp_1990)
	iad_w_gc = @elem(iad_w_gc,"1990q2")+(!cg_1985-!cg_1990)
	iad_w_i = @elem(iad_w_i,"1990q2") + (!inv_1985-!inv_1990)
	iad_w_gi = @elem(iad_w_gi,"1990q2") + (!inv_1985-!inv_1990)
	iad_w_x = @elem(iad_w_c,"1990q2")+(!exp_1985-!exp_1990)

	'*************************************
	''Interpolate Missing Values
	'************************************
	'1985 to 1990	
		for !i=1 to 20
			smpl 1985q2+!i 1985q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"1990q2")/@elem(iad_w_c,"1985q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"1990q2")/@elem(iad_w_gc,"1985q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"1990q2")/@elem(iad_w_i,"1985q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"1990q2")/@elem(iad_w_gi,"1985q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"1990q2")/@elem(iad_w_x,"1985q2"))^(1/20)
		next

		'1990 to 1995
		for !i=1 to 20
			smpl 1990q2+!i 1990q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"1995q2")/@elem(iad_w_c,"1990q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"1995q2")/@elem(iad_w_gc,"1990q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"1995q2")/@elem(iad_w_i,"1990q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"1995q2")/@elem(iad_w_gi,"1990q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"1995q2")/@elem(iad_w_x,"1990q2"))^(1/20)
		next
	
		'1995 to 1999
		for !i=1 to 16
			smpl 1995q2+!i 1995q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"1999q2")/@elem(iad_w_c,"1995q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"1999q2")/@elem(iad_w_gc,"1995q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"1999q2")/@elem(iad_w_i,"1995q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"1999q2")/@elem(iad_w_gi,"1995q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"1999q2")/@elem(iad_w_x,"1995q2"))^(1/20)
		next

		'1999 to 2002
		for !i=1 to 12
			smpl 1999q2+!i 1999q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2002q2")/@elem(iad_w_c,"1999q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2002q2")/@elem(iad_w_gc,"1999q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2002q2")/@elem(iad_w_i,"1999q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2002q2")/@elem(iad_w_gi,"1999q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2002q2")/@elem(iad_w_x,"1999q2"))^(1/20)
		next

		'2002 to 2005
		for !i=1 to 12
			smpl 2002q2+!i 2005q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2005q2")/@elem(iad_w_c,"2002q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2005q2")/@elem(iad_w_gc,"2002q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2005q2")/@elem(iad_w_i,"2002q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2005q2")/@elem(iad_w_gi,"2002q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2005q2")/@elem(iad_w_x,"2002q2"))^(1/20)
		next

		'2005 to 2006
		for !i=1 to 4
			smpl 2005q2+!i 2005q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2006q2")/@elem(iad_w_c,"2005q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2006q2")/@elem(iad_w_gc,"2005q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2006q2")/@elem(iad_w_i,"2005q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2006q2")/@elem(iad_w_gi,"2005q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2006q2")/@elem(iad_w_x,"2005q2"))^(1/20)
		next

		'2006 to 2007
		for !i=1 to 4
			smpl 2006q2+!i 2006q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2007q2")/@elem(iad_w_c,"2006q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2007q2")/@elem(iad_w_gc,"2006q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2007q2")/@elem(iad_w_i,"2006q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2007q2")/@elem(iad_w_gi,"2006q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2007q2")/@elem(iad_w_x,"2006q2"))^(1/20)
		next

		'2007 to 2008
		for !i=1 to 4
			smpl 2007q2+!i 2007q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2008q2")/@elem(iad_w_c,"2007q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2008q2")/@elem(iad_w_gc,"2007q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2008q2")/@elem(iad_w_i,"2007q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2008q2")/@elem(iad_w_gi,"2007q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2008q2")/@elem(iad_w_x,"2007q2"))^(1/20)
		next

		'2008 to 2009
		for !i=1 to 4
			smpl 2008q2+!i 2008q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2009q2")/@elem(iad_w_c,"2008q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2009q2")/@elem(iad_w_gc,"2008q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2009q2")/@elem(iad_w_i,"2008q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2009q2")/@elem(iad_w_gi,"2008q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2009q2")/@elem(iad_w_x,"2008q2"))^(1/20)
		next

		'2009 to 2010
		for !i=1 to 4
			smpl 2009q2+!i 2009q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2010q2")/@elem(iad_w_c,"2009q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2010q2")/@elem(iad_w_gc,"2009q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2010q2")/@elem(iad_w_i,"2009q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2010q2")/@elem(iad_w_gi,"2009q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2010q2")/@elem(iad_w_x,"2009q2"))^(1/20)
		next	

		'2010 to 2013
		for !i=1 to 12
			smpl 2010q2+!i 2010q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2013q2")/@elem(iad_w_c,"2010q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2013q2")/@elem(iad_w_gc,"2010q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2013q2")/@elem(iad_w_i,"2010q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2013q2")/@elem(iad_w_gi,"2010q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2013q2")/@elem(iad_w_x,"2010q2"))^(1/20)
		next

		'2013 to 2014
		for !i=1 to 4
			smpl 2013q2+!i 2013q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2014q2")/@elem(iad_w_c,"2013q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2014q2")/@elem(iad_w_gc,"2013q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2014q2")/@elem(iad_w_i,"2013q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2014q2")/@elem(iad_w_gi,"2013q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2014q2")/@elem(iad_w_x,"2013q2"))^(1/20)
		next

		'2014 to 2015
		for !i=1 to 4
			smpl 2014q2+!i 2014q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2015q2")/@elem(iad_w_c,"2014q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2015q2")/@elem(iad_w_gc,"2014q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2015q2")/@elem(iad_w_i,"2014q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2015q2")/@elem(iad_w_gi,"2014q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2015q2")/@elem(iad_w_x,"2014q2"))^(1/20)
		next

		'2015 to 2016
		for !i=1 to 4
			smpl 2015q2+!i 2015q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2016q2")/@elem(iad_w_c,"2015q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2016q2")/@elem(iad_w_gc,"2015q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2016q2")/@elem(iad_w_i,"2015q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2016q2")/@elem(iad_w_gi,"2015q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2016q2")/@elem(iad_w_x,"2015q2"))^(1/20)
		next

		'2016 to 2017
		for !i=1 to 4
			smpl 2016q2+!i 2016q2+!i 
			iad_w_c = iad_w_c(-1) * (@elem(iad_w_c,"2017q2")/@elem(iad_w_c,"2016q2"))^(1/20)
			iad_w_gc = iad_w_gc(-1) * (@elem(iad_w_gc,"2017q2")/@elem(iad_w_gc,"2016q2"))^(1/20)
			iad_w_i = iad_w_i(-1) * (@elem(iad_w_i,"2017q2")/@elem(iad_w_i,"2016q2"))^(1/20)
			iad_w_gi = iad_w_gi(-1) * (@elem(iad_w_gi,"2017q2")/@elem(iad_w_gi,"2016q2"))^(1/20)
			iad_w_x = iad_w_x(-1) * (@elem(iad_w_x,"2017q2")/@elem(iad_w_x,"2016q2"))^(1/20)
		next

'---------------------------------------------------------------------------------------------------------------
'Extend IAD Variables into Forecast Period
'---------------------------------------------------------------------------------------------------------------
smpl @all

'Extend and backcast
%iadvars="IAD_W_C IAD_W_GC IAD_W_I IAD_W_GI IAD_W_X"
for %var {%iadvars}
	smpl @all
	!obs = @obs({%var})
	smpl if {%var}<>na
	%firstdate=@otods(1)
	%lastdate=@otods(!obs)
	smpl @first %firstdate
	{%var} = @elem({%var},%firstdate)
	smpl %lastdate @last
	{%var}={%var}(-1)
next

smpl @all

'Scale IAD Variables so Sum to 1
for !i=1 to (@obs(iad_w_c))
	smpl 1959q2+!i 1959q2+!i
	%datenow = @otod(!i)
	!sum=(@elem(IAD_W_C,%datenow)+@elem(IAD_W_GC,%datenow)+@eleM(IAD_W_I,%datenow)+@elem(IAD_W_GI,%datenow)+@elem(IAD_W_X,%datenow))
	for %var {%iadvars}
		{%var}={%var}/!sum
	next
next

smpl @all

'------------------------------------------------
'Clean-up Workfile
'------------------------------------------------
delete(noerr) am_*
delete(noerr) fd_*
delete(noerr) fm_*
delete(noerr) lad_*
delete(noerr) m_*
delete(noerr) omega_*
delete(noerr) table*_*
delete(noerr) x_*
delete(noerr) mdir_*
delete(noerr) mind_*

group g_iad iad_w_*
freeze(t_iad) g_iad
t_iad.deleterow(2) 1
t_iad.save(t=csv) c:\users\wb398198\desktop\offline\martin\data\t_iad.csv

close io_calcs


