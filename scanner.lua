local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

getgenv().RefMiningProbe = getgenv().RefMiningProbe or {}

local Probe = getgenv().RefMiningProbe
Probe.Enabled = Probe.Enabled ~= false
Probe.FileName = Probe.FileName or ("ref_mining_probe_" .. tostring(game.PlaceId) .. "_" .. tostring(os.time()) .. ".jsonl")
Probe.FlushInterval = tonumber(Probe.FlushInterval) or 0.75
Probe.ScanInterval = tonumber(Probe.ScanInterval) or 0.22
Probe.ActiveScanSeconds = tonumber(Probe.ActiveScanSeconds) or 18
Probe.MaxLineLength = tonumber(Probe.MaxLineLength) or 18000
Probe.MaxTotalBytes = tonumber(Probe.MaxTotalBytes) or 7 * 1024 * 1024
Probe.MaxGuiDescendants = tonumber(Probe.MaxGuiDescendants) or 1800
Probe.MaxCandidatesPerScan = tonumber(Probe.MaxCandidatesPerScan) or 80
Probe.MaxObjectsAtClick = tonumber(Probe.MaxObjectsAtClick) or 24
Probe.ScanAlways = Probe.ScanAlways == true
Probe.NoConsole = Probe.NoConsole ~= false

local Remote = nil
pcall(function()
	Remote = ReplicatedStorage:WaitForChild("Modules", 8):WaitForChild("Events", 8):WaitForChild("RemoteEvent", 8)
end)

local writeOk = type(writefile) == "function"
local appendOk = type(appendfile) == "function"
local fileName = Probe.FileName

local buffer = {}
local allLines = {}
local totalBytes = 0
local lastFlush = os.clock()
local activeUntil = 0
local lastScan = 0
local lastGuiHash = ""
local connections = {}

local oreNames = {
	Blue = true,
	Pink = true,
	Orange = true,
	Red = true,
	Green = true,
	Greenish = true,
	Poisonous = true,
	Terracota = true,
	Terracotta = true,
	Destroyed = true,
}

local guiPropertyNames = {
	"Visible",
	"Active",
	"Selectable",
	"AutoButtonColor",
	"BackgroundTransparency",
	"BackgroundColor3",
	"BorderSizePixel",
	"ZIndex",
	"LayoutOrder",
	"Rotation",
	"AnchorPoint",
	"Position",
	"Size",
	"AbsolutePosition",
	"AbsoluteSize",
	"Text",
	"TextColor3",
	"TextTransparency",
	"TextSize",
	"TextScaled",
	"Font",
	"Image",
	"ImageColor3",
	"ImageTransparency",
	"ImageRectOffset",
	"ImageRectSize",
	"ScaleType",
	"SliceCenter",
	"SliceScale",
}

local function now()
	return math.round(os.clock() * 1000) / 1000
end

local function safeFullName(obj)
	local ok, value = pcall(function()
		return obj:GetFullName()
	end)

	return ok and value or tostring(obj)
end

local function safeDebugId(obj)
	local ok, value = pcall(function()
		return obj:GetDebugId()
	end)

	return ok and value or nil
end

local function vec2(v)
	return {
		x = math.round(v.X * 1000) / 1000,
		y = math.round(v.Y * 1000) / 1000,
	}
end

local function vec3(v)
	return {
		x = math.round(v.X * 1000) / 1000,
		y = math.round(v.Y * 1000) / 1000,
		z = math.round(v.Z * 1000) / 1000,
	}
end

local function color3(v)
	return {
		r = math.round(v.R * 255),
		g = math.round(v.G * 255),
		b = math.round(v.B * 255),
	}
end

local function udim(v)
	return {
		scale = math.round(v.Scale * 1000) / 1000,
		offset = v.Offset,
	}
end

local function udim2(v)
	return {
		x = udim(v.X),
		y = udim(v.Y),
	}
end

local function cframe(v)
	local pos = v.Position
	local _, y, _ = v:ToOrientation()

	return {
		position = vec3(pos),
		yaw = math.round(math.deg(y) * 1000) / 1000,
	}
