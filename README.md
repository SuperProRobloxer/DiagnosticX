# DIAGNOSTICX

DiagnosticX is a lightweight, zero-dependency APM and telemetry framework built to catch, decompile, and analyze client/server runtime errors in Roblox. Packaged inside a single drag-and-drop container, it provides strict type safety, pre-boot log ingestion, and low-overhead stack analysis without external dependencies or obfuscation. It was built using assistance from Generative AI.

It will be open source and free, forever. Audit the code, review it, and edit it to your needs. Read the documentation further below for more information.

## 1. ARCHITECTURAL OVERVIEW & PACKAGING

DiagnosticX is an in-engine expert system that translates cryptic Luau runtime exceptions, syntax errors, and engine warnings into actionable domain explanations.

DIRECTORY STRUCTURE

Drag the 'Debug' folder directly into ServerScriptService to install:
```
Insert-Into-ServerScriptService
└── Debug (Drag this folder into ServerScriptService to install)
    ├── Documentation (Folder)
    │   └── Debug-Tester (Folder)
    │       ├── DiagnosticHubTest (Script)        <-- Integration test suite
    │   └── read.me (Script)                      <-- In-engine documentation
    ├── DiagnosticHubBootstrap (Script)           <-- Auto-provisioner & starter
    │   └── Dependencies (Folder)
    │       ├── ScriptSignals (Folder)
    │       │   └── Debugging (Folder)
    │       │       └── Remotes (Folder)
    │       │           └── ClientDebugger (UnreliableRemoteEvent)
    │       └── DiagnosticSatellite (LocalScript) <-- Auto-cloned to StarterPlayer
    └── DiagnosticHub (ModuleScript)              <-- Master facade
        ├── Lexicons (Folder)
        │   ├── ContextCatalog (ModuleScript)     <-- Environment heuristics
        │   ├── FaultCatalog (ModuleScript)       <-- Syntax & failure rules
        │   └── TargetCatalog (ModuleScript)      <-- Engine token matcher
        ├── IngestionBus (ModuleScript)           <-- Signal hooks & log history
        ├── OutputCompositor (ModuleScript)        <-- Companion card renderer
        ├── StackDecompiler (ModuleScript)        <-- Call-stack sanitizer
        ├── Synthesizer (ModuleScript)            <-- Decoupled reasoning engine
        ├── Types (ModuleScript)                  <-- Static data contracts
        └── Watchdogs (ModuleScript)              <-- Yield & thread sentries
```


## 2. RETROACTIVE CONSOLE LOG PROCESSING

What if a script throws a fatal syntax error or runtime exception BEFORE DiagnosticHub initializes on the server?

DiagnosticHub contains an automatic Log History Ingestor:

On startup, IngestionBus queries LogService:GetLogHistory().

It scans the backlog for any errors or warnings printed prior to boot.

StackDecompiler inspects both native call-stacks and inline message traces ```(e.g., 'ServerScriptService.Script:14: ...')```, resolving source script and line numbers even for pre-boot crashes.

## 3. SCRIPTING FAILURE RECOGNITION

FaultCatalog contains targeted grammar definitions for common scripting errors:

### A. SYNTAX & COMPILATION ERRORS:

Missing 'end' block terminators (<eof>).

Unexpected token / reserved keyword usage (e.g., local local = 1).

Incomplete Luau statements & unclosed string literals.

Missing 'then' in conditionals or missing 'do' in loops.

Unmatched parentheses.

ModuleScript initialization crashes & missing return values.

Circular Module dependency deadlocks.

### B. MISSPELLINGS & LIBRARY MISUSE:

"X is not a valid member of Y" (misspelled property or child).

Non-existent method calls (e.g., part:destory(), player:Kickk()).

Iterating nil with pairs() or ipairs().

Inverted math.random ranges ("interval is empty").

Colon ':' vs. Dot '.' syntax confusion (e.g., math:random() instead of math.random()).

Missing mandatory API arguments (e.g., TweenService:Create).

### 4. ONE-CLICK AUTO-SETUP TOGGLE

At the top of DiagnosticHubBootstrap, configure auto-provisioning:

local AUTO_PROVISION_DEPENDENCIES: boolean = true



true (DEFAULT): Dependencies are managed automatically. On boot, the framework clones client remotes to ReplicatedStorage and injects DiagnosticSatellite into StarterPlayerScripts.

false: Provisioning is bypassed. Use this mode if your workflow relies on manual configuration or strict Rojo synchronization.

