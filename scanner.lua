local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remote = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Events"):WaitForChild("RemoteEvent")

getgenv().RefOreMiner = getgenv().RefOreMiner or {}

local Miner = getgenv().RefOreMiner
Miner.Enabled = Miner.Enabled ~= false
Miner.Debug = Miner.Debug == true
Miner.Teleport = Miner.Teleport ~= false
Miner.TryMineRemote = Miner.TryMineRemote ~= false
Miner.RemoteFinishFallback = Miner.RemoteFinishFallback ~= false
Miner.HideMouseDuringClicks = Miner.HideMouseDuringClicks ~= false
Miner.CatchAfterCircles = Miner.CatchAfterCircles ~= false
Miner.SwingDelay = tonumber(Miner.SwingDelay) or 0.18
Miner.TargetTimeout = tonumber(Miner.TargetTimeout) or 26
Miner.CircleTimeout = tonumber(Miner.CircleTimeout) or 18
Miner.CircleClickDelay = tonumber(Miner.CircleClickDelay) or 0.045
Miner.NextOreDelay = tonumber(Miner.NextOreDelay) or 0.75
Miner.TeleportOffset = Miner.TeleportOffset or Vector3.new(0, 2.35, 4.25)
Miner.Allowed = Miner.Allowed or {
	Blue = true,
	Pink = true,
	Orange = true,
	Red = true,
	Green = true,
}

local oreAliases = {
	blue = true,
	pink = true,
	orange = true,
	red = true,
	green = true,
	greenish = true,
	poisonous = true,
	terracota = true,
	terracotta = true,
	destroyed = true,
	burning = true,
	cracked = true,
}

local TOUCH_ID = 1
local seenRoots = {}
local clickedButtons = {}
local currentOre = nil
local currentOreKey = nil
local currentTool = nil
local phase = "idle"
local targetStartedAt = 0
local circleStartedAt = 0
local expectedClicks = nil
local clickedCount = 0
local waitingCollected = false
local finishing = false
local catchClicked = false
local catchClickedAt = 0
local originalMouseIconEnabled = nil
local lastCatchClick = 0

local function log(...)
	if Miner.Debug then
		print("[ref ore miner]", ...)
	end
end

local function setAutoMouseHidden(hidden)
	if not Miner.HideMouseDuringClicks then
		return
	end

	if not UserInputService then
		return
	end

	if originalMouseIconEnabled == nil then
		local ok, value = pcall(function()
			return UserInputService.MouseIconEnabled
		end)

		if ok then
			originalMouseIconEnabled = value
		else
			originalMouseIconEnabled = true
		end
	end

	pcall(function()
		UserInputService.MouseIconEnabled = not hidden
	end)
end

local function restoreMouseIcon()
	if not UserInputService then
		originalMouseIconEnabled = nil
		return
	end

	if originalMouseIconEnabled ~= nil then
		pcall(function()
			UserInputService.MouseIconEnabled = originalMouseIconEnabled
		end)
	end

	originalMouseIconEnabled = nil
end

local function cleanName(value)
	return tostring(value or ""):lower():gsub("%s+", "")
end

local function safeFullName(obj)
	local ok, value = pcall(function()
		return obj:GetFullName()
	end)

	return ok and value or tostring(obj)
end

local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function getHumanoid()
	local character = getCharacter()
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local character = getCharacter()
	return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
end

local function getObjectKey(obj)
	if not obj then return "nil" end

	local ok, id = pcall(function()
		return obj:GetDebugId()
	end)

	if ok then
		return obj.Name .. ":" .. tostring(id)
	end

	return obj:GetFullName()
end

local function isPlayerCharacterDescendant(obj)
	local node = obj

	while node and node ~= Workspace do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") and Players:GetPlayerFromCharacter(node) then
			return true
		end

		node = node.Parent
	end

	return false
end

local function isOreLikeName(name)
	return oreAliases[cleanName(name)] == true
end

local function isAllowedOreName(name)
	local cleaned = cleanName(name)

	for color, enabled in pairs(Miner.Allowed) do
		local colorName = cleanName(color)

		if enabled and (cleaned == colorName or cleaned:find(colorName, 1, true)) then
			return true
		end
	end

	if cleaned == "greenish" or cleaned == "poisonous" then
		return Miner.Allowed.Green == true
	end

	if cleaned == "terracota" or cleaned == "terracotta" then
		return Miner.Allowed.Orange == true
	end

	if cleaned == "destroyed" or cleaned == "cracked" then
		return Miner.Allowed.Blue == true
	end

	if cleaned == "burning" then
		return Miner.Allowed.Red == true
	end

	return false
