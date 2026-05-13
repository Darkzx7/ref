local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Enabled = true

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFlappyUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 150, 0, 45)
Main.Position = UDim2.new(0, 20, 0.5, -22)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local Toggle = Instance.new("TextButton")
Toggle.Size = UDim2.new(1, -10, 1, -10)
Toggle.Position = UDim2.new(0, 5, 0, 5)
Toggle.BackgroundColor3 = Color3.fromRGB(50, 160, 230)
Toggle.BorderSizePixel = 0
Toggle.Text = "Auto Flappy: ON"
Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
Toggle.TextSize = 14
Toggle.Font = Enum.Font.GothamBold
Toggle.Parent = Main
Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 8)

local function updateUI()
	if Enabled then
		Toggle.Text = "Auto Flappy: ON"
		Toggle.BackgroundColor3 = Color3.fromRGB(50, 160, 230)
	else
		Toggle.Text = "Auto Flappy: OFF"
		Toggle.BackgroundColor3 = Color3.fromRGB(170, 55, 55)
	end
end

Toggle.MouseButton1Click:Connect(function()
	Enabled = not Enabled
	updateUI()
end)

task.spawn(function()
	local BaseFlappy

	while true do
		local ok = pcall(function()
			BaseFlappy = PlayerGui.Game.Sections.ParkPhoneUI.BaseFlappy
		end)

		if ok and BaseFlappy then
			break
		end

		task.wait(0.5)
	end

	local GameArea = BaseFlappy:WaitForChild("GameArea", 30)
	local TapOverlay = GameArea:WaitForChild("TapOverlay", 30)

	local function tap()
		if typeof(firesignal) == "function" then
			pcall(firesignal, TapOverlay.MouseButton1Down)
			pcall(firesignal, TapOverlay.MouseButton1Click)
		end

		if typeof(firebutton) == "function" then
			pcall(firebutton, TapOverlay, "")
		end

		pcall(function()
			TapOverlay:Activate()
		end)
	end

	local function clamp(v, a, b)
		if v < a then
			return a
		end

		if v > b then
			return b
		end

		return v
	end

	local function lerp(a, b, t)
		return a + (b - a) * t
	end

	local bird

	local function scanBird()
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Name:lower():find("bird") then
				bird = obj
				return obj
			end
		end
	end

	scanBird()

	GameArea.ChildAdded:Connect(function(obj)
		if obj:IsA("GuiObject") and obj.Name:lower():find("bird") then
			bird = obj
		end
	end)

	local function isPipe(obj)
		return obj:IsA("GuiObject") and obj.Visible and obj.Name:match("^Pipe_%d+_[TB]$")
	end

	local function getRect(obj)
		local p = obj.AbsolutePosition
		local s = obj.AbsoluteSize

		return {
			obj = obj,
			name = obj.Name,
			left = p.X,
			right = p.X + s.X,
			top = p.Y,
			bottom = p.Y + s.Y,
			width = s.X,
			height = s.Y,
			cx = p.X + s.X / 2,
			cy = p.Y + s.Y / 2,
		}
	end

	local function getGuiBounds(obj)
		local p = obj.AbsolutePosition
		local s = obj.AbsoluteSize

		local left = p.X
		local right = p.X + s.X
		local top = p.Y
		local bottom = p.Y + s.Y

		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("GuiObject") and d.Visible then
				local dp = d.AbsolutePosition
				local ds = d.AbsoluteSize

				left = math.min(left, dp.X)
				right = math.max(right, dp.X + ds.X)
				top = math.min(top, dp.Y)
				bottom = math.max(bottom, dp.Y + ds.Y)
			end
		end

		return {
			obj = obj,
			name = obj.Name,
			left = left,
			right = right,
			top = top,
			bottom = bottom,
			width = right - left,
			height = bottom - top,
			cx = (left + right) / 2,
			cy = (top + bottom) / 2,
		}
	end

	local function getPipeColumns()
		local rects = {}

		for _, obj in ipairs(GameArea:GetChildren()) do
			if isPipe(obj) then
				table.insert(rects, getGuiBounds(obj))
			end
		end

		table.sort(rects, function(a, b)
			if math.abs(a.left - b.left) < 0.01 then
				return a.top < b.top
			end

			return a.left < b.left
		end)

		local columns = {}
		local xTolerance = 6

		for _, r in ipairs(rects) do
			local found

			for _, col in ipairs(columns) do
				if math.abs(r.cx - col.cx) <= xTolerance or math.abs(r.left - col.left) <= xTolerance then
					found = col
					break
				end
			end

			if not found then
				found = {
					left = r.left,
					right = r.right,
					cx = r.cx,
					rects = {},
				}

				table.insert(columns, found)
			end

			found.left = math.min(found.left, r.left)
			found.right = math.max(found.right, r.right)
			found.cx = (found.left + found.right) / 2
			table.insert(found.rects, r)
		end

		table.sort(columns, function(a, b)
			return a.left < b.left
		end)

		return columns
	end

	local function buildCorridor(col, b)
		local areaTop = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		local rawTop = areaTop
		local rawBottom = areaBottom

		for _, r in ipairs(col.rects) do
			local side = r.name:match("^Pipe_%d+_([TB])$")

			if side == "T" then
				rawTop = math.max(rawTop, r.bottom)
			elseif side == "B" then
				rawBottom = math.min(rawBottom, r.top)
			end
		end

		local rawHeight = rawBottom - rawTop

		if rawHeight <= b.height + 2 then
			return nil
		end

		local topClearance = math.clamp(b.height * 0.38, 4.2, 6.2)
		local bottomClearance = math.clamp(b.height * 0.48, 5.0, 7.2)

		if col.left - b.cx < 35 then
			topClearance += 0.8
			bottomClearance += 0.9
		end

		if col.left - b.cx < 16 then
			topClearance += 0.7
			bottomClearance += 0.8
		end

		local maxTotalClearance = rawHeight - b.height - 3

		if topClearance + bottomClearance > maxTotalClearance then
			local scale = maxTotalClearance / math.max(topClearance + bottomClearance, 1)
			topClearance *= scale
			bottomClearance *= scale
		end

		topClearance = math.max(topClearance, 2.5)
		bottomClearance = math.max(bottomClearance, 3.0)

		local safeTop = rawTop + topClearance
		local safeBottom = rawBottom - bottomClearance
		local safeHeight = safeBottom - safeTop

		if safeHeight < b.height + 2 then
			local remaining = rawHeight - b.height - 2
			topClearance = math.max(2, remaining * 0.45)
			bottomClearance = math.max(2, remaining * 0.55)
			safeTop = rawTop + topClearance
			safeBottom = rawBottom - bottomClearance
			safeHeight = safeBottom - safeTop
		end

		local minCenter = rawTop + b.height / 2 + topClearance
		local maxCenter = rawBottom - b.height / 2 - bottomClearance

		return {
			left = col.left,
			right = col.right,
			dist = col.left - b.cx,

			rawTop = rawTop,
			rawBottom = rawBottom,
			rawHeight = rawHeight,

			top = safeTop,
			bottom = safeBottom,
			height = safeHeight,
			center = safeTop + safeHeight * 0.5,

			minCenter = minCenter,
			maxCenter = maxCenter,

			topClearance = topClearance,
			bottomClearance = bottomClearance,
		}
	end

	local function getCorridors()
		if not bird or not bird.Parent then
			return {}
		end

		local b = getRect(bird)
		local cols = getPipeColumns()
		local corridors = {}

		for _, col in ipairs(cols) do
			if col.right >= b.cx - b.width * 0.85 then
				local c = buildCorridor(col, b)

				if c then
					table.insert(corridors, c)
				end
			end
		end

		local areaTop = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		if #corridors == 0 then
			table.insert(corridors, {
				left = math.huge,
				right = math.huge,
				dist = math.huge,

				rawTop = areaTop + 10,
				rawBottom = areaBottom - 24,
				rawHeight = areaBottom - areaTop - 34,

				top = areaTop + 15,
				bottom = areaBottom - 30,
				height = areaBottom - areaTop - 45,
				center = areaTop + (areaBottom - areaTop) * 0.48,

				minCenter = areaTop + 22,
				maxCenter = areaBottom - 36,

				topClearance = 5,
				bottomClearance = 6,
			})
		end

		return corridors
	end

	local function computeTarget(corridors, b, vel)
		local c1 = corridors[1]
		local c2 = corridors[2]
		local c3 = corridors[3]

		if not c1 then
			return nil
		end

		local target = c1.center

		if c2 then
			local d12 = c2.center - c1.center
			local bias = 0.50

			if d12 < -28 then
				bias = 0.30
			elseif d12 < -16 then
				bias = 0.37
			elseif d12 < -8 then
				bias = 0.43
			elseif d12 > 28 then
				bias = 0.72
			elseif d12 > 16 then
				bias = 0.64
			elseif d12 > 8 then
				bias = 0.58
			end

			if c3 then
				local d23 = c3.center - c2.center

				if d23 < -24 then
					bias = math.min(bias, 0.42)
				elseif d23 > 24 then
					bias = math.max(bias, 0.60)
				end
			end

			local exitY = c1.top + c1.height * bias
			local prep = 0

			if c1.dist < 95 then
				prep = 0.18
			end

			if c1.dist < 70 then
				prep = 0.34
			end

			if c1.dist < 48 then
				prep = 0.54
			end

			if c1.dist < 28 then
				prep = 0.76
			end

			if c1.dist < 14 then
				prep = 0.94
			end

			target = lerp(c1.center, exitY, prep)
		end

		local futureMin = c1.minCenter
		local futureMax = c1.maxCenter

		for i = 1, math.min(#corridors, 3) do
			local c = corridors[i]

			if c.dist < 100 then
				futureMin = math.max(futureMin, c.minCenter)
				futureMax = math.min(futureMax, c.maxCenter)
			end
		end

		if futureMin <= futureMax then
			if c1.dist < 60 then
				target = clamp(target, futureMin, futureMax)
			end
		else
			target = clamp(target, c1.minCenter, c1.maxCenter)
		end

		if c1.dist < 20 then
			target = clamp(target, c1.minCenter + 1.5, c1.maxCenter - 1.5)
		else
			target = clamp(target, c1.minCenter, c1.maxCenter)
		end

		if c2 then
			local d = c2.center - c1.center

			if d > 14 and vel < -20 then
				target = math.max(target, c1.center + 3)
			end

			if d < -14 and vel > 35 then
				target = math.min(target, c1.center - 3)
			end
		end

		return target, c1, c2, c3
	end

	local function estimateTapRisk(doTap, b, vel, corridors)
		local y = b.cy
		local v = vel
		local gravity = 680
		local tapImpulse = -165

		if doTap then
			v = tapImpulse
		end

		local risk = doTap and 18 or 0
		local dt = 1 / 75
		local steps = 48

		for i = 1, steps do
			local t = i * dt
			local yy = y + v * t + 0.5 * gravity * t * t
			local vv = v + gravity * t
			local top = yy - b.height / 2
			local bottom = yy + b.height / 2

			for index, c in ipairs(corridors) do
				if index > 3 then
					break
				end

				local xSoon = c.dist < 26 or (c.dist > 0 and c.dist < 85)
				local weight = index == 1 and 1 or 0.55

				if xSoon then
					if top < c.rawTop then
						risk += 4500 * weight + (c.rawTop - top) * 280 * weight
					end

					if bottom > c.rawBottom then
						risk += 4500 * weight + (bottom - c.rawBottom) * 280 * weight
					end

					if top < c.top then
						risk += (c.top - top) * 42 * weight
					end

					if bottom > c.bottom then
						risk += (bottom - c.bottom) * 42 * weight
					end

					local ideal = c.center
					local n = corridors[index + 1]

					if n then
						local d = n.center - c.center

						if d > 16 then
							ideal = c.top + c.height * 0.64
						elseif d < -16 then
							ideal = c.top + c.height * 0.36
						end
					end

					risk += math.abs(yy - ideal) * 1.25 * weight
				end
			end

			local areaTop = GameArea.AbsolutePosition.Y
			local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

			if top < areaTop + 7 then
				risk += 2600 + ((areaTop + 7) - top) * 120
			end

			if bottom > areaBottom - 20 then
				risk += 2600 + (bottom - (areaBottom - 20)) * 120
			end

			if vv < -145 and top < areaTop + 34 then
				risk += 800
			end

			if vv > 230 and bottom > areaBottom - 48 then
				risk += 800
			end
		end

		return risk
	end

	local lastTap = 0
	local lastY
	local lastTime = tick()
	local velY = 0
	local smoothVelY = 0
	local lastTarget
	local noTapUntil = 0

	local MIN_INTERVAL = 0.085
	local FAST_INTERVAL = 0.052

	RunService.Heartbeat:Connect(function()
		if not Enabled then
			return
		end

		if not bird or not bird.Parent then
			scanBird()
			return
		end

		local now = tick()
		local b = getRect(bird)

		if lastY then
			local dt = math.max(now - lastTime, 1 / 240)
			velY = (b.cy - lastY) / dt
			smoothVelY = smoothVelY * 0.60 + velY * 0.40
		end

		lastY = b.cy
		lastTime = now

		local corridors = getCorridors()
		local target, c1, c2 = computeTarget(corridors, b, smoothVelY)

		if not target or not c1 then
			return
		end

		if lastTarget then
			local maxStep = 7
			local diff = target - lastTarget

			if diff > maxStep then
				target = lastTarget + maxStep
			elseif diff < -maxStep then
				target = lastTarget - maxStep
			end

			target = lastTarget * 0.35 + target * 0.65
		end

		lastTarget = target

		local predT = 0.13
		local predY = b.cy + smoothVelY * predT
		local predTop = b.top + smoothVelY * predT
		local predBottom = b.bottom + smoothVelY * predT

		local noTapRisk = estimateTapRisk(false, b, smoothVelY, corridors)
		local tapRisk = estimateTapRisk(true, b, smoothVelY, corridors)

		local shouldTap = false
		local emergency = false

		local error = b.cy - target
		local predError = predY - target

		local topDanger = b.top <= c1.rawTop + c1.topClearance * 0.75 or predTop <= c1.rawTop + c1.topClearance
		local bottomDanger = b.bottom >= c1.rawBottom - c1.bottomClearance * 0.85 or predBottom >= c1.rawBottom - c1.bottomClearance

		local deadZone = 4.8

		if c1.dist < 50 then
			deadZone = 3.0
		end

		if c1.dist < 25 then
			deadZone = 1.8
		end

		if c1.dist < 12 then
			deadZone = 1.0
		end

		if tapRisk + 70 < noTapRisk then
			shouldTap = true
		end

		if error > deadZone and predError > deadZone and smoothVelY > -115 then
			shouldTap = true
		end

		if smoothVelY > 105 and predError > -9 then
			shouldTap = true
		end

		if bottomDanger then
			shouldTap = true
			emergency = true
		end

		if topDanger then
			shouldTap = false
			emergency = false
			noTapUntil = now + 0.10
		end

		local areaTop = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		if predTop <= areaTop + 8 then
			shouldTap = false
			emergency = false
			noTapUntil = now + 0.12
		end

		if predBottom >= areaBottom - 20 then
			shouldTap = true
			emergency = true
		end

		if smoothVelY < -110 and b.cy < target + 12 then
			shouldTap = false
			emergency = false
			noTapUntil = now + 0.065
		end

		if c2 then
			local nextLower = c2.minCenter > c1.minCenter + 5 or c2.center > c1.center + 12
			local nextHigher = c2.center < c1.center - 12

			if nextLower and (b.cy < target + 2 or smoothVelY < 10) then
				shouldTap = false
				emergency = false
				noTapUntil = math.max(noTapUntil, now + 0.06)
			end

			if nextHigher and smoothVelY > 50 and b.cy > target - 5 then
				shouldTap = true
			end
		end

		if c1.dist < b.width * 2.6 then
			if b.top <= c1.rawTop + c1.topClearance or predTop <= c1.rawTop + c1.topClearance + 1.5 then
				shouldTap = false
				emergency = false
				noTapUntil = now + 0.105
			end

			if b.bottom >= c1.rawBottom - c1.bottomClearance or predBottom >= c1.rawBottom - c1.bottomClearance - 1.5 then
				shouldTap = true
				emergency = true
			end
		end

		if now < noTapUntil and not emergency then
			shouldTap = false
		end

		local interval = emergency and FAST_INTERVAL or MIN_INTERVAL

		if shouldTap and (now - lastTap) >= interval then
			tap()
			lastTap = now
		end
	end)

	print("Auto Flappy com CAP corrigido iniciado.")
end)

updateUI()
print("Auto Flappy UI criada.")
