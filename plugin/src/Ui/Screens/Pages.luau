--!strict

local Actions = require(script.Parent.Parent.Parent.State.Actions)
local Config = require(script.Parent.Parent.Parent.Config)
local Controls = require(script.Parent.Parent.Components.Controls)
local Kit = require(script.Parent.Parent.Kit)
local Links = require(script.Parent.Parent.Parent.Studio.Links)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Parent.Components.Overlay)
local Stack = require(script.Parent.Parent.Layout.Stack)
local Store = require(script.Parent.Parent.Parent.State.Store)
local Theme = require(script.Parent.Parent.Theme)
local Typography = require(script.Parent.Parent.Typography)
local Measure = require(script.Parent.Parent.Measure)
local Time = require(script.Parent.Parent.Parent.Core.Time)

local Pages = {}

type Builder = (state: Store.State, add: (GuiObject, any) -> (), maid: Maid.Maid) -> ()

local cardLayouts: { [Instance]: (number, number?) -> number } = setmetatable({}, { __mode = "k" }) :: any

local function page(
	ctx: any,
	name: string,
	heading: string,
	description: string,
	signatureOf: (Store.State) -> string,
	build: Builder
): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.frame({ Name = name })
	local top = Kit.frame({ Size = UDim2.fromScale(1, 0.18), Parent = root })
	Kit.paddingXY(0.04, 0.08).Parent = top
	local title = Kit.label({ text = heading, role = "title", props = { Size = UDim2.fromScale(1, 0.4) } })
	title.Parent = top
	local sub = Kit.label({
		text = description,
		role = "meta",
		token = "subtext",
		wrap = true,
		yAlign = Enum.TextYAlignment.Top,
		props = { Position = UDim2.fromScale(0, 0.4), Size = UDim2.fromScale(1, 0.6) },
	})
	sub.Parent = top
	local body = Kit.frame({ Position = UDim2.fromScale(0, 0.18), Size = UDim2.fromScale(1, 0.82), Parent = root })
	local stack = Stack.new(body, maid)
	Kit.paddingXY(0.04, 0).Parent = stack.frame
	ctx.lock:register(stack)
	local contentMaid = Maid.new()
	maid:give(contentMaid)
	local signature: string? = nil
	return {
		root = root,
		title = title,
		render = function(state: Store.State)
			local next = signatureOf(state)
			if next == signature then
				return
			end
			signature = next
			contentMaid:clean()
			stack:clear()
			build(state, function(child, ratio)
				stack:add(child, cardLayouts[child] or ratio)
			end, contentMaid)
			stack:lock()
		end,
	}
end

local function note(text: string): TextLabel
	return Kit.label({ text = text, role = "meta", token = "dim", wrap = true })
end

local function noteRow(text: string): (TextLabel, (number, number?) -> number)
	return note(text), Measure.paragraph(text, "meta")
end

