--!strict

local TextService = game:GetService("TextService")

local Config = require(script.Parent.Parent.Parent.Config)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Overlay)
local Theme = require(script.Parent.Parent.Theme)
local Typography = require(script.Parent.Parent.Typography)

export type Action = { icon: string, tooltip: string, shortcut: string? }

export type Options = {
	parent: Instance,
	placeholder: string,
	maxLength: () -> number,
	role: string?,
	multiline: boolean?,
	keepOnSubmit: boolean?,
	clearOnSubmit: boolean?,
	fill: boolean?,
	maxLines: number?,
	action: Action?,
	zIndex: number?,
	onSubmit: ((string) -> ())?,
	onChanged: ((string) -> ())?,
	onFocusLost: ((string, boolean) -> ())?,
	onLinesChanged: ((number) -> ())?,
}

local GrowingTextBox = {}
GrowingTextBox.__index = GrowingTextBox

export type GrowingTextBox = typeof(setmetatable(
	{} :: {
		slot: Frame,
		box: Frame,
		scroller: ScrollingFrame,
		input: TextBox,
		counter: TextLabel,
		actionButton: Frame?,
		options: Options,
		lines: number,
		floating: boolean,
		submittedAt: number,
		maid: Maid.Maid,
	},
	GrowingTextBox
))

local actionShare = 0.11

local function legacyFont(): Enum.Font
	return Enum.Font.BuilderSans
end

function GrowingTextBox.new(options: Options, maid: Maid.Maid): GrowingTextBox
	local z = options.zIndex or 20
	local slot = Kit.frame({ Parent = options.parent, ClipsDescendants = false, ZIndex = z })
	local width = if options.action then 1 - actionShare - 0.015 else 1
	local box = Kit.surface("input", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(width, 1),
		ZIndex = z,
		Parent = slot,
	}, {})
	local blocker = Kit.hitbox({ ZIndex = z, Parent = box })
	local scroller = Kit.scroll({ ZIndex = z + 1, ScrollBarThickness = 4, Parent = box })
	Kit.paddingXY(0.03, 0.05).Parent = scroller
	local input = Kit.create("TextBox", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		PlaceholderText = options.placeholder,
		ClearTextOnFocus = false,
		MultiLine = options.multiline == true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z + 2,
		Parent = scroller,
	}, { Kit.padding() })
	Typography.apply(input, options.role or "body")
	Theme.bind(input, "TextColor3", "text")
	Theme.bind(input, "PlaceholderColor3", "dim")
	local counter = Kit.label({
		text = "",
		role = "hint",
		token = "dim",
		align = Enum.TextXAlignment.Right,
		props = {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.3, 0.6),
			ZIndex = z + 3,
			Visible = false,
			Parent = box,
		},
	})

	local self = setmetatable({
		slot = slot,
		box = box,
		scroller = scroller,
		input = input,
		counter = counter,
		actionButton = nil :: Frame?,
		options = options,
		lines = 1,
		floating = false,
		submittedAt = 0,
		maid = maid,
	}, GrowingTextBox)

	maid:give(blocker.Activated:Connect(function()
		if input.TextEditable then
			input:CaptureFocus()
		end
	end))

	if options.action then
		local action = options.action
		local holder = Kit.frame({
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromScale(actionShare, 1),
			ZIndex = z,
			Parent = slot,
		})
		local face = Kit.surface("accent", { ZIndex = z, Parent = holder }, { Kit.square() })
		face.AnchorPoint = Vector2.new(1, 0.5)
		face.Position = UDim2.fromScale(1, 0.5)
		local glyph = Kit.glyphIcon(action.icon, "accentText", { Size = UDim2.fromScale(0.55, 0.55), ZIndex = z + 1 })
		glyph.Parent = face
		local hit = Kit.hitbox({ ZIndex = z + 2, Parent = face })
		maid:give(hit.MouseEnter:Connect(function()
			Theme.bind(face, "BackgroundColor3", "accentHover")
		end))
		maid:give(hit.MouseLeave:Connect(function()
			Theme.bind(face, "BackgroundColor3", "accent")
		end))
		maid:give(hit.Activated:Connect(function()
			if Overlay.isCovered(hit) or os.clock() - self.submittedAt < 0.4 then
				return
			end
			self:submit()
		end))
		Overlay.tooltip(hit, action.tooltip, action.shortcut, maid)
		self.actionButton = holder
	end

	maid:give(input:GetPropertyChangedSignal("Text"):Connect(function()
		local limit = options.maxLength()
		if utf8.len(input.Text) and (utf8.len(input.Text) :: number) > limit then
			local cut = utf8.offset(input.Text, limit + 1)
			if cut then
				input.Text = string.sub(input.Text, 1, cut - 1)
				return
			end
		end
		self:measure()
		if options.onChanged then
			options.onChanged(input.Text)
		end
	end))
	maid:give(input:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		self:keepCursorVisible()
	end))
	maid:give(input.Focused:Connect(function()
		self:measure()
	end))
	maid:give(input.FocusLost:Connect(function(enterPressed)
		local text = input.Text
		local viaButton = self:actionUnderMouse()
		if options.onFocusLost then
			options.onFocusLost(text, enterPressed or viaButton)
		end
		if viaButton then
			self.submittedAt = os.clock()
		end
		if (enterPressed and not options.multiline) or (viaButton and options.onSubmit) then
			self:submit()
		end
		if not options.fill then
			self:collapse()
		end
	end))
	maid:give(slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:measure()
	end))
	maid:give(function()
		Overlay.unregisterFloating(box)
	end)
	return self