end

local function getOreRoot(obj)
	if not obj or not obj.Parent then
		return nil
	end

	local root = obj

	while root and root.Parent and root.Parent ~= Workspace do
		if isOreLikeName(root.Parent.Name) or isAllowedOreName(root.Parent.Name) then
			root = root.Parent
		else
			break
		end
	end

	return root
end

local function getPivotPosition(obj)
	if not obj or not obj.Parent then
		return nil
	end

	if obj:IsA("BasePart") then
		return obj.Position
	end

	if obj:IsA("Model") then
		local ok, pivot = pcall(function()
			return obj:GetPivot()
		end)

		if ok and pivot then
			return pivot.Position
		end

		local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		return primary and primary.Position or nil
	end

	local part = obj:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function scanOres()
	table.clear(seenRoots)

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj.Parent and not isPlayerCharacterDescendant(obj) and isAllowedOreName(obj.Name) then
			local root = getOreRoot(obj)

			if root and root.Parent and not seenRoots[root] then
				local pos = getPivotPosition(root)

				if pos then
					seenRoots[root] = pos
				end
			end
		end
	end

	for color, enabled in pairs(Miner.Allowed) do
		if enabled then
			local direct = Workspace:FindFirstChild(color)

			if direct and direct.Parent and not seenRoots[direct] then
				local pos = getPivotPosition(direct)

				if pos then
					seenRoots[direct] = pos
				end
			end
		end
	end
end

local function getNearestOre()
	local root = getRoot()
	if not root then return nil end

	scanOres()

	local nearest = nil
	local nearestDistance = math.huge

	for ore, pos in pairs(seenRoots) do
		if ore and ore.Parent and pos then
			local distance = (pos - root.Position).Magnitude

			if distance < nearestDistance then
				nearest = ore
				nearestDistance = distance
			end
		end
	end

	return nearest, nearestDistance
end

local function equipPickaxe()
	local character = getCharacter()
	local humanoid = getHumanoid()

	if not character or not humanoid then
		return nil
	end

	for _, tool in ipairs(character:GetChildren()) do
		if tool:IsA("Tool") and cleanName(tool.Name):find("pickaxe", 1, true) then
			currentTool = tool
			return tool
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end

	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") and cleanName(tool.Name):find("pickaxe", 1, true) then
			pcall(function()
				humanoid:EquipTool(tool)
			end)

			task.wait(0.12)

			currentTool = tool
			return tool
		end
	end

	return nil
end

local function teleportOnceToOre(ore)
	if not Miner.Teleport then return true end

	local root = getRoot()
	local pos = getPivotPosition(ore)

	if not root or not pos then
		return false
	end

	local destination = pos + Miner.TeleportOffset

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(destination, pos)

	task.wait(0.2)
	return true
end

local function swingPickaxe()
	local tool = equipPickaxe() or currentTool

	if tool and tool.Parent then
		pcall(function()
			tool:Activate()
		end)
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local center = camera.ViewportSize / 2

		pcall(function()
			VirtualInputManager:SendMouseMoveEvent(center.X, center.Y, game)
			task.wait(0.008)
			VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
			task.wait(0.035)
			VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
		end)
	end
end

local function getPickaxeGui()
	return playerGui:FindFirstChild("Pickaxe")
end

local function getPickaxeFrame()
	local pickaxeGui = getPickaxeGui()
	if not pickaxeGui then
		return nil
	end

	return pickaxeGui:FindFirstChild("Frame") or pickaxeGui
end

local function isInsidePickaxeGui(obj)
	local pickaxeGui = getPickaxeGui()

	return pickaxeGui and obj and obj:IsDescendantOf(pickaxeGui)
end

local function isGuiVisible(obj)
	if not obj or not obj.Parent then return false end

	if obj:IsA("GuiObject") then
		if not obj.Visible then return false end
		if obj.AbsoluteSize.X <= 2 or obj.AbsoluteSize.Y <= 2 then return false end
	end

	local parent = obj.Parent

	while parent and parent ~= playerGui do
		if parent:IsA("GuiObject") and not parent.Visible then
			return false
		end

		if parent:IsA("LayerCollector") then
			local ok, enabled = pcall(function()
				return parent.Enabled
			end)

			if ok and enabled == false then
				return false
			end
		end

		parent = parent.Parent
	end

	return true
