--!strict

local Config = require(script.Parent.Parent.Parent.Config)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Theme = require(script.Parent.Parent.Theme)

local TextService = game:GetService("TextService")

local Overlay = {}

local layer: Frame? = nil
local tooltipFrame: Frame? = nil
local tooltipLabel: TextLabel? = nil
local toastStack: Frame? = nil
local pluginRef: Plugin? = nil
local showTooltips = true
local showHints = true
local hints: { [TextLabel]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local onHintsChanged: (() -> ())? = nil
local modalMaid: Maid.Maid? = nil
local modalRoot: GuiObject? = nil
local toastCounter = 0

function Overlay.mount(root: GuiObject, plugin: Plugin, maid: Maid.Maid)
	pluginRef = plugin
	local frame = Kit.frame({ Name = "Overlay", ZIndex = 100, Parent = root })
	layer = frame

	local tip = Kit.surface(
		"tooltip",
		{ Visible = false, ZIndex = 140, Size = UDim2.fromScale(0.4, 0.05), Parent = frame },
		{}
	)
	local tipText = Kit.label({
		text = "",
		role = "meta",
		token = "tooltipText",
		align = Enum.TextXAlignment.Center,
		noPeek = true,
		props = { ZIndex = 141 },
	})
	tipText.Parent = tip
	tooltipFrame = tip
	tooltipLabel = tipText

	local stack = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.92, 0.5),
		ZIndex = 130,
		Parent = frame,
	}, { Kit.list(Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom, 0.015) })
	toastStack = stack
	maid:give(frame)
	Overlay.enablePeek(tip, tipText, frame)
end

function Overlay.setPreferences(tooltips: boolean, hintsOn: boolean)
	showTooltips = tooltips
	if hintsOn ~= showHints then
		showHints = hintsOn
		for label in hints do
			label.Visible = showHints
		end
		if onHintsChanged then
			onHintsChanged()
		end
	end
end

function Overlay.onHintsToggled(callback: () -> ())
	onHintsChanged = callback
end

function Overlay.hintsVisible(): boolean
	return showHints
end

function Overlay.registerHint(label: TextLabel)
	hints[label] = true
	label.Visible = showHints
end

local function toLayer(position: Vector2, size: Vector2): (UDim2, UDim2)
	local frame = layer :: Frame
	local origin = frame.AbsolutePosition
	local total = frame.AbsoluteSize
	return UDim2.fromScale((position.X - origin.X) / total.X, (position.Y - origin.Y) / total.Y),
		UDim2.fromScale(size.X / total.X, size.Y / total.Y)
end

function Overlay.enablePeek(tip: Frame, tipText: TextLabel, frame: Frame)
	local peekToken = 0
	Kit.peek = function(label: TextLabel, entering: boolean)
		peekToken += 1
		if not entering then
			tip.Visible = false
			return
		end
		if Overlay.isCovered(label) then
			return
		end
		local mine = peekToken
		task.delay(Config.interaction.tooltipDelay, function()
			if mine ~= peekToken or not label.Parent or label.TextFits then
				return
			end
			local size = tipText.TextSize
			local maxWidth = math.max(60, frame.AbsoluteSize.X - 16)
			local ok, bounds = pcall(
				TextService.GetTextSize,
				TextService,
				label.Text,
				size,
				Enum.Font.BuilderSans,
				Vector2.new(maxWidth * 0.86, 100000)
			)
			local textSize = if ok then bounds else Vector2.new(maxWidth, size * 4)
			local width = math.min(maxWidth, textSize.X / 0.86 + size)
			local height = (textSize.Y + size) / 0.86
			local x = math.clamp(
				label.AbsolutePosition.X,
				frame.AbsolutePosition.X + 8,
				math.max(frame.AbsolutePosition.X + 8, frame.AbsolutePosition.X + frame.AbsoluteSize.X - width - 8)
			)
			local below = label.AbsolutePosition.Y + label.AbsoluteSize.Y + 4
			local y = if below + height > frame.AbsolutePosition.Y + frame.AbsoluteSize.Y
				then math.max(frame.AbsolutePosition.Y + 4, label.AbsolutePosition.Y - height - 4)
				else below
			local position, area = toLayer(Vector2.new(x, y), Vector2.new(width, height))
			tipText.TextWrapped = true
			tipText.TextXAlignment = Enum.TextXAlignment.Left
			tipText.Text = label.Text
			tip.Position = position
			tip.Size = area
			tip.Visible = true
		end)
	end
