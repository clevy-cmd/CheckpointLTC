--!strict

local Actions = require(script.Parent.Parent.Parent.State.Actions)
local Config = require(script.Parent.Parent.Parent.Config)
local Controls = require(script.Parent.Parent.Components.Controls)
local Files = require(script.Parent.Parent.Parent.Studio.Files)
local GrowingTextBox = require(script.Parent.Parent.Components.GrowingTextBox)
local Kit = require(script.Parent.Parent.Kit)
local Measure = require(script.Parent.Parent.Measure)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Parent.Components.Overlay)
local Stack = require(script.Parent.Parent.Layout.Stack)
local Store = require(script.Parent.Parent.Parent.State.Store)
local Time = require(script.Parent.Parent.Parent.Core.Time)

local Settings = {}

local uploadWarning =
	"⚠️ All uploaded files are automatically moderated and checked. Inappropriate content will result in an immediate strike and a permanent ban from uploading files. Severe violations will result in a ban from CheckpointLTC entirely, and illegal content will be reported to the authorities."

local tabs: { { key: Store.SettingsTab, text: string } } = {
	{ key = "preferences", text = "Preferences" },
	{ key = "hints", text = "Help" },
	{ key = "plan", text = "Plan" },
	{ key = "support", text = "Support" },
	{ key = "devices", text = "Devices" },
}

