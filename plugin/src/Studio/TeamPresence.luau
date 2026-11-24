--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TeamPresence = {}

function TeamPresence.inSession(): { number }
	local ids = {}
	if RunService:IsRunning() then
		return ids
	end
	for _, player in Players:GetPlayers() do
		if player.UserId > 0 then
			table.insert(ids, player.UserId)
		end
	end
	return ids
end

function TeamPresence.watch(onChange: () -> ()): { RBXScriptConnection }
	return {
		Players.PlayerAdded:Connect(onChange),
		Players.PlayerRemoving:Connect(function()
			task.defer(onChange)
		end),
	}
end

return TeamPresence
