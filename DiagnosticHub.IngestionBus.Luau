--!strict
-- [[ INGESTION BUS ]] --
-- Central collector and normalizer for all diagnostic telemetry across
-- LogService, ScriptContext, Watchdogs, and the ClientDebugger UnreliableRemoteEvent.

-- [[ SERVICES ]] --
local LogService = game:GetService("LogService")
local ScriptContext = game:GetService("ScriptContext")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Types)
local Watchdogs = require(script.Parent.Watchdogs)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local os_time = os.time
local os_clock = os.clock
local string_sub = string.sub
local string_format = string.format
local table_insert = table.insert
local table_clear = table.clear
local table_freeze = table.freeze
local task_spawn = task.spawn
local task_delay = task.delay
local task_cancel = task.cancel
local coroutine_status = coroutine.status
local tostring = tostring
local typeof = typeof

-- [[ CONFIGURATION CONSTANTS ]] --
local MAX_MESSAGE_LENGTH: number = 2048
local MAX_STACK_LENGTH: number = 8192
local DEDUPLICATION_WINDOW_SECONDS: number = 0.25
local REMOTE_RESOLVER_MAX_ATTEMPTS: number = 10
local REMOTE_RESOLVER_BASE_INTERVAL: number = 0.5
local BURST_RATE_LIMIT_PER_SECOND: number = 60

-- [[ MODULE STATE ]] --
local IngestionBus = {}

type SignalConsumer = (signal: Types.RawLogSignal) -> ()

local consumers: { SignalConsumer } = {}
local activeConnections: { RBXScriptConnection } = {}
local resolverThread: thread? = nil
local isInitialized: boolean = false

local recentErrorsCache: { [string]: number } = {}
local signalsProcessedInCurrentWindow: number = 0
local currentRateLimitWindow: number = 0

-- [[ SECTION 1: UTILITY & RATE LIMITING ]] --
local function sanitizeString(rawInput: unknown, maxLength: number): string
	local text: string

	if typeof(rawInput) == "string" then
		text = rawInput :: string
	else
		text = tostring(rawInput)
	end

	if #text > maxLength then
		return string_sub(text, 1, maxLength) .. " [TRUNCATED]"
	end

	return text
end

local function isDuplicate(message: string): boolean
	local now = os_clock()
	local lastSeen = recentErrorsCache[message]

	for cachedMsg, timestamp in recentErrorsCache do
		if (now - timestamp) > DEDUPLICATION_WINDOW_SECONDS then
			recentErrorsCache[cachedMsg] = nil
		end
	end

	if lastSeen and (now - lastSeen) < DEDUPLICATION_WINDOW_SECONDS then
		return true
	end

	recentErrorsCache[message] = now
	return false
end

local function isRateLimited(): boolean
	local currentSecond = os_time()
	if currentSecond ~= currentRateLimitWindow then
		currentRateLimitWindow = currentSecond
		signalsProcessedInCurrentWindow = 0
	end

	signalsProcessedInCurrentWindow += 1
	return signalsProcessedInCurrentWindow > BURST_RATE_LIMIT_PER_SECOND
end

-- [[ SECTION 2: SIGNAL DISPATCH ]] --
function IngestionBus.Ingest(signal: Types.RawLogSignal)
	if isRateLimited() then
		Watchdogs.PushBreadcrumb("INGESTION", "Burst rate limit reached; dropping signal")
		return
	end

	for i = 1, #consumers do
		local consumer = consumers[i]
		task_spawn(consumer, signal)
	end
end

function IngestionBus.RegisterConsumer(consumer: SignalConsumer)
	table_insert(consumers, consumer)
end

-- [[ SECTION 3: RESILIENT UNRELIABLE REMOTE RESOLVER ]] --
--[[
	Locates ClientDebugger returning a generic Instance to avoid union-type errors.
]]
local function locateClientDebuggerRemote(): Instance?
	local hub: Instance? = script.Parent
	local bootstrap: Instance? = if hub then hub.Parent else nil

	-- 1. Check local bootstrap dependencies hierarchy
	if bootstrap then
		local dependencies = bootstrap:FindFirstChild("Dependencies")
		if dependencies then
			local scriptSignals = dependencies:FindFirstChild("ScriptSignals")
			if scriptSignals then
				local debugging = scriptSignals:FindFirstChild("Debugging")
				if debugging then
					local remotes = debugging:FindFirstChild("Remotes")
					if remotes then
						local remote = remotes:FindFirstChild("ClientDebugger")
						if remote and (remote:IsA("UnreliableRemoteEvent") or remote:IsA("RemoteEvent")) then
							return remote
						end
					end
				end
			end
		end
	end

	-- 2. Check auto-provisioned tree in ReplicatedStorage
	local replicatedSignals = ReplicatedStorage:FindFirstChild("ScriptSignals")
	if replicatedSignals then
		local debugging = replicatedSignals:FindFirstChild("Debugging")
		if debugging then
			local remotes = debugging:FindFirstChild("Remotes")
			if remotes then
				local remote = remotes:FindFirstChild("ClientDebugger")
				if remote and (remote:IsA("UnreliableRemoteEvent") or remote:IsA("RemoteEvent")) then
					return remote
				end
			end
		end
	end

	-- 3. Check direct ReplicatedStorage Remotes folder
	local directRemotes = ReplicatedStorage:FindFirstChild("Remotes")
	if directRemotes then
		local remote = directRemotes:FindFirstChild("ClientDebugger")
		if remote and (remote:IsA("UnreliableRemoteEvent") or remote:IsA("RemoteEvent")) then
			return remote
		end
	end

	return nil
end