function Settings.new(ctx: any): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.frame({ Name = "Settings" })
	local top = Kit.frame({ Size = UDim2.fromScale(1, 0.07), Parent = root })
	Kit.paddingXY(0.04, 0.12).Parent = top
	local title = Kit.label({ text = "Settings", role = "title" })
	title.Parent = top
	local tabRow = Kit.frame(
		{ Position = UDim2.fromScale(0, 0.07), Size = UDim2.fromScale(1, 0.055), Parent = root },
		{ Kit.row(0.01) }
	)
	Kit.paddingXY(0.04, 0.08).Parent = tabRow
	local tabChips = {}
	local tabWidths = { 0.235, 0.14, 0.14, 0.18, 0.18 }
	for index, tab in tabs do
		local chip = Controls.chip(tab.text, nil, function()
			Actions.openSettings(tab.key)
		end, maid, { Size = UDim2.fromScale(tabWidths[index] or 0.18, 1), LayoutOrder = index })
		chip.root.Parent = tabRow
		tabChips[tab.key] = chip
	end
	local body = Kit.frame({
		Position = UDim2.fromScale(0, 0.13),
		Size = UDim2.fromScale(1, 0.87),
		ClipsDescendants = false,
		Parent = root,
	})
	local stack = Stack.new(body, maid)
	Kit.paddingXY(0.04, 0).Parent = stack.frame
	ctx.lock:register(stack)
	local contentMaid = Maid.new()
	maid:give(contentMaid)
	local signature = ""

	local supportKind = "bug"
	local draft: { [string]: any } = { title = "", body = "", steps = "", includeInfo = true, category = nil }
	local attachment: Files.Picked? = nil
	local sending = false
	local progressText = ""
	local sendButton: any = nil

	local function add(child: GuiObject, ratio: any)
		stack:add(child, ratio)
	end

	local function toggle(text: string, hint: string?, key: string)
		local prefs = Store.get().prefs
		add(
			Controls.toggle(text, hint, prefs[key] == true, function(value)
				Actions.setPreference(key, value)
			end, contentMaid).root,
			Kit.rows.setting
		)
	end

	local function choice(text: string, key: string, options: { { text: string, value: any } })
		local prefs = Store.get().prefs
		local row = Kit.frame({})
		local label = Kit.label({ text = text, role = "body", props = { Size = UDim2.fromScale(0.34, 1) } })
		label.Parent = row
		local chips = Kit.frame(
			{ Position = UDim2.fromScale(0.34, 0.15), Size = UDim2.fromScale(0.66, 0.7), Parent = row },
			{ Kit.row(0.012) }
		)
		for index, option in options do
			local chip = Controls.chip(
				option.text,
				nil,
				function()
					Actions.setPreference(key, option.value)
				end,
				contentMaid,
				{ Size = UDim2.fromScale(math.min(0.32, 0.98 / #options - 0.012), 1), LayoutOrder = index }
			)
			chip.setSelected(prefs[key] == option.value)
			chip.root.Parent = chips
		end
		add(row, Kit.rows.setting)
	end

	local function buildPreferences()
		add(Controls.sectionTitle("Synced to my account on every computer"), Kit.rows.section)
		choice("Refresh", "refreshSeconds", {
			{ text = "10s", value = 10 },
			{ text = "30s", value = 30 },
			{ text = "1 min", value = 60 },
			{ text = "2 min", value = 120 },
		})
		choice("Sort tasks", "sortOrder", {
			{ text = "My order", value = "manual" },
			{ text = "Priority", value = "priority" },
			{ text = "Due", value = "due" },
			{ text = "Recent", value = "recent" },
		})
		choice("View", "view", { { text = "List", value = "list" }, { text = "Board", value = "board" } })
		choice(
			"New people are",
			"defaultRole",
			{ { text = "Editors", value = "editor" }, { text = "Viewers", value = "viewer" } }
		)
		toggle("Compact mode", "Smaller rows, more tasks on screen", "compact")
		toggle("Hide done tasks", nil, "hideCompleted")
		toggle("Confirm before deleting a task", nil, "confirmDelete")
		add(Controls.sectionTitle("Text"), Kit.rows.section)
		choice("Sizing", "textSizing", { { text = "Fixed", value = "fixed" }, { text = "Auto", value = "auto" } })
		local sizes = {
			{ text = "S", value = 0.85 },
			{ text = "M", value = 1 },
			{ text = "L", value = 1.15 },
			{ text = "XL", value = 1.3 },
		}
		choice("Titles", "titleSize", sizes)
		choice("Body text", "bodySize", sizes)
		choice("Small text", "smallSize", sizes)
		add(Controls.sectionTitle("Notify me about"), Kit.rows.section)
		toggle("Tasks given to me", nil, "notifyAssigned")
		toggle("Mentions in comments", nil, "notifyMentions")
		toggle("Changes to my lists", "A toast and a badge on the toolbar button", "notifyChanges")
		add(Controls.sectionTitle("Accent color"), Kit.rows.section)
		local row = Kit.frame({}, { Kit.row(0.02) })
		local prefs = Store.get().prefs
		for index, name in { "brand", "blue", "red", "green", "purple", "orange" } do
			local chip = Controls.chip(
				if name == "brand" then "Default" else name:sub(1, 1):upper() .. name:sub(2),
				(Config.accents :: any)[name],
				function()
					Actions.setPreference("accent", name)
				end,
				contentMaid,
				{ Size = UDim2.fromScale(0.15, 1), LayoutOrder = index }
			)
			chip.setSelected(prefs.accent == name)
			chip.root.Parent = row
		end
		add(row, Kit.rows.setting * 1.2)
	end

	local function buildHints()
		add(Controls.sectionTitle("Help and hints"), Kit.rows.section)
		toggle("Show hint text under buttons", "Short notes that say what a button does", "showHints")
		toggle("Show tooltips on hover", "Every icon button names itself and its shortcut", "showTooltips")
		toggle("Show What's new after updates", nil, "showWhatsNew")
		add(
			Controls.button({
				text = "Replay the tour",
				kind = "primary",
				onClick = function()
					ctx.startTour()
				end,
			}, contentMaid).root,
			Kit.rows.button
		)
		add(
			Controls.button({
				text = "Show What's new",
				onClick = function()
					ctx.showWhatsNew(true)
				end,
			}, contentMaid).root,
			Kit.rows.button
		)
		add(Controls.sectionTitle("Shortcuts"), Kit.rows.section)
		add(
			Kit.label({
				text = "Bind CheckpointLTC actions under File > Customize Shortcuts: open the panel, command bar, add a task from the selection, focus the new task box, refresh and undo. Press / with the mouse over the window to open the command bar.",
				role = "meta",
				token = "subtext",
				wrap = true,
			}),
			Measure.paragraph(
				"Bind CheckpointLTC actions under File > Customize Shortcuts: open the panel, command bar, add a task from the selection, focus the new task box, refresh and undo. Press / with the mouse over the window to open the command bar.",
				"meta"
			)
		)
	end

	local function buildPlan()
		local me = Store.get().me
		if not me then
			add(Kit.label({ text = "Loading", role = "meta", token = "dim" }), Kit.rows.field)
			return
		end
		local limits = me.limits
		add(Controls.sectionTitle("Your plan"), Kit.rows.section)
		add(
			Kit.label({
				text = if me.plan == "paid" then "Paid. A Lite tier is coming later." else "Free",
				role = "body",
			}),
			Kit.rows.field
		)
		local function meter(text: string, used: number, max: number, suffix: string?)
			local m = Controls.meter(text)
			m.set(used, max, suffix)
			add(m.root, Kit.rows.meter)
		end
		meter("Lists I own", me.usage.listsOwned, limits.listsOwned)
		local biggestItems, biggestEditors, biggestAssigned = 0, 0, 0
		for _, entry in me.usage.lists do
			biggestItems = math.max(biggestItems, entry.items)
			biggestEditors = math.max(biggestEditors, entry.editors)
			biggestAssigned = math.max(biggestAssigned, entry.assigned)
		end
		meter("Tasks in my fullest list", biggestItems, limits.itemsPerList)
		meter("Editors on my busiest list", biggestEditors, limits.editorsPerList)
		meter("People assigned on one list", biggestAssigned, limits.assignedPerList)
		add(Controls.sectionTitle("Other limits"), Kit.rows.section)
		local lines = {
			string.format(
				"List names up to %d characters, tasks up to %d.",
				limits.titleMaxLength,
				limits.itemMaxLength
			),
			string.format(
				"Bug reports: %d per hour. %s",
				limits.bugReportsPerHour,
				if me.cooldowns.bugAvailableAt
					then "Next one in " .. Time.countdown(me.cooldowns.bugAvailableAt) .. "."
					else "Ready now."
			),
			string.format(
				"Feedback: %d per hour. %s",
				limits.feedbackPerHour,
				if me.cooldowns.feedbackAvailableAt
					then "Next one in " .. Time.countdown(me.cooldowns.feedbackAvailableAt) .. "."
					else "Ready now."
			),
			string.format(
				"Attachments: one per report, up to %s, %s.",
				Time.bytes(limits.attachmentMaxBytes),
				table.concat(limits.attachmentTypes, ", ")
			),
			"File uploads: " .. (if me.uploads == "allowed" then "Allowed" else "Blocked"),
		}
		for _, line in lines do
			add(
				Kit.label({
					text = line,
					role = "meta",
					token = if string.find(line, "Blocked") then "danger" else "subtext",
					wrap = true,
				}),
				Kit.rows.setting
			)
		end
	end

	local function buildDevices()
		add(Controls.sectionTitle("Signed in on"), Kit.rows.section)
		for _, session in Store.get().sessions or {} do
			local row = Kit.surface("card", {}, {})
			local label = Kit.label({
				text = session.label .. (if session.current then "  ·  this one" else ""),
				role = "body",
				props = { Size = UDim2.fromScale(0.65, 0.55) },
			})
			label.Parent = row
			local seen = Kit.label({
				text = "Last used " .. Time.ago(session.lastSeenAt),
				role = "hint",
				token = "dim",
				props = { Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(0.65, 0.45) },
			})
			seen.Parent = row
			Controls.button({
				text = "Sign out",
				kind = "danger",
				onClick = function()
					Overlay.confirm({
						title = "Sign out " .. session.label .. "?",
						body = if session.current
							then "You will need to log in with Roblox again on this computer."
							else "That computer has to log in with Roblox again to use CheckpointLTC.",
						confirm = "Sign out",
						danger = true,
						onConfirm = function()
							if session.current then
								Actions.signOut()
							else
								Actions.signOutDevice(session.id)
							end
						end,
					})
				end,
				props = { Position = UDim2.fromScale(0.68, 0.2), Size = UDim2.fromScale(0.3, 0.6) },
				parent = row,
			}, contentMaid)
			add(row, Kit.rows.taskRow)
		end
	end

	local function field(label: string, key: string, placeholder: string, maxLength: number, multiline: boolean)
		add(Kit.label({ text = label, role = "label", token = "subtext" }), Kit.rows.section)
		local slot = Kit.frame({ ClipsDescendants = false })
		local box = GrowingTextBox.new({
			parent = slot,
			placeholder = placeholder,
			multiline = multiline,
			maxLength = function()
				return maxLength
			end,
			zIndex = 30,
			keepOnSubmit = true,
			onChanged = function(text)
				draft[key] = text
			end,
		}, contentMaid)
		box:setText(draft[key] or "")
		add(slot, Kit.rows.composer)
	end

	local function buildSupport()
		local state = Store.get()
		local me = state.me
		local limits = if me then me.limits else Config.fallbackLimits
		add(Controls.sectionTitle("Send to the developer"), Kit.rows.section)
		local kindRow = Kit.frame({}, { Kit.row(0.02) })
		for index, kind in { { key = "bug", text = "Report a bug" }, { key = "feedback", text = "Send feedback" } } do
			local chip = Controls.chip(kind.text, nil, function()
				supportKind = kind.key
				signature = ""
				Store.set({ lastChangeAt = os.clock() })
			end, contentMaid, { Size = UDim2.fromScale(0.48, 1), LayoutOrder = index })
			chip.setSelected(supportKind == kind.key)
			chip.root.Parent = kindRow
		end
		add(kindRow, Kit.rows.setting)

		local cooldownAt = if me
			then (if supportKind == "bug" then me.cooldowns.bugAvailableAt else me.cooldowns.feedbackAvailableAt)
			else nil
		if cooldownAt and cooldownAt > Time.nowMs() then
			local countdown = Kit.label({ text = "", role = "meta", token = "warning", wrap = true })
			local function tickCountdown()
				countdown.Text = string.format(
					"You can send one %s per hour. Next one in %s.",
					if supportKind == "bug" then "bug report" else "piece of feedback",
					Time.countdown(cooldownAt)
				)
			end
			tickCountdown()
			contentMaid:give(task.spawn(function()
				while countdown.Parent and Time.nowMs() < cooldownAt do
					task.wait(1)
					tickCountdown()
				end
				Actions.loadMe()
			end))
			add(countdown, Kit.rows.setting)
		end

		field(
			"Title",
			"title",
			if supportKind == "bug" then "Short summary of the bug" else "Short summary of the idea",
			limits.submissionTitleMaxLength or 100,
			false
		)
		field(
			if supportKind == "bug" then "What happened" else "The idea or request",
			"body",
			if supportKind == "bug" then "What went wrong?" else "What would make CheckpointLTC better?",
			limits.submissionBodyMaxLength or 2000,
			true
		)
		if supportKind == "bug" then
			field("Steps to reproduce", "steps", "1. Open a list  2. ...", limits.submissionBodyMaxLength or 2000, true)
			add(
				Controls.toggle(
					"Include plugin version and Studio info",
					"Version " .. Config.version .. ", theme and place type",
					draft.includeInfo == true,
					function(value)
						draft.includeInfo = value
					end,
					contentMaid
				).root,
				Kit.rows.setting
			)
		else
			local categoryRow = Kit.frame({}, { Kit.row(0.02) })
			for index, category in { "UI", "Feature", "Other" } do
				local chip = Controls.chip(category, nil, function()
					draft.category = if draft.category == category then nil else category
					signature = ""
					Store.set({ lastChangeAt = os.clock() })
				end, contentMaid, { Size = UDim2.fromScale(0.3, 1), LayoutOrder = index })
				chip.setSelected(draft.category == category)
				chip.root.Parent = categoryRow
			end
			add(categoryRow, Kit.rows.setting)
		end

		add(
			Kit.label({ text = uploadWarning, role = "meta", token = "warning", wrap = true }),
			Measure.paragraph(uploadWarning, "meta")
		)
		if me and me.uploads ~= "allowed" then
			add(
				Kit.label({
					text = "File uploads are disabled on this account.",
					role = "body",
					token = "danger",
					wrap = true,
				}),
				Kit.rows.setting
			)
		else
			local accepted = state.prefs.uploadWarningAccepted == true
			add(
				Controls.toggle("I understand", "Remembered for my account", accepted, function(value)
					if value then
						Actions.acceptUploadWarning()
					else
						Actions.setPreference("uploadWarningAccepted", false)
					end
					signature = ""
				end, contentMaid).root,
				Kit.rows.setting
			)
			if attachment then
				local picked = attachment :: Files.Picked
				local row = Kit.surface("card", {}, {})
				local name = Kit.label({
					text = picked.name .. "  ·  " .. Time.bytes(picked.size),
					role = "meta",
					props = { Size = UDim2.fromScale(0.7, 1) },
				})
				name.Parent = row
				Controls.button({
					text = "Remove",
					onClick = function()
						attachment = nil
						signature = ""
						Store.set({ lastChangeAt = os.clock() })
					end,
					props = { Position = UDim2.fromScale(0.72, 0.15), Size = UDim2.fromScale(0.26, 0.7) },
					parent = row,
				}, contentMaid)
				add(row, Kit.rows.taskRow)
			else
				local attach = Controls.button({
					text = "Attach a file",
					hint = "mp4, mov, png, jpg or txt, up to "
						.. Time.bytes(limits.attachmentMaxBytes or Config.fallbackLimits.attachmentMaxBytes),
					onClick = function()
						if not Store.get().prefs.uploadWarningAccepted then
							Actions.toast("warning", "Tick I understand first.")
							return
						end
						task.spawn(function()
							local file, problem = Files.pick(
								limits.attachmentTypes or Config.fallbackLimits.attachmentTypes,
								limits.attachmentMaxBytes or Config.fallbackLimits.attachmentMaxBytes
							)
							if problem then
								Actions.toast("error", problem)
							elseif file then
								attachment = file
								signature = ""
								Store.set({ lastChangeAt = os.clock() })
							end
						end)
					end,
				}, contentMaid)
				attach.setEnabled(accepted)
				add(attach.root, Kit.rows.button * 0.7)
			end
		end

		local send
		send = Controls.button({
			text = if sending
				then progressText
				else (if supportKind == "bug" then "Send bug report" else "Send feedback"),
			kind = "primary",
			onClick = function()
				if sending then
					return
				end
				local titleText = string.match(draft.title or "", "^%s*(.-)%s*$") or ""
				local bodyText = string.match(draft.body or "", "^%s*(.-)%s*$") or ""
				if titleText == "" or bodyText == "" then
					Actions.toast(
						"error",
						"Fill in the title and " .. (if supportKind == "bug" then "what happened." else "your idea.")
					)
					return
				end
				sending = true
				progressText = "Sending"
				signature = ""
				Store.set({ lastChangeAt = os.clock() })
				local studio = settings().Studio
				local fields: { [string]: any } = { title = titleText, body = bodyText }
				if supportKind == "bug" then
					fields.steps = draft.steps
					fields.includeInfo = draft.includeInfo == true
					if draft.includeInfo then
						fields.studioInfo = string.format(
							"Theme %s, %s, place %s",
							tostring(studio.Theme.Name),
							if game:GetService("RunService"):IsRunning() then "playtest" else "edit mode",
							if game.PlaceId > 0 then "published" else "local file"
						)
					end
				else
					fields.category = draft.category
				end
				local file = attachment
				Actions.submit(
					supportKind,
					fields,
					if file then { name = file.name, size = file.size, contents = file.contents } else nil,
					function(text)
						progressText = text
						if sendButton then
							sendButton.setText(text)
						end
					end,
					function(ok)
						sending = false
						if ok then
							draft = { title = "", body = "", steps = "", includeInfo = true, category = nil }
							attachment = nil
						end
						signature = ""
						Store.set({ lastChangeAt = os.clock() })
					end
				)
			end,
		}, contentMaid)
		send.setEnabled(not sending and not (cooldownAt and cooldownAt > Time.nowMs()))
		sendButton = send
		add(send.root, Kit.rows.button)
		add(
			Kit.label({
				text = "Reports go to my Discord. I read every one.",
				role = "hint",
				token = "dim",
				align = Enum.TextXAlignment.Center,
			}),
			Kit.rows.hint
		)
	end

	local view: any = { root = root }

	function view.render(state: Store.State)
		for key, chip in tabChips do
			chip.setSelected(state.settingsTab == key)
		end
		local me = state.me
		local parts = { state.settingsTab, tostring(me and me.serverTime or 0), tostring(#(state.sessions or {})) }
		for _, key in
			{
				"textSizing",
				"titleSize",
				"bodySize",
				"smallSize",
				"refreshSeconds",
				"sortOrder",
				"view",
				"defaultRole",
				"compact",
				"hideCompleted",
				"confirmDelete",
				"notifyAssigned",
				"notifyMentions",
				"notifyChanges",
				"accent",
				"showHints",
				"showTooltips",
				"showWhatsNew",
				"uploadWarningAccepted",
			}
		do
			table.insert(parts, tostring(state.prefs[key]))
		end
		local next = table.concat(parts, "|")
		if next == signature then
			return
		end
		local focused = false
		for _, descendant in stack.frame:GetDescendants() do
			if descendant:IsA("TextBox") and descendant:IsFocused() then
				focused = true
			end
		end
		if focused and state.settingsTab == "support" then
			return
		end
		signature = next
		local scroll = stack.frame.CanvasPosition
		contentMaid:clean()
		stack:clear()
		if state.settingsTab == "preferences" then
			buildPreferences()
		elseif state.settingsTab == "hints" then
			buildHints()
		elseif state.settingsTab == "plan" then
			buildPlan()
		elseif state.settingsTab == "support" then
			buildSupport()
		else
			buildDevices()
		end
		add(Controls.divider(), 200)
		add(
			Controls.button({
				text = "Log out on this computer",
				kind = "ghost",
				onClick = function()
					Overlay.confirm({
						title = "Log out?",
						body = "This computer signs out. Your lists stay on the server and come back when you log in again.",
						confirm = "Log out",
						danger = true,
						onConfirm = Actions.signOut,
					})
				end,
			}, contentMaid).root,
			Kit.rows.button
		)
		stack:lock()
		stack.frame.CanvasPosition = scroll
	end

	return view
end

return Settings
