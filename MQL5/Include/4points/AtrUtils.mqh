//+------------------------------------------------------------------+
//|                                                       AtrUtils.mqh |
//|  ATR compartido por los detectores que lo necesitan. Es la media  |
//|  simple del True Range, no la suavizada de Wilder — ver la nota   |
//|  de diseno en el plan de la Fase 1: es determinista sobre series  |
//|  sinteticas cortas, sin barras de precalentamiento.               |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_ATRUTILS_MQH
#define FOURPOINTS_ATRUTILS_MQH

//+------------------------------------------------------------------+
//| rates debe estar en orden de serie (indice 0 = mas reciente).     |
//| shift es el indice de la vela mas reciente incluida en el calculo.|
//| Devuelve -1.0 si no hay suficiente historia en el array.          |
//+------------------------------------------------------------------+
double SimpleATR(const MqlRates &rates[], const int period, const int shift = 0)
  {
   int size = ArraySize(rates);
   if(period <= 0 || shift < 0 || shift + period >= size)
      return -1.0;

   double sum = 0.0;
   for(int i = shift; i < shift + period; i++)
     {
      double prev_close = rates[i + 1].close;
      double tr = MathMax(rates[i].high - rates[i].low,
                  MathMax(MathAbs(rates[i].high - prev_close),
                          MathAbs(rates[i].low  - prev_close)));
      sum += tr;
     }
   return sum / period;
  }

#endif // FOURPOINTS_ATRUTILS_MQH
