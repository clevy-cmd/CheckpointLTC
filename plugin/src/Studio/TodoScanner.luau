--!strict

local ScriptEditorService = game:GetService("ScriptEditorService")

local TodoScanner = {}

export type Found = { script: LuaSourceContainer, path: string, line: number, text: string }

local searchRoots = {
	"Workspace",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Lighting",
	"SoundService",
	"Teams",
}

local function sourceOf(container: LuaSourceContainer): string
	local ok, source = pcall(ScriptEditorService.GetEditorSource, ScriptEditorService, container)
	if ok and type(source) == "string" then
		return source
	end
	local okSource, raw = pcall(function()
		return (container :: any).Source
	end)
	return if okSource and type(raw) == "string" then raw else ""
end

function TodoScanner.parse(source: string): { { line: number, text: string } }
	local found = {}
	local lineNumber = 0
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		lineNumber += 1
		local text = string.match(line, "%-%-%s*TODO%s*:%s*(.-)%s*$")
		if text and text ~= "" then
			table.insert(found, { line = lineNumber, text = string.sub(text, 1, 200) })
		end
	end
	return found
end

function TodoScanner.scan(limit: number?): { Found }
	local results: { Found } = {}
	local cap = limit or 500
	for _, rootName in searchRoots do
		local ok, root = pcall(game.GetService, game, rootName)
		if ok and root then
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("LuaSourceContainer") then
					for _, todo in TodoScanner.parse(sourceOf(descendant)) do
						table.insert(results, {
							script = descendant,
							path = descendant:GetFullName(),
							line = todo.line,
							text = todo.text,
						})
						if #results >= cap then
							return results
						end
					end
				end
			end
		end
	end
	return results
end

return TodoScanner