local function card(
	titleText: string,
	subText: string,
	buttons: { { text: string, kind: Controls.ButtonKind?, run: () -> () } },
	maid: Maid.Maid,
	onOpen: (() -> ())?
): Frame
	local frame = Kit.surface("card", {}, {})
	local textShare = if #buttons > 0 then 0.62 else 0.96
	local title = Kit.label({ text = titleText, role = "body", wrap = true })
	title.Parent = frame
	local sub = Kit.label({ text = subText, role = "hint", token = "subtext", wrap = true })
	sub.Parent = frame
	if onOpen then
		local hit = Kit.hitbox({ Size = UDim2.fromScale(textShare, 1), Parent = frame })
		maid:give(hit.Activated:Connect(onOpen))
	end
	local roots = {}
	for _, button in buttons do
		local made = Controls.button({
			text = button.text,
			kind = button.kind or "primary",
			onClick = button.run,
			parent = frame,
		}, maid)
		table.insert(roots, made.root)
	end

	cardLayouts[frame] = function(designWidth: number, realWidth: number?): number
		local width = realWidth or designWidth
		local textWidth = width * textShare
		local baseHeight = designWidth / Kit.rows.taskRow
		local titleHeight = Measure.height(titleText, "body", textWidth)
		local subHeight = if subText ~= "" then Measure.height(subText, "hint", textWidth) else 0
		local total = math.max(baseHeight, titleHeight + subHeight + Typography.size("hint") * 0.5)
		local top = (total - titleHeight - subHeight) / 2
		title.Position = UDim2.fromScale(0, top / total)
		title.Size = UDim2.fromScale(textShare, titleHeight / total)
		sub.Position = UDim2.fromScale(0, (top + titleHeight) / total)
		sub.Size = UDim2.fromScale(textShare, subHeight / total)
		local buttonHeight = baseHeight * 0.6
		for index, root in roots do
			root.Position = UDim2.fromScale(0.63 + (index - 1) * (0.36 / #roots), (total - buttonHeight) / 2 / total)
			root.Size = UDim2.fromScale(0.36 / #roots - 0.01, buttonHeight / total)
		end
		return designWidth / total
	end
	return frame
end

local function taskCard(item: any, maid: Maid.Maid): Frame
	local due = Time.dueText(item.dueAt)
	local bits = { item.listTitle or "" }
	if due ~= "" then
		table.insert(bits, due)
	end
	if item.label then
		table.insert(bits, item.label)
	end
	if (item.priority or 0) > 0 then
		table.insert(bits, Config.priorityNames[item.priority] .. " priority")
	end
	return card((if item.done then "✓ " else "") .. item.text, table.concat(bits, "  ·  "), {}, maid, function()
		Actions.openList(item.listId)
		task.delay(0.5, function()
			Actions.openDrawer(item.id)
		end)
	end)
end

function Pages.myTasks(ctx: any): any
	return page(
		ctx,
		"MyTasks",
		"My tasks",
		"Every task assigned to me, across all lists. Overdue and soonest first.",
		function(state)
			local parts = {}
			for _, item in state.myTasks or {} do
				table.insert(parts, item.id .. tostring(item.done) .. (item.dueAt or 0))
			end
			return (if state.myTasks then "y" else "n") .. table.concat(parts, ",")
		end,
		function(state, add, maid)
			if not state.myTasks then
				add(noteRow("Loading"))
				return
			end
			if #state.myTasks == 0 then
				add(noteRow("Nothing assigned to you right now. When someone gives you a task it shows up here."))
			end
			for _, item in state.myTasks do
				add(taskCard(item, maid), Kit.rows.taskRow)
			end
		end
	)
end

local function textWidth(text: string, role: string): number
	return Measure.width(text, role)
end

local function wrappedHeight(text: string, role: string, width: number): number
	return Measure.height(text, role, width)
end

local function notificationCard(
	options: {
		title: string,
		body: string,
		meta: string,
		urgent: boolean,
		read: boolean,
		selected: boolean?,
		onSelect: (() -> ())?,
		button: { text: string, kind: Controls.ButtonKind?, run: () -> () },
	},
	maid: Maid.Maid
): (Frame, (number) -> number)
	local live = options.urgent and not options.read
	local frame = Kit.surface(if live then "dangerSoft" else "card", {}, {})
	Kit.create("UICorner", { CornerRadius = UDim.new(0.06, 0), Parent = frame })
	local stripe = if live then Kit.surface("danger", { Size = UDim2.fromScale(0.012, 1), Parent = frame }) else nil
	local title =
		Kit.label({ text = options.title, role = "label", token = if options.read then "subtext" else "text" })
	title.Parent = frame
	local body = Kit.label({
		text = options.body,
		role = "meta",
		token = if options.read then "dim" else "subtext",
		wrap = true,
		yAlign = Enum.TextYAlignment.Top,
	})
	body.Parent = frame
	local meta = Kit.label({ text = options.meta, role = "hint", token = "dim", wrap = true })
	meta.Parent = frame
	local button = Controls.button({
		text = options.button.text,
		kind = options.button.kind,
		onClick = options.button.run,
		parent = frame,
	}, maid)

	local check: Frame? = nil
	if options.onSelect then
		local holder = Kit.frame({ Parent = frame })
		local box = Kit.surface(if options.selected then "accent" else "checkBorder", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			Parent = holder,
		}, { Kit.square() })
		Kit.create("UICorner", { CornerRadius = UDim.new(0.2, 0), Parent = box })
		if options.selected then
			local tick = Kit.icon(Config.icons.check, "accentText", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.75, 0.75),
			})
			tick.Parent = box
		else
			local inner = Kit.surface("canvas", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.74, 0.74),
				Parent = box,
			})
			Kit.create("UICorner", { CornerRadius = UDim.new(0.2, 0), Parent = inner })
		end
		local hit = Kit.hitbox({ Parent = holder })
		maid:give(hit.Activated:Connect(options.onSelect))
		check = holder
	end

	local function layout(designWidth: number, realWidth: number?): number
		local width = realWidth or designWidth
		local pad = width * 0.04
		local checkW = if check then Typography.size("label") * 2 else 0
		local textLeft = pad + checkW
		local inner = width - textLeft - pad
		local titleH = Typography.size("label") * 1.6
		local bodyH = wrappedHeight(options.body, "meta", inner * 0.92)
		local footerH = Typography.size("label") * 2.6
		local gap = width * 0.012
		local total = pad + titleH + gap + bodyH + gap * 2 + footerH + pad
		local function y(px: number): number
			return px / total
		end
		local x = textLeft / width
		local right = pad / width
		if check then
			check.Position = UDim2.fromScale(pad / width, y(pad))
			check.Size = UDim2.fromScale(checkW / width, y(titleH))
		end
		title.Position = UDim2.fromScale(x, y(pad))
		title.Size = UDim2.fromScale(1 - x - right, y(titleH))
		body.Position = UDim2.fromScale(x, y(pad + titleH + gap))
		body.Size = UDim2.fromScale(1 - x - right, y(bodyH))
		local footerY = y(pad + titleH + gap + bodyH + gap * 2)
		meta.Position = UDim2.fromScale(x, footerY)
		local buttonW = math.max(width * 0.2, textWidth(options.button.text, "label") + Typography.size("label") * 2)
		meta.Size = UDim2.fromScale(1 - x - right - buttonW / width - 0.02, y(footerH))
		button.root.Position = UDim2.fromScale(1 - right - buttonW / width, footerY)
		button.root.Size = UDim2.fromScale(buttonW / width, y(footerH))
		if stripe then
			stripe.Size = UDim2.fromScale(0.012, 1)
		end
		return designWidth / total
	end
	return frame, layout
end

local notificationTabs = {
	{ id = "fix", text = "Needs fixing" },
	{ id = "due", text = "Due dates" },
	{ id = "mentions", text = "Tasks" },
	{ id = "shared", text = "Shared" },
	{ id = "updates", text = "Updates" },
}

type NotificationEntry = {
	key: string,
	read: boolean,
	selectable: boolean,
	time: number,
	build: (maid: Maid.Maid, selected: boolean) -> (Frame, (number) -> number),
}

