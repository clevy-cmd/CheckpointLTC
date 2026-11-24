--!strict

local flavorModule = script.Parent:FindFirstChild("Flavor")
local flavor: { [string]: any } = if flavorModule and flavorModule:IsA("ModuleScript")
	then (require :: any)(flavorModule)
	else {}

local Config = {}

Config.version = "1.0.0"
Config.isTestBuild = flavor.isTestBuild == true
Config.productName = flavor.productName or "CheckpointLTC"
Config.toolbarName = flavor.toolbarName or "LTCLevTec"
Config.buttonText = flavor.buttonText or "CheckpointLTC"
Config.widgetId = flavor.widgetId or "CheckpointLTCWidget"
Config.actionPrefix = flavor.actionPrefix or "CheckpointLTC"
Config.settingPrefix = flavor.settingPrefix or ""
Config.apiBaseUrl = flavor.apiBaseUrl or "https://checkpointltc.ltclevtec.com"
Config.quickLogin = flavor.quickLogin == true
Config.buildKey = flavor.buildKey
Config.guideUrl = Config.apiBaseUrl .. "/guide.pdf"

Config.network = {
	timeoutSeconds = 12,
	longTimeoutSeconds = 120,
	maxAttempts = 3,
	backoffBaseSeconds = 0.6,
	backoffMaxSeconds = 4,
}

Config.refresh = {
	minimumGapSeconds = 2,
	idleAfterSeconds = 180,
	idleMultiplier = 4,
	presenceSeconds = 60,
	reminderCheckSeconds = 60,
}

Config.interaction = {
	debounceSeconds = 0.35,
	toastSeconds = 5,
	tooltipDelay = 0.45,
	resizeSettleSeconds = 0.15,
	drawerSeconds = 0.18,
	counterFromFraction = 0.8,
	maxInputLines = 6,
}

Config.fallbackLimits = {
	titleMaxLength = 60,
	itemMaxLength = 240,
	notesMaxLength = 2000,
	commentMaxLength = 1000,
	submissionTitleMaxLength = 100,
	submissionBodyMaxLength = 2000,
	attachmentMaxBytes = 10 * 1024 * 1024,
	attachmentTypes = { "mp4", "mov", "png", "jpg", "txt" },
	uploadChunkBytes = 256 * 1024,
}

Config.widget = {
	defaultWidth = 420,
	defaultHeight = 620,
	minWidth = 280,
	minHeight = 360,
	sidebarBreakpoint = 560,
}

Config.settingKeys = {
	authKeyPrefix = "authKey:",
	lastListPrefix = "lastList:",
	tourDone = "tourDone",
}

Config.brand = {
	blue = Color3.fromHex("29b9e8"),
	red = Color3.fromHex("7a0e1c"),
	redBright = Color3.fromHex("c0283b"),
	green = Color3.fromHex("4cb878"),
	yellow = Color3.fromHex("f2b632"),
}

Config.accents = {
	brand = Color3.fromHex("29b9e8"),
	blue = Color3.fromHex("3b82f6"),
	red = Color3.fromHex("c0283b"),
	green = Color3.fromHex("3fa66a"),
	purple = Color3.fromHex("8b6fd6"),
	orange = Color3.fromHex("e8833a"),
}

Config.labelColors = {
	Scripting = Color3.fromHex("29b9e8"),
	UI = Color3.fromHex("8b6fd6"),
	VFX = Color3.fromHex("e8833a"),
	Bug = Color3.fromHex("c0283b"),
}

Config.priorityNames = { [0] = "None", [1] = "Low", [2] = "Medium", [3] = "High" }

Config.icons = {
	toolbar = "rbxassetid://123898527062347",
	toolbarBadge = "rbxassetid://139397743856674",
	plus = "rbxassetid://91599608131754",
	refresh = "rbxassetid://121697490486236",
	back = "rbxassetid://70619703787501",
	forward = "rbxassetid://129608967539718",
	check = "rbxassetid://121770900041106",
	trash = "rbxassetid://122647145715550",
	edit = "rbxassetid://90611698396662",
	people = "rbxassetid://90576041275946",
	addPerson = "rbxassetid://88819616919951",
	close = "rbxassetid://75322994513099",
	lists = "rbxassetid://93395950213720",
	code = "rbxassetid://140138852429934",
	rotate = "rbxassetid://123803918948094",
	warning = "rbxassetid://97236700104027",
	info = "rbxassetid://70450343198155",
	link = "rbxassetid://97506263050838",
	assigned = "rbxassetid://132417594559643",
	search = "rbxassetid://113019725398371",
	settings = "rbxassetid://106489534539003",
	bell = "rbxassetid://107266371473658",
	more = "",
	sidebar = "",
	board = "",
	drag = "",
	undo = "rbxassetid://123803918948094",
	attach = "rbxassetid://70726941182592",
	comment = "rbxassetid://88678145314327",
	inbox = "rbxassetid://81437528554517",
}

Config.glyphs = {
	search = "🔍",
	settings = "⚙️",
	bell = "🔔",
	more = "•••",
	sidebar = "📋",
	board = "🗂️",
	drag = "↕️",
	undo = "↩️",
	attach = "📎",
	comment = "💬",
	inbox = "📥",
}

Config.fonts = {
	family = "rbxasset://fonts/families/BuilderSans.json",
	mono = "rbxasset://fonts/families/RobotoMono.json",
}

Config.type = {
	title = { size = 22, ratio = 0.066, min = 17, max = 32, group = "title", weight = Enum.FontWeight.SemiBold },
	body = { size = 19, ratio = 0.056, min = 15, max = 27, group = "body", weight = Enum.FontWeight.Regular },
	label = { size = 18, ratio = 0.052, min = 14, max = 25, group = "body", weight = Enum.FontWeight.Medium },
	meta = { size = 17, ratio = 0.048, min = 13, max = 23, group = "small", weight = Enum.FontWeight.Regular },
	code = { size = 19, ratio = 0.056, min = 15, max = 27, group = "body", weight = Enum.FontWeight.Medium },
	hint = { size = 15, ratio = 0.043, min = 12, max = 20, group = "small", weight = Enum.FontWeight.Regular },
}

Config.rows = {
	titleBar = 6.5,
	listHeader = 5.5,
	taskRow = 8.5,
	compactTaskRow = 12,
	sidebarRow = 13,
	composer = 10,
	field = 11,
	section = 17,
	setting = 9,
	meter = 8.5,
	button = 11,
	hint = 18,
	lineGrowth = 0.6,
}

Config.whatsNew = {
	version = "1.0.0",
	items = {
		{
			title = "The full guide",
			body = "Press Download Guide at the bottom of the sidebar for every button, setting and limit. Your version shows under it and turns orange when an update is out.",
			target = "sidebar",
		},
		{
			title = "Search and the command bar",
			body = "Search finds tasks in every list again. Press / with the mouse over the window to jump to any list, task or action.",
			target = "search",
		},
		{
			title = "Add a person",
			body = "People now has one Add a person button. Pick whether new people join as editors or viewers in Settings, Preferences.",
			target = "settings",
		},
		{
			title = "Player reports and exports",
			body = "Player bug reports work from playtests and unsaved places too. Exports show due dates in your own time, and importing brings them back.",
			target = "more",
		},
		{
			title = "Fewer false alarms",
			body = "The someone changed your list popup only shows when it really was someone else. Task and list actions live in the ••• menus.",
			target = "composer",
		},
	},
}

return Config
