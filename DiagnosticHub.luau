--!strict
-- [[ DIAGNOSTIC HUB: ROOT FACADE ]] --
-- Master bootstrap, lifecycle controller, and unified public gateway for the DiagnosticHub pipeline.

-- [[ SERVICES ]] --
local RunService = game:GetService("RunService")

-- [[ DEPENDENCIES ]] --
local Types = require(script.Types)
local IngestionBus = require(script.IngestionBus)
local Watchdogs = require(script.Watchdogs)
local StackDecompiler = require(script.StackDecompiler)
local Synthesizer = require(script.Synthesizer)
local OutputCompositor = require(script.OutputCompositor)
local FaultCatalog = require(script.Lexicons.FaultCatalog)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local os_clock = os.clock
local os_time = os.time
local math_floor = math.floor
local table_freeze = table.freeze
local debug_traceback = debug.traceback

-- [[ EXPORTED PUBLIC CONTRACTS ]] --
export type Severity = Types.Severity
export type DiagnosticArtifact = Types.DiagnosticArtifact
export type RawLogSignal = Types.RawLogSignal
export type StackTelemetry = Types.StackTelemetry
export type ParsedFrame = Types.ParsedFrame
export type FaultRule = FaultCatalog.FaultRule
export type BreadcrumbEntry = Types.BreadcrumbEntry

export type SystemStatus = {
	IsRunning: boolean,
	UptimeSeconds: number,
	RecordedBreadcrumbs: number,
	Environment: string,
	IsStudio: boolean,
}

-- [[ MODULE STATE ]] --
local isRunning: boolean = false
local startupTimestamp: number = os_clock()

local DiagnosticHub = {}

-- Expose direct references to sub-modules for advanced pipelines
DiagnosticHub.IngestionBus = IngestionBus
DiagnosticHub.Watchdogs = Watchdogs
DiagnosticHub.StackDecompiler = StackDecompiler
DiagnosticHub.Synthesizer = Synthesizer
DiagnosticHub.OutputCompositor = OutputCompositor
DiagnosticHub.FaultCatalog = FaultCatalog

-- [[ SECTION 1: PUBLIC EXTENSIBILITY API ]] --
--[[
	Registers a single custom diagnostic rule into the catalog.
]]
function DiagnosticHub.RegisterFaultRule(rule: FaultCatalog.FaultRule)
	FaultCatalog.RegisterRule(rule)
end

--[[
	Batch registers an array of custom diagnostic rules into the catalog.
]]
function DiagnosticHub.RegisterFaultRules(rules: { FaultCatalog.FaultRule })
	FaultCatalog.RegisterRules(rules)
end

--[[
	Registers an external callback to receive raw log signals from the ingestion bus.
	Enables integration with external loggers, telemetry aggregators, or UI consoles.
]]
function DiagnosticHub.RegisterConsumer(consumer: (signal: Types.RawLogSignal) -> ())
	IngestionBus.RegisterConsumer(consumer)
end

-- [[ SECTION 2: LIFECYCLE MANAGEMENT ]] --
--[[
	Initializes the diagnostic bus, binding engine listeners and remote resolvers.
]]
function DiagnosticHub.Start()
	if isRunning then
		return
	end
	IngestionBus.Initialize()
	isRunning = true
end

--[[
	Decommissions the diagnostic bus and disconnects all engine listeners.
]]
function DiagnosticHub.Stop()
	if not isRunning then
		return
	end

	-- Support both Decommission and legacy Teardown implementations
	if typeof(IngestionBus.Decommission) == "function" then
		IngestionBus.Decommission()
	end

	isRunning = false
end

--[[
	Returns true if the diagnostic hub is actively listening for exceptions.
]]
function DiagnosticHub.IsRunning(): boolean
	return isRunning
end

-- [[ SECTION 3: WATCHDOG & SENTRIES ]] --
--[[
	Spawns a new task thread protected by crash interceptors.
]]
function DiagnosticHub.SafeSpawn(fn: (...any) -> (), ...: any): thread
	return Watchdogs.SafeSpawn(fn, ...)
