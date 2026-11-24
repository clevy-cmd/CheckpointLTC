--!strict

local Config = require(script.Parent.Parent.Config)

local Debounce = {}

local busy: { [string]: boolean } = {}
local lastRun: { [string]: number } = {}

function Debounce.run(key: string, work: () -> (), cooldown: number?): boolean
	local now = os.clock()
	local gap = cooldown or Config.interaction.debounceSeconds
	if busy[key] or (lastRun[key] and now - lastRun[key] < gap) then
		return false
	end
	busy[key] = true
	lastRun[key] = now
	task.spawn(function()
		local ok, err = pcall(work)
		busy[key] = nil
		if not ok then
			warn("[CheckpointLTC]", key, err)
		end
	end)
	return true
end
function Debounce.isBusy(key: string): boolean
	return busy[key] == true
end
function Debounce.reset()
	table.clear(busy)
	table.clear(lastRun)
end
return Debounce
