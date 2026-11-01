library(bimets); library(xts); library(dplyr); library(readxl); library(ggplot2);
setwd("C:\\Users\\wb398198\\Desktop\\OFFLINE\\bimets")

#Load data from CSV file and convert into bimets friendly list
in_df <- read_excel("MARTINDATA_XLSX.xlsx")
names(in_df)[1] <- "Dates"
in_df$Dates <- as.Date(in_df$Dates)
series_count <- 206
varlist <- colnames(in_df)

MARTINDATA <- list()
for (idx in 2:series_count) MARTINDATA[[paste0(varlist[idx])]] <- as.bimets(xts(in_df[,idx], order.by = in_df$Dates))

MARTIN=LOAD_MODEL("MARTINMOD_AF.txt")

#load model data
MARTIN=LOAD_MODEL_DATA(MARTIN,MARTINDATA)

MARTIN=ESTIMATE(MARTIN)

#Assign Residuals as Add-Factors
#define add-factor list
constantAdjList <- list(
  ATS = MARTIN$behaviorals$ATS$residuals,
  DFD = MARTIN$behaviorals$DFD$residuals,
  G = MARTIN$behaviorals$G$residuals,
  GC = MARTIN$behaviorals$GC$residuals,
  GI = MARTIN$behaviorals$GI$residuals,
  GNE = MARTIN$behaviorals$GNE$residuals,
  IAD = MARTIN$behaviorals$IAD$residuals,
  IBCTR = MARTIN$behaviorals$IBCTR$residuals,
  IBN = MARTIN$behaviorals$IBN$residuals,
  IBNDR = MARTIN$behaviorals$IBNDR$residuals,
  IBRE = MARTIN$behaviorals$IBRE$residuals,
  IBREDR = MARTIN$behaviorals$IBREDR$residuals,
  ID = MARTIN$behaviorals$ID$residuals,
  IDDR = MARTIN$behaviorals$IDDR$residuals,
  KIBN = MARTIN$behaviorals$KIBN$residuals,
  KIBRE = MARTIN$behaviorals$KIBRE$residuals,
  KID = MARTIN$behaviorals$KID$residuals,
  KIDC = MARTIN$behaviorals$KIDC$residuals,
  KV = MARTIN$behaviorals$KV$residuals,
  LE = MARTIN$behaviorals$LE$residuals,
  LHPP = MARTIN$behaviorals$LHPP$residuals,
  LOKLAG = MARTIN$behaviorals$LOKLAG$residuals,
  LPOP = MARTIN$behaviorals$LPOP$residuals,
  LPR = MARTIN$behaviorals$LPR$residuals,
  LUR = MARTIN$behaviorals$LUR$residuals,
  M = MARTIN$behaviorals$M$residuals,
  N10R = MARTIN$behaviorals$N10R$residuals,
  N2R = MARTIN$behaviorals$N2R$residuals,
  NATS = MARTIN$behaviorals$NATS$residuals,
  NBRSP = MARTIN$behaviorals$NBRSP$residuals,
  NCR = MARTIN$behaviorals$NCR$residuals,
  NDFD = MARTIN$behaviorals$NDFD$residuals,
  NGNE = MARTIN$behaviorals$NGNE$residuals,
  NHC = MARTIN$behaviorals$NHC$residuals,
  NHFA = MARTIN$behaviorals$NHFA$residuals,
  NHL = MARTIN$behaviorals$NHL$residuals,
  NHNFA = MARTIN$behaviorals$NHNFA$residuals,
  NHOY = MARTIN$behaviorals$NHOY$residuals,
  NHS = MARTIN$behaviorals$NHS$residuals,
  NSD = MARTIN$behaviorals$NSD$residuals,
  NSP = MARTIN$behaviorals$NSP$residuals,
  NTWI = MARTIN$behaviorals$NTWI$residuals,
  NULCBS = MARTIN$behaviorals$NULCBS$residuals,
  NUSD = MARTIN$behaviorals$NUSD$residuals,
  NV = MARTIN$behaviorals$NV$residuals,
  OTC = MARTIN$behaviorals$OTC$residuals,
  P = MARTIN$behaviorals$P$residuals,
  PAE = MARTIN$behaviorals$PAE$residuals,
  PC = MARTIN$behaviorals$PC$residuals,
  PEX = MARTIN$behaviorals$PEX$residuals,
  PG = MARTIN$behaviorals$PG$residuals,
  PH = MARTIN$behaviorals$PH$residuals,
  PI_E = MARTIN$behaviorals$PI_E$residuals,
  PIBN = MARTIN$behaviorals$PIBN$residuals,
  PIBRE = MARTIN$behaviorals$PIBRE$residuals,
  PID = MARTIN$behaviorals$PID$residuals,
  PM = MARTIN$behaviorals$PM$residuals,
  PMCG = MARTIN$behaviorals$PMCG$residuals,
  POTC = MARTIN$behaviorals$POTC$residuals,
  PRT = MARTIN$behaviorals$PRT$residuals,
  PTM = MARTIN$behaviorals$PTM$residuals,
  PW = MARTIN$behaviorals$PW$residuals,
  PXAG = MARTIN$behaviorals$PXAG$residuals,
  PXM = MARTIN$behaviorals$PXM$residuals,
  PXO = MARTIN$behaviorals$PXO$residuals,
  PXRE = MARTIN$behaviorals$PXRE$residuals,
  PXS = MARTIN$behaviorals$PXS$residuals,
  RC = MARTIN$behaviorals$RC$residuals,
  REWI = MARTIN$behaviorals$REWI$residuals,
  RSTAR = MARTIN$behaviorals$RSTAR$residuals,
  RTWI = MARTIN$behaviorals$RTWI$residuals,
  RTWI_CONST = MARTIN$behaviorals$RTWI_CONST$residuals,
  SD = MARTIN$behaviorals$SD$residuals,
  TDLLA = MARTIN$behaviorals$TDLLA$residuals,
  TDLLHPP = MARTIN$behaviorals$TDLLHPP$residuals,
  TDLLPOP = MARTIN$behaviorals$TDLLPOP$residuals,
  TLLA = MARTIN$behaviorals$TLLA$residuals,
  TLLHPP = MARTIN$behaviorals$TLLHPP$residuals,
  TLLPOP = MARTIN$behaviorals$TLLPOP$residuals,
  TLUR = MARTIN$behaviorals$TLUR$residuals,
  TY = MARTIN$behaviorals$TY$residuals,
  V = MARTIN$behaviorals$V$residuals,
  WP = MARTIN$behaviorals$WP$residuals,
  WPAG = MARTIN$behaviorals$WPAG$residuals,
  WPCOM = MARTIN$behaviorals$WPCOM$residuals,
  WPOIL = MARTIN$behaviorals$WPOIL$residuals,
  WPX = MARTIN$behaviorals$WPX$residuals,
  WR2R = MARTIN$behaviorals$WR2R$residuals,
  WRR = MARTIN$behaviorals$WRR$residuals,
  WY = MARTIN$behaviorals$WY$residuals,
  XAG = MARTIN$behaviorals$XAG$residuals,
  XAGEXRAIN = MARTIN$behaviorals$XAGEXRAIN$residuals,
  XM = MARTIN$behaviorals$XM$residuals,
  XO = MARTIN$behaviorals$XO$residuals,
  XRE = MARTIN$behaviorals$XRE$residuals,
  XS = MARTIN$behaviorals$XS$residuals
  
)

