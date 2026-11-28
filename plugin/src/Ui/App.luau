--!strict

local UserInputService = game:GetService("UserInputService")

local Actions = require(script.Parent.Parent.State.Actions)
local CommandBar = require(script.Parent.Components.CommandBar)
local Config = require(script.Parent.Parent.Config)
local Drawer = require(script.Parent.Screens.Drawer)
local Kit = require(script.Parent.Kit)
local Links = require(script.Parent.Parent.Studio.Links)
local ListView = require(script.Parent.Screens.ListView)
local Maid = require(script.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Components.Overlay)
local Pages = require(script.Parent.Screens.Pages)
local PixelLock = require(script.Parent.Layout.PixelLock)
local ReportsModule = require(script.Parent.Parent.Studio.ReportsModule)
local Settings = require(script.Parent.Screens.Settings)
local Setup = require(script.Parent.Screens.Setup)
local Shell = require(script.Parent.Screens.Shell)
local Store = require(script.Parent.Parent.State.Store)
local Theme = require(script.Parent.Theme)
local TodoScanner = require(script.Parent.Parent.Studio.TodoScanner)
local Typography = require(script.Parent.Typography)

local App = {}

export type Handle = {
	titleBar: GuiObject,
	lock: PixelLock.PixelLock,
	openCommandBar: () -> (),
	addFromSelection: () -> (),
	focusComposer: () -> (),
	startTour: () -> (),
}

