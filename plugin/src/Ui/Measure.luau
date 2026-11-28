--!strict

local TextService = game:GetService("TextService")

local Typography = require(script.Parent.Typography)

local Measure = {}

function Measure.width(text: string, role: string): number
	local size = Typography.size(role :: any)
	local ok, bounds =
		pcall(TextService.GetTextSize, TextService, text, size, Enum.Font.BuilderSans, Vector2.new(100000, 100000))
	return (if ok then bounds.X else #text * size * 0.55) / 0.9
end

function Measure.height(text: string, role: string, width: number): number
	local size = Typography.size(role :: any)
	local ok, bounds = pcall(
		TextService.GetTextSize,
		TextService,
		text,
		size,
		Enum.Font.BuilderSans,
		Vector2.new(width * 0.88, 100000)
	)
	local lines = if ok then bounds.Y else size * 4
	return (lines + Typography.lineHeight(role :: any) * 0.35) / 0.9
end

function Measure.paragraph(text: string, role: string): (number, number?) -> number
	return function(designWidth: number, realWidth: number?): number
		return designWidth / Measure.height(text, role, realWidth or designWidth)
	end
end

return Measure
