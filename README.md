# 4 Points

Expert Advisor de MetaTrader 5 para continuación de tendencia basada en **estructura de mercado y liquidez**, sin indicadores.

La estrategia exige alineación estructural en H4, H1 y M15; localiza en M1 un patrón de cuatro puntos (impulso, pullback, nuevo extremo, segundo pullback); espera un **barrido de liquidez**; y entra al cierre de una vela de breakout que supere el nuevo extremo. Riesgo/beneficio fijo 1:1.

Símbolos iniciales: **XAUUSD** y **EURUSD**. La arquitectura admite más instrumentos sin tocar la lógica, porque todos los umbrales se expresan en múltiplos de ATR o de spread, nunca en pips fijos.

## Estado

**Fase 0 — completada.** Scaffolding, tipos y configuración.

El proyecto avanza en fases y el orden es deliberado:

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Scaffolding, `Types.mqh`, `Config.mqh`, deploy | ✅ |
| 1 | Detectores + `TestRunner` con series sintéticas | pendiente |
| 2 | Indicador validador: pinta el patrón sobre el histórico | pendiente |
| 3 | Medición estadística y **gate de viabilidad** | pendiente |
| 4 | Expert Advisor con gestión de riesgo | pendiente |
| 5 | Backtest con ticks reales, walk-forward, robustez | pendiente |

El primer entregable no es el EA: es un **indicador que dibuja el patrón** sobre el histórico, para verificar que el algoritmo reconoce lo que el trader reconoce a ojo antes de escribir una sola línea de lógica de dinero.

## Por qué el gate de la Fase 3

Con RR 1:1, el win-rate de break-even es `p = 0.5 + C / (2·S)`, donde `C` es el coste de transacción y `S` la distancia del stop. En XAUUSD con spread de $0.30, un stop de $1.50 exige **60% de aciertos solo para empatar**; uno de $5.00 exige 53%.

La distancia real del stop en esta estrategia **no está medida todavía**. La Fase 3 la mide sobre histórico y decide si M1 es viable o si la entrada debe moverse a M5. El EA no se escribe antes de cerrar esa pregunta.

## Estructura

```
MQL5/Include/4points/     Toda la lógica: detectores, filtros, journal
MQL5/Indicators/4points/  Indicador validador (Fase 2)
MQL5/Experts/4points/     Expert Advisor (Fase 4)
MQL5/Scripts/4points/     TestRunner (Fase 1)
tools/                    Análisis del journal en Python (Fase 3)
docs/superpowers/specs/   Documento de diseño
```

El indicador y el EA comparten los mismos `.mqh` sin modificarlos: si el validador pinta un setup, el EA opera exactamente ese setup.

## Puesta en marcha

```bash
cp deploy.config.example deploy.config   # y ajusta MT5_TERMINAL_DIR
./deploy.sh --dry-run
./deploy.sh
```

En Windows, `.\deploy.ps1`. Después, compilar desde MetaEditor.

Detalles de comandos, convenciones e invariantes de diseño: [`CLAUDE.md`](CLAUDE.md).
Diseño completo y justificación: [`docs/superpowers/specs/2026-08-06-4points-continuation-design.md`](docs/superpowers/specs/2026-08-06-4points-continuation-design.md).
