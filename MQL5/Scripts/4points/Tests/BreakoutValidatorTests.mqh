#ifndef FOURPOINTS_BREAKOUTVALIDATORTESTS_MQH
#define FOURPOINTS_BREAKOUTVALIDATORTESTS_MQH

#include "TestHelpers.mqh"
#include <4points/BreakoutValidator.mqh>

MqlRates BuildBreakoutCandle(const double open, const double high, const double low, const double close)
  {
   MqlRates r;
   r.time = D'2026.01.01 00:10';
   r.open = open; r.high = high; r.low = low; r.close = close;
   r.tick_volume = 1; r.spread = 0; r.real_volume = 0;
   return r;
  }

void BuildBreakoutHistory(const MqlRates &breakout_candle, MqlRates &out[])
  {
   // 15 velas de historia plana (TR=2.0 cada una, para ATR determinista) + la vela de breakout en el indice 0.
   // CORREGIDO respecto al brief original: el brief llamaba ArraySetAsSeries(out, true)
   // DESPUES del bucle de asignacion. Las escrituras out[i]=... con la bandera todavia en
   // false (modo normal) van a la posicion fisica i tal cual; al activar AS_SERIES despues,
   // las LECTURAS futuras invierten el mapeo indice->posicion (indice 0 pasa a leer la
   // posicion fisica size-1), asi que rates[0] en Evaluate() terminaba leyendo la ultima
   // vela plana del bucle (i=15: open=100,high=101,low=99,close=100), no la vela de
   // breakout — exactamente el mismo patron de bug ya documentado en TestHelpers.mqh
   // (Task 3): la bandera debe fijarse ANTES de escribir para que escritura y lectura usen
   // el mismo mapeo. Confirmado empiricamente: con el orden del brief, el Caso 1 (que
   // requiere passed=true) fallaba porque rates[0] resultaba ser una vela plana con
   // body=0 y close=level, no la vela de breakout planteada.
   int history = 15;
   ArrayResize(out, history + 1);
   ArraySetAsSeries(out, true);
   out[0] = breakout_candle;
   for(int i = 1; i <= history; i++)
     {
      out[i].time  = D'2026.01.01 00:00' + (history - i) * 60;
      out[i].open  = 100.0; out[i].high = 101.0; out[i].low = 99.0; out[i].close = 100.0;
      out[i].tick_volume = 1; out[i].spread = 0; out[i].real_volume = 0;
     }
  }

