# DiagnosticX
DiagnosticX is a lightweight, zero-dependency APM and telemetry framework built to catch, decompile, and analyze client/server runtime errors in Roblox. Packaged inside a single drag-and-drop container, it provides strict type safety, pre-boot log ingestion, and low-overhead stack analysis without external dependencies or obfuscation.

--!strict
-- [KEEP THIS SCRIPT DISABLED IN STUDIO'S PROPERTIES WINDOW: Enabled = false]
-- This script serves as the in-engine developer manual for DiagnosticHub.
return

--[=[
================================================================================
           DIAGNOSTIC HUB & SATELLITE: DEVELOPER OPERATIONAL MANUAL
================================================================================

1. ARCHITECTURAL OVERVIEW & DRAG-AND-DROP PACKAGING
--------------------------------------------------------------------------------
DiagnosticX is an in-engine expert system that translates cryptic 
Luau runtime exceptions, syntax errors, and engine warnings into actionable 
domain explanations. Dont forget to put it in ServerScriptService and unpack the parent folder, so it becomes just the "Debug" folder and its contents!

Packaged as a completely self-contained, drag-and-drop container:
Insert-Into-ServerScriptService
└── Debug (Drag this folder into ServerScriptService to install)
    ├── Documentation (Folder)
    │   └── Debug-Tester (Folder)
    │       ├── DiagnosticHubTest (Script)                 <-- Unit & integration diagnostic test suite
    │	  └── read.me 	(Script)                           <-- You are here
    ├── DiagnosticHubBootstrap (Script)                    <-- Auto-provisioner & starter
    │   └── Dependencies (Folder)
    │       ├── ScriptSignals (Folder)                     <-- Auto-cloned to ReplicatedStorage
    │       │   └── Debugging (Folder)
    │       │       └── Remotes (Folder)
    │       │           └── ClientDebugger (RemoteEvent)   <-- Network bridge for client-side diagnostics
    │       └── DiagnosticSattelite (LocalScript)          <-- Auto-cloned to StarterPlayerScripts
    └── DiagnosticHub (ModuleScript)                       <-- Master facade
        ├── Lexicons (Folder)
        │   ├── ContextCatalog (ModuleScript)              <-- Environment heuristics
        │   ├── FaultCatalog (ModuleScript)                <-- Syntax & engine failure rules
        │   └── TargetCatalog (ModuleScript)               <-- Engine tokens & member matcher
        ├── IngestionBus (ModuleScript)                    <-- Signal hooks, breaker & log history
        ├── OutputCompositor (ModuleScript)                <-- Companion card renderer
        ├── StackDecompiler (ModuleScript)                 <-- Dual-source call-stack sanitizer
        ├── Synthesizer (ModuleScript)                     <-- Decoupled reasoning engine
        ├── Types (ModuleScript)                           <-- Static data contracts
        └── Watchdogs (ModuleScript)                       <-- Yield & thread sentries
        
2. RETROACTIVE CONSOLE LOG PROCESSING
--------------------------------------------------------------------------------
What if a script throws a fatal syntax error or runtime exception BEFORE 
DiagnosticHub initializes on the server?

DiagnosticHub contains an automatic Log History Ingestor:
• On startup, IngestionBus queries LogService:GetLogHistory().
• It scans the backlog for any errors or warnings that printed before boot.
• StackDecompiler inspects both the native call-stack and inline message
  traces (e.g. 'ServerScriptService.Script:14: ...'), resolving the source
  script and line number even for pre-boot crashes.


3. SYNTAX ERRORS & SCRIPTING MISTAKE RECOGNITION
--------------------------------------------------------------------------------
FaultCatalog contains targeted grammar definitions for common scripting errors:

A. SYNTAX & COMPILATION ERRORS:
   • Missing 'end' Block Terminator (<eof>)
   • Unexpected Token / Reserved Keyword Usage (e.g. local local = 1)
   • Incomplete Luau Statement
   • Unclosed String Literal
   • Missing 'then' in conditionals / Missing 'do' in loops
   • Unmatched Parentheses
   • ModuleScript initialization crashes & missing return values
   • Circular Module Dependency Deadlocks

B. MISSPELLINGS & LIBRARY MISUSE:
   • 'X is not a valid member of Y' (misspelled property/child, e.g. .position)
   • Calling non-existent methods (e.g. part:destory(), player:Kickk())
   • Iterating nil with pairs() or ipairs()
   • Inverted math.random ranges ('interval is empty')
   • Colon ':' vs Dot '.' syntax confusion (e.g. math:random() instead of math.random())
   • Missing mandatory API arguments (e.g. TweenService:Create)


4. 1-CLICK AUTO-SETUP TOGGLE (OPEN SOURCE READY)
--------------------------------------------------------------------------------
At the top of DiagnosticHubBootstrap, there is an auto-provisioning switch:

    local AUTO_PROVISION_DEPENDENCIES: boolean = true

• WHEN SET TO TRUE (DEFAULT):
  You do not need to manually configure ReplicatedStorage or StarterPlayer.
  When the game boots, the bootstrapper automatically:
  1. Clones 'ScriptSignals.Debugging.Remotes.ClientDebugger' into ReplicatedStorage.
  2. Clones 'DiagnosticSatellite' into StarterPlayer.StarterPlayerScripts and 
     injects it into any players already in-game.

• WHEN SET TO FALSE:
  The bootstrapper bypasses the 'Dependencies' folder entirely. Use this if
  your studio manages files manually or uses strict Rojo synchronization.
  
  DiagnosticX contains inside its documentation a debug tester that lets you test how DiagnosticX reacts and responds to different errors and warnings. Just activate the disabled script, and you can test it out.
  The testing script, "DiagnosticHubTest" is not critical to the function of DiagnosticX. You can remove it if you want.


5. THE CONFIDENCE INDICATOR: DO NOT TRUST IT BLINDLY
--------------------------------------------------------------------------------
Every diagnostic card generated by the system contains a calculated Confidence
score between 0% and 100%.

Formula:
  Confidence = Clamp(Fault_Weight + Target_Weight + Context_Weight - Ambiguity_Penalty, 0, 100)

HOW TO EVALUATE THE SUGGESTED FIX:

┌──────────────────────────────────────────────────────────────────────────────┐
│ [██████████████████░] 90% – 100% (CONFIRMED)                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│ MEANING: The broken operation, affected entity, and engine runtime state     │
│ fully aligned. Deploy the 'ACTIONABLE FIX' with high confidence.             │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ [██████████████░░░░░] 70% – 89% (PROBABLE)                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│ MEANING: The system accurately identified the broken operation and target,   │
│ but environmental validation was inconclusive. Treat fix as a hypothesis.    │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ [█████████░░░░░░░░░░] UNDER 70% (DEDUCTION)                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│ MEANING: Error originated in engine C-code or lacked user stack frames.      │
│ CRITICAL WARNING: DO NOT BLINDLY COPY-PASTE THE FIX.                         │
│ Use 'WHY IT HAPPENED' to understand the broken rule, then engineer your fix. │
└──────────────────────────────────────────────────────────────────────────────┘


6. EXTENDING THE FAULT CATALOG (ZERO-MODIFICATION EXPANSION)
--------------------------------------------------------------------------------
Register custom rules for your game systems directly from any server script:

   local ServerScriptService = game:GetService("ServerScriptService")
   local DiagnosticHub = require(ServerScriptService.ServerScripts.Debug.DiagnosticHub)

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


7. CLIENT-SIDE TELEMETRY & BREADCRUMBS
--------------------------------------------------------------------------------
Client controllers and UI scripts can record timeline actions leading up to
crashes using the global function pointer provided by DiagnosticSatellite:

   -- In ANY LocalScript in your entire game:
   if shared.DiagnosticTrackBreadcrumb then
       shared.DiagnosticTrackBreadcrumb("INVENTORY_UI", "Opened Equipment Bag")
       shared.DiagnosticTrackBreadcrumb("COMBAT", "Attempted Skill: Whirlwind")
   end


8. CIRCUIT BREAKER & MEMORY-BOUNDED PRUNING
--------------------------------------------------------------------------------
• If an identical error occurs 3 times in 1 second, the breaker TRIPS.
• Console output is silenced for 2.0 seconds (doubling exponentially up to 60s).
• To protect memory on servers running for weeks, an automatic LRU sweep
  caps the table at 256 active entries, pruning stale records older than 60s.


9. DUAL RENDERING (STUDIO VS. PRODUCTION)
--------------------------------------------------------------------------------
• IN ROBLOX STUDIO:
  Renders the visual ASCII companion card with confidence progress bars,
  breadcrumb lists, and multi-line code recommendations.

• IN LIVE PRODUCTION SERVERS (RunService:IsStudio() == false):
  Automatically collapses into a concise 5-line structured log to prevent
  Developer Console (F9) line truncation while preserving the error category,
  root cause, and client identity ([CLIENT: PlayerName | UserId]).
  
  
 10. SILENT ERROR INTERCEPTION & THREAD DIAGNOSTICS
 --------------------------------------------------------------------------------
Standard Luau execution environments frequently swallow background exceptions, making silent failures difficult to diagnose.
DiagnosticX uses specialized watchdog utilities to capture, audit, and trace errors that would otherwise vanish into the void:

Audited pcall Execution (AuditedPcall): 
- When protective error-catching wrappers are used around high-risk operations, normal implementations discard failure details if the error is handled. 
  AuditedPcall automatically intercepts failed runs, pushes a structured timeline breadcrumb (SWALLOWED_ERROR), and fires a warning notification to the ingestion bus while preserving safe execution flow.

Background Thread Sentries (WaitForChildWithSentry): 
- Unresponsive object replication can cause critical initialization threads to hang indefinitely without throwing console errors. 
  The sentry wraps asynchronous instance lookups with a non-blocking timeout monitor. If replication exceeds the threshold, it extracts the suspended thread's execution path using debug_traceback and reports a precise infinite yield warning.

Asynchronous Protected Spawning (SafeSpawn): 
Replaces standard task.spawn calls with an internal xpcall boundary.
If an unhandled exception occurs inside a spawned worker thread, the runner catches the failure payload alongside a deep stack traceback and routes it directly to the diagnostic pipeline before thread termination occurs.


11. THE DIAGNOSTIC PIPELINE: END-TO-END ARCHITECTURE & DATA FLOW (Summary)
--------------------------------------------------------------------------------
DiagnosticX processes errors through a strictly decoupled, 4-stage processing 
pipeline designed for zero-latency degradation and high analytical precision:

STAGE 1: INGESTION (Collection & Rate-Limiting)
- Source Entry: Errors enter via server-side hooks, LogService:GetLogHistory(), 
  Watchdogs (SafeSpawn, AuditedPcall, WaitForChildWithSentry), or the 
  'ClientDebugger' UnreliableRemoteEvent from client satellites.
- Security Gate: Incoming remote payloads pass through token-bucket rate 
  limiters, strict type verification, and size clamping before queuing.

STAGE 2: DECOMPILATION & SANITIZATION (Stack Resolution)
- StackDecompiler parses raw native call-stacks and inline message traces.
- Resolves exact source ModuleScripts, parent containers, and line numbers 
  even for pre-boot crashes or obfuscated production frames.

STAGE 3: ANALYSIS & REASONING (Lexicon Synthesis)
- Synthesizer cross-references the sanitized error against three core catalogs:
  * FaultCatalog: Matches syntax grammar, missing ends, and engine error patterns.
  * TargetCatalog: Resolves property mismatches, nil indexing, and bad member calls.
  * ContextCatalog: Evaluates environment heuristics and runtime states.
- Calculates a weighted Confidence score (0%–100%) and generates a diagnostic hypothesis.

STAGE 4: COMPOSITING & RENDERING (Output Delivery)
- OutputCompositor formats the final diagnostic package based on runtime state:
  * In Studio: Renders a detailed ASCII companion card with confidence meters 
    and multi-line fix recommendations.
  * In Live Servers: Collapses into a clean 5-line structured log to prevent 
    F9 console spam while preserving client attribution and root-cause analysis.
================================================================================
]=]