end

local function sanitize(value, depth, seen)
	depth = depth or 0
	seen = seen or {}

	if depth > 4 then
		return "<max-depth>"
	end

	local t = typeof(value)

	if t == "nil" or t == "boolean" or t == "number" or t == "string" then
		return value
	end

	if t == "Instance" then
		return {
			kind = "Instance",
			name = value.Name,
			class = value.ClassName,
			path = safeFullName(value),
			debugId = safeDebugId(value),
		}
	end

	if t == "Vector2" then return vec2(value) end
	if t == "Vector3" then return vec3(value) end
	if t == "Color3" then return color3(value) end
	if t == "UDim" then return udim(value) end
	if t == "UDim2" then return udim2(value) end
	if t == "CFrame" then return cframe(value) end

	if t == "EnumItem" then
		return tostring(value)
	end

	if t == "table" then
		if seen[value] then
			return "<cycle>"
		end

		seen[value] = true

		local result = {}
		local count = 0

		for k, v in pairs(value) do
			count += 1

			if count > 80 then
				result["__truncated"] = true
				break
			end

			local key = tostring(k)
			result[key] = sanitize(v, depth + 1, seen)
		end

		seen[value] = nil
		return result
	end

	return tostring(value)
end

local function encodeLine(kind, data)
	local payload = {
		t = now(),
		kind = kind,
		data = sanitize(data),
	}

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)

	if not ok then
		encoded = '{"t":' .. tostring(now()) .. ',"kind":"encode_error","data":"' .. tostring(kind) .. '"}'
	end

	if #encoded > Probe.MaxLineLength then
		encoded = string.sub(encoded, 1, Probe.MaxLineLength) .. '...<truncated>"}'
	end

	return encoded
end

local function flush(force)
	if #buffer == 0 then
		return
	end

	if not force and os.clock() - lastFlush < Probe.FlushInterval and #buffer < 24 then
		return
	end

	local chunk = table.concat(buffer, "\n") .. "\n"
	buffer = {}
	lastFlush = os.clock()

	if totalBytes + #chunk > Probe.MaxTotalBytes then
		return
	end

	totalBytes += #chunk

	if appendOk then
		pcall(function()
			appendfile(fileName, chunk)
		end)
	elseif writeOk then
		table.insert(allLines, chunk)

		pcall(function()
			writefile(fileName, table.concat(allLines))
		end)
	end
end

local function log(kind, data, force)
	if not Probe.Enabled then
		return
	end

	local line = encodeLine(kind, data)
	table.insert(buffer, line)

	if force or #buffer >= 24 or os.clock() - lastFlush >= Probe.FlushInterval then
		flush(force)
	end
end

local function initFile()
	if writeOk then
		pcall(function()
			writefile(fileName, "")
		end)
	end

	log("probe_started", {
		file = fileName,
		placeId = game.PlaceId,
		jobId = game.JobId,
		hasWritefile = writeOk,
		hasAppendfile = appendOk,
		hasRemote = Remote ~= nil,
		remotePath = Remote and safeFullName(Remote) or nil,
	}, true)
end

local function isGuiVisible(obj)
	if not obj or not obj.Parent then
		return false
	end

	if obj:IsA("GuiObject") then
		if not obj.Visible then
			return false
		end

		if obj.AbsoluteSize.X <= 1 or obj.AbsoluteSize.Y <= 1 then
			return false
		end
	end

	local parent = obj.Parent
	while parent and parent ~= playerGui do
		if parent:IsA("GuiObject") and not parent.Visible then
			return false
		end
		parent = parent.Parent
	end

	return true
end

local function readProp(obj, prop)
	local ok, value = pcall(function()
		return obj[prop]
	end)

	if ok then
		return sanitize(value)
	end

	return nil
end

local function getChildrenNames(obj, maxChildren)
	local children = {}
	local count = 0

	for _, child in ipairs(obj:GetChildren()) do
		count += 1

		if count > (maxChildren or 25) then
			table.insert(children, {
				truncated = true,
				remaining = #obj:GetChildren() - count + 1,
			})
			break
		end

		table.insert(children, {
			name = child.Name,
			class = child.ClassName,
		})
	end

	return children
