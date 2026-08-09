//+------------------------------------------------------------------+
//|                                                PatternDetector.mqh |
//|  Maquina de estados del patron de 4 puntos sobre M1. Ver          |
//|  docs/superpowers/specs/2026-08-06-4points-continuation-          |
//|  design.md §3.                                                    |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_PATTERNDETECTOR_MQH
#define FOURPOINTS_PATTERNDETECTOR_MQH

#include <4points/Types.mqh>
#include <4points/SwingDetector.mqh>
#include <4points/AtrUtils.mqh>

class CPatternDetector
  {
private:
   CSwingDetector m_swings;
   double         m_min_impulse_atr;
   double         m_min_retrace;
   double         m_max_retrace;
   int            m_atr_period;

public:
   CPatternDetector(const int left, const int right, const double min_leg_atr, const int atr_period,
                     const double min_impulse_atr, const double min_retrace, const double max_retrace)
     : m_swings(left, right, min_leg_atr, atr_period)
     {
      m_atr_period       = atr_period;
      m_min_impulse_atr  = min_impulse_atr;
      m_min_retrace      = min_retrace;
      m_max_retrace      = max_retrace;
     }

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed,
             const EDirection direction, SPatternPoints &points, EPatternStage &stage)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, direction, points, stage);
     }

   bool Evaluate(const MqlRates &rates[], const EDirection direction, SPatternPoints &points, EPatternStage &stage)
     {
      points.Reset();
      stage = STAGE_IDLE;
      if(direction != DIR_BUY && direction != DIR_SELL)
         return true;

      SSwing swings[];
      if(!m_swings.Evaluate(rates, swings))
         return false;

      ESwingType origin_type   = (direction == DIR_BUY) ? SWING_LOW  : SWING_HIGH;
      ESwingType impulse_type  = (direction == DIR_BUY) ? SWING_HIGH : SWING_LOW;

      for(int i = 0; i < ArraySize(swings); i++)
        {
         SSwing s = swings[i];

         if(stage == STAGE_IDLE)
           {
            if(s.type == origin_type)
              {
               points.p1 = s;
               stage = STAGE_P1;
              }
            continue;
           }

         if(stage == STAGE_P1)
           {
            if(s.type == origin_type)
              {
               bool more_extreme = (direction == DIR_BUY) ? (s.price < points.p1.price) : (s.price > points.p1.price);
               if(more_extreme)
                  points.p1 = s;
               continue;
              }
            double leg = MathAbs(s.price - points.p1.price);
            double atr = SimpleATR(rates, m_atr_period, s.bar_shift);
            if(atr > 0.0 && leg >= m_min_impulse_atr * atr)
              {
               points.p2 = s;
               stage = STAGE_P2;
              }
            continue;
           }

         if(stage == STAGE_P2)
           {
            if(s.type == impulse_type)
              {
               bool more_extreme = (direction == DIR_BUY) ? (s.price > points.p2.price) : (s.price < points.p2.price);
               if(more_extreme)
                  points.p2 = s;
               continue;
              }
            bool higher_low_ok = (direction == DIR_BUY) ? (s.price > points.p1.price) : (s.price < points.p1.price);
            if(!higher_low_ok)
              {
               SSwing new_origin = s;
               points.Reset();
               points.p1 = new_origin;
               stage = STAGE_P1;
               continue;
              }
            double leg_p1_p2 = MathAbs(points.p2.price - points.p1.price);
            double retrace = (leg_p1_p2 > 0.0) ? MathAbs(points.p2.price - s.price) / leg_p1_p2 : 0.0;
            if(retrace >= m_min_retrace && retrace <= m_max_retrace)
              {
               points.p3 = s;
               stage = STAGE_P3;
              }
            continue;
           }

         if(stage == STAGE_P3)
           {
            if(s.type == origin_type)
              {
               bool higher_low_ok = (direction == DIR_BUY) ? (s.price > points.p1.price) : (s.price < points.p1.price);
               if(!higher_low_ok)
                 {
                  SSwing new_origin = s;
                  points.Reset();
                  points.p1 = new_origin;
                  stage = STAGE_P1;
                  continue;
                 }
               points.p3 = s;
               continue;
              }
            bool higher_high_ok = (direction == DIR_BUY) ? (s.price > points.p2.price) : (s.price < points.p2.price);
            if(higher_high_ok)
              {
               points.p4 = s;
               stage = STAGE_P4;
              }
            continue;
           }

         if(stage == STAGE_P4)
            break;
        }

      return true;
     }
  };

#endif // FOURPOINTS_PATTERNDETECTOR_MQH
