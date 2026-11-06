--!strict
-- [[ SYNTHESIZER: UNIVERSAL CONSUMER ]] --
-- Correlates catalog fragments, deconstructed stack telemetry, and environmental
-- state into human-readable, actionable diagnostic artifacts.

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Types)
local FaultCatalog = require(script.Parent.Lexicons.FaultCatalog)
local TargetCatalog = require(script.Parent.Lexicons.TargetCatalog)
local ContextCatalog = require(script.Parent.Lexicons.ContextCatalog)
local Watchdogs = require(script.Parent.Watchdogs)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local math_clamp = math.clamp
local string_format = string.format
local table_freeze = table.freeze
local pcall = pcall
local print = print
local typeof = typeof

-- [[ CONFIGURATION CONSTANTS ]] --
local PENALTY_NO_FRAMES: number = 15
local PENALTY_ENGINE_ORIGIN: number = 15
local DEFAULT_ORIGIN_STR: string = "Unknown Source -> Line Unknown"

-- [[ MODULE DEFINITION ]] --
local Synthesizer = {}

-- [[ SECTION 1: ARTIFACT SYNTHESIS ]] --
--[[
	Pure synthesis engine. Evaluates a RawLogSignal against parsed StackTelemetry,
	querying rule catalogs and environmental heuristics to construct a DiagnosticArtifact.
]]
function Synthesizer.Synthesize(
	signal: Types.RawLogSignal,
	telemetry: Types.StackTelemetry
): Types.DiagnosticArtifact
	-- Step 1: Lexicon fragment matching
	local fault: Types.FaultFragment = FaultCatalog.Match(signal.Message)
	local target: Types.TargetFragment = TargetCatalog.Match(signal.Message)
	local context: Types.ContextFragment = ContextCatalog.Evaluate(fault, target)

	-- Step 2: Telemetry ambiguity penalties
	local ambiguityPenalty: number = 0
	if telemetry.FrameDepth == 0 or #telemetry.UserFrames == 0 then
		ambiguityPenalty += PENALTY_NO_FRAMES
	end
	if telemetry.OriginFrame == nil or telemetry.OriginFrame.IsEngineInternal then
		ambiguityPenalty += PENALTY_ENGINE_ORIGIN
	end

	-- Safe weight arithmetic guards against malformed catalog additions
	local faultWeight: number = fault.Weight or 0
	local targetWeight: number = target.Weight or 0
	local contextWeight: number = context.Weight or 0
	local confidence: number = math_clamp(faultWeight + targetWeight + contextWeight - ambiguityPenalty, 0, 100)

	-- Step 3: Origin formatting & line attribution
	local originStr: string = DEFAULT_ORIGIN_STR
	local originLine: number = 0

	if telemetry.OriginFrame then
		local frame = telemetry.OriginFrame
		originLine = frame.Line

		local lineLabel = if frame.Line > 0 then string_format("Line %d", frame.Line) else "Line Unknown"
		local funcLabel = if frame.Function ~= "" and frame.Function ~= "(anonymous)"
			then string_format(" [Inside: %s()]", frame.Function)
			else " [Inside: anonymous/global scope]"

		originStr = string_format("%s -> %s%s", frame.Source, lineLabel, funcLabel)
	end

	local lineClause: string = if originLine > 0
		then string_format("on line %d", originLine)
		else "at the execution origin"

	-- Normalize target tokens to avoid empty or blank displays
	local hasValidTarget: boolean = target.Token ~= "" and target.Token ~= "nil" and target.Token ~= "Unknown" and target.Token ~= "UnknownSymbol"
	local targetToken: string = if hasValidTarget then target.Token else "target member"

	local category: string
	local clearMessage: string
	local possibleReason: string
	local whyItHappened: string
	local actionableFix: string

	-- Step 4: Environmental & catalog rule mapping
	if fault.ID == "INDEX_ON_NIL" and context.ID == "STREAMING_CHARACTER_RACE" then
		category = "Character Lifecycle / Streaming Race"
		clearMessage = if hasValidTarget
			then string_format("Attempted to access '%s', but the character model is not fully replicated or has streamed out.", targetToken)
			else "Attempted to access a character member, but the character model is not fully replicated or has streamed out."
		possibleReason = "The player character spawned, but its physical parts have not finished replicating over the network."
		whyItHappened = string_format("The variable referencing the character evaluates to 'nil' %s, preventing '%s' from dereferencing.", lineClause, targetToken)
		actionableFix = if hasValidTarget
			then string_format('Replace direct member access with: local part = character:WaitForChild("%s", 5)\nOr add an early guard: if not character then return end', targetToken)
			else "Wrap member access inside character:WaitForChild(...) or verify the character exists prior to indexing."
	else
		-- Generic universal catalog consumer binding
		category = fault.Category or fault.OperationName
		clearMessage = if hasValidTarget
			then string_format("%s (Target: '%s')", fault.OperationName, targetToken)
			else fault.OperationName
		possibleReason = fault.PossibleReason or context.Inference
		whyItHappened = string_format("%s (Observed %s).", fault.Mechanism, lineClause)
		actionableFix = fault.SuggestedFix or "Inspect the line of origin, verify instance hierarchy existence, and check calling arguments."
	end

	-- Step 5: Artifact assembly
	local artifact: Types.DiagnosticArtifact = {
		Severity = signal.Severity,
		Confidence = confidence,
		Category = category,
		ClearMessage = clearMessage,
		PossibleReason = possibleReason,
		WhyItHappened = whyItHappened,
		ActionableFix = actionableFix,
		ClientOrigin = signal.ClientPlayer,
		TelemetryContext = {
			Origin = originStr,
			Breadcrumbs = Watchdogs.GetBreadcrumbs(),
		},
	}

	return artifact
