--!strict
-- [[ STACK DECOMPILER: DUAL-SOURCE PARSER ]] --
-- Parses structured frames from native stack traces or fallback inline error strings,
-- with full support for instances, directories, and functions using whitespace name scheming.

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Types)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local string_gmatch = string.gmatch
local string_match = string.match
local string_find = string.find
local string_gsub = string.gsub
local tonumber = tonumber
local table_insert = table.insert
local table_freeze = table.freeze

-- [[ CONFIGURATION CONSTANTS ]] --
local INTERNAL_PATTERNS: { string } = table_freeze({
	"^%[C%]",
	"^CorePackages",
	"^CoreGui",
	"^builtin_",
	"^Plugin",
	"^PlayerScripts%.PlayerModule",
	"^StarterPlayerScripts%.PlayerModule",
})

-- [[ MODULE DEFINITION ]] --
local StackDecompiler = {}

-- [[ SECTION 1: INTERNAL CLASSIFICATION & TOKEN NORMALIZATION ]] --
--[[
	Determines whether a parsed script source path belongs to Roblox internal
	engine code, core libraries, or default player scripts.
]]
local function isInternal(source: string): boolean
	for i = 1, #INTERNAL_PATTERNS do
		if string_find(source, INTERNAL_PATTERNS[i]) then
			return true
		end
	end
	return false
end

--[[
	Trims surrounding whitespace while preserving spaces inside the name.
]]
local function trimWhitespace(str: string): string
	return string_match(str, "^%s*(.-)%s*$") or str
end

--[[
	Cleans function names extracted from stack frames.
	Handles whitespace, quotes, and prefixes such as 'function', 'in function',
	'upvalue', 'field', 'method', or 'local'.
]]
local function cleanFunctionName(rawName: string?): string
	if not rawName or rawName == "" then
		return "Anonymous"
	end

	local trimmed = trimWhitespace(rawName)

	-- Strip leading dash separators often present in Roblox tracebacks
	trimmed = string_gsub(trimmed, "^%-+%s*", "")

	-- Extract core identifier if preceded by Luau/Roblox traceback descriptors
	local matched = string_match(trimmed, "^[%w_]+%s+['\"]?([%w_%.%s]+)['\"]?$")
		or string_match(trimmed, "^in function%s+['\"]?([%w_%.%s]+)['\"]?$")
		or trimmed

	matched = string_gsub(matched, "['\"]", "")
	matched = trimWhitespace(matched)

	return if matched ~= "" then matched else "Anonymous"
end

--[[
	Strips console timestamps and extracts inline script paths and line numbers
	from historical error messages (e.g., "14:02:11 - Workspace.Part Name.Script:23: error").
]]
local function parseInlineFallback(message: string): (string?, number?)
	-- 1. Strip optional console timestamp prefixes (e.g. "12:34:56.789 - ")
	local cleanMessage = string_gsub(message, "^%s*%d%d:%d%d:%d%d%.?%d*%s*%-*%s*", "")

	-- 2. Match: Script 'Path With Spaces', Line 123
	local source, lineNumStr = string_match(cleanMessage, 'Script%s+["\'](.-)["\']%s*,%s*Line%s*(%-?%d+)')
	if source and lineNumStr then
		return trimWhitespace(source), tonumber(lineNumStr)
	end

	-- 3. Match: Path With Spaces:123: (standard error line format with trailing colon)
	source, lineNumStr = string_match(cleanMessage, "^%s*(.-)%s*:%s*(%d+)%s*:")
	if source and lineNumStr and #source > 0 then
		return trimWhitespace(source), tonumber(lineNumStr)
	end

	-- 4. Match: Path With Spaces:123 (without trailing colon)
	source, lineNumStr = string_match(cleanMessage, "^%s*(.-)%s*:%s*(%d+)%s*$")
	if source and lineNumStr and #source > 0 then
		return trimWhitespace(source), tonumber(lineNumStr)
	end

	return nil, nil
end

-- [[ SECTION 2: CORE DECOMPILATION PIPELINE ]] --
--[[
	Decompiles a raw call-stack string into structured StackTelemetry.
	Preserves whitespace inside instance and script paths while ignoring
	ambient line indentation and spacing variations.
]]
function StackDecompiler.Decompile(rawTrace: string, fallbackMessage: string?): Types.StackTelemetry
	local userFrames: { Types.ParsedFrame } = {}
	local allFrames: { Types.ParsedFrame } = {}
	local totalDepth: number = 0

	-- 1. Parse lines from the provided stack trace
	for rawLine in string_gmatch(rawTrace, "[^\r\n]+") do
		local source: string? = nil
		local lineNumStr: string? = nil
		local functionToken: string? = nil

		-- Pattern A: Quoted script format (e.g. "\tScript 'Workspace.Game Manager.Main Script', Line 15 - function Foo")
		source, lineNumStr, functionToken = string_match(
			rawLine,
			'^%s*Script%s+["\'](.-)["\']%s*,%s*Line%s*(%-?%d+)%s*%-?%s*(.*)$'
		)

		-- Pattern B: Path:Line format (e.g. "\tWorkspace.Game Manager.Main Script:15 function Foo")
		if not source then
			local matchedSource, matchedLine, colonFollowup, trailingToken = string_match(
				rawLine,
				"^%s*(.-)%s*:%s*(%-?%d+)(:?)%s*(.*)$"
			)

			if matchedSource and matchedLine then
				source = matchedSource
				lineNumStr = matchedLine

				-- If a colon immediately follows the line number (e.g., ":15: error message"),
				-- the trailing text is an error description, not a function identifier.
				if colonFollowup ~= ":" and trailingToken and trailingToken ~= "" then
					functionToken = trailingToken
				else
					functionToken = nil
				end
			end
		end

		-- Valid frame entry identified
		if source and lineNumStr then
			totalDepth += 1
			local lineNum = tonumber(lineNumStr) or 0
			local cleanSource = trimWhitespace(source)
			local cleanFunction = cleanFunctionName(functionToken)

			local frame: Types.ParsedFrame = {
				Source = cleanSource,
				Line = lineNum,
				Function = cleanFunction,
				IsEngineInternal = isInternal(cleanSource),
			}

			table_insert(allFrames, frame)

			if not frame.IsEngineInternal then
				table_insert(userFrames, frame)
			end
		end
	end

	-- 2. Fallback: Parse inline script path and line number from error message
	if #allFrames == 0 and fallbackMessage and fallbackMessage ~= "" then
		local source, lineNum = parseInlineFallback(fallbackMessage)

		if source and lineNum then
			totalDepth += 1
			local frame: Types.ParsedFrame = {
				Source = source,
				Line = lineNum,
				Function = "InlineEntry",
				IsEngineInternal = isInternal(source),
			}

			table_insert(allFrames, frame)

			if not frame.IsEngineInternal then
				table_insert(userFrames, frame)
			end
		end
	end

	-- OriginFrame selects the first user frame; if only engine frames exist,
	-- falls back to the top engine frame so consumers detect IsEngineInternal.
	local originFrame: Types.ParsedFrame? = nil
	if #userFrames > 0 then
		originFrame = userFrames[1]
	elseif #allFrames > 0 then
		originFrame = allFrames[1]
	end

	return {
		OriginalTrace = rawTrace,
		OriginFrame = originFrame,
		UserFrames = userFrames,
		FrameDepth = totalDepth,
	}
end

return table_freeze(StackDecompiler)