local function notificationEntries(state: Store.State, tab: string): { NotificationEntry }
	local entries: { NotificationEntry } = {}
	if tab == "updates" then
		local version = state.updateVersion
		if version then
			local key = "u:" .. version
			local read = state.seenUpdate == version
			table.insert(entries, {
				key = key,
				read = read,
				selectable = true,
				time = 0,
				build = function(maid, selected)
					return notificationCard({
						title = "Version " .. version .. " is out",
						body = "You're on "
							.. Config.version
							.. ". To update, open Plugins, then Manage Plugins, and press Update on CheckpointLTC. It should be good to go, if not reopen Studio.",
						meta = if read then "Update ready" else "New  ·  Update ready",
						urgent = false,
						read = read,
						selected = selected,
						onSelect = function()
							Actions.selectNotifications({ key }, not selected)
						end,
						button = {
							text = if read then "Read" else "Got it",
							kind = if read then "secondary" else "primary",
							run = function()
								Actions.markNotificationsRead({ key })
							end,
						},
					}, maid)
				end,
			})
		end
	elseif tab == "due" then
		for _, item in Actions.dueSoon(state) do
			local key = Actions.dueKey(item)
			local dueText, dueState = Time.dueText(item.dueAt)
			local overdue = dueState == "overdue"
			local read = state.seenDue[key] == true
			table.insert(entries, {
				key = key,
				read = read,
				selectable = true,
				time = -(item.dueAt :: number),
				build = function(maid, selected)
					return notificationCard({
						title = dueText,
						body = item.text,
						meta = (if read then "" else "New  ·  ") .. (item.listTitle or ""),
						urgent = overdue,
						read = read,
						selected = selected,
						onSelect = function()
							Actions.selectNotifications({ key }, not selected)
						end,
						button = {
							text = "Open task",
							kind = if overdue and not read then "danger" else "primary",
							run = function()
								Actions.openNotification({ listId = item.listId, itemId = item.id }, key)
							end,
						},
					}, maid)
				end,
			})
		end
	else
		for _, n in if state.notifications then state.notifications.list else {} do
			if Actions.notificationTabOf(n.kind) == tab then
				local key = "n:" .. tostring(n.id)
				local fix = tab == "fix"
				table.insert(entries, {
					key = key,
					read = n.read == true,
					selectable = not fix or n.read == true,
					time = n.createdAt,
					build = function(maid, selected)
						local bits = { Time.ago(n.createdAt), n.listTitle or "" }
						if not n.read then
							table.insert(bits, 1, if fix then "Needs you" else "New")
						end
						return notificationCard({
							title = Actions.notificationTitle(n),
							body = Actions.describeNotification(n),
							meta = table.concat(bits, "  ·  "),
							urgent = fix,
							read = n.read == true,
							selected = selected,
							onSelect = if fix and not n.read
								then nil
								else function()
									Actions.selectNotifications({ key }, not selected)
								end,
							button = {
								text = if fix then (if n.read then "Fixed" else "Fix it") else "Open",
								kind = if fix then (if n.read then "secondary" else "danger") else "primary",
								run = function()
									Actions.openNotification(n, key)
								end,
							},
						}, maid)
					end,
				})
			end
		end
	end
	table.sort(entries, function(x, y)
		if x.read ~= y.read then
			return not x.read
		end
		return x.time > y.time
	end)
	return entries
end

