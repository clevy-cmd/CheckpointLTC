--!strict

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Parent.Config)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)

export type Target = { lock: (any) -> (), reset: (any) -> () }

local PixelLock = {}
PixelLock.__index = PixelLock

export type PixelLock = typeof(setmetatable(
	{} :: {
		root: GuiObject,
		targets: { Target },
		maid: Maid.Maid,
		resizeMaid: Maid.Maid,
		lastSize: Vector2,
		stableSince: number,
		resizing: boolean,
		locked: boolean,
	},
	PixelLock
))

function PixelLock.new(root: GuiObject, maid: Maid.Maid): PixelLock
	local self = setmetatable({
		root = root,
		targets = {},
		maid = maid,
		resizeMaid = Maid.new(),
		lastSize = root.AbsoluteSize,
		stableSince = os.clock(),
		resizing = false,
		locked = false,
	}, PixelLock)
	maid:give(self.resizeMaid)
	maid:give(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:startResize()
	end))
	return self
end

function PixelLock.register(self: PixelLock, target: Target)
	table.insert(self.targets, target)
	if self.locked then
		target:lock()
	end
end

function PixelLock.unregister(self: PixelLock, target: Target)
	local index = table.find(self.targets, target)
	if index then
		table.remove(self.targets, index)
	end
end

function PixelLock.lockAll(self: PixelLock)
	if not self.locked then
		return
	end
	for _, target in table.clone(self.targets) do
		target:lock()
	end
end

function PixelLock.open(self: PixelLock)
	self.locked = true
	task.defer(function()
		RunService.Heartbeat:Wait()
		self:lockAll()
	end)
end

function PixelLock.close(self: PixelLock)
	self.locked = false
	self.resizeMaid:clean()
	self.resizing = false
	for _, target in table.clone(self.targets) do
		target:reset()
	end
end

function PixelLock.contentChanged(self: PixelLock)
	if self.locked and not self.resizing then
		self:lockAll()
	end
end

function PixelLock.startResize(self: PixelLock)
	if not self.locked then
		return
	end
	self.stableSince = os.clock()
	if self.resizing then
		return
	end
	self.resizing = true
	self.lastSize = self.root.AbsoluteSize
	self.resizeMaid:give(RunService.Heartbeat:Connect(function()
		local size = self.root.AbsoluteSize
		if size ~= self.lastSize then
			self.lastSize = size
			self.stableSince = os.clock()
		end
		self:lockAll()
		if os.clock() - self.stableSince >= Config.interaction.resizeSettleSeconds then
			self.resizing = false
			self.resizeMaid:clean()
			self:lockAll()
		end
	end))
end

return PixelLock