end

local function getGuiDecorators(obj)
	local decorators = {}

	for _, child in ipairs(obj:GetChildren()) do
		if child:IsA("UICorner") then
			table.insert(decorators, {
				class = "UICorner",
				cornerRadius = sanitize(child.CornerRadius),
			})
		elseif child:IsA("UIStroke") then
			table.insert(decorators, {
				class = "UIStroke",
				color = color3(child.Color),
				transparency = child.Transparency,
				thickness = child.Thickness,
				applyStrokeMode = tostring(child.ApplyStrokeMode),
			})
		elseif child:IsA("UIScale") then
			table.insert(decorators, {
				class = "UIScale",
				scale = child.Scale,
			})
		elseif child:IsA("UIAspectRatioConstraint") then
			table.insert(decorators, {
				class = "UIAspectRatioConstraint",
				aspectRatio = child.AspectRatio,
			})
		elseif child:IsA("UIGradient") then
			table.insert(decorators, {
				class = "UIGradient",
				rotation = child.Rotation,
				enabled = child.Enabled,
			})
		end
	end

	return decorators
end

local function circleScore(obj)
	if not obj:IsA("GuiObject") then
		return 0, {}
	end

	local reasons = {}
	local score = 0
	local name = string.lower(obj.Name)
	local class = obj.ClassName
	local size = obj.AbsoluteSize

	if not isGuiVisible(obj) then
		return 0, { "not_visible" }
	end

	if obj:IsA("ImageButton") or obj:IsA("TextButton") then
		score += 18
		table.insert(reasons, "clickable_button")
	elseif obj:IsA("ImageLabel") then
		score += 9
		table.insert(reasons, "image_label")
	elseif obj:IsA("Frame") then
		score += 3
		table.insert(reasons, "frame")
	end

	if name:find("circle") then score += 40; table.insert(reasons, "name_circle") end
	if name:find("ring") then score += 30; table.insert(reasons, "name_ring") end
	if name:find("white") then score += 18; table.insert(reasons, "name_white") end
	if name:find("animated") then score += 22; table.insert(reasons, "name_animated") end
	if name:find("button") then score += 7; table.insert(reasons, "name_button") end
	if name:find("target") then score += 7; table.insert(reasons, "name_target") end
	if name:find("ore") or name:find("mine") or name:find("mining") then score += 10; table.insert(reasons, "name_mining") end
	if name:find("hook") or name:find("meter") or name:find("minigame") then score += 8; table.insert(reasons, "name_minigame") end

	if size.X > 10 and size.Y > 10 then
		score += 5
		table.insert(reasons, "visible_size")
	end

	if size.X > 0 and size.Y > 0 then
		local ratio = size.X / size.Y

		if ratio >= 0.72 and ratio <= 1.38 then
			score += 20
			table.insert(reasons, "near_square")
		end
	end

	for _, child in ipairs(obj:GetChildren()) do
		if child:IsA("UICorner") then
			score += 16
			table.insert(reasons, "has_uicorner")
		elseif child:IsA("UIStroke") then
			score += 10
			table.insert(reasons, "has_uistroke")
		elseif child.Name:lower():find("circle") then
			score += 22
			table.insert(reasons, "child_circle")
		elseif child.Name:lower():find("ring") then
			score += 14
			table.insert(reasons, "child_ring")
		end
	end

	local okImage, image = pcall(function()
		return obj.Image
	end)

	if okImage and type(image) == "string" and image ~= "" then
		score += 7
		table.insert(reasons, "has_image")
	end

	local parent = obj.Parent
	for _ = 1, 4 do
		if parent and parent ~= playerGui then
			local pname = parent.Name:lower()
			if pname:find("hook") or pname:find("meter") or pname:find("minigame") or pname:find("mine") or pname:find("ore") then
				score += 10
				table.insert(reasons, "parent_minigame_" .. parent.Name)
				break
			end
			parent = parent.Parent
		end
	end

	return score, reasons
end

