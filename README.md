DiagnosticX

DiagnosticX is a lightweight, zero-dependency APM and telemetry framework built to catch, decompile, and analyze client/server runtime errors in Roblox. Packaged inside a single drag-and-drop container, it provides strict type safety, pre-boot log ingestion, and low-overhead stack analysis without external dependencies or obfuscation.

1. Architectural Overview & Packaging

DiagnosticX is an in-engine expert system that translates cryptic Luau runtime exceptions, syntax errors, and engine warnings into actionable domain explanations.

Directory Structure

Drag the Debug folder directly into ServerScriptService to install:

ServerScriptService
└── Debug
    ├── Documentation
    │   └── Debug-Tester
    │       ├── DiagnosticHubTest (Script)        <-- Integration diagnostic test suite
    │       └── read.me (Script)                  <-- In-engine documentation
    ├── DiagnosticHubBootstrap (Script)           <-- Auto-provisioner & starter
    │   └── Dependencies
    │       ├── ScriptSignals
    │       │   └── Debugging
    │       │       └── Remotes
    │       │           └── ClientDebugger (RemoteEvent)
    │       └── DiagnosticSatellite (LocalScript)  <-- Auto-cloned to StarterPlayerScripts
    └── DiagnosticHub (ModuleScript)              <-- Master facade
        ├── Lexicons
        │   ├── ContextCatalog (ModuleScript)     <-- Environment heuristics
        │   ├── FaultCatalog (ModuleScript)       <-- Syntax & engine failure rules
        │   └── TargetCatalog (ModuleScript)      <-- Engine tokens & member matcher
        ├── IngestionBus (ModuleScript)           <-- Signal hooks, breaker & log history
        ├── OutputCompositor (ModuleScript)        <-- Companion card renderer
        ├── StackDecompiler (ModuleScript)        <-- Dual-source call-stack sanitizer
        ├── Synthesizer (ModuleScript)            <-- Decoupled reasoning engine
        ├── Types (ModuleScript)                  <-- Static data contracts
        └── Watchdogs (ModuleScript)              <-- Yield & thread sentries


2. Retroactive Console Log Processing

What if a script throws a fatal syntax error or runtime exception before DiagnosticHub initializes on the server?

DiagnosticHub contains an automatic Log History Ingestor:

On startup, IngestionBus queries LogService:GetLogHistory().

It scans the backlog for any errors or warnings printed prior to boot.

StackDecompiler inspects both native call-stacks and inline message traces (e.g., 'ServerScriptService.Script:14: ...'), resolving source script and line numbers even for pre-boot crashes.

3. Scripting Failure Recognition

FaultCatalog contains targeted grammar definitions for common Luau and engine errors:

A. Syntax & Compilation Errors

Missing end block terminators (<eof>).

Unexpected token / reserved keyword usage (e.g., local local = 1).

Incomplete Luau statements & unclosed string literals.

Missing then in conditionals or missing do in loops.

Unmatched parentheses.

ModuleScript initialization crashes & missing return values.

Circular Module dependency deadlocks.

B. Misspellings & Library Misuse

"X is not a valid member of Y" (misspelled property/child).

Non-existent method calls (e.g., part:destory(), player:Kickk()).

Iterating nil with pairs() or ipairs().

Inverted math.random ranges (interval is empty).

Colon : vs. Dot . syntax confusion (e.g., math:random() instead of math.random()).

Missing mandatory API arguments (e.g., TweenService:Create).

4. One-Click Auto-Setup Toggle

At the top of DiagnosticHubBootstrap, configure auto-provisioning:

local AUTO_PROVISION_DEPENDENCIES: boolean = true


true (Default): Dependencies are managed automatically. On boot, the framework clones the client remotes to ReplicatedStorage and injects DiagnosticSatellite into StarterPlayerScripts.

false: Provisioning is bypassed. Use this mode if your workflow relies on manual configuration or strict Rojo synchronization.

Note: The included DiagnosticHubTest script provides unit tests for error handling. It can be toggled via Studio properties or removed entirely without affecting runtime operations.

5. Confidence Score System

Every diagnostic package contains a calculated confidence score between 0% and 100%:

$$\text{Confidence} = \text{Clamp}(\text{Fault Weight} + \text{Target Weight} + \text{Context Weight} - \text{Ambiguity Penalty}, 0, 100)$$

Rating Thresholds

Range

Level

Guidance

90% – 100%

Confirmed

The failure condition and target state aligned completely. Apply the suggested fix directly.

70% – 89%

Probable

Operation identified, but runtime environment validation was inconclusive. Treat fix as a strong hypothesis.

< 70%

Deduction

Error originated in C-code or lacked complete user stack frames. Review the root cause description and verify manually.

6. Zero-Modification Fault Extensions

Register custom diagnostic rules for game-specific systems from any server script without modifying core files:

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


7. Client Telemetry & Breadcrumbs

Record client timeline actions leading up to exceptions via the global helper provided by DiagnosticSatellite:

-- In any LocalScript:
if shared.DiagnosticTrackBreadcrumb then
    shared.DiagnosticTrackBreadcrumb("INVENTORY_UI", "Opened Equipment Bag")
    shared.DiagnosticTrackBreadcrumb("COMBAT", "Attempted Skill: Whirlwind")
end


8. Rate Limiting & Memory Pruning

Circuit Breaker: If an identical error occurs 3 times within 1 second, output is muted for 2.0 seconds (doubling exponentially up to 60s).

LRU Pruning: An automatic Least Recently Used sweep caps internal tables at 256 active entries, removing stale records older than 60 seconds to preserve memory on long-running servers.

9. Environment-Aware Output Modes

Roblox Studio (IsStudio == true): Outputs formatted ASCII diagnostic cards containing full stack details, confidence meters, breadcrumb histories, and code recommendations.

Production Servers (IsStudio == false): Collapses output into concise 5-line structured logs to prevent Developer Console (F9) truncation while preserving root-cause data and player attribution ([CLIENT: PlayerName | UserId]).

10. Silent Error & Thread Watchdogs

Standard execution environments often swallow background errors. DiagnosticX includes dedicated watchdogs:

AuditedPcall: Intercepts handled pcall failures, pushes timeline breadcrumbs (SWALLOWED_ERROR), and notifies the ingestion bus without interrupting code execution.

WaitForChildWithSentry: Wraps asynchronous instance lookups with non-blocking timeout checks. If replication stalls, it extracts the thread's call-stack via debug_traceback and logs an infinite yield warning.

SafeSpawn: Replaces task.spawn with an xpcall boundary, capturing unhandled exceptions inside background threads before termination.

11. Pipeline Architecture

[ STAGE 1: INGESTION ] ──► [ STAGE 2: SANITIZATION ] ──► [ STAGE 3: SYNTHESIS ] ──► [ STAGE 4: RENDERING ]
  • LogService History      • Traceback Parsing            • Fault Matching           • Studio Companion Card
  • Server / Client Hooks    • Module & Line Resolution     • Target Resolution        • Production 5-Line Log
  • Thread Watchdogs         • Frame Sanitization           • Confidence Scoring