function Pages.notifications(ctx: any): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.frame({ Name = "Notifications" })

	local top = Kit.frame({ Size = UDim2.fromScale(1, 0.12), Parent = root })
	Kit.paddingXY(0.04, 0.1).Parent = top
	local title = Kit.label({ text = "Notifications", role = "title", props = { Size = UDim2.fromScale(1, 0.55) } })
	title.Parent = top
	local sub = Kit.label({
		text = "Fix the red ones. Open the rest or mark them read.",
		role = "meta",
		token = "subtext",
		props = { Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45) },
	})
	sub.Parent = top

	local tabRow = Kit.create("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.06),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		CanvasSize = UDim2.fromOffset(0, 0),
		Parent = root,
	})
	local chips = {}
	local chipText: { [string]: string } = {}
	for _, tab in notificationTabs do
		local chip = Controls.chip(tab.text, nil, function()
			Actions.setNotificationTab(tab.id)
		end, maid, {})
		chip.root.Parent = tabRow
		chips[tab.id] = chip
		chipText[tab.id] = tab.text
	end
	local function layoutTabs()
		local rowWidth = tabRow.AbsoluteSize.X
		if rowWidth <= 0 then
			return
		end
		local pad = rowWidth * 0.03
		local gap = rowWidth * 0.01
		local widths = {}
		local total = pad * 2 + gap * (#notificationTabs - 1)
		for index, tab in notificationTabs do
			widths[index] = textWidth(chipText[tab.id], "hint") + Typography.size("hint") * 0.9
			total += widths[index]
		end
		local spare = rowWidth - total
		if spare > 0 then
			for index in widths do
				widths[index] += spare / #widths
			end
			total = rowWidth
		end
		local fits = spare >= 0
		tabRow.ScrollBarThickness = if fits then 0 else 3
		tabRow.CanvasSize = if fits then UDim2.fromOffset(0, 0) else UDim2.fromOffset(math.ceil(total), 0)
		local rowHeight = tabRow.AbsoluteSize.Y
		local x = pad
		for index, tab in notificationTabs do
			chips[tab.id].root.Position = UDim2.fromOffset(math.floor(x), math.floor(rowHeight * 0.1))
			chips[tab.id].root.Size = UDim2.fromOffset(math.floor(widths[index]), math.floor(rowHeight * 0.8))
			x += widths[index] + gap
		end
	end
	maid:give(tabRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutTabs))

	local tools = Kit.frame({ Position = UDim2.fromScale(0, 0.185), Size = UDim2.fromScale(1, 0.06), Parent = root })
	Kit.paddingXY(0.04, 0.08).Parent = tools
	local toolNote = Kit.label({ text = "", role = "hint", token = "dim" })
	toolNote.Parent = tools

	local current: { NotificationEntry } = {}
	local function keysOf(onlyUnread: boolean, onlyPicked: boolean): { string }
		local keys = {}
		local picked = Store.get().notificationSelected
		for _, entry in current do
			if entry.selectable and (not onlyUnread or not entry.read) and (not onlyPicked or picked[entry.key]) then
				table.insert(keys, entry.key)
			end
		end
		return keys
	end

	local selectAll = Controls.button({
		text = "Select all",
		kind = "secondary",
		onClick = function()
			Actions.selectNotifications(keysOf(false, false), true)
		end,
		parent = tools,
	}, maid)
	local clearAll = Controls.button({
		text = "Unselect all",
		kind = "secondary",
		onClick = function()
			Actions.selectNotifications(keysOf(false, false), false)
		end,
		parent = tools,
	}, maid)
	local markRead = Controls.button({
		text = "Mark all read",
		kind = "primary",
		onClick = function()
			local picked = keysOf(false, true)
			Actions.markNotificationsRead(if #picked > 0 then picked else keysOf(true, false))
		end,
		parent = tools,
	}, maid)
	local deleteButton = Controls.button({
		text = "Delete",
		kind = "danger",
		onClick = function()
			Actions.deleteNotifications(keysOf(false, true))
		end,
		parent = tools,
	}, maid)
	local toolText = { select = "Select all", clear = "Unselect all", mark = "Mark all read", delete = "Delete" }
	local function layoutTools()
		local width = tools.AbsoluteSize.X * 0.92
		if width <= 0 then
			return
		end
		local gap = width * 0.015
		local need = 0
		for _, entry in
			{
				{ button = markRead, text = toolText.mark },
				{ button = deleteButton, text = toolText.delete },
				{ button = clearAll, text = toolText.clear },
				{ button = selectAll, text = toolText.select },
			}
		do
			if entry.button.root.Visible then
				need += textWidth(entry.text, "label") + Typography.size("label") * 1.6 + gap
			end
		end
		if need > width and selectAll.root.Visible then
			selectAll.root.Visible = false
		end
		local right = width
		for _, entry in
			{
				{ button = markRead, text = toolText.mark },
				{ button = deleteButton, text = toolText.delete },
				{ button = clearAll, text = toolText.clear },
				{ button = selectAll, text = toolText.select },
			}
		do
			if entry.button.root.Visible then
				local w = textWidth(entry.text, "label") + Typography.size("label") * 1.6
				right -= w
				entry.button.root.Position = UDim2.fromScale(right / width, 0)
				entry.button.root.Size = UDim2.fromScale(w / width, 1)
				right -= gap
			end
		end
		toolNote.Size = UDim2.fromScale(math.max(0, right / width), 1)
		toolNote.Visible = textWidth(toolNote.Text, "hint") <= right
	end
	maid:give(tools:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutTools))

	local body = Kit.frame({ Position = UDim2.fromScale(0, 0.255), Size = UDim2.fromScale(1, 0.745), Parent = root })
	local stack = Stack.new(body, maid)
	Kit.paddingXY(0.04, 0).Parent = stack.frame
	ctx.lock:register(stack)
	local contentMaid = Maid.new()
	maid:give(contentMaid)

	local signature: string? = nil
	return {
		root = root,
		title = title,
		render = function(state: Store.State)
			local counts = Actions.notificationCounts(state)
			local tab = state.notificationTab
			for _, t in notificationTabs do
				local text = if counts[t.id] > 0 then t.text .. "  " .. tostring(counts[t.id]) else t.text
				chips[t.id].setSelected(t.id == tab)
				chips[t.id].setText(text)
				chipText[t.id] = text
			end
			layoutTabs()

			local entries = notificationEntries(state, tab)
			current = entries
			local picked = #keysOf(false, true)
			local unread = #keysOf(true, false)
			local selectableCount = #keysOf(false, false)
			local deletable = tab == "fix" or tab == "mentions" or tab == "shared"
			selectAll.root.Visible = selectableCount > 0 and picked < selectableCount
			clearAll.root.Visible = picked > 0
			deleteButton.root.Visible = deletable and picked > 0
			markRead.root.Visible = tab ~= "fix" and (picked > 0 or unread > 0)
			toolText.mark = if picked > 0 then "Mark " .. tostring(picked) .. " read" else "Mark all read"
			toolText.delete = "Delete " .. tostring(picked)
			markRead.setText(toolText.mark)
			deleteButton.setText(toolText.delete)
			toolNote.Text = if picked > 0
				then tostring(picked) .. " selected"
				elseif tab == "fix" then "These clear when you fix them."
				else ""
			layoutTools()

			local parts = { tab, if state.notifications then "y" else "n" }
			for _, entry in entries do
				table.insert(
					parts,
					entry.key
						.. (if entry.read then "r" else "u")
						.. (if state.notificationSelected[entry.key] then "s" else "")
				)
			end
			local next = table.concat(parts, ",")
			if next == signature then
				return
			end
			signature = next
			contentMaid:clean()
			stack:clear()
			if not state.notifications then
				stack:add(noteRow("Loading"))
			elseif #entries == 0 then
				stack:add(
					noteRow(if tab == "fix" then "Nothing needs fixing." else "Nothing here. You're all caught up.")
				)
			end
			for _, entry in entries do
				local frame, layout = entry.build(contentMaid, state.notificationSelected[entry.key] == true)
				stack:add(frame, layout)
			end
			stack:lock()
		end,
	}
end

