//+------------------------------------------------------------------+
//|                                                  SwingDetector.mqh |
//|  Fractal de N_left/N_right con alternancia forzada y filtro de    |
//|  pierna minima en ATR. Ver docs/superpowers/specs/               |
//|  2026-08-06-4points-continuation-design.md §1.                   |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_SWINGDETECTOR_MQH
#define FOURPOINTS_SWINGDETECTOR_MQH

#include <4points/Types.mqh>
#include <4points/AtrUtils.mqh>

class CSwingDetector
  {
private:
   int    m_left;
   int    m_right;
   double m_min_leg_atr;
   int    m_atr_period;

public:
   CSwingDetector(const int left, const int right, const double min_leg_atr, const int atr_period)
     {
      m_left        = left;
      m_right       = right;
      m_min_leg_atr = min_leg_atr;
      m_atr_period  = atr_period;
     }

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed, SSwing &swings[])
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, swings);
     }

   //+---------------------------------------------------------------+
   //| rates en orden de serie (indice 0 = mas reciente). Devuelve    |
   //| swings en orden cronologico ascendente (indice 0 = mas         |
   //| antiguo confirmado); swings[i].bar_shift referencia el indice  |
   //| en el rates[] recibido.                                       |
   //+---------------------------------------------------------------+
   bool Evaluate(const MqlRates &rates[], SSwing &swings[])
     {
      ArrayResize(swings, 0);
      int size = ArraySize(rates);
      if(size < m_left + m_right + 1)
         return true; // no hay suficientes velas para ningun swing, no es un error

      ESwingType last_type = SWING_NONE;

      // Recorre de mas antiguo a mas reciente: k empieza en el indice mas alto
      // valido (size-1-m_left) y desciende hasta m_right.
      for(int k = size - 1 - m_left; k >= m_right; k--)
        {
         bool is_high = true;
         bool is_low  = true;
         for(int j = 1; j <= m_left; j++)
           {
            if(rates[k].high <= rates[k + j].high) is_high = false;
            if(rates[k].low  >= rates[k + j].low)  is_low  = false;
           }
         for(int j = 1; j <= m_right; j++)
           {
            if(rates[k].high <= rates[k - j].high) is_high = false;
            if(rates[k].low  >= rates[k - j].low)  is_low  = false;
           }

         if(!is_high && !is_low)
            continue;

         // Si una vela cumple ambas condiciones a la vez (raro), se prioriza HIGH
         // de forma deterministica; ningun caso de test de la Fase 1 depende de esto.
         SSwing candidate;
         candidate.type      = is_high ? SWING_HIGH : SWING_LOW;
         candidate.bar_shift = k;
         candidate.time      = rates[k].time;
         candidate.price     = is_high ? rates[k].high : rates[k].low;

         AppendSwing(swings, candidate, last_type, rates);
        }

      return true;
     }

private:
   void AppendSwing(SSwing &swings[], const SSwing &candidate, ESwingType &last_type, const MqlRates &rates[])
     {
      int count = ArraySize(swings);

      if(count == 0)
        {
         ArrayResize(swings, 1);
         swings[0] = candidate;
         last_type = candidate.type;
         return;
        }

      SSwing last = swings[count - 1];

      if(candidate.type == last.type)
        {
         // Duplicado consecutivo: se conserva el mas extremo, no se abre pierna nueva.
         bool more_extreme = (candidate.type == SWING_HIGH) ? (candidate.price > last.price)
                                                              : (candidate.price < last.price);
         if(more_extreme)
            swings[count - 1] = candidate;
         return;
        }

      // Alterna correctamente: aplica el filtro de pierna minima contra el swing anterior.
      double leg = MathAbs(candidate.price - last.price);
      double atr = SimpleATR(rates, m_atr_period, candidate.bar_shift);
      if(atr > 0.0 && leg < m_min_leg_atr * atr)
         return; // pierna insuficiente: se descarta, no se actualiza last_type

      ArrayResize(swings, count + 1);
      swings[count] = candidate;
      last_type = candidate.type;
     }
  };

#endif // FOURPOINTS_SWINGDETECTOR_MQH
