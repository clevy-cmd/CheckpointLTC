--!strict

local Auth = require(script.Parent.Parent.Api.Auth)
local Base64 = require(script.Parent.Parent.Core.Base64)
local Client = require(script.Parent.Parent.Api.Client)
local Config = require(script.Parent.Parent.Config)
local Debounce = require(script.Parent.Parent.Core.Debounce)
local Signal = require(script.Parent.Parent.Core.Signal)
local Store = require(script.Parent.Store)
local Time = require(script.Parent.Parent.Core.Time)

type Detail = Store.Detail
type Item = Store.Item
type Result = Client.Result

export type ToastKind = "info" | "success" | "error" | "warning"
export type ToastAction = { label: string, run: () -> () }

local Actions = {}

Actions.toasted = Signal.new() :: Signal.Signal<ToastKind, string, ToastAction?>
Actions.contentChanged = Signal.new() :: Signal.Signal<>

local alive = true
local tempCounter = 0
local pendingItems: { [string]: boolean } = {}
local deletedItems: { [string]: boolean } = {}

function Actions.toast(kind: ToastKind, text: string, action: ToastAction?)
	if alive then
		Actions.toasted:fire(kind, text, action)
	end
end

local function errorMessage(result: Result): string
	return if result.ok == false then result.error.message else ""
end

local function errorCode(result: Result): string
	return if result.ok == false then result.error.code else ""
end

local function signOutLocally(patch: { [string]: any }?)
	local userId = Store.get().userId
	Auth.saveKey(userId, nil)
	Client.setSession(userId, nil)
	local reset: { [string]: any } = {
		phase = "signedOut",
		home = nil,
		detail = nil,
		listId = nil,
		view = "empty",
		drawerItemId = nil,
		me = nil,
	}
	for key, value in patch or {} do
		reset[key] = value
	end
	Store.set(reset)
	Store.clear("home", "detail", "listId", "drawerItemId", "me")
end

local function handleCommonFailure(result: Result): boolean
	local code = errorCode(result)
	if code == "unauthorized" then
		signOutLocally()
		Actions.toast("error", "Your sign in expired. Log in with Roblox again to continue.")
		return true
	elseif code == "licence_required" then
		signOutLocally({ needsPurchase = true })
		Actions.toast("error", errorMessage(result))
		return true
	elseif code == "banned" then
		signOutLocally({ banned = true })
		Actions.toast("error", errorMessage(result))
		return true
	elseif code == "upgrade_required" then
		Actions.toast("warning", errorMessage(result))
		return true
	end
	return false
end

local function fail(result: Result)
	if not handleCommonFailure(result) then
		Actions.toast("error", errorMessage(result))
	end
end

Actions.fail = fail

local function changed()
	Store.set({ lastChangeAt = os.clock() })
	Actions.contentChanged:fire()
end

local function rememberPeople(people: { any }?)
	if not people or #people == 0 then
		return
	end
	local names = table.clone(Store.get().names)
	for _, person in people do
		if type(person) == "table" and type(person.userId) == "number" and person.name then
			names[person.userId] = { userId = person.userId, name = person.name, displayName = person.displayName }
		end
	end
	Store.set({ names = names })
end

function Actions.resolveNames(ids: { number })
	local missing = {}
	local names = Store.get().names
	for _, id in ids do
		if id > 0 and not names[id] and not table.find(missing, id) then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	task.spawn(function()
		local result = Client.usersByIds(missing)
		if result.ok then
			rememberPeople(result.data.users)
		end
	end)
end

local function cloneDetail(detail: Detail): Detail
	local copy = table.clone(detail)
	copy.items = table.clone(detail.items)
	return copy
end

local function findItemIndex(detail: Detail, itemId: string): number?
	for index, item in detail.items do
		if item.id == itemId then
			return index
		end
	end
	return nil
end

local function patchItem(listId: string, itemId: string, change: (Item) -> Item?)
	local state = Store.get()
	if state.listId ~= listId or not state.detail then
		return
	end
	local detail = cloneDetail(state.detail)
	local index = findItemIndex(detail, itemId)
	if not index then
		return
	end
	local updated = change(table.clone(detail.items[index]))
	if updated then
		detail.items[index] = updated
	else
		table.remove(detail.items, index)
	end
	Store.set({ detail = detail })
end

local function sortItems(items: { Item })
	table.sort(items, function(a, b)
		return a.position < b.position
	end)
end

local function mergeDetail(incoming: Detail): Detail
	local current = Store.get().detail
	if not current or current.list.id ~= incoming.list.id then
		return incoming
	end
	local merged = table.clone(incoming)
	merged.items = {}
	for _, item in incoming.items do
		if not deletedItems[item.id] then
			local localIndex = if pendingItems[item.id] then findItemIndex(current, item.id) else nil
			table.insert(merged.items, if localIndex then current.items[localIndex] else item)
		end
	end
	for _, item in current.items do
		if string.sub(item.id, 1, 5) == "temp:" then
			table.insert(merged.items, item)
		end
	end
	return merged
end

local function applyDetail(data: any)
	if type(data) ~= "table" or not data.list then
		return
	end
	local detail = mergeDetail(data :: Detail)
	sortItems(detail.items)
	rememberPeople(data.people)
	local ids = {}
	for _, item in detail.items do
		if item.assigneeId then
			table.insert(ids, item.assigneeId)
		end
	end
	Actions.resolveNames(ids)
	Store.set({ detail = detail, detailLoading = false })
	Store.clear("detailError")
	changed()
end