#simulate model with add-factors set to equal residuals
MARTIN <- SIMULATE(MARTIN
                   ,TSRANGE=c(2010,1,2019,3)
                   ,ConstantAdjustment=constantAdjList
)

#check historical and simulated Y and Z are equal
TABIT((MARTIN$simulation$Y-MARTIN$modelData$Y)/MARTIN$modelData$Y*100)

#shock the NCR add-factor on 2010q1
Shock <- constantAdjList
Shock$NCR[[2010,1]] <- Shock$NCR[[2010,1]] + 1
Shock$NCR[[2010,2]] <- Shock$NCR[[2010,2]] + .341413
Shock$NCR[[2010,3]] <- Shock$NCR[[2010,3]] + .427
Shock$NCR[[2010,4]] <- Shock$NCR[[2010,4]] + .5137297

MARTIN_Shocked <- SIMULATE(MARTIN,
                           TSRANGE=c(2010,1,2019,3),
                           ConstantAdjustment = Shock  )

TABIT((MARTIN_Shocked$simulation$Y-MARTIN$simulation$Y)/MARTIN$simulation$Y*100)
sim_chart <- as.data.frame((MARTIN_Shocked$simulation$Y-MARTIN$simulation$Y)/MARTIN$simulation$Y*100)
sim_chart %>%
  ggplot(aes(x = seq(0,38), y = x)) +
  geom_line() + 
  ylab("% deviation from baseline") +
  xlab("Quarters")