function Pages.search(ctx: any): any
	local query = ""
	local view = page(
		ctx,
		"Search",
		"Search",
		"Find tasks in every list I can see. Type at least 2 letters.",
		function(state)
			local parts = { state.searchQuery }
			for _, item in state.searchResults or {} do
				table.insert(parts, item.id)
			end
			return table.concat(parts, ",")
		end,
		function(state, add, maid)
			local row = Kit.frame({})
			local box = Kit.surface("input", { Size = UDim2.fromScale(0.74, 1), Parent = row }, {})
			local input = Kit.create("TextBox", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Text = query,
				PlaceholderText = "Search tasks and notes",
				ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = box,
			}, { Kit.padding() })
			Typography.apply(input, "body")
			Theme.bind(input, "TextColor3", "text")
			Theme.bind(input, "PlaceholderColor3", "dim")
			maid:give(input.FocusLost:Connect(function()
				query = input.Text
				Actions.search(query, nil)
			end))
			maid:give(input:GetPropertyChangedSignal("Text"):Connect(function()
				if #input.Text >= 2 then
					query = input.Text
					task.delay(0.4, function()
						if query == input.Text then
							Actions.search(query, nil)
						end
					end)
				end
			end))
			Controls.button({
				text = "Search",
				kind = "primary",
				tooltip = "Search every list",
				shortcut = "Enter",
				onClick = function()
					query = input.Text
					Actions.search(query, nil)
				end,
				props = { Position = UDim2.fromScale(0.77, 0), Size = UDim2.fromScale(0.23, 1) },
				parent = row,
			}, maid)
			add(row, Kit.rows.composer)
			if state.searchQuery ~= "" and state.searchResults and #state.searchResults == 0 then
				add(noteRow("No tasks match."))
			end
			for _, item in state.searchResults or {} do
				add(taskCard(item, maid), Kit.rows.taskRow)
			end
			task.defer(function()
				if input.Parent then
					input:CaptureFocus()
				end
			end)
		end
	)
	return view
end

function Pages.trash(ctx: any): any
	local selected: { [string]: string } = {}
	local version = 0
	local function bump()
		version += 1
		Store.set({ lastChangeAt = os.clock() })
	end
	local function picked(kind: string): { string }
		local out = {}
		for id, entryKind in selected do
			if entryKind == kind then
				table.insert(out, id)
			end
		end
		return out
	end
	return page(
		ctx,
		"Trash",
		"Trash",
		"Deleted lists, tasks and notifications stay here for 30 days, then they are gone for good. Tap to select.",
		function(state)
			if not state.trash then
				return "n"
			end
			local parts = { tostring(version) }
			for _, entry in state.trash.lists do
				table.insert(parts, entry.id)
			end
			for _, entry in state.trash.items do
				table.insert(parts, entry.id)
			end
			for _, entry in state.trash.notifications or {} do
				table.insert(parts, "n:" .. tostring(entry.id))
			end
			return table.concat(parts, ",")
		end,
		function(state, add, maid)
			local trash = state.trash
			if not trash then
				add(noteRow("Loading"))
				return
			end
			local present: { [string]: boolean } = {}
			for _, entry in trash.lists do
				present[entry.id] = true
			end
			for _, entry in trash.items do
				present[entry.id] = true
			end
			local notes = trash.notifications or {}
			for _, entry in notes do
				present["n:" .. tostring(entry.id)] = true
			end
			for id in selected do
				if not present[id] then
					selected[id] = nil
				end
			end
			if #trash.lists == 0 and #trash.items == 0 and #notes == 0 then
				add(noteRow("The trash is empty."))
				return
			end
			local count = 0
			for _ in selected do
				count += 1
			end
			local total = #trash.lists + #trash.items + #notes
			local function pickedNotes(): { number }
				local out = {}
				for _, key in picked("note") do
					table.insert(out, tonumber(string.sub(key, 3)) :: number)
				end
				return out
			end
			local toolbar = Kit.frame({}, { Kit.row(0.015) })
			local function tool(
				text: string,
				kind: Controls.ButtonKind?,
				width: number,
				order: number,
				onClick: () -> ()
			)
				local button = Controls.button({
					text = text,
					kind = kind,
					onClick = onClick,
					props = { Size = UDim2.fromScale(width, 1), LayoutOrder = order },
				}, maid)
				button.root.Parent = toolbar
				return button
			end
			tool(if count == total then "Select none" else "Select all", nil, 0.3, 1, function()
				local all = count ~= total
				table.clear(selected)
				if all then
					for _, entry in trash.lists do
						selected[entry.id] = "list"
					end
					for _, entry in trash.items do
						selected[entry.id] = "item"
					end
					for _, entry in notes do
						selected["n:" .. tostring(entry.id)] = "note"
					end
				end
				bump()
			end)
			tool("Restore " .. count, "primary", 0.3, 2, function()
				if count > 0 then
					Actions.trashSelected(picked("item"), picked("list"), true, pickedNotes())
					table.clear(selected)
				end
			end).setEnabled(count > 0)
			tool("Delete " .. count, "danger", 0.35, 3, function()
				if count == 0 then
					return
				end
				Overlay.confirm({
					title = string.format("Delete %d forever?", count),
					body = "These are erased for good and can't be restored. Lists erased here take their tasks and comments with them.",
					confirm = "Delete forever",
					danger = true,
					onConfirm = function()
						Actions.trashSelected(picked("item"), picked("list"), false, pickedNotes())
						table.clear(selected)
					end,
				})
			end).setEnabled(count > 0)
			add(toolbar, Kit.rows.button)
			add(
				Controls.button({
					text = "Empty trash",
					kind = "danger",
					hint = "Erases everything here for good",
					onClick = function()
						Overlay.confirm({
							title = "Empty the trash?",
							body = string.format(
								"All %d items here are erased for good and can't be restored. Only things you are allowed to erase are removed.",
								total
							),
							confirm = "Empty trash",
							danger = true,
							onConfirm = function()
								table.clear(selected)
								Actions.emptyTrash()
							end,
						})
					end,
				}, maid).root,
				Kit.rows.button * 0.7
			)
			local function row(id: string, kind: string, title: string, sub: string)
				local isPicked = selected[id] ~= nil
				add(
					card(
						(if isPicked then "☑  " else "☐  ") .. title,
						sub,
						{
							{
								text = "Restore",
								kind = "primary",
								run = function()
									if kind == "list" then
										Actions.restoreList(id)
									elseif kind == "note" then
										Actions.trashSelected({}, {}, true, { tonumber(string.sub(id, 3)) :: number })
									else
										Actions.restoreItem(id)
									end
								end,
							},
						},
						maid,
						function()
							selected[id] = if isPicked then nil else kind
							bump()
						end
					),
					Kit.rows.taskRow
				)
			end
			if #trash.lists > 0 then
				add(Controls.sectionTitle("Lists"), Kit.rows.section)
			end
			for _, entry in trash.lists do
				row(
					entry.id,
					"list",
					entry.title,
					"Deleted " .. Time.ago(entry.deletedAt) .. "  ·  " .. entry.itemCount .. " tasks"
				)
			end
			if #trash.items > 0 then
				add(Controls.sectionTitle("Tasks"), Kit.rows.section)
			end
			for _, entry in trash.items do
				row(
					entry.id,
					"item",
					entry.text,
					"Deleted " .. Time.ago(entry.deletedAt) .. "  ·  " .. entry.listTitle
				)
			end
			if #notes > 0 then
				add(Controls.sectionTitle("Notifications"), Kit.rows.section)
			end
			for _, entry in notes do
				row(
					"n:" .. tostring(entry.id),
					"note",
					Actions.notificationTitle(entry),
					"Deleted " .. Time.ago(entry.deletedAt) .. "  ·  " .. (entry.listTitle or "")
				)
			end
		end
	)
