--!strict

local TextService = game:GetService("TextService")

local Config = require(script.Parent.Parent.Parent.Config)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Measure = require(script.Parent.Parent.Measure)
local Overlay = require(script.Parent.Overlay)
local Store = require(script.Parent.Parent.Parent.State.Store)
local Theme = require(script.Parent.Parent.Theme)
local Time = require(script.Parent.Parent.Parent.Core.Time)
local Typography = require(script.Parent.Parent.Typography)

export type Handlers = {
	open: (any) -> (),
	toggle: (any) -> (),
	menu: (any) -> (),
	startDrag: (any, GuiObject) -> (),
	editInline: (any, GuiObject) -> (),
	canEdit: (any) -> boolean,
	canToggle: (any) -> boolean,
	isSelected: (any) -> boolean,
	presenceOn: (string) -> string?,
}

local TaskRow = {}

TaskRow.collapsedLines = 5

local maxAvatars = 3
local padTop = 0.1
local metaShare = 0.3
local padBottom = 0.1
local separatorShare = 0.025
local doubleClickSeconds = 0.3

function TaskRow.avatar(userId: number, props: Kit.Props?): ImageLabel
	local image = Kit.create("ImageLabel", {
		BackgroundTransparency = 0,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=48&h=48",
		ScaleType = Enum.ScaleType.Crop,
	}, { Kit.square(), Kit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	Theme.bind(image, "BackgroundColor3", "line")
	for key, value in props or {} do
		(image :: any)[key] = value
	end
	return image
end

function TaskRow.lineHeight(): number
	local size = Typography.size("body")
	local ok, bounds =
		pcall(TextService.GetTextSize, TextService, "Ag", size, Enum.Font.BuilderSans, Vector2.new(1000, 1000))
	return if ok and bounds.Y > 0 then bounds.Y else Typography.lineHeight("body")
end

local function hasPeople(item: any): boolean
	if type(item.assigneeIds) == "table" then
		return #item.assigneeIds > 0
	end
	return item.assigneeId ~= nil
end

function TaskRow.textShare(item: any): number
	return if hasPeople(item) then 0.65 else 0.76
end

function TaskRow.lines(item: any, rowWidth: number, expanded: boolean): number
	if Store.get().prefs.compact then
		return 1
	end
	local size = Typography.size("body")
	local ok, bounds = pcall(
		TextService.GetTextSize,
		TextService,
		item.text,
		size,
		Enum.Font.BuilderSans,
		Vector2.new(math.max(20, rowWidth * TaskRow.textShare(item) * 0.96), 100000)
	)
	local line = TaskRow.lineHeight()
	local count = if ok then math.max(1, math.floor(bounds.Y / line + 0.5)) else 1
	return if expanded then count else math.min(count, TaskRow.collapsedLines)
end

function TaskRow.new(handlers: Handlers, maid: Maid.Maid): any
	local rowMaid = Maid.new()
	maid:give(rowMaid)
	local root = Kit.frame({ Name = "TaskRow", Visible = false })
	local body = Kit.surface("canvas", { Size = UDim2.fromScale(1, 1 - separatorShare), Parent = root }, {})
	local separator = Kit.surface("lineStrong", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.94, separatorShare),
		Parent = root,
	}, {
		Kit.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local accentBar = Kit.surface(
		"accent",
		{ Size = UDim2.fromScale(0.006, 0.7), Position = UDim2.fromScale(0, 0.15), Visible = false, Parent = body },
		{}
	)

	local handle = Kit.frame({ Size = UDim2.fromScale(0.06, 1), Parent = body })
	local handleGlyph = Kit.glyphIcon("drag", "dim", { Size = UDim2.fromScale(0.7, 0.5) })
	handleGlyph.Parent = handle
	local handleHit = Kit.hitbox({ Parent = handle })
	Overlay.tooltip(handleHit, "Drag to reorder", nil, rowMaid)

	local check = Kit.frame({ Position = UDim2.fromScale(0.06, 0), Size = UDim2.fromScale(0.09, 1), Parent = body })
	local box = Kit.surface("canvas", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		Parent = check,
	}, {
		Kit.square(),
	})
	local boxInner = Kit.surface("canvas", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		Parent = box,
	})
	local tick = Kit.icon(Config.icons.check, "accentText", { Size = UDim2.fromScale(0.75, 0.75), Visible = false })
	tick.Parent = box
	local checkHit = Kit.hitbox({ Parent = check })
	Overlay.tooltip(checkHit, "Mark done or not done", nil, rowMaid)

	local textArea = Kit.frame({ Position = UDim2.fromScale(0.15, 0), Size = UDim2.fromScale(0.76, 1), Parent = body })
	local title = Kit.label({
		text = "",
		role = "body",
		wrap = true,
		yAlign = Enum.TextYAlignment.Top,
		props = { Size = UDim2.fromScale(1, 0.5) },
	})
	local titlePadding = title:FindFirstChildOfClass("UIPadding")
	if titlePadding then
		titlePadding.PaddingTop = UDim.new(0, 0)
		titlePadding.PaddingBottom = UDim.new(0, 0)
		titlePadding.PaddingLeft = UDim.new(0.02, 0)
		titlePadding.PaddingRight = UDim.new(0.02, 0)
	end
	title.Parent = textArea
	local meta = Kit.frame({ Size = UDim2.fromScale(1, 0.3), Parent = textArea }, { Kit.row(0.015) })
	local labelChip = Kit.surface("card", { Size = UDim2.fromScale(0.18, 0.9), LayoutOrder = 1, Parent = meta }, {})
	local labelText = Kit.label({ text = "", role = "hint", align = Enum.TextXAlignment.Center })
	labelText.Parent = labelChip
	local priorityText = Kit.label({
		text = "",
		role = "hint",
		token = "warning",
		props = { Size = UDim2.fromScale(0.14, 1), LayoutOrder = 2 },
	})
	priorityText.Parent = meta
	local dueText = Kit.label({
		text = "",
		role = "hint",
		token = "subtext",
		props = { Size = UDim2.fromScale(0.3, 1), LayoutOrder = 3 },
	})
	dueText.Parent = meta
	local extras = Kit.label({
		text = "",
		role = "hint",
		token = "dim",
		props = { Size = UDim2.fromScale(0.34, 1), LayoutOrder = 4 },
	})
	extras.Parent = meta

	local people = Kit.frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.92, 0),
		Size = UDim2.fromScale(0.11, 1),
		Parent = body,
	})
	local avatars: { ImageLabel } = {}
	for index = 1, maxAvatars do
		avatars[index] = TaskRow.avatar(1, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1 - (index - 1) * 0.28, 0.5),
			Size = UDim2.fromScale(0.5, 0.62),
			ZIndex = maxAvatars - index + 2,
			Visible = false,
			Parent = people,
		})
	end
	local extraPeople = Kit.label({
		text = "",
		role = "hint",
		token = "subtext",
		align = Enum.TextXAlignment.Right,
		noPeek = true,
		props = { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.15, 0), Size = UDim2.fromScale(0.4, 1) },
	})
	extraPeople.Parent = people

	local more = Kit.frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.08, 1),
		Parent = body,
	})
	local moreGlyph = Kit.glyphIcon("more", "subtext", { Size = UDim2.fromScale(0.8, 0.5) })
	moreGlyph.Parent = more
	local moreHit = Kit.hitbox({ Parent = more, ZIndex = 4 })
	Overlay.tooltip(moreHit, "More actions", nil, rowMaid)

	local mainHit = Kit.hitbox({ Parent = textArea })

	local row: any = { root = root, item = nil, textArea = textArea }
	local lastClick = 0

	local function layout(units: number, hasMeta: boolean)
		local total = math.max(1, units)
		local extra = total - 1
		local textShare = (1 - padTop - metaShare - padBottom) + extra
		local band = (padTop * 2 + (1 - padTop - metaShare - padBottom)) / total
		if hasMeta then
			title.Position = UDim2.fromScale(0, padTop / total)
			title.Size = UDim2.fromScale(1, textShare / total)
			meta.Position = UDim2.fromScale(0, (padTop + textShare) / total)
			meta.Size = UDim2.fromScale(1, metaShare / total)
		else
			local spare = metaShare / 2
			title.Position = UDim2.fromScale(0, (padTop + spare) / total)
			title.Size = UDim2.fromScale(1, textShare / total)
		end
		local bandY = if hasMeta then 0 else (metaShare / 2) / total
		for _, frame in { handle, check, more, people } do
			frame.Position = UDim2.fromScale(frame.Position.X.Scale, bandY)
			frame.Size = UDim2.fromScale(frame.Size.X.Scale, band)
		end
		body.Size = UDim2.fromScale(1, 1 - separatorShare / total)
		separator.Size = UDim2.fromScale(0.94, separatorShare / total)
		accentBar.Size = UDim2.fromScale(0.006, math.min(0.7, 0.7 / total + extra / total))
		accentBar.Position = UDim2.fromScale(0, (1 - accentBar.Size.Y.Scale) / 2)
	end

	local function fitMeta()
		local width = meta.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local gap = 0.015
		local used = 0
		for _, entry in
			{ { labelChip, labelText.Text }, { priorityText, priorityText.Text }, { dueText, dueText.Text } }
		do
			local frame, text = entry[1] :: GuiObject, entry[2] :: string
			if frame.Visible and text ~= "" then
				local share = math.min(0.5, (Measure.width(text, "hint") + 8) / width)
				frame.Size = UDim2.fromScale(share, frame.Size.Y.Scale)
				used += share + gap
			end
		end
		extras.Size = UDim2.fromScale(math.max(0.12, 1 - used), 1)
	end
	rowMaid:give(meta:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitMeta))

	local function paint(hover: boolean)
		local selected = row.item ~= nil and handlers.isSelected(row.item)
		Theme.bind(body, "BackgroundColor3", if selected then "selected" elseif hover then "hover" else "canvas")
	end

	rowMaid:give(mainHit.MouseEnter:Connect(function()
		if not Overlay.isCovered(mainHit) then
			paint(true)
		end
	end))
	rowMaid:give(mainHit.MouseLeave:Connect(function()
		paint(false)
	end))
	rowMaid:give(mainHit.Activated:Connect(function()
		if not row.item or Overlay.isCovered(mainHit) then
			return
		end
		local now = os.clock()
		local item = row.item
		if now - lastClick < doubleClickSeconds and handlers.canEdit(item) then
			lastClick = 0
			handlers.editInline(item, textArea)
			return
		end
		lastClick = now
		if not handlers.canEdit(item) then
			handlers.open(item)
			return
		end
		task.delay(doubleClickSeconds, function()
			if lastClick == now and row.item == item then
				handlers.open(item)
			end
		end)
	end))
	rowMaid:give(moreHit.Activated:Connect(function()
		if row.item and not Overlay.isCovered(moreHit) then
			handlers.menu(row.item)
		end
	end))
	rowMaid:give(checkHit.Activated:Connect(function()
		if row.item and handlers.canToggle(row.item) and not Overlay.isCovered(checkHit) then
			handlers.toggle(row.item)
		end
	end))
	rowMaid:give(handleHit.MouseButton1Down:Connect(function()
		if row.item and handlers.canEdit(row.item) and not Overlay.isCovered(handleHit) then
			handlers.startDrag(row.item, root)
		end
	end))

	function row.bind(self: any, item: any, _index: number?, units: number?)
		self.item = item
		local selected = handlers.isSelected(item)
		paint(false)
		accentBar.Visible = selected
		title.Text = item.text
		textArea.Size = UDim2.fromScale(TaskRow.textShare(item), 1)
		Theme.bind(title, "TextColor3", if item.done then "dim" else "text")
		title.TextTransparency = if item.pending then 0.35 else 0
		box.BackgroundTransparency = 0
		Theme.bind(box, "BackgroundColor3", if item.done then "accent" else "checkBorder")
		boxInner.Visible = not item.done
		tick.Visible = item.done
		handle.Visible = handlers.canEdit(item)
		local labelColor = item.label and (Config.labelColors :: any)[item.label]
		labelChip.Visible = labelColor ~= nil
		if labelColor then
			Theme.unbind(labelChip, "BackgroundColor3")
			Theme.unbind(labelText, "TextColor3")
			labelChip.BackgroundColor3 = labelColor
			labelChip.BackgroundTransparency = 0.78
			labelText.TextColor3 = labelColor
			labelText.Text = item.label
		end
		priorityText.Visible = (item.priority or 0) > 0
		priorityText.Text = if item.priority == 3
			then "!!! High"
			elseif item.priority == 2 then "!! Medium"
			elseif item.priority == 1 then "! Low"
			else ""
		local due, state = Time.dueText(item.dueAt)
		dueText.Visible = due ~= ""
		dueText.Text = due
		Theme.bind(
			dueText,
			"TextColor3",
			if state == "overdue" then "danger" elseif state == "soon" then "warning" else "subtext"
		)
		local bits = {}
		if item.commentCount and item.commentCount > 0 then
			table.insert(bits, "💬 " .. item.commentCount)
		end
		if item.link then
			table.insert(bits, "🔗")
		end
		if item.listTitle then
			table.insert(bits, item.listTitle)
		end
		local here = handlers.presenceOn(item.id)
		if here then
			table.insert(bits, "● " .. here)
		end
		extras.Text = table.concat(bits, "  ")
		local assignees = if type(item.assigneeIds) == "table"
			then item.assigneeIds
			elseif item.assigneeId then { item.assigneeId }
			else {}
		for index, avatar in avatars do
			local userId = assignees[index]
			avatar.Visible = userId ~= nil
			if userId then
				avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=48&h=48"
			end
		end
		extraPeople.Visible = #assignees > maxAvatars
		extraPeople.Text = "+" .. tostring(#assignees - maxAvatars)
		local hasMeta = not Store.get().prefs.compact
			and (labelChip.Visible or priorityText.Visible or dueText.Visible or extras.Text ~= "")
		meta.Visible = hasMeta
		layout(units or 1, hasMeta)
		if hasMeta then
			fitMeta()
		end
	end

	return row
end

return TaskRow
