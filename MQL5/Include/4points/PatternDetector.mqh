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

   //+------------------------------------------------------------------+
   //| Recorre la lista de swings (cronologica, mas antiguo primero) y   |
   //| devuelve el ciclo P1->P2->P3->P4 mas RECIENTE, no el primero que  |
   //| completa. Para eso el escaneo nunca se detiene al llegar a        |
   //| STAGE_P4: guarda ese ciclo como "ultimo completo" (best_*),       |
   //| reinicia el intento en curso a STAGE_IDLE y sigue consumiendo     |
   //| swings desde el mismo punto (sin reiniciar el bucle) por si hay   |
   //| un ciclo todavia mas nuevo despues. Si el intento en curso tras   |
   //| el reinicio nunca vuelve a completar, se descarta y se devuelve   |
   //| el ultimo ciclo completo (best_*); solo si NINGUN ciclo llego a   |
   //| completarse en toda la serie se devuelve el progreso parcial del  |
   //| ultimo intento (cur_*).                                           |
   //+------------------------------------------------------------------+
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

      SPatternPoints cur;                        // intento de ciclo en curso
      EPatternStage  cur_stage = STAGE_IDLE;
      SPatternPoints best;                        // ultimo ciclo P1..P4 completo visto
      EPatternStage  best_stage = STAGE_IDLE;      // STAGE_P4 si "best" contiene algo valido

      for(int i = 0; i < ArraySize(swings); i++)
        {
         SSwing s = swings[i];

         if(cur_stage == STAGE_IDLE)
           {
            if(s.type == origin_type)
              {
               cur.p1 = s;
               cur_stage = STAGE_P1;
              }
            continue;
           }

         if(cur_stage == STAGE_P1)
           {
            if(s.type == origin_type)
              {
               bool more_extreme = (direction == DIR_BUY) ? (s.price < cur.p1.price) : (s.price > cur.p1.price);
               if(more_extreme)
                  cur.p1 = s;
               continue;
              }
            double leg = MathAbs(s.price - cur.p1.price);
            double atr = SimpleATR(rates, m_atr_period, s.bar_shift);
            // Fail-closed frente al centinela -1.0 de SimpleATR (ver AtrUtils.mqh):
            // sin ATR no se puede medir el impulso, asi que P2 no se confirma.
            if(atr > 0.0 && leg >= m_min_impulse_atr * atr)
              {
               cur.p2 = s;
               cur_stage = STAGE_P2;
              }
            continue;
           }

         if(cur_stage == STAGE_P2)
           {
            if(s.type == impulse_type)
              {
               bool more_extreme = (direction == DIR_BUY) ? (s.price > cur.p2.price) : (s.price < cur.p2.price);
               if(more_extreme)
                  cur.p2 = s;
               continue;
              }
            bool higher_low_ok = (direction == DIR_BUY) ? (s.price > cur.p1.price) : (s.price < cur.p1.price);
            if(!higher_low_ok)
              {
               SSwing new_origin = s;
               cur.Reset();
               cur.p1 = new_origin;
               cur_stage = STAGE_P1;
               continue;
              }
            double leg_p1_p2 = MathAbs(cur.p2.price - cur.p1.price);
            double retrace = (leg_p1_p2 > 0.0) ? MathAbs(cur.p2.price - s.price) / leg_p1_p2 : 0.0;
            if(retrace >= m_min_retrace && retrace <= m_max_retrace)
              {
               cur.p3 = s;
               cur_stage = STAGE_P3;
              }
            continue;
           }

         if(cur_stage == STAGE_P3)
           {
            if(s.type == origin_type)
              {
               bool higher_low_ok = (direction == DIR_BUY) ? (s.price > cur.p1.price) : (s.price < cur.p1.price);
               if(!higher_low_ok)
                 {
                  SSwing new_origin = s;
                  cur.Reset();
                  cur.p1 = new_origin;
                  cur_stage = STAGE_P1;
                  continue;
                 }
               // Candidato a reemplazar P3: debe superar el mismo filtro de
               // retroceso que el P3 original, o se descarta y se conserva
               // el P3 vigente (que ya era valido). Sin este chequeo, un
               // reemplazo con retroceso fuera de [min_retrace,max_retrace]
               // se colaba sin validar y un P4 posterior confirmaba el
               // patron sobre un pullback que nunca deberia haberse aceptado.
               double leg_p1_p2 = MathAbs(cur.p2.price - cur.p1.price);
               double retrace = (leg_p1_p2 > 0.0) ? MathAbs(cur.p2.price - s.price) / leg_p1_p2 : 0.0;
               // Decision deliberada: un candidato de reemplazo fuera de rango
               // (tanto demasiado profundo como demasiado superficial) se ignora y
               // el P3 vigente sobrevive; NO invalida el intento en curso como si
               // hace `!higher_low_ok` unas lineas mas arriba. El razonamiento es
               // que el P3 vigente ya paso el filtro y sigue siendo estructuralmente
               // valido mientras el precio no rompa P1. Pendiente de revisar con los
               // datos de la Fase 3 por si conviene resetear el intento.
               if(retrace >= m_min_retrace && retrace <= m_max_retrace)
                  cur.p3 = s;
               continue;
              }
            bool higher_high_ok = (direction == DIR_BUY) ? (s.price > cur.p2.price) : (s.price < cur.p2.price);
            if(higher_high_ok)
              {
               cur.p4 = s;
               cur_stage = STAGE_P4;

               // Ciclo completo: se guarda como el mas reciente visto hasta
               // ahora y se reinicia el intento en curso para seguir
               // buscando uno todavia mas nuevo, sin reiniciar el bucle.
               best = cur;
               best_stage = STAGE_P4;
               cur.Reset();
               cur_stage = STAGE_IDLE;
              }
            continue;
           }
        }

      if(best_stage == STAGE_P4)
        {
         points = best;
         stage  = best_stage;
        }
      else
        {
         points = cur;
         stage  = cur_stage;
        }

      return true;
     }
  };

#endif // FOURPOINTS_PATTERNDETECTOR_MQH
