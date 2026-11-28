--!strict

local Actions = require(script.Parent.Parent.Parent.State.Actions)
local Config = require(script.Parent.Parent.Parent.Config)
local Controls = require(script.Parent.Parent.Components.Controls)
local Files = require(script.Parent.Parent.Parent.Studio.Files)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Parent.Components.Overlay)
local Stack = require(script.Parent.Parent.Layout.Stack)
local Store = require(script.Parent.Parent.Parent.State.Store)
local Theme = require(script.Parent.Parent.Theme)

local Shell = {}

function Shell.titleBar(ctx: any): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.surface("raised", { Name = "TitleBar" })
	Kit.paddingXY(0.02, 0.14).Parent = root
	local left = Kit.frame({ Size = UDim2.fromScale(0.55, 1), Parent = root }, { Kit.row(0.02) })
	local menuButton = Controls.iconButton({
		icon = "sidebar",
		tooltip = "Show lists",
		onClick = function()
			Actions.toggleSidebar()
		end,
		props = { Size = UDim2.fromScale(0.2, 1), LayoutOrder = 0, Name = "SidebarButton" },
		parent = left,
	}, maid)
	local title = Kit.label({
		text = Config.productName,
		role = "label",
		props = { Size = UDim2.fromScale(0.7, 1), LayoutOrder = 2 },
	})
	title.Parent = left
	local right = Kit.frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.45, 1),
		Parent = root,
	}, {
		Kit.list(Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center, 0.03),
	})
	local search = Controls.iconButton({
		icon = "search",
		tooltip = "Command bar",
		shortcut = "/",
		onClick = function()
			ctx.openCommandBar()
		end,
		props = { Size = UDim2.fromScale(0.22, 1), LayoutOrder = 1, Name = "SearchButton" },
		parent = right,
	}, maid)
	local bell = Controls.iconButton({
		icon = "bell",
		tooltip = "Notifications",
		onClick = function()
			Actions.showView("notifications")
		end,
		props = { Size = UDim2.fromScale(0.22, 1), LayoutOrder = 2 },
		parent = right,
	}, maid)
	local refresh = Controls.iconButton({
		icon = "refresh",
		tooltip = "Refresh now",
		onClick = function()
			Actions.refresh(false)
		end,
		props = { Size = UDim2.fromScale(0.22, 1), LayoutOrder = 3 },
		parent = right,
	}, maid)
	local settingsButton = Controls.iconButton({
		icon = "settings",
		tooltip = "Settings, help and support",
		onClick = function()
			Actions.openSettings(nil)
		end,
		props = { Size = UDim2.fromScale(0.22, 1), LayoutOrder = 4, Name = "SettingsButton" },
		parent = right,
	}, maid)
	if ctx.onClose then
		Controls.iconButton({
			icon = "close",
			tooltip = "Close the window",
			onClick = ctx.onClose,
			props = { Size = UDim2.fromScale(0.22, 1), LayoutOrder = 5 },
			parent = right,
		}, maid)
	end

	return {
		root = root,
		searchButton = search.root,
		settingsButton = settingsButton.root,
		render = function(state: Store.State, narrow: boolean)
			local ready = state.phase == "ready"
			menuButton.setVisible(ready and narrow)
			search.setVisible(ready)
			bell.setVisible(ready)
			refresh.setVisible(ready)
			settingsButton.setVisible(ready)
			bell.setBadge(Actions.notificationCount(state))
			title.Text = if not Config.isTestBuild and state.environment ~= "production"
				then Config.productName .. "  ·  " .. state.environment
				else Config.productName
			menuButton.setActive(state.sidebarOpen)
		end,
	}
end

local function newListMenu()
	local items: { Overlay.MenuItem } = {
		{
			text = "Blank list",
			run = function()
				Overlay.prompt({
					title = "New list",
					placeholder = "List name",
					confirm = "Create",
					maxLength = Store.limit("titleMaxLength", Config.fallbackLimits.titleMaxLength),
					onConfirm = function(text)
						Actions.createList(text, nil)
					end,
				})
			end,
		},
		{
			text = "Template: Game launch checklist",
			run = function()
				Actions.createList(nil, "launch")
			end,
		},
		{
			text = "Template: Bug triage",
			run = function()
				Actions.createList(nil, "triage")
			end,
		},
		{
			text = "Import from a JSON or Markdown file",
			run = function()
				task.spawn(function()
					local file, problem = Files.pick({ "json", "md", "txt" }, 256 * 1024)
					if problem then
						Actions.toast("error", problem)
					elseif file then
						Actions.importList(if file.extension == "json" then "json" else "md", file.contents)
					end
				end)
			end,
		},
		{
			text = "Open a list with a share code",
			run = function()
				Overlay.prompt({
					title = "Open with a code",
					body = "Ask the owner for the 8 letter code. You can view the list once you open it.",
					placeholder = "ABCD 2345",
					confirm = "Open",
					maxLength = 12,
					onConfirm = function(text)
						Actions.joinByCode(text)
					end,
				})
			end,
		},
	}
	Overlay.menu(items)
