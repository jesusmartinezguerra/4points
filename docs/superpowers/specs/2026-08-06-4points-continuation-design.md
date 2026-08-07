# Diseño — EA "4 Points": continuación de tendencia con barrido de liquidez

**Fecha:** 2026-08-06
**Estado:** aprobado, Fase 0 implementada

---

## Contexto

Existe una estrategia discrecional que se opera manualmente sobre estructura de mercado, price action y liquidez —sin indicadores— y se quiere traducir a un algoritmo objetivo para MetaTrader 5, empezando por XAUUSD y EURUSD.

El problema real no es escribir un EA: es que **"estructura", "sweep" y "breakout fuerte" son criterios visuales**, y una traducción mal validada produce un robot que opera setups que el trader jamás habría tomado. A eso se suma que el RR fijo 1:1 en M1 es extremadamente sensible al coste de transacción, y que la distancia típica del stop en esta estrategia **todavía no está medida**.

El plan por tanto no va directo al EA. Va en este orden: reglas objetivas → validación visual sobre histórico → medición estadística → decisión sobre viabilidad → EA. El objetivo del primer entregable es responder *"¿el algoritmo ve mi patrón?"* antes de escribir una sola línea de gestión de dinero.

---

## Decisiones cerradas

| Decisión | Valor |
|---|---|
| Primer entregable | **Indicador validador**, no EA |
| Modo de sweep | **Ambos**, parametrizable, se comparan con datos |
| Stack | **MQL5 puro**; Python solo para analizar el journal |
| Layout | **Repo como fuente de verdad + deploy a la carpeta del terminal** |
| Distancia de SL | **A medir** en la Fase 3, no se fija a priori |
| Entradas | Solo a **cierre de vela** M1 |
| Estructura | Solo sobre **velas cerradas**; swings por fractal, nunca ZigZag |
| Entrada tras pullback | Fuera del alcance v1 |
| RR | 1:1 fijo en v1 |

---

## El problema económico que gobierna el proyecto

Con RR 1:1, el win-rate de break-even es:

```
p = 0.5 + C / (2·S)     C = spread + comisión + slippage,  S = distancia del SL
```

XAUUSD con spread ~$0.30: SL de $1.50 → hace falta **60%** de aciertos solo para empatar; SL de $5.00 → **53%**.

Consecuencia de diseño: existe un filtro duro `S >= K · spread` (K por defecto 10, `min_sl_spread_multiple`) que **descarta el setup** si el stop queda demasiado apretado. La Fase 3 mide la distribución real de `S` y decide si M1 es viable o si hay que probar M5 como timeframe de entrada.

---

## Reactivo por diseño: el lag y la inflación de R

La estrategia **reacciona, no predice**. Todos los disparadores son hechos ya consumados:

| Elemento | Por qué es reactivo |
|---|---|
| Alineación H4/H1/M15 | El BOS **ya ocurrió**; no se anticipa ningún giro |
| P4 > P2 | El máximo más alto **ya está impreso** |
| Sweep | Solo cuenta si el precio **ya cerró de vuelta**; perforación sin recuperación invalida |
| Breakout | Entrada al **cierre** de la vela, con el nivel ya roto |
| Swings por fractal | Imposible de conocer hasta `N_right` barras después |

No hay ningún punto donde el algoritmo afirme "esto va a pasar". Esto es lo que hace que el backtest sea honesto y que no exista look-ahead.

**La única predicción, y es inevitable**, es que tras el breakout el precio recorre 1R antes que −1R. El condicionamiento son hechos; la apuesta es la continuación condicionada. La pregunta empírica del proyecto es si `P(recorre 1R | esta estructura exacta) > 55–60%`.

**El coste de reaccionar es el lag, y se paga en precio.** La entrada ocurre al cierre de una vela expandida —el peor precio de esa vela— y el stop se mide desde el mínimo del barrido, que para entonces ya quedó lejos. Ambas cosas **inflan R**. De ahí la tensión que gobierna todo el proyecto:

> R más grande → el spread pesa proporcionalmente menos (bueno) → pero el precio debe recorrer más distancia para alcanzar el 1:1 (malo).

Confirmar protege de falsos giros y cobra en distancia. Ese balance es exactamente lo que mide la Fase 3. Métricas concretas a extraer allí: distribución de `r_points`, barras hasta resolución, y ratio `MFE/R` de los setups perdedores — si los perdedores llegan sistemáticamente a 0.8R antes de fallar, el problema es el lag de entrada, no el patrón.

**Matiz importante:** que el trigger sea reactivo garantiza que el backtest es honesto, **no** que el patrón tenga edge. Reaccionar a una estructura y que esa estructura prediga algo son cosas distintas. Lo primero está garantizado por diseño; lo segundo lo deciden los datos de las Fases 3 y 5.

---