end

local activityWords: { [string]: string } = {
	["list.created"] = "made the list",
	["list.imported"] = "imported the list",
	["list.renamed"] = "renamed the list",
	["list.archived"] = "archived the list",
	["list.unarchived"] = "unarchived the list",
	["list.pinned"] = "changed the pinned game",
	["code.rotated"] = "made a new share code",
	["item.added"] = "added",
	["item.edited"] = "edited",
	["item.checked"] = "checked off",
	["item.unchecked"] = "unchecked",
	["item.deleted"] = "deleted",
	["item.restored"] = "restored",
	["item.moved"] = "moved",
	["item.split"] = "split",
	["list.autoassign"] = "changed who new tasks go to",
	["comment.added"] = "commented on",
	["member.added"] = "added a person",
	["member.changed"] = "changed someone's role",
	["member.removed"] = "removed a person",
	["assignment.added"] = "assigned the list to someone",
	["assignment.removed"] = "removed an assignment",
	["report.approved"] = "approved a player report",
	["undo"] = "undid a change",
}

function Pages.activity(ctx: any): any
	return page(
		ctx,
		"Activity",
		"Activity log",
		"Who changed what and when. Owners see everything, editors see the latest 50 changes.",
		function(state)
			local parts = { state.listId or "", if state.activity then "y" else "n" }
			for _, event in state.activity or {} do
				table.insert(parts, tostring(event.id))
			end
			return table.concat(parts, ",")
		end,
		function(state, add, maid)
			if not state.activity then
				add(noteRow("Loading"))
				return
			end
			add(
				Controls.button({
					text = "Back to the list",
					onClick = function()
						Actions.showView("list")
					end,
				}, maid).root,
				Kit.rows.button
			)
			for _, event in state.activity do
				local data = event.data or {}
				local target = if data.text
					then '"' .. tostring(data.text) .. '"'
					elseif data.to then 'to "' .. tostring(data.to) .. '"'
					elseif data.userId then Store.personName(data.userId)
					else ""
				add(
					card(
						Store.shortName(event.actorId)
							.. " "
							.. (activityWords[event.kind] or event.kind)
							.. " "
							.. target,
						Time.ago(event.createdAt),
						{},
						maid
					),
					Kit.rows.taskRow
				)
			end
		end
	)
end

