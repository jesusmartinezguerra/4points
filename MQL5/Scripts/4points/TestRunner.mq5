//+------------------------------------------------------------------+
//|                                                    TestRunner.mq5 |
//|  Corre como script sobre cualquier grafico. No usa datos de       |
//|  mercado: cada bateria de tests construye sus propias series      |
//|  sinteticas. Imprime PASS/FAIL por caso y un resumen N/M PASS.    |
//|                                                                   |
//|  Sin `#property script_show_inputs`: el script no declara ningun   |
//|  input, asi que esa propiedad solo forzaba un dialogo vacio en     |
//|  cada ejecucion. Sin `#property strict` tampoco: es una directiva  |
//|  de compatibilidad con MQL4 que en MQL5 no tiene ningun efecto.    |
//+------------------------------------------------------------------+

#include "Tests/TestHelpers.mqh"
#include "Tests/AtrUtilsTests.mqh"
#include "Tests/SwingDetectorTests.mqh"
#include "Tests/StructureStateTests.mqh"
#include "Tests/TrendFilterTests.mqh"
#include "Tests/PatternDetectorTests.mqh"
#include "Tests/LiquiditySweepTests.mqh"
#include "Tests/BreakoutValidatorTests.mqh"

void OnStart()
  {
   ResetTestCounters();

   RunAtrUtilsTests();
   RunSwingDetectorTests();
   RunStructureStateTests();
   RunTrendFilterTests();
   RunPatternDetectorTests();
   RunLiquiditySweepTests();
   RunBreakoutValidatorTests();

   PrintTestSummary();
  }
