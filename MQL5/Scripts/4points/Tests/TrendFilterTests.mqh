#ifndef FOURPOINTS_TRENDFILTERTESTS_MQH
#define FOURPOINTS_TRENDFILTERTESTS_MQH

#include <4points/TrendFilter.mqh>

void RunTrendFilterTests()
  {
   CTrendFilter filter(2, 2, 0.0, 14);

   Assert(filter.Evaluate(TREND_BULL, TREND_BULL, TREND_BULL) == DIR_BUY,
          "TrendFilter: H4=H1=M15=BULL da DIR_BUY");
   Assert(filter.Evaluate(TREND_BEAR, TREND_BEAR, TREND_BEAR) == DIR_SELL,
          "TrendFilter: H4=H1=M15=BEAR da DIR_SELL");
   Assert(filter.Evaluate(TREND_BULL, TREND_BULL, TREND_NEUTRAL) == DIR_NONE,
          "TrendFilter: un timeframe NEUTRAL da DIR_NONE");
   Assert(filter.Evaluate(TREND_BULL, TREND_BEAR, TREND_BULL) == DIR_NONE,
          "TrendFilter: timeframes en direcciones opuestas da DIR_NONE");
  }

#endif // FOURPOINTS_TRENDFILTERTESTS_MQH
