' -------------------------------------------------------------------------------------
' -------------------------------------------------------------------------------------
' Create Model Database Using R and Other Databases
' Programmer: David Stephan
' Last Updated: 5 November
' email: david.stephan@gmail.com
' -------------------------------------------------------------------------------------
subroutine import_data(string %FRED, string %QUANDL)

' -------------------------------------------------------------------------------------
%pathimport=@runpath
%rpath = %pathimport + "PROGRAMS\RDATA\"
%rpath = @replace(%rpath,"\","/")
%setwd = "setwd("+"""" + @left(%rpath,@len(%rpath)-1) + """)"

wfcreate(wf=importeddata, page=Rqtly) q 1959q3 2099q4
pagecreate(page = Rannual) a 1960 2099
pageselect Rqtly

'********************************************************************************
'FRED DATABASE
'********************************************************************************
pageselect Rqtly

xopen(r)

xrun {%setwd}

xpackage fredr
xpackage dplyr 

xon

fredr_set_key(%FRED)

GDPC1 <- fredr(series_id = "GDPC1", observation_start = as.Date("1959-07-01"))
GDPC1 <- GDPC1 %>% rename(GDPC1 = value) %>% dplyr::select(date, GDPC1) 

GDPDEF <- fredr(series_id = "GDPDEF", observation_start = as.Date("1959-07-01"))
GDPDEF <- GDPDEF %>% rename(GDPDEF = value) %>% dplyr::select(date, GDPDEF)

A020RD3Q086SBEA <- fredr(series_id = "A020RD3Q086SBEA", observation_start = as.Date("1959-07-01"))
A020RD3Q086SBEA <- A020RD3Q086SBEA %>% rename(A020RD3Q086SBEA = value) %>% dplyr::select(date, A020RD3Q086SBEA)

MCOILWTICO <- fredr(series_id = "MCOILWTICO", observation_start = as.Date("1959-07-01"), frequency = "q")
MCOILWTICO <- MCOILWTICO %>% rename(MCOILWTICO = value) %>% dplyr::select(date, MCOILWTICO) 

GS2 <- fredr(series_id = "GS2", observation_start = as.Date("1959-07-01"), frequency = "q")
GS2 <- GS2 %>% rename(GS2 = value) %>% dplyr::select(date, GS2)

FEDFUNDS <- fredr(series_id = "FEDFUNDS", observation_start = as.Date("1959-07-01"), frequency = "q")
FEDFUNDS <- FEDFUNDS %>% rename(FEDFUNDS = value) %>% dplyr::select(date, FEDFUNDS)

T10Y2YM <- fredr(series_id = "T10Y2YM", observation_start = as.Date("1959-07-01"), frequency = "q")
T10Y2YM <- T10Y2YM %>% rename(T10Y2YM = value) %>% dplyr::select(date, T10Y2YM)

xrun FRED_DATA <- list(GDPC1, GDPDEF, A020RD3Q086SBEA, MCOILWTICO, GS2, FEDFUNDS, T10Y2YM) %>% Reduce(function(dtf1,dtf2) left_join(dtf1,dtf2,by="date"), .)

xoff

xget(type=series) FRED_DATA

'********************************************************************************
'LOAD ABS DATA USING R SCRIPTS
'********************************************************************************
xpackage readabs
xpackage reshape2
xpackage lubridate
xpackage tidyverse
xpackage zoo
xpackage Quandl
xpackage data.table
xpackage readrba
xpackage httr

xrun httr::set_config(config(ssl_verifypeer = FALSE)) 'Sometimes needed for work/office connection issues

xon

	'---------------------------------------------------------------------------------------------------------
	'Download Most Recent ABS Data
	'---------------------------------------------------------------------------------------------------------
	abs_5206 <- read_abs("5206.0", tables = c("1", "2", "3", "7", "20", "24"))
	abs_6401 <- read_abs("6401.0", tables = c("7"))
	abs_5302 <- read_abs("5302.0", tables = c("1", "4","5","6", "8"))
	abs_5204 <- read_abs("5204.0", tables = c("56", "58"))