function App.mount(widget: any, plugin: Plugin, maid: Maid.Maid, host: GuiObject?, onClose: (() -> ())?): Handle
	local background = Kit.surface("canvas", { Name = "CheckpointLTC", Parent = host or widget })
	maid:give(background)
	maid:give(background:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		Typography.setColumnWidth(math.min(background.AbsoluteSize.X, 640))
	end))
	Typography.setColumnWidth(math.min(background.AbsoluteSize.X, 640))

	local lock = PixelLock.new(background, maid)
	local ctx: any = { maid = maid, plugin = plugin, lock = lock, onClose = onClose }

	local titleBar = Shell.titleBar(ctx)
	titleBar.root.Size = UDim2.fromScale(1, 0.075)
	titleBar.root.ZIndex = 60
	titleBar.root.Parent = background
	local brandRule = Kit.frame({
		Position = UDim2.fromScale(0, 0.075),
		Size = UDim2.fromScale(1, 0.003),
		ZIndex = 61,
		Parent = background,
	})
	Kit.surface("brandBlue", { Size = UDim2.fromScale(0.7, 1), ZIndex = 61, Parent = brandRule })
	Kit.surface(
		"brandRed",
		{ Position = UDim2.fromScale(0.7, 0), Size = UDim2.fromScale(0.3, 1), ZIndex = 61, Parent = brandRule }
	)

	local bodyFrame =
		Kit.frame({ Position = UDim2.fromScale(0, 0.078), Size = UDim2.fromScale(1, 0.922), Parent = background })
	local sidebar = Shell.sidebar(ctx)
	sidebar.root.Parent = bodyFrame
	local main = Kit.frame({ Name = "Main", ClipsDescendants = true, Parent = bodyFrame })
	local scrim = Kit.frame({ BackgroundTransparency = 0.5, ZIndex = 44, Visible = false, Parent = bodyFrame })
	Theme.bind(scrim, "BackgroundColor3", "overlay")
	maid:give(Kit.hitbox({ ZIndex = 44, Parent = scrim }).Activated:Connect(function()
		Actions.toggleSidebar(false)
	end))
	Overlay.registerFloating(scrim, { sidebar.root })

	Overlay.mount(background, plugin, maid)
	Overlay.onHintsToggled(function()
		lock:contentChanged()
	end)

	local setup = Setup.new(ctx)
	setup.root.Parent = background
	setup.root.Position = UDim2.fromScale(0, 0.078)
	setup.root.Size = UDim2.fromScale(1, 0.922)

	ctx.openCommandBar = function()
		App.openCommandBar(ctx)
	end
	ctx.scanTodos = function()
		task.spawn(function()
			Actions.toast("info", "Scanning scripts for TODO comments.")
			local found = TodoScanner.scan(200)
			Store.set({ todoResults = found })
			Actions.showView("todo")
		end)
	end
	ctx.addFromSelection = function()
		local state = Store.get()
		if state.phase ~= "ready" or not state.detail then
			Actions.toast("info", "Open a list first, then select something in the Explorer.")
			return
		end
		local link, instance = Links.fromSelection()
		if not link or not instance then
			Actions.toast("warning", "Select a part, model or script in the Explorer first.")
			return
		end
		Actions.addItem(
			"Work on " .. instance.Name,
			{ link = link, label = if instance:IsA("LuaSourceContainer") then "Scripting" else nil }
		)
		Actions.toast("success", "Added a task linked to " .. instance.Name .. ".")
	end
	ctx.insertReportsModule = function(key: string)
		local ok, message = ReportsModule.insert(key)
		Actions.toast(if ok then "success" else "error", message)
	end

	local listView = ListView.new(ctx)
	listView.root.Parent = main
	local drawer = Drawer.new(ctx)
	drawer.root.Parent = main
	ctx.splitTask = function(item: any)
		drawer.openSplit(item)
	end
	ctx.autoAssignMenu = function()
		listView.autoAssignMenu()
	end
	Overlay.setToastAnchor(function()
		local state = Store.get()
		if state.phase == "ready" and state.view == "list" and bodyFrame.Visible then
			return listView.toastAnchor()
		end
		return nil
	end)
	local settingsView = Settings.new(ctx)
	settingsView.root.Parent = main
	local pages = {
		myTasks = Pages.myTasks(ctx),
		notifications = Pages.notifications(ctx),
		search = Pages.search(ctx),
		trash = Pages.trash(ctx),
		activity = Pages.activity(ctx),
		inbox = Pages.inbox(ctx),
		todo = Pages.todo(ctx),
		people = Pages.people(ctx),
	}
	for _, page in pages do
		page.root.Parent = main
	end
	local emptyView = Kit.frame({ Parent = main })
	local emptyText = Kit.label({
		text = "Pick a list on the left, or press New list.",
		role = "body",
		token = "subtext",
		wrap = true,
		align = Enum.TextXAlignment.Center,
		props = { Size = UDim2.fromScale(0.8, 0.2), Position = UDim2.fromScale(0.1, 0.35) },
	})
	emptyText.Parent = emptyView

	ctx.startTour = function()
		App.tour({
			titleBar = titleBar,
			sidebar = sidebar.root,
			composer = listView.composerSlot,
			menu = listView.menuButton,
		})
	end
	ctx.showWhatsNew = function(force: boolean?)
		App.whatsNew({
			search = titleBar.searchButton,
			settings = titleBar.settingsButton,
			sidebar = sidebar.root,
			composer = listView.composerSlot,
			more = listView.menuButton,
		}, force == true)
	end

	local lastAccent = ""
	local lastHints, lastTooltips = true, true
	local tourChecked = false

	local function layout(state: Store.State): boolean
		local narrow = background.AbsoluteSize.X < Config.widget.sidebarBreakpoint
		if narrow then
			sidebar.root.Size = UDim2.fromScale(0.78, 1)
			sidebar.root.Position = UDim2.fromScale(if state.sidebarOpen then 0 else -0.8, 0)
			sidebar.root.Visible = state.sidebarOpen
			scrim.Visible = state.sidebarOpen
			main.Position = UDim2.fromScale(0, 0)
			main.Size = UDim2.fromScale(1, 1)
		else
			sidebar.root.Size = UDim2.fromScale(0.3, 1)
			sidebar.root.Position = UDim2.fromScale(0, 0)
			sidebar.root.Visible = true
			scrim.Visible = false
			main.Position = UDim2.fromScale(0.3, 0)
			main.Size = UDim2.fromScale(0.7, 1)
		end
		return narrow
	end

	local function render(state: Store.State)
		local accent = state.prefs.accent or "brand"
		if accent ~= lastAccent then
			lastAccent = accent
			Theme.setAccent(accent)
		end
		Typography.setOptions(
			state.prefs.textSizing == "auto",
			tonumber(state.prefs.titleSize) or 1,
			tonumber(state.prefs.bodySize) or 1,
			tonumber(state.prefs.smallSize) or 1
		)
		if state.prefs.showHints ~= lastHints or state.prefs.showTooltips ~= lastTooltips then
			lastHints, lastTooltips = state.prefs.showHints, state.prefs.showTooltips
			Overlay.setPreferences(lastTooltips ~= false, lastHints ~= false)
		end

		local ready = state.phase == "ready"
		local narrow = layout(state)
		titleBar.render(state, narrow)
		setup.root.Visible = not ready
		bodyFrame.Visible = ready
		if not ready then
			setup.render(state)
			return
		end
		sidebar.render(state)
		local view = state.view
		listView.root.Visible = view == "list"
		settingsView.root.Visible = view == "settings"
		emptyView.Visible = view == "empty"
		for name, page in pages do
			page.root.Visible = view == name
		end
		if view == "list" then
			listView.render(state)
		elseif view == "settings" then
			settingsView.render(state)
		elseif pages[view] then
			pages[view].render(state)
		end
		drawer.render(state)
		lock:contentChanged()
		Overlay.placeToasts()

		if not tourChecked and state.me and widget.Enabled then
			tourChecked = true
			task.delay(1, function()
				if not widget.Enabled then
					tourChecked = false
					return
				end
				local prefs = Store.get().prefs
				if not prefs.tourDone then
					ctx.startTour()
				elseif prefs.showWhatsNew and prefs.seenVersion ~= Config.whatsNew.version then
					ctx.showWhatsNew(false)
				end
			end)
		end
	end

	local scheduled = false
	local function scheduleRender()
		if scheduled then
			return
		end
		scheduled = true
		task.defer(function()
			scheduled = false
			if background.Parent then
				render(Store.get())
			end
		end)
	end

	local connection = Store.changed:connect(scheduleRender)
	maid:give(connection.disconnect)
	maid:give(Theme.onChanged(scheduleRender))
	maid:give(background:GetPropertyChangedSignal("AbsoluteSize"):Connect(scheduleRender))
	local toastConnection = Actions.toasted:connect(function(kind, text, action)
		Overlay.toast(kind, text, action)
	end)
	maid:give(toastConnection.disconnect)
	local contentConnection = Actions.contentChanged:connect(function()
		lock:contentChanged()
	end)
	maid:give(contentConnection.disconnect)

	local hovering = false
	maid:give(background.MouseEnter:Connect(function()
		hovering = true
	end))
	maid:give(background.MouseLeave:Connect(function()
		hovering = false
	end))
	maid:give(UserInputService.InputBegan:Connect(function(input, processed)
		if not widget.Enabled then
			return
		end
		local slash = input.KeyCode == Enum.KeyCode.Slash
			and not processed
			and hovering
			and UserInputService:GetFocusedTextBox() == nil
		if slash and Store.get().phase == "ready" then
			ctx.openCommandBar()
		elseif input.KeyCode == Enum.KeyCode.Escape and not processed then
			if Store.get().drawerItemId then
				Actions.openDrawer(nil)
			end
		end
	end))

	maid:give(widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if widget.Enabled then
			lock:open()
			render(Store.get())
		else
			lock:close()
		end
	end))
	if widget.Enabled then
		lock:open()
	end
	render(Store.get())

	return {
		titleBar = titleBar.root,
		lock = lock,
		openCommandBar = ctx.openCommandBar,
		addFromSelection = ctx.addFromSelection,
		focusComposer = function()
			if Store.get().view ~= "list" then
				Actions.showView("list")
			end
			task.defer(function()
				listView.composer:focus()
			end)
		end,
		startTour = ctx.startTour,
	}
