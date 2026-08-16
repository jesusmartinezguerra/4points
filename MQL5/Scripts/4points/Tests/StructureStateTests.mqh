#ifndef FOURPOINTS_STRUCTURESTATETESTS_MQH
#define FOURPOINTS_STRUCTURESTATETESTS_MQH

#include "TestHelpers.mqh"
#include <4points/StructureState.mqh>

// AVISO PARA QUIEN EDITE LOS CASOS 2 Y 3
//
// Los `close` que disparan el BOS (c2[9]=115, c3[6]=115, c3[13]=80) quedan
// deliberadamente FUERA de los limites high/low de su propia vela (high=100,
// low=95). Eso es fisicamente imposible en una vela real, pero aqui es
// intencionado y no invalida el test: CSwingDetector solo lee .high y .low para
// confirmar fractales, y CStructureState solo lee .close para detectar el BOS;
// ninguno de los dos compara close contra high/low.
//
// Se intento corregir la geometria y NO es un cambio local: subir el high de esa
// vela hasta contener el close la convierte en un fractal alcista propio, que
// desplaza el "ultimo swing high" y rompe justo el BOS que el caso pretende
// medir. Hacerlo bien exige redisenar el escenario entero (mas velas, otra
// separacion entre fractales). Si alguien lo aborda, que verifique
// empiricamente el numero y la posicion de los swings resultantes antes de
// confiar en los nuevos valores.

void RunStructureStateTests()
  {
   // --- Caso 1: sin ningun BOS -> NEUTRAL.
   int n = 10;
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   for(int i = 0; i < n; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60;
      h[i] = 100.0; l[i] = 95.0; o[i] = 97.5; c[i] = 97.5; // rango plano, sin cierres extremos
     }
   MqlRates rates1[];
   BuildRatesSeries(t, o, h, l, c, rates1);

   CStructureState state_det(2, 2, 0.0, 14);
   ETrendState s1;
   state_det.Evaluate(rates1, s1);
   Assert(s1 == TREND_NEUTRAL, "StructureState: sin BOS permanece NEUTRAL");

   // --- Caso 2: swing high confirmado y luego un cierre por encima -> BULL.
   double h2[] = {100,100,100,100,100,100,100,100,100,100,100,100};
   double l2[] = {95,95,95,95,95,95,95,95,95,95,95,95};
   double o2[12], c2[12]; datetime t2[12];
   int n2 = 12;
   for(int i = 0; i < n2; i++)
     {
      t2[i] = D'2026.01.01 00:00' + i * 60;
      o2[i] = 97.5; c2[i] = 97.5;
     }
   h2[3] = 110.0; // swing high candidato (fractal 2/2, confirmado en indice 3 con vecinos 1,2,4,5)
   c2[9] = 115.0; // cierre posterior por encima del swing high -> BOS alcista
                  // (close fuera de [low,high] a proposito: ver el aviso de la cabecera)
   MqlRates rates2[];
   BuildRatesSeries(t2, o2, h2, l2, c2, rates2);
   ETrendState s2;
   state_det.Evaluate(rates2, s2);
   Assert(s2 == TREND_BULL, "StructureState: cierre sobre swing high confirmado -> BULL");

   // --- Caso 3: tras BULL, un cierre por debajo del ultimo swing low -> BEAR.
   double h3[] = {100,100,100,100,100,100,100,100,100,100,100,100,100,100};
   double l3[] = {95,95,95,95,95,95,95,95,95,95,95,95,95,95};
   double o3[14], c3[14]; datetime t3[14];
   int n3 = 14;
   for(int i = 0; i < n3; i++)
     {
      t3[i] = D'2026.01.01 00:00' + i * 60;
      o3[i] = 97.5; c3[i] = 97.5;
     }
   h3[2] = 110.0;  // swing high
   c3[6] = 115.0;  // BOS alcista -> BULL (close fuera de [low,high] a proposito:
                   // ver el aviso de la cabecera)
   l3[8] = 85.0;   // swing low tras el BOS (confirmado con vecinos 6,7,9,10)
   c3[13] = 80.0;  // cierre por debajo del swing low -> BOS bajista (idem: close
                   // fuera de [low,high] a proposito)
   MqlRates rates3[];
   BuildRatesSeries(t3, o3, h3, l3, c3, rates3);
   ETrendState s3;
   state_det.Evaluate(rates3, s3);
   Assert(s3 == TREND_BEAR, "StructureState: BULL -> BEAR tras cierre bajo el ultimo swing low");
  }

#endif // FOURPOINTS_STRUCTURESTATETESTS_MQH
