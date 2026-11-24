--!strict

local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Overlay)
local Theme = require(script.Parent.Parent.Theme)

local Controls = {}

export type ButtonKind = "primary" | "secondary" | "danger" | "ghost"

local kindTokens: { [string]: { base: string, hover: string, text: string, transparency: number } } = {
	primary = { base = "accent", hover = "accentHover", text = "accentText", transparency = 0 },
	secondary = { base = "card", hover = "hover", text = "text", transparency = 0 },
	danger = { base = "danger", hover = "dangerHover", text = "dangerText", transparency = 0 },
	ghost = { base = "canvas", hover = "hover", text = "text", transparency = 1 },
}

export type Button = {
	root: Frame,
	hit: TextButton,
	label: TextLabel,
	hint: TextLabel?,
	setText: (string) -> (),
	setEnabled: (boolean) -> (),
	setKind: (ButtonKind) -> (),
}

export type ButtonOptions = {
	text: string,
	kind: ButtonKind?,
	onClick: () -> (),
	tooltip: string?,
	shortcut: string?,
	hint: string?,
	props: Kit.Props?,
	parent: Instance?,
}

function Controls.button(options: ButtonOptions, maid: Maid.Maid): Button
	local kind = options.kind or "secondary"
	local root = Kit.frame(options.props)
	local body = Kit.surface(
		kindTokens[kind].base,
		{ Size = UDim2.fromScale(1, if options.hint then 0.62 else 1), Parent = root },
		{}
	)
	body.BackgroundTransparency = kindTokens[kind].transparency
	local label = Kit.label({
		text = options.text,
		role = "label",
		token = kindTokens[kind].text,
		align = Enum.TextXAlignment.Center,
	})
	label.Parent = body
	local hit = Kit.hitbox({ Parent = body })
	local hint: TextLabel? = nil
	if options.hint then
		local hintLabel = Kit.label({
			text = options.hint,
			role = "hint",
			token = "dim",
			wrap = true,
			align = Enum.TextXAlignment.Center,
			props = { Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), Name = "Hint" },
		})
		hintLabel.Parent = root
		hint = hintLabel
		Overlay.registerHint(hintLabel)
	end
	local enabled = true
	local current = kind
	local function paint(hover: boolean)
		local tokens = kindTokens[current]
		Theme.bind(body, "BackgroundColor3", if hover and enabled then tokens.hover else tokens.base)
		body.BackgroundTransparency = if current == "ghost" and not hover then 1 else 0
		Theme.bind(label, "TextColor3", if enabled then tokens.text else "dim")
	end
	maid:give(hit.MouseEnter:Connect(function()
		paint(true)
	end))
	maid:give(hit.MouseLeave:Connect(function()
		paint(false)
	end))
	maid:give(hit.Activated:Connect(function()
		if enabled then
			options.onClick()
		end
	end))
	if options.tooltip then
		Overlay.tooltip(hit, options.tooltip, options.shortcut, maid)
	end
	if options.parent then
		root.Parent = options.parent
	end
	paint(false)
	return {
		root = root,
		hit = hit,
		label = label,
		hint = hint,
		setText = function(text: string)
			label.Text = text
		end,
		setEnabled = function(value: boolean)
			enabled = value
			paint(false)
		end,
		setKind = function(value: ButtonKind)
			current = value
			paint(false)
		end,
	}
end

export type IconButton = {
	root: Frame,
	hit: TextButton,
	setActive: (boolean) -> (),
	setBadge: (number) -> (),
	setVisible: (boolean) -> (),
}

export type IconOptions = {
	icon: string,
	tooltip: string,
	shortcut: string?,
	onClick: () -> (),
	danger: boolean?,
	props: Kit.Props?,
	parent: Instance?,
}

function Controls.iconButton(options: IconOptions, maid: Maid.Maid): IconButton
	local root = Kit.frame(options.props, { Kit.square() })
	local body = Kit.surface("canvas", { Parent = root }, {})
	body.BackgroundTransparency = 1
	local glyph = Kit.glyphIcon(
		options.icon,
		if options.danger then "danger" else "subtext",
		{ Size = UDim2.fromScale(0.56, 0.56) }
	)
	glyph.Parent = body
	local badge = Kit.surface("danger", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1.05, -0.05),
		Size = UDim2.fromScale(0.45, 0.45),
		Visible = false,
		ZIndex = 4,
		Parent = root,
	}, {})
	local badgeText = Kit.label({
		text = "",
		role = "hint",
		token = "dangerText",
		align = Enum.TextXAlignment.Center,
		props = { ZIndex = 5 },
	})
	badgeText.Parent = badge
	local hit = Kit.hitbox({ Parent = root, ZIndex = 6 })
	local active = false
	local function paint(hover: boolean)
		body.BackgroundTransparency = if hover or active then 0 else 1
		Theme.bind(body, "BackgroundColor3", if active then "selected" else "hover")
	end
	maid:give(hit.MouseEnter:Connect(function()
		paint(true)
	end))
	maid:give(hit.MouseLeave:Connect(function()
		paint(false)
	end))
	maid:give(hit.Activated:Connect(options.onClick))
	Overlay.tooltip(hit, options.tooltip, options.shortcut, maid)
	if options.parent then
		root.Parent = options.parent
	end
	return {
		root = root,
		hit = hit,
		setActive = function(value: boolean)
			active = value
			paint(false)
		end,
		setBadge = function(count: number)
			badge.Visible = count > 0
			badgeText.Text = if count > 9 then "9+" else tostring(count)
		end,
		setVisible = function(value: boolean)
			root.Visible = value
		end,
	}
