# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es este proyecto

Expert Advisor de MetaTrader 5 que traduce una estrategia discrecional de **estructura de mercado, price action y liquidez** —sin indicadores— a reglas objetivas. Opera continuación de tendencia: exige alineación H4/H1/M15, detecta un patrón de 4 puntos en M1, espera un barrido de liquidez y entra al cierre de una vela de breakout, con RR fijo 1:1. Símbolos iniciales: XAUUSD y EURUSD.

El diseño completo está en `docs/superpowers/specs/2026-08-06-4points-continuation-design.md`. **Léelo antes de tocar la lógica**: contiene las definiciones formales de swing, tendencia, barrido y breakout, y el razonamiento económico que justifica los umbrales.

## Estado actual

Fase 1 completada: los seis detectores en `MQL5/Include/4points/` (`SwingDetector`, `StructureState`, `TrendFilter`, `PatternDetector`, `LiquiditySweep`, `BreakoutValidator`) más el `AtrUtils.mqh` compartido, con `TestRunner.mq5` en 100% PASS. La siguiente es la **Fase 2**: el indicador validador (`FourPoints_Validator.mq5`), que pinta los setups sobre histórico sin duplicar lógica de estos detectores. No existe todavía ni el indicador ni el EA.

El orden de fases no es negociable: **núcleo con tests → indicador validador → medición estadística → EA**. La Fase 3 es un gate real; el EA no se escribe hasta que los datos confirmen que el 1:1 es viable en M1.

## Comandos

Requieren MetaTrader 5 instalado. En Linux sin MT5 solo se puede escribir código y analizar CSV ya generados.

```bash
# Desplegar el código en la carpeta del terminal (el repo es la fuente de verdad)
./deploy.sh --dry-run          # ver qué se copiaría
./deploy.sh                    # copiar
.\deploy.ps1                   # equivalente en Windows
```

```powershell
# Compilar. SIEMPRE leer el log: exit code 0 NO significa que compilara.
& 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' `
    /compile:'<terminal-dir>\MQL5\Indicators\4points\FourPoints_Validator.mq5' `
    /log:'<terminal-dir>\MQL5\Logs\4points-compile.log'
```

```powershell
# Backtest: crear un .ini de tester y lanzarlo. Model=4 son ticks reales.
Start-Process -FilePath 'C:\Program Files\MetaTrader 5\terminal64.exe' `
    -ArgumentList '/config:<terminal-dir>\config\4points-xauusd.ini' -Wait
```

**Tests de la Fase 1**: compilar `MQL5/Scripts/4points/TestRunner.mq5` y ejecutarlo como script sobre cualquier gráfico. Imprime PASS/FAIL por caso en el log de Expertos. Alimenta series OHLC sintéticas a los detectores, así que no necesita datos de mercado y corre en segundos. Debe dar 100% PASS antes de pasar a la Fase 2.

## Arquitectura

Toda la lógica vive en `.mqh` bajo `MQL5/Include/4points/`. El indicador validador y el EA son **cascarones delgados** que consumen esos mismos módulos sin modificarlos. Una sola fuente de verdad: si el validador pinta un setup, el EA opera exactamente ese setup. Nunca dupliques lógica entre ambos.

Cadena de evaluación, cada eslabón puede rechazar y anotar el motivo:

```
SessionFilter → TrendFilter(H4,H1,M15) → VolatilityFilter
   → PatternDetector(M1): P1→P2→P3→P4
   → LiquiditySweep → BreakoutValidator → SpreadFilter
   → [Fase 4] RiskManager → TradeManager
   → Journal (registra TODO, aceptado o rechazado)
```

`Config.mqh` es la única fuente de defaults de parámetros; el indicador y el EA declaran sus `input` y los vuelcan a un `SConfig`. `Types.mqh` es el vocabulario compartido y no contiene lógica.

## Invariantes que no se rompen

Estas reglas existen por razones concretas documentadas en el spec. Si algo parece exigir romperlas, es señal de que el diseño necesita revisión, no de que la regla sobre.

- **Solo velas cerradas.** Carga con `CopyRates(sym, tf, 1, N, rates)` para que `rates[0]` sea la última vela cerrada. Leer la vela en formación (`shift 0`) introduce look-ahead que hace el backtest inservible.
- **Nada de ZigZag** ni de cualquier cosa que reescriba el pasado. Los swings se confirman por fractal tras `N_right` barras cerradas, y por eso no repintan.
- **Ningún umbral en pips fijos.** Todo en múltiplos de ATR o de spread. Es lo único que permite usar el mismo código en oro y en divisas.
- **El journal registra los setups rechazados**, con su `ERejectReason`. Sin las filas rechazadas es imposible saber qué filtro está costando dinero.
- **Entrada solo al cierre de vela.** Sin confirmación intrabar.

## Convenciones del workspace

Definidas en `.claude/skills/`. Las relevantes al escribir código aquí:

- **Inputs** (`expert-advisors`): agrupar con `input group ".......... Sección"` y poner comentario inline en **cada** `input`.
- **Series** (`candles-and-series`): `ArraySetAsSeries(array, true)` siempre que se espere índice 0 = vela más reciente, y documentar por escrito qué significa cada índice en ese contexto concreto.
- **Objetos de gráfico** (`paint-objects`): `ObjectFind` → `ObjectCreate` si no existe, `ObjectMove` si existe. Nombres deterministas. `ChartRedraw()` tras cada lote. `OBJ_RECTANGLE` para zonas, nunca dos líneas simulando un área.
- **Function ownership** (`candles-and-series`): cada detector carga sus propias velas. Para que siga siendo testeable, cada clase expone **dos** entradas: `Load()`, que hace el `CopyRates` internamente y es la que usan indicador y EA, y `Evaluate(const MqlRates &rates[])`, que recibe el array ya cargado y es la que usan los tests con series sintéticas.
- **Git** (`git`): ramas `feature/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`. Commits `type(scope): summary` en minúsculas y sin punto final.

## Cuenta MT5 en vivo — pedir permiso antes de usarla

La PC tiene MT5 y Python instalados, con varias skills de backtesting (`run-backtests`, `optimize`, `analyze`, `orquestate`) y un MCP (`mcp__metatrader__*`, y `interface.py`) **conectado a la cuenta real del usuario**.

- **Antes de invocar cualquiera de esas skills o herramientas MCP**, incluso para algo aparentemente de solo lectura como consultar precio o posiciones, pide permiso explícito en el chat y espera confirmación. No asumas autorización previa de una sesión anterior.
- Esto aplica en particular a cualquier acción con efecto en la cuenta: abrir/cerrar posiciones, órdenes pendientes, modificar SL/TP. Esas nunca se ejecutan sin una confirmación explícita y específica para esa acción.
- Escribir o compilar código MQL5, o correr `TestRunner.mq5` con series sintéticas, no toca la cuenta y no requiere este permiso.

## Rutas y portabilidad

Nada en el repo contiene rutas absolutas. La única ruta específica de máquina es `MT5_TERMINAL_DIR`, que vive en `deploy.config` (ignorado por git) y solo la usan los scripts de deploy y las invocaciones de MetaEditor.

Nada del proyecto requiere Windows *específicamente*: requiere **MT5**, que también corre en Linux bajo Wine. El único componente Windows-only del workspace es el paquete Python `MetaTrader5` que usa `.claude/scripts/interface.py`, y no interviene en este proyecto.

Ojo si trabajas sobre la partición NTFS: `core.filemode` está en `false` porque el mount reporta todos los ficheros como 777, y los symlinks no son fiables — de ahí que el deploy copie en lugar de enlazar.