end

function Overlay.tooltip(target: GuiObject, text: string, shortcut: string?, maid: Maid.Maid)
	local token = 0
	local full = if shortcut then text .. "   " .. shortcut else text
	maid:give(target.MouseEnter:Connect(function()
		token += 1
		if Overlay.isCovered(target) then
			return
		end
		local mine = token
		task.delay(Config.interaction.tooltipDelay, function()
			local tip, label, frame = tooltipFrame, tooltipLabel, layer
			if mine ~= token or not showTooltips or not tip or not label or not frame or not target.Parent then
				return
			end
			label.TextWrapped = false
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.Text = full
			local width =
				math.min(math.max(80, #full * label.TextSize * 0.55 + 24), math.max(40, frame.AbsoluteSize.X - 8))
			local height = label.TextSize * 2.1
			local x = math.clamp(
				target.AbsolutePosition.X + target.AbsoluteSize.X / 2 - width / 2,
				frame.AbsolutePosition.X + 4,
				math.max(frame.AbsolutePosition.X + 4, frame.AbsolutePosition.X + frame.AbsoluteSize.X - width - 4)
			)
			local below = target.AbsolutePosition.Y + target.AbsoluteSize.Y + 6
			local y = if below + height > frame.AbsolutePosition.Y + frame.AbsoluteSize.Y
				then target.AbsolutePosition.Y - height - 6
				else below
			local position, size = toLayer(Vector2.new(x, y), Vector2.new(width, height))
			tip.Position = position
			tip.Size = size
			tip.Visible = true
		end)
	end))
	local function hide()
		token += 1
		if tooltipFrame then
			tooltipFrame.Visible = false
		end
	end
	maid:give(target.MouseLeave:Connect(hide))
	maid:give(target.Destroying:Connect(hide))
end

export type ToastAction = { label: string, run: () -> () }

function Overlay.toast(kind: string, text: string, action: ToastAction?)
	local stack = toastStack
	if not stack then
		return
	end
	toastCounter += 1
	local token = if kind == "error"
		then "dangerSoft"
		elseif kind == "success" then "successSoft"
		elseif kind == "warning" then "warningSoft"
		else "card"
	local card = Kit.surface(
		token,
		{ Size = UDim2.fromScale(1, 0.16), LayoutOrder = toastCounter, ZIndex = 131, Parent = stack },
		{}
	)
	local message = Kit.label({
		text = text,
		role = "meta",
		wrap = true,
		props = { Size = UDim2.fromScale(if action then 0.72 else 0.9, 1), ZIndex = 132 },
	})
	message.Parent = card
	local close = Kit.hitbox({
		Text = "×",
		Position = UDim2.fromScale(0.92, 0),
		Size = UDim2.fromScale(0.08, 1),
		ZIndex = 133,
		Parent = card,
	})
	Theme.bind(close, "TextColor3", "subtext")
	close.TextScaled = false
	close.TextSize = message.TextSize + 4
	local alive = true
	local function dismiss()
		if alive then
			alive = false
			card:Destroy()
		end
	end
	close.Activated:Connect(dismiss)
	if action then
		local button = Kit.hitbox({
			Text = action.label,
			Position = UDim2.fromScale(0.72, 0.15),
			Size = UDim2.fromScale(0.19, 0.7),
			ZIndex = 133,
			Parent = card,
		})
		button.BackgroundTransparency = 0
		Theme.bind(button, "BackgroundColor3", "accent")
		Theme.bind(button, "TextColor3", "accentText")
		button.FontFace = message.FontFace
		button.TextSize = message.TextSize
		button.Activated:Connect(function()
			dismiss()
			action.run()
		end)
	end
	local children = {}
	for _, child in stack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 3 then
		(children[1] :: Frame):Destroy()
	end
	task.delay(Config.interaction.toastSeconds + (if action then 7 else 0), dismiss)
end

local function closeModal()
	modalRoot = nil
	if modalMaid then
		modalMaid:destroy()
		modalMaid = nil
	end
end

function Overlay.isCovered(target: Instance): boolean
	local root = modalRoot
	return root ~= nil and root.Parent ~= nil and not target:IsDescendantOf(root)
end

Overlay.closeModal = closeModal

function Overlay.modalCard(heightScale: number): (Frame, Maid.Maid)
	closeModal()
	local maid = Maid.new()
	modalMaid = maid
	local dim = Kit.frame({ BackgroundTransparency = 0.45, ZIndex = 110, Parent = layer })
	Theme.bind(dim, "BackgroundColor3", "overlay")
	modalRoot = dim
	local blocker = Kit.hitbox({ ZIndex = 111, Parent = dim })
	maid:give(blocker.Activated:Connect(closeModal))
	maid:give(dim)
	local card = Kit.surface("canvas", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.88, heightScale),
		ZIndex = 112,
		Parent = dim,
	}, { Kit.paddingXY(0.05, 0.04) })
	Kit.hitbox({ ZIndex = 112, Parent = card })
	return card, maid