Note: The included DiagnosticHubTest script provides unit tests for error handling. It can be toggled via Studio properties (Enabled = false) or removed entirely without affecting runtime operations.

## 5. CONFIDENCE SCORE SYSTEM

Every diagnostic package contains a calculated confidence score between 0% and 100%:

Formula:
```
Confidence = Clamp(Fault Weight + Target Weight + Context Weight - Ambiguity Penalty, 0, 100)
```

```RATING THRESHOLDS:

+------------+-----------+-------------------------------------------------+
| RANGE      | LEVEL     | GUIDANCE                                        |
+------------+-----------+-------------------------------------------------+
| 90% - 100% | CONFIRMED | Failure condition & target state aligned.       |
|            |           | Apply the suggested fix directly.               |
+------------+-----------+-------------------------------------------------+
| 70% - 89%  | PROBABLE  | Operation identified, but environment check     |
|            |           | was inconclusive. Treat fix as a hypothesis.    |
+------------+-----------+-------------------------------------------------+
| Under 70%  | DEDUCTION | Error originated in C-code or lacked stack.     |
|            |           | Review root cause & verify fix manually.        |
+------------+-----------+-------------------------------------------------+
```


## 6. ZERO-MODIFICATION FAULT EXTENSIONS

Register custom diagnostic rules for game-specific systems from any server script without modifying core files:
```
local ServerScriptService = game:GetService("ServerScriptService")
local DiagnosticHub = require(ServerScriptService.Debug.DiagnosticHub)

DiagnosticHub.RegisterFaultRule({
    Pattern = "InventoryException: Backpack is full",
    ID = "BACKPACK_CAPACITY_EXCEEDED",
    Name = "Inventory Capacity Exceeded",
    Mechanism = "A player attempted to pick up an item when inventory slots were saturated.",
    Weight = 40,
    Category = "Inventory / Storage System",
    PossibleReason = "Item drop was collected without verifying inventory capacity first.",
    SuggestedFix = "Check if playerInventory:HasFreeSlot() before firing the pickup event.",
})
```


## 7. CLIENT TELEMETRY & BREADCRUMBS

Record client timeline actions leading up to exceptions via the global helper provided by DiagnosticSatellite:
```
-- In any LocalScript:
if shared.DiagnosticTrackBreadcrumb then
    shared.DiagnosticTrackBreadcrumb("INVENTORY_UI", "Opened Equipment Bag")
    shared.DiagnosticTrackBreadcrumb("COMBAT", "Attempted Skill: Whirlwind")
end
```


## 8. RATE LIMITING & MEMORY PRUNING

**CIRCUIT BREAKER:** If an identical error occurs 3 times within 1 second, output is muted for 2.0 seconds (doubling exponentially up to 60s).

**LRU PRUNING:** An automatic Least Recently Used sweep caps internal tables at 256 active entries, removing stale records older than 60 seconds to preserve memory on long-running servers.

## 9. ENVIRONMENT-AWARE OUTPUT MODES

**ROBLOX STUDIO (RunService:IsStudio() == true):** Outputs formatted ASCII diagnostic cards containing full stack details, confidence meters, breadcrumb histories, and code recommendations.

**PRODUCTION SERVERS (RunService:IsStudio() == false):** Collapses output into concise 5-line structured logs to prevent Developer Console (F9) line truncation while preserving root-cause data and player attribution ([CLIENT: PlayerName | UserId]).

## 10. SILENT ERROR & THREAD WATCHDOGS

Standard execution environments often swallow background errors. DiagnosticX includes dedicated watchdogs:

**AuditedPcall:** Intercepts handled pcall failures, pushes timeline breadcrumbs (SWALLOWED_ERROR), and notifies the ingestion bus without interrupting code execution.

**WaitForChildWithSentry:** Wraps asynchronous instance lookups with non-blocking timeout checks. If replication stalls, it extracts the thread's call-stack via debug_traceback and logs an infinite yield warning.

**SafeSpawn:** Replaces task.spawn with an xpcall boundary, capturing unhandled exceptions inside background threads before termination.

## 11. PIPELINE ARCHITECTURE
```
  [STAGE 1: INGESTION] -> [STAGE 2: SANITIZATION] -> [STAGE 3: SYNTHESIS] -> [STAGE 4: RENDERING]
  -----------------------------------------------------------------------------------------------
  • LogService History    • Traceback Parsing        • Fault Matching         • Studio Companion Card
  • Server/Client Hooks   • Script & Line Resolution • Target Resolution      • Production 5-Line Log
  • Thread Watchdogs      • Frame Sanitization       • Confidence Scoring

```
