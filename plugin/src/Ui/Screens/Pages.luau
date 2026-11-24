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
local Time = require(script.Parent.Parent.Parent.Core.Time)

local Pages = {}

type Builder = (state: Store.State, add: (GuiObject, any) -> (), maid: Maid.Maid) -> ()

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
	local top = Kit.frame({ Size = UDim2.fromScale(1, 0.15), Parent = root })
	Kit.paddingXY(0.04, 0.1).Parent = top
	local title = Kit.label({ text = heading, role = "title", props = { Size = UDim2.fromScale(1, 0.55) } })
	title.Parent = top
	local sub = Kit.label({
		text = description,
		role = "meta",
		token = "subtext",
		wrap = true,
		props = { Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45) },
	})
	sub.Parent = top
	local body = Kit.frame({ Position = UDim2.fromScale(0, 0.15), Size = UDim2.fromScale(1, 0.85), Parent = root })
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
				stack:add(child, ratio)
			end, contentMaid)
			stack:lock()
		end,
	}
end

local function note(text: string): TextLabel
	return Kit.label({ text = text, role = "meta", token = "dim", wrap = true })
end

local function card(
	titleText: string,
	subText: string,
	buttons: { { text: string, kind: Controls.ButtonKind?, run: () -> () } },
	maid: Maid.Maid,
	onOpen: (() -> ())?
): Frame
	local frame = Kit.surface("card", {}, {})
	local width = if #buttons > 0 then 0.62 else 0.96
	local title =
		Kit.label({ text = titleText, role = "body", wrap = true, props = { Size = UDim2.fromScale(width, 0.55) } })
	title.Parent = frame
	local sub = Kit.label({
		text = subText,
		role = "hint",
		token = "subtext",
		props = { Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(width, 0.45) },
	})
	sub.Parent = frame
	if onOpen then
		local hit = Kit.hitbox({ Size = UDim2.fromScale(width, 1), Parent = frame })
		maid:give(hit.Activated:Connect(onOpen))
	end
	for index, button in buttons do
		Controls.button({
			text = button.text,
			kind = button.kind,
			onClick = button.run,
			props = {
				Position = UDim2.fromScale(0.63 + (index - 1) * (0.36 / #buttons), 0.2),
				Size = UDim2.fromScale(0.36 / #buttons - 0.01, 0.6),
			},
			parent = frame,
		}, maid)
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
				add(note("Loading"), Kit.rows.field)
				return
			end
			if #state.myTasks == 0 then
				add(
					note("Nothing assigned to you right now. When someone gives you a task it shows up here."),
					Kit.rows.field * 0.7
				)
			end
			for _, item in state.myTasks do
				add(taskCard(item, maid), Kit.rows.taskRow)
			end
		end
	)
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
			local box = Kit.surface("input", {}, {})
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
			add(box, Kit.rows.composer)
			if state.searchQuery ~= "" and state.searchResults and #state.searchResults == 0 then
				add(note("No tasks match."), Kit.rows.field)
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
		"Deleted lists and tasks stay here for 30 days, then they are gone for good. Tap to select.",
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
			return table.concat(parts, ",")
		end,
		function(state, add, maid)
			local trash = state.trash
			if not trash then
				add(note("Loading"), Kit.rows.field)
				return
			end
			local present: { [string]: boolean } = {}
			for _, entry in trash.lists do
				present[entry.id] = true
			end
			for _, entry in trash.items do
				present[entry.id] = true
			end
			for id in selected do
				if not present[id] then
					selected[id] = nil
				end
			end
			if #trash.lists == 0 and #trash.items == 0 then
				add(note("The trash is empty."), Kit.rows.field)
				return
			end
			local count = 0
			for _ in selected do
				count += 1
			end
			local total = #trash.lists + #trash.items
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
				end
				bump()
			end)
			tool("Restore " .. count, "primary", 0.3, 2, function()
				if count > 0 then
					Actions.trashSelected(picked("item"), picked("list"), true)
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
						Actions.trashSelected(picked("item"), picked("list"), false)
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
				row(entry.id, "item", entry.text, entry.listTitle .. "  ·  deleted " .. Time.ago(entry.deletedAt))
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
				add(note("Loading"), Kit.rows.field)
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
				table.insert(parts, key.id)
			end
			return table.concat(parts, ",")
		end,
		function(state, add, maid)
			local detail = state.detail
			local manages = detail and (detail.role == "owner" or detail.role == "admin")
			if not state.reports then
				add(note("Loading"), Kit.rows.field)
				return
			end
			if #state.reports == 0 then
				add(
					note(
						"No new reports. Players' reports show up here once your game uses the CheckpointLTC reports module."
					),
					Kit.rows.field * 0.7
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
					note(
						"A game key lets one game send reports to this list. Keep it in a server script only. Insert the module to set it up."
					),
					Kit.rows.field * 0.7
				)
				if state.newGameKey then
					add(
						card("New key, copy it now", "It is only shown once.", {
							{
								text = "Copy",
								kind = "primary",
								run = function()
									Overlay.prompt({
										title = "Your game key",
										body = "Paste this into the CheckpointLTCReports module in ServerScriptService.",
										placeholder = "",
										initial = state.newGameKey,
										confirm = "Done",
										maxLength = 200,
										readOnly = true,
									})
								end,
							},
							{
								text = "Insert",
								run = function()
									ctx.insertReportsModule(state.newGameKey)
								end,
							},
						}, maid),
						Kit.rows.taskRow
					)
				end
				for _, key in state.gameKeys or {} do
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
				add(note("No TODO comments found in this place's scripts."), Kit.rows.field)
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
			for index, option in
				{
					{ text = "No reminder", days = 0 },
					{ text = "Tomorrow", days = 1 },
					{ text = "In 3 days", days = 3 },
					{ text = "Next week", days = 7 },
				}
			do
				local chip = Controls.chip(option.text, nil, function()
					remind = option.days
					Store.set({ lastChangeAt = os.clock() })
				end, maid, { Size = UDim2.fromScale(0.24, 1), LayoutOrder = index })
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