end

function App.openCommandBar(ctx: any)
	CommandBar.open(function()
		local state = Store.get()
		local commands: { CommandBar.Command } = {}
		local function add(title: string, subtitle: string?, run: () -> ())
			table.insert(commands, { title = title, subtitle = subtitle, run = run })
		end
		if state.home then
			for _, group in { state.home.mine, state.home.assigned, state.home.opened } do
				for _, summary in group do
					add(summary.title, "List", function()
						Actions.openList(summary.id)
					end)
				end
			end
		end
		if state.detail then
			for _, item in state.detail.items do
				add(item.text, "Task in " .. state.detail.list.title, function()
					Actions.openDrawer(item.id)
				end)
			end
		end
		add("New list", "Action", function()
			Overlay.prompt({
				title = "New list",
				placeholder = "List name",
				confirm = "Create",
				maxLength = Store.limit("titleMaxLength", Config.fallbackLimits.titleMaxLength),
				onConfirm = function(text)
					Actions.createList(text, nil)
				end,
			})
		end)
		add("My tasks", "Action", function()
			Actions.showView("myTasks")
		end)
		add("Search all lists", "Action", function()
			Actions.showView("search")
		end)
		add("Add a task from my selection", "Action", ctx.addFromSelection)
		add("Scan scripts for TODO comments", "Action", ctx.scanTodos)
		add("Undo my last change", "Action", Actions.undo)
		add("Trash", "Action", function()
			Actions.showView("trash")
		end)
		add("Settings", "Action", function()
			Actions.openSettings("preferences")
		end)
		add("Report a bug", "Support", function()
			Actions.openSettings("support")
		end)
		add("Plan and limits", "Settings", function()
			Actions.openSettings("plan")
		end)
		add("Replay the tour", "Help", ctx.startTour)
		add(if state.prefs.view == "board" then "Switch to list view" else "Switch to board view", "View", function()
			Actions.setPreference("view", if state.prefs.view == "board" then "list" else "board")
		end)
		add(if state.prefs.compact then "Turn off compact mode" else "Turn on compact mode", "View", function()
			Actions.setPreference("compact", not state.prefs.compact)
		end)
		add("Refresh", "Action", function()
			Actions.refresh(false)
		end)
		return commands
	end)