end

function GrowingTextBox.actionUnderMouse(self: GrowingTextBox): boolean
	local button = self.actionButton
	if not button or not button.Visible then
		return false
	end
	local point = Overlay.mouse()
	local position, size = button.AbsolutePosition, button.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

function GrowingTextBox.submit(self: GrowingTextBox)
	local options = self.options
	if not options.onSubmit then
		if self.input:IsFocused() then
			self.input:ReleaseFocus(true)
		end
		return
	end
	local trimmed = string.match(self.input.Text, "^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return
	end
	options.onSubmit(trimmed)
	if options.clearOnSubmit ~= false and not options.keepOnSubmit then
		self.input.Text = ""
	end
end

function GrowingTextBox.textWidth(self: GrowingTextBox): number
	return math.max(1, self.input.AbsoluteSize.X * 0.9)
end

function GrowingTextBox.heightOf(self: GrowingTextBox, text: string, width: number?): number
	local size = TextService:GetTextSize(
		text,
		self.input.TextSize,
		legacyFont(),
		Vector2.new(width or self:textWidth(), math.huge)
	)
	return size.Y
end

function GrowingTextBox.lineHeight(self: GrowingTextBox): number
	return math.max(1, self:heightOf("Ag", 10000))
end

function GrowingTextBox.lineCount(self: GrowingTextBox, width: number?): number
	local lineHeight = self:lineHeight()
	local text = if self.input.Text == "" then " " else self.input.Text
	local bounds = self:heightOf(text, width)
	if not width then
		bounds = math.max(self.input.TextBounds.Y, bounds)
	end
	return math.max(1, math.floor(bounds / lineHeight + 0.5))
end

function GrowingTextBox.fitHeight(self: GrowingTextBox, slotWidth: number, collapsedLines: number?): number
	local share = if self.options.action then 1 - actionShare - 0.015 else 1
	local inner = slotWidth * share * 0.94 * 0.9
	local lines = self:lineCount(inner)
	local cap = math.min(self.options.maxLines or Config.interaction.maxFillLines, collapsedLines or math.huge)
	local shown = math.clamp(lines, 1, cap)
	local lineHeight = self:lineHeight()
	return shown * lineHeight / 0.9 / 0.9 + lineHeight * 0.4
end

function GrowingTextBox.setFloating(self: GrowingTextBox, floating: boolean)
	if floating == self.floating then
		return
	end
	self.floating = floating
	if floating then
		Overlay.registerFloating(self.box)
	else
		Overlay.unregisterFloating(self.box)
	end
end

function GrowingTextBox.measure(self: GrowingTextBox)
	local slotHeight = self.slot.AbsoluteSize.Y
	if slotHeight <= 0 then
		return
	end
	local focused = self.input:IsFocused()
	local fill = self.options.fill == true
	local lines = if focused or fill then self:lineCount() else 1
	if self.input.Text == "" then
		lines = 1
	end
	local lineHeight = self:lineHeight()
	if fill then
		local inner = self.scroller.AbsoluteSize.Y * 0.9
		local fits = math.max(1, math.floor(inner / lineHeight + 0.05))
		self.box.Size = UDim2.fromScale(self.box.Size.X.Scale, 1)
		if lines > fits then
			local contentHeight = lines * lineHeight / 0.9 + lineHeight
			self.scroller.CanvasSize = UDim2.fromOffset(0, contentHeight)
			self.input.Size = UDim2.new(1, 0, 0, contentHeight)
		else
			self.scroller.CanvasSize = UDim2.fromScale(0, 0)
			self.input.Size = UDim2.fromScale(1, 1)
		end
	else
		local maxLines = Config.interaction.maxInputLines
		local shown = math.min(lines, maxLines)
		local growth = lineHeight / slotHeight
		local scaleY = 1 + (shown - 1) * growth
		self.box.Size = UDim2.fromScale(self.box.Size.X.Scale, scaleY)
		self.counter.Size = UDim2.fromScale(0.3, 0.5 / scaleY)
		self:setFloating(scaleY > 1.01)
		local contentHeight = lines * lineHeight + slotHeight * 0.5
		if lines > maxLines then
			self.scroller.CanvasSize = UDim2.fromOffset(0, contentHeight)
			self.input.Size = UDim2.new(1, 0, 0, contentHeight)
		else
			self.scroller.CanvasSize = UDim2.fromScale(0, 0)
			self.input.Size = UDim2.fromScale(1, 1)
		end
	end
	if lines ~= self.lines then
		self.lines = lines
		if self.options.onLinesChanged then
			self.options.onLinesChanged(lines)
		end
	end
	local limit = self.options.maxLength()
	local length = utf8.len(self.input.Text) or #self.input.Text
	self.counter.Visible = focused and length >= math.floor(limit * Config.interaction.counterFromFraction)
	self.counter.Text = string.format("%d / %d", length, limit)
	Theme.bind(self.counter, "TextColor3", if length >= limit then "danger" else "dim")
	self:keepCursorVisible()
end

function GrowingTextBox.keepCursorVisible(self: GrowingTextBox)
	if self.scroller.CanvasSize.Y.Offset <= 0 then
		return
	end
	local cursor = self.input.CursorPosition
	if cursor < 1 then
		return
	end
	local before = string.sub(self.input.Text, 1, cursor - 1)
	local y = self:heightOf(if before == "" then " " else before)
	local view = self.scroller.AbsoluteSize.Y
	local top = self.scroller.CanvasPosition.Y
	local lineHeight = self:lineHeight()
	if y > top + view - lineHeight then
		self.scroller.CanvasPosition = Vector2.new(0, y - view + lineHeight * 1.5)
	elseif y - lineHeight < top then
		self.scroller.CanvasPosition = Vector2.new(0, math.max(0, y - lineHeight * 1.5))
	end
end

function GrowingTextBox.collapse(self: GrowingTextBox)
	self.box.Size = UDim2.fromScale(self.box.Size.X.Scale, 1)
	self.scroller.CanvasSize = UDim2.fromScale(0, 0)
	self.scroller.CanvasPosition = Vector2.zero
	self.input.Size = UDim2.fromScale(1, 1)
	self.counter.Visible = false
	self:setFloating(false)
	if self.lines ~= 1 then
		self.lines = 1
		if self.options.onLinesChanged then
			self.options.onLinesChanged(1)
		end
	end
end

function GrowingTextBox.setText(self: GrowingTextBox, text: string)
	self.input.Text = text
	self:measure()
end

function GrowingTextBox.getText(self: GrowingTextBox): string
	return self.input.Text
end

function GrowingTextBox.focus(self: GrowingTextBox)
	self.input:CaptureFocus()
end

function GrowingTextBox.setPlaceholder(self: GrowingTextBox, text: string)
	self.input.PlaceholderText = text
end

function GrowingTextBox.setEditable(self: GrowingTextBox, editable: boolean)
	self.input.TextEditable = editable
	self.box.BackgroundTransparency = if editable then 0 else 0.5
	if self.actionButton then
		self.actionButton.Visible = editable
	end
end

return GrowingTextBox
