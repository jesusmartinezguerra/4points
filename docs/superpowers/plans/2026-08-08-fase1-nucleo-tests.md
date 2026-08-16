# Fase 1 — Núcleo de detectores + TestRunner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the six Fase 1 detectors (`SwingDetector`, `StructureState`, `TrendFilter`, `PatternDetector`, `LiquiditySweep`, `BreakoutValidator`) under `MQL5/Include/4points/`, plus `MQL5/Scripts/4points/TestRunner.mq5`, so the whole suite compiles and prints `100% PASS` before Fase 2 (the validator indicator) begins.

**Architecture:** Each detector is a class with two entry points — `Load()` (does `CopyRates` internally, used by the future indicator/EA) and `Evaluate(const MqlRates &rates[], ...)` (takes an already-loaded series, used by tests). Detectors compose: `StructureState` uses `SwingDetector` internally, `TrendFilter` uses three `StructureState` instances, `PatternDetector` uses `SwingDetector`. `LiquiditySweep` and `BreakoutValidator` are independent. A shared `SimpleATR()` helper avoids duplicating the ATR formula across four detectors that need it.

**Tech Stack:** MQL5 (MetaEditor64.exe compiler), no external dependencies. Tests are a hand-rolled PASS/FAIL harness (`TestHelpers.mqh`) run as an `.mq5` script inside the MetaTrader 5 terminal — there is no MQL5 unit-testing framework in this workspace.

## Global Constraints

- Only closed candles: always `CopyRates(symbol, tf, 1, N, rates)` in every `Load()`, never shift `0`. (`CLAUDE.md`, invariantes)
- `ArraySetAsSeries(array, true)` on every rates array where index `0` must mean "most recent candle" — apply it right after the array is populated, whether by `CopyRates` or by the synthetic builder in tests. (`.claude/skills/candles-and-series/SKILL.md`)
- No ZigZag, no repainting: swings only become known once their `N_right` confirmation bars exist in the array. (`CLAUDE.md`, invariantes)
- No fixed-pip thresholds anywhere: every threshold is a multiple of ATR or of spread. (`CLAUDE.md`, invariantes; `docs/superpowers/specs/2026-08-06-4points-continuation-design.md`)
- Every detector class exposes exactly `Load(...)` and `Evaluate(const MqlRates &rates[], ...)` — tests only ever call `Evaluate`. **Exception:** `TrendFilter` (Task 5), whose `Evaluate` takes three already-resolved `ETrendState` values instead of a rates array — justified in Task 5's design note, not an oversight. (`.claude/skills/candles-and-series/SKILL.md`, function ownership; `docs/superpowers/specs/2026-08-08-4points-fase1-nucleo-tests-design.md`)
- Branch name: `feature/fase1-nucleo-tests`. Commits: `type(scope): summary`, lowercase, no trailing period, one focused change per commit. (`.claude/skills/git/SKILL.md`)
- Compile with MetaEditor64.exe and always read the resulting log — a `0` exit code does not mean it compiled. (`.claude/skills/compile-mql5/SKILL.md`)
- MT5 terminal directory for this machine is in `deploy.config` (gitignored): `C:/Users/Peter/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075`. Deploy with `./deploy.sh` (or `.\deploy.ps1` from PowerShell) before every compile, since MetaEditor compiles from the terminal's `MQL5/` folder, not from the repo.
- Never touch the live MT5 MCP / trading skills without asking first — irrelevant here since everything runs on synthetic data, but do not reach for `mcp__metatrader__*` or `interface.py` during this plan. (`CLAUDE.md`, cuenta MT5 en vivo)

---

## File Structure

```
MQL5/Include/4points/
├── AtrUtils.mqh            # NEW — SimpleATR(), shared by 4 of the 6 detectors
├── SwingDetector.mqh       # NEW — CSwingDetector
├── StructureState.mqh      # NEW — CStructureState (uses CSwingDetector)
├── TrendFilter.mqh         # NEW — CTrendFilter (uses 3x CStructureState)
├── PatternDetector.mqh     # NEW — CPatternDetector (uses CSwingDetector)
├── LiquiditySweep.mqh      # NEW — CLiquiditySweep
└── BreakoutValidator.mqh   # NEW — CBreakoutValidator

MQL5/Scripts/4points/
├── TestRunner.mq5          # NEW — script entry point, prints "N/M PASS"
└── Tests/
    ├── TestHelpers.mqh         # NEW — Assert(), counters, synthetic MqlRates builder
    ├── AtrUtilsTests.mqh       # NEW
    ├── SwingDetectorTests.mqh  # NEW
    ├── StructureStateTests.mqh # NEW
    ├── TrendFilterTests.mqh    # NEW
    ├── PatternDetectorTests.mqh    # NEW
    ├── LiquiditySweepTests.mqh     # NEW
    └── BreakoutValidatorTests.mqh  # NEW
```

`AtrUtils.mqh` is not in the six-file list from the Fase 0 spec's architecture table — it is a small addition justified by DRY: `SwingDetector`, `PatternDetector`, `LiquiditySweep`, and `BreakoutValidator` all need the same ATR-over-a-rates-array computation, and duplicating that formula four times risks the four detectors drifting out of sync, which is exactly what `Config.mqh`/`Types.mqh` being single sources of truth is meant to prevent.

**Design decision carried into every task:** ATR here is a **simple moving average of True Range**, not Wilder's smoothed ATR. This is deliberate: Wilder's ATR needs a seed period and asymptotically depends on how much history precedes the window, which makes it non-deterministic to hand-build in short synthetic test series. A plain SMA of True Range over `atr_period` bars is fully determined by the bars actually present in the test array. If Fase 3's real-data measurement later shows this matters, swapping the formula only touches `AtrUtils.mqh`.

---

### Task 1: Test harness scaffolding

**Files:**
- Create: `MQL5/Scripts/4points/Tests/TestHelpers.mqh`
- Create: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Produces: `void ResetTestCounters()`, `void Assert(const bool condition, const string case_name)`, `void PrintTestSummary()`, `void BuildRatesSeries(const datetime &times[], const double &opens[], const double &highs[], const double &lows[], const double &closes[], MqlRates &out[])` — all later test files use these.

- [ ] **Step 1: Create the branch**

```bash
git checkout -b feature/fase1-nucleo-tests
```

- [ ] **Step 2: Write `TestHelpers.mqh`**

```mq5
//+------------------------------------------------------------------+
//|                                                  TestHelpers.mqh |
//|  Arnes de test minimo para TestRunner.mq5: contador PASS/FAIL y  |
//|  un builder de MqlRates sinteticos a partir de arrays paralelos. |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_TESTHELPERS_MQH
#define FOURPOINTS_TESTHELPERS_MQH

int g_tests_total  = 0;
int g_tests_passed = 0;

void ResetTestCounters()
  {
   g_tests_total  = 0;
   g_tests_passed = 0;
  }

void Assert(const bool condition, const string case_name)
  {
   g_tests_total++;
   if(condition)
     {
      g_tests_passed++;
      PrintFormat("PASS %s", case_name);
     }
   else
     {
      PrintFormat("FAIL %s", case_name);
     }
  }

void PrintTestSummary()
  {
   PrintFormat("%d/%d PASS", g_tests_passed, g_tests_total);
  }

//+------------------------------------------------------------------+
//| Construye un MqlRates[] en orden de serie (indice 0 = mas        |
//| reciente) a partir de arrays paralelos en orden cronologico      |
//| (indice 0 = mas antiguo), que es como resulta mas natural         |
//| escribir un escenario de test a mano.                            |
//+------------------------------------------------------------------+
void BuildRatesSeries(const datetime &times[], const double &opens[], const double &highs[],
                       const double &lows[], const double &closes[], MqlRates &out[])
  {
   int n = ArraySize(times);
   ArrayResize(out, n);
   for(int i = 0; i < n; i++)
     {
      int src = n - 1 - i; // invierte: la ultima entrada cronologica va al indice 0
      out[i].time         = times[src];
      out[i].open         = opens[src];
      out[i].high         = highs[src];
      out[i].low          = lows[src];
      out[i].close        = closes[src];
      out[i].tick_volume  = 1;
      out[i].spread       = 0;
      out[i].real_volume  = 0;
     }
   ArraySetAsSeries(out, true);
  }

#endif // FOURPOINTS_TESTHELPERS_MQH
```

- [ ] **Step 3: Write `TestRunner.mq5` skeleton**

```mq5
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
```

- [ ] **Step 4: Deploy and compile**

```bash
./deploy.sh
```

```powershell
& 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' `
    /compile:'C:\Users\Peter\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\4points\TestRunner.mq5' `
    /log:'C:\Users\Peter\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Logs\4points-compile.log'
```

Read the log. Expected: `0 error(s), 0 warning(s)` and `TestRunner.ex5` produced next to the `.mq5`.

- [ ] **Step 5: Run it**

In the terminal: Navigator → Scripts → 4points → drag `TestRunner` onto any open chart. Expected output in the Experts log: `0/0 PASS`.

- [ ] **Step 6: Commit**

```bash
git add MQL5/Scripts/4points/TestRunner.mq5 MQL5/Scripts/4points/Tests/TestHelpers.mqh
git commit -m "test(4points): add test harness scaffolding"
```

---

### Task 2: `AtrUtils.mqh` — shared ATR helper

