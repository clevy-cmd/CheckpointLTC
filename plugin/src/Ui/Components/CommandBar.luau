--!strict

local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Overlay)
local Theme = require(script.Parent.Parent.Theme)
local Typography = require(script.Parent.Parent.Typography)

export type Command = { title: string, subtitle: string?, run: () -> () }

local CommandBar = {}

local maxRows = 8

local function score(command: Command, query: string): number
	if query == "" then
		return 1
	end
	local haystack = string.lower(command.title .. " " .. (command.subtitle or ""))
	local found = string.find(haystack, query, 1, true)
	if found then
		return 100 - found
	end
	local position = 1
	for index = 1, #query do
		local at = string.find(haystack, string.sub(query, index, index), position, true)
		if not at then
			return 0
		end
		position = at + 1
	end
	return 10
end

function CommandBar.open(commands: () -> { Command })
	local card, maid = Overlay.modalCard(0.62)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0.08)
	local field = Kit.surface("input", { Size = UDim2.fromScale(1, 0.12), ZIndex = 113, Parent = card }, {})
	local input = Kit.create("TextBox", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		PlaceholderText = "Type a list, a task or an action",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 114,
		Parent = field,
	}, { Kit.padding() })
	Typography.apply(input, "body")
	Theme.bind(input, "TextColor3", "text")
	Theme.bind(input, "PlaceholderColor3", "dim")
	local results =
		Kit.frame({ Position = UDim2.fromScale(0, 0.14), Size = UDim2.fromScale(1, 0.86), ZIndex = 113, Parent = card })
	local rows = {}
	local shown: { Command } = {}
	local selected = 1
	local rowMaid = Maid.new()
	maid:give(rowMaid)

	local function paint()
		for index, row in rows do
			Theme.bind(row.frame, "BackgroundColor3", if index == selected then "selected" else "canvas")
		end
	end

	local function run(command: Command?)
		if command then
			Overlay.closeModal()
			command.run()
		end
	end

	for index = 1, maxRows do
		local frame = Kit.surface("canvas", {
			Position = UDim2.fromScale(0, (index - 1) / maxRows),
			Size = UDim2.fromScale(1, 1 / maxRows - 0.008),
			ZIndex = 114,
			Visible = false,
			Parent = results,
		}, {})
		local title = Kit.label({ text = "", role = "body", props = { Size = UDim2.fromScale(0.62, 1), ZIndex = 115 } })
		title.Parent = frame
		local subtitle = Kit.label({
			text = "",
			role = "hint",
			token = "dim",
			align = Enum.TextXAlignment.Right,
			props = { Position = UDim2.fromScale(0.62, 0), Size = UDim2.fromScale(0.38, 1), ZIndex = 115 },
		})
		subtitle.Parent = frame
		local hit = Kit.hitbox({ ZIndex = 116, Parent = frame })
		maid:give(hit.MouseEnter:Connect(function()
			selected = index
			paint()
		end))
		maid:give(hit.Activated:Connect(function()
			run(shown[index])
		end))
		rows[index] = { frame = frame, title = title, subtitle = subtitle }
	end

	local function refresh()
		local query = string.lower(input.Text)
		local scored = {}
		for _, command in commands() do
			local value = score(command, query)
			if value > 0 then
				table.insert(scored, { command = command, value = value })
			end
		end
		table.sort(scored, function(a, b)
			return a.value > b.value
		end)
		table.clear(shown)
		for index = 1, maxRows do
			local entry = scored[index]
			rows[index].frame.Visible = entry ~= nil
			if entry then
				shown[index] = entry.command
				rows[index].title.Text = entry.command.title
				rows[index].subtitle.Text = entry.command.subtitle or ""
			end
		end
		selected = math.clamp(selected, 1, math.max(1, #shown))
		paint()
	end

	local openedAt = os.clock()
	maid:give(input:GetPropertyChangedSignal("Text"):Connect(function()
		if os.clock() - openedAt < 0.5 and string.sub(input.Text, 1, 1) == "/" then
			input.Text = string.sub(input.Text, 2)
			return
		end
		selected = 1
		refresh()
	end))
	maid:give(input.FocusLost:Connect(function(enter)
		if enter then
			run(shown[selected])
		end
	end))
	maid:give(game:GetService("UserInputService").InputBegan:Connect(function(pressed)
		if pressed.KeyCode == Enum.KeyCode.Down then
			selected = math.min(#shown, selected + 1)
			paint()
		elseif pressed.KeyCode == Enum.KeyCode.Up then
			selected = math.max(1, selected - 1)
			paint()
		elseif pressed.KeyCode == Enum.KeyCode.Escape then
			Overlay.closeModal()
		end
	end))
	refresh()
	task.defer(function()
		input:CaptureFocus()
	end)
end

return CommandBar
