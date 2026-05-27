local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

if getgenv().RefOreMinerScanner and getgenv().RefOreMinerScanner.Stop then
	pcall(function()
		getgenv().RefOreMinerScanner.Stop("restart")
	end)
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Scanner = {
	Enabled = true,
	StartedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	FileBase = "ref_ore_miner_scan_" .. tostring(os.time()),
	Logs = {},
	Lines = {},
	Connections = {},
	MaxLogs = 9000,
	LastFlush = 0,
	LastSnapshot = 0,
	LastCandidateDump = 0,
}

getgenv().RefOreMinerScanner = Scanner

local function now()
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
	if not parent then return nil end

	local children = parent:GetChildren()

	for index, child in ipairs(children) do
		if child == obj then
			return index
		end
	end

	return nil
end

local function indexedPathFromPlayerGui(obj)
	if not obj then return "nil" end

	local chain = {}
	local node = obj

	while node and node ~= playerGui do
		local index = childIndex(node) or 0
		table.insert(chain, 1, string.format(":GetChildren()[%d](%s)", index, node.Name))
		node = node.Parent
	end

	if node == playerGui then
		return "PlayerGui" .. table.concat(chain, "")
	end

	return safeFullName(obj)
end

local function visibleChain(obj)
	if not obj or not obj.Parent then
		return false
	end

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

local function instanceInfo(obj)
	local data = {
		class = obj and obj.ClassName or "nil",
		name = obj and obj.Name or "nil",
		fullName = obj and safeFullName(obj) or "nil",
		indexedPath = obj and indexedPathFromPlayerGui(obj) or "nil",
	}

	if obj and obj:IsA("GuiObject") then
		data.visible = obj.Visible
		data.visibleChain = visibleChain(obj)
		data.active = obj.Active
		data.selectable = obj.Selectable
		data.zIndex = obj.ZIndex
		data.layoutOrder = obj.LayoutOrder
		data.text = safeText(obj)
		data.absolutePosition = {
			x = math.floor(obj.AbsolutePosition.X),
			y = math.floor(obj.AbsolutePosition.Y),
		}
		data.absoluteSize = {
			x = math.floor(obj.AbsoluteSize.X),
			y = math.floor(obj.AbsoluteSize.Y),
		}
	end

	if obj and obj:IsA("LayerCollector") then
		pcall(function()
			data.enabled = obj.Enabled
			data.displayOrder = obj.DisplayOrder
			data.resetOnSpawn = obj.ResetOnSpawn
		end)
	end

	return data
end

local function simplify(value, depth)
	depth = depth or 0

	if depth > 3 then
		return tostring(value)
	end

	local t = typeof(value)

	if t == "Instance" then
		return {
			type = "Instance",
			class = value.ClassName,
			name = value.Name,
			fullName = safeFullName(value),
			indexedPath = value:IsDescendantOf(playerGui) and indexedPathFromPlayerGui(value) or nil,
		}
	elseif t == "Vector2" then
		return { type = "Vector2", x = value.X, y = value.Y }
	elseif t == "Vector3" then
		return { type = "Vector3", x = value.X, y = value.Y, z = value.Z }
	elseif t == "CFrame" then
		local p = value.Position
		return { type = "CFrame", x = p.X, y = p.Y, z = p.Z }
	elseif t == "EnumItem" then
		return tostring(value)
	elseif type(value) == "table" then
		local out = {}
		local count = 0

		for k, v in pairs(value) do
			count += 1
			if count > 30 then
				out.__truncated = true
				break
			end

			out[tostring(k)] = simplify(v, depth + 1)
		end

		return out
	end

	return value
end

local function lineFromData(event, data)
	local parts = { "[" .. now() .. "]", event }

	if data then
		if data.action then table.insert(parts, "action=" .. tostring(data.action)) end
		if data.reason then table.insert(parts, "reason=" .. tostring(data.reason)) end
		if data.path then table.insert(parts, "path=" .. tostring(data.path)) end
		if data.text then table.insert(parts, "text=" .. tostring(data.text)) end
		if data.class then table.insert(parts, "class=" .. tostring(data.class)) end
		if data.name then table.insert(parts, "name=" .. tostring(data.name)) end
	end

	return table.concat(parts, " | ")
end

local function log(event, data)
	if not Scanner.Enabled then return end

	data = data or {}
	data.t = now()
	data.event = event

	table.insert(Scanner.Logs, data)
	table.insert(Scanner.Lines, lineFromData(event, data))

	if #Scanner.Logs > Scanner.MaxLogs then
		table.remove(Scanner.Logs, 1)
	end

	if #Scanner.Lines > Scanner.MaxLogs then
		table.remove(Scanner.Lines, 1)
	end