**Files:**
- Create: `MQL5/Include/4points/AtrUtils.mqh`
- Create: `MQL5/Scripts/4points/Tests/AtrUtilsTests.mqh`
- Modify: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Consumes: `Assert()`, `BuildRatesSeries()` from `TestHelpers.mqh` (Task 1).
- Produces: `double SimpleATR(const MqlRates &rates[], const int period, const int shift = 0)` — returns `-1.0` if there are not enough bars. Used by `SwingDetector`, `PatternDetector`, `LiquiditySweep`, `BreakoutValidator` in later tasks.

- [ ] **Step 1: Write the failing tests**

Create `MQL5/Scripts/4points/Tests/AtrUtilsTests.mqh`:

```mq5
#ifndef FOURPOINTS_ATRUTILSTESTS_MQH
#define FOURPOINTS_ATRUTILSTESTS_MQH

#include <4points/AtrUtils.mqh>

void RunAtrUtilsTests()
  {
   // Serie con True Range constante = 2.0 en cada vela (high-low=2, sin gaps).
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, 6); ArrayResize(o, 6); ArrayResize(h, 6); ArrayResize(l, 6); ArrayResize(c, 6);
   for(int i = 0; i < 6; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60;
      o[i] = 100.0; h[i] = 101.0; l[i] = 99.0; c[i] = 100.0;
     }
   MqlRates rates[];
   BuildRatesSeries(t, o, h, l, c, rates);

   Assert(MathAbs(SimpleATR(rates, 5, 0) - 2.0) < 0.0001, "AtrUtils: TR constante da ATR = TR");
   Assert(SimpleATR(rates, 5, 1) < 0.0, "AtrUtils: sin barras suficientes devuelve -1");
   Assert(MathAbs(SimpleATR(rates, 3, 1) - 2.0) < 0.0001, "AtrUtils: shift > 0 usa la ventana correcta");
  }

#endif // FOURPOINTS_ATRUTILSTESTS_MQH
```

Add to `TestRunner.mq5` (after the include block, and inside `OnStart` before `PrintTestSummary()`):

```mq5
#include "Tests/AtrUtilsTests.mqh"
```

```mq5
   RunAtrUtilsTests();
```

- [ ] **Step 2: Deploy, compile, confirm it fails**

```bash
./deploy.sh
```

Compile as in Task 1 Step 4. Expected: compile error — `AtrUtils.mqh` does not exist yet (`cannot open include file`).

- [ ] **Step 3: Implement `AtrUtils.mqh`**

```mq5
//+------------------------------------------------------------------+
//|                                                       AtrUtils.mqh |
//|  ATR compartido por los detectores que lo necesitan. Es la media  |
//|  simple del True Range, no la suavizada de Wilder — ver la nota   |
//|  de diseno en el plan de la Fase 1: es determinista sobre series  |
//|  sinteticas cortas, sin barras de precalentamiento.               |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_ATRUTILS_MQH
#define FOURPOINTS_ATRUTILS_MQH

//+------------------------------------------------------------------+
//| rates debe estar en orden de serie (indice 0 = mas reciente).     |
//| shift es el indice de la vela mas reciente incluida en el calculo.|
//| Devuelve -1.0 si no hay suficiente historia en el array.          |
//+------------------------------------------------------------------+
double SimpleATR(const MqlRates &rates[], const int period, const int shift = 0)
  {
   int size = ArraySize(rates);
   if(period <= 0 || shift < 0 || shift + period >= size)
      return -1.0;

   double sum = 0.0;
   for(int i = shift; i < shift + period; i++)
     {
      double prev_close = rates[i + 1].close;
      double tr = MathMax(rates[i].high - rates[i].low,
                  MathMax(MathAbs(rates[i].high - prev_close),
                          MathAbs(rates[i].low  - prev_close)));
      sum += tr;
     }
   return sum / period;
  }

#endif // FOURPOINTS_ATRUTILS_MQH
```

- [ ] **Step 4: Deploy, compile, confirm 0 errors, run, confirm PASS**

```bash
./deploy.sh
```

Compile, read log: expect 0 errors. Run `TestRunner` on a chart: expect `PASS AtrUtils: TR constante da ATR = TR`, `PASS AtrUtils: sin barras suficientes devuelve -1`, `PASS AtrUtils: shift > 0 usa la ventana correcta`, summary `3/3 PASS`.

- [ ] **Step 5: Commit**

```bash
git add MQL5/Include/4points/AtrUtils.mqh MQL5/Scripts/4points/Tests/AtrUtilsTests.mqh MQL5/Scripts/4points/TestRunner.mq5
git commit -m "feat(4points): add shared simple-atr helper"
```

---

### Task 3: `SwingDetector.mqh` — `CSwingDetector`

**Files:**
- Create: `MQL5/Include/4points/SwingDetector.mqh`
- Create: `MQL5/Scripts/4points/Tests/SwingDetectorTests.mqh`
- Modify: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Consumes: `SimpleATR()` (Task 2); `SSwing`, `ESwingType` (`Types.mqh`, existing).
- Produces: class `CSwingDetector` with constructor `CSwingDetector(const int left, const int right, const double min_leg_atr, const int atr_period)` and `bool Evaluate(const MqlRates &rates[], SSwing &swings[])` — fills `swings[]` in chronological order (index `0` = earliest confirmed swing). `swings[i].bar_shift` is the index into the `rates[]` array that was passed in. Used by `StructureState` (Task 4) and `PatternDetector` (Task 6).

- [ ] **Step 1: Write the failing tests**

Create `MQL5/Scripts/4points/Tests/SwingDetectorTests.mqh`:

```mq5
#ifndef FOURPOINTS_SWINGDETECTORTESTS_MQH
#define FOURPOINTS_SWINGDETECTORTESTS_MQH

#include <4points/SwingDetector.mqh>

void RunSwingDetectorTests()
  {
   // --- Caso 1: alternancia perfecta low-high-low-high, fractal 2/2, sin filtro de pierna.
   // Cronologico (indice 0 = mas antiguo): low en 2, high en 5, low en 8, high en 11.
   datetime t[]; double o[], h[], l[], c[];
   int n = 14;
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   double base_high[] = {100,100,100,100,100,100,100,100,100,100,100,100,100,100};
   double base_low[]  = {95,95,95,95,95,95,95,95,95,95,95,95,95,95};
   for(int i = 0; i < n; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60;
      h[i] = base_high[i];
      l[i] = base_low[i];
      o[i] = (h[i] + l[i]) / 2.0;
      c[i] = o[i];
     }
   l[2] = 90.0;  // swing low
   h[5] = 105.0; // swing high
   l[8] = 88.0;  // swing low (mas bajo que el de indice 2)
   h[11] = 106.0; // swing high

   MqlRates rates1[];
   BuildRatesSeries(t, o, h, l, c, rates1);

   CSwingDetector det(2, 2, 0.0, 14); // min_leg_atr = 0 desactiva el filtro de pierna
   SSwing swings1[];
   bool ok1 = det.Evaluate(rates1, swings1);
   Assert(ok1 && ArraySize(swings1) == 4, "SwingDetector: alternancia perfecta detecta 4 swings");
   if(ArraySize(swings1) == 4)
     {
      Assert(swings1[0].type == SWING_LOW && MathAbs(swings1[0].price - 90.0) < 0.0001,
             "SwingDetector: primer swing es el low de indice 2");
      Assert(swings1[3].type == SWING_HIGH && MathAbs(swings1[3].price - 106.0) < 0.0001,
             "SwingDetector: cuarto swing es el high de indice 11");
     }

   // --- Caso 2: dos highs consecutivos -> se conserva el mas alto.
   double h2[] = {100,100,100,100,100,100,100,100,100,100,100,100,100,100};
   double l2[] = {95,95,95,95,95,95,95,95,95,95,95,95,95,95};
   double o2[n], c2[n]; datetime t2[n];
   for(int i = 0; i < n; i++)
     {
      t2[i] = D'2026.01.01 00:00' + i * 60;
      o2[i] = (h2[i] + l2[i]) / 2.0;
      c2[i] = o2[i];
     }
   l2[2] = 90.0;   // low inicial
   h2[5] = 105.0;  // high #1
   h2[8] = 108.0;  // high #2, mas alto -> debe reemplazar al #1

   MqlRates rates2[];
   BuildRatesSeries(t2, o2, h2, l2, c2, rates2);
   SSwing swings2[];
   det.Evaluate(rates2, swings2);
   Assert(ArraySize(swings2) == 2, "SwingDetector: dos highs seguidos colapsan a uno solo");
   if(ArraySize(swings2) == 2)
      Assert(MathAbs(swings2[1].price - 108.0) < 0.0001, "SwingDetector: se conserva el high mas alto");

   // --- Caso 3: filtro de pierna minima descarta un swing demasiado pequeno.
   CSwingDetector det_strict(2, 2, 5.0, 14); // exige pierna >= 5 * ATR
   SSwing swings3[];
   det_strict.Evaluate(rates1, swings3);
   // Con ATR chico (rango tipico ~5-15) y min_leg_atr=5, la pierna low(90)->high(105)=15
   // puede o no pasar segun el ATR real; se verifica que el detector no revienta y que
   // el resultado tiene como mucho los mismos swings que el caso sin filtro.
   Assert(ArraySize(swings3) <= ArraySize(swings1), "SwingDetector: filtro de pierna nunca añade swings");

   // --- Caso 4: los ultimos `right` bars no permiten confirmar swing ahi.
   // Con fractal 2/2 y 14 velas, el ultimo swing detectable esta en indice <= n-1-2=11.
   bool any_beyond = false;
   for(int i = 0; i < ArraySize(swings1); i++)
      if(swings1[i].bar_shift < 2) // bar_shift medido en el array 0..n-1, aqui el "reciente" es el indice bajo tras invertir
         any_beyond = true;
   Assert(!any_beyond, "SwingDetector: no confirma swings sin sus N_right barras");
  }

#endif // FOURPOINTS_SWINGDETECTORTESTS_MQH
```

