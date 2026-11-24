--!strict

local Config = require(script.Parent.Parent.Parent.Config)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Overlay)
local Store = require(script.Parent.Parent.Parent.State.Store)
local Theme = require(script.Parent.Parent.Theme)
local Time = require(script.Parent.Parent.Parent.Core.Time)

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

function TaskRow.avatar(userId: number, props: Kit.Props?): ImageLabel
	local image = Kit.create("ImageLabel", {
		BackgroundTransparency = 0,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=48&h=48",
		ScaleType = Enum.ScaleType.Crop,
	}, { Kit.square() })
	Theme.bind(image, "BackgroundColor3", "line")
	for key, value in props or {} do
		(image :: any)[key] = value
	end
	return image
end

function TaskRow.new(handlers: Handlers, maid: Maid.Maid): any
	local rowMaid = Maid.new()
	maid:give(rowMaid)
	local root = Kit.frame({ Name = "TaskRow", Visible = false })
	local body = Kit.surface(
		"canvas",
		{ Position = UDim2.fromScale(0.01, 0.04), Size = UDim2.fromScale(0.98, 0.92), Parent = root },
		{}
	)
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
		Position = UDim2.fromScale(0.5, 0.42),
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

	local textArea = Kit.frame({ Position = UDim2.fromScale(0.15, 0), Size = UDim2.fromScale(0.75, 1), Parent = body })
	local title = Kit.label({
		text = "",
		role = "body",
		wrap = true,
		yAlign = Enum.TextYAlignment.Top,
		props = { Size = UDim2.fromScale(1, 0.62) },
	})
	title.Parent = textArea
	local meta = Kit.frame(
		{ Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.34), Parent = textArea },
		{ Kit.row(0.015) }
	)
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

	local assignee = TaskRow.avatar(1, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.9, 0.42),
		Size = UDim2.fromScale(0.06, 0.5),
		Visible = false,
		Parent = body,
	})

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

	rowMaid:give(mainHit.MouseEnter:Connect(function()
		body.BackgroundTransparency = 0
		Theme.bind(body, "BackgroundColor3", if row.item and handlers.isSelected(row.item) then "selected" else "hover")
	end))
	rowMaid:give(mainHit.MouseLeave:Connect(function()
		Theme.bind(
			body,
			"BackgroundColor3",
			if row.item and handlers.isSelected(row.item) then "selected" else "canvas"
		)
	end))
	rowMaid:give(mainHit.Activated:Connect(function()
		if not row.item then
			return
		end
		local now = os.clock()
		if now - lastClick < 0.35 and handlers.canEdit(row.item) then
			lastClick = 0
			handlers.editInline(row.item, textArea)
			return
		end
		lastClick = now
		handlers.open(row.item)
	end))
	rowMaid:give(moreHit.Activated:Connect(function()
		if row.item then
			handlers.menu(row.item)
		end
	end))
	rowMaid:give(checkHit.Activated:Connect(function()
		if row.item and handlers.canToggle(row.item) then
			handlers.toggle(row.item)
		end
	end))
	rowMaid:give(handleHit.MouseButton1Down:Connect(function()
		if row.item and handlers.canEdit(row.item) then
			handlers.startDrag(row.item, root)
		end
	end))

	function row.bind(self: any, item: any)
		self.item = item
		local selected = handlers.isSelected(item)
		Theme.bind(body, "BackgroundColor3", if selected then "selected" else "canvas")
		accentBar.Visible = selected
		title.Text = item.text
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
		assignee.Visible = item.assigneeId ~= nil
		if item.assigneeId then
			assignee.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(item.assigneeId) .. "&w=48&h=48"
		end
		meta.Visible = not Store.get().prefs.compact or labelChip.Visible or dueText.Visible
	end

	return row
end

function TaskRow.lines(item: any, charsPerLine: number, expanded: boolean): number
	if Store.get().prefs.compact then
		return 1
	end
	local length = utf8.len(item.text) or #item.text
	local textLines = math.max(1, math.ceil(length / math.max(10, charsPerLine)))
	return if expanded then textLines else math.min(textLines, 2)
end

return TaskRow