end

function Overlay.notes(options: { title: string, subtitle: string, bullets: { string } })
	local card, maid = Overlay.modalCard(0.62)
	local title = Kit.label({
		text = options.title,
		role = "title",
		props = { Size = UDim2.fromScale(0.84, 0.1), ZIndex = 113 },
	})
	title.Parent = card
	local subtitle = Kit.label({
		text = options.subtitle,
		role = "meta",
		token = "subtext",
		props = { Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(0.84, 0.07), ZIndex = 113 },
	})
	subtitle.Parent = card

	local close = Kit.hitbox({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.1, 0.1),
		ZIndex = 114,
		Parent = card,
	})
	Kit.square().Parent = close
	local x = Kit.icon(Config.icons.close, "subtext", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		ZIndex = 115,
	})
	x.Parent = close
	maid:give(close.Activated:Connect(closeModal))

	local list = Kit.create("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.2),
		Size = UDim2.fromScale(1, 0.8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		ZIndex = 113,
		Parent = card,
	})
	local rows = {}
	for index, text in options.bullets do
		local line: Frame? = nil
		if index > 1 then
			local divider = Kit.surface("dim", { ZIndex = 113, Parent = list })
			divider.BackgroundTransparency = 0.55
			Kit.create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = divider,
			})
			line = divider
		end
		local row = Kit.frame({ ZIndex = 113, Parent = list })
		local dot = Kit.label({
			text = "•",
			role = "body",
			token = "accent",
			yAlign = Enum.TextYAlignment.Top,
			noPeek = true,
			props = { Size = UDim2.fromScale(0.06, 1), ZIndex = 113 },
		})
		dot.Parent = row
		local body = Kit.label({
			text = text,
			role = "body",
			token = "text",
			wrap = true,
			yAlign = Enum.TextYAlignment.Top,
			props = { Position = UDim2.fromScale(0.06, 0), Size = UDim2.fromScale(0.94, 1), ZIndex = 113 },
		})
		body.Parent = row
		table.insert(rows, { row = row, body = body, text = text, line = line })
	end

	local function layout()
		local width = list.AbsoluteSize.X
		local height = list.AbsoluteSize.Y
		if width <= 0 or height <= 0 then
			return
		end
		local heights = {}
		local total = 0
		for index, entry in rows do
			local size = entry.body.TextSize
			local ok, bounds = pcall(
				TextService.GetTextSize,
				TextService,
				entry.text,
				size,
				Enum.Font.BuilderSans,
				Vector2.new(width * 0.94 * 0.86, 100000)
			)
			local textHeight = if ok then bounds.Y else size * 3
			heights[index] = (textHeight + size * 0.3) / 0.9
			total += heights[index]
		end
		local gap = (rows[1] and rows[1].body.TextSize or 16) * 0.9
		total += gap * math.max(0, #rows - 1)
		local inner = width - list.ScrollBarThickness
		list.CanvasSize = UDim2.fromOffset(0, total)
		local y = 0
		for index, entry in rows do
			local line = entry.line
			if line then
				line.Position = UDim2.fromOffset(math.floor(inner * 0.1), math.floor(y + gap / 2))
				line.Size = UDim2.fromOffset(math.floor(inner * 0.8), 1)
				y += gap
			end
			entry.row.Position = UDim2.fromOffset(0, math.floor(y))
			entry.row.Size = UDim2.fromOffset(inner, math.ceil(heights[index]))
			y += heights[index]
		end
	end
	maid:give(list:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	task.defer(layout)
end

export type ConfirmOptions = {
	title: string,
	body: string,
	confirm: string,
	danger: boolean?,
	onConfirm: () -> (),
}

function Overlay.confirm(options: ConfirmOptions)
	local card, maid = Overlay.modalCard(0.34)
	local title = Kit.label({
		text = options.title,
		role = "title",
		token = if options.danger then "danger" else "text",
		props = { Size = UDim2.fromScale(1, 0.22), ZIndex = 113 },
	})
	title.Parent = card
	local body = Kit.label({
		text = options.body,
		role = "body",
		token = "subtext",
		wrap = true,
		yAlign = Enum.TextYAlignment.Top,
		props = { Position = UDim2.fromScale(0, 0.24), Size = UDim2.fromScale(1, 0.46), ZIndex = 113 },
	})
	body.Parent = card
	local function makeButton(text: string, danger: boolean, primary: boolean, x: number, onClick: () -> ())
		local button = Kit.hitbox({
			Text = text,
			Position = UDim2.fromScale(x, 0.74),
			Size = UDim2.fromScale(0.48, 0.24),
			ZIndex = 114,
			Parent = card,
		})
		button.BackgroundTransparency = 0
		Theme.bind(button, "BackgroundColor3", if danger then "danger" elseif primary then "accent" else "card")
		Theme.bind(button, "TextColor3", if danger then "dangerText" elseif primary then "accentText" else "text")
		button.FontFace = title.FontFace
		button.TextSize = body.TextSize
		maid:give(button.Activated:Connect(onClick))
	end
	makeButton("Cancel", false, false, 0, closeModal)
	makeButton(options.confirm, options.danger == true, true, 0.52, function()
		closeModal()
		options.onConfirm()
	end)
end

export type PromptOptions = {
	title: string,
	body: string?,
	placeholder: string,
	confirm: string,
	initial: string?,
	maxLength: number,
	readOnly: boolean?,
	onConfirm: ((string) -> ())?,
}

function Overlay.prompt(options: PromptOptions)
	local card, maid = Overlay.modalCard(0.4)
	local title =
		Kit.label({ text = options.title, role = "title", props = { Size = UDim2.fromScale(1, 0.18), ZIndex = 113 } })
	title.Parent = card
	if options.body then
		local body = Kit.label({
			text = options.body,
			role = "meta",
			token = "subtext",
			wrap = true,
			props = { Position = UDim2.fromScale(0, 0.18), Size = UDim2.fromScale(1, 0.22), ZIndex = 113 },
		})
		body.Parent = card
	end
	local field = Kit.surface(
		"input",
		{ Position = UDim2.fromScale(0, 0.42), Size = UDim2.fromScale(1, 0.26), ZIndex = 113, Parent = card },
		{}
	)
	local input = Kit.create("TextBox", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = options.initial or "",
		PlaceholderText = options.placeholder,
		ClearTextOnFocus = false,
		TextEditable = not options.readOnly,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 114,
		Parent = field,
	}, { Kit.padding() })
	input.FontFace = title.FontFace
	input.TextSize = math.max(12, title.TextSize - 3)
	Theme.bind(input, "TextColor3", "text")
	Theme.bind(input, "PlaceholderColor3", "dim")
	maid:give(input:GetPropertyChangedSignal("Text"):Connect(function()
		if not options.readOnly and #input.Text > options.maxLength then
			input.Text = string.sub(input.Text, 1, options.maxLength)
		end
	end))
	local function submit()
		local text = string.match(input.Text, "^%s*(.-)%s*$") or ""
		if options.readOnly then
			closeModal()
			return
		end
		if text == "" then
			return
		end
		closeModal()
		if options.onConfirm then
			options.onConfirm(text)
		end
	end
	maid:give(input.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end))
	local function makeButton(text: string, primary: boolean, x: number, width: number, onClick: () -> ())
		local button = Kit.hitbox({
			Text = text,
			Position = UDim2.fromScale(x, 0.76),
			Size = UDim2.fromScale(width, 0.22),
			ZIndex = 114,
			Parent = card,
		})
		button.BackgroundTransparency = 0
		Theme.bind(button, "BackgroundColor3", if primary then "accent" else "card")
		Theme.bind(button, "TextColor3", if primary then "accentText" else "text")
		button.FontFace = title.FontFace
		button.TextSize = input.TextSize
		maid:give(button.Activated:Connect(onClick))
	end
	if options.readOnly then
		makeButton(options.confirm, true, 0, 1, closeModal)
		task.defer(function()
			input:CaptureFocus()
			input.SelectionStart = 1
			input.CursorPosition = #input.Text + 1
		end)
	else
		makeButton("Cancel", false, 0, 0.48, closeModal)
		makeButton(options.confirm, true, 0.52, 0.48, submit)
		task.defer(function()
			input:CaptureFocus()
		end)
	end
