--!strict

local Signal = require(script.Parent.Parent.Core.Signal)

export type Role = "owner" | "admin" | "editor" | "viewer"
export type Phase = "booting" | "signedOut" | "login" | "ready"
export type View =
	"list"
	| "myTasks"
	| "search"
	| "trash"
	| "settings"
	| "people"
	| "inbox"
	| "todo"
	| "activity"
	| "empty"
export type SettingsTab = "preferences" | "hints" | "plan" | "support" | "devices"

export type ListSummary = {
	id: string,
	title: string,
	ownerId: number,
	role: Role,
	itemCount: number,
	doneCount: number,
	revision: number,
	seenRevision: number?,
	unseen: number,
	archived: boolean,
	placeId: number?,
	updatedAt: number,
	shareCode: string?,
}

export type TaskLink = { kind: string, path: string, guid: string?, line: number?, placeId: number? }

export type Item = {
	id: string,
	listId: string?,
	listTitle: string?,
	text: string,
	done: boolean,
	position: number,
	version: number,
	priority: number,
	dueAt: number?,
	label: string?,
	section: string?,
	notes: string?,
	assigneeId: number?,
	link: TaskLink?,
	commentCount: number?,
	updatedBy: number?,
	updatedAt: number?,
	pending: boolean?,
}

export type Person = { userId: number, name: string?, displayName: string?, role: string? }

export type Detail = {
	revision: number,
	role: Role,
	assigned: boolean,
	list: {
		id: string,
		title: string,
		ownerId: number,
		owner: Person?,
		shareCode: string?,
		archived: boolean,
		placeId: number?,
		itemCount: number,
		doneCount: number,
		updatedAt: number,
	},
	items: { Item },
	members: { Person },
	assignments: { Person },
	people: { Person },
	presence: { Person & { itemId: string?, placeId: number? } },
}

export type State = {
	phase: Phase,
	userId: number,
	environment: string,
	login: { code: string, url: string }?,
	needsPurchase: boolean,
	banned: boolean?,
	paid: boolean,
	storeUrl: string?,
	busyMessage: string?,
	me: any?,
	prefs: { [string]: any },
	names: { [number]: Person },
	home: { mine: { ListSummary }, assigned: { ListSummary }, opened: { ListSummary } }?,
	homeError: string?,
	view: View,
	settingsTab: SettingsTab,
	listId: string?,
	detail: Detail?,
	detailLoading: boolean,
	detailError: string?,
	drawerItemId: string?,
	comments: { itemId: string, list: { any }, loading: boolean }?,
	myTasks: { Item }?,
	searchQuery: string,
	searchResults: { Item }?,
	trash: { lists: { any }, items: { any } }?,
	notifications: { list: { any }, unread: number }?,
	activity: { any }?,
	reports: { any }?,
	gameKeys: { any }?,
	newGameKey: string?,
	sessions: { any }?,
	todoResults: { any }?,
	labelFilter: string?,
	refreshing: boolean,
	sidebarOpen: boolean,
	updateVersion: string?,
	lastChangeAt: number,
}

local defaultPrefs = {
	refreshSeconds = 30,
	compact = false,
	hideCompleted = false,
	sortOrder = "manual",
	confirmDelete = true,
	notifyAssigned = true,
	notifyMentions = true,
	notifyChanges = true,
	accent = "brand",
	defaultRole = "editor",
	showHints = true,
	showTooltips = true,
	showWhatsNew = true,
	tourDone = false,
	seenVersion = "",
	uploadWarningAccepted = false,
	view = "list",
	textSizing = "fixed",
	titleSize = 1,
	bodySize = 1,
	smallSize = 1,
}

local Store = {}

Store.defaultPrefs = defaultPrefs

local state: State = {
	phase = "booting",
	userId = 0,
	environment = "production",
	login = nil,
	needsPurchase = false,
	paid = false,
	storeUrl = nil,
	busyMessage = nil,
	me = nil,
	prefs = table.clone(defaultPrefs),
	names = {},
	home = nil,
	homeError = nil,
	view = "empty",
	settingsTab = "preferences",
	listId = nil,
	detail = nil,
	detailLoading = false,
	detailError = nil,
	drawerItemId = nil,
	comments = nil,
	myTasks = nil,
	searchQuery = "",
	searchResults = nil,
	trash = nil,
	notifications = nil,
	activity = nil,
	reports = nil,
	gameKeys = nil,
	newGameKey = nil,
	sessions = nil,
	todoResults = nil,
	labelFilter = nil,
	refreshing = false,
	sidebarOpen = false,
	updateVersion = nil,
	lastChangeAt = 0,
}

Store.changed = Signal.new() :: Signal.Signal<State>

function Store.get(): State
	return state
end

function Store.set(patch: { [string]: any })
	local nextState = table.clone(state) :: any
	for key, value in patch do
		nextState[key] = value
	end
	state = nextState
	Store.changed:fire(state)
end

function Store.clear(...: string)
	local nextState = table.clone(state) :: any
	for _, key in { ... } do
		nextState[key] = nil
	end
	state = nextState
	Store.changed:fire(state)
end

function Store.limit(name: string, fallback: any): any
	local me = state.me
	if me and type(me.limits) == "table" and me.limits[name] ~= nil then
		return me.limits[name]
	end
	return fallback
end

function Store.personName(userId: number?): string
	if not userId then
		return "Nobody"
	end
	local person = state.names[userId]
	if person and person.displayName and person.name and person.displayName ~= person.name then
		return person.displayName .. " (@" .. person.name .. ")"
	elseif person and person.name then
		return "@" .. person.name
	end
	return "User " .. tostring(userId)
end

function Store.shortName(userId: number?): string
	if not userId then
		return "Nobody"
	end
	local person = state.names[userId]
	if person and person.displayName then
		return person.displayName
	elseif person and person.name then
		return person.name
	end
	return tostring(userId)
end

return Store
