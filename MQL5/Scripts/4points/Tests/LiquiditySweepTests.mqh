#ifndef FOURPOINTS_LIQUIDITYSWEEPTESTS_MQH
#define FOURPOINTS_LIQUIDITYSWEEPTESTS_MQH

#include <4points/LiquiditySweep.mqh>

// P4 queda en el indice de rates[] correspondiente a bar_shift; el resto de
// velas hasta el indice 0 son las que LiquiditySweep explora en busca del barrido.
SPatternPoints BuildPointsForSweep(const int p4_shift, const double p1_price, const double p3_price)
  {
   SPatternPoints points;
   points.p1.type = SWING_LOW; points.p1.price = p1_price;
   points.p3.type = SWING_LOW; points.p3.price = p3_price;
   points.p4.type = SWING_HIGH; points.p4.bar_shift = p4_shift;
   return points;
  }

void RunLiquiditySweepTests()
  {
   int n = 8; // rates[0]=mas reciente .. rates[7]=mas antigua; P4 esta en rates[5]

   // NOTA sobre indices: BuildRatesSeries recibe arrays en orden CRONOLOGICO
   // (indice 0 = mas antiguo) e invierte el mapeo: out[s] = input[n-1-s]. Para
   // que una vela termine en un indice de serie s concreto del rates[] final,
   // hay que escribir en el indice cronologico k = n-1-s, NO en el indice s
   // directamente. Con n=8: s=4 -> k=3, s=3 -> k=4, s=2 -> k=5, s=1 -> k=6,
   // s=0 -> k=7. (El plan original escribia en los indices s directamente,
   // lo que en la practica colocaba el cierre de "recuperacion" del caso 1
   // en rates[5] -- la propia vela de P4, fuera de la ventana de busqueda,
   // que va de rates[4] a rates[0]. Verificado a mano y corregido aqui.)
   //
   // atr_period tambien se corrige de 14 (el valor del plan) a 3: SimpleATR
   // exige shift + period < ArraySize(rates); con n=8 y period=14 eso nunca
   // se cumple para ningun shift, así que SWEEP_INTERNAL siempre recibia
   // ATR=-1.0 (centinela de "sin historia suficiente") y la tolerancia
   // eq_tol_atr quedaba muerta (tol=0.0) sin que ningun caso lo advirtiera.
   // period=3 sí produce un ATR real para los shift 0..4 que exploran los
   // detectores en esta serie de 8 velas.
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   for(int i = 0; i < n; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60; h[i] = 100.0; l[i] = 95.0; o[i] = 97.5; c[i] = 97.5;
     }

   // --- Caso 1: SWEEP_BREACH_P3 valido. P1=80, P3=90. Perfora P3 en rates[3]
   // (low=88, > P1) sin recuperarse en la propia vela (close=89 <= P3), y se
   // recupera dos velas mas tarde en rates[2] (close=91 > P3). k=4 -> s=3,
   // k=5 -> s=2 (ver nota de indices arriba).
   MqlRates ratesA[];
   { datetime tA[]; double oA[], hA[], lA[], cA[];
     ArrayResize(tA,n); ArrayResize(oA,n); ArrayResize(hA,n); ArrayResize(lA,n); ArrayResize(cA,n);
     for(int i=0;i<n;i++){ tA[i]=t[i]; hA[i]=h[i]; lA[i]=l[i]; oA[i]=o[i]; cA[i]=c[i]; }
     oA[4]=88.5; hA[4]=90.0; lA[4]=88.0; cA[4]=89.0; // s=3: perfora, no recupera en la misma vela
     oA[5]=90.7; hA[5]=91.5; lA[5]=90.5; cA[5]=91.0; // s=2: recupera (close > P3)
     BuildRatesSeries(tA, oA, hA, lA, cA, ratesA); }
   SPatternPoints pointsA = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepA(SWEEP_BREACH_P3, 0.10, 3, 5);
   bool sweptA;
   sweepA.Evaluate(ratesA, DIR_BUY, pointsA, sweptA);
   Assert(sweptA, "LiquiditySweep: BREACH_P3 valido detecta el barrido");
   if(sweptA)
      Assert(pointsA.sweep_kind == SWEEP_BREACH_P3, "LiquiditySweep: modo detectado es BREACH_P3");

   // --- Caso 2: perforacion sin recuperacion dentro de max_sweep_bars -> no es sweep.
   // Mismo perfora en s=3 (low=88) pero NINGUN cierre en la ventana (s=3..0)
   // vuelve a superar P3=90.
   MqlRates ratesB[];
   { datetime tB[]; double oB[], hB[], lB[], cB[];
     ArrayResize(tB,n); ArrayResize(oB,n); ArrayResize(hB,n); ArrayResize(lB,n); ArrayResize(cB,n);
     for(int i=0;i<n;i++){ tB[i]=t[i]; hB[i]=h[i]; lB[i]=l[i]; oB[i]=o[i]; cB[i]=c[i]; }
     oB[4]=88.5; hB[4]=90.0; lB[4]=88.0; cB[4]=89.0; // s=3: perfora
     oB[5]=88.5; hB[5]=90.0; lB[5]=88.0; cB[5]=89.0; // s=2: sigue sin recuperar
     oB[6]=88.5; hB[6]=90.0; lB[6]=88.0; cB[6]=89.0; // s=1: sigue sin recuperar
     oB[7]=88.5; hB[7]=90.0; lB[7]=88.0; cB[7]=89.0; // s=0: sigue sin recuperar
     BuildRatesSeries(tB, oB, hB, lB, cB, ratesB); }
   SPatternPoints pointsB = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepB(SWEEP_BREACH_P3, 0.10, 3, 5);
   bool sweptB;
   sweepB.Evaluate(ratesB, DIR_BUY, pointsB, sweptB);
   Assert(!sweptB, "LiquiditySweep: perforacion sin recuperacion no es un barrido valido");

   // --- Caso 3: perforacion mas alla de P1 invalida el barrido.
   // s=3 perfora incluso por debajo de P1=80 (low=75) -> invalido sin
   // importar que una vela posterior (s=2) hubiera cerrado por encima de P3.
   MqlRates ratesC[];
   { datetime tC[]; double oC[], hC[], lC[], cC[];
     ArrayResize(tC,n); ArrayResize(oC,n); ArrayResize(hC,n); ArrayResize(lC,n); ArrayResize(cC,n);
     for(int i=0;i<n;i++){ tC[i]=t[i]; hC[i]=h[i]; lC[i]=l[i]; oC[i]=o[i]; cC[i]=c[i]; }
     oC[4]=76.0; hC[4]=78.0; lC[4]=75.0; cC[4]=76.0; // s=3: perfora mas alla de P1=80
     oC[5]=90.7; hC[5]=91.5; lC[5]=90.5; cC[5]=91.0; // s=2: cerraria por encima de P3, pero ya es invalido
     BuildRatesSeries(tC, oC, hC, lC, cC, ratesC); }
   SPatternPoints pointsC = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepC(SWEEP_BREACH_P3, 0.10, 3, 5);
   bool sweptC;
   sweepC.Evaluate(ratesC, DIR_BUY, pointsC, sweptC);
   Assert(!sweptC, "LiquiditySweep: perforar mas alla de P1 invalida el barrido");

   // --- Caso 4: SWEEP_INTERNAL valido (no perfora P3, solo forma un minimo interno y se recupera).
   // s=4 (la primera vela explorada, justo tras P4) fija el cluster interno en
   // low=92 (>= P3=90, no perfora). s=3 no marca un minimo mas extremo
   // (low=93 >= 92) y cierra por encima del cluster (close=93.5 > 92) ->
   // recuperacion.
   MqlRates ratesD[];
   { datetime tD[]; double oD[], hD[], lD[], cD[];
     ArrayResize(tD,n); ArrayResize(oD,n); ArrayResize(hD,n); ArrayResize(lD,n); ArrayResize(cD,n);
     for(int i=0;i<n;i++){ tD[i]=t[i]; hD[i]=h[i]; lD[i]=l[i]; oD[i]=o[i]; cD[i]=c[i]; }
     oD[3]=93.0; hD[3]=94.0; lD[3]=92.0; cD[3]=93.0; // s=4: fija el cluster interno en 92
     oD[4]=93.2; hD[4]=94.0; lD[4]=93.0; cD[4]=93.5; // s=3: no supera el cluster, cierra por encima -> recupera
     BuildRatesSeries(tD, oD, hD, lD, cD, ratesD); }
   SPatternPoints pointsD = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepD(SWEEP_INTERNAL, 0.10, 3, 5);
   bool sweptD;
   sweepD.Evaluate(ratesD, DIR_BUY, pointsD, sweptD);
   Assert(sweptD, "LiquiditySweep: INTERNAL valido detecta el barrido");
   if(sweptD)
      Assert(pointsD.sweep_kind == SWEEP_INTERNAL, "LiquiditySweep: modo detectado es INTERNAL");

   // --- Caso 5: SWEEP_ANY acepta un BREACH_P3 valido igual que el modo especifico.
   SPatternPoints pointsE = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepE(SWEEP_ANY, 0.10, 3, 5);
   bool sweptE;
   sweepE.Evaluate(ratesA, DIR_BUY, pointsE, sweptE);
   Assert(sweptE, "LiquiditySweep: SWEEP_ANY acepta un BREACH_P3 valido");
  }

#endif // FOURPOINTS_LIQUIDITYSWEEPTESTS_MQH