end

export type MenuItem = { text: string, run: () -> (), danger: boolean? }

local menuCounter = 0

function Overlay.menu(items: { MenuItem })
	local plugin = pluginRef
	if not plugin or #items == 0 then
		return
	end
	menuCounter += 1
	local menu = plugin:CreatePluginMenu(Config.actionPrefix .. "Menu" .. menuCounter, "")
	local byAction: { [PluginAction]: MenuItem } = {}
	for index, item in items do
		local action = menu:AddNewAction(Config.actionPrefix .. "Item" .. menuCounter .. "x" .. index, item.text)
		byAction[action] = item
	end
	task.spawn(function()
		local picked = menu:ShowAsync()
		local item = if picked then byAction[picked] else nil
		menu:Destroy()
		if item then
			item.run()
		end
	end)
end

function Overlay.layer(): Frame?
	return layer
end

function Overlay.highlight(
	target: GuiObject?,
	title: string,
	body: string,
	step: string,
	onNext: () -> (),
	onSkip: () -> (),
	nextText: string?
): Maid.Maid
	closeModal()
	local maid = Maid.new()
	modalMaid = maid
	local frame = layer :: Frame
	local dim = Kit.frame({ BackgroundTransparency = 0.55, ZIndex = 115, Parent = frame })
	Theme.bind(dim, "BackgroundColor3", "overlay")
	Kit.hitbox({ ZIndex = 116, Parent = dim })
	maid:give(dim)
	if target and target.Parent then
		local position, size = toLayer(target.AbsolutePosition, target.AbsoluteSize)
		local ring = Kit.frame({ Position = position, Size = size, ZIndex = 117, Parent = frame })
		ring.BackgroundTransparency = 0.9
		ring.BackgroundColor3 = Config.brand.blue
		local outline = Kit.create("UIStroke", {
			StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
			Thickness = 0.012,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.new(1, 1, 1),
			Parent = ring,
		})
		local sweep = Kit.create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Config.brand.blue),
				ColorSequenceKeypoint.new(0.5, Config.brand.redBright),
				ColorSequenceKeypoint.new(1, Config.brand.blue),
			}),
			Parent = outline,
		})
		maid:give(game:GetService("RunService").Heartbeat:Connect(function(dt)
			sweep.Rotation = (sweep.Rotation + dt * 120) % 360
		end))
		maid:give(ring)
	end
	local below = if target
		then (target.AbsolutePosition.Y - frame.AbsolutePosition.Y) / frame.AbsoluteSize.Y < 0.5
		else true
	local card = Kit.surface("canvas", {
		AnchorPoint = Vector2.new(0.5, if below then 1 else 0),
		Position = UDim2.fromScale(0.5, if below then 0.95 else 0.05),
		Size = UDim2.fromScale(0.9, 0.3),
		ZIndex = 118,
		Parent = frame,
	}, { Kit.paddingXY(0.05, 0.05) })
	maid:give(card)
	local stepLabel = Kit.label({
		text = step,
		role = "hint",
		token = "accent",
		props = { Size = UDim2.fromScale(1, 0.14), ZIndex = 119 },
	})
	stepLabel.Parent = card
	local titleLabel = Kit.label({
		text = title,
		role = "title",
		props = { Position = UDim2.fromScale(0, 0.14), Size = UDim2.fromScale(1, 0.2), ZIndex = 119 },
	})
	titleLabel.Parent = card
	local bodyLabel = Kit.label({
		text = body,
		role = "meta",
		token = "subtext",
		wrap = true,
		yAlign = Enum.TextYAlignment.Top,
		props = { Position = UDim2.fromScale(0, 0.36), Size = UDim2.fromScale(1, 0.38), ZIndex = 119 },
	})
	bodyLabel.Parent = card
	local function makeButton(text: string, primary: boolean, x: number, onClick: () -> ())
		local button = Kit.hitbox({
			Text = text,
			Position = UDim2.fromScale(x, 0.78),
			Size = UDim2.fromScale(0.48, 0.22),
			ZIndex = 120,
			Parent = card,
		})
		button.BackgroundTransparency = 0
		Theme.bind(button, "BackgroundColor3", if primary then "accent" else "card")
		Theme.bind(button, "TextColor3", if primary then "accentText" else "text")
		button.FontFace = titleLabel.FontFace
		button.TextSize = bodyLabel.TextSize
		maid:give(button.Activated:Connect(onClick))
	end
	makeButton("Skip", false, 0, onSkip)
	makeButton(nextText or "Next", true, 0.52, onNext)
	return maid
end

return Overlay
