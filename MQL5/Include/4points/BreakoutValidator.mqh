//+------------------------------------------------------------------+
//|                                              BreakoutValidator.mqh |
//|  Las 5 condiciones de vela de breakout fuerte. Ver                |
//|  docs/superpowers/specs/2026-08-06-4points-continuation-          |
//|  design.md §4.                                                    |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_BREAKOUTVALIDATOR_MQH
#define FOURPOINTS_BREAKOUTVALIDATOR_MQH

#include <4points/Types.mqh>
#include <4points/AtrUtils.mqh>

class CBreakoutValidator
  {
private:
   double m_min_body_ratio;
   double m_min_close_pos;
   double m_min_body_atr;
   double m_min_penetration_atr;
   double m_min_penetration_spreads;
   int    m_atr_period;

public:
   CBreakoutValidator(const double min_body_ratio, const double min_close_pos, const double min_body_atr,
                       const double min_penetration_atr, const double min_penetration_spreads, const int atr_period)
     {
      m_min_body_ratio          = min_body_ratio;
      m_min_close_pos           = min_close_pos;
      m_min_body_atr            = min_body_atr;
      m_min_penetration_atr     = min_penetration_atr;
      m_min_penetration_spreads = min_penetration_spreads;
      m_atr_period              = atr_period;
     }

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed,
             const EDirection direction, const double level, const double spread_price,
             SBreakoutMetrics &metrics, bool &passed)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, direction, level, spread_price, metrics, passed);
     }

   //+---------------------------------------------------------------+
   //| rates[0] es la vela candidata a breakout. spread_price ya      |
   //| viene en precio (spread_points * _Point), no en puntos, para   |
   //| que esta funcion no dependa de _Point y sea testeable.         |
   //+---------------------------------------------------------------+
   bool Evaluate(const MqlRates &rates[], const EDirection direction, const double level,
                 const double spread_price, SBreakoutMetrics &metrics, bool &passed)
     {
      metrics.Reset();
      passed = false;
      if(ArraySize(rates) == 0)
         return false;

      MqlRates c = rates[0];
      double range = c.high - c.low;
      if(range <= 0.0)
         return true;

      double body = MathAbs(c.close - c.open);
      double atr  = SimpleATR(rates, m_atr_period, 1); // hasta la vela anterior, sin mirar la de breakout

      metrics.body_ratio = body / range;
      metrics.close_pos  = (direction == DIR_BUY) ? (c.close - c.low) / range : (c.high - c.close) / range;
      metrics.body_atr   = (atr > 0.0) ? body / atr : 0.0;

      double penetration = (direction == DIR_BUY) ? (c.close - level) : (level - c.close);
      metrics.penetration_atr     = (atr > 0.0) ? penetration / atr : 0.0;
      metrics.penetration_spreads = (spread_price > 0.0) ? penetration / spread_price : 0.0;

      bool cond_close     = (direction == DIR_BUY) ? (c.close > level) : (c.close < level);
      bool cond_body      = metrics.body_ratio >= m_min_body_ratio;
      bool cond_pos       = metrics.close_pos  >= m_min_close_pos;
      bool cond_body_atr  = (atr > 0.0) && (body >= m_min_body_atr * atr);
      double min_penetration = MathMax(m_min_penetration_atr * ((atr > 0.0) ? atr : 0.0),
                                        m_min_penetration_spreads * spread_price);
      bool cond_penetration = penetration >= min_penetration;

      passed = cond_close && cond_body && cond_pos && cond_body_atr && cond_penetration;
      return true;
     }
  };

#endif // FOURPOINTS_BREAKOUTVALIDATOR_MQH
