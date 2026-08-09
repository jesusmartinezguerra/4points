#ifndef FOURPOINTS_ATRUTILSTESTS_MQH
#define FOURPOINTS_ATRUTILSTESTS_MQH

#include <4points/AtrUtils.mqh>

void RunAtrUtilsTests()
  {
   // Serie con True Range constante = 2.0 en cada vela (high-low=2, sin gaps).
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, 6); ArrayResize(o, 6); ArrayResize(h, 6); ArrayResize(l, 6); ArrayResize(c, 6);
   for(int i = 0; i < 6; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60;
      o[i] = 100.0; h[i] = 101.0; l[i] = 99.0; c[i] = 100.0;
     }
   MqlRates rates[];
   BuildRatesSeries(t, o, h, l, c, rates);

   Assert(MathAbs(SimpleATR(rates, 5, 0) - 2.0) < 0.0001, "AtrUtils: TR constante da ATR = TR");
   Assert(SimpleATR(rates, 5, 1) < 0.0, "AtrUtils: sin barras suficientes devuelve -1");
   Assert(MathAbs(SimpleATR(rates, 3, 1) - 2.0) < 0.0001, "AtrUtils: shift > 0 usa la ventana correcta");
  }

#endif // FOURPOINTS_ATRUTILSTESTS_MQH