## Especificación algorítmica

Toda la estructura se calcula con `CopyRates(sym, tf, 1, N, rates)` + `ArraySetAsSeries(rates, true)`, de modo que `rates[0]` es **la última vela cerrada**. Nunca se lee la vela en formación. Esto elimina look-ahead y repintado por construcción.

### 1. Detección de swings — `SwingDetector.mqh`

Fractal de `N_left`/`N_right` barras (por defecto 2/2 en M1, 3/3 en HTF):

- `rates[i]` es swing high si su `high` supera al de las `N_left` barras más antiguas y al de las `N_right` más recientes.
- Un swing solo se **emite cuando ya existen `N_right` barras posteriores cerradas**. De ahí que no repinte nunca; el coste es un retraso conocido de `N_right` barras.
- **Alternancia forzada**: la secuencia debe alternar high/low. Ante dos highs consecutivos se conserva el más alto.
- **Filtro de pierna mínima**: se descarta el swing si `|precio − swing opuesto anterior| < min_leg_atr · ATR(tf, atr_period)`. Elimina swings de ruido, que son la causa principal de falsos patrones en M1.

Descartado ZigZag: reescribe el pasado y produce backtests fantasía.

### 2. Tendencia por timeframe — `StructureState.mqh` + `TrendFilter.mqh`

Máquina de estados por TF, `{BULL, BEAR, NEUTRAL}`, sin indicadores:

- Arranca en `NEUTRAL`.
- Cierre por encima del último swing high confirmado → `BULL` (BOS alcista).
- Cierre por debajo del último swing low confirmado → `BEAR` (BOS bajista).
- Se mantiene hasta el BOS contrario.

`TrendFilter` devuelve dirección operable solo si **H4 == H1 == M15** y el estado no es `NEUTRAL`. Sin alineación, no se evalúa M1.

### 3. El patrón de 4 puntos — `PatternDetector.mqh`

Máquina de estados sobre M1. Descrita para compra; venta es el espejo exacto.

| Punto | Condición |
|---|---|
| **P1** | Swing low confirmado — origen del impulso |
| **P2** | Swing high confirmado, con pierna `P1→P2 >= min_impulse_atr · ATR(M1)` |
| **P3** | Swing low confirmado, `P3 > P1` (higher low), con retroceso dentro de `[min_retrace, max_retrace]` del tramo P1→P2 (por defecto 20%–80%) |
| **P4** | Swing high confirmado, `P4 > P2` (higher high) → **BOS de continuación confirmado** |

Después de P4, fase de **barrido** — `LiquiditySweep.mqh`. Sea `L_s` el mínimo del barrido:

- `SWEEP_BREACH_P3`: `L_s < P3.low`, con una vela que **cierra de vuelta por encima** de `P3.low` en `max_sweep_bars` velas. Exige `L_s > P1.low`. Este modo invalida momentáneamente la estructura alcista de M1, y es deliberado.
- `SWEEP_INTERNAL`: `L_s >= P3.low`; barre el cluster de mínimos menores o iguales formado tras P4, con tolerancia de igualdad `eq_tol_atr · ATR`.
- `SWEEP_ANY`: cualquiera de los dos.

Regla común: **perforación sin recuperación no es un sweep, es continuación bajista** → invalida el setup.

Después del barrido, **breakout**: vela M1 cerrada con `close > P4.high` que pase el validador (§4), dentro de `max_bars_from_sweep` velas desde el barrido.

- **Entrada**: al cierre de esa vela.
- **SL**: `L_s − (sl_buffer_atr · ATR + spread)`.
- **TP**: `entry + (entry − SL) · rr`, con `rr = 1.0`.

**Invalidaciones** (resetean la máquina): cierre por debajo de `P1.low`; perforación de `P3` sin recuperación en modo BREACH; pérdida de la alineación HTF; timeout de `max_bars_to_complete` barras desde P4.

### 4. Breakout fuerte — `BreakoutValidator.mqh`

Las cinco condiciones deben cumplirse en la vela cerrada (defaults entre paréntesis):

1. `close > nivel`
2. `body / (high−low) >= min_body_ratio` (0.55)
3. `(close − low) / (high − low) >= min_close_pos` (0.70) — cierre en el tercio superior
4. `body >= min_body_atr · ATR(M1, atr_period)` (0.50)
5. `close − nivel >= max(min_penetration_atr · ATR, min_penetration_spreads · spread)` (0.10 ATR / 1.5 spreads)

La condición 5 es la que descarta el breakout de mecha que solo roza el nivel.

Las métricas se registran en el journal **aunque el breakout sea rechazado**: son las que permiten calibrar los umbrales con datos en lugar de a ojo.

### 5. Filtros

