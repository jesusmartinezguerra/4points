//+------------------------------------------------------------------+
//|                                                    TestRunner.mq5 |
//|  Corre como script sobre cualquier grafico. No usa datos de       |
//|  mercado: cada bateria de tests construye sus propias series      |
//|  sinteticas. Imprime PASS/FAIL por caso y un resumen N/M PASS.    |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include "Tests/TestHelpers.mqh"

void OnStart()
  {
   ResetTestCounters();

   PrintTestSummary();
  }
