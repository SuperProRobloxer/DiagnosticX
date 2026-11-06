--!strict
-- [[ WATCHDOGS ]] --
-- Trappers for silent yields, crashed threads, swallowed errors, and circular breadcrumb auditing.

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Types)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local os_time = os.time
local os_date = os.date
local string_format = string.format
local string_sub = string.sub
local table_insert = table.insert
local table_pack = table.pack
local table_unpack = table.unpack
local table_freeze = table.freeze
local table_create = table.create
local debug_traceback = debug.traceback
local task_spawn = task.spawn
local task_delay = task.delay
local task_cancel = task.cancel
local coroutine_running = coroutine.running
local coroutine_status = coroutine.status
local tostring = tostring
local pcall = pcall
local xpcall = xpcall
local error = error

-- [[ TYPE DEFINITIONS ]] --
export type ErrorPayload = {
	Message: string,
	Stack: string,
}

export type Watchdogs = {
	RegisterSink: (sink: (severity: Types.Severity, message: string, rawStack: string) -> ()) -> (),
	PushBreadcrumb: (category: string, action: string) -> (),
	GetBreadcrumbs: () -> { string },
	SafeSpawn: (fn: (...any) -> (), ...any) -> thread,
	AuditedPcall: (fn: (...any) -> ...any, ...any) -> (boolean, ...any),
	WaitForChildWithSentry: (parent: Instance, childName: string, timeout: number?) -> Instance?,
}

-- [[ CONFIGURATION CONSTANTS ]] --
local BREADCRUMB_CAPACITY: number = 10
local DEFAULT_TIMEOUT_SECONDS: number = 5.0
local SENTRY_GRACE_PERIOD_SECONDS: number = 1.5

-- [[ MODULE STATE ]] --
local Watchdogs = {}

-- Fixed-capacity circular ring buffer
local breadcrumbs: { Types.BreadcrumbEntry } = table_create(BREADCRUMB_CAPACITY) :: { Types.BreadcrumbEntry }
local breadcrumbHead: number = 1
local breadcrumbCount: number = 0

-- Destination sink for trapped failures and diagnostics
local signalSink: ((severity: Types.Severity, message: string, rawStack: string) -> ())? = nil

-- [[ SECTION 1: CIRCULAR BREADCRUMB BUFFER ]] --
--[[
	Registers the external telemetry sink where trapped errors and watchdog
	diagnostics are dispatched.
]]
function Watchdogs.RegisterSink(sink: (severity: Types.Severity, message: string, rawStack: string) -> ())
	signalSink = sink
end

--[[
	Appends a state breadcrumb to a fixed-size circular ring buffer.
	Reuses existing slot tables once capacity is reached to eliminate GC allocation pressure.
]]
function Watchdogs.PushBreadcrumb(category: string, action: string)
	local existingEntry: Types.BreadcrumbEntry? = breadcrumbs[breadcrumbHead]

	if existingEntry then
		-- In-place mutation avoids GC table churning
		existingEntry.Timestamp = os_time()
		existingEntry.Category = category
		existingEntry.Action = action
	else
		-- Initial buffer slot population
		breadcrumbs[breadcrumbHead] = {
			Timestamp = os_time(),
			Category = category,
			Action = action,
		}
	end

	breadcrumbHead = (breadcrumbHead % BREADCRUMB_CAPACITY) + 1
	if breadcrumbCount < BREADCRUMB_CAPACITY then
		breadcrumbCount += 1
	end
end