- **`SessionFilter.mqh`** — ventanas de Londres y Nueva York configurables en minutos GMT, con `broker_gmt_offset_min` como input, porque el reloj del bróker no siempre es GMT y cambia con el DST. El solape LN/NY se marca como `SESSION_OVERLAP` en el journal para poder medirlo, no se prioriza a fuego. Corte de viernes configurable, activo por defecto.
- **`VolatilityFilter.mqh`** — `ATR(M15,14) >= percentil 40` de sus últimos 100 valores. Un rango que no se mueve no genera impulsos válidos.
- **`SpreadFilter.mqh`** — `spread <= max_spread_points` **y** `distancia_SL >= min_sl_spread_multiple · spread`. Esta segunda condición es la puerta de viabilidad económica descrita arriba.
- **News filter** — diferido a Fase 4. Se usará la API de calendario de MQL5 con fallback a CSV, porque su disponibilidad en el Strategy Tester depende del build del terminal y hay que verificarlo empíricamente antes de depender de ella.

### 6. Journal — `Journal.mqh`

CSV en *Common Files* (convención que ya usa la skill `analyze`), **una fila por setup evaluado, incluidos los rechazados con su código de motivo**. Sin las filas rechazadas es imposible saber qué filtro está costando dinero.

La estructura `SSetup` de `Types.mqh` define las columnas: identificación, contexto de tendencia por TF, los cuatro puntos y el barrido, métricas del breakout, niveles, condiciones de mercado en el momento de la señal, y resultado (`status`, `reject_reason`, `outcome`, `mfe`, `mae`, `bars_to_resolve`).

Este fichero **es** el dataset que responde la pregunta de la distancia de SL.

---

## Arquitectura

Toda la lógica vive en `.mqh` reutilizados **sin cambios** por el indicador validador y por el EA. Una sola fuente de verdad: si el validador pinta un setup, el EA opera exactamente ese setup.

```
MQL5/
├── Include/4points/
│   ├── Types.mqh              # enums y structs — sin lógica          [Fase 0 ✅]
│   ├── Config.mqh             # SConfig: defaults y validación        [Fase 0 ✅]
│   ├── SwingDetector.mqh                                              [Fase 1]
│   ├── StructureState.mqh     # máquina BOS por timeframe             [Fase 1]
│   ├── TrendFilter.mqh        # alineación H4/H1/M15                   [Fase 1]
│   ├── PatternDetector.mqh    # máquina de estados de 4 puntos         [Fase 1]
│   ├── LiquiditySweep.mqh                                             [Fase 1]
│   ├── BreakoutValidator.mqh                                          [Fase 1]
│   ├── SessionFilter.mqh                                              [Fase 2]
│   ├── VolatilityFilter.mqh                                           [Fase 2]
│   ├── SpreadFilter.mqh                                               [Fase 2]
│   ├── Journal.mqh                                                    [Fase 2]
│   ├── Painter.mqh            # objetos de gráfico                     [Fase 2]
│   ├── RiskManager.mqh                                                [Fase 4]
│   └── TradeManager.mqh                                               [Fase 4]
├── Indicators/4points/FourPoints_Validator.mq5                        [Fase 2]
├── Experts/4points/FourPoints_EA.mq5                                  [Fase 4]
└── Scripts/4points/TestRunner.mq5                                     [Fase 1]
```

**Convenciones del workspace a respetar** (definidas en `.claude/skills/`):

- `input group ".......... Sección"` + comentario inline en **cada** `input`.
- `ArraySetAsSeries(..., true)` siempre que se espere índice 0 = vela más reciente, documentando por escrito qué significa cada índice en ese contexto.
- Objetos de gráfico: `ObjectFind` → `ObjectCreate` o `ObjectMove`, nombres deterministas, `ChartRedraw()` tras cada lote. `OBJ_RECTANGLE` para zonas, nunca dos líneas simulando un área.
- *Function ownership*: cada detector carga sus propias velas. Para poder testear, cada clase expone **dos** entradas: `Load()`, que hace el `CopyRates` internamente y es la que usan indicador y EA, y `Evaluate(const MqlRates &rates[])`, que recibe el array y es la que usan los tests con series sintéticas. La convención se respeta y la lógica sigue siendo testeable.

**Portabilidad**: nada en el repo contiene rutas absolutas. La única ruta específica de máquina es `MT5_TERMINAL_DIR`, en `deploy.config` (ignorado por git), y solo la usan los scripts de deploy y las invocaciones de MetaEditor.

---

## Fases

**Fase 0 — Scaffolding** *(en Linux)* ✅. `git init`, estructura, `Types.mqh`, `Config.mqh`, scripts de deploy, `CLAUDE.md` y este documento. Publicado en `git@github.com:cruzatadelacruzc/4points.git` y clonado desde ahí en la PC Windows, donde se retoma a partir de la Fase 1.