'	abs_5625 <- read_abs("5625.0", tables = c("1e", "3b"))
	abs_5625 <- read_abs(series_id = c("A3515959C", "A3515137T"))
	abs_6202 <- read_abs("6202.0", tables = c("1", "19"))
	abs_6345 <- read_abs("6345.0", tables = c("1"))
	abs_6457 <- read_abs("6457.0", tables = c("4"))
	abs_6416 <- read_abs("6416.0", tables = c("1", "8"))
	abs_5232 <- read_abs("5232.0", tables = c("35"))
	abs_1364 <- read_abs("1364.0.15.003")

	'---------------------------------------------------------------------------------------------------------		
	'CLEANUP ABS SPREADSHEETS
	'---------------------------------------------------------------------------------------------------------

	'5206.0 Australian National Accounts: National Income, Expenditure and Product
	R_5206 <- abs_5206 %>%  filter(series_id %in% c("A2304080V"	,"A2304109L",	"A2304081W", "A2305148W",	"A2304098T",	"A2304099V", "A2304095K",	"A2304111X",	"A2304112A","A2304113C",	"A2304114F",	"A2304115J", "A2304116K",	"A2304402X",	"A2304036K", "A2304065W",	"A2304037L",	"A2305146T","A2304054R",	"A2304055T",	"A2304051J", "A2304067A",	"A2304068C",	"A2303823C", "A2303824F",	"A2303825J",	"A2303826K", "A2304418T", "A2302939L", "A2302915V", "A2302940W", "A2302837X", "A2304192L")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value) 
	R_5206 <- distinct(R_5206,date,series_id, .keep_all= TRUE)
	R_5206 <- dcast(R_5206, date ~ series_id)

	'5302.0 Balance of Payments and International Investment Position, Australia
	R_5302 <- abs_5302 %>%  filter(series_id %in% c("A3535039K"	,"A3535041W",	"A3535047K",	"A3535048L","A3535049R",	"A3535050X",	"A3535051A",	"A3535052C", "A3535053F",	"A3535093X",	"A3535055K", "A3535191C", "A3535199W",	"A3535200V",	"A3535201W",	"A3535202X", "A3535203A",	"A3535204C",	"A3535206J","A3535208L", "A3535060C", "A3535214J", "A3535247C", "A3535058T", "A3535059V", "A3535054J", "A3535212C", "A3535213F", "A3535207K")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value)
	R_5302 <- distinct(R_5302,date,series_id, .keep_all= TRUE)
	R_5302 <- dcast(R_5302, date ~ series_id)

	'5204.0 Australian System of National Accounts - ANNUAL
	R_5204 <- abs_5204 %>% filter(series_id %in% c("A3347284T",  "A3347277V", "A3348050V", "A2422531C", "A2422532F", "A2422574C", "A2422539W", "A2422538V", "A2422573A", "A2422537T", "A2422533J", "A2422575F", "A3347265K")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value)
	R_5204 <- distinct(R_5204,date,series_id, .keep_all= TRUE)
	R_5204 <- dcast(R_5204, date ~ series_id)
	
	'6202.0 Labour Force, Australia - Monthly
	R_6202 <- abs_6202 %>% filter(series_id %in% c("A84423043C", "A84423047L", "A84423051C", "A84426277X", "A84423091W")) %>% dplyr::select(date, series_id, value)
	R_6202 <- distinct(R_6202,date,series_id, .keep_all= TRUE)
	R_6202 <- dcast(R_6202, date ~ series_id)
	R_6202 <- R_6202 %>% group_by(date=floor_date(date, "quarter")) %>% summarize(A84423043C=mean(A84423043C), A84423047L=mean(A84423047L),A84423051C=mean(A84423051C), A84426277X=mean(A84426277X), A84423091W=mean(A84423091W)) %>% mutate(date = zoo::as.yearqtr(date))
	
	'6345.0 Wage Price Index, Australia
	R_6345 <- abs_6345 %>% filter(series_id %in% c("A2713849C")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, value)
	R_6345 <- R_6345 %>% rename(A2713849C = value) 
	
	'6457.0 International Trade Price Indexes, Australia
	R_6457 <- abs_6457 %>% filter(series_id %in% c("A2298279F")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, value)
	R_6457 <- R_6457 %>% rename(A2298279F = value) 

	'6401.0 Consumer Price Index, Australia
	R_6401 <- abs_6401 %>% filter(series_id %in% c("A2331876F")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value) 
	R_6401 <- distinct(R_6401,date,series_id, .keep_all= TRUE)
	R_6401 <- dcast(R_6401, date ~ series_id)
	
	'5625.0 Private New Capital Expenditure and Expected Expenditure, Australia
	R_5625 <- abs_5625 %>% filter(series_id %in% c("A3515959C", "A3515137T")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value)
	R_5625 <- distinct(R_5625,date,series_id, .keep_all= TRUE)
	R_5625 <- dcast(R_5625, date ~ series_id)

	'6416.0 - Residential Property Price Indexes: Eight Capital Cities
	R_6416 <- abs_6416 %>% filter(series_id %in% c("A83728455L", "A2333613R")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value)
	R_6416 <- distinct(R_6416,date,series_id, .keep_all= TRUE)
	R_6416 <- dcast(R_6416, date ~ series_id)

	'5232.0 Australian National Accounts: Finance and Wealth
	R_5232 <- abs_5232 %>% filter(series_id %in% c("A83728305F", "A83722666C", "A83722657A", "A83722670V")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value)
	R_5232 <- distinct(R_5232,date,series_id, .keep_all= TRUE)
	R_5232 <- dcast(R_5232, date ~ series_id)

	'1364 Modellers Database
	R_1364 <- abs_1364 %>% filter(series_id %in% c("A2454521V", "A2454517C", "A2454568C", "A2454516A", "A2454517C", "A2454518F")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value) 
	R_1364 <- distinct(R_1364,date,series_id, .keep_all= TRUE)
	R_1364 <- dcast(R_1364, date ~ series_id)

	'---------------------------------------------------------------------------------------------------------
	'Download RBA Data Using Quandl
	'---------------------------------------------------------------------------------------------------------

		'RBA DATA SERIES USING QUANDL
		Quandl.api_key(%QUANDL)

		'Credit; Total; Seasonally adjusted - Monthly
		D02_DLCACS <- Quandl("RBA/D02_DLCACS", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(D02_DLCACS = "Credit; Total; Seasonally adjusted. Units: $ billion; Series ID: DLCACS") %>% group_by(date=floor_date(date, "quarter")) %>% summarize(D02_DLCACS=mean(D02_DLCACS)) %>% mutate(date = zoo::as.yearqtr(date))    
		
		'Credit; Business; Seasonally adjusted - Monthly
		D02_DLCACBS <- Quandl("RBA/D02_DLCACBS", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(D02_DLCACBS = "Credit; Business; Seasonally adjusted. Units: $ billion; Series ID: DLCACBS") %>% group_by(date=floor_date(date, "quarter")) %>% summarize(D02_DLCACBS=mean(D02_DLCACBS)) %>% mutate(date = zoo::as.yearqtr(date))    
		
		'Interbank Overnight Cash Rate - Monthly
		F01_1_FIRMMCRI <- Quandl("RBA/F01_1_FIRMMCRI", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(F01_1_FIRMMCRI = "Interbank Overnight Cash Rate. Units: Per cent; Series ID: FIRMMCRI") %>%  group_by(date=floor_date(date, "quarter")) %>% summarize(F01_1_FIRMMCRI=mean(F01_1_FIRMMCRI)) %>% mutate(date = zoo::as.yearqtr(date))    

		'Cash Rate Target; monthly average
		F01_1_FIRMMCRT <- Quandl("RBA/F01_1_FIRMMCRT", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(F01_1_FIRMMCRT = "Cash Rate Target. Units: Per cent; Series ID: FIRMMCRT") %>%  group_by(date=floor_date(date, "quarter")) %>% summarize(F01_1_FIRMMCRT=mean(F01_1_FIRMMCRT)) %>% mutate(date = zoo::as.yearqtr(date))    
    		
		'Lending rates; Housing loans; Banks; Variable; Standard; Owner-occupier. Units: Monthly
		F05_FILRHLBVS <- Quandl("RBA/F05_FILRHLBVS", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(F05_FILRHLBVS = "Lending rates; Housing loans; Banks; Variable; Standard; Owner-occupier. Units: Per cent per annum; Series ID: FILRHLBVS") %>% group_by(date=floor_date(date, "quarter")) %>% summarize(F05_FILRHLBVS=mean(F05_FILRHLBVS)) %>% mutate(date = zoo::as.yearqtr(date))    
		
		'2-yr Commonwealth Bond Yield Monthly
		F02_1_FCMYGBAG2 <- Quandl("RBA/F02_1_FCMYGBAG2", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(F02_1_FCMYGBAG2 = "Commonwealth Government 2 year bond. Units: Per cent per annum; Series ID: FCMYGBAG2") %>% group_by(date=floor_date(date, "quarter")) %>% summarize(F02_1_FCMYGBAG2=mean(F02_1_FCMYGBAG2)) %>% mutate(date = zoo::as.yearqtr(date))    
		
		'10-yr Commonwealth Bond Yield Monthly
		F02_1_FCMYGBAG10 <- Quandl("RBA/F02_1_FCMYGBAG10", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(F02_1_FCMYGBAG10 = "Commonwealth Government 10 year bond. Units: Per cent per annum; Series ID: FCMYGBAG10") %>% group_by(date=floor_date(date, "quarter")) %>% summarize(F02_1_FCMYGBAG10=mean(F02_1_FCMYGBAG10)) %>% mutate(date = zoo::as.yearqtr(date))
		
		'USD Exchange Rate - Daily
		FXRUSD <- Quandl("RBA/FXRUSD", type="raw") %>% rename(FXRUSD = Value) %>% group_by(date=floor_date(Date, "quarter")) %>%  summarize(FXRUSD=mean(FXRUSD)) %>% mutate(date = zoo::as.yearqtr(date)) 
		
		'Trade Weighted Exchange Rate - Daily
		FXRTWI <- Quandl("RBA/FXRTWI", type="raw") %>% rename(FXRTWI = Value) %>% group_by(date=floor_date(Date, "quarter")) %>% summarize(FXRTWI=mean(FXRTWI)) %>% mutate(date = zoo::as.yearqtr(date))
		
		'Weighted Average Business Lending Rate 'qtly - #### NO LONGER UPDATED ON RBA WEBSITE ####
		F05_FILRLBWAV <- Quandl("RBA/F05_FILRLBWAV", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(F05_FILRLBWAV = "Lending rates; Large business; Weighted-average rate on credit outstanding; Variable. Units: Per cent per annum; Series ID: FILRLBWAV") %>% group_by(date=floor_date(date, "quarter")) %>% summarize(F05_FILRLBWAV=mean(F05_FILRLBWAV)) %>% mutate(date = zoo::as.yearqtr(date))    

		'Lending rates; Business finance; Outstanding; Large business; Total
		F07_FLRBFOLBT <- read_rba(series_id = "FLRBFOLBT") 
		F07_FLRBFOLBT %>% dplyr::select(date, series_id, value)
		F07_FLRBFOLBT <- distinct(F07_FLRBFOLBT,date,series_id, .keep_all= TRUE)
		F07_FLRBFOLBT <- dcast(F07_FLRBFOLBT, date ~ series_id)
		F07_FLRBFOLBT <- F07_FLRBFOLBT %>% group_by(date=floor_date(date, "quarter")) %>% summarize(FLRBFOLBT=mean(FLRBFOLBT)) %>% mutate(date = zoo::as.yearqtr(date))

		'Lending rates; Small business; Variable; Term
		F05_FILRSBVRT<- Quandl("RBA/F05_FILRSBVRT", type="raw") %>% arrange(Date) %>% rename(date = Date) %>% rename(F05_FILRSBVRT = "Lending rates; Small business; Variable; Term. Units: Per cent per annum; Series ID: FILRSBVRT") %>% group_by(date=floor_date(date, "quarter")) %>% summarize(F05_FILRSBVRT=mean(F05_FILRSBVRT)) %>% mutate(date = zoo::as.yearqtr(date))    
		
		'Real Trade Weighted Index
		F15_FRERTWI <- Quandl("RBA/F15_FRERTWI", type="raw") %>% mutate(Date = zoo::as.yearqtr(Date)) %>% arrange(Date) %>% rename(date = Date) %>% rename(F15_FRERTWI = "Real trade-weighted index. Units: Index; March 1995 = 100; Series ID: FRERTWI")
		
		'Real Trade Weighted Index Export Weights
		F15_FREREWI <- Quandl("RBA/F15_FREREWI", type = "raw") %>% mutate(Date = zoo::as.yearqtr(Date)) %>% arrange(Date) %>% rename(date = Date) %>% rename(F15_FREREWI = "Real export-weighted index. Units: Index; March 1995 = 100; Series ID: FREREWI")
		
		'Trimmed Mean Inflation
		G01_GCPIOCPMTMQP <- Quandl("RBA/G01_GCPIOCPMTMQP", type = "raw") %>% mutate(Date = zoo::as.yearqtr(Date)) %>% arrange(Date) %>% rename(date = Date) %>% rename(G01_GCPIOCPMTMQP = "Quarterly trimmed mean inflation. Units: Per cent; Series ID: GCPIOCPMTMQP")

		'Inflation excl. volatile items
		G01_GCPIXVIQP <- Quandl("RBA/G01_GCPIXVIQP", type = "raw") %>% mutate(Date = zoo::as.yearqtr(Date)) %>% arrange(Date) %>% rename(date = Date)
		names(G01_GCPIXVIQP)[2] <- "G01_GCPIXVIQP"
		' %>% rename(G01_GCPIXVIQP = "Quarterly inflation excluding volatile items. Units: Per cent; Series ID: GCPIXVIQP")

		'Inflation Expectations - Break-even 10-year inflation rate (converted to qtly)
		G03_GBONYLD <- Quandl("RBA/G03_GBONYLD") %>% mutate(Date = zoo::as.yearqtr(Date)) %>% arrange(Date) %>%  rename(date = Date) %>%  rename(value = "Break-even 10-year inflation rate. Units: Per cent ; Series ID: GBONYLD") %>% mutate(G03_GBONYLD = ((1+value/100)^(1/4)-1)*100) %>%  dplyr::select(date, G03_GBONYLD)

		'Other Inflation Expectation Series
'		g3_tables <- rba_search(pattern = "Expectations")
'		rba_g3 <- rba_stats(url = g3_tables$url)
		rba_g3 <- read_rba(series_id = c("GBUSEXP", "GUNIEXPY", "GUNIEXPYY", "GMAREXPY", "GMAREXPYY", "GBONYLD")) 
		R_g3 <- rba_g3 %>% filter(series_id %in% c("GBUSEXP", "GUNIEXPY", "GUNIEXPYY", "GMAREXPY", "GMAREXPYY", "GBONYLD")) %>% mutate(date = zoo::as.yearqtr(date)) %>% dplyr::select(date, series_id, value)
		R_g3 <- distinct(R_g3,date,series_id, .keep_all= TRUE)
		R_g3 <- dcast(R_g3, date ~ series_id)

		'Inflation excl. interest charges and GST
		G01_GCPIEITCQP <- Quandl("RBA/G01_GCPIEITCQP", type = "raw") %>% mutate(Date = zoo::as.yearqtr(Date)) %>% arrange(Date) %>% rename(date = Date)
		names(G01_GCPIEITCQP)[2] <- "G01_GCPIEITCQP"
' %>% rename(G01_GCPIEITCQP = "Quarterly inflation excluding interest and tax changes. Units: Per cent; Series ID: GCPIEITCQP")

'------------------------------------------------------------------------------------------------------------------------------------------------
' Join series together at a Qtly Frequency
'------------------------------------------------------------------------------------------------------------------------------------------------

xrun workfile = data.frame(matrix(vector(), 562, 1,dimnames=list(c(), c("blank"))),stringsAsFactors=F)
xrun workfile$date <- yearqtr(1959 + seq(2, 563)/4)

xrun MARTIN_data <- list(workfile, R_5206, R_5302, R_5625, R_6202, R_6345, R_6457, R_6401, R_6416, R_5232, G03_GBONYLD, F01_1_FIRMMCRI, F01_1_FIRMMCRT, F02_1_FCMYGBAG10, F02_1_FCMYGBAG2, F05_FILRHLBVS, F05_FILRLBWAV, F07_FLRBFOLBT, F15_FREREWI, F15_FRERTWI, D02_DLCACS, D02_DLCACBS, FXRTWI, FXRUSD, G01_GCPIOCPMTMQP, G01_GCPIXVIQP, R_1364, R_g3, G01_GCPIEITCQP) %>% Reduce(function(dtf1,dtf2) left_join(dtf1,dtf2,by="date"), .)

xoff

pageselect Rqtly
xget(type=series) MARTIN_data
pageselect Rannual
xget(type=series) R_5204

xclose

'********************************************************************************
'Commodity Prices
'********************************************************************************
pagecreate(page=commprices) m 1960m01 2099m12
'%url = "http://pubdocs.worldbank.org/en/561011486076393416/CMO-Historical-Data-Monthly.xlsx"
'import %url range="Monthly Indices"
import .\..\data\CMO-Historical-Data-Monthly.xlsx range = "Monthly Indices"
rename agriculture_iagriculture WPAG
rename energy_ienergy WPCOM
copy(c=a) commprices\WPAG Rqtly\*
copy(c=a) commprices\WPCOM Rqtly\*

'********************************************************************************
'Southern Oscillation Index
'********************************************************************************
pagecreate(page=soi) m 1876m01 2099m12
%url = "ftp://ftp.bom.gov.au/anon/home/ncc/www/sco/soi/soiplaintext.html"
importtbl(name=_tsoi) %url colhead=1
_tsoi.deleterow(1) 1
_tsoi.deletecol(1) 1

!rows = @rows(_tsoi)
!cols = @columns(_tsoi)
!movsmpl = 0

vector(!rows*!cols) VSOI

for !i=1 to !rows
	for !j=1 to !cols
		!movsmpl=!movsmpl+1
		vsoi(!movsmpl) = _tsoi(!i,!j)
	next
next

smpl @all
mtos(vsoi,soi)
copy(c=a) SOI\SOI Rqtly\*
 
'********************************************************************************
'Clean-up Workfile Names
'********************************************************************************
	'****************QUARTERLY********************
	pageselect Rqtly
	
	'Prices/Wages
		'Trimmed Mean
		rename G01_GCPIOCPMTMQP PTM
		'Consumer Import Prices
		rename A2298279F pmcg
		'Wage Price Index
		rename A2713849C pw
		'House Prices (ABS)
		rename A83728455L ph
		'House Price Established (ABS) Previuos
		rename A2333613R PH_OLD
		'Rent CPI
		rename A2331876F prt
		'CPI Excluding Volatile Items
		rename G01_GCPIXVIQP PEX
		'CPI
		rename G01_GCPIEITCQP P
	
	'National Accounts
		'Labor Productivity
		rename A2304192L LA
		'Household Consumption
		rename A2304081W rc
		rename A2304037L NC
		'Dwelling Investment		
		rename A2304098T id
		rename A2304054R NID
		'Ownership Transfer Costs
		rename A2304099V otc
		rename A2304055T NOTC
		'New Private Business Investment
		rename A2305148W IB
		rename A2305146T NIB
		'Private Business Investment
		rename A2304051J NIBtot
		rename A2304095K IBtot
		'Change in Inventories
		rename A2304112A V
		rename A2304068C NV
		'Public GFCF
		rename A2304109L gi
		rename A2304065W ngi
		'General Government Final Consumption
		rename A2304080V gc
		rename A2304036K ngc
		'Domestic Final Demand
		rename A2304111X DFD
		rename A2304067A NDFD
		'Gross National Expenditure
		rename A2304113C GNE
		rename A2303823C NGNE
		'Exports
		rename A2304114F X
		rename A2303824F NX
		'Imports
		rename A2304115J M
		rename A2303825J NM
		'GDP
		rename A2304402X Y
		rename A2304418T NY
		'Statistical Discrepancy (E)
		rename A2304116K SD
		rename A2303826K NSD
	
	'HOUSEHOLD INCOME
		'Gross Disposable Income
		rename A2302939L nhdy
		'Compensation of Employees
		rename A2302915V NHCOE
		'Hhold Consumption of Fixed Capital
		rename a2302940w kidc
		'Net Savings
		rename A2302837X NHS
	
	'Balance of Payments	
		'Service Exprots
		rename A3535093X XS
		rename a3535247c NXS
		'Agricultural Exports
		rename A3535041W XAG
		rename A3535191C NXAG
		'Goods Exports
		rename A3535039K X_goods
		
		rename A3535203A NXM_MACH '- machinery
		rename A3535204C NXM_TRNS 'transport eq
		rename A3535206J NXM_OTHR 'other manf
		rename A3535208L NXM_BEVO '- beverages
		
		rename A3535051A XM_MACH '- machinery
		rename A3535052C XM_TRNS 'transport eq
		rename A3535053F XM_OTHR 'other manf
		rename A3535055K XM_BEVO '- beverages

		rename A3535058T XO_CARY ' Goods procured in ports by carriers ;
		rename A3535059V XO_NXOM' Net exports of goods under merchanting
		rename A3535054J XO_NONR 'Other non-rural (incl. sugar and beverages) ;

		rename A3535212C NXO_CARY ' Goods procured in ports by carriers ;
		rename A3535213F NXO_NXOM' Net exports of goods under merchanting
		rename A3535207K NXO_NONR 'Other non-rural (incl. sugar and beverages) ;
		
		'Commodity Exports
		rename A3535047K XRE_ores 
		rename A3535048L XRE_Coal
		rename A3535049R XRE_othm
		rename A3535050X XRE_metl
		rename A3535060C XRE_nonm 
		rename A3535199W NXRE_ores	
		rename A3535200V	 NXRE_coal
		rename A3535201W NXRE_othm
		rename A3535202X NXRE_metl
		rename A3535214J NXRE_nonm
	
	'Labor Market
		'Employment
		rename a84423043c LE
		'Labor Force
		rename A84423047L LF
		'Part Rate
		rename A84423051C LPR
		'Population
		rename A84423091W LPOP
	
	'Monthly Hours Worked - Labor Force Survey
		rename A84426277X hours
	
	'World Variables
		'US Export Price Deflator
		rename a020rd3q086sbea WPX
		'Fed Funds Rate
		rename fedfunds wrcr
		'US GDP
		rename GDPC1 wy
		'US GDP Deflator
		rename GDPDEF wp
		'US 2year bond yield
		rename GS2 WN2R
		'WTI Oil Price
		rename MCOILWTICO WPOIL
		'10y-2y US Bond Spread
		rename T10Y2YM W2Rspread 
	
	'Interest Rates
		'Cash Rate
		rename f01_1_firmmcrt NCR
		'Interbank Overnight Cash Rate
		rename f01_1_firmmcri NCR_hist
		'10yr bond yield
		rename F02_1_FCMYGBAG10 N10R	
		'2yr bond yield
		rename F02_1_FCMYGBAG2 N2R
		'Mortgage Rate
		rename f05_filrhlbvs NMR
		'Business Rate (old)
		rename F05_FILRLBWAV NBR
		'Business Rate (new)
		rename FLRBFOLBT NBR_SPLICE
	
	'Credit
		'Business Credit (SA)	
		rename D02_DLCACBS NBC
		'Total Credit (SA)
		rename D02_DLCACS NTC
	
	'mining Capex
		rename a3515137t NIBRE_capex
		rename A3515959C IBRE_capex
		
	'Household Assets
		'Financial Assets		
		rename A83722657A NHFA
	
		'Non-Financial Assets
			'Consumer Durables
			rename A83722666C nhnfa_cd
			'Dwellings
			rename A83728305F nhnfa_dw
	
	'Household Liabilities
	rename A83722670V NHL
	
	'Real Trade Weighted Index
	rename F15_FRERTWI RTWI
			
	'Real Trade Weighted Index Import Weights
	rename F15_FREREWI REWI
	
	'Nominal TWI
	rename FXRTWI NTWI
	
	'USD exchange rate
	rename FXRUSD NUSD
	
	'Bond Yield Price Expectations
	rename g03_gbonyld pi_e_bond

	'Historical Unemployment
	rename A2454517C pop_hist
	rename A2454521V ur_hist

	'Historical Hours
	rename A2454568C lhpp_hist

	'Historical Farm Emp
	rename A2454516A le_farm_hist
	'Historical Non-Farm Emp
	rename A2454518F le_nonfarm_hist

'---------------------ANNUAL------------------------------
pageselect Rannual

	'Capital Stocks and Depreciation
		'Mining Capital Stock/Depreciation Rate/GFCF
		rename A3347284T KIBRE
		rename A3347277V IBRE
		rename A3348050V NIBRE
		rename A3347265K CFCIBRE
		'Dwelling Capital Stock/Depreciation Rate
		rename A2422532F KID
		rename A2422531C ID
		rename A2422533J CFCID
		'Total Capital Stock
		rename A2422574C KTOT
		rename A2422573A ITOT
		rename A2422575F CFCTOT
		'Ownership Transfer Costs K stock
		rename A2422539W KOTC
		rename A2422538V IOTC
		rename A2422537T CFCOTC	

		pageselect Rqtly
		%avar="KIBRE IBRE NIBRE KID ID KTOT ITOT KOTC IOTC CFCIBRE CFCID CFCOTC CFCTOT"
		for %var {%avar}
			copy(c=pointf) Rannual\{%var} Rqtly\*a1
			pageselect Rqtly
			series {%var}a2={%var}a1(-1)
		next

'************************************************************************************************
'Corporate Tax Rate
'************************************************************************************************
smpl @all
series IBCTR=NA
smpl @first 1963q2
IBCTR=0.4
smpl 1963q3 1967q2
IBCTR=0.425
smpl 1967q3 1969q2
IBCTR=0.45
smpl 1969q3 1973q2
IBCTR=0.475
smpl 1973q3 1974q2
IBCTR=0.45
smpl 1974q3 1976q2
IBCTR=0.425
smpl 1976q3 1986q2
IBCTR=0.46
smpl 1986q3 1988q2
IBCTR=0.49
smpl 1988q3 1993q2
IBCTR=0.39
smpl 1993q3 1995q2
IBCTR=0.33
smpl 1995q3 1999q2
IBCTR=0.36
smpl 1999q3 2000q2
IBCTR=0.34
smpl 2000q3 @last
IBCTR=0.3

'------------------------------------------------------------------------------------
'Trimmed Mean Level Series
'------------------------------------------------------------------------------------
smpl 1982Q1 1982q1
series PTML = 29.83452468
smpl 1982q2 @last
ptmL=ptmL(-1)*(1+ptm/100)
smpl @all
delete(noerr) ptm
rename ptml ptm

'------------------------------------------------------------------------------------
'Import Hard-coded values
'------------------------------------------------------------------------------------

	'IMPORT IO CALCULATED MULTIPLIERS
	import .\..\Data\t_iad.csv
	
	'RBA DATA Series
	wfopen .\..\data\martin_public
	copy martin_public::untitled\PI_E importeddata::Rqtly\*_MARTIN
	copy martin_public::untitled\N2R importeddata::Rqtly\*_MARTIN
	copy martin_public::untitled\N10R importeddata::Rqtly\*_MARTIN
	copy martin_public::untitled\TLUR importeddata::Rqtly\*_MARTIN
	copy martin_public::untitled\PEX importeddata::Rqtly\*_MARTIN
	close martin_public

	'Rainfall Adjusted Output (From June 2011 ModellersDatabase ABS) to use in Agr Export Eqn.
	import .\..\data\rain.xlsx

'Save Workfile After Importing Data
wfsave .\..\output\importeddata.wf1

endsub


