//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|      4 Points - Continuacion de tendencia con barrido de liquidez |
//|                                                                  |
//|  Unica fuente de verdad de los parametros. El indicador validador |
//|  y el EA declaran sus `input` y los vuelcan aqui, de modo que     |
//|  ambos operan exactamente con la misma configuracion.             |
//|                                                                  |
//|  Regla de diseno: ningun umbral se expresa en pips fijos. Todo    |
//|  va en multiplos de ATR o de spread, que es lo unico que permite  |
//|  usar el mismo codigo en XAUUSD y en EURUSD.                      |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_CONFIG_MQH
#define FOURPOINTS_CONFIG_MQH

#include "Types.mqh"

//+------------------------------------------------------------------+
//| Configuracion completa de la estrategia                          |
//+------------------------------------------------------------------+
struct SConfig
  {
   //--- Deteccion de swings
   int               swing_left;              // Barras a la izquierda del fractal, timeframe de entrada
   int               swing_right;             // Barras a la derecha del fractal, timeframe de entrada
   int               swing_left_htf;          // Barras a la izquierda del fractal, timeframes superiores
   int               swing_right_htf;         // Barras a la derecha del fractal, timeframes superiores
   double            min_leg_atr;             // Pierna minima entre swings opuestos, en ATR
   int               atr_period;              // Periodo del ATR usado como unidad de medida

   //--- Timeframes
   ENUM_TIMEFRAMES   tf_high;                 // Timeframe alto de la alineacion
   ENUM_TIMEFRAMES   tf_mid;                  // Timeframe medio de la alineacion
   ENUM_TIMEFRAMES   tf_low;                  // Timeframe bajo de la alineacion
   ENUM_TIMEFRAMES   tf_entry;                // Timeframe de entrada
   int               htf_bars;                // Velas a cargar por timeframe superior

   //--- Patron de 4 puntos
   double            min_impulse_atr;         // Pierna P1->P2 minima, en ATR
   double            min_retrace;             // Retroceso minimo de P3 sobre P1->P2, 0..1
   double            max_retrace;             // Retroceso maximo de P3 sobre P1->P2, 0..1
   int               max_bars_to_complete;    // Velas maximas desde P4 hasta el disparo
   int               max_sweep_bars;          // Velas maximas para recuperar tras perforar
   int               max_bars_from_sweep;     // Velas maximas del barrido al breakout

   //--- Barrido de liquidez
   ESweepMode        sweep_mode;              // Modo de deteccion del barrido
   double            eq_tol_atr;              // Tolerancia de minimos iguales, en ATR

   //--- Validacion del breakout
   double            min_body_ratio;          // Cuerpo minimo sobre el rango de la vela, 0..1
   double            min_close_pos;           // Posicion minima del cierre en el rango, 0..1
   double            min_body_atr;            // Cuerpo minimo, en ATR
   double            min_penetration_atr;     // Penetracion minima del nivel, en ATR
   double            min_penetration_spreads; // Penetracion minima del nivel, en spreads

   //--- Sesiones, en minutos desde medianoche GMT
   int               broker_gmt_offset_min;   // Desfase del reloj del broker respecto a GMT
   int               london_start_min;        // Inicio de la sesion de Londres
   int               london_end_min;          // Fin de la sesion de Londres
   int               ny_start_min;            // Inicio de la sesion de Nueva York
   int               ny_end_min;              // Fin de la sesion de Nueva York
   bool              use_friday_cutoff;       // Cortar la operativa el viernes
   int               friday_cutoff_min;       // Hora del corte del viernes

   //--- Filtro de volatilidad
   ENUM_TIMEFRAMES   vol_tf;                  // Timeframe del filtro de volatilidad
   int               vol_atr_period;          // Periodo del ATR del filtro
   int               vol_lookback;            // Ventana de comparacion del ATR
   double            vol_percentile;          // Percentil minimo exigido, 0..100

   //--- Coste y viabilidad economica
   int               max_spread_points;       // Spread maximo admitido, en puntos
   double            min_sl_spread_multiple;  // Stop minimo como multiplo del spread
   double            sl_buffer_atr;           // Colchon del stop mas alla del barrido, en ATR

   //--- Riesgo y gestion (Fase 4)
   double            risk_percent;            // Riesgo por operacion, en % del balance
   double            rr;                      // Ratio riesgo/beneficio
   int               max_simultaneous;        // Posiciones simultaneas maximas
   double            max_daily_loss_percent;  // Perdida diaria maxima, en % del balance
   int               max_consecutive_losses;  // Perdidas consecutivas maximas
   int               max_trades_per_session;  // Operaciones maximas por sesion

   //--- Journal
   bool              journal_enabled;         // Escribir el journal en CSV
   bool              journal_log_rejected;    // Registrar tambien los setups rechazados
   string            journal_file;            // Nombre del CSV en Common Files

                     SConfig() { SetDefaults(); }

   //+---------------------------------------------------------------+
   //| Valores por defecto                                           |
   //|                                                               |
   //| Son un punto de partida razonado, no optimizado. Los umbrales |
   //| definitivos salen de la medicion de la Fase 3.                |
   //+---------------------------------------------------------------+
   void              SetDefaults()
     {
      swing_left              = 2;
      swing_right             = 2;
      swing_left_htf          = 3;
      swing_right_htf         = 3;
      min_leg_atr             = 0.50;
      atr_period              = 14;

      tf_high                 = PERIOD_H4;
      tf_mid                  = PERIOD_H1;
      tf_low                  = PERIOD_M15;
      tf_entry                = PERIOD_M1;
      htf_bars                = 500;

      min_impulse_atr         = 1.00;
      min_retrace             = 0.20;
      max_retrace             = 0.80;
      max_bars_to_complete    = 60;
      max_sweep_bars          = 5;
      max_bars_from_sweep     = 10;

      sweep_mode              = SWEEP_ANY;
      eq_tol_atr              = 0.10;

      min_body_ratio          = 0.55;
      min_close_pos           = 0.70;
      min_body_atr            = 0.50;
      min_penetration_atr     = 0.10;
      min_penetration_spreads = 1.50;

      broker_gmt_offset_min   = 0;
      london_start_min        = 7 * 60;   // 07:00 GMT
      london_end_min          = 16 * 60;  // 16:00 GMT
      ny_start_min            = 12 * 60;  // 12:00 GMT
      ny_end_min              = 21 * 60;  // 21:00 GMT
      use_friday_cutoff       = true;
      friday_cutoff_min       = 16 * 60;  // 16:00 GMT

      vol_tf                  = PERIOD_M15;
      vol_atr_period          = 14;
      vol_lookback            = 100;
      vol_percentile          = 40.0;

      max_spread_points       = 40;
      min_sl_spread_multiple  = 10.0;
      sl_buffer_atr           = 0.10;

      risk_percent            = 0.50;
      rr                      = 1.00;
      max_simultaneous        = 1;
      max_daily_loss_percent  = 3.00;
      max_consecutive_losses  = 4;
      max_trades_per_session  = 5;

      journal_enabled         = true;
      journal_log_rejected    = true;
      journal_file            = "4points_journal.csv";
     }

   //+---------------------------------------------------------------+
   //| Validacion de coherencia                                      |
   //|                                                               |
   //| Se llama en OnInit del indicador y del EA. Una configuracion   |
   //| incoherente debe fallar al arrancar, no producir resultados    |
   //| silenciosamente equivocados durante un backtest entero.        |
   //+---------------------------------------------------------------+
   bool              Validate(string &error) const
     {
      error = "";

      if(swing_left < 1 || swing_right < 1)
         return(Fail(error, "swing_left y swing_right deben ser >= 1"));

      if(swing_left_htf < 1 || swing_right_htf < 1)
         return(Fail(error, "swing_left_htf y swing_right_htf deben ser >= 1"));

      if(atr_period < 2 || vol_atr_period < 2)
         return(Fail(error, "los periodos de ATR deben ser >= 2"));

      if(min_leg_atr <= 0.0 || min_impulse_atr <= 0.0)
         return(Fail(error, "min_leg_atr y min_impulse_atr deben ser > 0"));

      if(htf_bars <= atr_period + swing_left_htf + swing_right_htf)
         return(Fail(error, "htf_bars es insuficiente para calcular ATR y swings"));

      if(min_retrace < 0.0 || max_retrace > 1.0 || min_retrace >= max_retrace)
         return(Fail(error, "se exige 0 <= min_retrace < max_retrace <= 1"));

      if(max_bars_to_complete < 1 || max_sweep_bars < 1 || max_bars_from_sweep < 1)
         return(Fail(error, "los plazos en velas deben ser >= 1"));

      if(eq_tol_atr < 0.0)
         return(Fail(error, "eq_tol_atr no puede ser negativo"));

      if(min_body_ratio <= 0.0 || min_body_ratio > 1.0)
         return(Fail(error, "min_body_ratio debe estar en (0, 1]"));

      if(min_close_pos <= 0.0 || min_close_pos > 1.0)
         return(Fail(error, "min_close_pos debe estar en (0, 1]"));

      if(min_body_atr <= 0.0)
         return(Fail(error, "min_body_atr debe ser > 0"));

      if(min_penetration_atr < 0.0 || min_penetration_spreads < 0.0)
         return(Fail(error, "las penetraciones minimas no pueden ser negativas"));

      if(!IsValidWindow(london_start_min, london_end_min))
         return(Fail(error, "ventana de Londres invalida"));

      if(!IsValidWindow(ny_start_min, ny_end_min))
         return(Fail(error, "ventana de Nueva York invalida"));

      if(use_friday_cutoff && (friday_cutoff_min < 0 || friday_cutoff_min > 1440))
         return(Fail(error, "friday_cutoff_min fuera de rango"));

      if(vol_lookback < 10)
         return(Fail(error, "vol_lookback debe ser >= 10 para que el percentil signifique algo"));

      if(vol_percentile < 0.0 || vol_percentile > 100.0)
         return(Fail(error, "vol_percentile debe estar en [0, 100]"));

      if(max_spread_points <= 0)
         return(Fail(error, "max_spread_points debe ser > 0"));

      if(min_sl_spread_multiple <= 0.0)
         return(Fail(error, "min_sl_spread_multiple debe ser > 0"));

      if(sl_buffer_atr < 0.0)
         return(Fail(error, "sl_buffer_atr no puede ser negativo"));

      if(risk_percent <= 0.0 || risk_percent > 100.0)
         return(Fail(error, "risk_percent debe estar en (0, 100]"));

      if(rr <= 0.0)
         return(Fail(error, "rr debe ser > 0"));

      if(max_simultaneous < 1)
         return(Fail(error, "max_simultaneous debe ser >= 1"));

      if(journal_enabled && StringLen(journal_file) == 0)
         return(Fail(error, "journal_file no puede estar vacio con el journal activo"));

      //--- Los cuatro timeframes deben estar ordenados de mayor a menor
      if(!(PeriodSeconds(tf_high) > PeriodSeconds(tf_mid) &&
           PeriodSeconds(tf_mid)  > PeriodSeconds(tf_low) &&
           PeriodSeconds(tf_low)  > PeriodSeconds(tf_entry)))
         return(Fail(error, "se exige tf_high > tf_mid > tf_low > tf_entry"));

      return(true);
     }

   //+---------------------------------------------------------------+
   //| Resumen legible, para el panel del grafico y los logs         |
   //+---------------------------------------------------------------+
   string            Describe() const
     {
      return(StringFormat("sweep=%s  fractal=%d/%d  impulso>=%.2fATR  retro=%.0f-%.0f%%  breakout: body>=%.2f pos>=%.2f atr>=%.2f  SL>=%.1fx spread  RR=1:%.2f",
                          SweepModeToString(sweep_mode),
                          swing_left, swing_right,
                          min_impulse_atr,
                          min_retrace * 100.0, max_retrace * 100.0,
                          min_body_ratio, min_close_pos, min_body_atr,
                          min_sl_spread_multiple,
                          rr));
     }

private:
   //--- Helpers de validacion
   bool              Fail(string &error, const string message) const
     {
      error = message;
      return(false);
     }

   bool              IsValidWindow(const int start_min, const int end_min) const
     {
      if(start_min < 0 || start_min >= 1440) return(false);
      if(end_min   < 0 || end_min   >  1440) return(false);
      return(start_min < end_min);
     }
  };

#endif // FOURPOINTS_CONFIG_MQH
//+------------------------------------------------------------------+
