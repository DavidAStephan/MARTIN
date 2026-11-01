'**********************************************************************************************
' Model: RBA MARTIN Macroeconometric Model of Australia
' Programmer: David Stephan (david.stephan@gmail.com)
' Last Updated: November 5, 2019
'**********************************************************************************************
close @all
%path=@runpath
cd %path

'**********************************************************************************************
'Set Sample Periods for Model

%solve_start="2017q2"
%solve_end="2099q4"
!solve_stop = @val(%solve_end)
%eq_est_end = "2019q4" 'last period of sample for equation estimation
%NATACCS_end="2021q1" 'last quarter of national accounts data
%modelname="MARTIN"

'**********************************************************************************************

'Debugging Mode On/Off
!calc_ios = 0 'calculating IO multipliers for import-adjusted demand
!build_database = 0 'build database or load data from drive
!pistar = 0 'use RBA MARTIN Public Value for Inflation Expectations or calculate from State Space Model
!nairu = 0 'use RBA NAIRU estimate or calculate from State Space Model
!rstar = 0 'use simple backward moving average) or calculate from State Space Model
!test_identities = 0 'test identities hold in the historical period (add-factors on identities = 0)
!test_convergence = 0 'test convergence properties of LR forecast (eg. does growth = potential growth)
!run_sims = 0 'run scenarios of model endogenous variables
!fcst_table = 1 'create a SMP style forecast table

'**********************************************************************************************
'Enter API Keys for Downloading Data from Quandl and FRED
'Register at Quandl and FRED websites for API keys
%FRED = "819674707cc9b3a42385749283aacc6e"
%QUANDL = "c8j3mjrA43ToLv5yKYnv"

'**********************************************************************************************

'Subroutine
include .\programs\import_data

'**********************************************************************************************

'Create Model Database 
if !calc_ios = 1 then

	include .\programs\io_calcs.prg 'use IO tables to create import-adjusted demand variables

endif

if !build_database = 1 then

	call import_data(%FRED, %QUANDL) 'download data from ABS / FRED / WorldBank

	if !pistar=1 then
		include .\programs\pistar 'modify and create variables for model
	else
		rename pi_e_martin pi_e
	endif

	if !nairu=1 then
		include .\programs\nairu 'modify and create variables for model
	else
		rename TLUR_martin TLUR
	endif

	if !rstar=1 then
		include .\programs\rstar 'modify and create variables for model
	endif

	include .\programs\modify_data 'modify and create variables for model
	include .\programs\supply_side 'modify and create variables for model

	wfsave .\output\modeldatabase

else

	wfopen .\output\modeldatabase

endif

smpl @all

'****************************************************************************************************

'Create Model Object
model MARTIN

'Create Equations and Model Object
include .\programs\equations.prg

'****************************************************************************************************
smpl @all

'Solve Model
mode quiet
include .\programs\solve_model.prg

smpl @all
wfsave .\output\solvedmodel.wf1

'****************************************************************************************************

'Test Convergence of Model
if !test_convergence=1 then 'test convergence properties of LR forecast
	include .\programs\model_converge.prg
	stop
endif

'****************************************************************************************************
'Run Scenarios
if !run_sims = 1 then
	include .\programs\run_sims.prg
	stop
endif

'****************************************************************************************************
'Forecast Table
if !fcst_table = 1 then
	include .\programs\fcst_table.prg
	stop
endif


