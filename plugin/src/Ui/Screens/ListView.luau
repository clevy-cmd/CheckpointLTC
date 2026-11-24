--!strict

local Actions = require(script.Parent.Parent.Parent.State.Actions)
local Client = require(script.Parent.Parent.Parent.Api.Client)
local Config = require(script.Parent.Parent.Parent.Config)
local Controls = require(script.Parent.Parent.Components.Controls)
local GrowingTextBox = require(script.Parent.Parent.Components.GrowingTextBox)
local Kit = require(script.Parent.Parent.Kit)
local Links = require(script.Parent.Parent.Parent.Studio.Links)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Parent.Components.Overlay)
local Store = require(script.Parent.Parent.Parent.State.Store)
local TaskRow = require(script.Parent.Parent.Components.TaskRow)
local TeamPresence = require(script.Parent.Parent.Parent.Studio.TeamPresence)
local VirtualList = require(script.Parent.Parent.Layout.VirtualList)

local ListView = {}

local roleNames = { owner = "Owner", admin = "Admin", editor = "Editor", viewer = "View only" }

local function canEdit(detail: any): boolean
	return detail ~= nil
		and (detail.role == "owner" or detail.role == "admin" or detail.role == "editor")
		and not detail.list.archived
end

function ListView.visibleItems(state: Store.State): { any }
	local detail = state.detail
	if not detail then
		return {}
	end
	local items = {}
	for _, item in detail.items do
		if
			not (state.prefs.hideCompleted and item.done) and (not state.labelFilter or item.label == state.labelFilter)
		then
			table.insert(items, item)
		end
	end
	local order = state.prefs.sortOrder
	if order == "priority" then
		table.sort(items, function(a, b)
			if (a.priority or 0) ~= (b.priority or 0) then
				return (a.priority or 0) > (b.priority or 0)
			end
			return a.position < b.position
		end)
	elseif order == "due" then
		table.sort(items, function(a, b)
			local x, y = a.dueAt or math.huge, b.dueAt or math.huge
			if x ~= y then
				return x < y
			end
			return a.position < b.position
		end)
	elseif order == "recent" then
		table.sort(items, function(a, b)
			return (a.updatedAt or 0) > (b.updatedAt or 0)
		end)
	end
	return items
end

