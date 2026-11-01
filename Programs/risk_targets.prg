''*******************************************************************
' Risk targets for this round, read by risk_policy.prg
' Written by the risk-table skill and approved by a person.
'
' Narrative: growth tilted to the downside, inflation tilted to the
' upside due to supply shocks
' Labour market: downside, tilted
' Inflation: upside, tilted
' Flags: "growth" is read as the labour market. The named cause (supply
' shocks) isn't reflected, as the table sets outcomes, not causes.
''*******************************************************************
!tilt_l_weak = 1.35
!tilt_l_strong = 0.60
!tilt_i_low = 0.60
!tilt_i_high = 1.35
