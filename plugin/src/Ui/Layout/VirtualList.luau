--!strict

local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Typography = require(script.Parent.Parent.Typography)

export type Row = { root: GuiObject, bind: (any, any, number, number) -> (), destroy: ((any) -> ())? }

export type Options = {
	parent: Instance,
	rowRatio: number,
	minRowRole: string?,
	build: () -> Row,
	lines: ((any) -> number)?,
	lineGrowth: number?,
	lineHeight: (() -> number)?,
	empty: GuiObject?,
	props: Kit.Props?,
}

local VirtualList = {}
VirtualList.__index = VirtualList

export type VirtualList = typeof(setmetatable(
	{} :: {
		frame: ScrollingFrame,
		options: Options,
		data: { any },
		pool: { Row },
		used: { [number]: Row },
		offsets: { number },
		heights: { number },
		unit: number,
		locked: boolean,
		maid: Maid.Maid,
	},
	VirtualList
))

function VirtualList.new(options: Options, maid: Maid.Maid): VirtualList
	local frame = Kit.scroll(options.props)
	frame.Parent = options.parent
	local self = setmetatable({
		frame = frame,
		options = options,
		data = {},
		pool = {},
		used = {},
		offsets = {},
		heights = {},
		unit = 0,
		locked = false,
		maid = maid,
	}, VirtualList)
	maid:give(frame)
	maid:give(frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if self.locked then
			self:render()
		end
	end))
	if options.empty then
		options.empty.Parent = frame
		options.empty.Visible = false
	end
	return self
end

function VirtualList.setData(self: VirtualList, data: { any })
	self.data = data
	if self.options.empty then
		self.options.empty.Visible = #data == 0
	end
	if self.locked then
		self:lock()
	end
end

function VirtualList.lock(self: VirtualList)
	local size = self.frame.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	self.locked = true
	local minRow = Typography.lineHeight(self.options.minRowRole or "body") * 2
	local target = math.max(minRow, 480 * Typography.rowScale() / self.options.rowRatio)
	local rowsThatFit = math.max(1, math.floor(size.Y / target))
	local unit = size.Y / rowsThatFit
	self.unit = unit
	local growth = if self.options.lineHeight
		then self.options.lineHeight() / unit
		else self.options.lineGrowth or Kit.rows.lineGrowth
	local total = 0
	table.clear(self.offsets)
	table.clear(self.heights)
	for index, item in self.data do
		local lines = if self.options.lines then math.max(1, self.options.lines(item)) else 1
		local height = unit * (1 + (lines - 1) * growth)
		self.offsets[index] = total
		self.heights[index] = height
		total += height
	end
	local extraRows = math.max(0, #self.data - rowsThatFit)
	local canvas = if total > size.Y then total else size.Y
	if not self.options.lines then
		canvas = size.Y + extraRows * (size.Y / rowsThatFit)
	end
	self.frame.CanvasSize = UDim2.fromOffset(0, canvas)
	self:render()
end

function VirtualList.reset(self: VirtualList)
	self.locked = false
	for index, row in self.used do
		row.root.Visible = false
		table.insert(self.pool, row)
		self.used[index] = nil
	end
	self.frame.CanvasSize = UDim2.fromScale(0, 0)
end

local function search(offsets: { number }, y: number): number
	local low, high = 1, #offsets
	while low < high do
		local mid = (low + high + 1) // 2
		if offsets[mid] <= y then
			low = mid
		else
			high = mid - 1
		end
	end
	return low
end

function VirtualList.render(self: VirtualList)
	local count = #self.data
	local view = self.frame.CanvasPosition.Y
	local height = self.frame.AbsoluteSize.Y
	local first = if count > 0 then search(self.offsets, view) else 1
	local last = first
	while last < count and self.offsets[last + 1] < view + height do
		last += 1
	end
	first = math.max(1, first - 1)
	last = math.min(count, last + 1)

	for index, row in self.used do
		if index < first or index > last or count == 0 then
			row.root.Visible = false
			table.insert(self.pool, row)
			self.used[index] = nil
		end
	end
	if count == 0 then
		return
	end
	for index = first, last do
		local row = self.used[index]
		if not row then
			row = table.remove(self.pool) or self.options.build()
			row.root.Parent = self.frame
			self.used[index] = row
		end
		row.root.Visible = true
		row.root.Position = UDim2.fromOffset(0, self.offsets[index])
		row.root.Size = UDim2.new(1, 0, 0, self.heights[index])
		row.bind(row, self.data[index], index, self.heights[index] / math.max(1, self.unit))
	end
end

function VirtualList.refreshRows(self: VirtualList)
	for index, row in self.used do
		if self.data[index] then
			row.bind(row, self.data[index], index, (self.heights[index] or self.unit) / math.max(1, self.unit))
		end
	end
end

function VirtualList.indexAt(self: VirtualList, absoluteY: number): number
	local y = absoluteY - self.frame.AbsolutePosition.Y + self.frame.CanvasPosition.Y
	if #self.offsets == 0 then
		return 1
	end
	local index = search(self.offsets, y)
	local middle = self.offsets[index] + (self.heights[index] or 0) / 2
	return if y > middle then index + 1 else index
end

function VirtualList.scrollTo(self: VirtualList, index: number)
	local offset = self.offsets[index]
	if offset then
		self.frame.CanvasPosition = Vector2.new(0, math.max(0, offset - self.unit))
	end
end

return VirtualList
