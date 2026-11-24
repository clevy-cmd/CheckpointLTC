--!strict

local TextService = game:GetService("TextService")

local Config = require(script.Parent.Parent.Parent.Config)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Theme = require(script.Parent.Parent.Theme)
local Typography = require(script.Parent.Parent.Typography)

export type Options = {
	parent: Instance,
	placeholder: string,
	maxLength: () -> number,
	role: string?,
	multiline: boolean?,
	keepOnSubmit: boolean?,
	clearOnSubmit: boolean?,
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
		options: Options,
		lines: number,
		maid: Maid.Maid,
	},
	GrowingTextBox
))

local function legacyFont(): Enum.Font
	return Enum.Font.BuilderSans
end

function GrowingTextBox.new(options: Options, maid: Maid.Maid): GrowingTextBox
	local z = options.zIndex or 20
	local slot = Kit.frame({ Parent = options.parent, ClipsDescendants = false, ZIndex = z })
	local box = Kit.surface("input", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = slot,
	}, {})
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
		options = options,
		lines = 1,
		maid = maid,
	}, GrowingTextBox)

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
		if options.onFocusLost then
			options.onFocusLost(text, enterPressed)
		end
		if enterPressed and not options.multiline and options.onSubmit then
			local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
			if trimmed ~= "" then
				options.onSubmit(trimmed)
				if options.clearOnSubmit ~= false and not options.keepOnSubmit then
					input.Text = ""
				end
			end
		end
		self:collapse()
	end))
	maid:give(slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:measure()
	end))
	return self
end

function GrowingTextBox.textWidth(self: GrowingTextBox): number
	return math.max(1, self.input.AbsoluteSize.X * 0.9)
end

function GrowingTextBox.heightOf(self: GrowingTextBox, text: string): number
	local size =
		TextService:GetTextSize(text, self.input.TextSize, legacyFont(), Vector2.new(self:textWidth(), math.huge))
	return size.Y
end

function GrowingTextBox.lineCount(self: GrowingTextBox): number
	local lineHeight = math.max(1, self.input.TextSize)
	local bounds =
		math.max(self.input.TextBounds.Y, self:heightOf(if self.input.Text == "" then " " else self.input.Text))
	return math.max(1, math.floor(bounds / lineHeight + 0.5))
end

function GrowingTextBox.measure(self: GrowingTextBox)
	local slotHeight = self.slot.AbsoluteSize.Y
	if slotHeight <= 0 then
		return
	end
	local focused = self.input:IsFocused()
	local lines = if focused then self:lineCount() else 1
	if self.input.Text == "" then
		lines = 1
	end
	local maxLines = Config.interaction.maxInputLines
	local shown = math.min(lines, maxLines)
	local lineHeight = self.input.TextSize
	local growth = lineHeight / slotHeight
	local scaleY = 1 + (shown - 1) * growth
	self.box.Size = UDim2.fromScale(1, scaleY)
	self.counter.Size = UDim2.fromScale(0.3, 0.5 / scaleY)
	local contentHeight = lines * lineHeight + slotHeight * 0.5
	if lines > maxLines then
		self.scroller.CanvasSize = UDim2.fromOffset(0, contentHeight)
		self.input.Size = UDim2.new(1, 0, 0, contentHeight)
	else
		self.scroller.CanvasSize = UDim2.fromScale(0, 0)
		self.input.Size = UDim2.fromScale(1, 1)
	end
	if lines ~= self.lines then
		self.lines = lines
		if self.options.onLinesChanged then
			self.options.onLinesChanged(shown)
		end
	end
	local limit = self.options.maxLength()
	local length = utf8.len(self.input.Text) or #self.input.Text
	self.counter.Visible = length >= math.floor(limit * Config.interaction.counterFromFraction)
	self.counter.Text = string.format("%d / %d", length, limit)
	Theme.bind(self.counter, "TextColor3", if length >= limit then "danger" else "dim")
	self:keepCursorVisible()
end

function GrowingTextBox.keepCursorVisible(self: GrowingTextBox)
	if self.lines <= Config.interaction.maxInputLines then
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
	local lineHeight = self.input.TextSize
	if y > top + view - lineHeight then
		self.scroller.CanvasPosition = Vector2.new(0, y - view + lineHeight * 1.5)
	elseif y - lineHeight < top then
		self.scroller.CanvasPosition = Vector2.new(0, math.max(0, y - lineHeight * 1.5))
	end
end

function GrowingTextBox.collapse(self: GrowingTextBox)
	self.box.Size = UDim2.fromScale(1, 1)
	self.scroller.CanvasSize = UDim2.fromScale(0, 0)
	self.scroller.CanvasPosition = Vector2.zero
	self.input.Size = UDim2.fromScale(1, 1)
	self.counter.Visible = false
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
end

return GrowingTextBox
