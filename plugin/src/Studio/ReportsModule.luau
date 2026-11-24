--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Config = require(script.Parent.Parent.Config)

local ReportsModule = {}

local moduleSource = [=[
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local settings = {
	gameKey = "%s",
	apiUrl = "%s/v1/game/reports",
	cooldownSeconds = 60,
	maxLength = 500,
}

local Reports = {}

local lastSent: { [number]: number } = {}

local function filtered(player: Player, text: string): string?
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

function Reports.submit(player: Player, kind: string, text: string): (boolean, string)
	if kind ~= "bug" and kind ~= "feedback" then
		return false, "Pick bug or feedback."
	end
	if type(text) ~= "string" then
		return false, "Type something first."
	end
	text = string.sub(string.match(text, "^%%s*(.-)%%s*$") or "", 1, settings.maxLength)
	if text == "" then
		return false, "Type something first."
	end
	local now = os.clock()
	if lastSent[player.UserId] and now - lastSent[player.UserId] < settings.cooldownSeconds then
		return false, "Wait a minute before sending another one."
	end
	lastSent[player.UserId] = now
	local clean = filtered(player, text)
	if not clean then
		return false, "Could not check that text. Try again."
	end
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = settings.apiUrl,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json", ["X-Checkpoint-Key"] = settings.gameKey },
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
	return false, "Could not send it right now."
end

local remote = ReplicatedStorage:FindFirstChild("CheckpointLTCReport") or Instance.new("RemoteFunction")
remote.Name = "CheckpointLTCReport"
remote.Parent = ReplicatedStorage
remote.OnServerInvoke = function(player: Player, kind: string, text: string)
	return Reports.submit(player, kind, text)
end

Players.PlayerRemoving:Connect(function(player)
	lastSent[player.UserId] = nil
end)

return Reports
]=]

local loaderSource = [=[
require(script.Parent:WaitForChild("CheckpointLTCReports"))
]=]

function ReportsModule.insert(gameKey: string): (boolean, string)
	if not string.match(gameKey, "^ltcg_[%w_%-]+$") then
		return false, "That game key does not look right."
	end
	local recording = ChangeHistoryService:TryBeginRecording("Insert CheckpointLTC reports")
	local ok, problem = pcall(function()
		local folder = ServerScriptService:FindFirstChild("CheckpointLTC") or Instance.new("Folder")
		folder.Name = "CheckpointLTC"
		folder.Parent = ServerScriptService
		local module = folder:FindFirstChild("CheckpointLTCReports") or Instance.new("ModuleScript")
		module.Name = "CheckpointLTCReports"
		(module :: any).Source = string.format(moduleSource, gameKey, Config.apiBaseUrl)
		module.Parent = folder
		local loader = folder:FindFirstChild("StartReports") or Instance.new("Script")
		loader.Name = "StartReports"
		(loader :: any).Source = loaderSource
		loader.Parent = folder
		Selection:Set({ module })
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
		"Added CheckpointLTC reports to ServerScriptService. Turn on Allow HTTP Requests in Game Settings, then call the CheckpointLTCReport RemoteFunction from your own report button."
end

return ReportsModule
