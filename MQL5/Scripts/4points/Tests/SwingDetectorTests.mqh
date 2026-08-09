#ifndef FOURPOINTS_SWINGDETECTORTESTS_MQH
#define FOURPOINTS_SWINGDETECTORTESTS_MQH

#include <4points/SwingDetector.mqh>

void RunSwingDetectorTests()
  {
   // --- Caso 1: alternancia perfecta low-high-low-high, fractal 2/2, sin filtro de pierna.
   // Cronologico (indice 0 = mas antiguo): low en 2, high en 5, low en 8, high en 11.
   datetime t[]; double o[], h[], l[], c[];
   int n = 14;
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   double base_high[] = {100,100,100,100,100,100,100,100,100,100,100,100,100,100};
   double base_low[]  = {95,95,95,95,95,95,95,95,95,95,95,95,95,95};
   for(int i = 0; i < n; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60;
      h[i] = base_high[i];
      l[i] = base_low[i];
      o[i] = (h[i] + l[i]) / 2.0;
      c[i] = o[i];
     }
   l[2] = 90.0;  // swing low
   h[5] = 105.0; // swing high
   l[8] = 88.0;  // swing low (mas bajo que el de indice 2)
   h[11] = 106.0; // swing high

   MqlRates rates1[];
   BuildRatesSeries(t, o, h, l, c, rates1);

   CSwingDetector det(2, 2, 0.0, 14); // min_leg_atr = 0 desactiva el filtro de pierna
   SSwing swings1[];
   bool ok1 = det.Evaluate(rates1, swings1);
   Assert(ok1 && ArraySize(swings1) == 4, "SwingDetector: alternancia perfecta detecta 4 swings");
   if(ArraySize(swings1) == 4)
     {
      Assert(swings1[0].type == SWING_LOW && MathAbs(swings1[0].price - 90.0) < 0.0001,
             "SwingDetector: primer swing es el low de indice 2");
      Assert(swings1[3].type == SWING_HIGH && MathAbs(swings1[3].price - 106.0) < 0.0001,
             "SwingDetector: cuarto swing es el high de indice 11");
     }

   // --- Caso 2: dos highs consecutivos -> se conserva el mas alto.
   double h2[] = {100,100,100,100,100,100,100,100,100,100,100,100,100,100};
   double l2[] = {95,95,95,95,95,95,95,95,95,95,95,95,95,95};
   double o2[], c2[]; datetime t2[];
   ArrayResize(o2, n); ArrayResize(c2, n); ArrayResize(t2, n);
   for(int i = 0; i < n; i++)
     {
      t2[i] = D'2026.01.01 00:00' + i * 60;
      o2[i] = (h2[i] + l2[i]) / 2.0;
      c2[i] = o2[i];
     }
   l2[2] = 90.0;   // low inicial
   h2[5] = 105.0;  // high #1
   h2[8] = 108.0;  // high #2, mas alto -> debe reemplazar al #1

   MqlRates rates2[];
   BuildRatesSeries(t2, o2, h2, l2, c2, rates2);
   SSwing swings2[];
   det.Evaluate(rates2, swings2);
   Assert(ArraySize(swings2) == 2, "SwingDetector: dos highs seguidos colapsan a uno solo");
   if(ArraySize(swings2) == 2)
      Assert(MathAbs(swings2[1].price - 108.0) < 0.0001, "SwingDetector: se conserva el high mas alto");

   // --- Caso 3: filtro de pierna minima descarta un swing concreto (calculo exacto).
   // Serie dedicada (no rates1): con rates1, atr_period=14 y size=14, el guard de
   // SimpleATR (shift+period >= size) es cierto para todo shift, así que ATR siempre
   // devuelve -1 y el filtro nunca se ejecuta -- ese fue el bug detectado en review.
   // Aqui atr_period=3 << n3=10 para que el ATR sea siempre computable.
   // open=close=97.5 constante en todas las velas: asi TR(i) = max(high-low,
   // |high-97.5|, |low-97.5|) sin contribucion de gaps de cierre entre velas,
   // y se puede calcular a mano vela por vela.
   // Velas por defecto: high=100, low=95 -> TR = max(5, 2.5, 2.5) = 5.
   // low en indice cronologico 2 -> 90.0 (swing low).
   // high en indice cronologico 6 -> 100.5, apenas por encima del high por defecto
   //   de 100 (el minimo que aun confirma fractal), para dejar la pierna
   //   low(90.0)->high(100.5) = 10.5 deliberadamente corta frente al ATR.
   //   TR(high=100.5) = max(100.5-95, |100.5-97.5|, |95-97.5|) = max(5.5,3.0,2.5) = 5.5.
   datetime t3[]; double o3[], h3[], l3[], c3[];
   int n3 = 10;
   ArrayResize(t3, n3); ArrayResize(o3, n3); ArrayResize(h3, n3); ArrayResize(l3, n3); ArrayResize(c3, n3);
   for(int i = 0; i < n3; i++)
     {
      t3[i] = D'2026.01.01 00:00' + i * 60;
      h3[i] = 100.0;
      l3[i] = 95.0;
      o3[i] = 97.5;
      c3[i] = 97.5;
     }
   l3[2] = 90.0;   // swing low
   h3[6] = 100.5;  // swing high de pierna corta

   MqlRates rates3[];
   BuildRatesSeries(t3, o3, h3, l3, c3, rates3);
   // BuildRatesSeries invierte cronologico -> serie (indice 0 = mas reciente):
   // bar_shift = n3 - 1 - indice_cronologico. Low(indice2) -> bar_shift=7.
   // High(indice6) -> bar_shift=3.
   //
   // SimpleATR(rates3, periodo=3, shift=3) promedia TR en bar_shift 3,4,5:
   //   bar_shift 3 = la propia vela del high swing, TR = 5.5 (ver arriba).
   //   bar_shift 4 y 5 = velas por defecto, TR = 5 cada una.
   //   ATR = (5.5 + 5 + 5) / 3 = 15.5 / 3 = 5.1666...
   // Pierna = |100.5 - 90.0| = 10.5.
   // Umbral de rechazo (leg < min_leg_atr * atr): min_leg_atr > 10.5 / 5.1666... = 2.0323.
   // Con min_leg_atr = 2.5: 2.5 * 5.1666... = 12.9166... > 10.5 -> la pierna SE DESCARTA
   // (margen amplio sobre el umbral 2.0323, sin riesgo de redondeo en punto flotante).

   CSwingDetector det_unfiltered3(2, 2, 0.0, 3); // mismo periodo de ATR, sin filtro
   SSwing swings3_unfiltered[];
   det_unfiltered3.Evaluate(rates3, swings3_unfiltered);
   Assert(ArraySize(swings3_unfiltered) == 2, "SwingDetector: caso 3 sin filtro detecta low y high");

   CSwingDetector det_strict(2, 2, 2.5, 3); // exige pierna >= 2.5 * ATR(periodo 3)
   SSwing swings3[];
   det_strict.Evaluate(rates3, swings3);
   Assert(ArraySize(swings3) == 1, "SwingDetector: filtro de pierna descarta el high de pierna corta");
   if(ArraySize(swings3) == 1)
      Assert(swings3[0].type == SWING_LOW && MathAbs(swings3[0].price - 90.0) < 0.0001,
             "SwingDetector: sobrevive el low, el high queda filtrado");

   // --- Caso 4: los ultimos `right` bars no permiten confirmar swing ahi.
   // Con fractal 2/2 y 14 velas, el ultimo swing detectable esta en indice <= n-1-2=11.
   bool any_beyond = false;
   for(int i = 0; i < ArraySize(swings1); i++)
      if(swings1[i].bar_shift < 2) // bar_shift medido en el array 0..n-1, aqui el "reciente" es el indice bajo tras invertir
         any_beyond = true;
   Assert(!any_beyond, "SwingDetector: no confirma swings sin sus N_right barras");
  }

#endif // FOURPOINTS_SWINGDETECTORTESTS_MQH