function Pages.inbox(ctx: any): any
	return page(
		ctx,
		"Inbox",
		"In game reports",
		"Bugs and feedback players send from your game land here. Approve one to turn it into a task.",
		function(state)
			local parts = {
				state.listId or "",
				state.newGameKey or "",
				if state.reports then "r" else "-",
				if state.gameKeys then "k" else "-",
				if state.detail then state.detail.role else "",
			}
			for _, report in state.reports or {} do
				table.insert(parts, report.id)
			end
			for _, key in state.gameKeys or {} do
				table.insert(parts, key.id .. (if key.revokedAt then "!" else ""))
			end
			return table.concat(parts, ",")
		end,
		function(state, add, maid)
			local detail = state.detail
			local manages = detail and (detail.role == "owner" or detail.role == "admin")
			if not state.reports then
				add(noteRow("Loading"))
				return
			end
			if #state.reports == 0 then
				add(
					noteRow(
						"No new reports. Players' reports show up here once your game uses the CheckpointLTC reports module."
					)
				)
			end
			for _, report in state.reports do
				add(
					card(
						report.text,
						(if report.kind == "bug" then "Bug" else "Feedback")
							.. " from "
							.. report.playerName
							.. "  ·  "
							.. Time.ago(report.createdAt),
						{
							{
								text = "Approve",
								kind = "primary",
								run = function()
									Actions.approveReport(report.id)
								end,
							},
							{
								text = "Dismiss",
								kind = "danger",
								run = function()
									Actions.dismissReport(report.id)
								end,
							},
						},
						maid
					),
					Kit.rows.taskRow
				)
			end
			if manages then
				add(Controls.sectionTitle("Game keys"), Kit.rows.section)
				add(
					noteRow(
						"A game key lets one game send reports to this list. Best kept in your game's Secrets as CheckpointLTC. Players can send one report an hour."
					)
				)
				if state.newGameKey then
					add(
						card(
							"New key ready",
							"Press Insert and it goes in StartReports. Move it to Secrets from there.",
							{
								{
									text = "Insert",
									kind = "primary",
									run = function()
										ctx.insertReportsModule(state.newGameKey)
									end,
								},
							},
							maid
						),
						Kit.rows.taskRow
					)
				end
				for _, key in state.gameKeys or {} do
					if key.revokedAt then
						add(
							card(
								key.label .. " was turned off",
								"One player flooded reports with this key "
									.. Time.ago(key.revokedAt)
									.. ", so someone may have it. Make a new key, update your secret, then delete this one.",
								{
									{
										text = "Delete",
										kind = "danger",
										run = function()
											Actions.deleteGameKey(key.id)
										end,
									},
								},
								maid
							),
							Kit.rows.taskRow
						)
						continue
					end
					add(
						card(key.label, "Made " .. Time.ago(key.createdAt), {
							{
								text = "Revoke",
								kind = "danger",
								run = function()
									Overlay.confirm({
										title = "Revoke " .. key.label .. "?",
										body = "The game using this key can no longer send reports. Players' reports from it will fail until you put in a new key.",
										confirm = "Revoke key",
										danger = true,
										onConfirm = function()
											Actions.deleteGameKey(key.id)
										end,
									})
								end,
							},
						}, maid),
						Kit.rows.taskRow
					)
				end
				add(
					Controls.button({
						text = "Make a game key",
						kind = "primary",
						hint = "Lets a game send player reports to this list",
						onClick = function()
							Overlay.prompt({
								title = "Name the key",
								placeholder = "My obby",
								confirm = "Make key",
								maxLength = 40,
								onConfirm = function(text)
									Actions.createGameKey(text)
								end,
							})
						end,
					}, maid).root,
					Kit.rows.button * 0.7
				)
			end
		end
	)
end

