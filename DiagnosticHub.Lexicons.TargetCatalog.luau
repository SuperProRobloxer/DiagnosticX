--!strict
-- [[ TARGET CATALOG: ENHANCED TOKEN MATCHER ]] --
-- Extracts tokens from syntax errors, method invocations, missing member references,
-- and asynchronous yield sentries with zero-allocation pre-compiled fragment dispatching.

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Parent.Types)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local string_match = string.match
local string_upper = string.upper
local string_gsub = string.gsub
local table_freeze = table.freeze

-- [[ TYPE DEFINITIONS ]] --
export type TargetCatalog = {
	Match: (message: string) -> Types.TargetFragment,
}

local TargetCatalog = {}

-- Pre-allocated fallback fragment returned when no identifier can be resolved
local UNKNOWN_TARGET_FRAGMENT: Types.TargetFragment = {
	ID = "UNKNOWN_ENTITY",
	Token = "UnknownSymbol",
	Classification = "Unresolved Contextual Target",
	Weight = 10,
}

-- [[ SECTION 1: STATIC PRE-COMPILED TARGET REGISTRY ]] --
-- Initial raw taxonomy definitions compiled once into immutable TargetFragments
local RAW_TARGETS: { [string]: { Classification: string, Weight: number } } = {
	-- Character & Rig Assemblies (R6 / R15 / Custom)
	["HumanoidRootPart"] = { Classification = "Spatial Physics Node / Rig Assembly", Weight = 30 },
	["Humanoid"] = { Classification = "Character Controller Node", Weight = 30 },
	["Head"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["UpperTorso"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["LowerTorso"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["Torso"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["LeftUpperArm"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["RightUpperArm"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["LeftLowerArm"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["RightLowerArm"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["LeftHand"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["RightHand"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["LeftUpperLeg"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["RightUpperLeg"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["LeftLowerLeg"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["RightLowerLeg"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["LeftFoot"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["RightFoot"] = { Classification = "Kinematic Rig Assembly Part", Weight = 30 },
	["Character"] = { Classification = "Player Avatar Model Container", Weight = 30 },

	-- Network Authority & RPC Endpoints
	["FireServer"] = { Classification = "Client-to-Server Remote Dispatcher", Weight = 30 },
	["FireClient"] = { Classification = "Server-to-Client Remote Dispatcher", Weight = 30 },
	["FireAllClients"] = { Classification = "Server-to-All-Clients Remote Broadcast", Weight = 30 },
	["InvokeServer"] = { Classification = "Two-Way Client-to-Server RPC", Weight = 30 },
	["InvokeClient"] = { Classification = "Two-Way Server-to-Client RPC", Weight = 30 },
	["OnServerEvent"] = { Classification = "Server-Side Remote Signal Listener", Weight = 30 },
	["OnClientEvent"] = { Classification = "Client-Side Remote Signal Listener", Weight = 30 },
	["OnServerInvoke"] = { Classification = "Server-Side RPC Callback Binding", Weight = 30 },
	["OnClientInvoke"] = { Classification = "Client-Side RPC Callback Binding", Weight = 30 },
	["SetNetworkOwner"] = { Classification = "Physics Network Authority Assignment", Weight = 35 },
	["SetNetworkOwnershipAuto"] = { Classification = "Automatic Network Ownership Evaluator", Weight = 35 },

	-- Cloud Persistence & DataStores
	["GetAsync"] = { Classification = "DataStore Read Operation", Weight = 30 },
	["SetAsync"] = { Classification = "DataStore Write Operation", Weight = 30 },
	["UpdateAsync"] = { Classification = "DataStore Transactional Mutator", Weight = 30 },
	["IncrementAsync"] = { Classification = "DataStore Atomic Counter Operation", Weight = 30 },
	["RemoveAsync"] = { Classification = "DataStore Key Invalidation", Weight = 30 },
	["ListKeysAsync"] = { Classification = "DataStore Enumeration Query", Weight = 30 },

	-- Spatial Math, Transforms & Assemblies
	["CFrame"] = { Classification = "CoordinateFrame Transform Struct", Weight = 30 },
	["Position"] = { Classification = "Vector3 Spatial Coordinate", Weight = 30 },
	["Orientation"] = { Classification = "Euler Angle Spatial Rotation", Weight = 30 },
	["Size"] = { Classification = "Vector3 Geometric Extents", Weight = 30 },
	["AssemblyLinearVelocity"] = { Classification = "Rigid Body Momentum State", Weight = 30 },
	["AssemblyAngularVelocity"] = { Classification = "Rigid Body Rotational State", Weight = 30 },
	["AssemblyMass"] = { Classification = "Physical Mass Evaluator", Weight = 30 },
	["PivotTo"] = { Classification = "Atomic Model Transform Matrix", Weight = 30 },
	["GetPivot"] = { Classification = "Atomic Model Pivot Coordinate", Weight = 30 },
	["WeldConstraint"] = { Classification = "Rigid Physics Constraint", Weight = 30 },
	["Motor6D"] = { Classification = "Kinematic Animated Transform Joint", Weight = 30 },
	["Attachment"] = { Classification = "Spatial Constraint Anchor", Weight = 30 },

	-- Instance Hierarchy Operations
	["Destroy"] = { Classification = "Instance Lifecycle Deletion", Weight = 30 },
	["Clone"] = { Classification = "Instance Deep Duplication", Weight = 30 },
	["WaitForChild"] = { Classification = "Asynchronous Replication Sentry", Weight = 30 },
	["FindFirstChild"] = { Classification = "Synchronous Tree Query", Weight = 30 },
	["FindFirstChildWhichIsA"] = { Classification = "Class Hierarchy Tree Query", Weight = 30 },
	["FindFirstChildOfClass"] = { Classification = "Exact Class Tree Query", Weight = 30 },
	["GetChildren"] = { Classification = "Immediate Children Array Query", Weight = 30 },
	["GetDescendants"] = { Classification = "Deep Subtree Traversal Query", Weight = 30 },
	["GetPropertyChangedSignal"] = { Classification = "Property Event Binding", Weight = 30 },
	["Parent"] = { Classification = "DataModel Hierarchy Placement", Weight = 30 },

	-- Tween & Animation Systems
	["Animator"] = { Classification = "Kinematic Animation Evaluator", Weight = 30 },
	["AnimationTrack"] = { Classification = "Track Playback Controller", Weight = 30 },
	["Play"] = { Classification = "Animation/Audio Playback Trigger", Weight = 30 },
	["Stop"] = { Classification = "Animation/Audio Cessation Trigger", Weight = 30 },
	["AdjustSpeed"] = { Classification = "Animation Playback Scale Mutator", Weight = 30 },
	["Create"] = { Classification = "Tween Instance Constructor", Weight = 30 },

	-- Core Services & Containers
	["Workspace"] = { Classification = "Spatial DataModel Root Container", Weight = 30 },
	["Players"] = { Classification = "Player Management Service", Weight = 30 },
	["ReplicatedStorage"] = { Classification = "Network Replicated Shared Storage", Weight = 30 },
	["ServerScriptService"] = { Classification = "Server-Authoritative Script Container", Weight = 30 },
	["ServerStorage"] = { Classification = "Server-Exclusive Asset Storage", Weight = 30 },
	["HttpService"] = { Classification = "External Network Gateway Service", Weight = 30 },
	["DataStoreService"] = { Classification = "Cloud Persistence Storage Gateway", Weight = 30 },
	["MarketplaceService"] = { Classification = "Monetization & Product Transaction Gateway", Weight = 30 },
	["TweenService"] = { Classification = "Property Interpolation Service", Weight = 30 },
	["RunService"] = { Classification = "Engine Execution Step Scheduler", Weight = 30 },
	["TeleportService"] = { Classification = "Inter-Experience Player Transport Gateway", Weight = 30 },
	["PlayerGui"] = { Classification = "Client User Interface Container", Weight = 30 },
	["StarterGui"] = { Classification = "Default Client User Interface Template", Weight = 30 },
	["LocalPlayer"] = { Classification = "Client Session Player Singleton", Weight = 30 },

	-- Modern Engine Audio API
	["AudioEmitter"] = { Classification = "Spatialized Audio Source", Weight = 30 },
	["AudioListener"] = { Classification = "Spatialized Audio Receiver", Weight = 30 },
	["AudioPlayer"] = { Classification = "Audio Stream Asset Provider", Weight = 30 },
	["Wire"] = { Classification = "Audio Node Data Routing Channel", Weight = 30 },

	-- Luau Language & Scheduler Primitives
	["buffer"] = { Classification = "Low-Level Byte Memory Struct", Weight = 30 },
	["task"] = { Classification = "Engine Task Scheduler API", Weight = 30 },
	["pairs"] = { Classification = "Standard Table Iterator", Weight = 30 },
	["ipairs"] = { Classification = "Array Table Iterator", Weight = 30 },
	["random"] = { Classification = "Math Random Function", Weight = 30 },
	["insert"] = { Classification = "Table Insert Method", Weight = 30 },
	["synchronize"] = { Classification = "Parallel Luau Actor Sync Barrier", Weight = 35 },
	["desynchronize"] = { Classification = "Parallel Luau Actor Desync Barrier", Weight = 35 },
}

-- Pre-compile into immutable, zero-allocation TargetFragment records
local COMPILED_TARGETS: { [string]: Types.TargetFragment } = {}
for token, def in RAW_TARGETS do
	COMPILED_TARGETS[token] = {
		ID = string_upper(token),
		Token = token,
		Classification = def.Classification,
		Weight = def.Weight,
	}
end
table_freeze(COMPILED_TARGETS)

-- [[ SECTION 2: UTILITY FUNCTIONS ]] --
--[[
	Trims surrounding quotes and boundary whitespace from extracted tokens.
]]
local function cleanToken(rawToken: string?): string?
	if not rawToken or rawToken == "" then
		return nil
	end

	local cleaned = string_gsub(rawToken, "^%s*['\"]?", "")
	cleaned = string_gsub(cleaned, "['\"]?%s*$", "")

	if cleaned == "" or cleaned == "nil" or cleaned == "unknown" or cleaned == "true" or cleaned == "false" then
		return nil
	end

	return cleaned
end

-- [[ SECTION 3: TOKEN EXTRACTION & RESOLUTION ]] --
--[[
	Parses incoming raw error messages through prioritized regex extractors.
	Returns pre-compiled TargetFragments for recognized engine targets, or constructs
	dynamic custom records for game-defined variables.
]]
function TargetCatalog.Match(message: string): Types.TargetFragment
	local candidateToken: string? = nil

	-- 1. Asynchronous replication wait sentries: WaitForChild("Target")
	candidateToken = string_match(message, "WaitForChild%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")

	-- 2. Missing member references: Target is not a valid member of Parent "Container"
	if not candidateToken then
		candidateToken = string_match(message, "([%w_%s]+)%s+is not a valid member of")
	end

	-- 3. Dereference on nil/primitive: attempt to index nil with 'Target'
	if not candidateToken then
		candidateToken = string_match(message, "attempt to index .- with%s+['\"]([^'\"]+)['\"]")
	end

	-- 4. Invocations on nil: attempt to call method 'Target' / field 'Target'
	if not candidateToken then
		candidateToken = string_match(message, "attempt to call method%s+['\"]([^'\"]+)['\"]")
			or string_match(message, "attempt to call field%s+['\"]([^'\"]+)['\"]")
	end

	-- 5. Engine method parameter errors: bad argument # to 'Target'
	if not candidateToken then
		candidateToken = string_match(message, "bad argument #%d+ to%s+['\"]([^'\"]+)['\"]")
	end

	-- 6. Specific engine authority constraint invocations
	if not candidateToken then
		candidateToken = string_match(message, "The Part passed to%s+([%w_]+)%s+")
			or string_match(message, "([%w_]+)%s+can only be called from")
			or string_match(message, "([%w_]+)%s+cannot be called without a player")
			or string_match(message, "([%w_]+):%s+player argument must be a Player")
	end

	-- 7. Fallback: Colon method call or standalone quoted symbol
	if not candidateToken then
		candidateToken = string_match(message, ":([%w_]+)%(")
			or string_match(message, "['\"]([%w_%s]+)['\"]")
	end

	local resolvedToken = cleanToken(candidateToken)

	if resolvedToken then
		-- Fast-path: Pre-compiled static fragment lookup
		local precompiled = COMPILED_TARGETS[resolvedToken]
		if precompiled then
			return precompiled
		end

		-- Dynamic path: Custom project token
		return {
			ID = string_upper(resolvedToken),
			Token = resolvedToken,
			Classification = "Dynamic Script Member / Identifier",
			Weight = 20,
		}
	end

	return UNKNOWN_TARGET_FRAGMENT
end

return table_freeze(TargetCatalog)
