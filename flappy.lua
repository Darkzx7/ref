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

	local pipeSpeed = 42
	local lastPipePositions = {}

	local function updatePipeSpeed()
		local now = tick()
		local total = 0
		local count = 0

		for _, obj in ipairs(GameArea:GetChildren()) do
			if isPipe(obj) then
				local r = getGuiBounds(obj)
				local old = lastPipePositions[obj]

				if old then
					local dt = math.max(now - old.t, 1 / 240)
					local speed = (old.left - r.left) / dt

					if speed > 18 and speed < 100 then
						total = total + speed
						count = count + 1
					end
				end

				lastPipePositions[obj] = {
					left = r.left,
					t = now,
				}
			end
		end

		for obj in pairs(lastPipePositions) do
			if not obj.Parent then
				lastPipePositions[obj] = nil
			end
		end

		if count > 0 then
			local measured = total / count
			pipeSpeed = pipeSpeed * 0.82 + measured * 0.18
			pipeSpeed = clamp(pipeSpeed, 32, 76)
		end
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

		if rawHeight <= b.height + 4 then
			return nil
		end

		local dist = col.left - b.cx

		local topClearance = math.clamp(b.height * 0.42, 4.3, 6.4)
		local bottomClearance = math.clamp(b.height * 0.50, 5.0, 7.2)

		if dist < 36 then
			topClearance = topClearance + 0.8
			bottomClearance = bottomClearance + 0.9
		end

		if dist < 16 then
			topClearance = topClearance + 0.7
			bottomClearance = bottomClearance + 0.8
		end

		local maxTotalClearance = rawHeight - b.height - 4

		if maxTotalClearance < 2 then
			maxTotalClearance = 2
		end

		if topClearance + bottomClearance > maxTotalClearance then
			local scale = maxTotalClearance / math.max(topClearance + bottomClearance, 1)
			topClearance = topClearance * scale
			bottomClearance = bottomClearance * scale
		end

		topClearance = math.max(topClearance, 2.4)
		bottomClearance = math.max(bottomClearance, 2.8)

		local safeTop = rawTop + topClearance
		local safeBottom = rawBottom - bottomClearance
		local safeHeight = safeBottom - safeTop

		if safeHeight < b.height + 2 then
			local remaining = rawHeight - b.height - 2

			if remaining < 2 then
				remaining = 2
			end

			topClearance = remaining * 0.44
			bottomClearance = remaining * 0.56

			safeTop = rawTop + topClearance
			safeBottom = rawBottom - bottomClearance
			safeHeight = safeBottom - safeTop
		end

		local minCenter = rawTop + b.height / 2 + topClearance
		local maxCenter = rawBottom - b.height / 2 - bottomClearance

		if minCenter > maxCenter then
			local mid = (rawTop + rawBottom) / 2
			minCenter = mid - 1
			maxCenter = mid + 1
		end

		return {
			left = col.left,
			right = col.right,
			dist = dist,

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
			if col.right >= b.cx - b.width * 0.9 then
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

	local function predictY(b, vel, t, tapped)
		local gravity = 680
		local tapImpulse = -165
		local v = tapped and tapImpulse or vel
		local y = b.cy + v * t + 0.5 * gravity * t * t
		local newV = v + gravity * t

		return y, newV
	end

	local function timeToColumn(b, c)
		if c.left <= b.right and c.right >= b.left then
			return 0
		end

		local t = (c.left - b.right) / math.max(pipeSpeed, 30)
		return clamp(t, 0, 0.95)
	end

	local function scoreAction(tapped, b, vel, corridors)
		local risk = tapped and 30 or 0
		local areaTop = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		for i = 1, math.min(#corridors, 4) do
			local c = corridors[i]
			local t = timeToColumn(b, c)
			local y, v = predictY(b, vel, t, tapped)
			local top = y - b.height / 2
			local bottom = y + b.height / 2
			local weight = 1

			if i == 1 then
				weight = 4.5
			elseif i == 2 then
				weight = 2.5
			elseif i == 3 then
				weight = 1.35
			else
				weight = 0.75
			end

			if top < c.rawTop then
				risk = risk + (9000 + (c.rawTop - top) * 420) * weight
			end

			if bottom > c.rawBottom then
				risk = risk + (9000 + (bottom - c.rawBottom) * 420) * weight
			end

			if y < c.minCenter then
				local d = c.minCenter - y
				risk = risk + (d * d * 10 + d * 120) * weight
			end

			if y > c.maxCenter then
				local d = y - c.maxCenter
				risk = risk + (d * d * 10 + d * 120) * weight
			end

			if top < c.top then
				risk = risk + (c.top - top) * 35 * weight
			end

			if bottom > c.bottom then
				risk = risk + (bottom - c.bottom) * 35 * weight
			end

			local nextC = corridors[i + 1]

			if nextC then
				local nextLower = nextC.center > c.center + 12
				local nextHigher = nextC.center < c.center - 12

				if nextLower and v < -25 then
					risk = risk + 550 * weight
				end

				if nextHigher and v > 190 then
					risk = risk + 450 * weight
				end
			end

			if top < areaTop + 7 then
				risk = risk + (3000 + ((areaTop + 7) - top) * 160) * weight
			end

			if bottom > areaBottom - 20 then
				risk = risk + (3000 + (bottom - (areaBottom - 20)) * 160) * weight
			end
		end

		for _, t in ipairs({0.12, 0.24, 0.36, 0.48}) do
			local y, v = predictY(b, vel, t, tapped)
			local top = y - b.height / 2
			local bottom = y + b.height / 2

			if top < areaTop + 7 then
				risk = risk + 2500 + ((areaTop + 7) - top) * 110
			end

			if bottom > areaBottom - 20 then
				risk = risk + 2500 + (bottom - (areaBottom - 20)) * 110
			end

			if v < -150 and top < areaTop + 35 then
				risk = risk + 900
			end

			if v > 240 and bottom > areaBottom - 48 then
				risk = risk + 900
			end
		end

		return risk
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
				bias = 0.28
			elseif d12 < -16 then
				bias = 0.36
			elseif d12 < -8 then
				bias = 0.42
			elseif d12 > 28 then
				bias = 0.82
			elseif d12 > 16 then
				bias = 0.74
			elseif d12 > 8 then
				bias = 0.65
			end

			if c3 then
				local d23 = c3.center - c2.center

				if d23 < -24 then
					bias = math.min(bias, 0.40)
				elseif d23 > 24 then
					bias = math.max(bias, 0.68)
				end
			end

			local exitY = c1.top + c1.height * bias
			local timeToC1 = c1.dist / math.max(pipeSpeed, 30)
			local prep = 0

			if timeToC1 < 1.60 then
				prep = 0.20
			end

			if timeToC1 < 1.20 then
				prep = 0.38
			end

			if timeToC1 < 0.85 then
				prep = 0.58
			end

			if timeToC1 < 0.55 then
				prep = 0.78
			end

			if timeToC1 < 0.30 then
				prep = 0.96
			end

			target = lerp(c1.center, exitY, prep)
		end

		local futureMin = c1.minCenter
		local futureMax = c1.maxCenter

		for i = 1, math.min(#corridors, 3) do
			local c = corridors[i]

			if c.dist < 120 then
				futureMin = math.max(futureMin, c.minCenter)
				futureMax = math.min(futureMax, c.maxCenter)
			end
		end

		if futureMin <= futureMax and c1.dist < 85 then
			target = clamp(target, futureMin, futureMax)
		else
			target = clamp(target, c1.minCenter, c1.maxCenter)
		end

		if c1.dist < 24 then
			target = clamp(target, c1.minCenter + 2, c1.maxCenter - 2)
		end

		return target, c1, c2, c3
	end

	local lastTap = 0
	local lastY
	local lastTime = tick()
	local velY = 0
	local smoothVelY = 0
	local lastTarget
	local noTapUntil = 0
	local postTapLockUntil = 0

	local MIN_INTERVAL = 0.092
	local FAST_INTERVAL = 0.054

	RunService.Heartbeat:Connect(function()
		if not Enabled then
			return
		end

		if not bird or not bird.Parent then
			scanBird()
			return
		end

		updatePipeSpeed()

		local now = tick()
		local b = getRect(bird)

		if lastY then
			local dt = math.max(now - lastTime, 1 / 240)
			velY = (b.cy - lastY) / dt
			smoothVelY = smoothVelY * 0.52 + velY * 0.48
		end

		lastY = b.cy
		lastTime = now

		local corridors = getCorridors()
		local target, c1, c2 = computeTarget(corridors, b, smoothVelY)

		if not target or not c1 then
			return
		end

		if lastTarget then
			local maxStep = 8.5
			local diff = target - lastTarget

			if diff > maxStep then
				target = lastTarget + maxStep
			elseif diff < -maxStep then
				target = lastTarget - maxStep
			end

			target = lastTarget * 0.26 + target * 0.74
		end

		lastTarget = target

		local noTapRisk = scoreAction(false, b, smoothVelY, corridors)
		local tapRisk = scoreAction(true, b, smoothVelY, corridors)

		local predT = 0.13
		local predY, predVel = predictY(b, smoothVelY, predT, false)
		local predTop = predY - b.height / 2
		local predBottom = predY + b.height / 2

		local shouldTap = false
		local emergency = false

		local error = b.cy - target
		local predError = predY - target

		local topDanger = b.top <= c1.rawTop + c1.topClearance + 1 or predTop <= c1.rawTop + c1.topClearance + 2
		local bottomDanger = b.bottom >= c1.rawBottom - c1.bottomClearance - 1 or predBottom >= c1.rawBottom - c1.bottomClearance - 2

		local deadZone = 5.5

		if c1.dist < 50 then
			deadZone = 3.5
		end

		if c1.dist < 25 then
			deadZone = 2.1
		end

		if c1.dist < 12 then
			deadZone = 1.2
		end

		if noTapRisk < 1200 and not bottomDanger then
			shouldTap = false
		elseif tapRisk + 260 < noTapRisk then
			shouldTap = true
		end

		if error > deadZone and predError > deadZone and smoothVelY > -120 then
			shouldTap = true
		end

		if smoothVelY > 120 and predError > -10 then
			shouldTap = true
		end

		if bottomDanger then
			shouldTap = true
			emergency = true
		end

		if topDanger then
			shouldTap = false
			emergency = false
			noTapUntil = now + 0.13
		end

		local areaTop = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		if predTop <= areaTop + 8 then
			shouldTap = false
			emergency = false
			noTapUntil = now + 0.14
		end

		if predBottom >= areaBottom - 20 then
			shouldTap = true
			emergency = true
		end

		if smoothVelY < -115 and b.cy < target + 14 then
			shouldTap = false
			emergency = false
			noTapUntil = now + 0.085
		end

		if c2 then
			local nextLower = c2.center > c1.center + 10
			local nextMuchLower = c2.center > c1.center + 20
			local nextHigher = c2.center < c1.center - 12

			if nextLower and (b.cy < target + 4 or smoothVelY < 20) then
				shouldTap = false
				emergency = false
				noTapUntil = math.max(noTapUntil, now + 0.085)
			end

			if nextMuchLower and smoothVelY < 60 then
				shouldTap = false
				emergency = false
				noTapUntil = math.max(noTapUntil, now + 0.11)
			end

			if nextHigher and smoothVelY > 70 and b.cy > target - 6 then
				shouldTap = true
			end
		end

		if c1.dist < b.width * 2.8 then
			if b.top <= c1.rawTop + c1.topClearance + 1.5 or predTop <= c1.rawTop + c1.topClearance + 2.5 then
				shouldTap = false
				emergency = false
				noTapUntil = now + 0.145
			end

			if b.bottom >= c1.rawBottom - c1.bottomClearance - 1.5 or predBottom >= c1.rawBottom - c1.bottomClearance - 2.5 then
				shouldTap = true
				emergency = true
			end
		end

		if now < noTapUntil and not emergency then
			shouldTap = false
		end

		if now < postTapLockUntil and not emergency then
			shouldTap = false
		end

		local interval = emergency and FAST_INTERVAL or MIN_INTERVAL

		if shouldTap and (now - lastTap) >= interval then
			tap()
			lastTap = now

			if c2 and c2.center > c1.center + 10 then
				postTapLockUntil = now + 0.13
			else
				postTapLockUntil = now + 0.075
			end
		end
	end)

	print("Auto Flappy gate-risk iniciado.")
end)

updateUI()
print("Auto Flappy UI criada.")