Note on Caso 4: `BuildRatesSeries` reverses chronological input into series order, so the chronologically-last bars (highest input index) land at the lowest `rates[]` indices. `bar_shift` is stored in that series indexing, so "the last `right` bars have no confirmed swing" means no returned swing has `bar_shift < right`.

Add to `TestRunner.mq5`:

```mq5
#include "Tests/SwingDetectorTests.mqh"
```

```mq5
   RunSwingDetectorTests();
```

- [ ] **Step 2: Deploy, compile, confirm it fails to compile** (missing `SwingDetector.mqh`)

- [ ] **Step 3: Implement `SwingDetector.mqh`**

```mq5
//+------------------------------------------------------------------+
//|                                                  SwingDetector.mqh |
//|  Fractal de N_left/N_right con alternancia forzada y filtro de    |
//|  pierna minima en ATR. Ver docs/superpowers/specs/               |
//|  2026-08-06-4points-continuation-design.md §1.                   |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_SWINGDETECTOR_MQH
#define FOURPOINTS_SWINGDETECTOR_MQH

#include <4points/Types.mqh>
#include <4points/AtrUtils.mqh>

class CSwingDetector
  {
private:
   int    m_left;
   int    m_right;
   double m_min_leg_atr;
   int    m_atr_period;

public:
   CSwingDetector(const int left, const int right, const double min_leg_atr, const int atr_period)
     {
      m_left        = left;
      m_right       = right;
      m_min_leg_atr = min_leg_atr;
      m_atr_period  = atr_period;
     }

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed, SSwing &swings[])
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, swings);
     }

   //+---------------------------------------------------------------+
   //| rates en orden de serie (indice 0 = mas reciente). Devuelve    |
   //| swings en orden cronologico ascendente (indice 0 = mas         |
   //| antiguo confirmado); swings[i].bar_shift referencia el indice  |
   //| en el rates[] recibido.                                       |
   //+---------------------------------------------------------------+
   bool Evaluate(const MqlRates &rates[], SSwing &swings[])
     {
      ArrayResize(swings, 0);
      int size = ArraySize(rates);
      if(size < m_left + m_right + 1)
         return true; // no hay suficientes velas para ningun swing, no es un error

      ESwingType last_type = SWING_NONE;

      // Recorre de mas antiguo a mas reciente: k empieza en el indice mas alto
      // valido (size-1-m_left) y desciende hasta m_right.
      for(int k = size - 1 - m_left; k >= m_right; k--)
        {
         bool is_high = true;
         bool is_low  = true;
         for(int j = 1; j <= m_left; j++)
           {
            if(rates[k].high <= rates[k + j].high) is_high = false;
            if(rates[k].low  >= rates[k + j].low)  is_low  = false;
           }
         for(int j = 1; j <= m_right; j++)
           {
            if(rates[k].high <= rates[k - j].high) is_high = false;
            if(rates[k].low  >= rates[k - j].low)  is_low  = false;
           }

         if(!is_high && !is_low)
            continue;

         // Si una vela cumple ambas condiciones a la vez (raro), se prioriza HIGH
         // de forma deterministica; ningun caso de test de la Fase 1 depende de esto.
         SSwing candidate;
         candidate.type      = is_high ? SWING_HIGH : SWING_LOW;
         candidate.bar_shift = k;
         candidate.time      = rates[k].time;
         candidate.price     = is_high ? rates[k].high : rates[k].low;

         AppendSwing(swings, candidate, last_type, rates);
        }

      return true;
     }

private:
   void AppendSwing(SSwing &swings[], const SSwing &candidate, ESwingType &last_type, const MqlRates &rates[])
     {
      int count = ArraySize(swings);

      if(count == 0)
        {
         ArrayResize(swings, 1);
         swings[0] = candidate;
         last_type = candidate.type;
         return;
        }

      SSwing last = swings[count - 1];

      if(candidate.type == last.type)
        {
         // Duplicado consecutivo: se conserva el mas extremo, no se abre pierna nueva.
         bool more_extreme = (candidate.type == SWING_HIGH) ? (candidate.price > last.price)
                                                              : (candidate.price < last.price);
         if(more_extreme)
            swings[count - 1] = candidate;
         return;
        }

      // Alterna correctamente: aplica el filtro de pierna minima contra el swing anterior.
      double leg = MathAbs(candidate.price - last.price);
      double atr = SimpleATR(rates, m_atr_period, candidate.bar_shift);
      if(atr > 0.0 && leg < m_min_leg_atr * atr)
         return; // pierna insuficiente: se descarta, no se actualiza last_type

      ArrayResize(swings, count + 1);
      swings[count] = candidate;
      last_type = candidate.type;
     }
  };

#endif // FOURPOINTS_SWINGDETECTOR_MQH
```

- [ ] **Step 4: Deploy, compile, confirm 0 errors, run, confirm all `SwingDetector:` cases PASS**

- [ ] **Step 5: Commit**

```bash
git add MQL5/Include/4points/SwingDetector.mqh MQL5/Scripts/4points/Tests/SwingDetectorTests.mqh MQL5/Scripts/4points/TestRunner.mq5
git commit -m "feat(4points): add fractal swing detector"
```

---

### Task 4: `StructureState.mqh` — `CStructureState`

**Files:**
- Create: `MQL5/Include/4points/StructureState.mqh`
- Create: `MQL5/Scripts/4points/Tests/StructureStateTests.mqh`
- Modify: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Consumes: `CSwingDetector` and `SSwing` (Task 3).
- Produces: class `CStructureState` with constructor `CStructureState(const int left, const int right, const double min_leg_atr, const int atr_period)` and `bool Evaluate(const MqlRates &rates[], ETrendState &state)`. Used by `TrendFilter` (Task 5).

- [ ] **Step 1: Write the failing tests**

Create `MQL5/Scripts/4points/Tests/StructureStateTests.mqh`:

```mq5
#ifndef FOURPOINTS_STRUCTURESTATETESTS_MQH
#define FOURPOINTS_STRUCTURESTATETESTS_MQH

#include <4points/StructureState.mqh>

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
   c3[6] = 115.0;  // BOS alcista -> BULL
   l3[8] = 85.0;   // swing low tras el BOS (confirmado con vecinos 6,7,9,10)
   c3[13] = 80.0;  // cierre por debajo del swing low -> BOS bajista
   MqlRates rates3[];
   BuildRatesSeries(t3, o3, h3, l3, c3, rates3);
   ETrendState s3;
   state_det.Evaluate(rates3, s3);
   Assert(s3 == TREND_BEAR, "StructureState: BULL -> BEAR tras cierre bajo el ultimo swing low");
  }

#endif // FOURPOINTS_STRUCTURESTATETESTS_MQH
```

Add to `TestRunner.mq5`:

```mq5
#include "Tests/StructureStateTests.mqh"
```

```mq5
   RunStructureStateTests();
```

- [ ] **Step 2: Deploy, compile, confirm it fails to compile**

- [ ] **Step 3: Implement `StructureState.mqh`**

```mq5
//+------------------------------------------------------------------+
//|                                                 StructureState.mqh |
//|  Maquina BOS por timeframe: BULL si el cierre supera al ultimo    |
//|  swing high confirmado, BEAR si cae bajo el ultimo swing low.     |
//|  Ver docs/superpowers/specs/2026-08-06-4points-continuation-      |
//|  design.md §2.                                                    |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_STRUCTURESTATE_MQH
#define FOURPOINTS_STRUCTURESTATE_MQH

#include <4points/Types.mqh>
#include <4points/SwingDetector.mqh>

class CStructureState
  {
private:
   CSwingDetector m_swings;

public:
   CStructureState(const int left, const int right, const double min_leg_atr, const int atr_period)
     : m_swings(left, right, min_leg_atr, atr_period) {}

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed, ETrendState &state)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, state);
     }

   //+---------------------------------------------------------------+
   //| Devuelve el estado final (el vigente en rates[0], la vela mas  |
   //| reciente), simulando hacia adelante desde la vela mas antigua. |
   //| Simplificacion deliberada de la Fase 1: un swing "activa" su   |
   //| nivel en su propia barra, no N_right barras despues; para el   |
   //| estado final de un analisis estatico esto no cambia el         |
   //| resultado y evita duplicar aqui la logica de streaming.        |
   //+---------------------------------------------------------------+
   bool Evaluate(const MqlRates &rates[], ETrendState &state)
     {
      state = TREND_NEUTRAL;

      SSwing swings[];
      if(!m_swings.Evaluate(rates, swings))
         return false;

      int size = ArraySize(rates);
      if(size == 0)
         return true;

      double last_high = 0.0;
      double last_low  = 0.0;
      bool   have_high = false;
      bool   have_low  = false;
      int    next_swing = 0; // recorre swings[] en su orden cronologico ascendente

      for(int k = size - 1; k >= 0; k--)
        {
         while(next_swing < ArraySize(swings) && swings[next_swing].bar_shift >= k)
           {
            if(swings[next_swing].type == SWING_HIGH) { last_high = swings[next_swing].price; have_high = true; }
            if(swings[next_swing].type == SWING_LOW)  { last_low  = swings[next_swing].price; have_low  = true; }
            next_swing++;
           }

         if(have_high && rates[k].close > last_high)
            state = TREND_BULL;
         else if(have_low && rates[k].close < last_low)
            state = TREND_BEAR;
        }

      return true;
     }
  };

#endif // FOURPOINTS_STRUCTURESTATE_MQH
```

