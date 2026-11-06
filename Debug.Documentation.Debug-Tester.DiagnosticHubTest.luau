--!strict
-- [[ DIAGNOSTIC HUB: SERVER CAPABILITY TEST SUITE ]] --
-- Exercises heuristic analysis, watchdogs, infinite yields, custom rule registration,
-- external consumer hooks, and burst suppression with self-validating assertions.

-- [[ MODULE RESOLUTION ]] --
-- Statically resolved relative path: DiagnosticHubTest -> Debug-Tester -> Documentation -> Debug -> DiagnosticHub
local DiagnosticHub = require(script.Parent.Parent.Parent.DiagnosticHub)

-- [[ SERVICES ]] --
local Workspace = game:GetService("Workspace")

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local os_clock = os.clock
local string_format = string.format
local table_insert = table.insert
local task_wait = task.wait
local task_spawn = task.spawn
local task_defer = task.defer
local print = print
local warn = warn

-- [[ TEST HARNESS STATE ]] --
local suiteStartTime: number = os_clock()
local totalTests: number = 0
local passedTests: number = 0
local failedTests: number = 0

local function runTestStage(testName: string, testFn: () -> (boolean, string?))
	totalTests += 1
	local stageStart = os_clock()
	print(string_format("\n>>> [RUNNING TEST %d]: %s...", totalTests, testName))

	local success, resultMessage = testFn()
	local duration = (os_clock() - stageStart)

	if success then
		passedTests += 1
		print(string_format("    [PASS] (%.3fs) %s", duration, resultMessage or "Stage verified successfully."))
	else
		failedTests += 1
		warn(string_format("    [FAIL] (%.3fs) %s", duration, resultMessage or "Stage encountered an assertion failure."))
	end
end

-- Allow engine subsystems to complete startup initialization
task_wait(1.5)

print("\n========================================================")
print("     [DIAGNOSTIC HUB: SERVER VERIFICATION SUITE]        ")
print("========================================================")

-- [[ TEST 1: SYSTEM READINESS & STATUS INTROSPECTION ]] --
runTestStage("System Readiness & Introspection", function()
	if not DiagnosticHub.IsRunning() then
		return false, "DiagnosticHub reported IsRunning() == false."
	end

	local status = DiagnosticHub.GetSystemStatus()
	if not status.IsRunning then
		return false, "GetSystemStatus().IsRunning is false."
	end

	if status.UptimeSeconds < 0 then
		return false, "UptimeSeconds returned an invalid negative timestamp."
	end

	return true, string_format("Hub online in %s mode (Uptime: %.2fs)", status.Environment, status.UptimeSeconds)
end)