--[[
	Dumps all recorded breadcrumbs in chronological order as formatted timestamped strings.
	Pre-allocates the result array to prevent incremental reallocation re-hashing.
]]
function Watchdogs.GetBreadcrumbs(): { string }
	if breadcrumbCount == 0 then
		return {}
	end

	local result: { string } = table_create(breadcrumbCount) :: { string }
	local startIndex: number = if breadcrumbCount < BREADCRUMB_CAPACITY then 1 else breadcrumbHead

	for i = 0, breadcrumbCount - 1 do
		local index = ((startIndex - 1 + i) % BREADCRUMB_CAPACITY) + 1
		local entry = breadcrumbs[index]
		if entry then
			local timeStr = os_date("%H:%M:%S", entry.Timestamp)
			table_insert(result, string_format("[%s] [%s] -> %s", timeStr, entry.Category, entry.Action))
		end
	end

	return result
end

-- [[ SECTION 2: THREAD SUPERVISION (SAFESPAWN) ]] --
--[[
	Spawns a new task-managed thread wrapped in an error interceptor.
	If an unhandled throw occurs, the error message and callstack are captured
	prior to unwinding and safely dispatched to the registered sink.
]]
function Watchdogs.SafeSpawn(fn: (...any) -> (), ...: any): thread
	local args = table_pack(...)

	return task_spawn(function()
		local capturedMessage: string? = nil
		local capturedStack: string? = nil

		-- xpcall captures error data at the throw point before the callstack unwinds
		local ok = xpcall(function()
			fn(table_unpack(args, 1, args.n))
		end, function(err: unknown)
			capturedMessage = tostring(err)
			capturedStack = debug_traceback(nil, 2)
		end)

		if not ok and signalSink then
			local errorMessage = capturedMessage or "Unknown thread execution failure"
			local errorStack = capturedStack or debug_traceback(nil, 2)

			signalSink("ERROR", errorMessage, errorStack)
		end
	end)
end

-- [[ SECTION 3: AUDITED CALL PROTECTION ]] --
--[[
	Executes a function inside a protected call boundary. If it throws, records
	a breadcrumb and logs a warning diagnostic to the sink while preserving all
	native return values (including trailing nils) back to the caller.
]]
function Watchdogs.AuditedPcall(fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table_pack(pcall(fn, ...))
	local success = results[1]

	if not success then
		local errMessage = tostring(results[2])
		Watchdogs.PushBreadcrumb("SWALLOWED_ERROR", string_sub(errMessage, 1, 40))

		if signalSink then
			signalSink(
				"WARNING",
				string_format("[AuditedPcall Swallowed] %s", errMessage),
				debug_traceback(nil, 2)
			)
		end
	end

	return table_unpack(results, 1, results.n)
end

-- [[ SECTION 4: INFINITE YIELD SENTRY ]] --
function Watchdogs.WaitForChildWithSentry(parent: Instance, childName: string, timeout: number?): Instance?
	local callingThread: thread = coroutine_running()
	local resolved: boolean = false
	local sentryThreshold: number = (timeout or DEFAULT_TIMEOUT_SECONDS) + SENTRY_GRACE_PERIOD_SECONDS

	local sentryThread: thread
	sentryThread = task_delay(sentryThreshold, function()
		-- Verify the operation has not finished and the calling thread is still alive
		if not resolved and signalSink and coroutine_status(callingThread) ~= "dead" then
			local syntheticStack = debug_traceback(callingThread, nil, 2)
			signalSink(
				"WARNING",
				string_format(
					"Infinite yield possible on '%s:WaitForChild(\"%s\")'",
					parent:GetFullName(),
					childName
				),
				syntheticStack
			)
		end
	end)

	-- Execute the engine wait inside a guarded boundary to ensure sentry cleanup on crash
	local ok: boolean, result: Instance? = pcall(function()
		if timeout ~= nil then
			return parent:WaitForChild(childName, timeout)
		else
			return parent:WaitForChild(childName)
		end
	end)

	resolved = true

	-- Actively cancel the pending sentry thread to release task scheduler resources
	if coroutine_status(sentryThread) ~= "dead" then
		task_cancel(sentryThread)
	end

	if not ok then
		-- Re-throw the original engine exception at caller level
		error(result, 2)
	end

	return result
end

return table_freeze(Watchdogs) :: Watchdogs
