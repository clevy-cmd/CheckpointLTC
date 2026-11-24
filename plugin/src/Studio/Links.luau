--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")

local Links = {}

local tag = "CheckpointLTCLink"
local attribute = "CheckpointLTCId"

export type Link = { kind: string, path: string, guid: string?, line: number?, placeId: number? }

local pluginRef: Plugin? = nil

function Links.init(plugin: Plugin)
	pluginRef = plugin
end

local function guidFor(instance: Instance): string
	local existing = instance:GetAttribute(attribute)
	if type(existing) == "string" and existing ~= "" then
		return existing
	end
	local guid = string.lower((string.gsub(HttpService:GenerateGUID(false), "%-", "")))
	instance:SetAttribute(attribute, guid)
	CollectionService:AddTag(instance, tag)
	return guid
end

function Links.fromSelection(): (Link?, Instance?)
	local selected = Selection:Get()[1]
	if not selected then
		return nil, nil
	end
	local isScript = selected:IsA("LuaSourceContainer")
	return {
		kind = if isScript then "script" else "instance",
		path = string.sub(selected:GetFullName(), 1, 400),
		guid = guidFor(selected),
		line = if isScript then 1 else nil,
		placeId = if game.PlaceId > 0 then game.PlaceId else nil,
	},
		selected
end

function Links.forScriptLine(source: LuaSourceContainer, line: number): Link
	return {
		kind = "script",
		path = string.sub(source:GetFullName(), 1, 400),
		guid = guidFor(source),
		line = line,
		placeId = if game.PlaceId > 0 then game.PlaceId else nil,
	}
end

local function byPath(path: string): Instance?
	local current: Instance? = game
	for piece in string.gmatch(path, "[^%.]+") do
		if not current then
			return nil
		end
		local child = (current :: Instance):FindFirstChild(piece)
		if not child and current == game then
			local ok, service = pcall(game.GetService, game, piece)
			child = if ok then service else nil
		end
		current = child
	end
	return if current ~= game then current else nil
end

function Links.resolve(link: Link): Instance?
	if link.guid then
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:GetAttribute(attribute) == link.guid then
				return instance
			end
		end
	end
	return byPath(link.path)
end

function Links.open(link: Link): (boolean, string)
	if link.placeId and game.PlaceId > 0 and link.placeId ~= game.PlaceId then
		return false, "That link points to a different place."
	end
	local target = Links.resolve(link)
	if not target then
		return false, "I couldn't find " .. link.path .. " in this place. It may have been deleted or renamed."
	end
	Selection:Set({ target })
	if target:IsA("LuaSourceContainer") and pluginRef then
		local ok = pcall(pluginRef.OpenScript, pluginRef, target, link.line or 1)
		if not ok then
			return true, "Selected " .. target.Name .. "."
		end
		return true, "Opened " .. target.Name .. (if link.line then " at line " .. link.line else "") .. "."
	end
	return true, "Selected " .. target.Name .. "."
end

function Links.describe(link: Link): string
	local name = string.match(link.path, "([^%.]+)$") or link.path
	if link.kind == "script" and link.line then
		return name .. " line " .. link.line
	end
	return name
end

return Links