end

--[[
	Executes a function in a protected call. Traps failures into breadcrumbs and telemetry.
]]
function DiagnosticHub.AuditedPcall(fn: (...any) -> ...any, ...: any): (boolean, ...any)
	return Watchdogs.AuditedPcall(fn, ...)
end

--[[
	Wraps WaitForChild with an asynchronous timeout watchdog sentry.
]]
function DiagnosticHub.WaitForChild(parent: Instance, childName: string, timeout: number?): Instance?
	return Watchdogs.WaitForChildWithSentry(parent, childName, timeout)
end

--[[
	Appends an operational breadcrumb to the fixed-size circular history ring buffer.
]]
function DiagnosticHub.TrackBreadcrumb(category: string, action: string)
	Watchdogs.PushBreadcrumb(category, action)
end

--[[
	Dumps all recorded breadcrumbs in chronological order as timestamped strings.
]]
function DiagnosticHub.GetBreadcrumbs(): { string }
	return Watchdogs.GetBreadcrumbs()
end

-- [[ SECTION 4: DIAGNOSTIC TELEMETRY & REPORTING ]] --
--[[
	Manually injects an error or exception into the diagnostic intake pipeline.
]]
function DiagnosticHub.CaptureException(message: string, rawStack: string?, severity: Types.Severity?)
	local stack = if rawStack and rawStack ~= "" then rawStack else debug_traceback(nil, 2)

	local signal: Types.RawLogSignal = {
		Message = message,
		RawStack = stack,
		Severity = severity or "ERROR",
		ScriptContext = nil,
		Timestamp = os_time(),
		ClientPlayer = nil,
	}

	IngestionBus.Ingest(signal)
end

--[[
	Semantic alias for CaptureException.
]]
function DiagnosticHub.Report(message: string, rawStack: string?, severity: Types.Severity?)
	DiagnosticHub.CaptureException(message, rawStack, severity)
end

--[[
	Preserved signature for backward compatibility. Directs to IngestionBus.Ingest.
]]
function DiagnosticHub.Synthesize(message: string, rawStack: string?, severity: Types.Severity?)
	DiagnosticHub.CaptureException(message, rawStack, severity)
end

-- [[ SECTION 5: PIPELINE UTILITIES ]] --
--[[
	Decompiles a raw stack trace into a structured StackTelemetry record.
]]
function DiagnosticHub.Decompile(rawTrace: string, fallbackMessage: string?): Types.StackTelemetry
	return StackDecompiler.Decompile(rawTrace, fallbackMessage)
end

--[[
	Synthesizes a raw log signal and deconstructed stack into a DiagnosticArtifact.
]]
function DiagnosticHub.SynthesizeArtifact(signal: Types.RawLogSignal, telemetry: Types.StackTelemetry): Types.DiagnosticArtifact
	return Synthesizer.Synthesize(signal, telemetry)
end

--[[
	Formats a DiagnosticArtifact into an ASCII companion card string without printing.
]]
function DiagnosticHub.ComposeCard(artifact: Types.DiagnosticArtifact): string
	return OutputCompositor.Compose(artifact)
end

--[[
	Composes and prints a DiagnosticArtifact companion card to the output console.
]]
function DiagnosticHub.RenderCard(artifact: Types.DiagnosticArtifact)
	OutputCompositor.Render(artifact)
end

-- [[ SECTION 6: SYSTEM INTROSPECTION ]] --
--[[
	Returns runtime operational telemetry for the diagnostic system.
]]
function DiagnosticHub.GetSystemStatus(): SystemStatus
	return {
		IsRunning = isRunning,
		UptimeSeconds = math_floor((os_clock() - startupTimestamp) * 100) / 100,
		RecordedBreadcrumbs = #Watchdogs.GetBreadcrumbs(),
		Environment = if RunService:IsServer() then "Server" else "Client",
		IsStudio = RunService:IsStudio(),
	}
end

-- Autonomous bootstrap on initial require
DiagnosticHub.Start()

return table_freeze(DiagnosticHub)
