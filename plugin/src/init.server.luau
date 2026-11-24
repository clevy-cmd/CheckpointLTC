--!strict

local Selection = game:GetService("Selection")

local Actions = require(script.State.Actions)
local App = require(script.Ui.App)
local Auth = require(script.Api.Auth)
local Client = require(script.Api.Client)
local Config = require(script.Config)
local Links = require(script.Studio.Links)
local Maid = require(script.Core.Maid)
local Store = require(script.State.Store)
local Theme = require(script.Ui.Theme)
local Window = require(script.Ui.Layout.Window)
local Time = require(script.Core.Time)

local maid = Maid.new()
maid:give(plugin.Unloading:Connect(function()
	Actions.shutdown()
	maid:destroy()
end))

Auth.init(plugin)
Links.init(plugin)
maid:give(Theme.start())

local toolbar = plugin:CreateToolbar(Config.toolbarName)
local button =
	toolbar:CreateButton(Config.widgetId, "Shared to do lists for your team", Config.icons.toolbar, Config.buttonText)
button.ClickableWhenViewportHidden = true

local window = Window.new(maid)
local widget = window.gui

local handle = App.mount(widget, plugin, maid, window.host, function()
	widget.Enabled = false
end)
window.attachDrag(handle.titleBar)

local badgeShown = false
local function setBadge(on: boolean)
	if on ~= badgeShown then
		badgeShown = on
		button.Icon = if on then Config.icons.toolbarBadge else Config.icons.toolbar
	end
end

maid:give(button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end))
local function syncButton()
	button:SetActive(widget.Enabled)
	if widget.Enabled then
		setBadge(false)
	end
end
maid:give(widget:GetPropertyChangedSignal("Enabled"):Connect(syncButton))
syncButton()

local function action(id: string, text: string, tip: string, run: () -> ())
	local pluginAction = plugin:CreatePluginAction(Config.actionPrefix .. id, text, tip, Config.icons.toolbar, true)
	maid:give(pluginAction.Triggered:Connect(run))
	maid:give(pluginAction)
end

action("TogglePanel", Config.productName .. ": Open or close", "Show or hide the panel", function()
	widget.Enabled = not widget.Enabled
end)
action("CommandBar", Config.productName .. ": Command bar", "Jump to any list, task or action", function()
	widget.Enabled = true
	handle.openCommandBar()
end)
action(
	"AddFromSelection",
	Config.productName .. ": Add task from selection",
	"Adds a task linked to what is selected",
	function()
		widget.Enabled = true
		handle.addFromSelection()
	end
)
action("NewTask", Config.productName .. ": New task", "Focus the new task box", function()
	widget.Enabled = true
	handle.focusComposer()
end)
action("Refresh", Config.productName .. ": Refresh", "Check for changes now", function()
	Actions.refresh(false)
end)
action("Undo", Config.productName .. ": Undo my last change", "Undo your last change on the open list", Actions.undo)

local booted = false
local function bootIfNeeded()
	if booted or not widget.Enabled then
		return
	end
	booted = true
	Actions.boot()
end

local lastActivity = os.clock()
local function touched()
	lastActivity = os.clock()
end
maid:give(Selection.SelectionChanged:Connect(touched))
maid:give(widget:GetPropertyChangedSignal("Enabled"):Connect(touched))
maid:give(Store.changed:connect(function(state)
	if state.lastChangeAt > lastActivity then
		touched()
	end
end).disconnect)

local lastRefresh = os.clock()
maid:give(widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	bootIfNeeded()
	local state = Store.get()
	if
		widget.Enabled
		and booted
		and state.phase == "ready"
		and os.clock() - lastRefresh > (state.prefs.refreshSeconds or 30)
	then
		lastRefresh = os.clock()
		Actions.refresh(true)
	end
end))
bootIfNeeded()

local function interval(): number
	local state = Store.get()
	local base = state.prefs.refreshSeconds or 30
	if not widget.Enabled then
		return base * Config.refresh.idleMultiplier * 2
	end
	if os.clock() - lastActivity > Config.refresh.idleAfterSeconds then
		return base * Config.refresh.idleMultiplier
	end
	return base
end

local lastUnseen = 0
maid:give(task.spawn(function()
	while true do
		task.wait(5)
		local state = Store.get()
		if booted and state.phase == "ready" and os.clock() - lastRefresh >= interval() then
			lastRefresh = os.clock()
			if widget.Enabled then
				Actions.refresh(true)
			else
				Actions.refreshHome(true)
				Actions.loadNotifications()
			end
			task.wait(2)
			local after = Store.get()
			local unseen = if after.notifications then after.notifications.unread else 0
			if after.home then
				for _, group in { after.home.mine, after.home.assigned, after.home.opened } do
					for _, summary in group do
						unseen += summary.unseen
					end
				end
			end
			if not widget.Enabled and unseen > lastUnseen and after.prefs.notifyChanges then
				setBadge(true)
			end
			lastUnseen = unseen
		end
	end
end))

local presenceItem: string? = nil
local presenceList: string? = nil
maid:give(task.spawn(function()
	while true do
		task.wait(Config.refresh.presenceSeconds)
		local state = Store.get()
		if state.phase == "ready" and widget.Enabled and state.listId and Client.hasSession() then
			presenceList = state.listId
			presenceItem = state.drawerItemId
			Client.putPresence(
				state.listId,
				if presenceItem and string.sub(presenceItem, 1, 5) ~= "temp:" then presenceItem else nil,
				if game.PlaceId > 0 then game.PlaceId else nil
			)
		elseif presenceList and Client.hasSession() then
			Client.clearPresence(presenceList)
			presenceList = nil
		end
	end
end))

local reminded: { [string]: boolean } = {}
maid:give(task.spawn(function()
	while true do
		task.wait(Config.refresh.reminderCheckSeconds)
		local state = Store.get()
		if state.phase == "ready" then
			local now = Time.nowMs()
			for _, item in state.myTasks or {} do
				if item.dueAt and not item.done and item.dueAt - now < 3600000 and not reminded[item.id] then
					reminded[item.id] = true
					local due = Time.dueText(item.dueAt)
					Actions.toast("warning", due .. ": " .. item.text)
					if not widget.Enabled then
						setBadge(true)
					end
				end
			end
		end
	end
end))

maid:give(task.spawn(function()
	while true do
		task.wait(600)
		if Store.get().phase == "ready" then
			Actions.loadMyTasks()
		end
	end
end))