end

-- [[ SECTION 2: PIPELINE DISPATCH & CONSUMER BRIDGE ]] --
--[[
	Entrypoint invoked by IngestionBus. Decompiles raw stack traces via sibling
	StackDecompiler, runs Synthesize, and guarantees that OutputCompositor emits
	the resulting diagnostic companion card to the output console.
]]
function Synthesizer.ProcessSignal(signal: Types.RawLogSignal): Types.DiagnosticArtifact
	local telemetry: Types.StackTelemetry

	-- Attempt deconstruction via StackDecompiler sibling
	local stackDecompilerModule = script.Parent:FindFirstChild("StackDecompiler")
	if stackDecompilerModule and stackDecompilerModule:IsA("ModuleScript") then
		local ok, StackDecompiler = pcall(require, stackDecompilerModule)
		if ok and typeof(StackDecompiler) == "table" and typeof(StackDecompiler.Decompile) == "function" then
			telemetry = StackDecompiler.Decompile(signal.RawStack, signal.Message)
		else
			telemetry = {
				OriginalTrace = signal.RawStack,
				OriginFrame = nil,
				UserFrames = {},
				FrameDepth = 0,
			}
		end
	else
		telemetry = {
			OriginalTrace = signal.RawStack,
			OriginFrame = nil,
			UserFrames = {},
			FrameDepth = 0,
		}
	end

	local artifact = Synthesizer.Synthesize(signal, telemetry)

	-- Forward completed artifact to OutputCompositor sibling with guaranteed console emission
	local outputCompositorModule = script.Parent:FindFirstChild("OutputCompositor")
	if outputCompositorModule and outputCompositorModule:IsA("ModuleScript") then
		local ok, OutputCompositor = pcall(require, outputCompositorModule)
		if ok and typeof(OutputCompositor) == "table" then
			-- Prioritize Render/Emit (which execute print). Fallback to Compose only if it returns a printable string.
			if typeof(OutputCompositor.Render) == "function" then
				pcall(OutputCompositor.Render, artifact)
			elseif typeof(OutputCompositor.Emit) == "function" then
				pcall(OutputCompositor.Emit, artifact)
			elseif typeof(OutputCompositor.Compose) == "function" then
				local composeOk, cardString = pcall(OutputCompositor.Compose, artifact)
				if composeOk and typeof(cardString) == "string" then
					print(cardString)
				end
			end
		end
	end

	return artifact
end

return table_freeze(Synthesizer)
