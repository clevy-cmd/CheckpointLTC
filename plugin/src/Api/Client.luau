--!strict

local HttpService = game:GetService("HttpService")

local Auth = require(script.Parent.Auth)
local Config = require(script.Parent.Parent.Config)
local Http = require(script.Parent.Http)

export type Result = Http.Result

local Client = {}

Client.null = Http.null

local session = { userId = 0, key = nil :: string? }

function Client.setSession(userId: number, key: string?)
	session.userId = userId
	session.key = key
end

function Client.hasSession(): boolean
	return session.userId > 0 and session.key ~= nil
end

local function authed(method: string, path: string, payload: any?, options: Http.Options?): Result
	local key = session.key
	if not key then
		return { ok = false, error = { code = "unauthorized", message = "Not signed in yet.", status = 401 } }
	end
	return Http.request(method, path, Auth.headers(session.userId, key), payload, options)
end

local function open(method: string, path: string, payload: any?): Result
	return Http.request(method, path, {}, payload)
end

local function seg(value: string | number): string
	return HttpService:UrlEncode(tostring(value))
end

local function list(listId: string): string
	return "/v1/lists/" .. seg(listId)
end

function Client.meta(): Result
	return open("GET", "/v1/meta")
end
function Client.loginStart(userId: number): Result
	return open("POST", "/v1/login/start", { userId = userId })
end
function Client.loginPoll(code: string, pollToken: string): Result
	return open("POST", "/v1/login/poll", { code = code, pollToken = pollToken, label = Auth.deviceLabel() })
end
function Client.testRegister(userId: number): Result
	return open("POST", "/v1/register", { userId = userId, label = Auth.deviceLabel() })
end

function Client.me(): Result
	return authed("GET", "/v1/me")
end
function Client.preferences(): Result
	return authed("GET", "/v1/preferences")
end
function Client.savePreferences(patch: { [string]: any }): Result
	return authed("PATCH", "/v1/preferences", patch)
end
function Client.sessions(): Result
	return authed("GET", "/v1/sessions")
end
function Client.signOutHere(): Result
	return authed("DELETE", "/v1/session")
end
function Client.signOutDevice(sessionId: string): Result
	return authed("DELETE", "/v1/sessions/" .. seg(sessionId))
end
function Client.usersByIds(ids: { number }): Result
	local parts = {}
	for _, id in ids do
		table.insert(parts, tostring(id))
	end
	return authed("GET", "/v1/users?ids=" .. table.concat(parts, ","))
end
function Client.userByName(username: string): Result
	return authed("GET", "/v1/users?username=" .. seg(username))
end
function Client.notifications(): Result
	return authed("GET", "/v1/notifications")
end
function Client.readNotifications(upTo: number?, ids: { number }?): Result
	return authed("POST", "/v1/notifications/read", { upTo = upTo, ids = ids })
end
function Client.deleteNotifications(ids: { number }): Result
	return authed("POST", "/v1/notifications/delete", { ids = ids })
end
function Client.myTasks(): Result
	return authed("GET", "/v1/tasks/mine")
end
function Client.search(query: string, filters: { [string]: string }?): Result
	local params = { "q=" .. seg(query) }
	for key, value in filters or {} do
		table.insert(params, key .. "=" .. seg(value))
	end
	return authed("GET", "/v1/search?" .. table.concat(params, "&"))
end
function Client.trash(): Result
	return authed("GET", "/v1/trash")
end
function Client.restoreTrash(items: { string }, lists: { string }, notifications: { number }?): Result
	return authed("POST", "/v1/trash/restore", { items = items, lists = lists, notifications = notifications })
end
function Client.deleteTrash(items: { string }, lists: { string }, notifications: { number }?): Result
	return authed("POST", "/v1/trash/delete", { items = items, lists = lists, notifications = notifications })
end
function Client.emptyTrash(): Result
	return authed("POST", "/v1/trash/empty", {})
end
function Client.templates(): Result
	return authed("GET", "/v1/templates")
end

function Client.home(): Result
	return authed("GET", "/v1/lists")
end
function Client.createList(title: string?, template: string?): Result
	return authed("POST", "/v1/lists", { title = title, template = template })
end
function Client.openByCode(code: string): Result
	return authed("POST", "/v1/lists/open", { code = code })
end
function Client.importList(format: string, content: string, title: string?): Result
	return authed(
		"POST",
		"/v1/lists/import",
		{ format = format, content = content, title = title },
		{ timeout = Config.network.longTimeoutSeconds }
	)
end
function Client.getList(listId: string): Result
	return authed("GET", list(listId))
end
function Client.changes(listId: string, since: number): Result
	return authed("GET", list(listId) .. "/changes?since=" .. tostring(since))
