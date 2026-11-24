--!strict

local Time = {}

local dayMs = 86400000

function Time.nowMs(): number
	return DateTime.now().UnixTimestampMillis
end

function Time.startOfTodayMs(): number
	local now = DateTime.now():ToLocalTime()
	return DateTime.fromLocalTime(now.Year, now.Month, now.Day, 0, 0, 0, 0).UnixTimestampMillis
end

function Time.endOfDayMs(daysFromToday: number): number
	return Time.startOfTodayMs() + (daysFromToday + 1) * dayMs - 60000
end

function Time.dueText(dueAt: number?): (string, "overdue" | "soon" | "later" | "none")
	if not dueAt then
		return "", "none"
	end
	local today = Time.startOfTodayMs()
	local days = math.floor((dueAt - today) / dayMs)
	if dueAt < Time.nowMs() then
		if days == 0 then
			return "Due today", "overdue"
		end
		local ago = -days
		return if ago == 1 then "1 day overdue" else string.format("%d days overdue", ago), "overdue"
	elseif days == 0 then
		return "Due today", "soon"
	elseif days == 1 then
		return "Due tomorrow", "soon"
	elseif days < 7 then
		return "Due " .. DateTime.fromUnixTimestampMillis(dueAt):FormatLocalTime("dddd", "en-us"), "later"
	end
	return "Due " .. DateTime.fromUnixTimestampMillis(dueAt):FormatLocalTime("MMM D", "en-us"), "later"
end

function Time.ago(ms: number): string
	local seconds = math.max(0, (Time.nowMs() - ms) / 1000)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		local minutes = math.floor(seconds / 60)
		return if minutes == 1 then "1 minute ago" else string.format("%d minutes ago", minutes)
	elseif seconds < 86400 then
		local hours = math.floor(seconds / 3600)
		return if hours == 1 then "1 hour ago" else string.format("%d hours ago", hours)
	end
	local days = math.floor(seconds / 86400)
	if days < 30 then
		return if days == 1 then "yesterday" else string.format("%d days ago", days)
	end
	return DateTime.fromUnixTimestampMillis(ms):FormatLocalTime("MMM D, YYYY", "en-us")
end

function Time.countdown(untilMs: number): string
	local seconds = math.max(0, math.ceil((untilMs - Time.nowMs()) / 1000))
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%02d", minutes, seconds % 60)
end

function Time.bytes(size: number): string
	if size >= 1024 * 1024 then
		return string.format("%.1f MB", size / 1024 / 1024)
	elseif size >= 1024 then
		return string.format("%d KB", math.floor(size / 1024))
	end
	return string.format("%d bytes", size)
end

function Time.offsetMinutes(ms: number): number
	local whole = DateTime.fromUnixTimestampMillis(ms)
	local here = whole:ToLocalTime()
	local asUtc = DateTime.fromUniversalTime(
		here.Year,
		here.Month,
		here.Day,
		here.Hour,
		here.Minute,
		here.Second,
		here.Millisecond
	)
	return math.floor((asUtc.UnixTimestampMillis - ms) / 60000 + 0.5)
end

function Time.offsetRanges(stamps: { number }): { { number } }
	local sorted = table.clone(stamps)
	table.insert(sorted, Time.nowMs())
	table.sort(sorted)
	local ranges = {}
	local last: number? = nil
	for _, ms in sorted do
		local offset = Time.offsetMinutes(ms)
		if offset ~= last then
			table.insert(ranges, { if #ranges == 0 then 0 else math.floor(ms), offset })
			last = offset
			if #ranges >= 50 then
				break
			end
		end
	end
	return ranges
end

function Time.parseDate(text: string): number?
	local parts = {}
	for digits in string.gmatch(text, "%d+") do
		table.insert(parts, digits)
	end
	local year, month, day
	if #parts == 1 and #parts[1] == 8 then
		year, month, day =
			tonumber(string.sub(parts[1], 1, 4)),
			tonumber(string.sub(parts[1], 5, 6)),
			tonumber(string.sub(parts[1], 7, 8))
	elseif #parts == 3 and #parts[1] == 4 then
		year, month, day = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
	elseif #parts == 3 and #parts[3] == 4 then
		year, month, day = tonumber(parts[3]), tonumber(parts[1]), tonumber(parts[2])
	else
		return nil
	end
	if
		not year
		or not month
		or not day
		or month < 1
		or month > 12
		or day < 1
		or day > 31
		or year < 2000
		or year > 2200
	then
		return nil
	end
	local ok, date = pcall(DateTime.fromLocalTime, year, month, day, 23, 59, 0, 0)
	if not ok then
		return nil
	end
	local check = date:ToLocalTime()
	if check.Month ~= month or check.Day ~= day then
		return nil
	end
	return date.UnixTimestampMillis
end

return Time
