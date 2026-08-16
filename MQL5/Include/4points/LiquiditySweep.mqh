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

         // L_s es el minimo (BUY) / maximo (SELL) de TODO el barrido, no solo
         // de la vela de la primera perforacion: se actualiza vela a vela
         // mientras se recorre la ventana de recuperacion, y "mas alla de P1"
         // se revalida contra ese extremo corrido en cada paso, no una sola
         // vez al principio. Si el precio sigue cayendo (BUY) / subiendo
         // (SELL) despues de la primera perforacion y cruza P1 en una vela
         // posterior, el barrido queda invalidado aunque luego recupere.
         double   extreme      = (direction == DIR_BUY) ? rates[i].low : rates[i].high;
         datetime extreme_time = rates[i].time;

         for(int j = i; j >= 0 && (i - j) <= m_max_sweep_bars; j--)
           {
            double candidate     = (direction == DIR_BUY) ? rates[j].low : rates[j].high;
            bool   more_extreme  = (direction == DIR_BUY) ? (candidate < extreme) : (candidate > extreme);
            if(more_extreme)
              {
               extreme      = candidate;
               extreme_time = rates[j].time;
              }

            bool beyond_origin = (direction == DIR_BUY) ? (extreme <= p1_price) : (extreme >= p1_price);
            if(beyond_origin)
               return false;

            bool recovered = (direction == DIR_BUY) ? (rates[j].close > p3_level) : (rates[j].close < p3_level);
            if(recovered)
              {
               points.sweep_price = extreme;
               points.sweep_time  = extreme_time;
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

         // Politica fail-closed del centinela -1.0 de SimpleATR (ver AtrUtils.mqh).
         // La version anterior degradaba a tol=0.0 cuando el ATR no estaba
         // disponible, asumiendo que una tolerancia nula solo puede ser mas
         // estricta. No es cierto en ambos sentidos: con tol=0 una vela apenas
         // mas extrema que el cluster pasa a REDEFINIR el cluster (mas extremo,
         // por tanto mas facil de recuperar despues) en lugar de contarse como
         // parte del mismo cluster, de modo que hay series en las que tol=0
         // detecta un barrido que con la tolerancia real no existiria. Como
         // puede ser permisivo, se rechaza: sin ATR no hay "extremos iguales"
         // medibles y el modo INTERNAL no puede pronunciarse.
         double atr = SimpleATR(rates, m_atr_period, i);
         if(m_eq_tol_atr > 0.0 && atr <= 0.0)
            return false;
         double tol = (m_eq_tol_atr > 0.0) ? m_eq_tol_atr * atr : 0.0;
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