end

local function flush(reason)
	local payload = {
		reason = reason or "flush",
		startedAt = Scanner.StartedAt,
		flushedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		placeId = game.PlaceId,
		jobId = game.JobId,
		player = player.Name,
		logCount = #Scanner.Logs,
		logs = Scanner.Logs,
	}

	local jsonName = Scanner.FileBase .. ".json"
	local txtName = Scanner.FileBase .. ".txt"

	local okJson, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)

	if writefile then
		if okJson then
			pcall(function()
				writefile(jsonName, encoded)
			end)
		end

		pcall(function()
			writefile(txtName, table.concat(Scanner.Lines, "\n"))
		end)
	else
		warn("[RefOreMinerScanner] writefile nao existe nesse executor")
	end

	Scanner.LastFlush = os.clock()
	print("[RefOreMinerScanner] saved:", jsonName, txtName, "reason:", reason or "flush")
end

function Scanner.Flush(reason)
	flush(reason or "manual flush")
end

function Scanner.Stop(reason)
	Scanner.Enabled = false

	for _, connection in ipairs(Scanner.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	flush(reason or "stop")
	print("[RefOreMinerScanner] stopped")
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Scanner.Connections, connection)
	return connection
end

local function lowerBlob(...)
	local parts = {}

	for _, value in ipairs({ ... }) do
		table.insert(parts, tostring(value or ""))
	end

	return table.concat(parts, " "):lower()
end

local function isCatchRelated(obj)
	if not obj then return false end

	local blob = lowerBlob(
		obj.Name,
		obj.ClassName,
		safeFullName(obj),
		safeText(obj),
		obj.Parent and obj.Parent.Name or ""
	)

	return blob:find("catch", 1, true)
		or blob:find("captur", 1, true)
		or blob:find("collect", 1, true)
		or blob:find("colet", 1, true)
		or blob:find("claim", 1, true)
		or blob:find("release", 1, true)
		or blob:find("soltar", 1, true)
		or blob:find("pickaxe", 1, true)
end

local function scanCatchCandidates(reason)
	local candidates = {}

	for _, obj in ipairs(playerGui:GetDescendants()) do
		if obj:IsA("TextButton") or obj:IsA("ImageButton") then
			local blob = lowerBlob(obj.Name, safeText(obj), safeFullName(obj))
			local parentBlob = obj.Parent and lowerBlob(obj.Parent.Name, safeFullName(obj.Parent)) or ""

			if isCatchRelated(obj)
				or parentBlob:find("catchorrelease", 1, true)
				or parentBlob:find("frame.frame", 1, true) then
				table.insert(candidates, instanceInfo(obj))
			end
		end
	end

	log("catch_candidates", {
		reason = reason,
		count = #candidates,
		candidates = candidates,
	})
end

local function logGuiAtPosition(x, y, label)
	local positions = {}

	local inset = GuiService:GetGuiInset()
	table.insert(positions, { label = label .. "_raw", x = x, y = y })
	table.insert(positions, { label = label .. "_minus_inset", x = x - inset.X, y = y - inset.Y })
	table.insert(positions, { label = label .. "_plus_inset", x = x + inset.X, y = y + inset.Y })

	for _, pos in ipairs(positions) do
		local ok, objects = pcall(function()
			return playerGui:GetGuiObjectsAtPosition(pos.x, pos.y)
		end)

		local list = {}

		if ok and objects then
			for index, obj in ipairs(objects) do
				if index > 20 then break end
				table.insert(list, instanceInfo(obj))
			end
		end

		log("gui_at_position", {
			label = pos.label,
			x = math.floor(pos.x),
			y = math.floor(pos.y),
			count = #list,
			objects = list,
		})
	end
end

local function snapshot(reason)
	local top = {}

	for index, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("LayerCollector") then
			local info = instanceInfo(child)
			info.childIndex = index
			info.descendantCount = #child:GetDescendants()
			table.insert(top, info)
		end
	end

	log("playergui_snapshot", {
		reason = reason,
		topLevelCount = #top,
		topLevel = top,
	})

	scanCatchCandidates(reason)
end

local function logRemoteIncoming(action, data)
	log("remote_in", {
		remote = "Modules.Events.RemoteEvent",
		action = simplify(action),
		data = simplify(data),
	})
end

local remote
pcall(function()
	remote = ReplicatedStorage:WaitForChild("Modules", 10)
		:WaitForChild("Events", 10)
		:WaitForChild("RemoteEvent", 10)
end)

if remote and remote:IsA("RemoteEvent") then
	connect(remote.OnClientEvent, function(action, data)
		logRemoteIncoming(action, data)

		if tostring(action):lower():find("mining", 1, true)
			or tostring(action):lower():find("ore", 1, true) then
			task.defer(function()
				snapshot("after_remote_" .. tostring(action))
			end)
		end
	end)

	log("remote_connected", {
		path = safeFullName(remote),
	})
