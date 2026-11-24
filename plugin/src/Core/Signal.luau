--!strict

local Signal = {}
Signal.__index = Signal

export type Connection = { disconnect: () -> () }
export type Signal<T...> = typeof(setmetatable({} :: { listeners: { (T...) -> () } }, Signal))

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ listeners = {} }, Signal) :: any
end

function Signal.connect<T...>(self: Signal<T...>, listener: (T...) -> ()): Connection
	table.insert(self.listeners, listener)
	return {
		disconnect = function()
			local index = table.find(self.listeners, listener)
			if index then
				table.remove(self.listeners, index)
			end
		end,
	}
end

function Signal.fire<T...>(self: Signal<T...>, ...: T...)
	for _, listener in table.clone(self.listeners) do
		local ok, err = pcall(listener, ...)
		if not ok then
			warn("[CheckpointLTC] listener error:", err)
		end
	end
end

function Signal.destroy<T...>(self: Signal<T...>)
	table.clear(self.listeners)
end

return Signal