void RunBreakoutValidatorTests()
  {
   // level=100, spread_price=0.10, atr(14) sobre la historia plana = 2.0 (TR constante).
   CBreakoutValidator v(0.55, 0.70, 0.50, 0.10, 1.50, 14);

   // --- Caso 1: las 5 condiciones se cumplen.
   // body=1.6 (open 100 -> close 101.6), range=1.8 (high 101.7, low 99.9), close_pos=(101.6-99.9)/1.8=0.944,
   // body_atr=1.6/2.0=0.8, penetration=101.6-100=1.6, min_penetration=max(0.10*2.0, 1.50*0.10)=max(0.2,0.15)=0.2.
   MqlRates candleOK = BuildBreakoutCandle(100.0, 101.7, 99.9, 101.6);
   MqlRates ratesOK[];
   BuildBreakoutHistory(candleOK, ratesOK);
   SBreakoutMetrics metricsOK; bool passedOK;
   v.Evaluate(ratesOK, DIR_BUY, 100.0, 0.10, metricsOK, passedOK);
   Assert(passedOK, "BreakoutValidator: las 5 condiciones cumplidas dan passed=true");

   // --- Caso 2: cuerpo insuficiente (body_ratio bajo) aunque el resto pase.
   // CORREGIDO respecto al brief original: los valores del brief (open=100.5, high=102.0,
   // low=99.9, close=101.0) dan body_ratio=0.5/2.1=0.238 (falla, ok) PERO tambien
   // close_pos=(101.0-99.9)/2.1=0.524<0.70 (falla) y body_atr=0.5/2.0=0.25<0.50 (falla) -
   // no aisla la condicion, contradice el comentario "aunque el resto pase". Se sustituye
   // por datos que fallan solo body_ratio:
   // open=100.4, close=101.5 (body=1.1), high=102.1, low=99.9 (range=2.2) ->
   // body_ratio=1.1/2.2=0.50 < 0.55 (falla, con margen 0.05),
   // close_pos=(101.5-99.9)/2.2=0.727 >= 0.70 (pasa, con margen 0.027),
   // body_atr=1.1/2.0=0.55 >= 0.50 (pasa, con margen 0.05),
   // penetration=101.5-100=1.5, min_penetration=max(0.10*2.0,1.50*0.10)=0.2 -> pasa.
   // cond_close: 101.5>100 pasa. Solo falla la condicion 2 (body_ratio).
   MqlRates candleWeakBody = BuildBreakoutCandle(100.4, 102.1, 99.9, 101.5);
   MqlRates ratesWeakBody[];
   BuildBreakoutHistory(candleWeakBody, ratesWeakBody);
   SBreakoutMetrics metricsWeakBody; bool passedWeakBody;
   v.Evaluate(ratesWeakBody, DIR_BUY, 100.0, 0.10, metricsWeakBody, passedWeakBody);
   Assert(!passedWeakBody, "BreakoutValidator: body_ratio insuficiente rechaza el breakout");
   // Las metricas deben quedar pobladas aunque el setup sea rechazado (el journal de la
   // Fase 2 las necesita tambien para los setups descartados). body_ratio=1.1/2.2=0.50
   // exacto para estos datos - verificado arriba. Si un futuro refactor moviera el calculo
   // de metricas detras de la comprobacion de "passed" (o lo envolviera en un if(passed)),
   // este Assert lo detectaria: metricsWeakBody.body_ratio se quedaria en el default 0.0
   // de SBreakoutMetrics::Reset(), fuera del rango 0.49..0.51.
   Assert(metricsWeakBody.body_ratio > 0.49 && metricsWeakBody.body_ratio < 0.51,
          "BreakoutValidator: metrics quedan pobladas aunque el breakout sea rechazado (body_ratio)");

   // --- Caso 3: breakout de mecha (close_pos bajo) - cierre lejos del maximo del rango.
   // CORREGIDO respecto al brief original: los valores del brief (open=100.0, high=102.0,
   // low=99.9, close=100.3) dan close_pos=(100.3-99.9)/2.1=0.19<0.70 (falla, ok) PERO
   // tambien body_ratio=0.3/2.1=0.143<0.55 (falla) y body_atr=0.3/2.0=0.15<0.50 (falla) -
   // tres condiciones caen a la vez, no aisla close_pos. Se sustituye por datos que solo
   // fallan la condicion 3:
   // open=99.4, close=101.0 (body=1.6), high=101.9, low=99.4 (range=2.5, sin mecha inferior,
   // toda la mecha es superior: 101.9-101.0=0.9) ->
   // body_ratio=1.6/2.5=0.64 >= 0.55 (pasa, margen 0.09),
   // close_pos=(101.0-99.4)/2.5=0.64 < 0.70 (falla, margen 0.06) - cierre lejos del maximo,
   // body_atr=1.6/2.0=0.8 >= 0.50 (pasa),
   // penetration=101.0-100=1.0, min_penetration=0.2 -> pasa. cond_close: 101.0>100 pasa.
   // Solo falla la condicion 3 (close_pos).
   MqlRates candleWick = BuildBreakoutCandle(99.4, 101.9, 99.4, 101.0);
   MqlRates ratesWick[];
   BuildBreakoutHistory(candleWick, ratesWick);
   SBreakoutMetrics metricsWick; bool passedWick;
   v.Evaluate(ratesWick, DIR_BUY, 100.0, 0.10, metricsWick, passedWick);
   Assert(!passedWick, "BreakoutValidator: cierre en mecha (close_pos bajo) rechaza el breakout");

   // --- Caso 4: penetracion insuficiente del nivel.
   // Para aislar solo la condicion 5, se sube el body/close_pos y se deja la penetracion corta:
   // open=99.0, close=100.05, high=100.1, low=98.9 -> body=1.05, range=1.2, body_ratio=0.875,
   // close_pos=(100.05-98.9)/1.2=0.958, body_atr=1.05/2.0=0.525 (>=0.50 ok), penetration=0.05,
   // min_penetration=max(0.10*2.0,1.50*0.10)=0.2 -> 0.05 < 0.2, falla solo la condicion 5.
   // Verificado: aritmetica correcta, sin cambios respecto al brief.
   MqlRates candlePenetration = BuildBreakoutCandle(99.0, 100.1, 98.9, 100.05);
   MqlRates ratesPenetration[];
   BuildBreakoutHistory(candlePenetration, ratesPenetration);
   SBreakoutMetrics metricsPenetration; bool passedPenetration;
   v.Evaluate(ratesPenetration, DIR_BUY, 100.0, 0.10, metricsPenetration, passedPenetration);
   Assert(!passedPenetration, "BreakoutValidator: penetracion insuficiente del nivel rechaza el breakout");
   // Misma razon que en el Caso 2: penetration=100.05-100=0.05, spread_price=0.10 ->
   // penetration_spreads=0.05/0.10=0.5 exacto - verificado arriba. Confirma que
   // penetration_spreads se calcula y guarda en metrics pese a passed=false.
   Assert(metricsPenetration.penetration_spreads > 0.4 && metricsPenetration.penetration_spreads < 0.6,
          "BreakoutValidator: metrics quedan pobladas aunque el breakout sea rechazado (penetration_spreads)");

   // --- Caso 5: no rompe el nivel (close <= level) -> rechazado por la condicion 1 sin importar el resto.
   MqlRates candleNoBreak = BuildBreakoutCandle(99.0, 100.1, 98.9, 99.9);
   MqlRates ratesNoBreak[];
   BuildBreakoutHistory(candleNoBreak, ratesNoBreak);
   SBreakoutMetrics metricsNoBreak; bool passedNoBreak;
   v.Evaluate(ratesNoBreak, DIR_BUY, 100.0, 0.10, metricsNoBreak, passedNoBreak);
   Assert(!passedNoBreak, "BreakoutValidator: cierre que no supera el nivel rechaza el breakout");

   // --- Caso 6: las 5 condiciones se cumplen en DIR_SELL (espejo del Caso 1).
   // Hasta este caso TODOS los tests de esta bateria usaban DIR_BUY, dejando sin
   // cobertura las ramas SELL de close_pos, cond_close y penetration.
   //
   // Espejo del Caso 1 reflejado sobre level=100:
   //   open=100.0, close=98.4 -> body = |98.4 - 100.0| = 1.6
   //   high=100.1, low=98.3   -> range = 100.1 - 98.3 = 1.8
   //   body_ratio = 1.6 / 1.8 = 0.889 >= 0.55                      pasa
   //   close_pos (SELL) = (high - close)/range = (100.1-98.4)/1.8
   //                    = 1.7/1.8 = 0.944 >= 0.70                  pasa
   //   ATR de la historia plana = 2.0 -> body_atr = 1.6/2.0 = 0.8 >= 0.50  pasa
   //   penetration (SELL) = level - close = 100.0 - 98.4 = 1.6
   //   min_penetration = max(0.10*2.0, 1.50*0.10) = max(0.2, 0.15) = 0.2
   //                    -> 1.6 >= 0.2                              pasa
   //   cond_close (SELL): 98.4 < 100.0                             pasa
   // Geometria OHLC valida: low 98.3 <= close 98.4 < open 100.0 <= high 100.1.
   MqlRates candleSellOK = BuildBreakoutCandle(100.0, 100.1, 98.3, 98.4);
   MqlRates ratesSellOK[];
   BuildBreakoutHistory(candleSellOK, ratesSellOK);
   SBreakoutMetrics metricsSellOK; bool passedSellOK;
   v.Evaluate(ratesSellOK, DIR_SELL, 100.0, 0.10, metricsSellOK, passedSellOK);
   Assert(passedSellOK, "BreakoutValidator: las 5 condiciones cumplidas en DIR_SELL dan passed=true");
   if(passedSellOK)
      Assert(metricsSellOK.close_pos > 0.94 && metricsSellOK.close_pos < 0.95,
             "BreakoutValidator: close_pos en DIR_SELL se mide desde el maximo (0.944)");

   // --- Caso 7: vela plana (doji con high == low) -> rechazada, pero las metricas
   // que NO dependen del rango deben quedar calculadas igualmente.
   // Antes de este fix, el guard `if(range <= 0.0) return true;` estaba delante del
   // calculo de la penetracion y devolvia los ceros de Reset(), dejando al journal
   // de la Fase 2 sin dato para un caso de rechazo frecuente.
   //
   // Vela: open=high=low=close=100.5, level=100.0, spread_price=0.10, ATR=2.0.
   //   range = 0 -> body_ratio, close_pos y body_atr se quedan en 0.0 (correcto:
   //   sin rango son indefinidos).
   //   penetration = close - level = 100.5 - 100.0 = 0.5
   //   penetration_atr     = 0.5 / 2.0  = 0.25
   //   penetration_spreads = 0.5 / 0.10 = 5.0
   MqlRates candleDoji = BuildBreakoutCandle(100.5, 100.5, 100.5, 100.5);
   MqlRates ratesDoji[];
   BuildBreakoutHistory(candleDoji, ratesDoji);
   SBreakoutMetrics metricsDoji; bool passedDoji;
   v.Evaluate(ratesDoji, DIR_BUY, 100.0, 0.10, metricsDoji, passedDoji);
   Assert(!passedDoji, "BreakoutValidator: vela sin rango (doji plano) rechaza el breakout");
   Assert(MathAbs(metricsDoji.penetration_atr - 0.25) < 0.0001,
          "BreakoutValidator: penetration_atr se calcula aunque la vela no tenga rango");
   Assert(MathAbs(metricsDoji.penetration_spreads - 5.0) < 0.0001,
          "BreakoutValidator: penetration_spreads se calcula aunque la vela no tenga rango");
   Assert(MathAbs(metricsDoji.body_ratio) < 0.0001 && MathAbs(metricsDoji.close_pos) < 0.0001,
          "BreakoutValidator: sin rango, body_ratio y close_pos quedan en su valor por defecto");
  }

#endif // FOURPOINTS_BREAKOUTVALIDATORTESTS_MQH