end
function Client.updateList(listId: string, patch: { [string]: any }): Result
	return authed("PATCH", list(listId), patch)
end
function Client.deleteList(listId: string): Result
	return authed("DELETE", list(listId))
end
function Client.restoreList(listId: string): Result
	return authed("POST", list(listId) .. "/restore")
end
function Client.duplicateList(listId: string): Result
	return authed("POST", list(listId) .. "/duplicate", {})
end
function Client.rotateCode(listId: string): Result
	return authed("POST", list(listId) .. "/code")
end
function Client.forgetVisit(listId: string): Result
	return authed("DELETE", list(listId) .. "/visit")
end
function Client.markSeen(listId: string, revision: number): Result
	return authed("POST", list(listId) .. "/seen", { revision = revision })
end
function Client.putPresence(listId: string, itemId: string?, placeId: number?): Result
	return authed("PUT", list(listId) .. "/presence", { itemId = itemId, placeId = placeId })
end
function Client.clearPresence(listId: string): Result
	return authed("DELETE", list(listId) .. "/presence")
end
function Client.exportList(listId: string, format: string, tz: { { number } }?): Result
	return authed("POST", list(listId) .. "/export", { format = format, tz = tz })
end
function Client.undo(listId: string): Result
	return authed("POST", list(listId) .. "/undo")
end
function Client.activity(listId: string): Result
	return authed("GET", list(listId) .. "/activity")
end
function Client.gameKeys(listId: string): Result
	return authed("GET", list(listId) .. "/game-keys")
end
function Client.createGameKey(listId: string, label: string): Result
	return authed("POST", list(listId) .. "/game-keys", { label = label })
end
function Client.deleteGameKey(listId: string, keyId: string): Result
	return authed("DELETE", list(listId) .. "/game-keys/" .. seg(keyId))
end
function Client.reports(listId: string): Result
	return authed("GET", list(listId) .. "/reports")
end
function Client.approveReport(reportId: string): Result
	return authed("POST", "/v1/reports/" .. seg(reportId) .. "/approve")
end
function Client.dismissReport(reportId: string): Result
	return authed("POST", "/v1/reports/" .. seg(reportId) .. "/dismiss")
end

function Client.addItem(listId: string, fields: { [string]: any }): Result
	return authed("POST", list(listId) .. "/items", fields)
end
function Client.updateItem(itemId: string, fields: { [string]: any }): Result
	return authed("PATCH", "/v1/items/" .. seg(itemId), fields)
end
function Client.moveItem(itemId: string, aboveId: string?, belowId: string?, section: string?): Result
	local body: { [string]: any } = { aboveId = aboveId, belowId = belowId }
	if section ~= nil then
		body.section = if section == "" then Http.null else section
	end
	return authed("POST", "/v1/items/" .. seg(itemId) .. "/move", body)
end
function Client.deleteItem(itemId: string): Result
	return authed("DELETE", "/v1/items/" .. seg(itemId))
end
function Client.restoreItem(itemId: string): Result
	return authed("POST", "/v1/items/" .. seg(itemId) .. "/restore")
end
function Client.comments(itemId: string): Result
	return authed("GET", "/v1/items/" .. seg(itemId) .. "/comments")
end
function Client.addComment(itemId: string, body: string): Result
	return authed("POST", "/v1/items/" .. seg(itemId) .. "/comments", { body = body })
end
function Client.deleteComment(commentId: string): Result
	return authed("DELETE", "/v1/comments/" .. seg(commentId))
end

function Client.putMember(listId: string, userId: number, role: string): Result
	return authed("PUT", list(listId) .. "/members/" .. seg(userId), { role = role })
end
function Client.removeMember(listId: string, userId: number): Result
	return authed("DELETE", list(listId) .. "/members/" .. seg(userId))
end
function Client.assign(listId: string, userId: number): Result
	return authed("PUT", list(listId) .. "/assignments/" .. seg(userId))
end
function Client.unassign(listId: string, userId: number): Result
	return authed("DELETE", list(listId) .. "/assignments/" .. seg(userId))
end

function Client.startUpload(name: string, size: number): Result
	return authed("POST", "/v1/uploads", { name = name, size = size })
end
function Client.uploadPart(uploadId: string, part: number, data: string): Result
	return authed(
		"PUT",
		"/v1/uploads/" .. seg(uploadId) .. "/parts/" .. tostring(part),
		{ data = data },
		{ timeout = 60 }
	)
end
function Client.cancelUpload(uploadId: string): Result
	return authed("DELETE", "/v1/uploads/" .. seg(uploadId))
end
function Client.submit(fields: { [string]: any }): Result
	return authed("POST", "/v1/submissions", fields, { timeout = Config.network.longTimeoutSeconds, attempts = 1 })
end

return Client