- [ ] **Step 4: Deploy, compile, confirm 0 errors, run, confirm all `StructureState:` cases PASS**

- [ ] **Step 5: Commit**

```bash
git add MQL5/Include/4points/StructureState.mqh MQL5/Scripts/4points/Tests/StructureStateTests.mqh MQL5/Scripts/4points/TestRunner.mq5
git commit -m "feat(4points): add bos structure state machine"
```

---

### Task 5: `TrendFilter.mqh` — `CTrendFilter`

**Files:**
- Create: `MQL5/Include/4points/TrendFilter.mqh`
- Create: `MQL5/Scripts/4points/Tests/TrendFilterTests.mqh`
- Modify: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Consumes: `CStructureState` (Task 4); `ETrendState`, `EDirection`, `DirectionFromTrend()` (`Types.mqh`, existing).
- Produces: class `CTrendFilter` with constructor `CTrendFilter(const int left, const int right, const double min_leg_atr, const int atr_period)` and `EDirection Evaluate(const ETrendState state_high, const ETrendState state_mid, const ETrendState state_low)`. Used by `PatternDetector` callers (the indicator/EA in Fase 2, not by `PatternDetector` itself — `PatternDetector` takes a resolved `EDirection`, it does not call `CTrendFilter`).

**Design note:** unlike the other detectors, `CTrendFilter.Evaluate` does not take a `MqlRates[]` — it combines three already-computed `ETrendState` values. Its natural unit of input is "the state of each timeframe", not a single candle series, so forcing it through the generic `Evaluate(rates[])` shape would mean building three synthetic HTF series per test case for no benefit. `Load()` still does the three `CopyRates`/`CStructureState.Load()` calls and is what the indicator/EA will use.

- [ ] **Step 1: Write the failing tests**

Create `MQL5/Scripts/4points/Tests/TrendFilterTests.mqh`:

```mq5
#ifndef FOURPOINTS_TRENDFILTERTESTS_MQH
#define FOURPOINTS_TRENDFILTERTESTS_MQH

#include <4points/TrendFilter.mqh>

void RunTrendFilterTests()
  {
   CTrendFilter filter(2, 2, 0.0, 14);

   Assert(filter.Evaluate(TREND_BULL, TREND_BULL, TREND_BULL) == DIR_BUY,
          "TrendFilter: H4=H1=M15=BULL da DIR_BUY");
   Assert(filter.Evaluate(TREND_BEAR, TREND_BEAR, TREND_BEAR) == DIR_SELL,
          "TrendFilter: H4=H1=M15=BEAR da DIR_SELL");
   Assert(filter.Evaluate(TREND_BULL, TREND_BULL, TREND_NEUTRAL) == DIR_NONE,
          "TrendFilter: un timeframe NEUTRAL da DIR_NONE");
   Assert(filter.Evaluate(TREND_BULL, TREND_BEAR, TREND_BULL) == DIR_NONE,
          "TrendFilter: timeframes en direcciones opuestas da DIR_NONE");
  }

#endif // FOURPOINTS_TRENDFILTERTESTS_MQH
```

Add to `TestRunner.mq5`:

```mq5
#include "Tests/TrendFilterTests.mqh"
```

```mq5
   RunTrendFilterTests();
```

- [ ] **Step 2: Deploy, compile, confirm it fails to compile**

- [ ] **Step 3: Implement `TrendFilter.mqh`**

```mq5
//+------------------------------------------------------------------+
//|                                                    TrendFilter.mqh |
//|  Alineacion H4/H1/M15: direccion operable solo si los tres        |
//|  coinciden y ninguno esta NEUTRAL. Ver docs/superpowers/specs/    |
//|  2026-08-06-4points-continuation-design.md §2.                    |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_TRENDFILTER_MQH
#define FOURPOINTS_TRENDFILTER_MQH

#include <4points/Types.mqh>
#include <4points/StructureState.mqh>

class CTrendFilter
  {
private:
   CStructureState m_high;
   CStructureState m_mid;
   CStructureState m_low;

public:
   CTrendFilter(const int left, const int right, const double min_leg_atr, const int atr_period)
     : m_high(left, right, min_leg_atr, atr_period),
       m_mid(left, right, min_leg_atr, atr_period),
       m_low(left, right, min_leg_atr, atr_period) {}

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf_high, const ENUM_TIMEFRAMES tf_mid,
             const ENUM_TIMEFRAMES tf_low, const int bars_needed,
             ETrendState &state_high, ETrendState &state_mid, ETrendState &state_low, EDirection &direction)
     {
      if(!m_high.Load(symbol, tf_high, bars_needed, state_high)) return false;
      if(!m_mid.Load(symbol, tf_mid, bars_needed, state_mid))   return false;
      if(!m_low.Load(symbol, tf_low, bars_needed, state_low))   return false;
      direction = Evaluate(state_high, state_mid, state_low);
      return true;
     }

   EDirection Evaluate(const ETrendState state_high, const ETrendState state_mid, const ETrendState state_low)
     {
      if(state_high == TREND_NEUTRAL || state_mid == TREND_NEUTRAL || state_low == TREND_NEUTRAL)
         return DIR_NONE;
      if(state_high != state_mid || state_mid != state_low)
         return DIR_NONE;
      return DirectionFromTrend(state_high);
     }
  };

#endif // FOURPOINTS_TRENDFILTER_MQH
```

- [ ] **Step 4: Deploy, compile, confirm 0 errors, run, confirm all `TrendFilter:` cases PASS**

- [ ] **Step 5: Commit**

```bash
git add MQL5/Include/4points/TrendFilter.mqh MQL5/Scripts/4points/Tests/TrendFilterTests.mqh MQL5/Scripts/4points/TestRunner.mq5
git commit -m "feat(4points): add h4/h1/m15 trend alignment filter"
```

---

### Task 6: `PatternDetector.mqh` — `CPatternDetector`

**Files:**
- Create: `MQL5/Include/4points/PatternDetector.mqh`
- Create: `MQL5/Scripts/4points/Tests/PatternDetectorTests.mqh`
- Modify: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Consumes: `CSwingDetector`, `SSwing` (Task 3); `SimpleATR()` (Task 2); `SPatternPoints`, `EPatternStage`, `EDirection` (`Types.mqh`, existing).
- Produces: class `CPatternDetector` with constructor `CPatternDetector(const int left, const int right, const double min_leg_atr, const int atr_period, const double min_impulse_atr, const double min_retrace, const double max_retrace)` and `bool Evaluate(const MqlRates &rates[], const EDirection direction, SPatternPoints &points, EPatternStage &stage)`. `stage` is one of `STAGE_IDLE`, `STAGE_P1`, `STAGE_P2`, `STAGE_P3`, `STAGE_P4` on return (never `STAGE_SWEPT`/`STAGE_TRIGGERED` — those are set by `LiquiditySweep`/`BreakoutValidator`, not here). Used by `LiquiditySweep` (Task 7).

**Scope boundary:** `PatternDetector` finds the most recent P1→P2→P3→P4 sequence in the swing list. It does **not** check the `max_bars_to_complete` timeout or the "close below P1.low" live invalidation from the design spec — both require knowing "the current bar" in a streaming sense, which only the Fase 2 indicator/EA loop has. That orchestration is out of scope for Fase 1; it is noted here so it isn't mistaken for a missed requirement.

- [ ] **Step 1: Write the failing tests**

Create `MQL5/Scripts/4points/Tests/PatternDetectorTests.mqh`:

