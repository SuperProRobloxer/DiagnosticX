--!strict
-- [[ CONTEXT CATALOG ]] --
-- Environmental probes evaluating replication flags, authority boundaries,
-- streaming states, and studio sandboxes into pre-compiled ContextFragments.

-- [[ SERVICES ]] --
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Parent.Types)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local string_find = string.find
local string_format = string.format
local table_freeze = table.freeze

-- [[ MODULE DEFINITION ]] --
local ContextCatalog = {}

-- [[ SECTION 1: INVARIANT ENGINE STATE CACHING ]] --
-- Evaluated once at load time since execution environment and streaming configurations are immutable at runtime
local IS_SERVER: boolean = RunService:IsServer()
local IS_STUDIO: boolean = RunService:IsStudio()
local STREAMING_ENABLED: boolean = Workspace.StreamingEnabled

local ENV_LABEL: string = if IS_SERVER then "Server (Script)" else "Client (LocalScript)"
local STREAMING_LABEL: string = if STREAMING_ENABLED then "Active" else "Disabled"
local STUDIO_LABEL: string = if IS_STUDIO then "Studio" else "Live Game"

-- [[ SECTION 2: PRE-CONSTRUCTED CONTEXT FRAGMENTS ]] --
-- Pre-allocated to eliminate string formatting and dictionary allocation in the hot path

local FRAGMENT_STREAMING_CHARACTER_RACE: Types.ContextFragment = {
	ID = "STREAMING_CHARACTER_RACE",
	ObservedState = string_format("Workspace.StreamingEnabled = true | Environment = %s", ENV_LABEL),
	Inference = "Physical rig assemblies stream asynchronously. Sub-parts may not be present when the parent model first instantiates.",
	Weight = 30,
}

local FRAGMENT_DATASTORE_INFRASTRUCTURE: Types.ContextFragment = {
	ID = "DATASTORE_INFRASTRUCTURE",
	ObservedState = string_format("Environment = %s | Cloud Persistence Budget Active", ENV_LABEL),
	Inference = "Cloud DataStore and MemoryStore requests are constrained by per-key request throttling and external network latency.",
	Weight = 30,
}

local FRAGMENT_CLIENT_AUTHORITY_VIOLATION: Types.ContextFragment = {
	ID = "CLIENT_AUTHORITY_VIOLATION",
	ObservedState = "Environment = Client (LocalScript) | Server Authority Required",
	Inference = "A client-side script attempted to invoke server-exclusive operations or services. The client lacks network authority for this action.",
	Weight = 35,
}

local FRAGMENT_SERVER_AUTHORITY_INVERSION: Types.ContextFragment = {
	ID = "SERVER_AUTHORITY_INVERSION",
	ObservedState = "Environment = Server (Script) | Client Target Expected",
	Inference = "A server script attempted to invoke client-side RPC methods (e.g., FireServer). The server must use FireClient or FireAllClients.",
	Weight = 35,
}

local FRAGMENT_STUDIO_LIMITATION: Types.ContextFragment = {
	ID = "STUDIO_ENVIRONMENT_LIMITATION",
	ObservedState = string_format("Environment = %s | %s Sandbox Constraints", ENV_LABEL, STUDIO_LABEL),
	Inference = "Certain engine features (such as inter-place teleports, external HTTP, or third-party purchases) are restricted by Studio settings or sandbox policies.",
	Weight = 35,
}

local FRAGMENT_PARALLEL_EXECUTION: Types.ContextFragment = {
	ID = "PARALLEL_ACTOR_EXECUTION",
	ObservedState = "Execution Model = Parallel Luau | Actor Desynchronized Phase",
	Inference = "The calling thread is currently executing inside a desynchronized Parallel Luau phase where direct DataModel mutation is strictly prohibited.",
	Weight = 35,
}

local FRAGMENT_REPLICATION_BOUNDARY: Types.ContextFragment = {
	ID = "REPLICATION_BOUNDARY",
	ObservedState = string_format("Authority Context: %s | Network Boundary", ENV_LABEL),
	Inference = "Cross-boundary remote calls require network-replicated Remote instances and conformant parameter serialization across the network bridge.",
	Weight = 25,
}