local function describeGui(obj, compact)
	local data = {
		name = obj.Name,
		class = obj.ClassName,
		path = safeFullName(obj),
		debugId = safeDebugId(obj),
		parent = obj.Parent and obj.Parent.Name or nil,
		parentClass = obj.Parent and obj.Parent.ClassName or nil,
	}

	if obj:IsA("GuiObject") then
		data.visible = obj.Visible
		data.active = readProp(obj, "Active")
		data.selectable = readProp(obj, "Selectable")
		data.absolutePosition = vec2(obj.AbsolutePosition)
		data.absoluteSize = vec2(obj.AbsoluteSize)
		data.position = sanitize(obj.Position)
		data.size = sanitize(obj.Size)
		data.anchorPoint = sanitize(obj.AnchorPoint)
		data.rotation = obj.Rotation
		data.zIndex = obj.ZIndex
		data.layoutOrder = obj.LayoutOrder
		data.backgroundTransparency = obj.BackgroundTransparency
		data.backgroundColor3 = color3(obj.BackgroundColor3)
		data.borderSizePixel = obj.BorderSizePixel

		local score, reasons = circleScore(obj)
		data.circleScore = score
		data.circleReasons = reasons
	end

	if not compact then
		for _, prop in ipairs(guiPropertyNames) do
			local value = readProp(obj, prop)
			if value ~= nil then
				data[prop] = value
			end
		end

		data.decorators = getGuiDecorators(obj)
		data.children = getChildrenNames(obj, 40)
	end

	return data
end

local function screenGuiSummary(screenGui)
	local data = {
		name = screenGui.Name,
		class = screenGui.ClassName,
		path = safeFullName(screenGui),
		enabled = readProp(screenGui, "Enabled"),
		displayOrder = readProp(screenGui, "DisplayOrder"),
		resetOnSpawn = readProp(screenGui, "ResetOnSpawn"),
		ignoreGuiInset = readProp(screenGui, "IgnoreGuiInset"),
		children = getChildrenNames(screenGui, 60),
	}

	return data
end

