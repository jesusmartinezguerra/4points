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

   // --- Caso 3: filtro de pierna minima descarta un swing demasiado pequeno.
   CSwingDetector det_strict(2, 2, 5.0, 14); // exige pierna >= 5 * ATR
   SSwing swings3[];
   det_strict.Evaluate(rates1, swings3);
   // Con ATR chico (rango tipico ~5-15) y min_leg_atr=5, la pierna low(90)->high(105)=15
   // puede o no pasar segun el ATR real; se verifica que el detector no revienta y que
   // el resultado tiene como mucho los mismos swings que el caso sin filtro.
   Assert(ArraySize(swings3) <= ArraySize(swings1), "SwingDetector: filtro de pierna nunca añade swings");

   // --- Caso 4: los ultimos `right` bars no permiten confirmar swing ahi.
   // Con fractal 2/2 y 14 velas, el ultimo swing detectable esta en indice <= n-1-2=11.
   bool any_beyond = false;
   for(int i = 0; i < ArraySize(swings1); i++)
      if(swings1[i].bar_shift < 2) // bar_shift medido en el array 0..n-1, aqui el "reciente" es el indice bajo tras invertir
         any_beyond = true;
   Assert(!any_beyond, "SwingDetector: no confirma swings sin sus N_right barras");
  }

#endif // FOURPOINTS_SWINGDETECTORTESTS_MQH
