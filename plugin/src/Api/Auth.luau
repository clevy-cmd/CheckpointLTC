--!strict

local StudioService = game:GetService("StudioService")

local Config = require(script.Parent.Parent.Config)

local Auth = {}

local pluginRef: Plugin? = nil

function Auth.init(plugin: Plugin)
	pluginRef = plugin
end

function Auth.currentUserId(): number
	local ok, userId = pcall(StudioService.GetUserId, StudioService)
	return if ok and type(userId) == "number" then userId else 0
end

local function settingKey(userId: number): string
	return Config.settingPrefix .. Config.settingKeys.authKeyPrefix .. tostring(userId)
end

function Auth.getSetting(key: string): any
	if not pluginRef then
		return nil
	end
	local ok, value = pcall(pluginRef.GetSetting, pluginRef, Config.settingPrefix .. key)
	return if ok then value else nil
end

function Auth.setSetting(key: string, value: any)
	if pluginRef then
		pcall(pluginRef.SetSetting, pluginRef, Config.settingPrefix .. key, value)
	end
end

function Auth.loadKey(userId: number): string?
	if not pluginRef or userId <= 0 then
		return nil
	end
	local ok, value = pcall(pluginRef.GetSetting, pluginRef, settingKey(userId))
	return if ok and type(value) == "string" and value ~= "" then value else nil
end

function Auth.saveKey(userId: number, key: string?)
	if pluginRef and userId > 0 then
		pcall(pluginRef.SetSetting, pluginRef, settingKey(userId), key)
	end
end

function Auth.deviceLabel(): string
	local placeName = if game.Name ~= "" then game.Name else "a place"
	return string.sub("Studio on " .. placeName, 1, 40)
end

function Auth.headers(userId: number, key: string): { [string]: string }
	return {
		Authorization = "Bearer " .. key,
		["X-Roblox-User-Id"] = tostring(userId),
	}
end

return Auth