end

local function getCenter(gui)
	local pos = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return pos.X + size.X / 2, pos.Y + size.Y / 2
end

local function fireSignal(signal)
	pcall(function()
		if firesignal and signal then
			firesignal(signal)
		end
	end)

	pcall(function()
		if getconnections and signal then
			for _, connection in ipairs(getconnections(signal)) do
				if connection.Fire then
					pcall(function()
						connection:Fire()
					end)
				end

				if connection.Function then
					pcall(connection.Function)
				end
			end
		end
	end)
end

local function fireButtonSignals(button)
	if not button then return end

	fireSignal(button.Activated)
	fireSignal(button.MouseButton1Click)
	fireSignal(button.MouseButton1Down)
	fireSignal(button.MouseButton1Up)
end

local function mouseTap(x, y)
	pcall(function()
		VirtualInputManager:SendMouseMoveEvent(x, y, game)
		task.wait(0.015)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(0.045)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
end

local function mouseTapSingle(x, y)
	pcall(function()
		VirtualInputManager:SendMouseMoveEvent(x, y, game)
		task.wait(0.01)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(0.04)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
end

local function touchTap(x, y)
	pcall(function()
		VirtualInputManager:SendTouchEvent(TOUCH_ID, Enum.UserInputState.Begin, x, y)
		task.wait(0.045)
		VirtualInputManager:SendTouchEvent(TOUCH_ID, Enum.UserInputState.End, x, y)
	end)

	pcall(function()
		VirtualInputManager:SendTouchEvent(TOUCH_ID, Vector2.new(x, y), true, game)
		task.wait(0.045)
		VirtualInputManager:SendTouchEvent(TOUCH_ID, Vector2.new(x, y), false, game)
	end)
end

local function tapAt(x, y)
	local inset = GuiService:GetGuiInset()
	touchTap(x, y)
	mouseTap(x, y)
	mouseTap(x + inset.X, y + inset.Y)
end

local function isPointOwnedByButton(button, x, y)
	if not button or not isInsidePickaxeGui(button) then
		return false
	end

	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(x, y)
	end)

	if not ok or not objects or #objects == 0 then
		return true
	end

	local top = objects[1]

	if top and (top == button or top:IsDescendantOf(button)) then
		return true
	end

	for _, obj in ipairs(objects) do
		if obj == button or obj:IsDescendantOf(button) then
			return true
		end

		if isInsidePickaxeGui(obj) then
			break
		end
	end

	return false
end

local function clickGuiObject(obj)
	if not obj or not obj.Parent or not isGuiVisible(obj) then
		return false
	end

	local x, y = getCenter(obj)

	setAutoMouseHidden(true)

	pcall(function()
		GuiService.SelectedObject = obj
	end)

	fireButtonSignals(obj)

	task.wait(0.02)

	tapAt(x, y)

	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
		task.wait(0.035)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
	end)

	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
		task.wait(0.035)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
	end)

	return true
end

local function clickButton(button)
	if not button or not button.Parent or not isGuiVisible(button) or not isInsidePickaxeGui(button) then
		return false
	end

	local target = button:FindFirstChild("MiddleCircle", true)
		or button:FindFirstChild("InnerCircle", true)
		or button:FindFirstChild("AnimatedWhiteCircle", true)
		or button

	if not target or not target:IsA("GuiObject") or not isGuiVisible(target) then
		target = button
	end

	local x, y = getCenter(target)

	if not isPointOwnedByButton(button, x, y) then
		return false
	end

	setAutoMouseHidden(true)

	fireButtonSignals(button)

	task.wait(0.01)

	mouseTapSingle(x, y)

	return true
end

local function hasCircleParts(button)
	if not button or not button.Parent then
		return false
	end

	return button:FindFirstChild("AnimatedWhiteCircle", true)
		or button:FindFirstChild("MiddleCircle", true)
		or button:FindFirstChild("InnerCircle", true)
end

