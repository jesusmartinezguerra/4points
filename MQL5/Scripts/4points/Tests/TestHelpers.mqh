//+------------------------------------------------------------------+
//|                                                  TestHelpers.mqh |
//|  Arnes de test minimo para TestRunner.mq5: contador PASS/FAIL y  |
//|  un builder de MqlRates sinteticos a partir de arrays paralelos. |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_TESTHELPERS_MQH
#define FOURPOINTS_TESTHELPERS_MQH

int g_tests_total  = 0;
int g_tests_passed = 0;

void ResetTestCounters()
  {
   g_tests_total  = 0;
   g_tests_passed = 0;
  }

void Assert(const bool condition, const string case_name)
  {
   g_tests_total++;
   if(condition)
     {
      g_tests_passed++;
      PrintFormat("PASS %s", case_name);
     }
   else
     {
      PrintFormat("FAIL %s", case_name);
     }
  }

void PrintTestSummary()
  {
   PrintFormat("%d/%d PASS", g_tests_passed, g_tests_total);
  }

//+------------------------------------------------------------------+
//| Construye un MqlRates[] en orden de serie (indice 0 = mas        |
//| reciente) a partir de arrays paralelos en orden cronologico      |
//| (indice 0 = mas antiguo), que es como resulta mas natural         |
//| escribir un escenario de test a mano.                            |
//+------------------------------------------------------------------+
void BuildRatesSeries(const datetime &times[], const double &opens[], const double &highs[],
                       const double &lows[], const double &closes[], MqlRates &out[])
  {
   int n = ArraySize(times);
   ArrayResize(out, n);
   // El flag AS_SERIES debe fijarse ANTES de escribir: ArraySetAsSeries invierte el
   // mapeo indice->posicion fisica para TODO acceso futuro (lectura y escritura) con
   // ese flag activo. Si se fijara despues de un bucle que ya escribio en orden
   // invertido "a mano", el flag revertiria esa inversion por segunda vez y el
   // resultado neto seria el orden cronologico original (bug ya detectado y corregido
   // aqui: ver Task 3 SwingDetector, que expuso el problema).
   ArraySetAsSeries(out, true);
   for(int i = 0; i < n; i++)
     {
      int src = n - 1 - i; // invierte: la ultima entrada cronologica va al indice 0
      out[i].time         = times[src];
      out[i].open         = opens[src];
      out[i].high         = highs[src];
      out[i].low          = lows[src];
      out[i].close        = closes[src];
      out[i].tick_volume  = 1;
      out[i].spread       = 0;
      out[i].real_volume  = 0;
     }
  }

#endif // FOURPOINTS_TESTHELPERS_MQH