end

export type Toggle = { root: Frame, set: (boolean) -> (), get: () -> boolean }

function Controls.toggle(
	text: string,
	hint: string?,
	initial: boolean,
	onChange: (boolean) -> (),
	maid: Maid.Maid,
	props: Kit.Props?
): Toggle
	local root = Kit.frame(props)
	local textArea = Kit.frame({ Size = UDim2.fromScale(0.78, 1), Parent = root })
	local title =
		Kit.label({ text = text, role = "body", props = { Size = UDim2.fromScale(1, if hint then 0.55 else 1) } })
	title.Parent = textArea
	if hint then
		local hintLabel = Kit.label({
			text = hint,
			role = "hint",
			token = "dim",
			wrap = true,
			props = { Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5) },
		})
		hintLabel.Parent = textArea
	end
	local track = Kit.surface("lineStrong", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.13, 0.42),
		Parent = root,
	}, {})
	local knob = Kit.surface(
		"tooltipText",
		{ Size = UDim2.fromScale(0.42, 0.8), AnchorPoint = Vector2.new(0, 0.5), Parent = track },
		{}
	)
	local value = initial
	local function paint()
		Theme.bind(track, "BackgroundColor3", if value then "accent" else "lineStrong")
		knob.Position = UDim2.fromScale(if value then 0.53 else 0.05, 0.5)
	end
	local hit = Kit.hitbox({ Parent = root })
	maid:give(hit.Activated:Connect(function()
		value = not value
		paint()
		onChange(value)
	end))
	paint()
	return {
		root = root,
		set = function(next: boolean)
			value = next
			paint()
		end,
		get = function()
			return value
		end,
	}
end

export type Chip = { root: Frame, setSelected: (boolean) -> (), setText: (string) -> () }

function Controls.chip(text: string, color: Color3?, onClick: (() -> ())?, maid: Maid.Maid, props: Kit.Props?): Chip
	local root = Kit.frame(props)
	local body = Kit.surface("card", { Parent = root })
	local label = Kit.label({ text = text, role = "hint", token = "subtext", align = Enum.TextXAlignment.Center })
	label.Parent = body
	local underline = Kit.surface("accent", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.1),
		Visible = false,
		Parent = body,
	})
	if color then
		Theme.unbind(body, "BackgroundColor3")
		Theme.unbind(label, "TextColor3")
		Theme.unbind(underline, "BackgroundColor3")
		body.BackgroundColor3 = color
		body.BackgroundTransparency = 0.75
		label.TextColor3 = color
		underline.BackgroundColor3 = color
	end
	if onClick then
		local hit = Kit.hitbox({ Parent = body })
		maid:give(hit.Activated:Connect(onClick))
	end
	return {
		root = root,
		setSelected = function(selected: boolean)
			underline.Visible = selected
			if color then
				underline.BackgroundColor3 = color
				body.BackgroundTransparency = if selected then 0.55 else 0.85
			else
				Theme.bind(body, "BackgroundColor3", if selected then "selected" else "card")
				Theme.bind(label, "TextColor3", if selected then "text" else "subtext")
			end
		end,
		setText = function(value: string)
			label.Text = value
		end,
	}
end

export type Meter = { root: Frame, set: (number, number, string?) -> () }

function Controls.meter(title: string, props: Kit.Props?): Meter
	local root = Kit.frame(props)
	local name = Kit.label({ text = title, role = "label", props = { Size = UDim2.fromScale(0.6, 0.55) } })
	name.Parent = root
	local value = Kit.label({
		text = "",
		role = "meta",
		token = "subtext",
		align = Enum.TextXAlignment.Right,
		props = { Position = UDim2.fromScale(0.6, 0), Size = UDim2.fromScale(0.4, 0.55) },
	})
	value.Parent = root
	local track = Kit.surface(
		"line",
		{ Position = UDim2.fromScale(0.02, 0.62), Size = UDim2.fromScale(0.96, 0.16), Parent = root },
		{}
	)
	local bar = Kit.surface("accent", { Size = UDim2.fromScale(0, 1), Parent = track }, {})
	local warning = Kit.label({
		text = "",
		role = "hint",
		token = "warning",
		props = { Position = UDim2.fromScale(0, 0.8), Size = UDim2.fromScale(1, 0.2) },
	})
	warning.Parent = root
	return {
		root = root,
		set = function(used: number, max: number, suffix: string?)
			local fraction = if max > 0 then math.clamp(used / max, 0, 1) else 0
			bar.Size = UDim2.fromScale(fraction, 1)
			value.Text = string.format("%d / %d%s", used, max, suffix or "")
			Theme.bind(
				bar,
				"BackgroundColor3",
				if fraction >= 1 then "danger" elseif fraction >= 0.8 then "warning" else "accent"
			)
			warning.Text = if fraction >= 1
				then "Limit reached."
				elseif fraction >= 0.8 then "Getting close to the limit."
				else ""
		end,
	}
end

function Controls.sectionTitle(text: string, props: Kit.Props?): TextLabel
	local label = Kit.label({ text = string.upper(text), role = "hint", token = "dim", props = props })
	return label
end

function Controls.divider(props: Kit.Props?): Frame
	local merged: Kit.Props = { Size = UDim2.fromScale(1, 0.004) }
	for key, value in props or {} do
		merged[key] = value
	end
	return Kit.surface("line", merged)
end

return Controls