--[[
	Narrows the remote instance to concrete types before connecting,
	preventing Luau 'Cannot call a value of the union type' errors.
]]
local function connectRemoteEvent(
	targetRemote: Instance,
	handler: (player: Player, payload: unknown) -> ()
): RBXScriptConnection?
	if targetRemote:IsA("UnreliableRemoteEvent") then
		return targetRemote.OnServerEvent:Connect(handler)
	elseif targetRemote:IsA("RemoteEvent") then
		return targetRemote.OnServerEvent:Connect(handler)
	end
	return nil
end

local function hookClientDebuggerRemoteAsync()
	resolverThread = task_spawn(function()
		local attempts = 0
		local remote: Instance? = nil

		while attempts < REMOTE_RESOLVER_MAX_ATTEMPTS do
			attempts += 1
			remote = locateClientDebuggerRemote()

			if remote then
				break
			end

			local delayTime = REMOTE_RESOLVER_BASE_INTERVAL * (1.2 ^ attempts)
			task.wait(delayTime)
		end

		if not remote then
			Watchdogs.PushBreadcrumb(
				"INGESTION",
				string_format("Failed to resolve ClientDebugger network remote after %d attempts", attempts)
			)
			return
		end

		local conn = connectRemoteEvent(remote, function(player: Player, payload: unknown)
			if typeof(payload) ~= "table" then
				return
			end

			local data = payload :: { [string]: unknown }
			local rawMessage = sanitizeString(data.Message, MAX_MESSAGE_LENGTH)
			local rawStack = sanitizeString(data.RawStack, MAX_STACK_LENGTH)
			local severityStr = tostring(data.Severity)

			local severity: Types.Severity = if severityStr == "ERROR" then "ERROR" else "WARNING"

			local signal: Types.RawLogSignal = {
				Message = rawMessage,
				RawStack = rawStack,
				Severity = severity,
				ScriptContext = nil,
				Timestamp = os_time(),
				ClientPlayer = player,
			}

			IngestionBus.Ingest(signal)
		end)

		if conn then
			table_insert(activeConnections, conn)
			Watchdogs.PushBreadcrumb("INGESTION", "ClientDebugger remote connected successfully via " .. remote.ClassName)
		end
	end)
end

-- [[ SECTION 4: ENGINE LOG LISTENERS ]] --
local function hookScriptContext()
	local conn = ScriptContext.Error:Connect(function(message: string, stack: string, scriptInstance: Instance)
		local sanitizedMessage = sanitizeString(message, MAX_MESSAGE_LENGTH)
		isDuplicate(sanitizedMessage)

		local scriptContainer: LuaSourceContainer? = nil
		if scriptInstance and scriptInstance:IsA("LuaSourceContainer") then
			scriptContainer = scriptInstance :: LuaSourceContainer
		end

		local signal: Types.RawLogSignal = {
			Message = sanitizedMessage,
			RawStack = sanitizeString(stack, MAX_STACK_LENGTH),
			Severity = "ERROR",
			ScriptContext = scriptContainer,
			Timestamp = os_time(),
			ClientPlayer = nil,
		}

		IngestionBus.Ingest(signal)
	end)

	table_insert(activeConnections, conn)
end

local function hookLogService()
	local conn = LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
		if messageType ~= Enum.MessageType.MessageWarning and messageType ~= Enum.MessageType.MessageError then
			return
		end

		local sanitizedMessage = sanitizeString(message, MAX_MESSAGE_LENGTH)

		if isDuplicate(sanitizedMessage) then
			return
		end

		local severity: Types.Severity = if messageType == Enum.MessageType.MessageError then "ERROR" else "WARNING"

		local signal: Types.RawLogSignal = {
			Message = sanitizedMessage,
			RawStack = "",
			Severity = severity,
			ScriptContext = nil,
			Timestamp = os_time(),
			ClientPlayer = nil,
		}

		IngestionBus.Ingest(signal)
	end)

	table_insert(activeConnections, conn)
end

local function hookWatchdogs()
	Watchdogs.RegisterSink(function(severity: Types.Severity, message: string, rawStack: string)
		local signal: Types.RawLogSignal = {
			Message = sanitizeString(message, MAX_MESSAGE_LENGTH),
			RawStack = sanitizeString(rawStack, MAX_STACK_LENGTH),
			Severity = severity,
			ScriptContext = nil,
			Timestamp = os_time(),
			ClientPlayer = nil,
		}

		IngestionBus.Ingest(signal)
	end)
end

-- [[ SECTION 5: LIFECYCLE MANAGEMENT ]] --
function IngestionBus.Initialize()
	if isInitialized then
		return
	end
	isInitialized = true

	hookScriptContext()
	hookLogService()
	hookWatchdogs()
	hookClientDebuggerRemoteAsync()

	local synthesizerModule = script.Parent:FindFirstChild("Synthesizer")
	if synthesizerModule and synthesizerModule:IsA("ModuleScript") then
		local ok, Synthesizer: any = pcall(require, synthesizerModule)
		if ok and typeof(Synthesizer) == "table" and typeof(Synthesizer.ProcessSignal) == "function" then
			IngestionBus.RegisterConsumer(function(signal: Types.RawLogSignal)
				Synthesizer.ProcessSignal(signal)
			end)
		end
	end
end

function IngestionBus.Decommission()
	if not isInitialized then
		return
	end
	isInitialized = false

	if resolverThread and coroutine_status(resolverThread) ~= "dead" then
		task_cancel(resolverThread)
		resolverThread = nil
	end

	for i = 1, #activeConnections do
		activeConnections[i]:Disconnect()
	end
	table_clear(activeConnections)
	table_clear(consumers)
	table_clear(recentErrorsCache)
end

return table_freeze(IngestionBus)
