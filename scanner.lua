local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

if getgenv().RefOreLiteScan and getgenv().RefOreLiteScan.Stop then
	pcall(function()
		getgenv().RefOreLiteScan.Stop("restart")
	end)
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Scan = {
	Enabled = true,
	FileBase = "ref_ore_lite_scan_" .. tostring(os.time()),
	LatestTxt = "ref_ore_lite_scan_latest.txt",
	LatestJson = "ref_ore_lite_scan_latest.json",
	Logs = {},
	Lines = {},
	Connections = {},
}

getgenv().RefOreLiteScan = Scan

local function t()
	return string.format("%.3f", os.clock())
end

local function safeFullName(obj)
	local ok, value = pcall(function()
		return obj:GetFullName()
	end)
	return ok and value or tostring(obj)
end

local function safeText(obj)
	local value = ""
	pcall(function()
		value = tostring(obj.Text or "")
	end)
	return value
end

local function childIndex(obj)
	local parent = obj and obj.Parent
	if not parent then return 0 end

	for i, child in ipairs(parent:GetChildren()) do
		if child == obj then
			return i
		end
	end

	return 0
end

local function indexedPath(obj)
	if not obj then return "nil" end

	local chain = {}
	local node = obj

	while node and node ~= playerGui do
		table.insert(chain, 1, string.format(":GetChildren()[%d].%s", childIndex(node), node.Name))
		node = node.Parent
	end

	if node == playerGui then
		return "PlayerGui" .. table.concat(chain, "")
	end

	return safeFullName(obj)
end

local function isVisibleChain(obj)
	if not obj or not obj.Parent then return false end

	local node = obj
	while node and node ~= playerGui do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end

		if node:IsA("LayerCollector") then
			local ok, enabled = pcall(function()
				return node.Enabled
			end)
			if ok and enabled == false then
				return false
			end
		end

		node = node.Parent
	end

	return true
end

local function info(obj)
	local data = {
		class = obj.ClassName,
		name = obj.Name,
		fullName = safeFullName(obj),
		indexedPath = indexedPath(obj),
	}

	if obj:IsA("GuiObject") then
		data.text = safeText(obj)
		data.visible = obj.Visible
		data.visibleChain = isVisibleChain(obj)
		data.active = obj.Active
		data.selectable = obj.Selectable
		data.zIndex = obj.ZIndex
		data.layoutOrder = obj.LayoutOrder
		data.absolutePosition = {
			x = math.floor(obj.AbsolutePosition.X),
			y = math.floor(obj.AbsolutePosition.Y),
		}
		data.absoluteSize = {
			x = math.floor(obj.AbsoluteSize.X),
			y = math.floor(obj.AbsoluteSize.Y),
		}
	end

	if obj:IsA("LayerCollector") then
		pcall(function()
			data.enabled = obj.Enabled
			data.displayOrder = obj.DisplayOrder
		end)
	end

	return data
end

local function blobOf(obj)
	return string.lower(table.concat({
		obj.Name or "",
		obj.ClassName or "",
		safeText(obj),
		safeFullName(obj),
		obj.Parent and obj.Parent.Name or "",
	}, " "))
end

local function isInteresting(obj)
	local blob = blobOf(obj)

	return blob:find("catch", 1, true)
		or blob:find("captur", 1, true)
		or blob:find("collect", 1, true)
		or blob:find("colet", 1, true)
		or blob:find("release", 1, true)
		or blob:find("soltar", 1, true)
		or blob:find("pickaxe", 1, true)
		or blob:find("ore", 1, true)
		or blob:find("mine", 1, true)
end

local function add(event, data)
	if not Scan.Enabled then return end

	data = data or {}
	data.t = t()
	data.event = event

	table.insert(Scan.Logs, data)

	local line = "[" .. data.t .. "] " .. event
	if data.name then line = line .. " | name=" .. tostring(data.name) end
	if data.class then line = line .. " | class=" .. tostring(data.class) end
	if data.text then line = line .. " | text=" .. tostring(data.text) end
	if data.indexedPath then line = line .. " | path=" .. tostring(data.indexedPath) end
	if data.reason then line = line .. " | reason=" .. tostring(data.reason) end

	table.insert(Scan.Lines, line)
