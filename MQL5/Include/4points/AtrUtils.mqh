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
//|                                                                   |
//| CONTRATO DEL CENTINELA -1.0 (politica fail-closed)                |
//|                                                                   |
//| El calculo necesita shift + period < ArraySize(rates), porque la  |
//| ultima vela de la ventana usa rates[shift+period].close como      |
//| cierre previo. Las ~period velas mas ANTIGUAS de cualquier        |
//| ventana cargada quedan por tanto sin ATR: no es un caso de test,  |
//| pasa en toda evaluacion real.                                     |
//|                                                                   |
//| Todo llamante debe tratar el -1.0 como "no se puede medir" y      |
//| RECHAZAR el candidato que dependia de esa medida, nunca           |
//| aceptarlo sin medir. Un umbral ATR que se desactiva solo cuando   |
//| falta historia viola en silencio la invariante del proyecto de    |
//| "ningun umbral en pips fijos, todo en multiplos de ATR": el       |
//| candidato pasaria sin ningun umbral en absoluto.                  |
//|                                                                   |
//| Excepcion unica y explicita: si el multiplicador del umbral es    |
//| 0.0 el filtro esta desactivado por configuracion y no hay nada    |
//| que medir; en ese caso el candidato pasa. Config::Validate exige  |
//| min_leg_atr > 0 y min_impulse_atr > 0, asi que esa excepcion solo |
//| se da en los tests que aislan otra logica.                        |
//|                                                                   |
//| Sitios que aplican esta politica:                                 |
//|   SwingDetector      - filtro de pierna minima                    |
//|   PatternDetector    - filtro de impulso P1->P2                   |
//|   BreakoutValidator  - cuerpo minimo en ATR                       |
//|   LiquiditySweep     - tolerancia de extremos iguales (INTERNAL)  |
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