```mq5
#ifndef FOURPOINTS_PATTERNDETECTORTESTS_MQH
#define FOURPOINTS_PATTERNDETECTORTESTS_MQH

#include <4points/PatternDetector.mqh>

// Construye una serie de 20 velas planas (high=100, low=95) y aplica los
// picos/valles indicados en (indice, high, low) para formar swings a medida.
// idx, hval, lval en paralelo; usar 0.0 para "no tocar" ese lado en esa vela.
void BuildPatternScenario(const int &idx[], const double &hval[], const double &lval[], const int count,
                           MqlRates &out[])
  {
   int n = 20;
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   for(int i = 0; i < n; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60;
      h[i] = 100.0; l[i] = 95.0; o[i] = 97.5; c[i] = 97.5;
     }
   for(int i = 0; i < count; i++)
     {
      if(hval[i] != 0.0) h[idx[i]] = hval[i];
      if(lval[i] != 0.0) l[idx[i]] = lval[i];
     }
   BuildRatesSeries(t, o, h, l, c, out);
  }

void RunPatternDetectorTests()
  {
   CPatternDetector det(2, 2, 0.0, 14, 1.0, 0.20, 0.80);

   // --- Caso 1: secuencia completa P1(low)->P2(high)->P3(higher low, retroceso 50%)->P4(higher high).
   int    idx1[]  = {3, 7, 11, 15};
   double hval1[] = {0.0, 120.0, 0.0, 125.0};
   double lval1[] = {90.0, 0.0, 105.0, 0.0}; // P3 = 105, retroceso de (120-90)=30 es (120-105)/30=0.5
   MqlRates rates1[];
   BuildPatternScenario(idx1, hval1, lval1, 4, rates1);

   SPatternPoints points1; EPatternStage stage1;
   det.Evaluate(rates1, DIR_BUY, points1, stage1);
   Assert(stage1 == STAGE_P4, "PatternDetector: secuencia completa llega a STAGE_P4");
   if(stage1 == STAGE_P4)
     {
      Assert(MathAbs(points1.p1.price - 90.0) < 0.0001, "PatternDetector: P1 = 90 (low de indice 3)");
      Assert(MathAbs(points1.p2.price - 120.0) < 0.0001, "PatternDetector: P2 = 120 (high de indice 7)");
      Assert(MathAbs(points1.p3.price - 105.0) < 0.0001, "PatternDetector: P3 = 105 (low de indice 11)");
      Assert(MathAbs(points1.p4.price - 125.0) < 0.0001, "PatternDetector: P4 = 125 (high de indice 15)");
     }

   // --- Caso 2: sin P4 -> P2 nunca es superado, se queda en STAGE_P3.
   int    idx2[]  = {3, 7, 11};
   double hval2[] = {0.0, 120.0, 0.0};
   double lval2[] = {90.0, 0.0, 105.0};
   MqlRates rates2[];
   BuildPatternScenario(idx2, hval2, lval2, 3, rates2);
   SPatternPoints points2; EPatternStage stage2;
   det.Evaluate(rates2, DIR_BUY, points2, stage2);
   Assert(stage2 == STAGE_P3, "PatternDetector: sin P4 se queda en STAGE_P3");

   // --- Caso 3: retroceso demasiado profundo (>80%) -> ese candidato a P3 se descarta.
   int    idx3[]  = {3, 7, 11};
   double hval3[] = {0.0, 120.0, 0.0};
   double lval3[] = {90.0, 0.0, 92.0}; // retroceso = (120-92)/(120-90) = 0.933, fuera de [0.2, 0.8]
   MqlRates rates3[];
   BuildPatternScenario(idx3, hval3, lval3, 3, rates3);
   SPatternPoints points3; EPatternStage stage3;
   det.Evaluate(rates3, DIR_BUY, points3, stage3);
   Assert(stage3 == STAGE_P2, "PatternDetector: retroceso fuera de rango no confirma P3");

   // --- Caso 4: retroceso demasiado superficial (<20%).
   int    idx4[]  = {3, 7, 11};
   double hval4[] = {0.0, 120.0, 0.0};
   double lval4[] = {90.0, 0.0, 118.0}; // retroceso = (120-118)/30 = 0.067
   MqlRates rates4[];
   BuildPatternScenario(idx4, hval4, lval4, 3, rates4);
   SPatternPoints points4; EPatternStage stage4;
   det.Evaluate(rates4, DIR_BUY, points4, stage4);
   Assert(stage4 == STAGE_P2, "PatternDetector: retroceso demasiado superficial no confirma P3");

   // --- Caso 5: impulso P1->P2 demasiado pequeno frente a min_impulse_atr -> nunca llega a P2.
   CPatternDetector det_strict(2, 2, 0.0, 14, 50.0, 0.20, 0.80); // exige impulso >= 50*ATR, imposible aqui
   SPatternPoints points5; EPatternStage stage5;
   det_strict.Evaluate(rates1, DIR_BUY, points5, stage5);
   Assert(stage5 == STAGE_P1, "PatternDetector: impulso insuficiente nunca confirma P2");

   // --- Caso 6: direccion SELL es el espejo (P1=high, P2=low, P3=lower high, P4=lower low).
   int    idx6[]  = {3, 7, 11, 15};
   double hval6[] = {110.0, 0.0, 95.0, 0.0};
   double lval6[] = {0.0, 80.0, 0.0, 75.0}; // P2=80, P1=110, P3=95 -> retroceso=(95-80)/(110-80)=0.5
   MqlRates rates6[];
   BuildPatternScenario(idx6, hval6, lval6, 4, rates6);
   SPatternPoints points6; EPatternStage stage6;
   det.Evaluate(rates6, DIR_SELL, points6, stage6);
   Assert(stage6 == STAGE_P4, "PatternDetector: secuencia SELL (espejo) llega a STAGE_P4");
  }

#endif // FOURPOINTS_PATTERNDETECTORTESTS_MQH
```

Add to `TestRunner.mq5`:

```mq5
#include "Tests/PatternDetectorTests.mqh"
```

```mq5
   RunPatternDetectorTests();
```

- [ ] **Step 2: Deploy, compile, confirm it fails to compile**

- [ ] **Step 3: Implement `PatternDetector.mqh`**

```mq5
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

      for(int i = 0; i < ArraySize(swings); i++)
        {
         SSwing s = swings[i];

         if(stage == STAGE_IDLE)
           {
            if(s.type == origin_type)
              {
               points.p1 = s;
               stage = STAGE_P1;
              }
            continue;
           }

         if(stage == STAGE_P1)
           {
            if(s.type == origin_type)
              {
               bool more_extreme = (direction == DIR_BUY) ? (s.price < points.p1.price) : (s.price > points.p1.price);
               if(more_extreme)
                  points.p1 = s;
               continue;
              }
            double leg = MathAbs(s.price - points.p1.price);
            double atr = SimpleATR(rates, m_atr_period, s.bar_shift);
            if(atr > 0.0 && leg >= m_min_impulse_atr * atr)
              {
               points.p2 = s;
               stage = STAGE_P2;
              }
            continue;
           }

         if(stage == STAGE_P2)
           {
            if(s.type == impulse_type)
              {
               bool more_extreme = (direction == DIR_BUY) ? (s.price > points.p2.price) : (s.price < points.p2.price);
               if(more_extreme)
                  points.p2 = s;
               continue;
              }
            bool higher_low_ok = (direction == DIR_BUY) ? (s.price > points.p1.price) : (s.price < points.p1.price);
            if(!higher_low_ok)
              {
               SSwing new_origin = s;
               points.Reset();
               points.p1 = new_origin;
               stage = STAGE_P1;
               continue;
              }
            double leg_p1_p2 = MathAbs(points.p2.price - points.p1.price);
            double retrace = (leg_p1_p2 > 0.0) ? MathAbs(points.p2.price - s.price) / leg_p1_p2 : 0.0;
            if(retrace >= m_min_retrace && retrace <= m_max_retrace)
              {
               points.p3 = s;
               stage = STAGE_P3;
              }
            continue;
           }

         if(stage == STAGE_P3)
           {
            if(s.type == origin_type)
              {
               bool higher_low_ok = (direction == DIR_BUY) ? (s.price > points.p1.price) : (s.price < points.p1.price);
               if(!higher_low_ok)
                 {
                  SSwing new_origin = s;
                  points.Reset();
                  points.p1 = new_origin;
                  stage = STAGE_P1;
                  continue;
                 }
               points.p3 = s;
               continue;
              }
            bool higher_high_ok = (direction == DIR_BUY) ? (s.price > points.p2.price) : (s.price < points.p2.price);
            if(higher_high_ok)
              {
               points.p4 = s;
               stage = STAGE_P4;
              }
            continue;
           }

         if(stage == STAGE_P4)
            break;
        }

      return true;
     }
  };

#endif // FOURPOINTS_PATTERNDETECTOR_MQH
```

- [ ] **Step 4: Deploy, compile, confirm 0 errors, run, confirm all `PatternDetector:` cases PASS**

- [ ] **Step 5: Commit**

```bash
git add MQL5/Include/4points/PatternDetector.mqh MQL5/Scripts/4points/Tests/PatternDetectorTests.mqh MQL5/Scripts/4points/TestRunner.mq5
git commit -m "feat(4points): add 4-point pattern state machine"
```

---

### Task 7: `LiquiditySweep.mqh` — `CLiquiditySweep`

**Files:**
- Create: `MQL5/Include/4points/LiquiditySweep.mqh`
- Create: `MQL5/Scripts/4points/Tests/LiquiditySweepTests.mqh`
- Modify: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Consumes: `SimpleATR()` (Task 2); `SPatternPoints`, `ESweepMode`, `EDirection` (`Types.mqh`, existing). Expects `points.p1`/`p3`/`p4` already filled (by `PatternDetector`, Task 6).
- Produces: class `CLiquiditySweep` with constructor `CLiquiditySweep(const ESweepMode mode, const double eq_tol_atr, const int atr_period, const int max_sweep_bars)` and `bool Evaluate(const MqlRates &rates[], const EDirection direction, SPatternPoints &points, bool &swept)`. Fills `points.sweep_price`, `points.sweep_time`, `points.sweep_kind` when `swept == true`. Used by `BreakoutValidator` callers in Fase 2 (not consumed by another Fase 1 detector).

**Design note — `SWEEP_INTERNAL` is an interpretation, flag for review:** the Fase 0 spec describes `SWEEP_INTERNAL` in one sentence ("barre el cluster de minimos menores o iguales formado tras P4, con tolerancia de igualdad `eq_tol_atr · ATR`") without fully pinning down the mechanics. This task implements it as: track the running lowest low (BUY case) since P4 that still stays at or above `P3.low`, and treat a later close back above that running low as the recovery. This is a reasonable, testable reading, but it is the one piece of Fase 1 most likely to need revisiting once Fase 3's real data lets us compare `SWEEP_BREACH_P3` vs `SWEEP_INTERNAL` — which is exactly what `ESweepMode` in `Types.mqh` says the two modes are for ("hipotesis competidoras... Se comparan con datos en Fase 3"). Flag this to the project owner when Fase 1 is reviewed.

