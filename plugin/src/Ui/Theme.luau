--!strict

local Config = require(script.Parent.Parent.Config)

export type Token = string

local Theme = {}

local studio = settings().Studio
local guide = Enum.StudioStyleGuideColor
local modifier = Enum.StudioStyleGuideModifier

local function color(name: Enum.StudioStyleGuideColor, mod: Enum.StudioStyleGuideModifier?): Color3
	return studio.Theme:GetColor(name, mod or modifier.Default)
end

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local accentName = "brand"
local palette: { [string]: Color3 } = {}

local function rebuildPalette()
	local canvas = color(guide.MainBackground)
	local text = color(guide.MainText)
	local isDark = luminance(canvas) < 0.5
	local accent = (Config.accents :: any)[accentName] or Config.accents.brand
	local onAccent = if luminance(accent) > 0.55 then Color3.fromHex("060c18") else Color3.new(1, 1, 1)
	local danger = if isDark then Config.brand.redBright else Config.brand.red

	palette = {
		canvas = canvas,
		sidebar = canvas:Lerp(text, if isDark then 0.035 else 0.03),
		raised = color(guide.Titlebar),
		card = canvas:Lerp(text, if isDark then 0.06 else 0.025),
		overlay = Color3.new(0, 0, 0),
		text = text,
		subtext = color(guide.SubText),
		dim = color(guide.DimmedText),
		line = canvas:Lerp(text, 0.1),
		lineStrong = canvas:Lerp(text, 0.2),
		hover = canvas:Lerp(text, 0.06),
		press = canvas:Lerp(text, 0.1),
		selected = canvas:Lerp(accent, if isDark then 0.2 else 0.14),
		input = color(guide.InputFieldBackground),
		accent = accent,
		accentHover = accent:Lerp(Color3.new(1, 1, 1), 0.12),
		accentText = onAccent,
		accentSoft = canvas:Lerp(accent, if isDark then 0.18 else 0.12),
		brandBlue = Config.brand.blue,
		brandRed = Config.brand.red,
		danger = danger,
		dangerHover = danger:Lerp(Color3.new(1, 1, 1), 0.12),
		dangerText = Color3.new(1, 1, 1),
		dangerSoft = canvas:Lerp(danger, if isDark then 0.22 else 0.12),
		warning = color(guide.WarningText),
		warningSoft = canvas:Lerp(Config.brand.yellow, if isDark then 0.18 else 0.16),
		success = Config.brand.green,
		successSoft = canvas:Lerp(Config.brand.green, if isDark then 0.2 else 0.14),
		checkBorder = canvas:Lerp(text, 0.38),
		tooltip = if isDark then Color3.fromHex("0d1628") else Color3.fromHex("1c2533"),
		tooltipText = Color3.fromHex("eef2ff"),
	}
end

local bindings: { [Instance]: { [string]: string } } = setmetatable({}, { __mode = "k" }) :: any
local listeners: { () -> () } = {}

function Theme.get(token: Token): Color3
	return palette[token] or palette.text
end

function Theme.isDark(): boolean
	return luminance(palette.canvas) < 0.5
end

function Theme.bind(instance: Instance, property: string, token: Token)
	local binding = bindings[instance]
	if not binding then
		binding = {}
		bindings[instance] = binding
	end
	binding[property] = token;
	(instance :: any)[property] = Theme.get(token)
end

function Theme.unbind(instance: Instance, property: string)
	local binding = bindings[instance]
	if binding then
		binding[property] = nil
	end
end

function Theme.onChanged(listener: () -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

local function repaint()
	rebuildPalette()
	for instance, binding in bindings do
		if instance.Parent ~= nil then
			for property, token in binding do
				(instance :: any)[property] = Theme.get(token)
			end
		end
	end
	for _, listener in table.clone(listeners) do
		task.spawn(listener)
	end
end

function Theme.setAccent(name: string)
	if name ~= accentName then
		accentName = name
		repaint()
	end
end

function Theme.start(): RBXScriptConnection
	rebuildPalette()
	return studio.ThemeChanged:Connect(repaint)
end

rebuildPalette()

return Theme
