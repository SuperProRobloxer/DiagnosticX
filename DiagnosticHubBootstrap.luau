--!strict
-- [[ DIAGNOSTIC HUB BOOTSTRAPPER: AUTO-PROVISIONER & SUBSYSTEM LOADER ]] --
-- Automatically provisions the UnreliableRemoteEvent network tree into ReplicatedStorage,
-- unpacks DiagnosticSatellite into StarterPlayerScripts, and ignites DiagnosticHub.

-- [[ SERVICES ]] --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local string_format = string.format
local tostring = tostring
local warn = warn
local print = print

-- [[ CONFIGURATION & ATTRIBUTES ]] --
local DEFAULT_AUTO_PROVISION: boolean = true

local autoProvisionAttribute = script:GetAttribute("AutoProvision")
local AUTO_PROVISION_DEPENDENCIES: boolean = if autoProvisionAttribute ~= nil
	then (autoProvisionAttribute == true)
	else DEFAULT_AUTO_PROVISION

-- [[ SECTION 1: DIRECTORY UTILITIES ]] --
--[[
	Ensures a Folder exists under a parent container idempotently.
]]
local function ensureFolder(parent: Instance, folderName: string): Folder
	local existing = parent:FindFirstChild(folderName)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = folderName
	newFolder.Parent = parent
	return newFolder
end

--[[
	Locates an instance recursively across spelling variations.
]]
local function findSatelliteSource(container: Instance): LocalScript?
	local satellite = container:FindFirstChild("DiagnosticSatellite", true)
		or container:FindFirstChild("DiagnosticSattelite", true)

	if satellite and satellite:IsA("LocalScript") then
		return satellite
	end

	return nil
end

-- [[ SECTION 2: IDEMPOTENT DEPENDENCY UNPACKER ]] --
--[[
	Provisions ReplicatedStorage.ScriptSignals.Debugging.Remotes.ClientDebugger
	(UnreliableRemoteEvent) and installs DiagnosticSatellite into StarterPlayerScripts.
]]
local function provisionDependencies()
	local dependenciesFolder = script:FindFirstChild("Dependencies")
	if not dependenciesFolder then
		warn("[DiagnosticHubBootstrap]: Auto-provisioning is enabled, but no 'Dependencies' folder was found inside the bootstrapper.")
		return
	end

	-- 1. Provision UnreliableRemoteEvent into ReplicatedStorage/ScriptSignals/Debugging/Remotes
	local targetScriptSignals = ensureFolder(ReplicatedStorage, "ScriptSignals")
	local targetDebugging = ensureFolder(targetScriptSignals, "Debugging")
	local targetRemotes = ensureFolder(targetDebugging, "Remotes")

	if not targetRemotes:FindFirstChild("ClientDebugger") then
		local sourceRemote = dependenciesFolder:FindFirstChild("ClientDebugger", true)
		if sourceRemote and (sourceRemote:IsA("UnreliableRemoteEvent") or sourceRemote:IsA("RemoteEvent")) then
			local remoteClone = sourceRemote:Clone()
			remoteClone.Parent = targetRemotes
		else
			-- Fallback: Instantiate an UnreliableRemoteEvent if not present in Dependencies
			local newRemote = Instance.new("UnreliableRemoteEvent")
			newRemote.Name = "ClientDebugger"
			newRemote.Parent = targetRemotes
		end
	end

	-- 2. Provision Client Satellite into StarterPlayerScripts
	local sourceSatellite = findSatelliteSource(dependenciesFolder)
	if sourceSatellite then
		local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
		if starterPlayerScripts then
			local existingSatellite = starterPlayerScripts:FindFirstChild("DiagnosticSatellite")
				or starterPlayerScripts:FindFirstChild("DiagnosticSattelite")

			if not existingSatellite then
				local satelliteClone = sourceSatellite:Clone()
				satelliteClone.Name = "DiagnosticSatellite" -- Normalize name to standard spelling
				satelliteClone.Parent = starterPlayerScripts

				-- Hot-Join Redundancy: Inject into existing players in Studio Play Solo
				local activePlayers = Players:GetPlayers()
				for i = 1, #activePlayers do
					local player = activePlayers[i]
					local playerScripts = player:FindFirstChild("PlayerScripts")
					if playerScripts then
						local hasSatellite = playerScripts:FindFirstChild("DiagnosticSatellite")
							or playerScripts:FindFirstChild("DiagnosticSattelite")

						if not hasSatellite then
							local runtimeClone = sourceSatellite:Clone()
							runtimeClone.Name = "DiagnosticSatellite"
							runtimeClone.Parent = playerScripts
						end
					end
				end
			end
		end
	end
end

-- Execute auto-provisioning
if AUTO_PROVISION_DEPENDENCIES then
	provisionDependencies()
end

-- [[ SECTION 3: SUBSYSTEM IGNITION ]] --
--[[
	Resolves DiagnosticHub dynamically across both child and sibling layouts,
	using an untyped require call to eliminate Luau AST path analysis errors.
]]
local function resolveDiagnosticHub(): ModuleScript
	-- Check child of DiagnosticHubBootstrap (as displayed in latest Explorer view)
	local child = script:FindFirstChild("DiagnosticHub")
	if child and child:IsA("ModuleScript") then
		return child
	end

	-- Check sibling under ServerScriptService.Debug
	local sibling = script.Parent and script.Parent:FindFirstChild("DiagnosticHub")
	if sibling and sibling:IsA("ModuleScript") then
		return sibling
	end

	error(
		string_format(
			"[DiagnosticHubBootstrap]: Failed to locate 'DiagnosticHub' ModuleScript as a child or sibling of '%s'.",
			script:GetFullName()
		),
		2
	)
end

local hubModule = resolveDiagnosticHub()
-- Bypasses Luau's 'Unknown require: unsupported path' AST restriction for dynamic resolution
local dynamicRequire = require :: (ModuleScript) -> any
local DiagnosticHub = dynamicRequire(hubModule)

-- Expose runtime status attributes
script:SetAttribute("SubsystemActive", true)
script:SetAttribute("AutoSetup", AUTO_PROVISION_DEPENDENCIES)

print(
	string_format(
		"[DiagnosticHub]: Subsystem successfully initialized and listening via '%s'. (AutoSetup = %s)",
		script:GetFullName(),
		tostring(AUTO_PROVISION_DEPENDENCIES)
	)
)
