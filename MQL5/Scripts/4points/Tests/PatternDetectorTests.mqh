#ifndef FOURPOINTS_PATTERNDETECTORTESTS_MQH
#define FOURPOINTS_PATTERNDETECTORTESTS_MQH

#include <4points/PatternDetector.mqh>

// Construye una serie de 20 velas planas (high=100, low=95, open=close=97.5) y aplica
// los picos/valles indicados en (indice, high, low) para formar swings a medida.
// idx, hval, lval en paralelo; usar 0.0 para "no tocar" ese lado en esa vela.
//
// Restriccion importante para quien anada casos nuevos: open/close quedan fijos en
// 97.5 en TODAS las velas (tambien las tocadas). Por tanto cualquier low plantado debe
// ser < 97.5 y cualquier high plantado debe ser > 97.5, o la vela resultante es
// invalida (low/high por el lado equivocado del cuerpo). Ademas, para que un punto
// plantado se confirme como swing fractal (izquierda/derecha = 2), su valor debe ser
// estrictamente mas extremo que el fondo plano (high=100, low=95) de sus 2 vecinos a
// cada lado -- si esos vecinos no han sido tambien tocados. Un "low" plantado por
// ENCIMA de 95 (o un "high" por DEBAJO de 100) nunca se confirma como swing, por mucho
// que la aritmetica del retroceso parezca correcta sobre el papel.
void BuildPatternScenario(const int &idx[], const double &hval[], const double &lval[], const int count,
                           MqlRates &out[])
  {
   int n = 20;
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   for(int i = 0; i < n; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60;
      h[i] = 100.0; l[i] = 95.0; o[i] = 97.5; c[i] = 97.5;
     }
   for(int i = 0; i < count; i++)
     {
      if(hval[i] != 0.0) h[idx[i]] = hval[i];
      if(lval[i] != 0.0) l[idx[i]] = lval[i];
     }
   BuildRatesSeries(t, o, h, l, c, out);
  }

