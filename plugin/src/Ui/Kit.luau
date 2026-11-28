--!strict

local ContentProvider = game:GetService("ContentProvider")

local Config = require(script.Parent.Parent.Config)
local Theme = require(script.Parent.Theme)
local Typography = require(script.Parent.Typography)

local Kit = {}

export type Props = { [string]: any }

function Kit.create(className: string, props: Props?, children: { any }?): any
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	local parent = if props then props.Parent else nil
	for key, value in props or {} do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Kit.frame(props: Props?, children: { any }?): Frame
	local merged: Props = { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }
	for key, value in props or {} do
		merged[key] = value
	end
	return Kit.create("Frame", merged, children)
end

function Kit.surface(token: string, props: Props?, children: { any }?): Frame
	local frame = Kit.frame(props, children)
	frame.BackgroundTransparency = if props and props.BackgroundTransparency then props.BackgroundTransparency else 0
	Theme.bind(frame, "BackgroundColor3", token)
	return frame
end

function Kit.padding(scale: number?): UIPadding
	local s = UDim.new(scale or 0.05, 0)
	return Kit.create("UIPadding", { PaddingTop = s, PaddingBottom = s, PaddingLeft = s, PaddingRight = s })
end

function Kit.paddingXY(x: number, y: number): UIPadding
	return Kit.create("UIPadding", {
		PaddingTop = UDim.new(y, 0),
		PaddingBottom = UDim.new(y, 0),
		PaddingLeft = UDim.new(x, 0),
		PaddingRight = UDim.new(x, 0),
	})
end

function Kit.aspect(ratio: number, dominant: Enum.DominantAxis?): UIAspectRatioConstraint
	return Kit.create("UIAspectRatioConstraint", {
		AspectRatio = ratio,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = dominant or Enum.DominantAxis.Width,
	})
end

function Kit.square(): UIAspectRatioConstraint
	return Kit.aspect(1, Enum.DominantAxis.Height)
end

function Kit.list(
	direction: Enum.FillDirection?,
	align: Enum.HorizontalAlignment?,
	verticalAlign: Enum.VerticalAlignment?,
	gap: number?
): UIListLayout
	return Kit.create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = verticalAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(gap or 0, 0),
	})
end

function Kit.row(gap: number?, verticalAlign: Enum.VerticalAlignment?): UIListLayout
	return Kit.list(
		Enum.FillDirection.Horizontal,
		Enum.HorizontalAlignment.Left,
		verticalAlign or Enum.VerticalAlignment.Center,
		gap
	)
end

function Kit.fill(): UIFlexItem
	return Kit.create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
end

function Kit.aspectRow(ratio: number, props: Props?, children: { any }?): Frame
	local row = Kit.frame(props, children)
	Kit.aspect(ratio).Parent = row
	return row
end

Kit.peek = nil :: ((TextLabel, boolean) -> ())?

export type TextOptions = {
	text: string?,
	role: string?,
	token: string?,
	align: Enum.TextXAlignment?,
	yAlign: Enum.TextYAlignment?,
	wrap: boolean?,
	rich: boolean?,
	noPeek: boolean?,
	props: Props?,
}

function Kit.label(options: TextOptions): TextLabel
	local label = Kit.create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = options.text or "",
		TextXAlignment = options.align or Enum.TextXAlignment.Left,
		TextYAlignment = options.yAlign or Enum.TextYAlignment.Center,
		TextWrapped = options.wrap == true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = options.rich == true,
	}, { Kit.padding() })
	for key, value in options.props or {} do
		(label :: any)[key] = value
	end
	Typography.apply(label, options.role or "body")
	Theme.bind(label, "TextColor3", options.token or "text")
	if not options.noPeek then
		label.MouseEnter:Connect(function()
			local peek = Kit.peek
			if peek and not label.TextFits then
				peek(label, true)
			end
		end)
		label.MouseLeave:Connect(function()
			local peek = Kit.peek
			if peek then
				peek(label, false)
			end
		end)
	end
	return label
end

function Kit.icon(image: string, token: string, props: Props?): ImageLabel
	local icon = Kit.create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = image,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
	}, { Kit.square() })
	for k, v in props or {} do
		(icon :: any)[k] = v
	end
	Theme.bind(icon, "ImageColor3", token)
	return icon
end

local drawn: { [string]: { { number } } } = {
	drag = {
		{ 0.3, 0.2, 0.14, 0.14 },
		{ 0.56, 0.2, 0.14, 0.14 },
		{ 0.3, 0.43, 0.14, 0.14 },
		{ 0.56, 0.43, 0.14, 0.14 },
		{ 0.3, 0.66, 0.14, 0.14 },
		{ 0.56, 0.66, 0.14, 0.14 },
	},
	more = { { 0.14, 0.43, 0.14, 0.14 }, { 0.43, 0.43, 0.14, 0.14 }, { 0.72, 0.43, 0.14, 0.14 } },
	sidebar = { { 0.15, 0.22, 0.7, 0.1 }, { 0.15, 0.45, 0.7, 0.1 }, { 0.15, 0.68, 0.7, 0.1 } },
	board = { { 0.15, 0.2, 0.18, 0.6 }, { 0.41, 0.2, 0.18, 0.45 }, { 0.67, 0.2, 0.18, 0.3 } },
}

function Kit.glyphIcon(name: string, token: string, props: Props?): GuiObject
	local shape = drawn[name]
	if shape then
		local holder = Kit.frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
		}, { Kit.square() })
		for _, part in shape do
			Kit.surface(token, {
				Position = UDim2.fromScale(part[1], part[2]),
				Size = UDim2.fromScale(part[3], part[4]),
				Parent = holder,
			})
		end
		for k, v in props or {} do
			(holder :: any)[k] = v
		end
		return holder
	end
	local image = (Config.icons :: any)[name] or ""
	if image ~= "" then
		local holder = Kit.frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
		})
		local picture = Kit.icon(image, token, { Size = UDim2.fromScale(1, 1), Parent = holder })
		local fallback = Kit.label({
			text = (Config.glyphs :: any)[name] or "•",
			role = "label",
			token = token,
			align = Enum.TextXAlignment.Center,
		})
		fallback.Visible = false
		fallback.Parent = holder
		task.spawn(function()
			local ok = pcall(function()
				ContentProvider:PreloadAsync({ picture }, function(_, status)
					if status ~= Enum.AssetFetchStatus.Success then
						picture.Visible = false
						fallback.Visible = true
					end
				end)
			end)
			if not ok then
				picture.Visible = false
				fallback.Visible = true
			end
		end)
		for k, v in props or {} do
			(holder :: any)[k] = v
		end
		return holder
	end
	local glyph = Kit.label({
		text = (Config.glyphs :: any)[name] or "•",
		role = "label",
		token = token,
		align = Enum.TextXAlignment.Center,
	})
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.8, 0.8)
	for k, v in props or {} do
		(glyph :: any)[k] = v
	end
	return glyph
end

function Kit.hitbox(props: Props?): TextButton
	local merged: Props = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 2,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return Kit.create("TextButton", merged)
end

function Kit.scroll(props: Props?, children: { any }?): ScrollingFrame
	local merged: Props = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		BorderSizePixel = 0,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	local frame = Kit.create("ScrollingFrame", merged, children)
	Theme.bind(frame, "ScrollBarImageColor3", "lineStrong")
	return frame
end

function Kit.escape(text: string): string
	return (
		string.gsub(string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), '"', "&quot;")
	)
end

function Kit.color(token: string): Color3
	return Theme.get(token)
end

Kit.rows = Config.rows

return Kit
