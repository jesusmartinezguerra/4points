//+------------------------------------------------------------------+
//|                                                 LiquiditySweep.mqh |
//|  Barrido de liquidez tras P4: BREACH_P3 e INTERNAL. Ver           |
//|  docs/superpowers/specs/2026-08-06-4points-continuation-          |
//|  design.md §3 y la nota de diseno del plan de la Fase 1 sobre     |
//|  la interpretacion de INTERNAL.                                   |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_LIQUIDITYSWEEP_MQH
#define FOURPOINTS_LIQUIDITYSWEEP_MQH

#include <4points/Types.mqh>
#include <4points/AtrUtils.mqh>

class CLiquiditySweep
  {
private:
   ESweepMode m_mode;
   double     m_eq_tol_atr;
   int        m_atr_period;
   int        m_max_sweep_bars;

public:
   CLiquiditySweep(const ESweepMode mode, const double eq_tol_atr, const int atr_period, const int max_sweep_bars)
     {
      m_mode           = mode;
      m_eq_tol_atr     = eq_tol_atr;
      m_atr_period     = atr_period;
      m_max_sweep_bars = max_sweep_bars;
     }

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed,
             const EDirection direction, SPatternPoints &points, bool &swept)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, direction, points, swept);
     }

   bool Evaluate(const MqlRates &rates[], const EDirection direction, SPatternPoints &points, bool &swept)
     {
      swept = false;
      if(!points.p4.IsValid())
         return true;

      int search_start = points.p4.bar_shift - 1;
      if(search_start < 0)
         return true;

      if(m_mode == SWEEP_BREACH_P3 || m_mode == SWEEP_ANY)
        {
         if(TryBreach(rates, direction, points.p1.price, points.p3.price, search_start, points))
           {
            points.sweep_kind = SWEEP_BREACH_P3;
            swept = true;
            return true;
           }
        }

      if(m_mode == SWEEP_INTERNAL || m_mode == SWEEP_ANY)
        {
         if(TryInternal(rates, direction, points.p3.price, search_start, points))
           {
            points.sweep_kind = SWEEP_INTERNAL;
            swept = true;
            return true;
           }
        }

      return true;
     }

private:
   bool TryBreach(const MqlRates &rates[], const EDirection direction, const double p1_price,
                   const double p3_level, const int search_start, SPatternPoints &points)
     {
      for(int i = search_start; i >= 0 && (search_start - i) < m_max_sweep_bars; i--)
        {
         bool breaches = (direction == DIR_BUY) ? (rates[i].low < p3_level) : (rates[i].high > p3_level);
         if(!breaches)
            continue;

         bool beyond_origin = (direction == DIR_BUY) ? (rates[i].low <= p1_price) : (rates[i].high >= p1_price);
         if(beyond_origin)
            return false;

         double extreme = (direction == DIR_BUY) ? rates[i].low : rates[i].high;

         for(int j = i; j >= 0 && (i - j) <= m_max_sweep_bars; j--)
           {
            bool recovered = (direction == DIR_BUY) ? (rates[j].close > p3_level) : (rates[j].close < p3_level);
            if(recovered)
              {
               points.sweep_price = extreme;
               points.sweep_time  = rates[i].time;
               return true;
              }
           }
         return false;
        }
      return false;
     }

   bool TryInternal(const MqlRates &rates[], const EDirection direction, const double p3_level,
                     const int search_start, SPatternPoints &points)
     {
      double cluster_extreme = (direction == DIR_BUY) ? 999999999.0 : -999999999.0;
      int    cluster_shift   = -1;

      for(int i = search_start; i >= 0 && (search_start - i) < m_max_sweep_bars; i--)
        {
         double candidate = (direction == DIR_BUY) ? rates[i].low : rates[i].high;
         bool beyond_p3 = (direction == DIR_BUY) ? (candidate < p3_level) : (candidate > p3_level);
         if(beyond_p3)
            break; // eso ya es un BREACH_P3, no liquidez interna

         double atr = SimpleATR(rates, m_atr_period, i);
         double tol = (atr > 0.0) ? m_eq_tol_atr * atr : 0.0;
         bool more_extreme = (direction == DIR_BUY) ? (candidate < cluster_extreme - tol)
                                                      : (candidate > cluster_extreme + tol);
         if(cluster_shift < 0 || more_extreme)
           {
            cluster_extreme = candidate;
            cluster_shift   = i;
            continue; // esta misma vela establece el minimo, no puede recuperarlo en el mismo tick
           }

         bool recovered = (direction == DIR_BUY) ? (rates[i].close > cluster_extreme)
                                                    : (rates[i].close < cluster_extreme);
         if(recovered)
           {
            points.sweep_price = cluster_extreme;
            points.sweep_time  = rates[cluster_shift].time;
            return true;
           }
        }
      return false;
     }
  };

#endif // FOURPOINTS_LIQUIDITYSWEEP_MQH