end

function Shell.sidebar(ctx: any): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.surface("sidebar", { Name = "Sidebar", ZIndex = 45 })
	local top = Kit.frame({ Size = UDim2.fromScale(1, 0.085), ZIndex = 45, Parent = root })
	Kit.paddingXY(0.05, 0.12).Parent = top
	Controls.button({
		text = "New list",
		kind = "primary",
		tooltip = "Blank list, template, import or share code",
		onClick = function()
			newListMenu()
		end,
		props = { Size = UDim2.fromScale(1, 1), ZIndex = 45, Name = "NewListButton" },
		parent = top,
	}, maid)

	local holder =
		Kit.frame({ Position = UDim2.fromScale(0, 0.09), Size = UDim2.fromScale(1, 0.76), ZIndex = 45, Parent = root })

	local footer =
		Kit.frame({ Position = UDim2.fromScale(0, 0.86), Size = UDim2.fromScale(1, 0.14), ZIndex = 45, Parent = root })
	Kit.paddingXY(0.05, 0.08).Parent = footer
	Controls.button({
		text = "Download Guide",
		tooltip = "The full CheckpointLTC guide as a PDF",
		onClick = function()
			Overlay.prompt({
				title = "Download the guide",
				body = "Copy this link into your browser to open the CheckpointLTC guide. Save it from there to keep your own copy.",
				placeholder = "",
				initial = Config.guideUrl,
				confirm = "Done",
				maxLength = 300,
				readOnly = true,
			})
		end,
		props = { Size = UDim2.fromScale(1, 0.48), ZIndex = 45, Name = "GuideButton" },
		parent = footer,
	}, maid)
	local versionLabel = Kit.label({
		text = "v" .. Config.version,
		role = "hint",
		token = "dim",
		wrap = true,
		props = { Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45), ZIndex = 45 },
	})
	versionLabel.Parent = footer
	local shownUpdate: string? = nil
	local versionHit =
		Kit.hitbox({ Position = versionLabel.Position, Size = versionLabel.Size, ZIndex = 46, Parent = footer })
	maid:give(versionHit.Activated:Connect(function()
		if shownUpdate then
			Actions.showView("notifications")
			Actions.setNotificationTab("updates")
		end
	end))
	local function renderVersion(update: string?)
		if update == shownUpdate and versionLabel.Text ~= "" then
			return
		end
		shownUpdate = update
		if update then
			versionLabel.Text = "v" .. Config.version .. "  ·  " .. update .. " is out"
			Theme.bind(versionLabel, "TextColor3", "warning")
		else
			versionLabel.Text = "v" .. Config.version
			Theme.bind(versionLabel, "TextColor3", "dim")
		end
	end
	local stack = Stack.new(holder, maid, { ZIndex = 45 }, 0.004)
	Kit.paddingXY(0.03, 0).Parent = stack.frame
	ctx.lock:register(stack)
	local rowMaid = Maid.new()
	maid:give(rowMaid)
	local signature = ""

	local function navRow(text: string, glyph: string, active: boolean, count: number?, onClick: () -> ()): Frame
		local row = Kit.surface(if active then "selected" else "sidebar", { ZIndex = 46 }, {})
		local marker =
			Kit.surface("accent", { Size = UDim2.fromScale(0.012, 1), Visible = active, ZIndex = 47, Parent = row })
		marker.Name = glyph
		local label = Kit.label({
			text = text,
			role = "meta",
			token = if active then "text" else "subtext",
			props = { Position = UDim2.fromScale(0.03, 0), Size = UDim2.fromScale(0.8, 1), ZIndex = 46 },
		})
		label.Parent = row
		if count and count > 0 then
			local badge = Kit.surface("accent", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.97, 0.5),
				Size = UDim2.fromScale(0.14, 0.6),
				ZIndex = 47,
				Parent = row,
			}, {})
			local number = Kit.label({
				text = if count > 99 then "99+" else tostring(count),
				role = "hint",
				token = "accentText",
				align = Enum.TextXAlignment.Center,
				props = { ZIndex = 48 },
			})
			number.Parent = badge
		end
		local hit = Kit.hitbox({ ZIndex = 49, Parent = row })
		rowMaid:give(hit.MouseEnter:Connect(function()
			if not active and not Overlay.isCovered(hit) then
				Theme.bind(row, "BackgroundColor3", "hover")
			end
		end))
		rowMaid:give(hit.MouseLeave:Connect(function()
			Theme.bind(row, "BackgroundColor3", if active then "selected" else "sidebar")
		end))
		rowMaid:give(hit.Activated:Connect(onClick))
		return row
	end

	local function render(state: Store.State)
		renderVersion(state.updateVersion)
		local home = state.home
		local parts = { state.view, state.listId or "", tostring(state.prefs.showHints) }
		if home then
			for _, group in { home.mine, home.assigned, home.opened } do
				for _, summary in group do
					table.insert(
						parts,
						summary.id
							.. summary.title
							.. summary.unseen
							.. tostring(summary.archived)
							.. tostring(summary.placeId)
					)
				end
			end
		end
		table.insert(parts, tostring(Actions.notificationCount(state)))
		local nextSignature = table.concat(parts, "|")
		if nextSignature == signature then
			return
		end
		signature = nextSignature
		rowMaid:clean()
		stack:clear()

		local function title(text: string)
			stack:add(Controls.sectionTitle(text, { ZIndex = 46 }), Kit.rows.section)
		end
		local function listRow(summary: Store.ListSummary)
			local active = state.view == "list" and state.listId == summary.id
			local done = if summary.itemCount > 0
				then string.format("  %d/%d", summary.doneCount, summary.itemCount)
				else ""
			stack:add(
				navRow(summary.title .. done, summary.role, active, summary.unseen, function()
					Actions.openList(summary.id)
				end),
				Kit.rows.sidebarRow
			)
		end

		title("Workspace")
		stack:add(
			navRow("My tasks", "nav", state.view == "myTasks", nil, function()
				Actions.showView("myTasks")
			end),
			Kit.rows.sidebarRow
		)
		stack:add(
			navRow("Search", "nav", state.view == "search", nil, function()
				Actions.showView("search")
			end),
			Kit.rows.sidebarRow
		)
		stack:add(
			navRow("Trash", "nav", state.view == "trash", nil, function()
				Actions.showView("trash")
			end),
			Kit.rows.sidebarRow
		)

		if not home then
			stack:add(
				Kit.label({
					text = state.homeError or "Loading lists",
					role = "meta",
					token = "dim",
					wrap = true,
					props = { ZIndex = 46 },
				}),
				Kit.rows.sidebarRow
			)
			stack:lock()
			return
		end
		local pinned, active, archived = {}, {}, {}
		for _, summary in home.mine do
			if summary.archived then
				table.insert(archived, summary)
			elseif summary.placeId and summary.placeId == game.PlaceId and game.PlaceId > 0 then
				table.insert(pinned, summary)
			else
				table.insert(active, summary)
			end
		end
		for _, group in { home.assigned, home.opened } do
			for _, summary in group do
				if
					summary.placeId
					and summary.placeId == game.PlaceId
					and game.PlaceId > 0
					and not summary.archived
				then
					table.insert(pinned, summary)
				end
			end
		end
		if #pinned > 0 then
			title("This game")
			for _, summary in pinned do
				listRow(summary)
			end
		end
		title("My lists")
		if #active == 0 and #pinned == 0 then
			local empty = Kit.label({
				text = "No lists yet. Press New list to make one.",
				role = "meta",
				token = "dim",
				wrap = true,
				props = { ZIndex = 46 },
			})
			stack:add(empty, Kit.rows.sidebarRow * 0.8)
		end
		for _, summary in active do
			listRow(summary)
		end
		if #home.assigned > 0 then
			title("Assigned to me")
			for _, summary in home.assigned do
				if not (summary.placeId == game.PlaceId and game.PlaceId > 0) then
					listRow(summary)
				end
			end
		end
		if #home.opened > 0 then
			title("Opened by code")
			for _, summary in home.opened do
				if not (summary.placeId == game.PlaceId and game.PlaceId > 0) then
					listRow(summary)
				end
			end
		end
		if #archived > 0 then
			title("Archived")
			for _, summary in archived do
				listRow(summary)
			end
		end
		stack:lock()
	end

	return { root = root, render = render }
end

return Shell