- [ ] **Step 1: Write the failing tests**

Create `MQL5/Scripts/4points/Tests/LiquiditySweepTests.mqh`:

```mq5
#ifndef FOURPOINTS_LIQUIDITYSWEEPTESTS_MQH
#define FOURPOINTS_LIQUIDITYSWEEPTESTS_MQH

#include <4points/LiquiditySweep.mqh>

// P4 queda en el indice de rates[] correspondiente a bar_shift; el resto de
// velas hasta el indice 0 son las que LiquiditySweep explora en busca del barrido.
SPatternPoints BuildPointsForSweep(const int p4_shift, const double p1_price, const double p3_price)
  {
   SPatternPoints points;
   points.p1.type = SWING_LOW; points.p1.price = p1_price;
   points.p3.type = SWING_LOW; points.p3.price = p3_price;
   points.p4.type = SWING_HIGH; points.p4.bar_shift = p4_shift;
   return points;
  }

void RunLiquiditySweepTests()
  {
   int n = 8; // rates[0]=mas reciente .. rates[7]=mas antigua; P4 esta en rates[5]
   datetime t[]; double o[], h[], l[], c[];
   ArrayResize(t, n); ArrayResize(o, n); ArrayResize(h, n); ArrayResize(l, n); ArrayResize(c, n);
   for(int i = 0; i < n; i++)
     {
      t[i] = D'2026.01.01 00:00' + i * 60; h[i] = 100.0; l[i] = 95.0; o[i] = 97.5; c[i] = 97.5;
     }

   // --- Caso 1: SWEEP_BREACH_P3 valido. P1=80, P3=90. Perfora P3 en rates[3] (low=88,
   // > P1) y se recupera en rates[2] (close=91 > P3).
   MqlRates ratesA[];
   { datetime tA[]; double oA[], hA[], lA[], cA[];
     ArrayResize(tA,n); ArrayResize(oA,n); ArrayResize(hA,n); ArrayResize(lA,n); ArrayResize(cA,n);
     for(int i=0;i<n;i++){ tA[i]=t[i]; hA[i]=h[i]; lA[i]=l[i]; oA[i]=o[i]; cA[i]=c[i]; }
     lA[3]=88.0; cA[2]=91.0; // en input cronologico (indice 0=mas antiguo)
     BuildRatesSeries(tA, oA, hA, lA, cA, ratesA); }
   SPatternPoints pointsA = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepA(SWEEP_BREACH_P3, 0.10, 14, 5);
   bool sweptA;
   sweepA.Evaluate(ratesA, DIR_BUY, pointsA, sweptA);
   Assert(sweptA, "LiquiditySweep: BREACH_P3 valido detecta el barrido");
   if(sweptA)
      Assert(pointsA.sweep_kind == SWEEP_BREACH_P3, "LiquiditySweep: modo detectado es BREACH_P3");

   // --- Caso 2: perforacion sin recuperacion dentro de max_sweep_bars -> no es sweep.
   MqlRates ratesB[];
   { datetime tB[]; double oB[], hB[], lB[], cB[];
     ArrayResize(tB,n); ArrayResize(oB,n); ArrayResize(hB,n); ArrayResize(lB,n); ArrayResize(cB,n);
     for(int i=0;i<n;i++){ tB[i]=t[i]; hB[i]=h[i]; lB[i]=l[i]; oB[i]=o[i]; cB[i]=c[i]; }
     lB[3]=88.0; // perfora P3 pero ningun cierre posterior vuelve a superar 90
     BuildRatesSeries(tB, oB, hB, lB, cB, ratesB); }
   SPatternPoints pointsB = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepB(SWEEP_BREACH_P3, 0.10, 14, 5);
   bool sweptB;
   sweepB.Evaluate(ratesB, DIR_BUY, pointsB, sweptB);
   Assert(!sweptB, "LiquiditySweep: perforacion sin recuperacion no es un barrido valido");

   // --- Caso 3: perforacion mas alla de P1 invalida el barrido.
   MqlRates ratesC[];
   { datetime tC[]; double oC[], hC[], lC[], cC[];
     ArrayResize(tC,n); ArrayResize(oC,n); ArrayResize(hC,n); ArrayResize(lC,n); ArrayResize(cC,n);
     for(int i=0;i<n;i++){ tC[i]=t[i]; hC[i]=h[i]; lC[i]=l[i]; oC[i]=o[i]; cC[i]=c[i]; }
     lC[3]=75.0; cC[2]=91.0; // perfora incluso por debajo de P1=80
     BuildRatesSeries(tC, oC, hC, lC, cC, ratesC); }
   SPatternPoints pointsC = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepC(SWEEP_BREACH_P3, 0.10, 14, 5);
   bool sweptC;
   sweepC.Evaluate(ratesC, DIR_BUY, pointsC, sweptC);
   Assert(!sweptC, "LiquiditySweep: perforar mas alla de P1 invalida el barrido");

   // --- Caso 4: SWEEP_INTERNAL valido (no perfora P3, solo forma un minimo interno y se recupera).
   MqlRates ratesD[];
   { datetime tD[]; double oD[], hD[], lD[], cD[];
     ArrayResize(tD,n); ArrayResize(oD,n); ArrayResize(hD,n); ArrayResize(lD,n); ArrayResize(cD,n);
     for(int i=0;i<n;i++){ tD[i]=t[i]; hD[i]=h[i]; lD[i]=l[i]; oD[i]=o[i]; cD[i]=c[i]; }
     lD[3]=92.0; cD[2]=93.0; // minimo interno en 92 (>= P3=90), luego cierre de vuelta por encima
     BuildRatesSeries(tD, oD, hD, lD, cD, ratesD); }
   SPatternPoints pointsD = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepD(SWEEP_INTERNAL, 0.10, 14, 5);
   bool sweptD;
   sweepD.Evaluate(ratesD, DIR_BUY, pointsD, sweptD);
   Assert(sweptD, "LiquiditySweep: INTERNAL valido detecta el barrido");
   if(sweptD)
      Assert(pointsD.sweep_kind == SWEEP_INTERNAL, "LiquiditySweep: modo detectado es INTERNAL");

   // --- Caso 5: SWEEP_ANY acepta un BREACH_P3 valido igual que el modo especifico.
   SPatternPoints pointsE = BuildPointsForSweep(5, 80.0, 90.0);
   CLiquiditySweep sweepE(SWEEP_ANY, 0.10, 14, 5);
   bool sweptE;
   sweepE.Evaluate(ratesA, DIR_BUY, pointsE, sweptE);
   Assert(sweptE, "LiquiditySweep: SWEEP_ANY acepta un BREACH_P3 valido");
  }

#endif // FOURPOINTS_LIQUIDITYSWEEPTESTS_MQH
```

Add to `TestRunner.mq5`:

```mq5
#include "Tests/LiquiditySweepTests.mqh"
```

```mq5
   RunLiquiditySweepTests();
```

- [ ] **Step 2: Deploy, compile, confirm it fails to compile**

- [ ] **Step 3: Implement `LiquiditySweep.mqh`**

```mq5
//+------------------------------------------------------------------+
//|                                                 LiquiditySweep.mqh |
//|  Barrido de liquidez tras P4: BREACH_P3 e INTERNAL. Ver           |
//|  docs/superpowers/specs/2026-08-06-4points-continuation-          |
//|  design.md §3 y la nota de diseno del plan de la Fase 1 sobre     |
//|  la interpretacion de INTERNAL.                                   |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_LIQUIDITYSWEEP_MQH
#define FOURPOINTS_LIQUIDITYSWEEP_MQH

#include <4points/Types.mqh>
#include <4points/AtrUtils.mqh>

class CLiquiditySweep
  {
private:
   ESweepMode m_mode;
   double     m_eq_tol_atr;
   int        m_atr_period;
   int        m_max_sweep_bars;

public:
   CLiquiditySweep(const ESweepMode mode, const double eq_tol_atr, const int atr_period, const int max_sweep_bars)
     {
      m_mode           = mode;
      m_eq_tol_atr     = eq_tol_atr;
      m_atr_period     = atr_period;
      m_max_sweep_bars = max_sweep_bars;
     }

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed,
             const EDirection direction, SPatternPoints &points, bool &swept)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, direction, points, swept);
     }

   bool Evaluate(const MqlRates &rates[], const EDirection direction, SPatternPoints &points, bool &swept)
     {
      swept = false;
      if(!points.p4.IsValid())
         return true;

      int search_start = points.p4.bar_shift - 1;
      if(search_start < 0)
         return true;

      if(m_mode == SWEEP_BREACH_P3 || m_mode == SWEEP_ANY)
        {
         if(TryBreach(rates, direction, points.p1.price, points.p3.price, search_start, points))
           {
            points.sweep_kind = SWEEP_BREACH_P3;
            swept = true;
            return true;
           }
        }

      if(m_mode == SWEEP_INTERNAL || m_mode == SWEEP_ANY)
        {
         if(TryInternal(rates, direction, points.p3.price, search_start, points))
           {
            points.sweep_kind = SWEEP_INTERNAL;
            swept = true;
            return true;
           }
        }

      return true;
     }

private:
   bool TryBreach(const MqlRates &rates[], const EDirection direction, const double p1_price,
                   const double p3_level, const int search_start, SPatternPoints &points)
     {
      for(int i = search_start; i >= 0 && (search_start - i) < m_max_sweep_bars; i--)
        {
         bool breaches = (direction == DIR_BUY) ? (rates[i].low < p3_level) : (rates[i].high > p3_level);
         if(!breaches)
            continue;

         bool beyond_origin = (direction == DIR_BUY) ? (rates[i].low <= p1_price) : (rates[i].high >= p1_price);
         if(beyond_origin)
            return false;

         double extreme = (direction == DIR_BUY) ? rates[i].low : rates[i].high;

         for(int j = i; j >= 0 && (i - j) <= m_max_sweep_bars; j--)
           {
            bool recovered = (direction == DIR_BUY) ? (rates[j].close > p3_level) : (rates[j].close < p3_level);
            if(recovered)
              {
               points.sweep_price = extreme;
               points.sweep_time  = rates[i].time;
               return true;
              }
           }
         return false;
        }
      return false;
     }

   bool TryInternal(const MqlRates &rates[], const EDirection direction, const double p3_level,
                     const int search_start, SPatternPoints &points)
     {
      double cluster_extreme = (direction == DIR_BUY) ? 999999999.0 : -999999999.0;
      int    cluster_shift   = -1;

      for(int i = search_start; i >= 0 && (search_start - i) < m_max_sweep_bars; i--)
        {
         double candidate = (direction == DIR_BUY) ? rates[i].low : rates[i].high;
         bool beyond_p3 = (direction == DIR_BUY) ? (candidate < p3_level) : (candidate > p3_level);
         if(beyond_p3)
            break; // eso ya es un BREACH_P3, no liquidez interna

         double atr = SimpleATR(rates, m_atr_period, i);
         double tol = (atr > 0.0) ? m_eq_tol_atr * atr : 0.0;
         bool more_extreme = (direction == DIR_BUY) ? (candidate < cluster_extreme - tol)
                                                      : (candidate > cluster_extreme + tol);
         if(cluster_shift < 0 || more_extreme)
           {
            cluster_extreme = candidate;
            cluster_shift   = i;
            continue; // esta misma vela establece el minimo, no puede recuperarlo en el mismo tick
           }

         bool recovered = (direction == DIR_BUY) ? (rates[i].close > cluster_extreme)
                                                    : (rates[i].close < cluster_extreme);
         if(recovered)
           {
            points.sweep_price = cluster_extreme;
            points.sweep_time  = rates[cluster_shift].time;
            return true;
           }
        }
      return false;
     }
  };

#endif // FOURPOINTS_LIQUIDITYSWEEP_MQH
```