local function applyDelta(data: any)
	local state = Store.get()
	local detail = state.detail
	if not detail then
		return
	end
	local copy = cloneDetail(detail)
	copy.revision = data.revision
	copy.role = data.role
	for _, removed in data.removed or {} do
		local index = findItemIndex(copy, removed)
		if index and not pendingItems[removed] then
			table.remove(copy.items, index)
		end
	end
	for _, item in data.items or {} do
		if not pendingItems[item.id] and not deletedItems[item.id] then
			local index = findItemIndex(copy, item.id)
			if index then
				copy.items[index] = item
			else
				table.insert(copy.items, item)
			end
		end
	end
	sortItems(copy.items)
	local done = 0
	for _, item in copy.items do
		if item.done then
			done += 1
		end
	end
	copy.list = table.clone(copy.list)
	copy.list.itemCount = #copy.items
	copy.list.doneCount = done
	Store.set({ detail = copy })
	changed()
end

local function markSeen(listId: string, revision: number)
	task.spawn(function()
		Client.markSeen(listId, revision)
	end)
end

function Actions.loadMe()
	Debounce.run("loadMe", function()
		local result = Client.me()
		if result.ok then
			Store.set({ me = result.data, environment = result.data.environment or "production" })
			if result.data.uploadWarningAccepted ~= nil then
				local prefs = table.clone(Store.get().prefs)
				prefs.uploadWarningAccepted = result.data.uploadWarningAccepted
				Store.set({ prefs = prefs })
			end
		end
	end, 0)
end

function Actions.loadPreferences()
	task.spawn(function()
		local result = Client.preferences()
		if result.ok and type(result.data.preferences) == "table" then
			local prefs = table.clone(Store.defaultPrefs) :: { [string]: any }
			for key, value in result.data.preferences do
				prefs[key] = value
			end
			Store.set({ prefs = prefs })
			changed()
		end
	end)
end

function Actions.setPreference(key: string, value: any)
	local prefs = table.clone(Store.get().prefs)
	local before = prefs[key]
	prefs[key] = value
	Store.set({ prefs = prefs })
	changed()
	task.spawn(function()
		local result = Client.savePreferences({ [key] = value })
		if not result.ok then
			local rollback = table.clone(Store.get().prefs)
			rollback[key] = before
			Store.set({ prefs = rollback })
			fail(result)
		end
	end)
end

function Actions.refreshHome(silent: boolean?)
	Debounce.run("refreshHome", function()
		local result = Client.home()
		if not alive then
			return
		end
		if result.ok then
			Store.clear("homeError")
			Store.set({ home = result.data })
			changed()
		elseif not handleCommonFailure(result) then
			if Store.get().home == nil then
				Store.set({ homeError = errorMessage(result) })
			elseif not silent then
				Actions.toast("error", errorMessage(result))
			end
		end
	end, 0)
end

