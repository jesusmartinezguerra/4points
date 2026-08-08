# Diseño — Fase 1: núcleo con detectores + tests

**Fecha:** 2026-08-08
**Estado:** aprobado
**Depende de:** `docs/superpowers/specs/2026-08-06-4points-continuation-design.md` (fija el algoritmo; este documento fija el enfoque de construcción)

---

## Contexto

El spec de Fase 0 ya define, para cada uno de los seis detectores de la Fase 1, su algoritmo exacto (fractal de swings, máquina BOS, alineación HTF, máquina de estados de 4 puntos, barrido, breakout fuerte) y la lista de casos de prueba mínimos. Lo que falta acordar no es *qué* construir, sino *cómo*: orden de construcción, y organización de `TestRunner.mq5` y sus casos.

## Decisiones

| Decisión | Valor |
|---|---|
| Metodología | TDD estricto, un detector a la vez |
| Orden de construcción | El orden de dependencias del spec: `SwingDetector → StructureState → TrendFilter → PatternDetector → LiquiditySweep → BreakoutValidator` |
| Organización de tests | `TestRunner.mq5` delgado + un `.mqh` de casos por detector bajo `Scripts/4points/Tests/` |
| Helper compartido | `TestHelpers.mqh` con `Assert()` y builders de `MqlRates` sintéticos |

## Flujo de trabajo por detector

Para cada uno de los seis, en el orden de la tabla:

1. Escribir los casos de ese detector en su archivo `Tests/<Detector>Tests.mqh`, referenciando una clase que todavía no existe (o existe vacía). Los tests deben fallar.
2. Implementar la clase en `Include/4points/<Detector>.mqh` siguiendo la convención de la skill `candles-and-series`: `Load()` hace el `CopyRates` real; `Evaluate(const MqlRates &rates[])` recibe la serie ya cargada y es la que ejercitan los tests.
3. Compilar `TestRunner.mq5` (arrastra todos los includes) y ejecutarlo como script. Iterar hasta que los casos de ese detector den PASS.
4. Pasar al siguiente detector. No se reordena ni se paraleliza: cada detector depende del anterior salvo `BreakoutValidator`, que se deja al final de todos modos por ser el que cierra la cadena de evaluación.

## Estructura de archivos

```
MQL5/Scripts/4points/
├── TestRunner.mq5              # script que se compila/ejecuta; incluye todo lo de abajo
└── Tests/
    ├── TestHelpers.mqh         # Assert(cond, name) + contador global PASS/FAIL + builders de MqlRates
    ├── SwingDetectorTests.mqh
    ├── StructureStateTests.mqh
    ├── TrendFilterTests.mqh
    ├── PatternDetectorTests.mqh
    ├── LiquiditySweepTests.mqh
    └── BreakoutValidatorTests.mqh
```

`TestHelpers.mqh` expone:

- `Assert(bool condition, string case_name)` — imprime `PASS`/`FAIL <case_name>` al log de Expertos y acumula en contadores globales (`g_tests_total`, `g_tests_passed`).
- Un builder de series sintéticas que arma un `MqlRates[]` a partir de arrays paralelos de OHLC (y opcionalmente `time`/`tick_volume`), para que cada caso construya su escenario sin repetir boilerplate.

`TestRunner.mq5` termina imprimiendo el resumen `N/M PASS`. El criterio de salida de la Fase 1, ya fijado en el spec de Fase 0, es 100% en ese resumen antes de pasar a la Fase 2.

## Casos de prueba por detector

Los casos transversales ya enumerados en el spec de Fase 0 (patrón perfecto, patrón sin P4, sweep sin recuperación, breakout de mecha, cuerpo insuficiente, retroceso demasiado profundo/superficial, timeout, pérdida de alineación HTF, ambos modos de sweep) se reparten en el archivo de test del detector que los origina — por ejemplo "retroceso demasiado profundo" es un caso de `PatternDetectorTests.mqh`, "breakout de mecha" de `BreakoutValidatorTests.mqh`. Cada detector añade además sus propios casos de borde:

- **SwingDetector**: alternancia forzada (dos highs seguidos → se queda el más alto), filtro de pierna mínima en ATR, swing que aún no tiene las `N_right` barras para confirmarse.
- **StructureState**: arranque en `NEUTRAL`, transición `BULL→BEAR` por cierre bajo el último swing low, no cambia de estado sin BOS.
- **TrendFilter**: alineación total, un timeframe en `NEUTRAL`, timeframes en direcciones opuestas.
- **PatternDetector**: la secuencia completa P1→P2→P3→P4, y cada invalidación (cierre bajo `P1.low`, timeout desde P4).
- **LiquiditySweep**: `SWEEP_BREACH_P3` válido, `SWEEP_INTERNAL` válido, barrido que perfora más allá de `P1.low` (invalida), `SWEEP_ANY` aceptando cualquiera de los dos modos.
- **BreakoutValidator**: cada una de las 5 condiciones fallando de forma aislada (para poder atribuir el rechazo a la condición correcta), y el caso donde las 5 se cumplen.

## Fuera de alcance de este documento

Filtros de sesión/volatilidad/spread, journal, painter y el propio indicador validador son Fase 2 y ya están fuera del árbol de dependencias de estos seis detectores; no se tocan aquí.

## Nota operativa: cuenta MT5 en vivo

La máquina de desarrollo tiene un MCP y skills conectados a la cuenta MT5 real del usuario. Nada de la Fase 1 los necesita (los tests corren sobre series sintéticas, sin datos de mercado ni conexión a cuenta), pero queda documentado en `CLAUDE.md` que cualquier uso de esas herramientas en este o futuros trabajos requiere pedir permiso explícito en el chat antes de invocarlas.