local FRAGMENT_CLIENT_GUI_LIFECYCLE: Types.ContextFragment = {
	ID = "CLIENT_GUI_LIFECYCLE",
	ObservedState = "Environment = Client | PlayerGui Lifecycle Active",
	Inference = "PlayerGui instances are rebuilt when a player respawns. Scripts referencing UI objects directly may fail across respawn cycles if ResetOnSpawn is enabled.",
	Weight = 25,
}

local FRAGMENT_STANDARD_ENVIRONMENT: Types.ContextFragment = {
	ID = "STANDARD_ENVIRONMENT",
	ObservedState = string_format("Environment: %s | Streaming: %s | Mode: %s", ENV_LABEL, STREAMING_LABEL, STUDIO_LABEL),
	Inference = "Standard execution environment without special streaming or network authority anomalies detected.",
	Weight = 15,
}

-- [[ SECTION 3: EVALUATION PIPELINE ]] --
--[[
	Evaluates a matched FaultFragment and TargetFragment against ambient
	environmental states, returning an appropriate ContextFragment.
]]
function ContextCatalog.Evaluate(fault: Types.FaultFragment, target: Types.TargetFragment): Types.ContextFragment
	local classification = target.Classification or ""
	local faultID = fault.ID or ""

	-- 1. Studio Sandbox Constraints
	if IS_STUDIO and (faultID == "TELEPORT_IN_STUDIO" or faultID == "THIRD_PARTY_SALES_DISABLED" or faultID == "HTTP_SERVICE_DISABLED") then
		return FRAGMENT_STUDIO_LIMITATION
	end

	-- 2. Client Authority Violations (Client attempting server-only actions)
	if not IS_SERVER and (
		faultID == "DATASTORE_CLIENT_ACCESS"
			or faultID == "INVOKE_CLIENT_AUTHORITY"
			or faultID == "FIRE_ALL_CLIENTS_ON_CLIENT"
			or faultID == "NETWORK_OWNER_CLIENT_CALL"
			or classification == "Server Authority Storage"
		) then
		return FRAGMENT_CLIENT_AUTHORITY_VIOLATION
	end

	-- 3. Server Authority Inversions (Server attempting client-only actions)
	if IS_SERVER and (faultID == "FIRE_SERVER_ON_SERVER" or classification == "Client RPC Endpoint") then
		return FRAGMENT_SERVER_AUTHORITY_INVERSION
	end

	-- 4. Parallel Luau Concurrency Constraints
	if faultID == "PARALLEL_DESYNC_WRITE" or faultID == "PARALLEL_THREAD_UNSAFE_READ" then
		return FRAGMENT_PARALLEL_EXECUTION
	end

	-- 5. StreamingEnabled Character / Spatial Rig Races
	if STREAMING_ENABLED and (
		classification == "Spatial Physics Node / Rig Assembly"
			or classification == "Kinematic Rig Assembly Part"
			or (faultID == "INDEX_ON_NIL" and string_find(classification, "Rig", 1, true) ~= nil)
		) then
		return FRAGMENT_STREAMING_CHARACTER_RACE
	end

	-- 6. DataStore & Cloud Persistence Infrastructure
	if classification == "DataStore Read Operation"
		or classification == "DataStore Write Operation"
		or classification == "DataStore Transactional Mutator"
		or faultID == "DATASTORE_SATURATION"
		or faultID == "DATASTORE_EMPTY_KEY"
		or faultID == "MEMORY_STORE_KEY_LIMIT"
	then
		return FRAGMENT_DATASTORE_INFRASTRUCTURE
	end

	-- 7. Network Replication Boundary
	if string_find(classification, "Remote", 1, true) ~= nil
		or faultID == "REMOTE_CYCLIC_TABLE"
		or faultID == "UNRELIABLE_PAYLOAD_OVERFLOW"
		or faultID == "FIRE_CLIENT_MISSING_PLAYER"
		or faultID == "INVOKE_CLIENT_MISSING_PLAYER"
	then
		return FRAGMENT_REPLICATION_BOUNDARY
	end

	-- 8. Client UI / PlayerGui Lifecycle Races
	if not IS_SERVER and (
		string_find(classification, "Gui", 1, true) ~= nil
			or string_find(classification, "PlayerGui", 1, true) ~= nil
		) then
		return FRAGMENT_CLIENT_GUI_LIFECYCLE
	end

	-- 9. Standard Fallback Context
	return FRAGMENT_STANDARD_ENVIRONMENT
end

return table_freeze(ContextCatalog)