void RunPatternDetectorTests()
  {
   // atr_period=3 (no 14): con 20 velas y fractal 2/2, el swing P2 de estos escenarios
   // cae en bar_shift=12. SimpleATR exige shift+period<size (ver AtrUtils.mqh), y
   // 12+14=26 >= 20 devuelve siempre -1, lo que apagaria el filtro de impulso sin
   // querer (el mismo bug de "ATR vacuo" que aparecio en SwingDetectorTests Caso 3).
   // Con periodo=3, 12+3=15<20 y el ATR es un numero real y computable.
   CPatternDetector det(2, 2, 0.0, 3, 1.0, 0.20, 0.80);

   // --- Caso 1: secuencia completa P1(low)->P2(high)->P3(higher low, retroceso 50%)->P4(higher high).
   // P1=70 y P3=90 deben quedar por debajo del fondo plano (low=95) para confirmarse
   // como swing low; P2=110 y P4=115 deben quedar por encima del fondo plano (high=100)
   // para confirmarse como swing high. Retroceso = (P2-P3)/(P2-P1) = (110-90)/(110-70) = 20/40 = 0.5.
   int    idx1[]  = {3, 7, 11, 15};
   double hval1[] = {0.0, 110.0, 0.0, 115.0};
   double lval1[] = {70.0, 0.0, 90.0, 0.0};
   MqlRates rates1[];
   BuildPatternScenario(idx1, hval1, lval1, 4, rates1);

   SPatternPoints points1; EPatternStage stage1;
   det.Evaluate(rates1, DIR_BUY, points1, stage1);
   Assert(stage1 == STAGE_P4, "PatternDetector: secuencia completa llega a STAGE_P4");
   if(stage1 == STAGE_P4)
     {
      Assert(MathAbs(points1.p1.price - 70.0) < 0.0001, "PatternDetector: P1 = 70 (low de indice 3)");
      Assert(MathAbs(points1.p2.price - 110.0) < 0.0001, "PatternDetector: P2 = 110 (high de indice 7)");
      Assert(MathAbs(points1.p3.price - 90.0) < 0.0001, "PatternDetector: P3 = 90 (low de indice 11)");
      Assert(MathAbs(points1.p4.price - 115.0) < 0.0001, "PatternDetector: P4 = 115 (high de indice 15)");
     }

   // --- Caso 2: sin P4 -> P2 nunca es superado, se queda en STAGE_P3.
   int    idx2[]  = {3, 7, 11};
   double hval2[] = {0.0, 110.0, 0.0};
   double lval2[] = {70.0, 0.0, 90.0};
   MqlRates rates2[];
   BuildPatternScenario(idx2, hval2, lval2, 3, rates2);
   SPatternPoints points2; EPatternStage stage2;
   det.Evaluate(rates2, DIR_BUY, points2, stage2);
   Assert(stage2 == STAGE_P3, "PatternDetector: sin P4 se queda en STAGE_P3");

   // --- Caso 3: retroceso demasiado profundo (>80%) -> ese candidato a P3 se descarta.
   // P3=74 (por debajo del fondo plano 95, por tanto swing low valido, pero muy cerca de
   // P1=70). Retroceso = (110-74)/(110-70) = 36/40 = 0.9, fuera de [0.2, 0.8].
   int    idx3[]  = {3, 7, 11};
   double hval3[] = {0.0, 110.0, 0.0};
   double lval3[] = {70.0, 0.0, 74.0};
   MqlRates rates3[];
   BuildPatternScenario(idx3, hval3, lval3, 3, rates3);
   SPatternPoints points3; EPatternStage stage3;
   det.Evaluate(rates3, DIR_BUY, points3, stage3);
   Assert(stage3 == STAGE_P2, "PatternDetector: retroceso fuera de rango no confirma P3");

   // --- Caso 4: retroceso demasiado superficial (<20%).
   // P1=10 (muy por debajo del fondo, deja una pierna P1->P2 amplia) y P3=90 (justo por
   // debajo del fondo plano 95, por tanto swing low valido, pero muy cerca de P2=105).
   // Retroceso = (105-90)/(105-10) = 15/95 = 0.1579, fuera de [0.2, 0.8].
   int    idx4[]  = {3, 7, 11};
   double hval4[] = {0.0, 105.0, 0.0};
   double lval4[] = {10.0, 0.0, 90.0};
   MqlRates rates4[];
   BuildPatternScenario(idx4, hval4, lval4, 3, rates4);
   SPatternPoints points4; EPatternStage stage4;
   det.Evaluate(rates4, DIR_BUY, points4, stage4);
   Assert(stage4 == STAGE_P2, "PatternDetector: retroceso demasiado superficial no confirma P3");

   // --- Caso 5: impulso P1->P2 demasiado pequeno frente a min_impulse_atr -> nunca llega a P2.
   // Reutiliza rates1 (P1=70, P2=110, pierna=40). atr_period=3 (igual que "det", no 14)
   // para que el ATR en el bar_shift de P2 sea un numero real (~8.33 sobre esta serie) y
   // el rechazo se deba de verdad al umbral de impulso, no a un ATR vacuo por falta de
   // historia -- con periodo=14 el ATR ahi tambien da -1 y el caso "pasaria" por la
   // razon equivocada.
   CPatternDetector det_strict(2, 2, 0.0, 3, 50.0, 0.20, 0.80); // exige impulso >= 50*ATR, imposible aqui
   SPatternPoints points5; EPatternStage stage5;
   det_strict.Evaluate(rates1, DIR_BUY, points5, stage5);
   Assert(stage5 == STAGE_P1, "PatternDetector: impulso insuficiente nunca confirma P2");

   // --- Caso 6: direccion SELL es el espejo (P1=high, P2=low, P3=lower high, P4=lower low).
   // P1=130 y P3=110 deben quedar por encima del fondo plano (high=100) para confirmarse
   // como swing high; P2=90 y P4=85 deben quedar por debajo del fondo plano (low=95)
   // para confirmarse como swing low. Retroceso = (P3-P2)/(P1-P2) = (110-90)/(130-90) = 20/40 = 0.5.
   int    idx6[]  = {3, 7, 11, 15};
   double hval6[] = {130.0, 0.0, 110.0, 0.0};
   double lval6[] = {0.0, 90.0, 0.0, 85.0};
   MqlRates rates6[];
   BuildPatternScenario(idx6, hval6, lval6, 4, rates6);
   SPatternPoints points6; EPatternStage stage6;
   det.Evaluate(rates6, DIR_SELL, points6, stage6);
   Assert(stage6 == STAGE_P4, "PatternDetector: secuencia SELL (espejo) llega a STAGE_P4");
  }

#endif // FOURPOINTS_PATTERNDETECTORTESTS_MQH
