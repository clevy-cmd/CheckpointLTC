--!strict

local StudioService = game:GetService("StudioService")

local Files = {}

export type Picked = { name: string, size: number, contents: string, extension: string }

function Files.pick(types: { string }, maxBytes: number): (Picked?, string?)
	local ok, file = pcall(function()
		return (StudioService :: any):PromptImportFileAsync(types)
	end)
	if not ok then
		return nil, "Studio could not open the file picker."
	end
	if not file then
		return nil, nil
	end
	local name = tostring(file.Name)
	local extension = string.lower(string.match(name, "%.([%w]+)$") or "")
	if extension == "jpeg" then
		extension = "jpg"
	end
	if not table.find(types, extension) then
		return nil, "Only " .. table.concat(types, ", ") .. " files can be attached."
	end
	local size = tonumber(file.Size) or 0
	if size > maxBytes then
		return nil,
			string.format(
				"That file is %.1f MB. Files can be up to %d MB.",
				size / 1024 / 1024,
				math.floor(maxBytes / 1024 / 1024)
			)
	end
	if size <= 0 then
		return nil, "That file is empty."
	end
	local readOk, contents = pcall(function()
		return file:GetBinaryContents()
	end)
	if not readOk or type(contents) ~= "string" then
		return nil, "I couldn't read that file."
	end
	return { name = name, size = #contents, contents = contents, extension = extension }, nil
end

return Files
