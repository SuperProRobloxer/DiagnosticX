--!strict
-- [[ SHARED CONTRACTS & SCHEMAS ]] --
-- Immutable schema definitions, telemetry payloads, and diagnostic DTOs
-- passed throughout the DiagnosticHub pipeline.

-- [[ SECTION 1: SEVERITY & BASIC LOGGING ]] --
--[[
	Defines the allowable severity classifications across the diagnostic framework.
	Constrained strictly to ERROR and WARNING to maintain consistent filtering.
]]
export type Severity = "ERROR" | "WARNING"

--[[
	Represents the unparsed, raw signal captured directly from LogService,
	ScriptContext, or runtime exception hooks.
]]
export type RawLogSignal = {
	Message: string,
	RawStack: string,
	Severity: Severity,
	ScriptContext: LuaSourceContainer?,
	Timestamp: number,
	ClientPlayer: Player?,
}

--[[
	Lightweight error payload structure used for passing trapped errors
	across internal thread boundaries.
]]
export type ErrorPayload = {
	Message: string,
	Stack: string,
}

-- [[ SECTION 2: STACK TELEMETRY & FRAME DECONSTRUCTION ]] --
--[[
	Represents a single parsed line/frame from a debug.traceback string.
]]
export type ParsedFrame = {
	Source: string,
	Line: number,
	Function: string,
	IsEngineInternal: boolean,
}

--[[
	Represents the complete parsed structure of an execution stack trace,
	partitioned into origin frames and non-engine user frames.
]]
export type StackTelemetry = {
	OriginalTrace: string,
	OriginFrame: ParsedFrame?,
	UserFrames: { ParsedFrame },
	FrameDepth: number,
}

-- [[ SECTION 3: INFERENCE & FAULT MATCHING FRAGMENTS ]] --
--[[
	Fully self-contained fault fragment supporting decoupled heuristic rule expansion.
	Used by pattern-matching analyzers to identify root causes.
]]
export type FaultFragment = {
	ID: string,
	OperationName: string,
	Mechanism: string,
	Weight: number,
	SuggestedFix: string?,
	Category: string?,
	PossibleReason: string?,
}

--[[
	Target identification fragment representing tokens, instances, or operations
	targeted by a failing routine.
]]
export type TargetFragment = {
	ID: string,
	Token: string,
	Classification: string,
	Weight: number,
}

--[[
	Contextual state observation fragment capturing ambient engine or player conditions
	at the time of a diagnostic event.
]]
export type ContextFragment = {
	ID: string,
	ObservedState: string,
	Inference: string,
	Weight: number,
}

-- [[ SECTION 4: DIAGNOSTIC ARTIFACTS & AUDITING ]] --
--[[
	Snapshot of contextual execution metadata, containing execution origin
	and chronological circular breadcrumbs leading up to the fault.
]]
export type TelemetryContext = {
	Origin: string,
	Breadcrumbs: { string },
}

--[[
	The final synthesized diagnostic product output by the pipeline,
	ready for telemetry serialization, UI presentation, or developer logging.
]]
export type DiagnosticArtifact = {
	Severity: Severity,
	Confidence: number,
	Category: string,
	ClearMessage: string,
	PossibleReason: string,
	WhyItHappened: string,
	ActionableFix: string,
	ClientOrigin: Player?,
	TelemetryContext: TelemetryContext,
}

--[[
	Single circular buffer state entry for chronological runtime tracking.
]]
export type BreadcrumbEntry = {
	Timestamp: number,
	Category: string,
	Action: string,
}

-- [[ SECTION 5: SINK CALLBACK SIGNATURES ]] --
--[[
	Standardized callback signature for receiving intercepted logs, watchdog alerts,
	and trapped thread errors.
]]
export type SignalSink = (severity: Severity, message: string, rawStack: string) -> ()

-- [[ MODULE DEFINITION ]] --
local Types = {}

return table.freeze(Types)