local function loadMeta()
	local result = Client.meta()
	if not alive or not result.ok or type(result.data) ~= "table" then
		return
	end
	Store.set({
		paid = result.data.paid == true,
		storeUrl = if type(result.data.storeUrl) == "string" and result.data.storeUrl ~= ""
			then result.data.storeUrl
			else nil,
		environment = result.data.environment or "production",
	})
	local latest = tostring(result.data.latestPluginVersion or "")
	local function parts(version: string): { number }
		local out = {}
		for piece in string.gmatch(version, "%d+") do
			table.insert(out, tonumber(piece) :: number)
		end
		return out
	end
	local a, b = parts(Config.version), parts(latest)
	for index = 1, math.max(#a, #b) do
		local x, y = a[index] or 0, b[index] or 0
		if x ~= y then
			if x < y then
				Store.set({ updateVersion = latest })
			end
			return
		end
	end
end

local function afterSignIn()
	Store.set({ phase = "ready", needsPurchase = false })
	Actions.loadSeenDue()
	Actions.loadPreferences()
	Actions.loadMe()
	Actions.refreshHome()
	Actions.loadNotifications()
	Actions.loadMyTasks()
	local last = Auth.getSetting(Config.settingKeys.lastListPrefix .. tostring(Store.get().userId))
	if type(last) == "string" and last ~= "" then
		Actions.openList(last)
	end
end

function Actions.boot()
	local userId = Auth.currentUserId()
	Store.set({ userId = userId })
	task.spawn(loadMeta)
	if userId <= 0 then
		Store.set({ phase = "signedOut" })
		return
	end
	local key = Auth.loadKey(userId)
	if not key then
		Store.set({ phase = "signedOut" })
		return
	end
	Client.setSession(userId, key)
	afterSignIn()
end

local loginAttempt = 0

function Actions.startLogin()
	Debounce.run("login", function()
		local userId = Auth.currentUserId()
		Store.set({ userId = userId })
		if userId <= 0 then
			Actions.toast("error", "Sign in to Roblox Studio first.")
			return
		end
		if Config.quickLogin then
			local result = Client.testRegister(userId)
			if result.ok then
				Auth.saveKey(userId, result.data.key)
				Client.setSession(userId, result.data.key)
				afterSignIn()
			else
				fail(result)
			end
			return
		end
		Store.set({ busyMessage = "Starting" })
		local result = Client.loginStart(userId)
		if not alive then
			return
		end
		Store.clear("busyMessage")
		if not result.ok then
			fail(result)
			return
		end
		loginAttempt += 1
		local attempt = loginAttempt
		local data = result.data
		Store.set({ phase = "login", login = { code = data.code, url = data.url } })
		while alive and attempt == loginAttempt do
			task.wait(data.pollSeconds)
			if not alive or attempt ~= loginAttempt then
				return
			end
			local poll = Client.loginPoll(data.code, data.pollToken)
			if not alive or attempt ~= loginAttempt then
				return
			end
			if poll.ok and poll.data.status == "done" then
				Auth.saveKey(userId, poll.data.key)
				Client.setSession(userId, poll.data.key)
				Store.clear("login")
				afterSignIn()
				return
			elseif not poll.ok and poll.error.code ~= "network" and poll.error.code ~= "rate_limited" then
				Store.clear("login")
				Store.set({ phase = "signedOut" })
				fail(poll)
				return
			end
		end
	end)
end

function Actions.cancelLogin()
	loginAttempt += 1
	Store.clear("login")
	Store.set({ phase = "signedOut" })
end

function Actions.signOut()
	task.spawn(function()
		Client.signOutHere()
		signOutLocally()
		Actions.toast("info", "Signed out on this computer.")
	end)
end

function Actions.showView(view: Store.View)
	Store.set({ view = view, sidebarOpen = false })
	Store.clear("drawerItemId")
	if view == "myTasks" then
		Actions.loadMyTasks()
	elseif view == "notifications" then
		local counts = Actions.notificationCounts(Store.get())
		local tab = "mentions"
		for _, id in { "fix", "due", "mentions", "shared", "updates" } do
			if counts[id] > 0 then
				tab = id
				break
			end
		end
		Store.set({ notificationTab = tab, notificationSelected = {} })
		Actions.loadMyTasks()
	elseif view == "trash" then
		Actions.loadTrash()
	elseif view == "settings" then
		Actions.loadMe()
		Actions.loadSessions()
	elseif view == "inbox" then
		Actions.loadReports()
	elseif view == "activity" then
		Actions.loadActivity()
	end
	changed()
end

function Actions.openSettings(tab: Store.SettingsTab?)
	Store.set({ settingsTab = tab or Store.get().settingsTab })
	Actions.showView("settings")
end

function Actions.toggleSidebar(open: boolean?)
	Store.set({ sidebarOpen = if open == nil then not Store.get().sidebarOpen else open })
end

function Actions.setLabelFilter(label: string?)
	if label then
		Store.set({ labelFilter = label })
	else
		Store.clear("labelFilter")
	end
	changed()
end

function Actions.loadDetail(listId: string, quiet: boolean?)
	Debounce.run("detail:" .. listId, function()
		if not quiet then
			Store.set({ detailLoading = Store.get().detail == nil or (Store.get().detail :: any).list.id ~= listId })
		end
		local result = Client.getList(listId)
		if not alive or Store.get().listId ~= listId then
			return
		end
		if result.ok then
			applyDetail(result.data)
			markSeen(listId, result.data.revision)
		elseif result.error.code == "not_found" then
			Store.set({ detailLoading = false, view = "empty" })
			Store.clear("listId", "detail")
			Auth.setSetting(Config.settingKeys.lastListPrefix .. tostring(Store.get().userId), "")
			Actions.toast("warning", result.error.message)
			Actions.refreshHome(true)
		elseif not handleCommonFailure(result) then
			Store.set({ detailLoading = false, detailError = result.error.message })
		end
	end, 0)
end

function Actions.openList(listId: string)
	local state = Store.get()
	if state.listId ~= listId then
		Store.set({ listId = listId, detailLoading = true, view = "list", sidebarOpen = false })
		Store.clear("detail", "drawerItemId", "detailError")
	else
		Store.set({ view = "list", sidebarOpen = false })
	end
	Auth.setSetting(Config.settingKeys.lastListPrefix .. tostring(state.userId), listId)
	Actions.loadDetail(listId)
	changed()
end

function Actions.syncDetail()
	local state = Store.get()
	local detail = state.detail
	local listId = state.listId
	if not detail or not listId then
		return
	end
	Debounce.run("sync:" .. listId, function()
		local result = Client.changes(listId, detail.revision)
		if not alive or Store.get().listId ~= listId then
			return
		end
		if not result.ok then
			if result.error.code == "not_found" then
				Actions.loadDetail(listId, true)
			end
			return
		end
		local data = result.data
		if data.mode == "none" then
			return
		elseif data.mode == "delta" then
			applyDelta(data)
		else
			applyDetail(data)
		end
		local prefs = Store.get().prefs
		if prefs.notifyChanges and Store.get().view ~= "list" and data.othersChanged == true then
			Actions.toast("info", "Someone changed " .. detail.list.title .. ".")
		end
		markSeen(listId, data.revision)
	end, 0)
end

function Actions.refresh(silent: boolean?)
	if Store.get().phase ~= "ready" then
		return
	end
	Store.set({ refreshing = not silent })
	Actions.refreshHome(silent)
	Actions.syncDetail()
	Actions.loadNotifications()
	local view = Store.get().view
	if view == "myTasks" then
		Actions.loadMyTasks()
	elseif view == "inbox" then
		Actions.loadReports()
	end
	task.delay(0.6, function()
		Store.set({ refreshing = false })
	end)
end

local function currentDetail(): (string?, Detail?)
	local state = Store.get()
	return state.listId, state.detail
end

function Actions.openDrawer(itemId: string?)
	if itemId then
		Store.set({ drawerItemId = itemId })
		Actions.loadComments(itemId)
	else
		Store.clear("drawerItemId", "comments")
	end
	changed()
end

function Actions.addItem(text: string, fields: { [string]: any }?)
	local listId, detail = currentDetail()
	if not listId or not detail then
		return
	end
	local trimmed = string.gsub(text, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return
	end
	local maxLength = Store.limit("itemMaxLength", Config.fallbackLimits.itemMaxLength)
	if utf8.len(trimmed) and (utf8.len(trimmed) :: number) > maxLength then
		Actions.toast("error", string.format("Tasks can be up to %d characters.", maxLength))
		return
	end
	tempCounter += 1
	local tempId = "temp:" .. tempCounter
	local last = detail.items[#detail.items]
	local optimistic: Item = {
		id = tempId,
		text = trimmed,
		done = false,
		position = if last then last.position + 1 else 1,
		version = 0,
		priority = if fields and fields.priority then fields.priority else 0,
		section = if fields then fields.section else nil,
		label = if fields then fields.label else nil,
		dueAt = if fields then fields.dueAt else nil,
		link = if fields then fields.link else nil,
		pending = true,
	}
	local copy = cloneDetail(detail)
	table.insert(copy.items, optimistic)
	Store.set({ detail = copy })
	changed()
	task.spawn(function()
		local payload: { [string]: any } = { text = trimmed }
		for key, value in fields or {} do
			payload[key] = value
		end
		local result = Client.addItem(listId, payload)
		if result.ok then
			patchItem(listId, tempId, function()
				return result.data.item
			end)
			changed()
		else
			patchItem(listId, tempId, function()
				return nil
			end)
			changed()
			fail(result)
		end
	end)
	return tempId
end

function Actions.toggleDone(itemId: string)
	local listId, detail = currentDetail()
	if not listId or not detail or string.sub(itemId, 1, 5) == "temp:" then
		return
	end
	local index = findItemIndex(detail, itemId)
	if not index then
		return
	end
	local target = not detail.items[index].done
	pendingItems[itemId] = true
	patchItem(listId, itemId, function(item)
		item.done = target
		item.pending = true
		return item
	end)
	changed()
	Debounce.run("done:" .. itemId, function()
		local result = Client.updateItem(itemId, { done = target })
		pendingItems[itemId] = nil
		if result.ok then
			patchItem(listId, itemId, function()
				return result.data.item
			end)
		else
			patchItem(listId, itemId, function(item)
				item.done = not target
				item.pending = nil
				return item
			end)
			fail(result)
		end
		changed()
	end, 0)
end

function Actions.updateItem(itemId: string, fields: { [string]: any })
	local listId, detail = currentDetail()
	if not listId or not detail or string.sub(itemId, 1, 5) == "temp:" then
		return
	end
	local index = findItemIndex(detail, itemId)
	if not index then
		return
	end
	local before = table.clone(detail.items[index])
	local payload = table.clone(fields)
	if payload.text ~= nil or payload.notes ~= nil then
		payload.version = before.version
	end
	pendingItems[itemId] = true
	patchItem(listId, itemId, function(item)
		for key, value in fields do
			(item :: any)[key] = if value == Client.null then nil else value
		end
		item.pending = true
		return item
	end)
	changed()
	task.spawn(function()
		local result = Client.updateItem(itemId, payload)
		pendingItems[itemId] = nil
		if result.ok then
			patchItem(listId, itemId, function()
				return result.data.item
			end)
		elseif result.error.code == "conflict" and type(result.error.body) == "table" and result.error.body.item then
			patchItem(listId, itemId, function()
				return result.error.body.item
			end)
			Actions.toast("warning", "Someone else changed this task first. I loaded their version.")
		else
			patchItem(listId, itemId, function()
				return before
			end)
			fail(result)
		end
		changed()
	end)
end

function Actions.deleteItem(itemId: string)
	local listId, detail = currentDetail()
	if not listId or not detail then
		return
	end
	local index = findItemIndex(detail, itemId)
	if not index then
		return
	end
	local removed = detail.items[index]
	deletedItems[itemId] = true
	patchItem(listId, itemId, function()
		return nil
	end)
	if Store.get().drawerItemId == itemId then
		Store.clear("drawerItemId")
	end
	changed()
	task.spawn(function()
		local result = Client.deleteItem(itemId)
		if result.ok then
			Actions.toast("info", "Task moved to the trash.", {
				label = "Undo",
				run = function()
					Actions.restoreItem(itemId)
				end,
			})
		else
			deletedItems[itemId] = nil
			local current = Store.get().detail
			if current and Store.get().listId == listId then
				local copy = cloneDetail(current)
				table.insert(copy.items, removed)
				sortItems(copy.items)
				Store.set({ detail = copy })
				changed()
			end
			fail(result)
		end
	end)
end

function Actions.restoreItem(itemId: string)
	task.spawn(function()
		local result = Client.restoreItem(itemId)
		deletedItems[itemId] = nil
		if result.ok then
			Actions.toast("success", "Task restored.")
			local listId = Store.get().listId
			if listId then
				Actions.loadDetail(listId, true)
			end
			if Store.get().view == "trash" then
				Actions.loadTrash()
			end
		else
			fail(result)
		end
	end)
end

function Actions.moveItem(itemId: string, aboveId: string?, belowId: string?, section: string?)
	local listId, detail = currentDetail()
	if not listId or not detail then
		return
	end
	local copy = cloneDetail(detail)
	local index = findItemIndex(copy, itemId)
	if not index then
		return
	end
	local item = table.clone(copy.items[index])
	local function positionOf(id: string?): number?
		if not id then
			return nil
		end
		local i = findItemIndex(copy, id)
		return if i then copy.items[i].position else nil
	end
	local above, below = positionOf(aboveId), positionOf(belowId)
	if above and below then
		item.position = (above + below) / 2
	elseif above then
		item.position = above + 1
	elseif below then
		item.position = below - 1
	end
	if section ~= nil then
		item.section = if section == "" then nil else section
	end
	item.pending = true
	pendingItems[itemId] = true
	copy.items[index] = item
	sortItems(copy.items)
	Store.set({ detail = copy })
	changed()
	task.spawn(function()
		local result = Client.moveItem(itemId, aboveId, belowId, section)
		pendingItems[itemId] = nil
		if result.ok then
			patchItem(listId, itemId, function()
				return result.data.item
			end)
			changed()
		else
			fail(result)
			Actions.loadDetail(listId, true)
		end
	end)
end

function Actions.undo()
	local listId = Store.get().listId
	if not listId then
		Actions.toast("info", "Open a list first.")
		return
	end
	Debounce.run("undo", function()
		local result = Client.undo(listId)
		if result.ok then
			applyDetail(result.data)
			Actions.toast("success", "Undid your last change.")
		else
			fail(result)
		end
	end)
end

local function afterListResult(result: Result, message: string?)
	if result.ok and result.data.list then
		Store.set({ listId = result.data.list.id, view = "list" })
		Store.clear("detail", "drawerItemId")
		applyDetail(result.data)
		Auth.setSetting(Config.settingKeys.lastListPrefix .. tostring(Store.get().userId), result.data.list.id)
		Actions.refreshHome(true)
		Actions.loadMe()
		if message then
			Actions.toast("success", message)
		end
	else
		fail(result)
	end
end

function Actions.createList(title: string?, template: string?)
	Debounce.run("createList", function()
		afterListResult(Client.createList(title, template), "List created.")
	end)
end

function Actions.joinByCode(code: string)
	Debounce.run("joinByCode", function()
		afterListResult(Client.openByCode(code), "List opened.")
	end)
end

function Actions.duplicateList(listId: string)
	Debounce.run("duplicate", function()
		afterListResult(Client.duplicateList(listId), "Copy made. It is yours now.")
	end)
end

function Actions.importList(format: string, content: string)
	Debounce.run("import", function()
		afterListResult(Client.importList(format, content), "List imported.")
	end)
end

function Actions.updateList(listId: string, patch: { [string]: any }, message: string?)
	Debounce.run("updateList:" .. listId, function()
		local result = Client.updateList(listId, patch)
		if result.ok then
			if Store.get().listId == listId then
				applyDetail(result.data)
			end
			Actions.refreshHome(true)
			if message then
				Actions.toast("success", message)
			end
		else
			fail(result)
		end
	end)
end

function Actions.renameList(listId: string, title: string)
	Actions.updateList(listId, { title = title }, "List renamed.")
end

function Actions.archiveList(listId: string, archived: boolean)
	Actions.updateList(listId, { archived = archived }, if archived then "List archived." else "List unarchived.")
end

function Actions.pinToGame(listId: string, pinned: boolean)
	Actions.updateList(
		listId,
		{ placeId = if pinned then game.PlaceId else Client.null },
		if pinned then "This list now opens with this game." else "Unpinned from this game."
	)
end

function Actions.deleteList(listId: string)
	Debounce.run("deleteList", function()
		local result = Client.deleteList(listId)
		if result.ok then
			if Store.get().listId == listId then
				Store.set({ view = "empty" })
				Store.clear("listId", "detail", "drawerItemId")
			end
			Actions.refreshHome(true)
			Actions.loadMe()
			Actions.toast("info", "List moved to the trash for 30 days.", {
				label = "Undo",
				run = function()
					Actions.restoreList(listId)
				end,
			})
		else
			fail(result)
		end
	end)
end

function Actions.restoreList(listId: string)
	Debounce.run("restoreList", function()
		afterListResult(Client.restoreList(listId), "List restored.")
		if Store.get().view == "trash" then
			Actions.loadTrash()
		end
	end)
end

function Actions.forgetList(listId: string)
	Debounce.run("forget", function()
		local result = Client.forgetVisit(listId)
		if result.ok then
			if Store.get().listId == listId then
				Store.set({ view = "empty" })
				Store.clear("listId", "detail")
			end
			Actions.refreshHome(true)
		else
			fail(result)
		end
	end)
end

function Actions.rotateCode(listId: string)
	Debounce.run("rotate", function()
		local result = Client.rotateCode(listId)
		if result.ok then
			applyDetail(result.data)
			Actions.toast("success", "New code made. Everyone who joined with the old code lost access.")
		else
			fail(result)
		end
	end)
end

function Actions.exportList(listId: string, format: string, done: (string) -> ())
	Debounce.run("export", function()
		local stamps = {}
		local detail = Store.get().detail
		if detail and detail.list.id == listId then
			for _, item in detail.items do
				if item.dueAt then
					table.insert(stamps, item.dueAt)
				end
			end
		end
		local ok, tz = pcall(Time.offsetRanges, stamps)
		local result = Client.exportList(listId, format, if ok then tz else nil)
		if result.ok then
			done(result.data.url)
		else
			fail(result)
		end
	end)
end

local function reloadPeople(listId: string)
	if Store.get().listId == listId then
		Actions.loadDetail(listId, true)
	end
end

function Actions.addPerson(listId: string, username: string, role: string, assignOnly: boolean)
	Debounce.run("addPerson", function()
		local cleaned = string.gsub(username, "^@", "")
		cleaned = string.gsub(cleaned, "%s", "")
		local userId = tonumber(cleaned)
		if not userId then
			local lookup = Client.userByName(cleaned)
			if not lookup.ok then
				fail(lookup)
				return
			end
			local user = lookup.data.users[1]
			rememberPeople(lookup.data.users)
			userId = user.userId
		end
		local id = userId :: number
		local result = if assignOnly then Client.assign(listId, id) else Client.putMember(listId, id, role)
		if result.ok then
			Actions.toast(
				"success",
				if assignOnly
					then "Assigned " .. Store.personName(id) .. "."
					else "Added " .. Store.personName(id) .. "."
			)
			reloadPeople(listId)
		else
			fail(result)
		end
	end)
end

function Actions.setRole(listId: string, userId: number, role: string)
	Debounce.run("role:" .. userId, function()
		local result = Client.putMember(listId, userId, role)
		if result.ok then
			reloadPeople(listId)
		else
			fail(result)
		end
	end)
end

function Actions.removePerson(listId: string, userId: number, fromAssignments: boolean)
	Debounce.run("remove:" .. userId, function()
		local result = if fromAssignments then Client.unassign(listId, userId) else Client.removeMember(listId, userId)
		if result.ok then
			Actions.toast("info", "Removed " .. Store.personName(userId) .. ".")
			if userId == Store.get().userId then
				Store.set({ view = "empty" })
				Store.clear("listId", "detail")
				Actions.refreshHome(true)
			else
				reloadPeople(listId)
			end
		else
			fail(result)
		end
	end)
end

function Actions.loadComments(itemId: string)
	if string.sub(itemId, 1, 5) == "temp:" then
		return
	end
	Store.set({ comments = { itemId = itemId, list = {}, loading = true } })
	task.spawn(function()
		local result = Client.comments(itemId)
		if Store.get().drawerItemId ~= itemId then
			return
		end
		if result.ok then
			local ids = {}
			for _, comment in result.data.comments do
				table.insert(ids, comment.authorId)
			end
			Actions.resolveNames(ids)
			Store.set({ comments = { itemId = itemId, list = result.data.comments, loading = false } })
		else
			Store.set({ comments = { itemId = itemId, list = {}, loading = false } })
		end
		changed()
	end)
end

function Actions.addComment(itemId: string, body: string)
	Debounce.run("comment", function()
		local result = Client.addComment(itemId, body)
		if result.ok then
			local comments = Store.get().comments
			if comments and comments.itemId == itemId then
				local list = table.clone(comments.list)
				table.insert(list, result.data.comment)
				Store.set({ comments = { itemId = itemId, list = list, loading = false } })
			end
			local listId = Store.get().listId
			if listId then
				patchItem(listId, itemId, function(item)
					item.commentCount = (item.commentCount or 0) + 1
					return item
				end)
			end
			changed()
		else
			fail(result)
		end
	end)
end

function Actions.deleteComment(itemId: string, commentId: string)
	task.spawn(function()
		local result = Client.deleteComment(commentId)
		if result.ok then
			Actions.loadComments(itemId)
		else
			fail(result)
		end
	end)
end

function Actions.loadMyTasks()
	Debounce.run("myTasks", function()
		local result = Client.myTasks()
		if result.ok then
			Store.set({ myTasks = result.data.items })
			changed()
		else
			fail(result)
		end
	end, 0)
end

function Actions.search(query: string, filters: { [string]: string }?)
	Store.set({ searchQuery = query })
	if #query < 2 and not filters then
		Store.set({ searchResults = {} })
		changed()
		return
	end
	Debounce.run("search", function()
		local result = Client.search(query, filters)
		if result.ok and Store.get().searchQuery == query then
			Store.set({ searchResults = result.data.items })
			changed()
		end
	end, 0)
end

function Actions.loadTrash()
	Debounce.run("trash", function()
		local result = Client.trash()
		if result.ok then
			Store.set({ trash = result.data })
			changed()
		else
			fail(result)
		end
	end, 0)
end

function Actions.trashSelected(items: { string }, lists: { string }, restore: boolean, notifications: { number }?)
	Debounce.run("trashBatch", function()
		local result = if restore
			then Client.restoreTrash(items, lists, notifications)
			else Client.deleteTrash(items, lists, notifications)
		if result.ok then
			local done = if restore then result.data.restored else result.data.deleted
			local skipped = #(result.data.skipped or {})
			Actions.toast(
				"success",
				string.format(
					"%s %d %s.%s",
					if restore then "Restored" else "Deleted forever",
					done,
					if done == 1 then "item" else "items",
					if skipped > 0 then string.format(" %d could not be changed.", skipped) else ""
				)
			)
			Actions.loadTrash()
			Actions.refreshHome(true)
			if notifications and #notifications > 0 then
				Actions.loadNotifications()
			end
			local listId = Store.get().listId
			if listId then
				Actions.loadDetail(listId, true)
			end
		else
			fail(result)
		end
	end)
end

function Actions.emptyTrash()
	Debounce.run("trashBatch", function()
		local result = Client.emptyTrash()
		if result.ok then
			Actions.toast("success", string.format("Trash emptied. %d items deleted forever.", result.data.deleted))
			Actions.loadTrash()
		else
			fail(result)
		end
	end)
end

function Actions.loadNotifications()
	Debounce.run("notifications", function()
		local result = Client.notifications()
		if result.ok then
			Store.set({ notifications = { list = result.data.notifications, unread = result.data.unread } })
			local ids = {}
			for _, n in result.data.notifications do
				table.insert(ids, n.actorId)
			end
			Actions.resolveNames(ids)
			changed()
		end
	end, 0)
end

function Actions.describeNotification(n: any): string
	local who = Store.shortName(n.actorId)
	local text = if n.data and n.data.text then n.data.text else ""
	if n.kind == "task.assigned" then
		return who .. " gave you a task: " .. text
	elseif n.kind == "comment.mention" then
		return who .. " mentioned you on " .. text
	elseif n.kind == "list.shared" then
		return who .. " added you to " .. (n.listTitle or "a list")
	elseif n.kind == "gamekey.revoked" then
		return "One player sent far more reports than your game allows, so someone outside your game may have this key. "
			.. "We turned it off to keep your list safe. Make a new key, update your secret, then delete the old one."
	end
	return who .. " changed " .. (n.listTitle or "a list")
end

function Actions.dueSoon(state: Store.State): { any }
	local now = Time.nowMs()
	local out = {}
	for _, item in state.myTasks or {} do
		if item.dueAt and not item.done and item.dueAt - now < 86400000 then
			table.insert(out, item)
		end
	end
	table.sort(out, function(x, y)
		return x.dueAt < y.dueAt
	end)
	return out
end

function Actions.dueKey(item: any): string
	return "d:" .. item.id .. ":" .. tostring(item.dueAt)
end

function Actions.notificationTabOf(kind: string): string
	if kind == "gamekey.revoked" then
		return "fix"
	elseif kind == "list.shared" then
		return "shared"
	end
	return "mentions"
end

function Actions.notificationCounts(state: Store.State): { [string]: number }
	local counts = { fix = 0, due = 0, mentions = 0, shared = 0, updates = 0 }
	if state.updateVersion and state.seenUpdate ~= state.updateVersion then
		counts.updates = 1
	end
	for _, n in if state.notifications then state.notifications.list else {} do
		if not n.read then
			local tab = Actions.notificationTabOf(n.kind)
			counts[tab] += 1
		end
	end
	for _, item in Actions.dueSoon(state) do
		if not state.seenDue[Actions.dueKey(item)] then
			counts.due += 1
		end
	end
	return counts
end

function Actions.notificationCount(state: Store.State): number
	local total = 0
	for _, count in Actions.notificationCounts(state) do
		total += count
	end
	return total
end

function Actions.setNotificationTab(tab: string)
	Store.set({ notificationTab = tab, notificationSelected = {} })
	changed()
end

function Actions.selectNotifications(keys: { string }, selected: boolean)
	local picked = table.clone(Store.get().notificationSelected)
	for _, key in keys do
		picked[key] = if selected then true else nil
	end
	Store.set({ notificationSelected = picked })
	changed()
end

local function saveSeenDue(seen: { [string]: boolean })
	local keep = {}
	for _, item in Actions.dueSoon(Store.get()) do
		local key = Actions.dueKey(item)
		if seen[key] then
			keep[key] = true
		end
	end
	Store.set({ seenDue = keep })
	Auth.setSetting("seenDue:" .. tostring(Store.get().userId), keep)
end

function Actions.markNotificationsRead(keys: { string })
	if Debounce.isBusy("notificationRead") then
		return
	end
	local state = Store.get()
	local ids = {}
	local seen = table.clone(state.seenDue)
	for _, key in keys do
		local id = tonumber(string.match(key, "^n:(%d+)$"))
		if id then
			table.insert(ids, id)
		elseif string.sub(key, 1, 2) == "d:" then
			seen[key] = true
		elseif string.sub(key, 1, 2) == "u:" then
			local version = string.sub(key, 3)
			Store.set({ seenUpdate = version })
			Auth.setSetting("seenUpdate:" .. tostring(state.userId), version)
		end
	end
	saveSeenDue(seen)
	local picked = table.clone(state.notificationSelected)
	for _, key in keys do
		picked[key] = nil
	end
	Store.set({ notificationSelected = picked })
	if #ids > 0 and state.notifications then
		local marked = {}
		for _, id in ids do
			marked[id] = true
		end
		local list = {}
		local unread = 0
		for _, n in state.notifications.list do
			local copy = table.clone(n)
			if marked[copy.id] then
				copy.read = true
			end
			if not copy.read then
				unread += 1
			end
			table.insert(list, copy)
		end
		Store.set({ notifications = { list = list, unread = unread } })
		Debounce.run("notificationRead", function()
			Client.readNotifications(nil, ids)
		end, 0)
	end
	changed()
end

function Actions.deleteNotifications(keys: { string })
	if Debounce.isBusy("notificationTrash") then
		return
	end
	local state = Store.get()
	local gone = {}
	local ids = {}
	for _, key in keys do
		local id = tonumber(string.match(key, "^n:(%d+)$"))
		if id then
			gone[id] = true
			table.insert(ids, id)
		end
	end
	if #ids == 0 or not state.notifications then
		return
	end
	local list = {}
	local unread = 0
	for _, n in state.notifications.list do
		if gone[n.id] and not (n.kind == "gamekey.revoked" and not n.read) then
			continue
		end
		if not n.read then
			unread += 1
		end
		table.insert(list, n)
	end
	local picked = table.clone(state.notificationSelected)
	for _, key in keys do
		picked[key] = nil
	end
	Store.set({ notifications = { list = list, unread = unread }, notificationSelected = picked })
	changed()
	Debounce.run("notificationTrash", function()
		local result = Client.deleteNotifications(ids)
		if not result.ok then
			fail(result)
			Actions.loadNotifications()
			return
		end
		local count = result.data.deleted or #ids
		Actions.toast(
			"info",
			string.format("Moved %d %s to the trash.", count, if count == 1 then "notification" else "notifications"),
			{
				label = "Undo",
				run = function()
					Debounce.run("notificationTrash", function()
						Client.restoreTrash({}, {}, ids)
						Actions.loadNotifications()
						if Store.get().view == "trash" then
							Actions.loadTrash()
						end
					end)
				end,
			}
		)
	end, 0)
end

function Actions.loadSeenDue()
	local userId = tostring(Store.get().userId)
	local saved = Auth.getSetting("seenDue:" .. userId)
	local update = Auth.getSetting("seenUpdate:" .. userId)
	Store.set({
		seenDue = if type(saved) == "table" then saved else {},
		seenUpdate = if type(update) == "string" then update else nil,
	})
end

function Actions.notificationTitle(n: any): string
	if n.kind == "task.assigned" then
		return "New task for you"
	elseif n.kind == "comment.mention" then
		return "You were mentioned"
	elseif n.kind == "list.shared" then
		return "A list was shared with you"
	elseif n.kind == "gamekey.revoked" then
		return "Game key " .. (if n.data and n.data.label then n.data.label else "") .. " was turned off"
	end
	return "Something changed"
end

function Actions.openNotification(n: any, key: string?)
	if key then
		Actions.markNotificationsRead({ key })
	end
	Actions.openList(n.listId)
	if n.kind == "gamekey.revoked" then
		task.delay(0.5, function()
			Actions.showView("inbox")
		end)
	elseif n.itemId then
		task.delay(0.5, function()
			Actions.openDrawer(n.itemId)
		end)
	end
end

function Actions.readNotifications()
	local notifications = Store.get().notifications
	if not notifications or notifications.unread == 0 then
		return
	end
	local list = {}
	for _, n in notifications.list do
		local copy = table.clone(n)
		copy.read = true
		table.insert(list, copy)
	end
	Store.set({ notifications = { list = list, unread = 0 } })
	changed()
	task.spawn(function()
		Client.readNotifications(nil, nil)
	end)
end

function Actions.loadActivity()
	local listId = Store.get().listId
	if not listId then
		return
	end
	Debounce.run("activity", function()
		local result = Client.activity(listId)
		if result.ok then
			local ids = {}
			for _, e in result.data.events do
				table.insert(ids, e.actorId)
			end
			Actions.resolveNames(ids)
			Store.set({ activity = result.data.events })
		else
			Store.set({ activity = {} })
			fail(result)
		end
		changed()
	end, 0)
end

function Actions.loadReports()
	local listId = Store.get().listId
	if not listId then
		return
	end
	Debounce.run("reports", function()
		local result = Client.reports(listId)
		Store.set({ reports = if result.ok then result.data.reports else {} })
		local detail = Store.get().detail
		if detail and (detail.role == "owner" or detail.role == "admin") then
			local keys = Client.gameKeys(listId)
			Store.set({ gameKeys = if keys.ok then keys.data.keys else {} })
		end
		changed()
	end, 0)
end

function Actions.approveReport(reportId: string)
	Debounce.run("report:" .. reportId, function()
		local result = Client.approveReport(reportId)
		if result.ok then
			Actions.toast("success", "Report added as a task in the Inbox section.")
			Actions.loadReports()
			Actions.syncDetail()
		else
			fail(result)
		end
	end)
end

function Actions.dismissReport(reportId: string)
	Debounce.run("report:" .. reportId, function()
		local result = Client.dismissReport(reportId)
		if result.ok then
			Actions.loadReports()
		else
			fail(result)
		end
	end)
end

function Actions.createGameKey(label: string)
	local listId = Store.get().listId
	if not listId then
		return
	end
	Debounce.run("gameKey", function()
		local result = Client.createGameKey(listId, label)
		if result.ok then
			Store.set({ newGameKey = result.data.key })
			Actions.loadReports()
		else
			fail(result)
		end
	end)
end

function Actions.deleteGameKey(keyId: string)
	local listId = Store.get().listId
	if not listId then
		return
	end
	Debounce.run("gameKey", function()
		local result = Client.deleteGameKey(listId, keyId)
		if result.ok then
			Store.clear("newGameKey")
			Actions.loadReports()
		else
			fail(result)
		end
	end)
end

function Actions.loadSessions()
	Debounce.run("sessions", function()
		local result = Client.sessions()
		if result.ok then
			Store.set({ sessions = result.data.sessions })
			changed()
		end
	end, 0)
end

function Actions.signOutDevice(sessionId: string)
	Debounce.run("device:" .. sessionId, function()
		local result = Client.signOutDevice(sessionId)
		if result.ok then
			Actions.toast("info", "That device is signed out.")
			Actions.loadSessions()
		else
			fail(result)
		end
	end)
end

function Actions.acceptUploadWarning()
	Actions.setPreference("uploadWarningAccepted", true)
end

export type Attachment = { name: string, size: number, contents: string }

function Actions.submit(
	kind: string,
	fields: { [string]: any },
	attachment: Attachment?,
	progress: (string) -> (),
	done: (boolean) -> ()
)
	Debounce.run("submit:" .. kind, function()
		local payload = table.clone(fields)
		payload.kind = kind
		if attachment then
			progress("Uploading 0%")
			local started = Client.startUpload(attachment.name, attachment.size)
			if not started.ok then
				fail(started)
				done(false)
				return
			end
			local uploadId = started.data.uploadId
			local chunk = started.data.chunkBytes
			for part = 0, started.data.parts - 1 do
				local from = part * chunk + 1
				local data = Base64.encode(attachment.contents, from, from + chunk - 1)
				local sent = Client.uploadPart(uploadId, part, data)
				if not sent.ok then
					Client.cancelUpload(uploadId)
					fail(sent)
					done(false)
					return
				end
				progress(string.format("Uploading %d%%", math.floor((part + 1) / started.data.parts * 100)))
			end
			payload.uploadId = uploadId
			progress("Checking the file")
		else
			progress("Sending")
		end
		local result = Client.submit(payload)
		if result.ok then
			Actions.toast("success", result.data.message or "Sent. Thanks!")
			done(true)
		else
			fail(result)
			done(false)
		end
		Actions.loadMe()
	end, 0)
end

function Actions.shutdown()
	alive = false
	loginAttempt += 1
	local listId = Store.get().listId
	if listId and Client.hasSession() then
		task.spawn(Client.clearPresence, listId)
	end
end

return Actions