end

local function scanGui(reason)
	local top = {}
	local buttons = {}

	for index, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("LayerCollector") then
			local childInfo = info(child)
			childInfo.childIndex = index
			childInfo.descendants = #child:GetDescendants()
			table.insert(top, childInfo)
		end
	end

	for _, obj in ipairs(playerGui:GetDescendants()) do
		if obj:IsA("TextButton") or obj:IsA("ImageButton") then
			if isInteresting(obj) then
				table.insert(buttons, info(obj))
			end
		end
	end

	add("manual_gui_scan", {
		reason = reason,
		topLevelCount = #top,
		buttonCount = #buttons,
		topLevel = top,
		buttons = buttons,
	})
end

local function scanClickPosition(x, y, reason)
	local inset = GuiService:GetGuiInset()
	local points = {
		{ label = "raw", x = x, y = y },
		{ label = "minus_inset", x = x - inset.X, y = y - inset.Y },
	}

	for _, point in ipairs(points) do
		local list = {}

		local ok, objects = pcall(function()
			return playerGui:GetGuiObjectsAtPosition(point.x, point.y)
		end)

		if ok and objects then
			for i, obj in ipairs(objects) do
				if i > 12 then break end
				table.insert(list, info(obj))
			end
		end

		add("click_position_scan", {
			reason = reason,
			point = point.label,
			x = math.floor(point.x),
			y = math.floor(point.y),
			count = #list,
			objects = list,
		})
	end
end

local function save(reason)
	local payload = {
		reason = reason or "save",
		placeId = game.PlaceId,
		jobId = game.JobId,
		player = player.Name,
		savedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		logs = Scan.Logs,
	}

	local ok, json = pcall(function()
		return HttpService:JSONEncode(payload)
	end)

	if writefile then
		local txt = table.concat(Scan.Lines, "\n")

		if ok then
			pcall(function() writefile(Scan.FileBase .. ".json", json) end)
			pcall(function() writefile(Scan.LatestJson, json) end)
		end

		pcall(function() writefile(Scan.FileBase .. ".txt", txt) end)
		pcall(function() writefile(Scan.LatestTxt, txt) end)
	end
end

function Scan.ScanNow(reason)
	scanGui(reason or "manual")
	save(reason or "manual")
end

function Scan.Stop(reason)
	Scan.Enabled = false

	for _, connection in ipairs(Scan.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	save(reason or "stop")
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(Scan.Connections, c)
	return c
end

local remote
pcall(function()
	remote = ReplicatedStorage:WaitForChild("Modules", 10)
		:WaitForChild("Events", 10)
		:WaitForChild("RemoteEvent", 10)
end)

if remote and remote:IsA("RemoteEvent") then
	connect(remote.OnClientEvent, function(action, data)
		add("remote_in", {
			action = tostring(action),
			dataType = typeof(data),
		})

		local actionText = tostring(action):lower()
		if actionText:find("mining", 1, true)
			or actionText:find("ore", 1, true)
			or actionText:find("catch", 1, true)
			or actionText:find("collect", 1, true) then
			scanGui("remote_" .. tostring(action))
		end
	end)
end

connect(UserInputService.InputBegan, function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.F6 then
		scanGui("F6")
		save("F6")
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		local pos = input.Position

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pos = UserInputService:GetMouseLocation()
		end

		add("input_click", {
			gameProcessed = gameProcessed,
			x = math.floor(pos.X),
			y = math.floor(pos.Y),
		})

		scanClickPosition(pos.X, pos.Y, "click")
	end
end)

connect(playerGui.DescendantAdded, function(obj)
	if obj:IsA("TextButton") or obj:IsA("ImageButton") or isInteresting(obj) then
		if isInteresting(obj) then
			add("interesting_added", info(obj))
		end
	end
end)

scanGui("start")
save("start")
