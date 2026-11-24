--!strict

local Base64 = {}

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local codes = buffer.create(64)
for index = 1, 64 do
	buffer.writeu8(codes, index - 1, string.byte(alphabet, index))
end
local pad = string.byte("=")

function Base64.encode(input: string, from: number?, to: number?): string
	local first = from or 1
	local last = math.min(to or #input, #input)
	local length = math.max(0, last - first + 1)
	local source = buffer.fromstring(string.sub(input, first, last))
	local output = buffer.create(math.ceil(length / 3) * 4)
	local out = 0
	local index = 0
	while index + 2 < length do
		local a = buffer.readu8(source, index)
		local b = buffer.readu8(source, index + 1)
		local c = buffer.readu8(source, index + 2)
		local n = bit32.bor(bit32.lshift(a, 16), bit32.lshift(b, 8), c)
		buffer.writeu8(output, out, buffer.readu8(codes, bit32.extract(n, 18, 6)))
		buffer.writeu8(output, out + 1, buffer.readu8(codes, bit32.extract(n, 12, 6)))
		buffer.writeu8(output, out + 2, buffer.readu8(codes, bit32.extract(n, 6, 6)))
		buffer.writeu8(output, out + 3, buffer.readu8(codes, bit32.extract(n, 0, 6)))
		index += 3
		out += 4
	end
	local remaining = length - index
	if remaining == 1 then
		local n = bit32.lshift(buffer.readu8(source, index), 16)
		buffer.writeu8(output, out, buffer.readu8(codes, bit32.extract(n, 18, 6)))
		buffer.writeu8(output, out + 1, buffer.readu8(codes, bit32.extract(n, 12, 6)))
		buffer.writeu8(output, out + 2, pad)
		buffer.writeu8(output, out + 3, pad)
	elseif remaining == 2 then
		local n =
			bit32.bor(bit32.lshift(buffer.readu8(source, index), 16), bit32.lshift(buffer.readu8(source, index + 1), 8))
		buffer.writeu8(output, out, buffer.readu8(codes, bit32.extract(n, 18, 6)))
		buffer.writeu8(output, out + 1, buffer.readu8(codes, bit32.extract(n, 12, 6)))
		buffer.writeu8(output, out + 2, buffer.readu8(codes, bit32.extract(n, 6, 6)))
		buffer.writeu8(output, out + 3, pad)
	end
	return buffer.tostring(output)
end

return Base64
