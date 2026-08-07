//+------------------------------------------------------------------+
//|                                                        Types.mqh |
//|      4 Points - Continuacion de tendencia con barrido de liquidez |
//|                                                                  |
//|  Enums y estructuras compartidas por el indicador validador y el  |
//|  EA. Este fichero no contiene logica: solo el vocabulario comun.  |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_TYPES_MQH
#define FOURPOINTS_TYPES_MQH

//+------------------------------------------------------------------+
//| Estado estructural de un timeframe                               |
//|                                                                  |
//| Se deriva de rupturas de estructura (BOS) sobre velas cerradas.  |
//| NEUTRAL es el estado inicial, antes del primer BOS observado.    |
//+------------------------------------------------------------------+
enum ETrendState
  {
   TREND_NEUTRAL = 0,   // Sin BOS observado todavia
   TREND_BULL    = 1,   // Ultimo BOS al alza
   TREND_BEAR    = 2    // Ultimo BOS a la baja
  };

//+------------------------------------------------------------------+
//| Direccion operable                                               |
//+------------------------------------------------------------------+
enum EDirection
  {
   DIR_NONE = 0,        // Sin direccion
   DIR_BUY  = 1,        // Compra
   DIR_SELL = 2         // Venta
  };

//+------------------------------------------------------------------+
//| Modo de deteccion del barrido de liquidez                        |
//|                                                                  |
//| Los dos modos son hipotesis competidoras sobre que liquidez toma |
//| el precio antes del breakout. Se comparan con datos en Fase 3.   |
//+------------------------------------------------------------------+
enum ESweepMode
  {
   SWEEP_BREACH_P3 = 0, // Perfora el minimo/maximo de P3 y cierra de vuelta
   SWEEP_INTERNAL  = 1, // Solo liquidez interna, respeta P3
   SWEEP_ANY       = 2  // Cualquiera de los dos
  };

//+------------------------------------------------------------------+
//| Etapa de la maquina de estados del patron de 4 puntos            |
//+------------------------------------------------------------------+
enum EPatternStage
  {
   STAGE_IDLE      = 0, // Sin patron en curso
   STAGE_P1        = 1, // Origen del impulso localizado
   STAGE_P2        = 2, // Fin del impulso confirmado
   STAGE_P3        = 3, // Primer pullback confirmado
   STAGE_P4        = 4, // BOS de continuacion confirmado
   STAGE_SWEPT     = 5, // Barrido de liquidez confirmado y recuperado
   STAGE_TRIGGERED = 6  // Breakout validado, setup disparado
  };

//+------------------------------------------------------------------+
//| Tipo de swing                                                    |
//+------------------------------------------------------------------+
enum ESwingType
  {
   SWING_NONE = 0,      // No es swing
   SWING_HIGH = 1,      // Maximo fractal confirmado
   SWING_LOW  = 2       // Minimo fractal confirmado
  };

//+------------------------------------------------------------------+
//| Sesion de mercado                                                |
//+------------------------------------------------------------------+
enum ESession
  {
   SESSION_NONE    = 0, // Fuera de sesion operable
   SESSION_LONDON  = 1, // Solo Londres
   SESSION_NEWYORK = 2, // Solo Nueva York
   SESSION_OVERLAP = 3  // Solape Londres / Nueva York
  };

//+------------------------------------------------------------------+
//| Resultado de la evaluacion de un setup                           |
//+------------------------------------------------------------------+
enum ESetupStatus
  {
   SETUP_REJECTED = 0,  // Descartado por algun filtro
   SETUP_TAKEN    = 1   // Aceptado
  };

//+------------------------------------------------------------------+
//| Desenlace de un setup aceptado                                   |
//+------------------------------------------------------------------+
enum ESetupOutcome
  {
   OUTCOME_PENDING = 0, // Sin resolver todavia
   OUTCOME_TP      = 1, // Alcanzo el take profit
   OUTCOME_SL      = 2, // Alcanzo el stop loss
   OUTCOME_TIMEOUT = 3  // Expiro sin tocar ninguno
  };

