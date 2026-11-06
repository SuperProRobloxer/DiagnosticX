--!strict
-- [[ OUTPUT COMPOSITOR ]] --
-- Companion card renderer and string compositor formatted for the
-- Roblox Studio command bar, Developer Console, and Output Window.

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Types)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local math_clamp = math.clamp
local math_floor = math.floor
local string_rep = string.rep
local string_sub = string.sub
local string_find = string.find
local string_gmatch = string.gmatch
local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat
local table_freeze = table.freeze
local print = print

-- [[ CONFIGURATION CONSTANTS ]] --
local CARD_WIDTH: number = 68
local BAR_BLOCKS: number = 20
local CONTENT_WIDTH: number = CARD_WIDTH - 20
local DEFAULT_EMPTY_FIELD: string = "[None provided]"

-- Prefixes for aligned multi-line card output
local PREFIX_EMPTY_SPACER: string = "│                   "

-- [[ MODULE DEFINITION ]] --
local OutputCompositor = {}

OutputCompositor.SESSION_SIGNATURE = "[DIAG_CARD_ACTIVE]"

-- [[ SECTION 1: VISUAL UTILITIES & TEXT WRAPPING ]] --
--[[
	Generates an ASCII block progress bar representing confidence percentage.
]]
local function generateProgressBar(confidence: number): string
	local safeConfidence = math_clamp(confidence, 0, 100)
	local filledCount = math_clamp(math_floor((safeConfidence / 100) * BAR_BLOCKS + 0.5), 0, BAR_BLOCKS)
	return string_rep("█", filledCount) .. string_rep("░", BAR_BLOCKS - filledCount)
end

--[[
	Wraps text to a maximum width. Handles explicit newlines, wraps on word
	boundaries, and hard-splits oversized unbroken tokens to preserve card geometry.
]]
local function wrapText(text: string?, maxLen: number): { string }
	if not text or text == "" or not string_find(text, "%S") then
		return { DEFAULT_EMPTY_FIELD }
	end

	local lines: { string } = {}

	for rawLine in string_gmatch(text, "[^\r\n]+") do
		if #rawLine <= maxLen then
			table_insert(lines, rawLine)
		else
			local current = ""

			for word in string_gmatch(rawLine, "%S+") do
				-- If a single word is wider than maxLen, chunk it into slices
				while #word > maxLen do
					if #current > 0 then
						table_insert(lines, current)
						current = ""
					end
					table_insert(lines, string_sub(word, 1, maxLen))
					word = string_sub(word, maxLen + 1)
				end

				if #word == 0 then
					continue
				end

				if #current == 0 then
					current = word
				elseif #current + 1 + #word <= maxLen then
					current = current .. " " .. word
				else
					table_insert(lines, current)
					current = word
				end
			end

			if #current > 0 then
				table_insert(lines, current)
			end
		end
	end

	return if #lines > 0 then lines else { DEFAULT_EMPTY_FIELD }
end

--[[
	Appends a labeled multi-line section to the buffer with aligned indentations.
]]
local function appendSection(buffer: { string }, label: string, lines: { string })
	local paddedLabel = string_format("│ %-16s: ", label)
	for i = 1, #lines do
		local prefix = if i == 1 then paddedLabel else PREFIX_EMPTY_SPACER
		table_insert(buffer, prefix .. lines[i])
	end
end

-- [[ SECTION 2: CARD COMPOSITION ]] --
--[[
	Composes the complete diagnostic artifact into an ASCII companion card.
	Returns the formatted string without executing any console side effects.
]]
function OutputCompositor.Compose(artifact: Types.DiagnosticArtifact): string
	local confidenceTier = if artifact.Confidence >= 90 then "(Confirmed)"
		elseif artifact.Confidence >= 70 then "(Probable)"
		else "(Deduction)"

	local confidenceBar = generateProgressBar(artifact.Confidence)
	local buffer: { string } = {}

	-- Statement-level narrowing for optional ClientOrigin
	local client = artifact.ClientOrigin
	local environmentStr: string
	if client then
		environmentStr = string_format("Client [%s (UserId: %d)]", client.Name, client.UserId)
	else
		environmentStr = "Server Authoritative"
	end

	-- Header
	table_insert(buffer, "\n" .. OutputCompositor.SESSION_SIGNATURE)
	table_insert(buffer, "┌─── [DIAGNOSTIC ADVISOR] ──────────────────────────────────────────")
	table_insert(buffer, string_format("│ CONFIDENCE      : [%s] %d%% %s", confidenceBar, artifact.Confidence, confidenceTier))
	table_insert(buffer, string_format("│ ENVIRONMENT     : %s", environmentStr))
	table_insert(buffer, string_format("│ CATEGORY        : %s", artifact.Category or "General Fault"))
	table_insert(buffer, "│")

	-- Core Diagnostic Context
	appendSection(buffer, "CLEAR MESSAGE", wrapText(artifact.ClearMessage, CONTENT_WIDTH))
	table_insert(buffer, "│")

	appendSection(buffer, "POSSIBLE REASON", wrapText(artifact.PossibleReason, CONTENT_WIDTH))
	table_insert(buffer, "│")

	appendSection(buffer, "WHY IT HAPPENED", wrapText(artifact.WhyItHappened, CONTENT_WIDTH))
	table_insert(buffer, "│")

	appendSection(buffer, "ACTIONABLE FIX", wrapText(artifact.ActionableFix, CONTENT_WIDTH))
	table_insert(buffer, "│")

	-- Telemetry Origin
	local originStr = if artifact.TelemetryContext and artifact.TelemetryContext.Origin ~= ""
		then artifact.TelemetryContext.Origin
		else "Unknown Origin"
	table_insert(buffer, string_format("│ TRACE ORIGIN    : %s", originStr))

	-- Breadcrumb History
	local breadcrumbs = if artifact.TelemetryContext then artifact.TelemetryContext.Breadcrumbs else nil
	if breadcrumbs and #breadcrumbs > 0 then
		for i = 1, #breadcrumbs do
			local prefix = if i == 1 then "│ BREADCRUMBS     : " else PREFIX_EMPTY_SPACER
			table_insert(buffer, prefix .. breadcrumbs[i])
		end
	else
		table_insert(buffer, "│ BREADCRUMBS     : [No recent recorded actions]")
	end

	-- Footer
	table_insert(buffer, "└───────────────────────────────────────────────────────────────────")

	return table_concat(buffer, "\n")
end

-- [[ SECTION 3: EMISSION & CONSOLE RENDERING ]] --
--[[
	Composes and prints the diagnostic card to the Studio Output Window.
]]
function OutputCompositor.Render(artifact: Types.DiagnosticArtifact)
	local cardString = OutputCompositor.Compose(artifact)
	print(cardString)
end

--[[
	Pipeline alias to fulfill the consumer contract invoked by Synthesizer.ProcessSignal.
]]
function OutputCompositor.Emit(artifact: Types.DiagnosticArtifact)
	OutputCompositor.Render(artifact)
end

return table_freeze(OutputCompositor)