local function findPickaxeCircleButtons()
	local found = {}
	local pickaxeGui = getPickaxeGui()
	local frame = getPickaxeFrame()

	if not pickaxeGui or not isGuiVisible(pickaxeGui) or not frame then
		return found
	end

	local roots = { frame }

	for _, root in ipairs(roots) do
		for _, obj in ipairs(root:GetDescendants()) do
			if obj:IsA("ImageButton") and isGuiVisible(obj) and isInsidePickaxeGui(obj) and hasCircleParts(obj) then
				table.insert(found, obj)
			end
		end
	end

	table.sort(found, function(a, b)
		local ap = a.AbsolutePosition
		local bp = b.AbsolutePosition

		if math.abs(ap.Y - bp.Y) > 8 then
			return ap.Y < bp.Y
		end

		return ap.X < bp.X
	end)

	return found
end

local function getButtonText(obj)
	local txt = ""

	pcall(function()
		txt = tostring(obj.Text or "")
	end)

	return txt
end

local function cleanButtonText(txt)
	return tostring(txt or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function isCatchText(txt)
	txt = cleanButtonText(txt)

	return txt == "catch"
		or txt == "capturar"
		or txt == "captura"
		or txt == "collect"
		or txt == "coletar"
		or txt == "claim"
		or txt == "take"
		or txt == "✓"
end

local function isReleaseText(txt)
	txt = cleanButtonText(txt)

	return txt == "release"
		or txt == "soltar"
		or txt == "liberar"
		or txt == "descartar"
end

local catchButtonPaths = {
	{ "Frame", "Frame", "TextButton" },
	{ "Frame", "Frame", "Frame", "TextButton" },
	{ "Frame", "TextButton" },
	{ "TextButton" },
}

local function getPath(root, path)
	local node = root

	for _, name in ipairs(path) do
		if not node then
			return nil
		end

		node = node:FindFirstChild(name)
	end

	return node
end

local function getDeepText(obj)
	local parts = {}

	local function addText(target)
		pcall(function()
			local value = tostring(target.Text or "")

			if value ~= "" then
				table.insert(parts, value)
			end
		end)
	end

	if obj:IsA("TextButton") or obj:IsA("TextLabel") or obj:IsA("TextBox") then
		addText(obj)
	end

	for _, desc in ipairs(obj:GetDescendants()) do
		if desc:IsA("TextButton") or desc:IsA("TextLabel") or desc:IsA("TextBox") then
			addText(desc)
		end
	end

	return table.concat(parts, " ")
end

local function getNearbyText(button)
	local parts = { getDeepText(button) }
	local parent = button and button.Parent

	if parent then
		for _, child in ipairs(parent:GetChildren()) do
			if child ~= button and (child:IsA("TextButton") or child:IsA("TextLabel") or child:IsA("TextBox")) then
				table.insert(parts, getDeepText(child))
			end
		end
	end

	return table.concat(parts, " ")
end

local function isReleaseBlob(blob)
	return blob:find("release", 1, true)
		or blob:find("soltar", 1, true)
		or blob:find("liberar", 1, true)
		or blob:find("descartar", 1, true)
end

local function hasReleaseSibling(button)
	local parent = button and button.Parent
	if not parent then
		return false
	end

	for _, sibling in ipairs(parent:GetChildren()) do
		if sibling ~= button and sibling:IsA("TextButton") and isGuiVisible(sibling) and isReleaseText(getButtonText(sibling)) then
			return true
		end
	end

	return false
end

local function scoreCatchButton(button, boost)
	if not button or not button:IsA("TextButton") or not isGuiVisible(button) then
		return nil
	end

	local buttonBlob = cleanButtonText(getDeepText(button) .. " " .. tostring(button.Name or ""))

	if isReleaseBlob(buttonBlob) then
		return nil
	end

	local fullBlob = cleanButtonText(safeFullName(button))
	local nearbyBlob = cleanButtonText(getNearbyText(button))
	local blob = buttonBlob .. " " .. nearbyBlob .. " " .. fullBlob
	local score = boost or 0

	if isCatchText(buttonBlob) then score += 260 end
	if blob:find("catch", 1, true) then score += 180 end
	if blob:find("captur", 1, true) then score += 170 end
	if blob:find("collect", 1, true) or blob:find("colet", 1, true) then score += 95 end
	if blob:find("claim", 1, true) or blob:find("take", 1, true) then score += 65 end

	if hasReleaseSibling(button) then
		score += 85
	end

	if fullBlob:find("catchorreleaseindicator", 1, true) then
		score += 180
	elseif fullBlob:find("catchorrelease", 1, true) then
		score += 140
	end

	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local x, y = getCenter(button)

	if y >= viewport.Y * 0.45 and y <= viewport.Y * 0.98 then score += 25 end
	if x >= viewport.X * 0.02 and x <= viewport.X * 0.70 then score += 15 end

	return score >= 120 and score or nil
end

local function pushCatchCandidate(candidates, button, boost, source)
	local score = scoreCatchButton(button, boost)

	if score then
		table.insert(candidates, {
			button = button,
			score = score,
			source = source,
		})
	end
end

local function bestCatchCandidate(candidates)
	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	local best = candidates[1]

	if best then
		log("catch candidate", best.source, math.floor(best.score), safeFullName(best.button), getDeepText(best.button))
		return best.button
	end

	return nil
end

local function findMushCatchButton()
	local candidates = {}

	for _, rootGui in ipairs({
		playerGui:FindFirstChild("CatchOrReleaseIndicator"),
		playerGui:FindFirstChild("CatchOrRelease"),
	}) do
		if rootGui then
			for _, path in ipairs(catchButtonPaths) do
				pushCatchCandidate(candidates, getPath(rootGui, path), 220, "named_path")
			end

			for _, obj in ipairs(rootGui:GetDescendants()) do
				if obj:IsA("TextButton") then
					pushCatchCandidate(candidates, obj, 130, "named_scan")
				end
			end
		end
	end

	for _, rootGui in ipairs(playerGui:GetChildren()) do
		for _, path in ipairs(catchButtonPaths) do
			pushCatchCandidate(candidates, getPath(rootGui, path), 125, "playergui_frame_path")
		end
	end

	return bestCatchCandidate(candidates)
end

local function findComponentCatchButton()
	local candidates = {}

	for _, obj in ipairs(playerGui:GetDescendants()) do
		if obj:IsA("TextButton") then
			pushCatchCandidate(candidates, obj, 0, "global_scan")
		end
	end

	return bestCatchCandidate(candidates)
end

local function findCatchButton()
	return findMushCatchButton() or findComponentCatchButton()
end

local function clickCatchButton()
	if not Miner.CatchAfterCircles then
		return false
	end

	if os.clock() - lastCatchClick < 0.14 then
		return false
	end

	local button = findCatchButton()
	if not button then
		return false
	end

	lastCatchClick = os.clock()
	catchClicked = true
	catchClickedAt = tick()

	log("catch button", safeFullName(button), "text", getDeepText(button))

	clickGuiObject(button)
	task.wait(0.25)

	return true
end

local function completeCurrentOreAfterCircles(reason)
	if not currentOre or not currentOre.Parent then
		return false
	end

	if not Miner.RemoteFinishFallback then
		return false
	end

	catchClicked = true
	catchClickedAt = tick()

	log("complete ore after circles", reason or "direct", currentOre:GetFullName())

	pcall(function()
		Remote:FireServer("MinigameCompleted", currentOre)
	end)

	return true
end

local function resetMinigameState()
	phase = "idle"
	expectedClicks = nil
	clickedCount = 0
	waitingCollected = false
	finishing = false
	catchClicked = false
	catchClickedAt = 0
	lastCatchClick = 0
	table.clear(clickedButtons)
end

local function finishCurrentOre(reason)
	if finishing then return end

	finishing = true
	log("finish", reason or "unknown", "clicked", clickedCount, "expected", expectedClicks or "?")

	task.defer(function()
		pcall(function()
			Remote:FireServer("StopHoldingOre")
		end)

		currentOre = nil
		currentOreKey = nil
		currentTool = nil
		resetMinigameState()
		restoreMouseIcon()
		task.wait(Miner.NextOreDelay)
	end)
end

local function markCollected(reason)
	if currentOre and catchClicked and (phase == "circles" or phase == "waiting_collect") then
		finishCurrentOre(reason)
	end
end

local function solveCircleStep()
	if phase ~= "circles" or not currentOre then
		return false
	end

	local buttons = findPickaxeCircleButtons()

	if #buttons == 0 then
		if waitingCollected then
			return false
		end

		return false
	end

	for _, button in ipairs(buttons) do
		if not clickedButtons[button] then
			clickedButtons[button] = true
			clickedCount += 1

			task.wait(Miner.CircleClickDelay)
			clickButton(button)

			log("circle click", clickedCount, expectedClicks or "?")

			if expectedClicks and clickedCount >= expectedClicks then
				phase = "waiting_collect"
				waitingCollected = true

				task.spawn(function()
					for _ = 1, 55 do
						if not currentOre or not waitingCollected then
							return
						end

						clickCatchButton()

						if catchClicked then
							task.wait(0.24)
						else
							task.wait(0.08)
						end
					end
				end)

				task.delay(0.35, function()
					if currentOre and waitingCollected then
						completeCurrentOreAfterCircles("expected_clicks")
					end
				end)

				task.delay(1.15, function()
					if currentOre and waitingCollected then
						completeCurrentOreAfterCircles("retry_1")
					end
				end)

				task.delay(2.25, function()
					if currentOre and waitingCollected then
						completeCurrentOreAfterCircles("retry_2")
					end
				end)

				task.delay(8.5, function()
					if currentOre and waitingCollected and catchClicked then
						finishCurrentOre("catch_or_remote_timeout")
					end
				end)
			end

			return true
		end
	end

	return false
end

local function startOre(ore)
	if not ore or not ore.Parent then
		return false
	end

	currentOre = ore
	currentOreKey = getObjectKey(ore)
	targetStartedAt = tick()
	resetMinigameState()
	phase = "hitting"
	setAutoMouseHidden(true)

	if not equipPickaxe() then
		log("pickaxe not found")
		currentOre = nil
		currentOreKey = nil
		resetMinigameState()
		restoreMouseIcon()
		return false
	end

	if not teleportOnceToOre(ore) then
		currentOre = nil
		currentOreKey = nil
		resetMinigameState()
		restoreMouseIcon()
		return false
	end

	if Miner.TryMineRemote then
		pcall(function()
			Remote:FireServer("TryMine", ore)
		end)
	end

	log("target", ore:GetFullName())

	task.spawn(function()
		while Miner.Enabled
			and currentOre == ore
			and ore.Parent
			and phase == "hitting"
			and tick() - targetStartedAt < Miner.TargetTimeout do
			swingPickaxe()
			task.wait(Miner.SwingDelay)
		end
	end)

	return true
end

Remote.OnClientEvent:Connect(function(action, data)
	if action == "MiningMinigame" then
		if currentOre and currentOre.Parent then
			phase = "circles"
			circleStartedAt = tick()
			expectedClicks = tonumber(data and data.Clicks) or expectedClicks
			clickedCount = 0
			waitingCollected = false
			table.clear(clickedButtons)

			log("MiningMinigame", data and data.Color, data and data.ShardName, "clicks", expectedClicks or "?")
		end
	elseif action == "OresChanged" or action == "MiningDataChanged" then
		if catchClicked and currentOre and (phase == "waiting_collect" or phase == "circles") then
			task.delay(0.2, function()
				if currentOre and catchClicked then
					finishCurrentOre(action .. "_after_catch")
				end
			end)
		end
	end
end)

task.spawn(function()
	log("loaded")

	while Miner.Enabled do
		if currentOre and currentOre.Parent then
			if phase == "circles" then
				solveCircleStep()

				if tick() - circleStartedAt > Miner.CircleTimeout then
					finishCurrentOre("circle_timeout")
				end
			elseif phase == "waiting_collect" then
				clickCatchButton()

				if Miner.RemoteFinishFallback and os.clock() - lastCatchClick > 0.65 then
					completeCurrentOreAfterCircles("waiting_collect")
				end

				if catchClicked and tick() - catchClickedAt > 5 then
					finishCurrentOre("catch_or_remote_wait_timeout")
				elseif tick() - circleStartedAt > Miner.CircleTimeout + 10 then
					if catchClicked then
						finishCurrentOre("collect_timeout")
					else
						log("waiting catch/direct complete")
					end
				end
			elseif phase == "hitting" then
				if tick() - targetStartedAt > Miner.TargetTimeout then
					log("hit timeout", currentOre.Name)
					pcall(function()
						Remote:FireServer("StopHoldingOre")
					end)
					currentOre = nil
					currentOreKey = nil
					resetMinigameState()
					restoreMouseIcon()
					task.wait(0.35)
				end
			end
		else
			local ore, distance = getNearestOre()

			if ore then
				log("nearest", ore:GetFullName(), math.floor(distance or 0))
				startOre(ore)
			else
				task.wait(0.65)
			end
		end

		task.wait(0.025)
	end

	if currentOre then
		pcall(function()
			Remote:FireServer("StopHoldingOre")
		end)
	end

	currentOre = nil
	currentOreKey = nil
	currentTool = nil
	resetMinigameState()
	restoreMouseIcon()

	log("stopped")
end)

print("[ref ore miner] Pickaxe circle minigame loaded")
