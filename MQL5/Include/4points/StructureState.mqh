//+------------------------------------------------------------------+
//|                                                 StructureState.mqh |
//|  Maquina BOS por timeframe: BULL si el cierre supera al ultimo    |
//|  swing high confirmado, BEAR si cae bajo el ultimo swing low.     |
//|  Ver docs/superpowers/specs/2026-08-06-4points-continuation-      |
//|  design.md §2.                                                    |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_STRUCTURESTATE_MQH
#define FOURPOINTS_STRUCTURESTATE_MQH

#include <4points/Types.mqh>
#include <4points/SwingDetector.mqh>

class CStructureState
  {
private:
   CSwingDetector m_swings;

public:
   CStructureState(const int left, const int right, const double min_leg_atr, const int atr_period)
     : m_swings(left, right, min_leg_atr, atr_period) {}

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed, ETrendState &state)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, state);
     }

   //+---------------------------------------------------------------+
   //| Devuelve el estado final (el vigente en rates[0], la vela mas  |
   //| reciente), simulando hacia adelante desde la vela mas antigua. |
   //| Simplificacion deliberada de la Fase 1: un swing "activa" su   |
   //| nivel en su propia barra, no N_right barras despues; para el   |
   //| estado final de un analisis estatico esto no cambia el         |
   //| resultado y evita duplicar aqui la logica de streaming.        |
   //+---------------------------------------------------------------+
   bool Evaluate(const MqlRates &rates[], ETrendState &state)
     {
      state = TREND_NEUTRAL;

      SSwing swings[];
      if(!m_swings.Evaluate(rates, swings))
         return false;

      int size = ArraySize(rates);
      if(size == 0)
         return true;

      double last_high = 0.0;
      double last_low  = 0.0;
      bool   have_high = false;
      bool   have_low  = false;
      int    next_swing = 0; // recorre swings[] en su orden cronologico ascendente

      for(int k = size - 1; k >= 0; k--)
        {
         while(next_swing < ArraySize(swings) && swings[next_swing].bar_shift >= k)
           {
            if(swings[next_swing].type == SWING_HIGH) { last_high = swings[next_swing].price; have_high = true; }
            if(swings[next_swing].type == SWING_LOW)  { last_low  = swings[next_swing].price; have_low  = true; }
            next_swing++;
           }

         if(have_high && rates[k].close > last_high)
            state = TREND_BULL;
         else if(have_low && rates[k].close < last_low)
            state = TREND_BEAR;
        }

      return true;
     }
  };

#endif // FOURPOINTS_STRUCTURESTATE_MQH
