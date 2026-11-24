--!strict

local Actions = require(script.Parent.Parent.Parent.State.Actions)
local Config = require(script.Parent.Parent.Parent.Config)
local Controls = require(script.Parent.Parent.Components.Controls)
local Kit = require(script.Parent.Parent.Kit)
local Maid = require(script.Parent.Parent.Parent.Core.Maid)
local Overlay = require(script.Parent.Parent.Components.Overlay)
local Store = require(script.Parent.Parent.Parent.State.Store)

local Setup = {}

function Setup.new(ctx: any): any
	local maid: Maid.Maid = ctx.maid
	local root = Kit.frame({ Name = "Setup" })
	local column = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.86, 0.7),
		Parent = root,
	})
	local mark = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.24, 0.012),
		Parent = column,
	})
	Kit.surface("brandBlue", { Size = UDim2.fromScale(0.7, 1), Parent = mark })
	Kit.surface("brandRed", { Position = UDim2.fromScale(0.7, 0), Size = UDim2.fromScale(0.3, 1), Parent = mark })
	local title = Kit.label({
		text = Config.productName,
		role = "title",
		align = Enum.TextXAlignment.Center,
		props = { Position = UDim2.fromScale(0, 0.16), Size = UDim2.fromScale(1, 0.1) },
	})
	title.Parent = column
	local body = Kit.label({
		text = "",
		role = "body",
		token = "subtext",
		wrap = true,
		align = Enum.TextXAlignment.Center,
		props = { Position = UDim2.fromScale(0, 0.27), Size = UDim2.fromScale(1, 0.22) },
	})
	body.Parent = column
	local code = Kit.surface(
		"accentSoft",
		{ Position = UDim2.fromScale(0.1, 0.5), Size = UDim2.fromScale(0.8, 0.12), Visible = false, Parent = column },
		{}
	)
	local codeText = Kit.label({ text = "", role = "code", token = "accent", align = Enum.TextXAlignment.Center })
	codeText.Parent = code
	local primary = Controls.button({
		text = "Log in with Roblox",
		kind = "primary",
		onClick = function()
			local state = Store.get()
			if state.phase == "login" and state.login then
				Overlay.prompt({
					title = "Login link",
					body = "Copy this link into your browser.",
					placeholder = "",
					initial = state.login.url,
					confirm = "Done",
					maxLength = 300,
					readOnly = true,
				})
			else
				Actions.startLogin()
			end
		end,
		props = { Position = UDim2.fromScale(0.1, 0.66), Size = UDim2.fromScale(0.8, 0.11) },
		parent = column,
	}, maid)
	local secondary = Controls.button({
		text = "Cancel",
		kind = "ghost",
		onClick = function()
			local state = Store.get()
			if state.phase == "login" then
				Actions.cancelLogin()
			elseif state.storeUrl then
				Overlay.prompt({
					title = "Get CheckpointLTC",
					body = "Copy this link into your browser.",
					placeholder = "",
					initial = state.storeUrl,
					confirm = "Done",
					maxLength = 300,
					readOnly = true,
				})
			end
		end,
		props = { Position = UDim2.fromScale(0.1, 0.8), Size = UDim2.fromScale(0.8, 0.09) },
		parent = column,
	}, maid)
	local foot = Kit.label({
		text = "",
		role = "hint",
		token = "dim",
		wrap = true,
		align = Enum.TextXAlignment.Center,
		props = { Position = UDim2.fromScale(0, 0.91), Size = UDim2.fromScale(1, 0.09) },
	})
	foot.Parent = column

	return {
		root = root,
		render = function(state: Store.State)
			local loggingIn = state.phase == "login" and state.login ~= nil
			code.Visible = loggingIn
			if state.phase == "booting" then
				body.Text = "Starting"
			elseif loggingIn then
				body.Text =
					"Open the login link in your browser, check the code matches, and finish on Roblox. This panel finishes on its own."
				codeText.Text = (state.login :: any).code
			elseif state.banned then
				body.Text = "This account has been banned from CheckpointLTC for violating the Terms of Service."
			elseif state.needsPurchase then
				body.Text =
					"This Roblox account doesn't own CheckpointLTC yet. Get it on the Creator Store with the same account, then log in again."
			else
				body.Text =
					"Shared to do lists for your team, right inside Studio. Log in with the Roblox account you use in Studio."
			end
			primary.setText(
				if loggingIn
					then "Show the login link"
					elseif state.busyMessage then state.busyMessage
					else "Log in with Roblox"
			)
			secondary.root.Visible = loggingIn or (state.needsPurchase and state.storeUrl ~= nil)
			secondary.setText(if loggingIn then "Cancel" else "Get it on the Creator Store")
			foot.Text = if Config.quickLogin
				then "Test build: logs in without Roblox, only on the test server."
				else "Roblox only tells CheckpointLTC your UserId. Never your password."
		end,
	}
end

return Setup