local function scanGui(reason)
	local descendants = playerGui:GetDescendants()
	local total = #descendants
	local candidates = {}
	local screenGuis = {}
	local sampled = 0

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") or child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
			table.insert(screenGuis, screenGuiSummary(child))
		end
	end

	for _, obj in ipairs(descendants) do
		if sampled >= Probe.MaxGuiDescendants then
			break
		end

		sampled += 1

		if obj:IsA("GuiObject") then
			local score, reasons = circleScore(obj)

			if score >= 18 then
				table.insert(candidates, {
					score = score,
					reasons = reasons,
					gui = describeGui(obj, false),
				})
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	local limited = {}
	for i = 1, math.min(#candidates, Probe.MaxCandidatesPerScan) do
		limited[i] = candidates[i]
	end

	local hashParts = {}
	for i = 1, math.min(#limited, 14) do
		local item = limited[i]
		local gui = item.gui
		hashParts[i] = tostring(gui.path) .. ":" .. tostring(item.score) .. ":" .. tostring(gui.absolutePosition and gui.absolutePosition.x) .. "," .. tostring(gui.absolutePosition and gui.absolutePosition.y)
	end

	local hash = table.concat(hashParts, "|")

	if hash ~= lastGuiHash or reason ~= "periodic" then
		lastGuiHash = hash
		log("gui_scan", {
			reason = reason,
			totalDescendants = total,
			sampled = sampled,
			screenGuis = screenGuis,
			candidates = limited,
		})
	end
end

local function describeOre(obj)
	local data = {
		name = obj.Name,
		class = obj.ClassName,
		path = safeFullName(obj),
		debugId = safeDebugId(obj),
		parent = obj.Parent and obj.Parent.Name or nil,
		children = getChildrenNames(obj, 35),
	}

	if obj:IsA("BasePart") then
		data.position = vec3(obj.Position)
		data.size = vec3(obj.Size)
		data.color = color3(obj.Color)
		data.material = tostring(obj.Material)
		data.transparency = obj.Transparency
		data.canCollide = obj.CanCollide
	elseif obj:IsA("Model") then
		local ok, pivot = pcall(function()
			return obj:GetPivot()
		end)

		if ok and pivot then
			data.pivot = sanitize(pivot)
		end
	end

	return data
end

local function scanOres(reason)
	local found = {}

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if oreNames[obj.Name] or oreNames[(obj.Name or ""):gsub("%s+", "")] then
			table.insert(found, describeOre(obj))
			if #found >= 120 then
				break
			end
		end
	end

	log("ore_scan", {
		reason = reason,
		count = #found,
		ores = found,
	})
end

local function logObjectsAtPosition(x, y, inputType)
	local objects = {}

	local ok, found = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(x, y)
	end)

	if ok and found then
		for i, obj in ipairs(found) do
			if i > Probe.MaxObjectsAtClick then
				break
			end

			table.insert(objects, describeGui(obj, false))
		end
	end

	log("input_at_position", {
		inputType = tostring(inputType),
		x = x,
		y = y,
		objects = objects,
	})
end

local function describeRemoteArgs(...)
	local packed = table.pack(...)
	local result = {}

	for i = 1, packed.n do
		result[i] = sanitize(packed[i])
	end

	return result
end

initFile()
scanOres("start")
scanGui("start")
flush(true)

if Remote then
	table.insert(connections, Remote.OnClientEvent:Connect(function(...)
		local args = table.pack(...)
		local action = args[1]

		if action == "MiningMinigame" then
			activeUntil = os.clock() + Probe.ActiveScanSeconds
			log("remote_onclient_mining_minigame", {
				args = describeRemoteArgs(...),
			}, true)

			task.defer(function()
				scanOres("MiningMinigame")
				scanGui("MiningMinigame_immediate")
				task.wait(0.15)
				scanGui("MiningMinigame_0_15")
				task.wait(0.35)
				scanGui("MiningMinigame_0_50")
				task.wait(0.75)
				scanGui("MiningMinigame_1_25")
			end)
		else
			log("remote_onclient", {
				args = describeRemoteArgs(...),
			})
		end
	end))
else
	log("remote_missing", {
		expected = "ReplicatedStorage.Modules.Events.RemoteEvent",
	}, true)
end

table.insert(connections, playerGui.DescendantAdded:Connect(function(obj)
	if not Probe.Enabled then
		return
	end

	if os.clock() <= activeUntil or Probe.ScanAlways then
		task.defer(function()
			if obj and obj.Parent and (obj:IsA("GuiObject") or obj:IsA("ScreenGui") or obj:IsA("LayerCollector")) then
				log("gui_added", describeGui(obj, false))
			end
		end)
	end
end))

table.insert(connections, playerGui.DescendantRemoving:Connect(function(obj)
	if not Probe.Enabled then
		return
	end

	if os.clock() <= activeUntil or Probe.ScanAlways then
		if obj and (obj:IsA("GuiObject") or obj:IsA("ScreenGui") or obj:IsA("LayerCollector")) then
			log("gui_removing", {
				name = obj.Name,
				class = obj.ClassName,
				path = safeFullName(obj),
				debugId = safeDebugId(obj),
			})
		end
	end
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not Probe.Enabled then
		return
	end

	local inputType = input.UserInputType

	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
		local pos = input.Position
		activeUntil = math.max(activeUntil, os.clock() + 4)

		log("input_began", {
			type = tostring(inputType),
			gameProcessed = gameProcessed,
			position = vec3(pos),
		})

		logObjectsAtPosition(pos.X, pos.Y, inputType)
	end
end))

task.spawn(function()
	while Probe.Enabled do
		local clock = os.clock()

		if Probe.ScanAlways or clock <= activeUntil then
			if clock - lastScan >= Probe.ScanInterval then
				lastScan = clock
				scanGui("periodic")
			end
		end

		flush(false)
		task.wait(0.08)
	end

	log("probe_stopped", {
		file = fileName,
		totalBytes = totalBytes,
	}, true)

	for _, conn in ipairs(connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end

	flush(true)
end)

getgenv().RefMiningProbeStop = function()
	Probe.Enabled = false
end
