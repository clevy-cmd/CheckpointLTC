--!strict

local Config = require(script.Parent.Parent.Config)

export type Role = string

local Typography = {}

local columnWidth = Config.widget.defaultWidth
local roles: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local listeners: { () -> () } = {}

local auto = false
local scales: { [string]: number } = { title = 1, body = 1, small = 1 }

function Typography.size(role: Role): number
	local spec = (Config.type :: any)[role] or Config.type.body
	local base = if auto then math.clamp(columnWidth * spec.ratio, spec.min, spec.max) else spec.size
	return math.floor(base * (scales[spec.group] or 1) + 0.5)
end

function Typography.rowScale(): number
	if auto then
		return math.max(0.7, columnWidth / Config.widget.defaultWidth)
	end
	return scales.body or 1
end

local function reapply()
	for label, role in roles do
		(label :: any).TextSize = Typography.size(role)
	end
	for _, listener in table.clone(listeners) do
		task.spawn(listener)
	end
end

function Typography.setOptions(autoSizing: boolean, title: number, body: number, small: number)
	if autoSizing == auto and scales.title == title and scales.body == body and scales.small == small then
		return
	end
	auto = autoSizing
	scales = { title = title, body = body, small = small }
	reapply()
end

function Typography.lineHeight(role: Role): number
	return math.ceil(Typography.size(role) * 1.25)
end

function Typography.font(role: Role): Font
	local spec = (Config.type :: any)[role] or Config.type.body
	local family = if role == "code" then Config.fonts.mono else Config.fonts.family
	return Font.new(family, spec.weight, Enum.FontStyle.Normal)
end

function Typography.apply(label: GuiObject, role: Role)
	roles[label] = role
	local text = label :: any
	text.FontFace = Typography.font(role)
	text.TextSize = Typography.size(role)
end

function Typography.columnWidth(): number
	return columnWidth
end

function Typography.onResized(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

function Typography.setColumnWidth(width: number)
	if width <= 0 or math.abs(width - columnWidth) < 0.5 then
		return
	end
	columnWidth = width
	if auto then
		reapply()
	end
end

return Typography