function Pages.todo(ctx: any): any
	local chosen: { [number]: boolean } = {}
	local remind = 0
	local view
	view = page(
		ctx,
		"Todo",
		"TODO comments",
		"TODO comments from my scripts, ready to become tasks. Pick the ones to add.",
		function(state)
			local parts = { tostring(remind) }
			for index, found in state.todoResults or {} do
				table.insert(parts, found.path .. found.line .. tostring(chosen[index]))
			end
			return table.concat(parts, ",")
		end,
		function(state, add, maid)
			local results = state.todoResults or {}
			if #results == 0 then
				add(noteRow("No TODO comments found in this place's scripts."))
				return
			end
			local reminderRow = Kit.frame({})
			local reminderLabel = Kit.label({
				text = "Remind me",
				role = "meta",
				token = "subtext",
				props = { Size = UDim2.fromScale(0.26, 1) },
			})
			reminderLabel.Parent = reminderRow
			local chips = Kit.frame(
				{ Position = UDim2.fromScale(0.26, 0.1), Size = UDim2.fromScale(0.74, 0.8), Parent = reminderRow },
				{ Kit.row(0.015) }
			)
			local options = {
				{ text = "None", days = 0 },
				{ text = "Tomorrow", days = 1 },
				{ text = "In 3 days", days = 3 },
				{ text = "Next week", days = 7 },
			}
			local needs = {}
			local totalNeed = 0
			for index, option in options do
				needs[index] = Measure.width(option.text, "hint") + Typography.size("hint") * 0.8
				totalNeed += needs[index]
			end
			for index, option in options do
				local share = (0.98 - 0.015 * (#options - 1)) * needs[index] / totalNeed
				local chip = Controls.chip(option.text, nil, function()
					remind = option.days
					Store.set({ lastChangeAt = os.clock() })
				end, maid, { Size = UDim2.fromScale(share, 1), LayoutOrder = index })
				chip.setSelected(remind == option.days)
				chip.root.Parent = chips
			end
			add(reminderRow, Kit.rows.field)
			for index, found in results do
				local selected = chosen[index] ~= false
				add(
					card(
						(if selected then "☑ " else "☐ ") .. found.text,
						Links.describe({ kind = "script", path = found.path, line = found.line }),
						{
							{
								text = "Open",
								run = function()
									local link = Links.forScriptLine(found.script, found.line)
									local _, message = Links.open(link)
									Actions.toast("info", message)
								end,
							},
						},
						maid,
						function()
							chosen[index] = not selected
							Store.set({ lastChangeAt = os.clock() })
						end
					),
					Kit.rows.taskRow
				)
			end
			add(
				Controls.button({
					text = "Add the ticked ones as tasks",
					kind = "primary",
					onClick = function()
						local count = 0
						for index, found in results do
							if chosen[index] ~= false then
								count += 1
								local fields: { [string]: any } = {
									link = Links.forScriptLine(found.script, found.line),
									label = "Scripting",
									section = "TODO",
								}
								if remind > 0 then
									fields.dueAt = Time.endOfDayMs(remind)
								end
								Actions.addItem(found.text, fields)
							end
						end
						Actions.toast("success", string.format("Added %d tasks from TODO comments.", count))
						Store.clear("todoResults")
						Actions.showView("list")
					end,
				}, maid).root,
				Kit.rows.button
			)
		end
	)
	return view
end

function Pages.people(ctx: any): any
	local roleNames = { owner = "Owner", admin = "Admin", editor = "Editor", viewer = "Viewer" }
	return page(ctx, "People", "People", "Who can see and change this list.", function(state)
		local detail = state.detail
		if not detail then
			return "n"
		end
		local parts = {
			detail.list.id,
			detail.list.shareCode or "",
			detail.role,
			tostring(state.prefs.showHints),
			tostring(state.prefs.defaultRole),
			table.concat(detail.list.autoAssignees or {}, "."),
		}
		for _, person in detail.members do
			table.insert(parts, person.userId .. (person.role or "") .. (person.name or ""))
		end
		for _, person in detail.assignments do
			table.insert(parts, "a" .. person.userId)
		end
		return table.concat(parts, ",")
	end, function(state, add, maid)
		local detail = state.detail
		if not detail then
			return
		end
		local listId = detail.list.id
		local manages = detail.role == "owner" or detail.role == "admin"
		add(
			Controls.button({
				text = "Back to the list",
				onClick = function()
					Actions.showView("list")
				end,
			}, maid).root,
			Kit.rows.button
		)

		if detail.list.shareCode then
			add(Controls.sectionTitle("Share code"), Kit.rows.section)
			add(
				card(
					string.sub(detail.list.shareCode, 1, 4) .. " " .. string.sub(detail.list.shareCode, 5),
					"Anyone with this code can view the list.",
					if manages
						then {
							{
								text = "New code",
								kind = "danger",
								run = function()
									Overlay.confirm({
										title = "Make a new code?",
										body = "The old code stops working, and everyone who joined with it loses access right away. People you added by username keep their access.",
										confirm = "Make new code",
										danger = true,
										onConfirm = function()
											Actions.rotateCode(listId)
										end,
									})
								end,
							},
						}
						else {},
					maid
				),
				Kit.rows.taskRow
			)
			if manages then
				local hint = Kit.label({
					text = "New code: kicks out everyone who joined with the old one",
					role = "hint",
					token = "dim",
					wrap = true,
				})
				Overlay.registerHint(hint)
				add(hint, Kit.rows.hint)
			end
		end

		if manages then
			add(Controls.sectionTitle("Add someone"), Kit.rows.section)
			local function addButton(text: string, hintText: string, role: string, assignOnly: boolean)
				return Controls.button({
					text = text,
					hint = hintText,
					onClick = function()
						Overlay.prompt({
							title = text,
							body = "Type their UserId, or their Roblox username.",
							placeholder = "UserId or username",
							confirm = "Add",
							maxLength = 20,
							onConfirm = function(name)
								Actions.addPerson(listId, name, role, assignOnly)
							end,
						})
					end,
				}, maid).root
			end
			local defaultRole = if state.prefs.defaultRole == "viewer" then "viewer" else "editor"
			add(
				addButton(
					"Add a person",
					if defaultRole == "viewer"
						then "Adds them as a viewer. Change the default in Settings, New people are"
						else "Adds them as an editor. Change the default in Settings, New people are",
					defaultRole,
					false
				),
				Kit.rows.button * 0.7
			)
			if detail.role == "owner" then
				add(
					addButton("Add an admin", "Admins manage people but cannot delete the list", "admin", false),
					Kit.rows.button * 0.7
				)
			end
			add(
				addButton("Assign the list", "Shows under their Assigned to me, view only", "viewer", true),
				Kit.rows.button * 0.7
			)
		end

		if manages then
			add(Controls.sectionTitle("Auto assign"), Kit.rows.section)
			local auto = detail.list.autoAssignees or {}
			local names = {}
			for _, userId in auto do
				table.insert(names, Store.shortName(userId))
			end
			add(
				Controls.button({
					text = if #names == 0
						then "New tasks go to nobody"
						else "New tasks go to " .. table.concat(names, ", "),
					hint = "Every new task on this list is given to these people. You can still change it on each task",
					onClick = function()
						ctx.autoAssignMenu()
					end,
				}, maid).root,
				Kit.rows.button * 0.7
			)
		end

		add(Controls.sectionTitle("On this list"), Kit.rows.section)
		add(card(Store.personName(detail.list.ownerId), "Owner", {}, maid), Kit.rows.taskRow)
		for _, person in detail.members do
			local buttons = {}
			local canChange = manages and (detail.role == "owner" or person.role ~= "admin")
			if canChange then
				table.insert(buttons, {
					text = "Role",
					run = function()
						local items: { Overlay.MenuItem } = {}
						for _, role in { "editor", "viewer", if detail.role == "owner" then "admin" else nil } do
							if role then
								table.insert(items, {
									text = "Make " .. roleNames[role],
									run = function()
										Actions.setRole(listId, person.userId, role)
									end,
								})
							end
						end
						Overlay.menu(items)
					end,
				})
				table.insert(buttons, {
					text = "Remove",
					kind = "danger",
					run = function()
						Overlay.confirm({
							title = "Remove " .. Store.personName(person.userId) .. "?",
							body = "They lose access to this list right away. Tasks assigned to them stay on the list.",
							confirm = "Remove",
							danger = true,
							onConfirm = function()
								Actions.removePerson(listId, person.userId, false)
							end,
						})
					end,
				})
			end
			add(
				card(Store.personName(person.userId), roleNames[person.role or "viewer"] or "", buttons, maid),
				Kit.rows.taskRow
			)
		end
		for _, person in detail.assignments do
			add(
				card(
					Store.personName(person.userId),
					"Assigned",
					if manages
						then {
							{
								text = "Unassign",
								kind = "danger",
								run = function()
									Actions.removePerson(listId, person.userId, true)
								end,
							},
						}
						else {},
					maid
				),
				Kit.rows.taskRow
			)
		end
	end)
end

return Pages
