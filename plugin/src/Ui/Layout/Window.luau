--!strict

local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local Auth = require(script.Parent.Parent.Parent.Api.Auth)
local Config = require(script.Parent.Parent.Parent.Config)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Theme = require(script.Parent.Parent.Theme)

local Window = {}

export type Window = {
	gui: ScreenGui,
	frame: Frame,
	host: Frame,
	attachDrag: (GuiObject) -> (),
}

local placementKey = "windowPlacement"
local minWidth, minHeight = 360, 440

local function viewport(gui: ScreenGui): Vector2
	local size = gui.AbsoluteSize
	return if size.X > 0 and size.Y > 0 then size else Vector2.new(1280, 720)
end

function Window.new(maid: Maid.Maid): Window
	local gui = Instance.new("ScreenGui")
	gui.Name = Config.widgetId
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false
	gui.Parent = CoreGui
	maid:give(gui)

	local saved = Auth.getSetting(placementKey)
	local frame = Kit.surface("canvas", {
		Name = "Window",
		Position = UDim2.fromScale(0.66, 0.1),
		Size = UDim2.fromScale(0.36, 0.8),
		Active = true,
		Parent = gui,
	})
	if type(saved) == "table" and #saved == 4 then
		frame.Position = UDim2.fromScale(saved[1], saved[2])
		frame.Size = UDim2.fromScale(saved[3], saved[4])
	end
	local edge = Kit.surface(
		"lineStrong",
		{ Position = UDim2.fromScale(-0.004, -0.003), Size = UDim2.fromScale(1.008, 1.006), ZIndex = 0, Parent = frame }
	)
	edge.Name = "Edge"
	local host = Kit.frame({ Name = "Host", ClipsDescendants = true, Parent = frame })

	local function clamp()
		local view = viewport(gui)
		local size = frame.AbsoluteSize
		local width = math.clamp(size.X, math.min(minWidth, view.X), view.X)
		local height = math.clamp(size.Y, math.min(minHeight, view.Y), view.Y)
		local x = math.clamp(frame.AbsolutePosition.X, 0, math.max(0, view.X - width))
		local y = math.clamp(frame.AbsolutePosition.Y, 0, math.max(0, view.Y - height))
		frame.Position = UDim2.fromScale(x / view.X, y / view.Y)
		frame.Size = UDim2.fromScale(width / view.X, height / view.Y)
	end

	local function save()
		Auth.setSetting(
			placementKey,
			{ frame.Position.X.Scale, frame.Position.Y.Scale, frame.Size.X.Scale, frame.Size.Y.Scale }
		)
	end

	local active: { mode: string, start: Vector2, position: Vector2, size: Vector2 }? = nil
	maid:give(UserInputService.InputChanged:Connect(function(input)
		local drag = active
		if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local view = viewport(gui)
		local mouse = UserInputService:GetMouseLocation()
		local delta = mouse - drag.start
		if drag.mode == "move" then
			local x = math.clamp(drag.position.X + delta.X, 0, math.max(0, view.X - frame.AbsoluteSize.X))
			local y = math.clamp(drag.position.Y + delta.Y, 0, math.max(0, view.Y - frame.AbsoluteSize.Y))
			frame.Position = UDim2.fromScale(x / view.X, y / view.Y)
		else
			local width = math.clamp(
				drag.size.X + delta.X,
				math.min(minWidth, view.X),
				math.max(math.min(minWidth, view.X), view.X - frame.AbsolutePosition.X)
			)
			local height = math.clamp(
				drag.size.Y + delta.Y,
				math.min(minHeight, view.Y),
				math.max(math.min(minHeight, view.Y), view.Y - frame.AbsolutePosition.Y)
			)
			frame.Size = UDim2.fromScale(width / view.X, height / view.Y)
		end
	end))
	maid:give(UserInputService.InputEnded:Connect(function(input)
		if active and input.UserInputType == Enum.UserInputType.MouseButton1 then
			active = nil
			save()
		end
	end))

	local function begin(mode: string)
		active = {
			mode = mode,
			start = UserInputService:GetMouseLocation(),
			position = frame.AbsolutePosition,
			size = frame.AbsoluteSize,
		}
	end

	local grip = Kit.frame({
		Name = "ResizeGrip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromScale(0.05, 0.05),
		ZIndex = 200,
		Parent = frame,
	}, { Kit.square() })
	for index = 1, 3 do
		local bar = Kit.surface("dim", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1 - (index - 1) * 0.3, 1),
			Size = UDim2.fromScale(0.16, 0.16 + (3 - index) * 0.3),
			ZIndex = 200,
			Parent = grip,
		})
		bar.Name = "Bar"
	end
	local gripHit = Kit.hitbox({ ZIndex = 201, Parent = grip })
	maid:give(gripHit.MouseButton1Down:Connect(function()
		begin("resize")
	end))

	maid:give(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(clamp))
	maid:give(gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			task.defer(clamp)
		end
	end))
	Theme.bind(frame, "BackgroundColor3", "canvas")

	return {
		gui = gui,
		frame = frame,
		host = host,
		attachDrag = function(target: GuiObject)
			maid:give(target.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					begin("move")
				end
			end))
		end,
	}
end

return Window
