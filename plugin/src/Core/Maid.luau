--!strict

export type Task = RBXScriptConnection | thread | Instance | () -> () | { destroy: (any) -> () }

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { tasks: { Task }, destroyed: boolean }, Maid))

function Maid.new(): Maid
	return setmetatable({ tasks = {}, destroyed = false }, Maid)
end

local function release(item: Task)
	if typeof(item) == "RBXScriptConnection" then
		item:Disconnect()
	elseif typeof(item) == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif typeof(item) == "Instance" then
		item:Destroy()
	elseif type(item) == "function" then
		item()
	elseif type(item) == "table" and type(item.destroy) == "function" then
		item:destroy()
	end
end

function Maid.give<T>(self: Maid, task: T & Task): T
	if self.destroyed then
		release(task)
	else
		table.insert(self.tasks, task)
	end
	return task
end

function Maid.clean(self: Maid)
	local tasks = self.tasks
	self.tasks = {}
	for index = #tasks, 1, -1 do
		release(tasks[index])
	end
end

function Maid.destroy(self: Maid)
	self:clean()
	self.destroyed = true
end

return Maid