end

local tourSteps = {
	{
		key = "sidebar",
		title = "Your lists",
		body = "Lists you own, lists given to you and lists you opened by code live here. Lists pinned to this game sit at the top.",
	},
	{
		key = "titleBar",
		title = "Title bar",
		body = "Press / with the mouse over this window to search, see notifications, refresh, and open Settings. Hover any button to see what it does.",
	},
	{
		key = "composer",
		title = "Add tasks",
		body = "Type a task and press Enter or the arrow. Long tasks grow upward as you type. Double click a task to edit it right there.",
	},
	{
		key = "menu",
		title = "List actions",
		body = "Rename, pin to this game, export, scan TODO comments, see the activity log and more. Every task has its own ••• menu too.",
	},
}

function App.tour(targets: { [string]: any })
	local index = 0
	local function step()
		index += 1
		local entry = tourSteps[index]
		if not entry then
			Overlay.closeModal()
			Actions.setPreference("tourDone", true)
			return
		end
		local target = targets[entry.key]
		local gui = if type(target) == "table" then target.root else target
		if entry.key == "sidebar" and gui and not gui.Visible then
			Actions.toggleSidebar(true)
			task.wait(0.1)
		end
		if entry.key ~= "sidebar" and Store.get().sidebarOpen then
			Actions.toggleSidebar(false)
			task.wait(0.1)
		end
		Overlay.highlight(
			gui,
			entry.title,
			entry.body,
			string.format("Step %d of %d", index, #tourSteps),
			step,
			function()
				Overlay.closeModal()
				Actions.setPreference("tourDone", true)
			end,
			if index == #tourSteps then "Done" else "Next"
		)
	end
	step()
end

function App.whatsNew(_targets: { [string]: GuiObject }, force: boolean)
	local prefs = Store.get().prefs
	if not force and (not prefs.showWhatsNew or prefs.seenVersion == Config.whatsNew.version) then
		return
	end
	Overlay.notes({
		title = "Updated to " .. Config.whatsNew.version,
		subtitle = "Here's what's new.",
		bullets = Config.whatsNew.items,
	})
	Actions.setPreference("seenVersion", Config.whatsNew.version)
end

return App
