--!strict

local TweenService = game:GetService("TweenService")

local Actions = require(script.Parent.Parent.Parent.State.Actions)
local Client = require(script.Parent.Parent.Parent.Api.Client)
local Config = require(script.Parent.Parent.Parent.Config)
local Controls = require(script.Parent.Parent.Components.Controls)
local GrowingTextBox = require(script.Parent.Parent.Components.GrowingTextBox)
local Kit = require(script.Parent.Parent.Kit)
local Links = require(script.Parent.Parent.Parent.Studio.Links)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Parent.Components.Overlay)
local Stack = require(script.Parent.Parent.Layout.Stack)
local Store = require(script.Parent.Parent.Parent.State.Store)
local Time = require(script.Parent.Parent.Parent.Core.Time)

local Drawer = {}

local function findItem(state: Store.State): any
	local detail = state.detail
	if not detail or not state.drawerItemId then
		return nil
	end
	for _, item in detail.items do
		if item.id == state.drawerItemId then
			return item
		end
	end
	return nil
end

function Drawer.new(ctx: any): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.surface("canvas", {
		Name = "Drawer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(2, 0),
		Size = UDim2.fromScale(0.9, 1),
		ZIndex = 50,
		Visible = false,
		ClipsDescendants = true,
	})

	local top = Kit.frame({ Size = UDim2.fromScale(1, 0.08), ZIndex = 51, Parent = root })
	Kit.paddingXY(0.03, 0.12).Parent = top
	local topTitle = Kit.label({
		text = "Task",
		role = "label",
		token = "subtext",
		props = { Size = UDim2.fromScale(0.7, 1), ZIndex = 51 },
	})
	topTitle.Parent = top
	Controls.iconButton({
		icon = "close",
		tooltip = "Close details",
		shortcut = "Esc",
		onClick = function()
			Actions.openDrawer(nil)
		end,
		props = {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.1, 1),
			ZIndex = 52,
		},
		parent = top,
	}, maid)

	local body =
		Kit.frame({ Position = UDim2.fromScale(0, 0.08), Size = UDim2.fromScale(1, 0.92), ZIndex = 51, Parent = root })
	local contentMaid = Maid.new()
	maid:give(contentMaid)
	local stack = Stack.new(body, maid, { ZIndex = 51 })
	Kit.paddingXY(0.04, 0).Parent = stack.frame
	ctx.lock:register(stack)

	local view: any = { root = root }
	local shownId: string? = nil
	local shownVersion = -1
	local open = false

	local function save(itemId: string, fields: { [string]: any })
		Actions.updateItem(itemId, fields)
	end

	local function rowLabel(text: string, parent: Instance)
		local label = Kit.label({
			text = text,
			role = "hint",
			token = "dim",
			props = { Size = UDim2.fromScale(0.26, 1), ZIndex = 52 },
		})
		label.Parent = parent
	end

	local function chipRow(
		parent: Instance,
		values: { { text: string, value: any, color: Color3? } },
		selected: any,
		onPick: (any) -> ()
	)
		local holder = Kit.frame(
			{ Position = UDim2.fromScale(0.26, 0.1), Size = UDim2.fromScale(0.74, 0.8), ZIndex = 52, Parent = parent },
			{ Kit.row(0.015) }
		)
		for index, entry in values do
			local chip = Controls.chip(
				entry.text,
				entry.color,
				function()
					onPick(entry.value)
				end,
				contentMaid,
				{
					Size = UDim2.fromScale(math.min(0.3, (0.98 - 0.015 * (#values - 1)) / #values), 1),
					LayoutOrder = index,
					ZIndex = 52,
				}
			)
			chip.setSelected(entry.value == selected)
			chip.root.Parent = holder
		end
	end

	local function build(item: any)
		contentMaid:clean()
		stack:clear()
		local state = Store.get()
		local detail = state.detail :: any
		local editable = detail
			and (detail.role == "owner" or detail.role == "admin" or detail.role == "editor")
			and not detail.list.archived
		local canToggle = editable or (item.assigneeId == state.userId)

		local titleRow = Kit.frame({ ZIndex = 52, ClipsDescendants = false })
		local titleBox = GrowingTextBox.new({
			parent = titleRow,
			placeholder = "Task text",
			maxLength = function()
				return Store.limit("itemMaxLength", Config.fallbackLimits.itemMaxLength)
			end,
			zIndex = 60,
			keepOnSubmit = true,
			onFocusLost = function(text)
				local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
				if editable and trimmed ~= "" and trimmed ~= item.text then
					save(item.id, { text = trimmed })
				end
			end,
		}, contentMaid)
		titleBox:setText(item.text)
		titleBox:setEditable(editable)
		view.boxes = { titleBox }
		stack:add(titleRow, Kit.rows.composer)

		local doneRow = Kit.frame({ ZIndex = 52 })
		local doneButton = Controls.button({
			text = if item.done then "Done  ✓" else "Mark done",
			kind = if item.done then "secondary" else "primary",
			onClick = function()
				Actions.toggleDone(item.id)
			end,
			props = { Size = UDim2.fromScale(0.48, 1), ZIndex = 52 },
			parent = doneRow,
		}, contentMaid)
		doneButton.setEnabled(canToggle)
		local updated = Kit.label({
			text = if item.updatedBy
				then "Changed by " .. Store.shortName(item.updatedBy) .. " " .. Time.ago(item.updatedAt or 0)
				else "",
			role = "hint",
			token = "dim",
			wrap = true,
			props = { Position = UDim2.fromScale(0.52, 0), Size = UDim2.fromScale(0.48, 1), ZIndex = 52 },
		})
		updated.Parent = doneRow
		stack:add(doneRow, Kit.rows.button)

		local priorityRow = Kit.frame({ ZIndex = 52 })
		rowLabel("Priority", priorityRow)
		chipRow(
			priorityRow,
			{
				{ text = "None", value = 0 },
				{ text = "Low", value = 1 },
				{ text = "Medium", value = 2 },
				{ text = "High", value = 3 },
			},
			item.priority or 0,
			function(value)
				if editable then
					save(item.id, { priority = value })
				end
			end
		)
		stack:add(priorityRow, Kit.rows.field)

		local labelRow = Kit.frame({ ZIndex = 52 })
		rowLabel("Label", labelRow)
		local labelValues: { any } = { { text = "None", value = false } }
		for _, name in { "Scripting", "UI", "VFX", "Bug" } do
			table.insert(labelValues, { text = name, value = name, color = (Config.labelColors :: any)[name] })
		end
		chipRow(labelRow, labelValues, item.label or false, function(value)
			if editable then
				save(item.id, { label = if value == false then Client.null else value })
			end
		end)
		stack:add(labelRow, Kit.rows.field)

		local dueRow = Kit.frame({ ZIndex = 52 })
		rowLabel(if item.dueAt then (Time.dueText(item.dueAt)) else "Due date", dueRow)
		chipRow(
			dueRow,
			{
				{ text = "None", value = false },
				{ text = "Today", value = 0 },
				{ text = "Tomorrow", value = 1 },
				{ text = "Next week", value = 7 },
				{ text = "Pick", value = "pick" },
			},
			if item.dueAt then -1 else false,
			function(value)
				if not editable then
					return
				end
				if value == false then
					save(item.id, { dueAt = Client.null })
				elseif value == "pick" then
					Overlay.prompt({
						title = "Due date",
						body = "Type a date like 2026 12 24, 20261224 or 12/24/2026.",
						placeholder = "YYYY MM DD",
						confirm = "Set date",
						maxLength = 16,
						onConfirm = function(text)
							local date = Time.parseDate(text)
							if date then
								save(item.id, { dueAt = date })
							else
								Actions.toast("error", "I couldn't read that date. Try 2026 12 24 or 20261224.")
							end
						end,
					})
				else
					save(item.id, { dueAt = Time.endOfDayMs(value) })
				end
			end
		)
		stack:add(dueRow, Kit.rows.field)

		local sectionRow = Kit.frame({ ZIndex = 52 })
		rowLabel("Section", sectionRow)
		Controls.button({
			text = item.section or "No section",
			onClick = function()
				if not editable then
					return
				end
				local menu: { Overlay.MenuItem } = {
					{
						text = "No section",
						run = function()
							save(item.id, { section = Client.null })
						end,
					},
				}
				local seen: { [string]: boolean } = {}
				for _, other in detail.items do
					if other.section and not seen[other.section] then
						seen[other.section] = true
						table.insert(menu, {
							text = other.section,
							run = function()
								save(item.id, { section = other.section })
							end,
						})
					end
				end
				table.insert(menu, {
					text = "New section",
					run = function()
						Overlay.prompt({
							title = "New section",
							placeholder = "Section name",
							confirm = "Add",
							maxLength = 40,
							onConfirm = function(text)
								save(item.id, { section = text })
							end,
						})
					end,
				})
				Overlay.menu(menu)
			end,
			props = { Position = UDim2.fromScale(0.26, 0.1), Size = UDim2.fromScale(0.74, 0.8), ZIndex = 52 },
			parent = sectionRow,
		}, contentMaid)
		stack:add(sectionRow, Kit.rows.field)

		local assigneeRow = Kit.frame({ ZIndex = 52 })
		rowLabel("Assigned to", assigneeRow)
		Controls.button({
			text = if item.assigneeId then Store.personName(item.assigneeId) else "Nobody",
			onClick = function()
				if not editable then
					return
				end
				local menu: { Overlay.MenuItem } = {
					{
						text = "Nobody",
						run = function()
							save(item.id, { assigneeId = Client.null })
						end,
					},
				}
				local seen: { [number]: boolean } = {}
				local function add(userId: number)
					if not seen[userId] then
						seen[userId] = true
						table.insert(menu, {
							text = Store.personName(userId),
							run = function()
								save(item.id, { assigneeId = userId })
							end,
						})
					end
				end
				add(detail.list.ownerId)
				for _, person in detail.members do
					add(person.userId)
				end
				for _, person in detail.assignments do
					add(person.userId)
				end
				Overlay.menu(menu)
			end,
			props = { Position = UDim2.fromScale(0.26, 0.1), Size = UDim2.fromScale(0.74, 0.8), ZIndex = 52 },
			parent = assigneeRow,
		}, contentMaid)
		stack:add(assigneeRow, Kit.rows.field)

		local linkRow = Kit.frame({ ZIndex = 52 })
		rowLabel("Studio link", linkRow)
		if item.link then
			Controls.button({
				text = "Go to " .. Links.describe(item.link),
				kind = "primary",
				onClick = function()
					local _, message = Links.open(item.link)
					Actions.toast("info", message)
				end,
				props = { Position = UDim2.fromScale(0.26, 0.1), Size = UDim2.fromScale(0.5, 0.8), ZIndex = 52 },
				parent = linkRow,
			}, contentMaid)
			if editable then
				Controls.button({
					text = "Unlink",
					onClick = function()
						save(item.id, { link = Client.null })
					end,
					props = { Position = UDim2.fromScale(0.78, 0.1), Size = UDim2.fromScale(0.22, 0.8), ZIndex = 52 },
					parent = linkRow,
				}, contentMaid)
			end
		else
			Controls.button({
				text = "Link my selection",
				onClick = function()
					if not editable then
						return
					end
					local link = Links.fromSelection()
					if link then
						save(item.id, { link = link })
					else
						Actions.toast("warning", "Select a part, model or script in the Explorer first.")
					end
				end,
				props = { Position = UDim2.fromScale(0.26, 0.1), Size = UDim2.fromScale(0.74, 0.8), ZIndex = 52 },
				parent = linkRow,
			}, contentMaid)
		end
		stack:add(linkRow, Kit.rows.field)

		local notesTitle = Controls.sectionTitle("Notes", { ZIndex = 52 })
		stack:add(notesTitle, Kit.rows.section)
		local notesRow = Kit.frame({ ZIndex = 52, ClipsDescendants = false })
		local notes = GrowingTextBox.new({
			parent = notesRow,
			placeholder = if editable then "Add notes" else "No notes",
			multiline = true,
			maxLength = function()
				return Store.limit("notesMaxLength", Config.fallbackLimits.notesMaxLength)
			end,
			zIndex = 58,
			onFocusLost = function(text)
				local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
				if editable and trimmed ~= (item.notes or "") then
					save(item.id, { notes = if trimmed == "" then Client.null else trimmed })
				end
			end,
		}, contentMaid)
		notes:setText(item.notes or "")
		notes:setEditable(editable)
		table.insert(view.boxes, notes)
		stack:add(notesRow, Kit.rows.composer)

		local commentsTitle = Controls.sectionTitle("Comments", { ZIndex = 52 })
		stack:add(commentsTitle, Kit.rows.section)
		local comments = state.comments
		if comments and comments.itemId == item.id then
			if comments.loading then
				local loading =
					Kit.label({ text = "Loading comments", role = "meta", token = "dim", props = { ZIndex = 52 } })
				stack:add(loading, Kit.rows.field)
			elseif #comments.list == 0 then
				local none = Kit.label({
					text = "No comments yet. Type @ and a username to mention someone.",
					role = "meta",
					token = "dim",
					wrap = true,
					props = { ZIndex = 52 },
				})
				stack:add(none, Kit.rows.field)
			end
			for _, comment in comments.list do
				local card = Kit.surface("card", { ZIndex = 52 }, {})
				local who = Kit.label({
					text = Store.shortName(comment.authorId) .. "  ·  " .. Time.ago(comment.createdAt),
					role = "hint",
					token = "subtext",
					props = { Size = UDim2.fromScale(0.85, 0.3), ZIndex = 53 },
				})
				who.Parent = card
				local text = Kit.label({
					text = comment.body,
					role = "meta",
					wrap = true,
					yAlign = Enum.TextYAlignment.Top,
					props = { Position = UDim2.fromScale(0, 0.3), Size = UDim2.fromScale(1, 0.7), ZIndex = 53 },
				})
				text.Parent = card
				if comment.authorId == state.userId or detail.role == "owner" or detail.role == "admin" then
					local remove = Kit.hitbox({
						Text = "×",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.fromScale(0.1, 0.3),
						ZIndex = 54,
						Parent = card,
					})
					remove.FontFace = text.FontFace
					remove.TextSize = text.TextSize + 2
					remove.TextColor3 = Kit.color("dim")
					contentMaid:give(remove.Activated:Connect(function()
						Overlay.confirm({
							title = "Delete this comment?",
							body = "The comment is removed for everyone. This cannot be undone.",
							confirm = "Delete comment",
							danger = true,
							onConfirm = function()
								Actions.deleteComment(item.id, comment.id)
							end,
						})
					end))
				end
				local length = utf8.len(comment.body) or #comment.body
				stack:add(card, function(width)
					local perLine = math.max(10, width / math.max(6, text.TextSize * 0.55))
					local lines = math.ceil(length / perLine)
					return width / (text.TextSize * (lines + 1.6) * 1.3)
				end)
			end
			local canComment = editable or item.assigneeId == state.userId
			if canComment then
				local composerRow = Kit.frame({ ZIndex = 52, ClipsDescendants = false })
				local composer = GrowingTextBox.new({
					parent = composerRow,
					placeholder = "Write a comment, Enter sends",
					maxLength = function()
						return Store.limit("commentMaxLength", Config.fallbackLimits.commentMaxLength)
					end,
					zIndex = 56,
					onSubmit = function(text)
						Actions.addComment(item.id, text)
					end,
				}, contentMaid)
				stack:add(composerRow, Kit.rows.composer)
				local mentionHint = Kit.label({
					text = "Mention people on this list with @username. They get a notification.",
					role = "hint",
					token = "dim",
					wrap = true,
					props = { ZIndex = 52 },
				})
				Overlay.registerHint(mentionHint)
				stack:add(mentionHint, Kit.rows.hint)
				table.insert(view.boxes, composer)
			end
		end

		if editable then
			local deleteRow = Kit.frame({ ZIndex = 52 })
			Controls.button({
				text = "Delete task",
				kind = "danger",
				hint = "Moves it to the trash for 30 days",
				onClick = function()
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
				end,
				props = { Size = UDim2.fromScale(1, 1), ZIndex = 52 },
				parent = deleteRow,
			}, contentMaid)
			stack:add(deleteRow, Kit.rows.button * 0.7)
		end
		stack:lock()
	end

	local function slide(visible: boolean)
		if visible == open then
			return
		end
		open = visible
		if visible then
			root.Visible = true
			root.Position = UDim2.fromScale(1.9, 0)
		end
		local tween = TweenService:Create(
			root,
			TweenInfo.new(Config.interaction.drawerSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromScale(if visible then 1 else 1.9, 0),
			}
		)
		tween:Play()
		if not visible then
			tween.Completed:Once(function()
				if not open then
					root.Visible = false
				end
			end)
		end
	end

	function view.render(state: Store.State)
		local item = findItem(state)
		local wide = (root.Parent and (root.Parent :: GuiObject).AbsoluteSize.X or 0) > 720
		root.Size = UDim2.fromScale(if wide then 0.5 else 0.92, 1)
		if not item or state.view ~= "list" then
			shownId = nil
			slide(false)
			return
		end
		topTitle.Text = if item.done then "Task  ·  done" else "Task"
		local commentsKey = if state.comments and state.comments.itemId == item.id
			then (if state.comments.loading then -1 else #state.comments.list)
			else -2
		local version = (item.version or 0) * 1000 + commentsKey + (if item.pending then 0.5 else 0)
		if shownId ~= item.id or shownVersion ~= version then
			local focused = false
			if shownId == item.id then
				for _, box in view.boxes or {} do
					if box.input:IsFocused() then
						focused = true
					end
				end
			end
			if not focused then
				shownId = item.id
				shownVersion = version
				build(item)
			end
		end
		slide(true)
	end

	return view
end

return Drawer