- [ ] **Step 4: Deploy, compile, confirm 0 errors, run, confirm all `LiquiditySweep:` cases PASS**

- [ ] **Step 5: Commit**

```bash
git add MQL5/Include/4points/LiquiditySweep.mqh MQL5/Scripts/4points/Tests/LiquiditySweepTests.mqh MQL5/Scripts/4points/TestRunner.mq5
git commit -m "feat(4points): add liquidity sweep detector"
```

---

### Task 8: `BreakoutValidator.mqh` — `CBreakoutValidator`

**Files:**
- Create: `MQL5/Include/4points/BreakoutValidator.mqh`
- Create: `MQL5/Scripts/4points/Tests/BreakoutValidatorTests.mqh`
- Modify: `MQL5/Scripts/4points/TestRunner.mq5`

**Interfaces:**
- Consumes: `SimpleATR()` (Task 2); `SBreakoutMetrics`, `EDirection` (`Types.mqh`, existing).
- Produces: class `CBreakoutValidator` with constructor `CBreakoutValidator(const double min_body_ratio, const double min_close_pos, const double min_body_atr, const double min_penetration_atr, const double min_penetration_spreads, const int atr_period)` and `bool Evaluate(const MqlRates &rates[], const EDirection direction, const double level, const double spread_price, SBreakoutMetrics &metrics, bool &passed)`. `rates[0]` is the candidate breakout candle; `spread_price` is already converted to price units (`spread_points * _Point`), not raw points, so this stays testable without `_Point`.

- [ ] **Step 1: Write the failing tests**

Create `MQL5/Scripts/4points/Tests/BreakoutValidatorTests.mqh`:

```mq5
#ifndef FOURPOINTS_BREAKOUTVALIDATORTESTS_MQH
#define FOURPOINTS_BREAKOUTVALIDATORTESTS_MQH

#include <4points/BreakoutValidator.mqh>

MqlRates BuildBreakoutCandle(const double open, const double high, const double low, const double close)
  {
   MqlRates r;
   r.time = D'2026.01.01 00:10';
   r.open = open; r.high = high; r.low = low; r.close = close;
   r.tick_volume = 1; r.spread = 0; r.real_volume = 0;
   return r;
  }

void BuildBreakoutHistory(const MqlRates &breakout_candle, MqlRates &out[])
  {
   // 15 velas de historia plana (TR=2.0 cada una, para ATR determinista) + la vela de breakout en el indice 0.
   int history = 15;
   ArrayResize(out, history + 1);
   out[0] = breakout_candle;
   for(int i = 1; i <= history; i++)
     {
      out[i].time  = D'2026.01.01 00:00' + (history - i) * 60;
      out[i].open  = 100.0; out[i].high = 101.0; out[i].low = 99.0; out[i].close = 100.0;
      out[i].tick_volume = 1; out[i].spread = 0; out[i].real_volume = 0;
     }
   ArraySetAsSeries(out, true);
  }

void RunBreakoutValidatorTests()
  {
   // level=100, spread_price=0.10, atr(14) sobre la historia plana = 2.0 (TR constante).
   CBreakoutValidator v(0.55, 0.70, 0.50, 0.10, 1.50, 14);

   // --- Caso 1: las 5 condiciones se cumplen.
   // body=1.6 (open 100 -> close 101.6), range=1.8 (high 101.7, low 99.9), close_pos=(101.6-99.9)/1.8=0.944,
   // body_atr=1.6/2.0=0.8, penetration=101.6-100=1.6, min_penetration=max(0.10*2.0, 1.50*0.10)=max(0.2,0.15)=0.2.
   MqlRates candleOK = BuildBreakoutCandle(100.0, 101.7, 99.9, 101.6);
   MqlRates ratesOK[];
   BuildBreakoutHistory(candleOK, ratesOK);
   SBreakoutMetrics metricsOK; bool passedOK;
   v.Evaluate(ratesOK, DIR_BUY, 100.0, 0.10, metricsOK, passedOK);
   Assert(passedOK, "BreakoutValidator: las 5 condiciones cumplidas dan passed=true");

   // --- Caso 2: cuerpo insuficiente (body_ratio bajo) aunque el resto pase.
   // open=100.5, close=101.0 (body=0.5), high=102.0, low=99.9 (range=2.1) -> body_ratio=0.238 < 0.55.
   MqlRates candleWeakBody = BuildBreakoutCandle(100.5, 102.0, 99.9, 101.0);
   MqlRates ratesWeakBody[];
   BuildBreakoutHistory(candleWeakBody, ratesWeakBody);
   SBreakoutMetrics metricsWeakBody; bool passedWeakBody;
   v.Evaluate(ratesWeakBody, DIR_BUY, 100.0, 0.10, metricsWeakBody, passedWeakBody);
   Assert(!passedWeakBody, "BreakoutValidator: body_ratio insuficiente rechaza el breakout");

   // --- Caso 3: breakout de mecha (close_pos bajo) - cierre lejos del maximo del rango.
   // open=100.0, close=100.3, high=102.0, low=99.9 -> range=2.1, close_pos=(100.3-99.9)/2.1=0.19 < 0.70.
   MqlRates candleWick = BuildBreakoutCandle(100.0, 102.0, 99.9, 100.3);
   MqlRates ratesWick[];
   BuildBreakoutHistory(candleWick, ratesWick);
   SBreakoutMetrics metricsWick; bool passedWick;
   v.Evaluate(ratesWick, DIR_BUY, 100.0, 0.10, metricsWick, passedWick);
   Assert(!passedWick, "BreakoutValidator: cierre en mecha (close_pos bajo) rechaza el breakout");

   // --- Caso 4: penetracion insuficiente del nivel.
   // open=100.0, close=100.05 (apenas rompe 100), high=100.2, low=99.9 -> range=0.3,
   // body=0.05 (body_ratio=0.167, ya insuficiente, pero se aisla penetracion con nivel muy cercano).
   // Para aislar solo la condicion 5, se sube el body/close_pos y se deja la penetracion corta:
   // open=99.0, close=100.05, high=100.1, low=98.9 -> body=1.05, range=1.2, body_ratio=0.875,
   // close_pos=(100.05-98.9)/1.2=0.958, body_atr=1.05/2.0=0.525 (>=0.50 ok), penetration=0.05,
   // min_penetration=max(0.10*2.0,1.50*0.10)=0.2 -> 0.05 < 0.2, falla solo la condicion 5.
   MqlRates candlePenetration = BuildBreakoutCandle(99.0, 100.1, 98.9, 100.05);
   MqlRates ratesPenetration[];
   BuildBreakoutHistory(candlePenetration, ratesPenetration);
   SBreakoutMetrics metricsPenetration; bool passedPenetration;
   v.Evaluate(ratesPenetration, DIR_BUY, 100.0, 0.10, metricsPenetration, passedPenetration);
   Assert(!passedPenetration, "BreakoutValidator: penetracion insuficiente del nivel rechaza el breakout");

   // --- Caso 5: no rompe el nivel (close <= level) -> rechazado por la condicion 1 sin importar el resto.
   MqlRates candleNoBreak = BuildBreakoutCandle(99.0, 100.1, 98.9, 99.9);
   MqlRates ratesNoBreak[];
   BuildBreakoutHistory(candleNoBreak, ratesNoBreak);
   SBreakoutMetrics metricsNoBreak; bool passedNoBreak;
   v.Evaluate(ratesNoBreak, DIR_BUY, 100.0, 0.10, metricsNoBreak, passedNoBreak);
   Assert(!passedNoBreak, "BreakoutValidator: cierre que no supera el nivel rechaza el breakout");
  }

#endif // FOURPOINTS_BREAKOUTVALIDATORTESTS_MQH
```

