--!strict

local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Typography = require(script.Parent.Parent.Typography)

export type Entry = { child: GuiObject, ratio: number | (number) -> number }

local Stack = {}

local maxDesignWidth = 440
Stack.__index = Stack

export type Stack = typeof(setmetatable(
	{} :: {
		frame: ScrollingFrame,
		entries: { Entry },
		gap: number,
		locked: boolean,
		maid: Maid.Maid,
	},
	Stack
))

function Stack.new(parent: Instance, maid: Maid.Maid, props: Kit.Props?, gap: number?): Stack
	local frame = Kit.scroll(props)
	frame.Parent = parent
	maid:give(frame)
	return setmetatable({ frame = frame, entries = {}, gap = gap or 0.015, locked = false, maid = maid }, Stack)
end

function Stack.add(self: Stack, child: GuiObject, ratio: number | (number) -> number): GuiObject
	table.insert(self.entries, { child = child, ratio = ratio })
	child.Size = UDim2.fromScale(1, 1 / math.max(1, #self.entries))
	child.Parent = self.frame
	if self.locked then
		self:lock()
	end
	return child
end

function Stack.clear(self: Stack)
	for _, entry in self.entries do
		entry.child:Destroy()
	end
	table.clear(self.entries)
	if self.locked then
		self:lock()
	end
end

function Stack.lock(self: Stack)
	local size = self.frame.AbsoluteSize
	if size.X <= 0 then
		return
	end
	self.locked = true
	local padding = self.frame:FindFirstChildOfClass("UIPadding")
	local inset = if padding then size.X * (padding.PaddingLeft.Scale + padding.PaddingRight.Scale) else 0
	local width = size.X - inset - self.frame.ScrollBarThickness
	local designWidth = maxDesignWidth * Typography.rowScale()
	local gap = designWidth * self.gap
	local y = gap
	for _, entry in self.entries do
		if entry.child.Visible then
			local ratio = if type(entry.ratio) == "function"
				then (entry.ratio :: any)(designWidth, width)
				else entry.ratio
			local height = designWidth / math.max(0.1, ratio :: number)
			entry.child.Position = UDim2.fromOffset(0, y)
			entry.child.Size = UDim2.fromOffset(width, height)
			y += height + gap
		end
	end
	self.frame.CanvasSize = UDim2.fromOffset(0, math.max(size.Y, y))
end

function Stack.reset(self: Stack)
	self.locked = false
	local count = math.max(1, #self.entries)
	for index, entry in self.entries do
		entry.child.Position = UDim2.fromScale(0, (index - 1) / count)
		entry.child.Size = UDim2.fromScale(1, 1 / count)
	end
	self.frame.CanvasSize = UDim2.fromScale(0, 0)
end

return Stack
