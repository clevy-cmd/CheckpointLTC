--!strict

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Parent.Config)

export type ApiError = {
	code: string,
	message: string,
	status: number,
	body: any?,
}

export type Result = { ok: true, status: number, data: any } | { ok: false, error: ApiError }

export type Options = { timeout: number?, attempts: number? }

local Http = {}

Http.null = "@@checkpointltc.null@@"

local idempotentMethods = { GET = true, PUT = true, DELETE = true }
local retryableStatus = { [429] = true, [500] = true, [502] = true, [503] = true, [504] = true }

local function failure(code: string, message: string, status: number?, body: any?): Result
	return { ok = false, error = { code = code, message = message, status = status or 0, body = body } }
end

local function describeTransportError(err: string): Result
	local lowered = string.lower(err)
	if string.find(lowered, "not allowed") or string.find(lowered, "permission") or string.find(lowered, "denied") then
		return failure(
			"http_blocked",
			"Studio blocked the connection. Allow this plugin's web access in Plugins > Manage Plugins.",
			0
		)
	end
	return failure("network", "I couldn't reach the server. Check your connection and try again.", 0)
end

local function requestWithTimeout(options: { [string]: any }, timeout: number): (boolean, any)
	local finished = false
	local success, response = false, "timeout" :: any
	local caller = coroutine.running()

	task.spawn(function()
		local ok, result = pcall(HttpService.RequestAsync, HttpService, options :: any)
		if finished then
			return
		end
		finished = true
		success, response = ok, result
		task.spawn(caller)
	end)

	local timer = task.delay(timeout, function()
		if finished then
			return
		end
		finished = true
		success, response = false, "timeout"
		task.spawn(caller)
	end)

	if not finished then
		coroutine.yield()
	end
	pcall(task.cancel, timer)
	return success, response
end

local function decode(body: string?): any
	if not body or body == "" then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
	return if ok then data else nil
end

local function backoff(attempt: number): number
	local base = Config.network.backoffBaseSeconds * 2 ^ (attempt - 1)
	return math.min(base, Config.network.backoffMaxSeconds) * (0.75 + math.random() * 0.5)
end

function Http.request(
	method: string,
	path: string,
	headers: { [string]: string },
	payload: any?,
	settings: Options?
): Result
	local options = {
		Url = Config.apiBaseUrl .. path,
		Method = method,
		Headers = headers,
		Body = if payload ~= nil
			then (string.gsub(HttpService:JSONEncode(payload), '"@@checkpointltc%.null@@"', "null"))
			else nil,
	}
	options.Headers["Content-Type"] = "application/json"
	options.Headers["X-Plugin-Version"] = Config.version
	if Config.buildKey then
		options.Headers["X-Build-Key"] = Config.buildKey
	end

	local timeout = if settings and settings.timeout then settings.timeout else Config.network.timeoutSeconds
	local attempts = if settings and settings.attempts
		then settings.attempts
		elseif idempotentMethods[method] then Config.network.maxAttempts
		else 1
	local last: Result = failure("network", "I couldn't reach the server.")

	for attempt = 1, attempts do
		local ok, response = requestWithTimeout(options, timeout)
		if not ok then
			last = if response == "timeout"
				then failure("timeout", "The server took too long to answer. Try again.")
				else describeTransportError(tostring(response))
			if last.ok == false and last.error.code == "http_blocked" then
				return last
			end
		else
			local data = decode(response.Body)
			if response.Success then
				return { ok = true, status = response.StatusCode, data = data }
			end
			local serverError = if type(data) == "table" and type(data.error) == "table" then data.error else nil
			last = failure(
				if serverError then tostring(serverError.code) else "http_" .. response.StatusCode,
				if serverError then tostring(serverError.message) else "The server answered with an error.",
				response.StatusCode,
				data
			)
			if not retryableStatus[response.StatusCode] or (serverError and serverError.code == "cooldown") then
				return last
			end
		end
		if attempt < attempts then
			task.wait(backoff(attempt))
		end
	end
	return last
end

return Http