Add to `TestRunner.mq5`:

```mq5
#include "Tests/BreakoutValidatorTests.mqh"
```

```mq5
   RunBreakoutValidatorTests();
```

- [ ] **Step 2: Deploy, compile, confirm it fails to compile**

- [ ] **Step 3: Implement `BreakoutValidator.mqh`**

```mq5
//+------------------------------------------------------------------+
//|                                              BreakoutValidator.mqh |
//|  Las 5 condiciones de vela de breakout fuerte. Ver                |
//|  docs/superpowers/specs/2026-08-06-4points-continuation-          |
//|  design.md §4.                                                    |
//+------------------------------------------------------------------+
#ifndef FOURPOINTS_BREAKOUTVALIDATOR_MQH
#define FOURPOINTS_BREAKOUTVALIDATOR_MQH

#include <4points/Types.mqh>
#include <4points/AtrUtils.mqh>

class CBreakoutValidator
  {
private:
   double m_min_body_ratio;
   double m_min_close_pos;
   double m_min_body_atr;
   double m_min_penetration_atr;
   double m_min_penetration_spreads;
   int    m_atr_period;

public:
   CBreakoutValidator(const double min_body_ratio, const double min_close_pos, const double min_body_atr,
                       const double min_penetration_atr, const double min_penetration_spreads, const int atr_period)
     {
      m_min_body_ratio          = min_body_ratio;
      m_min_close_pos           = min_close_pos;
      m_min_body_atr            = min_body_atr;
      m_min_penetration_atr     = min_penetration_atr;
      m_min_penetration_spreads = min_penetration_spreads;
      m_atr_period              = atr_period;
     }

   bool Load(const string symbol, const ENUM_TIMEFRAMES tf, const int bars_needed,
             const EDirection direction, const double level, const double spread_price,
             SBreakoutMetrics &metrics, bool &passed)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, tf, 1, bars_needed, rates);
      if(copied <= 0)
         return false;
      return Evaluate(rates, direction, level, spread_price, metrics, passed);
     }

   //+---------------------------------------------------------------+
   //| rates[0] es la vela candidata a breakout. spread_price ya      |
   //| viene en precio (spread_points * _Point), no en puntos, para   |
   //| que esta funcion no dependa de _Point y sea testeable.         |
   //+---------------------------------------------------------------+
   bool Evaluate(const MqlRates &rates[], const EDirection direction, const double level,
                 const double spread_price, SBreakoutMetrics &metrics, bool &passed)
     {
      metrics.Reset();
      passed = false;
      if(ArraySize(rates) == 0)
         return false;

      MqlRates c = rates[0];
      double range = c.high - c.low;
      if(range <= 0.0)
         return true;

      double body = MathAbs(c.close - c.open);
      double atr  = SimpleATR(rates, m_atr_period, 1); // hasta la vela anterior, sin mirar la de breakout

      metrics.body_ratio = body / range;
      metrics.close_pos  = (direction == DIR_BUY) ? (c.close - c.low) / range : (c.high - c.close) / range;
      metrics.body_atr   = (atr > 0.0) ? body / atr : 0.0;

      double penetration = (direction == DIR_BUY) ? (c.close - level) : (level - c.close);
      metrics.penetration_atr     = (atr > 0.0) ? penetration / atr : 0.0;
      metrics.penetration_spreads = (spread_price > 0.0) ? penetration / spread_price : 0.0;

      bool cond_close     = (direction == DIR_BUY) ? (c.close > level) : (c.close < level);
      bool cond_body      = metrics.body_ratio >= m_min_body_ratio;
      bool cond_pos       = metrics.close_pos  >= m_min_close_pos;
      bool cond_body_atr  = (atr > 0.0) && (body >= m_min_body_atr * atr);
      double min_penetration = MathMax(m_min_penetration_atr * ((atr > 0.0) ? atr : 0.0),
                                        m_min_penetration_spreads * spread_price);
      bool cond_penetration = penetration >= min_penetration;

      passed = cond_close && cond_body && cond_pos && cond_body_atr && cond_penetration;
      return true;
     }
  };

#endif // FOURPOINTS_BREAKOUTVALIDATOR_MQH
```

- [ ] **Step 4: Deploy, compile, confirm 0 errors, run, confirm all `BreakoutValidator:` cases PASS**

- [ ] **Step 5: Commit**

```bash
git add MQL5/Include/4points/BreakoutValidator.mqh MQL5/Scripts/4points/Tests/BreakoutValidatorTests.mqh MQL5/Scripts/4points/TestRunner.mq5
git commit -m "feat(4points): add breakout candle validator"
```

---

### Task 9: Full suite verification and status update

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:** none — this task only verifies and updates docs, no new code.

- [ ] **Step 1: Full deploy, compile, run**

```bash
./deploy.sh
```

Compile `TestRunner.mq5` as before, read the log for 0 errors. Run `TestRunner` on a chart and read the full Experts log output.

Expected: every case prints `PASS`, and the final line is `X/X PASS` where `X` equals the total case count (0 `FAIL` lines). If any case fails, stop here and fix it — do not proceed to Step 2 with a non-100% suite, since 100% PASS is Fase 1's stated exit criterion.

- [ ] **Step 2: Update `README.md` status table**

Change the Fase 1 row:

```diff
-| 1 | Detectores + `TestRunner` con series sintéticas | pendiente |
+| 1 | Detectores + `TestRunner` con series sintéticas | ✅ |
```

And the summary line:

```diff
-**Fase 0 — completada.** Scaffolding, tipos y configuración.
+**Fase 1 — completada.** Detectores del núcleo con 100% de tests sintéticos en verde.
```

- [ ] **Step 3: Update `CLAUDE.md` "Estado actual"**

```diff
-Fase 0 completada (scaffolding, `Types.mqh`, `Config.mqh`, deploy). La siguiente es la **Fase 1**: escribir los detectores en `MQL5/Include/4points/` junto con `TestRunner.mq5`. No existe todavía ni el indicador validador ni el EA.
+Fase 1 completada: los seis detectores en `MQL5/Include/4points/` (`SwingDetector`, `StructureState`, `TrendFilter`, `PatternDetector`, `LiquiditySweep`, `BreakoutValidator`) más el `AtrUtils.mqh` compartido, con `TestRunner.mq5` en 100% PASS. La siguiente es la **Fase 2**: el indicador validador (`FourPoints_Validator.mq5`), que pinta los setups sobre histórico sin duplicar lógica de estos detectores. No existe todavía ni el indicador ni el EA.
```

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: mark fase 1 complete"
```

- [ ] **Step 5: Push and open a PR against upstream (ask first)**

Do not push or open the PR automatically — ask the user whether to push `feature/fase1-nucleo-tests` to their fork (`origin`) and whether they want a PR opened against `upstream` (the colleague's repo) or kept as a plain push to their own fork's `main`/branch.

---

## Self-Review Notes

- **Spec coverage:** all six detectors from the Fase 0 architecture table are covered (Tasks 3–8), plus the shared `AtrUtils.mqh` (Task 2) and the `TestHelpers.mqh`/`TestRunner.mq5` harness (Task 1). Every test case category listed in the Fase 0 spec and the Fase 1 design doc appears in at least one task: patrón perfecto (Task 6, caso 1), patrón sin P4 (Task 6, caso 2), retroceso profundo/superficial (Task 6, casos 3–4), impulso insuficiente (Task 6, caso 5), dirección SELL espejo (Task 6, caso 6), sweep sin recuperación (Task 7, caso 2), sweep más allá de P1 (Task 7, caso 3), ambos modos de sweep + `SWEEP_ANY` (Task 7, casos 1/4/5), breakout de mecha (Task 8, caso 3), cuerpo insuficiente (Task 8, caso 2), penetración insuficiente (Task 8, caso 4), alternancia forzada y filtro de pierna mínima (Task 3, casos 2–3), arranque `NEUTRAL` y transición `BULL→BEAR` (Task 4), alineación HTF total/parcial/opuesta (Task 5).
- **Known gap, called out explicitly, not silently dropped:** `max_bars_to_complete` timeout and the "close below P1.low" live invalidation are streaming concerns that belong to the Fase 2 orchestration loop, not to a single static `Evaluate()` call — documented in Task 6's scope boundary rather than left as an implicit gap.
- **Type consistency:** `SSwing`, `SPatternPoints`, `SBreakoutMetrics`, `ETrendState`, `EDirection`, `EPatternStage`, `ESwingType`, `ESweepMode` are used exactly as declared in the existing `Types.mqh` — no new fields invented. `SimpleATR(rates, period, shift)` signature is identical across every task that calls it (Tasks 3, 6, 7, 8).
- **`SWEEP_INTERNAL` flagged, not hidden:** since its spec description is genuinely underspecified, Task 7 states plainly that the implementation is an interpretation to revisit with Fase 3 data, rather than presenting it as equally certain as `SWEEP_BREACH_P3`.