local function withSections(items: { any }, manual: boolean): { any }
	if not manual then
		return items
	end
	local hasSection = false
	for _, item in items do
		if item.section then
			hasSection = true
			break
		end
	end
	if not hasSection then
		return items
	end
	local order: { string } = {}
	local groups: { [string]: { any } } = {}
	for _, item in items do
		local key = item.section or ""
		if not groups[key] then
			groups[key] = {}
			table.insert(order, key)
		end
		table.insert(groups[key], item)
	end
	local out = {}
	for _, key in order do
		table.insert(
			out,
			{ isHeader = true, section = key, title = if key == "" then "No section" else key, count = #groups[key] }
		)
		for _, item in groups[key] do
			table.insert(out, item)
		end
	end
	return out
end

function ListView.sections(items: { any }): { string }
	local order = {}
	for _, item in items do
		local key = item.section or ""
		if not table.find(order, key) then
			table.insert(order, key)
		end
	end
	return order
end

function ListView.new(ctx: any): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.frame({ Name = "ListView", ClipsDescendants = false })
	local expanded: { [string]: boolean } = {}

	local header = Kit.frame({ Size = UDim2.fromScale(1, 0.11), Parent = root })
	Kit.paddingXY(0.03, 0.08).Parent = header
	local title = Kit.label({ text = "", role = "title", props = { Size = UDim2.fromScale(0.62, 0.55) } })
	title.Parent = header
	local subtitle = Kit.label({
		text = "",
		role = "meta",
		token = "subtext",
		props = { Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(0.62, 0.45) },
	})
	subtitle.Parent = header
	local progress = Kit.surface(
		"line",
		{ Position = UDim2.fromScale(0, 0.98), Size = UDim2.fromScale(0.6, 0.06), Parent = header },
		{}
	)
	local progressBar = Kit.surface("accent", { Size = UDim2.fromScale(0, 1), Parent = progress }, {})
	local headerButtons = Kit.frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.05),
		Size = UDim2.fromScale(0.38, 0.62),
		Parent = header,
	}, {
		Kit.list(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center, 0.02),
	})
	local presenceRow = Kit.frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0.68),
		Size = UDim2.fromScale(0.38, 0.32),
		Parent = header,
	}, {
		Kit.list(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center, 0.01),
	})

	local filters = Kit.frame(
		{ Position = UDim2.fromScale(0, 0.11), Size = UDim2.fromScale(1, 0.055), Parent = root },
		{ Kit.row(0.012) }
	)
	Kit.paddingXY(0.03, 0.08).Parent = filters
	local allChip = Controls.chip("All", nil, function()
		Actions.setLabelFilter(nil)
	end, maid, { Size = UDim2.fromScale(0.13, 1), LayoutOrder = 0 })
	allChip.root.Parent = filters
	local labelChips = {}
	for index, name in { "Scripting", "UI", "VFX", "Bug" } do
		local chip = Controls.chip(name, (Config.labelColors :: any)[name], function()
			Actions.setLabelFilter(if Store.get().labelFilter == name then nil else name)
		end, maid, { Size = UDim2.fromScale(0.15, 1), LayoutOrder = index })
		chip.root.Parent = filters
		labelChips[name] = chip
	end
	local hideDone = Controls.chip("Hide done", nil, function()
		Actions.setPreference("hideCompleted", not Store.get().prefs.hideCompleted)
	end, maid, { Size = UDim2.fromScale(0.2, 1), LayoutOrder = 9 })
	hideDone.root.Parent = filters

	local content =
		Kit.frame({ Position = UDim2.fromScale(0, 0.17), Size = UDim2.fromScale(1, 0.72), ZIndex = 1, Parent = root })
	local listArea = Kit.frame({ Parent = content })
	local boardArea = Kit.scroll({ Visible = false, ScrollingDirection = Enum.ScrollingDirection.X, Parent = content })

	local empty = Kit.frame({ Size = UDim2.fromScale(1, 1) })
	local emptyLabel = Kit.label({
		text = "",
		role = "body",
		token = "subtext",
		wrap = true,
		align = Enum.TextXAlignment.Center,
		props = { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.2) },
	})
	emptyLabel.Parent = empty

	local view: any = { root = root }
	local current: { any } = {}
	local charsPerLine = 40

	local handlers: TaskRow.Handlers = {
		open = function(item)
			Actions.openDrawer(item.id)
		end,
		toggle = function(item)
			Actions.toggleDone(item.id)
		end,
		menu = function(item)
			view.itemMenu(item)
		end,
		startDrag = function(item, rowRoot)
			view.startDrag(item, rowRoot)
		end,
		editInline = function(item, area)
			view.editInline(item, area)
		end,
		canEdit = function()
			return canEdit(Store.get().detail)
		end,
		canToggle = function(item)
			local state = Store.get()
			return canEdit(state.detail)
				or (item.assigneeId == state.userId and state.detail ~= nil and not state.detail.list.archived)
		end,
		isSelected = function(item)
			return Store.get().drawerItemId == item.id
		end,
		presenceOn = function(itemId)
			local detail = Store.get().detail
			if not detail then
				return nil
			end
			for _, person in detail.presence do
				if person.itemId == itemId then
					return person.displayName or person.name or tostring(person.userId)
				end
			end
			return nil
		end,
	}

	local function buildRow(): any
		local task = TaskRow.new(handlers, maid)
		local headerLabel = Kit.label({
			text = "",
			role = "label",
			token = "subtext",
			props = { Visible = false, Parent = task.root, Name = "SectionHeader" },
		})
		local baseBind = task.bind
		function task.bind(self: any, item: any)
			local isHeader = item.isHeader == true
			headerLabel.Visible = isHeader
			for _, child in self.root:GetChildren() do
				if child ~= headerLabel and child:IsA("GuiObject") then
					child.Visible = not isHeader
				end
			end
			if isHeader then
				headerLabel.Text = string.upper(item.title) .. "   " .. item.count
				self.item = item
			else
				baseBind(self, item)
			end
		end
		return task
	end

	local list = VirtualList.new({
		parent = listArea,
		rowRatio = Kit.rows.taskRow,
		build = buildRow,
		empty = empty,
		lines = function(item)
			if item.isHeader then
				return 1
			end
			return TaskRow.lines(item, charsPerLine, expanded[item.id] == true)
		end,
	}, maid)
	ctx.lock:register(list)

	local boardMaid = Maid.new()
	maid:give(boardMaid)
	local boardLists: { any } = {}
	local boardSections: { string } = {}

	local composerRow = Kit.frame({
		Position = UDim2.fromScale(0, 0.89),
		Size = UDim2.fromScale(1, 0.075),
		ZIndex = 10,
		ClipsDescendants = false,
		Parent = root,
	})
	Kit.paddingXY(0.03, 0.08).Parent = composerRow
	local composerSlot =
		Kit.frame({ Size = UDim2.fromScale(0.86, 1), ZIndex = 10, ClipsDescendants = false, Parent = composerRow })
	local composer
	composer = GrowingTextBox.new({
		parent = composerSlot,
		placeholder = "Add a task and press Enter",
		maxLength = function()
			return Store.limit("itemMaxLength", Config.fallbackLimits.itemMaxLength)
		end,
		zIndex = 30,
		onSubmit = function(text)
			local state = Store.get()
			local fields: { [string]: any } = {}
			if state.labelFilter then
				fields.label = state.labelFilter
			end
			Actions.addItem(text, fields)
			task.defer(function()
				composer:focus()
			end)
		end,
	}, maid)
	view.composer = composer
	view.composerSlot = composerSlot
	local addButton = Controls.iconButton({
		icon = "plus",
		tooltip = "Add task from selection",
		shortcut = "Bind it in File > Customize Shortcuts",
		onClick = function()
			ctx.addFromSelection()
		end,
		props = { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.12, 1) },
		parent = composerRow,
	}, maid)
	local composerHint = Kit.label({
		text = "Enter adds the task. Double click a task to edit it here.",
		role = "hint",
		token = "dim",
		props = { Position = UDim2.fromScale(0, 0.965), Size = UDim2.fromScale(1, 0.035), Parent = root },
	})
	Overlay.registerHint(composerHint)

	local archivedBar = Kit.surface(
		"warningSoft",
		{ Position = UDim2.fromScale(0.03, 0.895), Size = UDim2.fromScale(0.94, 0.065), Visible = false, Parent = root },
		{}
	)
	local archivedText = Kit.label({
		text = "This list is archived. Unarchive it to make changes.",
		role = "meta",
		props = { Size = UDim2.fromScale(0.7, 1) },
	})
	archivedText.Parent = archivedBar
	local unarchive = Controls.button({
		text = "Unarchive",
		kind = "primary",
		onClick = function()
			local listId = Store.get().listId
			if listId then
				Actions.archiveList(listId, false)
			end
		end,
		props = { Position = UDim2.fromScale(0.72, 0.15), Size = UDim2.fromScale(0.26, 0.7) },
		parent = archivedBar,
	}, maid)

	local viewerBar = Kit.label({
		text = "You can view this list. Ask the owner for edit rights.",
		role = "meta",
		token = "subtext",
		align = Enum.TextXAlignment.Center,
		props = { Position = UDim2.fromScale(0, 0.9), Size = UDim2.fromScale(1, 0.06), Visible = false, Parent = root },
	})

	local undoButton = Controls.iconButton({
		icon = "undo",
		tooltip = "Undo my last change",
		shortcut = "Ctrl+Shift+Z if bound",
		onClick = Actions.undo,
		props = { Size = UDim2.fromScale(0.2, 1), LayoutOrder = 1 },
		parent = headerButtons,
	}, maid)
	local viewToggle = Controls.iconButton({
		icon = "board",
		tooltip = "Switch between list and board view",
		onClick = function()
			Actions.setPreference("view", if Store.get().prefs.view == "board" then "list" else "board")
		end,
		props = { Size = UDim2.fromScale(0.2, 1), LayoutOrder = 2 },
		parent = headerButtons,
	}, maid)
	local peopleButton = Controls.iconButton({
		icon = "people",
		tooltip = "People on this list",
		onClick = function()
			Actions.showView("people")
		end,
		props = { Size = UDim2.fromScale(0.2, 1), LayoutOrder = 3 },
		parent = headerButtons,
	}, maid)
	local menuButton = Controls.iconButton({
		icon = "more",
		tooltip = "List actions",
		onClick = function()
			view.listMenu()
		end,
		props = { Size = UDim2.fromScale(0.2, 1), LayoutOrder = 4, Name = "ListMenu" },
		parent = headerButtons,
	}, maid)
	view.menuButton = menuButton.root

	function view.listMenu()
		local state = Store.get()
		local detail = state.detail
		local listId = state.listId
		if not detail or not listId then
			return
		end
		local role = detail.role
		local items: { Overlay.MenuItem } = {}
		local function add(text: string, run: () -> ())
			table.insert(items, { text = text, run = run })
		end
		if role == "owner" or role == "admin" then
			add("Rename list", function()
				Overlay.prompt({
					title = "Rename list",
					placeholder = "List name",
					initial = detail.list.title,
					confirm = "Rename",
					maxLength = Store.limit("titleMaxLength", Config.fallbackLimits.titleMaxLength),
					onConfirm = function(text)
						Actions.renameList(listId, text)
					end,
				})
			end)
			if detail.list.placeId == game.PlaceId and game.PlaceId > 0 then
				add("Unpin from this game", function()
					Actions.pinToGame(listId, false)
				end)
			elseif game.PlaceId > 0 then
				add("Pin to this game", function()
					Actions.pinToGame(listId, true)
				end)
			end
		end
		add("Duplicate list", function()
			Actions.duplicateList(listId)
		end)
		add("Export as Markdown", function()
			view.export("md")
		end)
		add("Export as JSON", function()
			view.export("json")
		end)
		if role ~= "viewer" then
			add("Activity log", function()
				Actions.showView("activity")
			end)
			add("In game reports inbox", function()
				Actions.showView("inbox")
			end)
			add("Scan scripts for TODO comments", function()
				ctx.scanTodos()
			end)
		end
		if role == "owner" then
			add(if detail.list.archived then "Unarchive list" else "Archive list", function()
				Actions.archiveList(listId, not detail.list.archived)
			end)
			add("Delete list", function()
				Overlay.confirm({
					title = "Delete " .. detail.list.title .. "?",
					body = string.format(
						"This moves the list and its %d tasks to the trash. Everyone you shared it with loses access right away. You can restore it from the trash for 30 days, then it is gone for good.",
						detail.list.itemCount
					),
					confirm = "Delete list",
					danger = true,
					onConfirm = function()
						Actions.deleteList(listId)
					end,
				})
			end)
		else
			local openedByCode = false
			for _, summary in if state.home then state.home.opened else {} do
				if summary.id == listId then
					openedByCode = true
				end
			end
			if openedByCode then
				add("Remove from my sidebar", function()
					Actions.forgetList(listId)
				end)
			end
			add("Leave this list", function()
				Overlay.confirm({
					title = "Leave " .. detail.list.title .. "?",
					body = "You lose access to this list. The owner can add you back later.",
					confirm = "Leave list",
					danger = true,
					onConfirm = function()
						Actions.removePerson(listId, state.userId, detail.assigned)
						Actions.forgetList(listId)
					end,
				})
			end)
		end
		Overlay.menu(items)
	end

	function view.export(format: string)
		local listId = Store.get().listId
		if not listId then
			return
		end
		Actions.exportList(listId, format, function(url)
			Overlay.prompt({
				title = "Export ready",
				body = "Copy this link and open it in your browser to download the file. It works for 10 minutes.",
				placeholder = "",
				initial = url,
				confirm = "Done",
				maxLength = 500,
				readOnly = true,
			})
		end)
	end

	function view.itemMenu(item: any)
		if item.isHeader then
			return
		end
		local state = Store.get()
		local editable = canEdit(state.detail)
		local items: { Overlay.MenuItem } = {}
		local function add(text: string, run: () -> ())
			table.insert(items, { text = text, run = run })
		end
		add("Open details", function()
			Actions.openDrawer(item.id)
		end)
		if handlers.canToggle(item) then
			add(if item.done then "Mark not done" else "Mark done", function()
				Actions.toggleDone(item.id)
			end)
		end
		if item.link then
			add("Go to " .. Links.describe(item.link), function()
				local _, message = Links.open(item.link)
				Actions.toast("info", message)
			end)
		end
		add(if expanded[item.id] then "Collapse text" else "Show full text", function()
			expanded[item.id] = not expanded[item.id]
			list:setData(current)
			ctx.lock:contentChanged()
		end)
		if editable then
			add("Edit text", function()
				Actions.openDrawer(item.id)
			end)
			for level = 3, 0, -1 do
				add("Priority: " .. Config.priorityNames[level], function()
					Actions.updateItem(item.id, { priority = level })
				end)
			end
			add("Assign to me", function()
				Actions.updateItem(item.id, { assigneeId = state.userId })
			end)
			add("Link to my selection", function()
				local link = Links.fromSelection()
				if link then
					Actions.updateItem(item.id, { link = link })
					Actions.toast("success", "Linked to " .. Links.describe(link) .. ".")
				else
					Actions.toast("warning", "Select something in the Explorer first.")
				end
			end)
			add("Delete task", function()
				local run = function()
					Actions.deleteItem(item.id)
				end
				if state.prefs.confirmDelete then
					Overlay.confirm({
						title = "Delete this task?",
						body = '"'
							.. item.text
							.. '" moves to the trash. You or another editor can restore it for 30 days.',
						confirm = "Delete task",
						danger = true,
						onConfirm = run,
					})
				else
					run()
				end
			end)
		end
		Overlay.menu(items)
	end

	local inlineMaid = Maid.new()
	maid:give(inlineMaid)

	function view.editInline(item: any, area: GuiObject)
		inlineMaid:clean()
		local origin = root.AbsolutePosition
		local size = root.AbsoluteSize
		local slot = Kit.frame({
			Position = UDim2.fromScale(
				(area.AbsolutePosition.X - origin.X) / size.X,
				(area.AbsolutePosition.Y - origin.Y) / size.Y
			),
			Size = UDim2.fromScale(
				area.AbsoluteSize.X / size.X,
				math.min(area.AbsoluteSize.Y, size.Y * 0.075) / size.Y
			),
			ZIndex = 40,
			ClipsDescendants = false,
			Parent = root,
		})
		inlineMaid:give(slot)
		local editorMaid = Maid.new()
		inlineMaid:give(editorMaid)
		local editor = GrowingTextBox.new({
			parent = slot,
			placeholder = "Task text",
			maxLength = function()
				return Store.limit("itemMaxLength", Config.fallbackLimits.itemMaxLength)
			end,
			zIndex = 41,
			keepOnSubmit = true,
			onSubmit = function(text)
				if text ~= item.text then
					Actions.updateItem(item.id, { text = text })
				end
			end,
			onFocusLost = function()
				task.defer(function()
					inlineMaid:clean()
				end)
			end,
		}, editorMaid)
		editor:setText(item.text)
		task.defer(function()
			editor:focus()
			editor.input.CursorPosition = #editor.input.Text + 1
		end)
	end

	local dragMaid = Maid.new()
	maid:give(dragMaid)

	local function dropTarget(x: number, y: number): (string?, string?, string?)
		local state = Store.get()
		if state.prefs.view == "board" then
			for index, columnList in boardLists do
				local frame = columnList.frame
				if x >= frame.AbsolutePosition.X and x <= frame.AbsolutePosition.X + frame.AbsoluteSize.X then
					local data = columnList.data
					local at = columnList:indexAt(y)
					local above = data[at - 1]
					local below = data[at]
					return if above then above.id else nil, if below then below.id else nil, boardSections[index]
				end
			end
			return nil, nil, nil
		end
		local at = list:indexAt(y)
		local above, below = current[at - 1], current[at]
		local section: string? = nil
		for i = at - 1, 1, -1 do
			if current[i] and current[i].isHeader then
				section = current[i].section
				break
			end
		end
		if above and above.isHeader then
			above = nil
		end
		if below and below.isHeader then
			below = nil
		end
		local hasHeaders = current[1] and current[1].isHeader
		return if above then above.id else nil,
			if below then below.id else nil,
			if hasHeaders then (section or "") else nil
	end

	function view.startDrag(item: any, rowRoot: GuiObject)
		dragMaid:clean()
		local layer = Overlay.layer()
		if not layer then
			return
		end
		local capture = Kit.hitbox({ ZIndex = 150, Parent = layer })
		dragMaid:give(capture)
		local ghost = Kit.surface("selected", {
			ZIndex = 151,
			Size = UDim2.fromScale(
				rowRoot.AbsoluteSize.X / layer.AbsoluteSize.X,
				rowRoot.AbsoluteSize.Y / layer.AbsoluteSize.Y
			),
			Parent = layer,
		}, {})
		dragMaid:give(ghost)
		local ghostText = Kit.label({ text = item.text, role = "body", props = { ZIndex = 152 } })
		ghostText.Parent = ghost
		local marker =
			Kit.surface("accent", { ZIndex = 153, Size = UDim2.fromScale(0.9, 0.004), Visible = false, Parent = layer })
		dragMaid:give(marker)
		local function move(x: number, y: number)
			local origin = layer.AbsolutePosition
			local total = layer.AbsoluteSize
			ghost.Position =
				UDim2.fromScale((x - origin.X) / total.X - 0.05, (y - origin.Y) / total.Y - ghost.Size.Y.Scale / 2)
			marker.Visible = true
			marker.Position = UDim2.fromScale(0.05, (y - origin.Y) / total.Y)
		end
		dragMaid:give(capture.MouseMoved:Connect(move))
		dragMaid:give(capture.MouseButton1Up:Connect(function(x, y)
			dragMaid:clean()
			local aboveId, belowId, section = dropTarget(x, y)
			if aboveId == item.id or belowId == item.id then
				return
			end
			if section == "status:todo" or section == "status:done" then
				local done = section == "status:done"
				if done ~= item.done then
					Actions.toggleDone(item.id)
				end
				if aboveId or belowId then
					Actions.moveItem(item.id, aboveId, belowId, nil)
				end
			elseif aboveId or belowId then
				Actions.moveItem(item.id, aboveId, belowId, section)
			elseif section ~= nil and section ~= (item.section or "") then
				Actions.updateItem(item.id, { section = if section == "" then Client.null else section })
			end
		end))
		dragMaid:give(capture.MouseLeave:Connect(function()
			dragMaid:clean()
		end))
	end

	local function renderBoard(items: { any })
		local sections = ListView.sections(items)
		if #sections <= 1 and (sections[1] == nil or sections[1] == "") then
			sections = { "status:todo", "status:done" }
		end
		local same = #sections == #boardSections
		if same then
			for index, name in sections do
				if boardSections[index] ~= name then
					same = false
				end
			end
		end
		if not same then
			for _, columnList in boardLists do
				ctx.lock:unregister(columnList)
			end
			boardMaid:clean()
			table.clear(boardLists)
			boardSections = sections
			local columns = #sections
			local perView = math.min(columns, 2)
			boardArea.CanvasSize = UDim2.fromScale(columns / perView, 0)
			for index, name in sections do
				local column = Kit.frame({
					Position = UDim2.fromScale((index - 1) / columns, 0),
					Size = UDim2.fromScale(1 / columns, 1),
					Parent = boardArea,
				})
				boardMaid:give(column)
				local card = Kit.surface(
					"sidebar",
					{ Position = UDim2.fromScale(0.02, 0), Size = UDim2.fromScale(0.96, 1), Parent = column },
					{}
				)
				local columnTitle = Kit.label({
					text = if name == "status:todo"
						then "To do"
						elseif name == "status:done" then "Done"
						elseif name == "" then "No section"
						else name,
					role = "label",
					token = "subtext",
					props = { Size = UDim2.fromScale(1, 0.07) },
				})
				columnTitle.Parent = card
				local holder =
					Kit.frame({ Position = UDim2.fromScale(0, 0.07), Size = UDim2.fromScale(1, 0.93), Parent = card })
				local columnList = VirtualList.new({
					parent = holder,
					rowRatio = Kit.rows.taskRow,
					build = function()
						return TaskRow.new(handlers, boardMaid)
					end,
					lines = function(item)
						return TaskRow.lines(item, math.floor(charsPerLine * 0.45), expanded[item.id] == true)
					end,
				}, boardMaid)
				ctx.lock:register(columnList)
				table.insert(boardLists, columnList)
			end
		end
		for index, name in boardSections do
			local columnItems = {}
			for _, item in items do
				local matches = if name == "status:todo"
					then not item.done
					elseif name == "status:done" then item.done
					else (item.section or "") == name
				if matches then
					table.insert(columnItems, item)
				end
			end
			boardLists[index]:setData(columnItems)
		end
	end

	function view.render(state: Store.State)
		local detail = state.detail
		if not detail then
			title.Text = if state.detailLoading then "Loading" else (state.detailError or "")
			subtitle.Text = ""
			list:setData({})
			emptyLabel.Text = if state.detailLoading then "Loading your list" else (state.detailError or "")
			return
		end
		title.Text = detail.list.title
		local done, total = detail.list.doneCount, detail.list.itemCount
		local roleText = roleNames[detail.role] or detail.role
		subtitle.Text = string.format(
			"%s  ·  %d of %d done%s%s",
			roleText,
			done,
			total,
			if detail.assigned then "  ·  assigned to you" else "",
			if detail.list.archived then "  ·  archived" else ""
		)
		progressBar.Size = UDim2.fromScale(if total > 0 then done / total else 0, 1)
		peopleButton.setVisible(detail.role ~= "viewer")
		undoButton.setVisible(canEdit(detail))
		viewToggle.setActive(state.prefs.view == "board")

		for _, child in presenceRow:GetChildren() do
			if child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
		local shown: { [number]: boolean } = {}
		local inSession = TeamPresence.inSession()
		for _, person in detail.presence do
			if not shown[person.userId] and person.userId ~= state.userId then
				shown[person.userId] = true
				TaskRow.avatar(person.userId, { Size = UDim2.fromScale(0.12, 1), Parent = presenceRow })
			end
		end
		for _, userId in inSession do
			if not shown[userId] and userId ~= state.userId then
				shown[userId] = true
				local avatar = TaskRow.avatar(userId, { Size = UDim2.fromScale(0.12, 1), Parent = presenceRow })
				avatar.ImageTransparency = 0.35
			end
		end

		allChip.setSelected(state.labelFilter == nil)
		for name, chip in labelChips do
			chip.setSelected(state.labelFilter == name)
		end
		hideDone.setSelected(state.prefs.hideCompleted == true)

		local editable = canEdit(detail)
		composerRow.Visible = editable
		composerHint.Visible = editable and Overlay.hintsVisible()
		archivedBar.Visible = detail.list.archived
		unarchive.root.Visible = detail.role == "owner"
		viewerBar.Visible = not editable and not detail.list.archived
		addButton.setVisible(editable)

		local items = ListView.visibleItems(state)
		charsPerLine =
			math.max(16, math.floor(listArea.AbsoluteSize.X * 0.72 / math.max(6, composer.input.TextSize * 0.5)))
		emptyLabel.Text = if #detail.items == 0
			then (if editable then "No tasks yet. Type one below and press Enter." else "This list has no tasks yet.")
			else "Nothing matches these filters."

		local board = state.prefs.view == "board"
		listArea.Visible = not board
		boardArea.Visible = board
		if board then
			renderBoard(items)
		else
			current = withSections(items, state.prefs.sortOrder == "manual")
			list:setData(current)
		end
	end

	return view
end

return ListView
