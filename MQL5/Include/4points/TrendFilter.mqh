//+------------------------------------------------------------------+
//|                                                    TrendFilter.mqh |
//|  Alineacion H4/H1/M15: direccion operable solo si los tres        |
//|  coinciden y ninguno esta NEUTRAL. Ver docs/superpowers/specs/    |
//|  2026-08-06-4points-continuation-design.md §2.                    |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_TRENDFILTER_MQH
#define FOURPOINTS_TRENDFILTER_MQH

#include <4points/Types.mqh>
#include <4points/StructureState.mqh>

class CTrendFilter
  {
private:
   CStructureState m_high;
   CStructureState m_mid;
   CStructureState m_low;

public:
   CTrendFilter(const int left, const int right, const double min_leg_atr, const int atr_period)
     : m_high(left, right, min_leg_atr, atr_period),
       m_mid(left, right, min_leg_atr, atr_period),
       m_low(left, right, min_leg_atr, atr_period) {}

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf_high, const ENUM_TIMEFRAMES tf_mid,
             const ENUM_TIMEFRAMES tf_low, const int bars_needed,
             ETrendState &state_high, ETrendState &state_mid, ETrendState &state_low, EDirection &direction)
     {
      if(!m_high.Load(symbol, tf_high, bars_needed, state_high)) return false;
      if(!m_mid.Load(symbol, tf_mid, bars_needed, state_mid))   return false;
      if(!m_low.Load(symbol, tf_low, bars_needed, state_low))   return false;
      direction = Evaluate(state_high, state_mid, state_low);
      return true;
     }

   EDirection Evaluate(const ETrendState state_high, const ETrendState state_mid, const ETrendState state_low)
     {
      if(state_high == TREND_NEUTRAL || state_mid == TREND_NEUTRAL || state_low == TREND_NEUTRAL)
         return DIR_NONE;
      if(state_high != state_mid || state_mid != state_low)
         return DIR_NONE;
      return DirectionFromTrend(state_high);
     }
  };

#endif // FOURPOINTS_TRENDFILTER_MQH