else
	log("remote_missing", {
		path = "ReplicatedStorage.Modules.Events.RemoteEvent",
	})
end

if hookmetamethod and getnamecallmethod then
	local oldNamecall
	local wrapper = newcclosure or function(fn) return fn end

	local ok, err = pcall(function()
		oldNamecall = hookmetamethod(game, "__namecall", wrapper(function(self, ...)
			local method = getnamecallmethod()
			local args = { ... }

			if (method == "FireServer" or method == "InvokeServer")
				and typeof(self) == "Instance"
				and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
				local full = safeFullName(self)
				local blob = full:lower()

				if blob:find("modules.events", 1, true)
					or blob:find("remoteevent", 1, true)
					or blob:find("mine", 1, true)
					or blob:find("ore", 1, true)
					or blob:find("pickaxe", 1, true) then
					log("remote_out", {
						method = method,
						remote = full,
						args = simplify(args),
					})
				end
			end

			return oldNamecall(self, ...)
		end))
	end)

	log("namecall_hook", {
		success = ok,
		error = err,
	})
else
	log("namecall_hook_missing", {
		hookmetamethod = hookmetamethod ~= nil,
		getnamecallmethod = getnamecallmethod ~= nil,
	})
end

connect(UserInputService.InputBegan, function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		local pos = input.Position

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pos = UserInputService:GetMouseLocation()
		end

		log("input_began", {
			inputType = tostring(input.UserInputType),
			keyCode = tostring(input.KeyCode),
			gameProcessed = gameProcessed,
			x = math.floor(pos.X),
			y = math.floor(pos.Y),
		})

		logGuiAtPosition(pos.X, pos.Y, "input_began")
		scanCatchCandidates("input_began")
	end
end)

connect(UserInputService.InputEnded, function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		local pos = input.Position

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pos = UserInputService:GetMouseLocation()
		end

		log("input_ended", {
			inputType = tostring(input.UserInputType),
			keyCode = tostring(input.KeyCode),
			gameProcessed = gameProcessed,
			x = math.floor(pos.X),
			y = math.floor(pos.Y),
		})

		logGuiAtPosition(pos.X, pos.Y, "input_ended")
	end
end)

connect(playerGui.ChildAdded, function(child)
	log("playergui_child_added", instanceInfo(child))

	if isCatchRelated(child) then
		task.delay(0.1, function()
			snapshot("child_added_related")
		end)
	end
end)

connect(playerGui.DescendantAdded, function(obj)
	if obj:IsA("TextButton") or obj:IsA("ImageButton") or isCatchRelated(obj) then
		log("gui_descendant_added", instanceInfo(obj))

		if isCatchRelated(obj) then
			task.delay(0.05, function()
				scanCatchCandidates("descendant_added_related")
			end)
		end
	end
end)

connect(playerGui.DescendantRemoving, function(obj)
	if obj:IsA("TextButton") or obj:IsA("ImageButton") or isCatchRelated(obj) then
		log("gui_descendant_removing", instanceInfo(obj))
	end
end)

connect(RunService.Heartbeat, function()
	if not Scanner.Enabled then return end

	if os.clock() - Scanner.LastSnapshot > 1.25 then
		Scanner.LastSnapshot = os.clock()

		local pickaxe = playerGui:FindFirstChild("Pickaxe")
		local catchIndicator = playerGui:FindFirstChild("CatchOrReleaseIndicator")
		local catchRelease = playerGui:FindFirstChild("CatchOrRelease")

		if pickaxe or catchIndicator or catchRelease then
			log("important_gui_state", {
				pickaxe = pickaxe and instanceInfo(pickaxe) or nil,
				catchIndicator = catchIndicator and instanceInfo(catchIndicator) or nil,
				catchRelease = catchRelease and instanceInfo(catchRelease) or nil,
			})
		end
	end

	if os.clock() - Scanner.LastCandidateDump > 2.5 then
		Scanner.LastCandidateDump = os.clock()
		scanCatchCandidates("periodic")
	end

	if os.clock() - Scanner.LastFlush > 3 then
		flush("auto")
	end
end)

snapshot("start")
flush("start")

print("[RefOreMinerScanner] rodando.")
print("[RefOreMinerScanner] minera e clica manualmente no Catch/Capturar.")
print("[RefOreMinerScanner] depois execute: getgenv().RefOreMinerScanner.Stop('manual stop')")
print("[RefOreMinerScanner] arquivos:", Scanner.FileBase .. ".txt", Scanner.FileBase .. ".json")
