--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Config = require(script.Parent.Parent.Config)

local ReportsModule = {}

local moduleSource = [=[
-- CheckpointLTC in game reports, by LTCLevTec

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local API_URL = "{{API_URL}}/v1/game/reports"
local SECRET_NAME = "CheckpointLTC"
local MAX_LENGTH = 500

-- ONE REPORT PER PLAYER PER HOUR, ACROSS EVERY SERVER OF YOUR GAME.
-- THIS LIMIT IS REQUIRED. DO NOT CHANGE IT, DO NOT REMOVE IT.
-- THE CHECKPOINTLTC SERVER CHECKS IT TOO. IF ONE PLAYER SENDS WAY MORE THAN THIS,
-- THE SERVER TREATS YOUR GAME KEY AS STOLEN, TURNS IT OFF, AND YOU HAVE TO MAKE A NEW ONE.
local ONE_REPORT_EVERY_SECONDS = 3600

local Reports = {}

local key: any = nil
local lastSent: { [number]: number } = {}
local cooldowns = MemoryStoreService:GetHashMap("CheckpointLTCReports")

local function findKey(fallback: string?): any
	local ok, secret = pcall(HttpService.GetSecret, HttpService, SECRET_NAME)
	if ok and secret then
		return secret
	end
	if type(fallback) == "string" and string.match(fallback, "^ltcg_") then
		return fallback
	end
	return nil
end

local function claim(userId: number): boolean
	local ok, claimed = pcall(function()
		local got = false
		cooldowns:UpdateAsync(tostring(userId), function(old)
			got = false
			if old then
				return nil
			end
			got = true
			return os.time()
		end, ONE_REPORT_EVERY_SECONDS)
		return got
	end)
	if ok then
		return claimed
	end
	return RunService:IsStudio()
end

local function release(userId: number)
	lastSent[userId] = nil
	pcall(cooldowns.RemoveAsync, cooldowns, tostring(userId))
end

local function filtered(player: Player, text: string): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

function Reports.submit(player: Player, kind: any, text: any): (boolean, string)
	if not key then
		return false, "Reports are not set up for this game yet."
	end
	if kind ~= "bug" and kind ~= "feedback" then
		return false, "Pick bug or feedback."
	end
	if type(text) ~= "string" then
		return false, "Type something first."
	end
	text = string.sub(string.match(text, "^%s*(.-)%s*$") or "", 1, MAX_LENGTH)
	if text == "" then
		return false, "Type something first."
	end

	local now = os.clock()
	if lastSent[player.UserId] and now - lastSent[player.UserId] < ONE_REPORT_EVERY_SECONDS then
		return false, "You can send one report per hour."
	end
	lastSent[player.UserId] = now
	if not claim(player.UserId) then
		return false, "You can send one report per hour."
	end

	local clean = filtered(player, text)
	if not clean then
		release(player.UserId)
		return false, "Could not check that text. Try again."
	end
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = API_URL,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json", ["X-Checkpoint-Key"] = key },
		Body = HttpService:JSONEncode({
			kind = kind,
			text = clean,
			playerId = player.UserId,
			playerName = player.Name,
			placeId = if game.PlaceId > 0 then game.PlaceId else nil,
			filtered = true,
		}),
	})
	if ok and response.Success then
		return true, "Thanks, it was sent to the developers."
	end
	if ok and response.StatusCode == 429 then
		return false, "You can send one report per hour."
	end
	if ok and response.StatusCode == 401 then
		warn("CheckpointLTC: your game key was refused. It may have been turned off. Make a new one in the plugin.")
		return false, "Reports are off right now."
	end
	release(player.UserId)
	return false, "Could not send it right now."
end

local started = false

function Reports.start(options: { gameKey: string? }?)
	if started then
		return
	end
	started = true
	key = findKey(options and options.gameKey)
	if not key then
		warn("CheckpointLTC: no game key. Add a secret named " .. SECRET_NAME .. " or put the key in StartReports.")
	end
	local remote = ReplicatedStorage:FindFirstChild("CheckpointLTCReport") or Instance.new("RemoteFunction")
	remote.Name = "CheckpointLTCReport"
	remote.Parent = ReplicatedStorage;
	(remote :: RemoteFunction).OnServerInvoke = function(player: Player, kind: any, text: any)
		local ok, sent, message = pcall(Reports.submit, player, kind, text)
		if ok then
			return sent, message
		end
		return false, "Could not send it right now."
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastSent[player.UserId] = nil
end)

return Reports
]=]

local loaderSource = [=[
-- CheckpointLTC in game reports, by LTCLevTec

-- KEEP YOUR GAME KEY OUT OF EVERY OTHER SCRIPT. THIS SERVER SCRIPT IS THE ONLY PLACE IT CAN GO.
-- BEST: PUT IT IN YOUR GAME'S SECRETS STORE INSTEAD, THEN CLEAR THE gameKey LINE BELOW.
--   Creator Dashboard > your game > Secrets > Create Secret
--   Name: CheckpointLTC   Secret: your ltcg_ key   Domain: {{DOMAIN}}
--   For Studio playtests: File > Experience Settings > Security > Local Secrets, same name
-- A key in Secrets can't be read by collaborators or anyone who gets a copy of this place.

-- ONE REPORT PER PLAYER PER HOUR. THIS LIMIT IS REQUIRED AND CANNOT BE CHANGED.
-- IF ONE PLAYER FLOODS REPORTS, THE CHECKPOINTLTC SERVER TURNS YOUR KEY OFF AND YOU MAKE A NEW ONE.

require(script.Parent:WaitForChild("CheckpointLTCReports")).start({
	gameKey = "{{GAME_KEY}}",
})
]=]

local function fill(source: string, values: { [string]: string }): string
	return (string.gsub(source, "{{(%u+_?%u*)}}", function(name)
		return values[name]
	end))
end

function ReportsModule.insert(gameKey: string): (boolean, string)
	if not string.match(gameKey, "^ltcg_[%w_%-]+$") then
		return false, "That game key does not look right."
	end
	local domain = string.match(Config.apiBaseUrl, "^https?://([^/]+)") or Config.apiBaseUrl
	local recording = ChangeHistoryService:TryBeginRecording("Insert CheckpointLTC reports")
	local ok, problem = pcall(function()
		local folder = ServerScriptService:FindFirstChild("CheckpointLTC") or Instance.new("Folder")
		folder.Name = "CheckpointLTC"
		folder.Parent = ServerScriptService
		local module = folder:FindFirstChild("CheckpointLTCReports") or Instance.new("ModuleScript")
		module.Name = "CheckpointLTCReports"
		(module :: any).Source = fill(moduleSource, { API_URL = Config.apiBaseUrl })
		module.Parent = folder
		local loader = folder:FindFirstChild("StartReports") or Instance.new("Script")
		loader.Name = "StartReports"
		(loader :: any).Source = fill(loaderSource, { GAME_KEY = gameKey, DOMAIN = domain })
		loader.Parent = folder
		Selection:Set({ loader })
	end)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		return false,
			"Studio would not let me add the scripts. Allow script injection for this plugin in Manage Plugins. "
				.. tostring(problem)
	end
	return true,
		"Added CheckpointLTC reports to ServerScriptService. Turn on Allow HTTP Requests, then move the key from StartReports into your game's Secrets as CheckpointLTC."
end

return ReportsModule