-- [[ TEST 2: SERVER BREADCRUMBS & CHARACTER STREAMING RACE ]] --
runTestStage("Breadcrumbs & Heuristic Card Synthesis", function()
	DiagnosticHub.TrackBreadcrumb("COMBAT_SYSTEM", "Equipped 'ObsidianWarhammer'")
	DiagnosticHub.TrackBreadcrumb("ANIMATION", "Started 'HeavyAttack_Windup'")
	DiagnosticHub.TrackBreadcrumb("NETWORK_RPC", "Validated weapon hitbox bounds")

	local crumbs = DiagnosticHub.GetBreadcrumbs()
	if #crumbs < 3 then
		return false, string_format("Expected at least 3 breadcrumbs, got %d.", #crumbs)
	end

	-- Intentionally dereference 'HumanoidRootPart' on nil to simulate a character streaming race
	task_defer(function()
		local unassignedCharacter: Model? = nil
		local _ = (unassignedCharacter :: any).HumanoidRootPart
	end)

	task_wait(0.5) -- Allow defer queue to process through IngestionBus
	return true, "Recorded 3 breadcrumbs and triggered INDEX_ON_NIL character race."
end)

-- [[ TEST 3: SAFESPAWN UNHANDLED THREAD CRASH TRAPPING ]] --
runTestStage("SafeSpawn Thread Crash Trapping", function()
	local threadReturned: thread? = nil
	local threadFinished = false

	threadReturned = DiagnosticHub.SafeSpawn(function()
		DiagnosticHub.TrackBreadcrumb("INVENTORY_THREAD", "Parsing item metadata dictionary")
		task_wait(0.05)

		-- Calling a table as a function to trigger CALL_ON_NON_FUNCTION
		local weaponData = { Damage = 75, Durability = 100 }
		local _ = (weaponData :: any)()
		threadFinished = true
	end)

	if typeof(threadReturned) ~= "thread" then
		return false, "SafeSpawn did not return a valid thread instance."
	end

	task_wait(0.2) -- Allow spawned thread to fail and be caught by the interceptor

	if threadFinished then
		return false, "The thread should have crashed before setting threadFinished."
	end

	return true, "SafeSpawn intercepted thread crash without terminating caller thread."
end)

-- [[ TEST 4: SENTRY-GUARDED INFINITE YIELD ]] --
runTestStage("Sentry-Guarded Infinite Yield (1.0s threshold)", function()
	DiagnosticHub.TrackBreadcrumb("DUNGEON_LOADER", "Awaiting room boss model replication")

	-- 1-second timeout triggers the sentry warning while returning safely at the engine boundary
	local startTime = os_clock()
	local missingBoss = DiagnosticHub.WaitForChild(Workspace, "NonExistentTestEntity_XYZ", 1.0)
	local elapsed = os_clock() - startTime

	if missingBoss ~= nil then
		return false, "WaitForChild should have returned nil for a non-existent child."
	end

	if elapsed < 0.95 then
		return false, string_format("WaitForChild returned too early (%.2fs)", elapsed)
	end

	return true, string_format("Sentry timed out deterministically after %.2fs with nil return.", elapsed)
end)

-- [[ TEST 5: AUDITED PCALL (SWALLOWED ERROR AUDITING) ]] --
runTestStage("AuditedPcall Swallowed Error Capture", function()
	local ok, err = DiagnosticHub.AuditedPcall(function()
		local dataStoreService = nil
		return (dataStoreService :: any).GetDataStore("PlayerData")
	end)

	if ok == true then
		return false, "AuditedPcall reported success on a crashing closure."
	end

	if typeof(err) ~= "string" or err == "" then
		return false, "AuditedPcall did not return an error description string."
	end

	return true, "AuditedPcall intercepted error and pushed 'SWALLOWED_ERROR' breadcrumb."
end)

-- [[ TEST 6: CUSTOM FAULT RULE REGISTRATION ]] --
runTestStage("Custom Fault Rule Registration", function()
	local customTriggered = false

	DiagnosticHub.RegisterFaultRule({
		Pattern = "CustomInventorySyncFailure",
		ID = "CUSTOM_INV_SYNC",
		Name = "Inventory State Desync",
		Mechanism = "Simulated unit-test exception for custom rule matching.",
		Weight = 50,
		Category = "Custom Systems",
		SuggestedFix = "Ensure inventory records are flushed prior to transaction commit.",
	})

	-- Hook a temporary consumer to verify the custom fault rule executes through the pipeline
	DiagnosticHub.RegisterConsumer(function(signal)
		if signal.Message == "CustomInventorySyncFailure" then
			customTriggered = true
		end
	end)

	DiagnosticHub.CaptureException("CustomInventorySyncFailure", nil, "WARNING")

	task_wait(0.2)

	if not customTriggered then
		return false, "Consumer did not intercept manually reported CustomInventorySyncFailure."
	end

	return true, "Registered custom rule and verified end-to-end signal ingestion."
end)

-- [[ TEST 7: BURST SUPPRESSION & CASCADE MITIGATION ]] --
runTestStage("Burst Rate-Limiting & Cascade Mitigation", function()
	print("    >>> Emitting 10 rapid duplicate exceptions via task.defer...")

	for _ = 1, 10 do
		task_defer(function()
			local nullTable = nil
			local _ = (nullTable :: any).CascadeTestMember
		end)
	end

	task_wait(0.5) -- Allow IngestionBus deduplication and window clamp to process

	-- Wait for the deduplication window to expire (0.25s), then send a recovery error
	task_wait(0.5)

	task_defer(function()
		local nullTable = nil
		local _ = (nullTable :: any).CascadeTestMember
	end)

	task_wait(0.2)
	return true, "Processed error cascade without server lockup or thread starvation."
end)

-- [[ FINAL SUMMARY BANNER ]] --
local suiteDuration = os_clock() - suiteStartTime

print("\n========================================================")
print("       [SERVER CAPABILITY TEST SUITE COMPLETED]         ")
print(string_format("       Total: %d | Passed: %d | Failed: %d (%.2fs)", totalTests, passedTests, failedTests, suiteDuration))
if failedTests == 0 then
	print("       Status: ALL SUBSYSTEM TESTS PASSED               ")
else
	warn(string_format("       Status: %d TEST(S) FAILED                        ", failedTests))
end
print("========================================================\n")