//+------------------------------------------------------------------+
//| Motivo de rechazo                                                |
//|                                                                  |
//| El journal registra una fila por setup evaluado, incluidos los   |
//| rechazados. Sin el motivo es imposible saber que filtro esta     |
//| costando dinero, que es la pregunta central de la Fase 3.        |
//+------------------------------------------------------------------+
enum ERejectReason
  {
   REJECT_NONE                 = 0,  // Sin rechazo
   // --- Contexto
   REJECT_HTF_NOT_ALIGNED      = 1,  // H4/H1/M15 no coinciden
   REJECT_HTF_NEUTRAL          = 2,  // Algun timeframe sin BOS observado
   REJECT_OUT_OF_SESSION       = 3,  // Fuera de Londres y Nueva York
   REJECT_FRIDAY_CUTOFF        = 4,  // Despues del corte del viernes
   REJECT_LOW_VOLATILITY       = 5,  // ATR por debajo del percentil minimo
   REJECT_NEWS_WINDOW          = 6,  // Ventana de noticia de alto impacto
   // --- Coste
   REJECT_SPREAD_TOO_HIGH      = 10, // Spread por encima del maximo
   REJECT_SL_TOO_TIGHT         = 11, // Stop demasiado corto frente al spread
   // --- Patron
   REJECT_IMPULSE_TOO_SMALL    = 20, // Pierna P1->P2 por debajo del minimo ATR
   REJECT_RETRACE_TOO_SHALLOW  = 21, // Pullback P3 demasiado superficial
   REJECT_RETRACE_TOO_DEEP     = 22, // Pullback P3 demasiado profundo
   REJECT_NO_HIGHER_HIGH       = 23, // P4 no supera a P2
   REJECT_STRUCTURE_BROKEN     = 24, // Precio cerro mas alla de P1
   REJECT_PATTERN_TIMEOUT      = 25, // Expiro el plazo desde P4
   // --- Barrido
   REJECT_SWEEP_NOT_RECOVERED  = 30, // Perforo pero no cerro de vuelta
   REJECT_SWEEP_BEYOND_P1      = 31, // El barrido invalido el origen del impulso
   REJECT_SWEEP_MODE_MISMATCH  = 32, // El barrido no encaja en el modo activo
   REJECT_SWEEP_TIMEOUT        = 33, // Expiro el plazo de recuperacion
   // --- Breakout
   REJECT_BREAKOUT_WEAK_BODY   = 40, // Cuerpo insuficiente frente al rango
   REJECT_BREAKOUT_CLOSE_POS   = 41, // Cierre fuera del tercio correcto
   REJECT_BREAKOUT_BODY_ATR    = 42, // Cuerpo insuficiente frente al ATR
   REJECT_BREAKOUT_PENETRATION = 43, // Penetracion del nivel insuficiente
   REJECT_BREAKOUT_TIMEOUT     = 44, // Expiro el plazo desde el barrido
   // --- Gestion (Fase 4)
   REJECT_MAX_TRADES           = 50, // Limite de operaciones alcanzado
   REJECT_DAILY_LOSS_LIMIT     = 51, // Limite de perdida diaria alcanzado
   REJECT_CONSECUTIVE_LOSSES   = 52  // Limite de perdidas consecutivas
  };

//+------------------------------------------------------------------+
//| Un swing confirmado                                              |
//|                                                                  |
//| bar_shift es el desplazamiento respecto a la vela mas reciente    |
//| cargada, en indexacion de serie (0 = ultima vela cerrada cuando   |
//| se carga con CopyRates(sym, tf, 1, N, rates)).                    |
//+------------------------------------------------------------------+
struct SSwing
  {
   ESwingType        type;        // Tipo de swing
   int               bar_shift;   // Indice en serie del array cargado
   datetime          time;        // Hora de apertura de la vela del swing
   double            price;       // High si es SWING_HIGH, low si es SWING_LOW

                     SSwing() { Reset(); }

   void              Reset()
     {
      type      = SWING_NONE;
      bar_shift = -1;
      time      = 0;
      price     = 0.0;
     }

   bool              IsValid() const { return(type != SWING_NONE && bar_shift >= 0); }
  };

//+------------------------------------------------------------------+
//| Los cuatro puntos del patron, mas el extremo del barrido          |
//+------------------------------------------------------------------+
struct SPatternPoints
  {
   SSwing            p1;          // Origen del impulso
   SSwing            p2;          // Fin del impulso
   SSwing            p3;          // Primer pullback
   SSwing            p4;          // Nuevo extremo: BOS de continuacion
   double            sweep_price; // Extremo alcanzado durante el barrido
   datetime          sweep_time;  // Hora de la vela del extremo del barrido
   ESweepMode        sweep_kind;  // Modo con el que se clasifico el barrido

                     SPatternPoints() { Reset(); }

   void              Reset()
     {
      p1.Reset();
      p2.Reset();
      p3.Reset();
      p4.Reset();
      sweep_price = 0.0;
      sweep_time  = 0;
      sweep_kind  = SWEEP_ANY;
     }
  };

