# MARTIN
This repository recreates the Reserve Bank of Australia's MARTIN macroeconomic model. This includes downloading all the source data, modifying variables for the model, estimating the state space models and main model equations, and solving the model. Tested in Eviews 10.

The model is almost identical to the RBA version, however there are some series where it was too difficult or impossible to source the data. The RBA model has data on net asset transfers between the public and private sectors which, as far as I can tell, is not a publicly released series. Instead, I only have the separation of private business investment into new private business investment and second-hand asset sales. This means that the non-mining business investment and government investment series differ slightly from the RBA version.

Also, for now, I have not created world GDP, export price, and interest rate series by weighting the major trading partners (or G3 for interest rates). For now, the model simply uses the USA version of each variable for ease. This is mainly due to China, which doesn't publish (or at least didn't) quarterly seasonally adjusted GDP. If I can find easy, publicly available series for GDP, export deflators, and interest rates for major trading partners I will adjust the code.

For the export categories( mining, manufacturing, services) I did not calculate a time-varying constant. I found that with a fairly standard linear time trend (sometimes with the trend ending in the mid-2000s) you could get a good fit of the equation (similar to RBA values). For the agricultural export equaiton I used an old value from the TRYM modellers database (ABS 1364.0.15.003 - June 2011 Table 22) which has the value of agricultural output affected by rain. By using this value in history (Agriculture Exports - Rain Affected Output as the dependent variable) the fit of the equation (expected signs and magnitudes) worked quite well.

Feel free to email me with any question/comments: david.stephan@gmail.com

<b>REQUIREMENTS</b>

Eviews; R; Excel