> **Reparto por entorno.** Nada del plan requiere Windows *específicamente*: requiere **MT5**. Sin MT5, Linux solo cubre la Fase 0, la redacción de código sin verificar, y el análisis del CSV de la Fase 3 (pandas sobre un fichero). Con MT5 bajo Wine, Linux cubriría el 100%. El único componente Windows-only del workspace es el paquete Python `MetaTrader5` de `.claude/scripts/interface.py`, que no interviene aquí.

**Fase 1 — Núcleo + tests.** Los seis detectores, y en paralelo `TestRunner.mq5` con series OHLC sintéticas construidas a mano: patrón perfecto, patrón sin P4, sweep sin recuperación, breakout de mecha, cuerpo insuficiente, retroceso demasiado profundo, timeout, pérdida de alineación HTF, y ambos modos de sweep. **Aquí vive el 80% del riesgo del proyecto y corre en segundos.** Sin lógica de trading ni gráficos.

**Fase 2 — Indicador validador** (entregable clave). Escanea todo el histórico en `OnCalculate` y, por cada setup detectado, pinta P1–P4 etiquetados, marca el barrido, resalta la vela de breakout, dibuja los rectángulos de SL y TP, simula el desenlace barra a barra y escribe la fila del journal. Panel con el estado H4/H1/M15 y contadores. **Criterio de salida: revisión visual de 20–30 setups marcados en XAUUSD M1 contra el criterio manual del trader.** Si el algoritmo no ve el patrón, se itera aquí, no en el EA.

**Fase 3 — Medición y decisión** (gate del proyecto). Ejecutar el validador sobre histórico de XAUUSD y EURUSD y analizar el CSV con `tools/analyze_journal.py`: distribución de `r_points` y su equivalente en dinero, win-rate de break-even implícito por tramo de SL, frecuencia de setups por sesión y símbolo, comparativa `SWEEP_BREACH_P3` vs `SWEEP_INTERNAL`, sensibilidad a los umbrales del breakout, y `MFE/R` de los perdedores. **De aquí sale el valor de `min_sl_spread_multiple` y la respuesta a si el 1:1 en M1 es viable o hay que mover la entrada a M5.** No se escribe el EA hasta cerrar este gate.

**Fase 4 — EA.** `FourPoints_EA.mq5` reutilizando los mismos `.mqh`, más `RiskManager` (riesgo % por operación, máxima pérdida diaria, máximas pérdidas consecutivas, una posición simultánea por defecto), `TradeManager` y el filtro de noticias.

**Fase 5 — Validación estadística.** Backtest con ticks reales, walk-forward, y test de robustez variando parámetros ±20% para confirmar que el resultado no depende de un punto exacto de optimización.

**Diferido explícitamente**: entradas tras pullback, TP dinámico, parciales, trailing, scanner multi-símbolo, riesgo de cartera y clasificación con IA. Todo ello se decide con los datos de la Fase 3 en la mano.

---

## Verificación

| Qué | Cómo | Criterio de éxito |
|---|---|---|
| Compilación | `MetaEditor64.exe /compile:<ruta> /log:<ruta>` y **leer el log** (exit code 0 no significa que compilara) | 0 errores y `.ex5` generado o actualizado |
| Fase 1 | Ejecutar `TestRunner.ex5` como script en cualquier gráfico; imprime PASS/FAIL por caso | 100% PASS antes de pasar a Fase 2 |
| Fase 2 | Adjuntar el validador a XAUUSD M1 e inspeccionar los setups marcados | El trader confirma que son los setups que él tomaría |
| No repintado | Comparar los setups marcados sobre histórico con los marcados en avance barra a barra en el mismo rango | Marcas idénticas |
| Fase 3 | `tools/analyze_journal.py` sobre el CSV de Common Files | Distribución de R publicada; decisión documentada sobre M1 vs M5 |
| Fases 4–5 | Strategy Tester con `.ini` según la skill `run-backtests`, `Model=4` (ticks reales), y leer el reporte | Métricas reales reportadas; si el test no arranca, se dice y se inspecciona el log, no se inventan resultados |

---

## Riesgos abiertos

1. **El 1:1 puede no sobrevivir a los costes en M1.** Mitigado por el gate de la Fase 3, que lo mide antes de invertir en el EA.
2. **La API de calendario económico puede no estar disponible en el Strategy Tester** según el build del terminal. Se verifica empíricamente en la Fase 4; fallback a CSV.
3. **El retraso de `N_right` barras en la confirmación de swings** desplaza el reconocimiento del patrón respecto a la lectura visual del trader. Es medible en la Fase 2 y ajustable vía `swing_right`, a costa de más ruido.
4. **XAUUSD y EURUSD tienen regímenes de volatilidad muy distintos.** Por eso todos los umbrales se expresan en múltiplos de ATR o de spread, nunca en pips fijos.