//+------------------------------------------------------------------+
//| Metricas de la vela de breakout                                  |
//|                                                                  |
//| Se guardan aunque el breakout sea rechazado: son las que permiten|
//| calibrar los umbrales con datos en lugar de a ojo.               |
//+------------------------------------------------------------------+
struct SBreakoutMetrics
  {
   double            body_ratio;           // cuerpo / rango de la vela
   double            close_pos;            // posicion del cierre dentro del rango, 0..1
   double            body_atr;             // cuerpo / ATR
   double            penetration_atr;      // penetracion del nivel / ATR
   double            penetration_spreads;  // penetracion del nivel / spread

                     SBreakoutMetrics() { Reset(); }

   void              Reset()
     {
      body_ratio          = 0.0;
      close_pos           = 0.0;
      body_atr            = 0.0;
      penetration_atr     = 0.0;
      penetration_spreads = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| Una fila del journal: un setup evaluado                          |
//|                                                                  |
//| Es el registro que alimenta el analisis de la Fase 3. Contiene   |
//| tanto los setups aceptados como los rechazados con su motivo.    |
//+------------------------------------------------------------------+
struct SSetup
  {
   // --- Identificacion
   datetime          signal_time;      // Hora de cierre de la vela de breakout
   string            symbol;           // Simbolo
   EDirection        direction;        // Compra o venta
   ESession          session;          // Sesion en la que se detecto

   // --- Contexto de tendencia
   ETrendState       state_high;       // Estado del timeframe alto
   ETrendState       state_mid;        // Estado del timeframe medio
   ETrendState       state_low;        // Estado del timeframe bajo

   // --- Patron
   SPatternPoints    points;           // P1..P4 y barrido
   SBreakoutMetrics  breakout;         // Metricas de la vela de breakout

   // --- Niveles
   double            entry;            // Precio de entrada, cierre del breakout
   double            sl;               // Stop loss
   double            tp;               // Take profit
   double            r_points;         // Distancia del stop en puntos

   // --- Condiciones de mercado en el momento de la senal
   double            spread_points;    // Spread en puntos
   double            atr_entry_tf;     // ATR del timeframe de entrada
   double            atr_vol_tf;       // ATR del timeframe de volatilidad

   // --- Resultado
   ESetupStatus      status;           // Aceptado o rechazado
   ERejectReason     reject_reason;    // Motivo si fue rechazado
   ESetupOutcome     outcome;          // Desenlace si fue aceptado
   double            mfe;              // Maxima excursion favorable, en R
   double            mae;              // Maxima excursion adversa, en R
   int               bars_to_resolve;  // Velas hasta TP, SL o expiracion

                     SSetup() { Reset(); }

   void              Reset()
     {
      signal_time     = 0;
      symbol          = "";
      direction       = DIR_NONE;
      session         = SESSION_NONE;
      state_high      = TREND_NEUTRAL;
      state_mid       = TREND_NEUTRAL;
      state_low       = TREND_NEUTRAL;
      points.Reset();
      breakout.Reset();
      entry           = 0.0;
      sl              = 0.0;
      tp              = 0.0;
      r_points        = 0.0;
      spread_points   = 0.0;
      atr_entry_tf    = 0.0;
      atr_vol_tf      = 0.0;
      status          = SETUP_REJECTED;
      reject_reason   = REJECT_NONE;
      outcome         = OUTCOME_PENDING;
      mfe             = 0.0;
      mae             = 0.0;
      bars_to_resolve = 0;
     }
  };

//+------------------------------------------------------------------+
//| Conversiones a texto para el journal y los logs                  |
//+------------------------------------------------------------------+
string TrendStateToString(const ETrendState v)
  {
   switch(v)
     {
      case TREND_BULL: return("BULL");
      case TREND_BEAR: return("BEAR");
      default:         return("NEUTRAL");
     }
  }

string DirectionToString(const EDirection v)
  {
   switch(v)
     {
      case DIR_BUY:  return("BUY");
      case DIR_SELL: return("SELL");
      default:       return("NONE");
     }
  }

string SweepModeToString(const ESweepMode v)
  {
   switch(v)
     {
      case SWEEP_BREACH_P3: return("BREACH_P3");
      case SWEEP_INTERNAL:  return("INTERNAL");
      default:              return("ANY");
     }
  }

string SessionToString(const ESession v)
  {
   switch(v)
     {
      case SESSION_LONDON:  return("LONDON");
      case SESSION_NEWYORK: return("NEWYORK");
      case SESSION_OVERLAP: return("OVERLAP");
      default:              return("NONE");
     }
  }

string SetupStatusToString(const ESetupStatus v)
  {
   return(v == SETUP_TAKEN ? "TAKEN" : "REJECTED");
  }

string SetupOutcomeToString(const ESetupOutcome v)
  {
   switch(v)
     {
      case OUTCOME_TP:      return("TP");
      case OUTCOME_SL:      return("SL");
      case OUTCOME_TIMEOUT: return("TIMEOUT");
      default:              return("PENDING");
     }
  }

string PatternStageToString(const EPatternStage v)
  {
   switch(v)
     {
      case STAGE_P1:        return("P1");
      case STAGE_P2:        return("P2");
      case STAGE_P3:        return("P3");
      case STAGE_P4:        return("P4");
      case STAGE_SWEPT:     return("SWEPT");
      case STAGE_TRIGGERED: return("TRIGGERED");
      default:              return("IDLE");
     }
  }

string RejectReasonToString(const ERejectReason v)
  {
   switch(v)
     {
      case REJECT_NONE:                 return("NONE");
      case REJECT_HTF_NOT_ALIGNED:      return("HTF_NOT_ALIGNED");
      case REJECT_HTF_NEUTRAL:          return("HTF_NEUTRAL");
      case REJECT_OUT_OF_SESSION:       return("OUT_OF_SESSION");
      case REJECT_FRIDAY_CUTOFF:        return("FRIDAY_CUTOFF");
      case REJECT_LOW_VOLATILITY:       return("LOW_VOLATILITY");
      case REJECT_NEWS_WINDOW:          return("NEWS_WINDOW");
      case REJECT_SPREAD_TOO_HIGH:      return("SPREAD_TOO_HIGH");
      case REJECT_SL_TOO_TIGHT:         return("SL_TOO_TIGHT");
      case REJECT_IMPULSE_TOO_SMALL:    return("IMPULSE_TOO_SMALL");
      case REJECT_RETRACE_TOO_SHALLOW:  return("RETRACE_TOO_SHALLOW");
      case REJECT_RETRACE_TOO_DEEP:     return("RETRACE_TOO_DEEP");
      case REJECT_NO_HIGHER_HIGH:       return("NO_HIGHER_HIGH");
      case REJECT_STRUCTURE_BROKEN:     return("STRUCTURE_BROKEN");
      case REJECT_PATTERN_TIMEOUT:      return("PATTERN_TIMEOUT");
      case REJECT_SWEEP_NOT_RECOVERED:  return("SWEEP_NOT_RECOVERED");
      case REJECT_SWEEP_BEYOND_P1:      return("SWEEP_BEYOND_P1");
      case REJECT_SWEEP_MODE_MISMATCH:  return("SWEEP_MODE_MISMATCH");
      case REJECT_SWEEP_TIMEOUT:        return("SWEEP_TIMEOUT");
      case REJECT_BREAKOUT_WEAK_BODY:   return("BREAKOUT_WEAK_BODY");
      case REJECT_BREAKOUT_CLOSE_POS:   return("BREAKOUT_CLOSE_POS");
      case REJECT_BREAKOUT_BODY_ATR:    return("BREAKOUT_BODY_ATR");
      case REJECT_BREAKOUT_PENETRATION: return("BREAKOUT_PENETRATION");
      case REJECT_BREAKOUT_TIMEOUT:     return("BREAKOUT_TIMEOUT");
      case REJECT_MAX_TRADES:           return("MAX_TRADES");
      case REJECT_DAILY_LOSS_LIMIT:     return("DAILY_LOSS_LIMIT");
      case REJECT_CONSECUTIVE_LOSSES:   return("CONSECUTIVE_LOSSES");
      default:                          return("UNKNOWN");
     }
  }

//+------------------------------------------------------------------+
//| Utilidad: direccion opuesta                                      |
//+------------------------------------------------------------------+
EDirection OppositeDirection(const EDirection v)
  {
   if(v == DIR_BUY)  return(DIR_SELL);
   if(v == DIR_SELL) return(DIR_BUY);
   return(DIR_NONE);
  }

//+------------------------------------------------------------------+
//| Utilidad: direccion implicada por un estado de tendencia         |
//+------------------------------------------------------------------+
EDirection DirectionFromTrend(const ETrendState v)
  {
   if(v == TREND_BULL) return(DIR_BUY);
   if(v == TREND_BEAR) return(DIR_SELL);
   return(DIR_NONE);
  }

#endif // FOURPOINTS_TYPES_MQH
//+------------------------------------------------------------------+
