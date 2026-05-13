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
	Toggle.Text = Enabled and "Auto Flappy: ON" or "Auto Flappy: OFF"
	Toggle.BackgroundColor3 = Enabled and Color3.fromRGB(50, 160, 230) or Color3.fromRGB(170, 55, 55)
end

Toggle.MouseButton1Click:Connect(function()
	Enabled = not Enabled
	updateUI()
end)

task.spawn(function()
	local BaseFlappy
	while true do
		local ok = pcall(function() BaseFlappy = PlayerGui.Game.Sections.ParkPhoneUI.BaseFlappy end)
		if ok and BaseFlappy then break end
		task.wait(0.5)
	end

	local GameArea   = BaseFlappy:WaitForChild("GameArea", 30)
	local TapOverlay = GameArea:WaitForChild("TapOverlay", 30)

	local GRAVITY     = 680
	local TAP_IMPULSE = -165
	local SIM_DT      = 1 / 60
	local SIM_STEPS   = 60
	local PIPE_PAT    = "^Pipe_%d+_([TB])$"
	local COL_X_TOL   = 2

	local function tap()
		if typeof(firesignal) == "function" then
			pcall(firesignal, TapOverlay.MouseButton1Down)
			pcall(firesignal, TapOverlay.MouseButton1Click)
		end
		if typeof(firebutton) == "function" then pcall(firebutton, TapOverlay, "") end
		pcall(function() TapOverlay:Activate() end)
	end

	local function getRect(obj)
		local p = obj.AbsolutePosition
		local s = obj.AbsoluteSize
		return {
			left   = p.X,
			right  = p.X + s.X,
			top    = p.Y,
			bottom = p.Y + s.Y,
			cx     = p.X + s.X * 0.5,
			cy     = p.Y + s.Y * 0.5,
			width  = s.X,
			height = s.Y,
		}
	end

	local bird = nil
	local function findBird()
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Name:lower() == "bird" then
				bird = obj
				return
			end
		end
	end
	findBird()
	GameArea.ChildAdded:Connect(function(obj)
		if obj:IsA("GuiObject") and obj.Name:lower() == "bird" then bird = obj end
	end)
	GameArea.ChildRemoved:Connect(function(obj)
		if obj == bird then bird = nil end
	end)

	local pipeSpeed    = 50
	local prevPipePos  = {}

	local function measurePipeSpeed(dt)
		local newPos = {}
		local deltas = {}
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Name:match(PIPE_PAT) then
				local cx = obj.AbsolutePosition.X
				local prev = prevPipePos[obj]
				if prev and dt > 0.002 then
					local spd = (prev - cx) / dt
					if spd > 5 and spd < 600 then
						table.insert(deltas, spd)
					end
				end
				newPos[obj] = cx
			end
		end
		prevPipePos = newPos
		if #deltas > 0 then
			local sum = 0
			for _, v in ipairs(deltas) do sum += v end
			local measured = sum / #deltas
			pipeSpeed = pipeSpeed * 0.75 + measured * 0.25
		end
	end

	local function getColumns(birdRight)
		local pipes = {}
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Visible then
				local side = obj.Name:match(PIPE_PAT)
				if side then
					local p = obj.AbsolutePosition
					local s = obj.AbsoluteSize
					local r = {
						left   = p.X,
						right  = p.X + s.X,
						top    = p.Y,
						bottom = p.Y + s.Y,
						cx     = p.X + s.X * 0.5,
					}
					if r.right > birdRight - 4 then
						table.insert(pipes, { r = r, side = side })
					end
				end
			end
		end

		local cols = {}
		for _, p in ipairs(pipes) do
			local found = nil
			for _, col in ipairs(cols) do
				if math.abs(p.r.cx - col.cx) <= COL_X_TOL then
					found = col
					break
				end
			end
			if not found then
				found = { cx = p.r.cx, left = p.r.left, right = p.r.right, T = nil, B = nil }
				table.insert(cols, found)
			end
			found.left  = math.min(found.left,  p.r.left)
			found.right = math.max(found.right, p.r.right)
			found.cx    = (found.left + found.right) * 0.5
			if p.side == "T" then
				if not found.T or p.r.bottom > found.T.bottom then found.T = p.r end
			else
				if not found.B or p.r.top < found.B.top then found.B = p.r end
			end
		end

		local valid = {}
		for _, col in ipairs(cols) do
			if col.T and col.B and col.B.top > col.T.bottom then
				table.insert(valid, col)
			end
		end
		table.sort(valid, function(a, b) return a.left < b.left end)
		return valid
	end

	local function buildCorridor(col, birdRect, capH, capXOverhang)
		local bodyTop    = col.T.bottom
		local bodyBottom = col.B.top

		local effTop    = bodyTop    + capH
		local effBottom = bodyBottom - capH
		local effH      = effBottom  - effTop

		if effH < birdRect.height + 4 then return nil end

		local halfB    = birdRect.height * 0.5
		local margin   = halfB + 2.2

		if margin * 2 >= effH then
			margin = (effH - halfB * 2) * 0.5 - 0.5
		end

		local safeTop    = effTop    + margin
		local safeBottom = effBottom - margin

		local hitLeft  = col.left  - capXOverhang
		local hitRight = col.right + capXOverhang
		local distLeft = hitLeft   - birdRect.right

		return {
			left       = col.left,
			right      = col.right,
			hitLeft    = hitLeft,
			hitRight   = hitRight,
			distLeft   = distLeft,
			bodyTop    = bodyTop,
			bodyBottom = bodyBottom,
			effTop     = effTop,
			effBottom  = effBottom,
			effH       = effH,
			safeTop    = safeTop,
			safeBottom = safeBottom,
			center     = (safeTop + safeBottom) * 0.5,
			minCY      = effTop    + halfB + 0.5,
			maxCY      = effBottom - halfB - 0.5,
		}
	end

	local function computeTarget(corridors, birdCY)
		local c1 = corridors[1]
		if not c1 then return nil end
		local c2 = corridors[2]

		local base = c1.center

		if c2 then
			local d = c2.center - c1.center

			local bias = 0.5
			if     d >  30 then bias = 0.70
			elseif d >  15 then bias = 0.60
			elseif d < -30 then bias = 0.30
			elseif d < -15 then bias = 0.40
			end

			local exitY = c1.safeTop + (c1.safeBottom - c1.safeTop) * bias

			local dl   = c1.distLeft
			local prep = 0.0
			if     dl < -8  then prep = 1.00
			elseif dl <  8  then prep = 0.90
			elseif dl <  22 then prep = 0.76
			elseif dl <  42 then prep = 0.56
			elseif dl <  68 then prep = 0.34
			elseif dl < 100 then prep = 0.16
			end

			base = c1.center + (exitY - c1.center) * prep
		end

		return math.clamp(base, c1.minCY, c1.maxCY)
	end

	local function simulate(birdRect, velY, corridors, doTap, areaTop, areaBottom)
		local y = birdRect.cy
		local v = doTap and TAP_IMPULSE or velY
		local risk = 0.0

		for i = 1, SIM_STEPS do
			v = v + GRAVITY * SIM_DT
			y = y + v       * SIM_DT

			local bTop = y - birdRect.height * 0.5
			local bBot = y + birdRect.height * 0.5

			if bTop < areaTop + 2 then
				risk += 8000 + (areaTop + 2 - bTop) * 500
			end
			if bBot > areaBottom - 2 then
				risk += 8000 + (bBot - (areaBottom - 2)) * 500
			end

			for idx = 1, math.min(#corridors, 3) do
				local c = corridors[idx]
				local w = idx == 1 and 1.0 or (idx == 2 and 0.60 or 0.30)

				local t      = i * SIM_DT
				local pLeft  = c.hitLeft  - pipeSpeed * t
				local pRight = c.hitRight - pipeSpeed * t

				local xOverlap = birdRect.right > pLeft and birdRect.left < pRight

				if xOverlap then
					if bTop < c.effTop then
						local pen = (c.effTop - bTop)
						risk += (10000 + pen * 600) * w
					elseif bBot > c.effBottom then
						local pen = (bBot - c.effBottom)
						risk += (10000 + pen * 600) * w
					else
						local topGap = y - c.effTop    - birdRect.height * 0.5
						local botGap = c.effBottom - y - birdRect.height * 0.5
						local minGap = math.min(topGap, botGap)
						if minGap < 4 then
							risk += (4 - minGap) * 220 * w
						end
					end

					if bTop < c.bodyTop or bBot > c.bodyBottom then
						risk += 3000 * w
					end
				end
			end

			if v < -155 and bTop < areaTop + 25 then risk += 1200 end
			if v >  240 and bBot > areaBottom - 35 then risk += 1200 end
		end

		return risk
	end

	local lastTap    = 0
	local lastY      = nil
	local lastTime   = tick()
	local velY       = 0
	local smoothVelY = 0
	local noTapUntil = 0
	local lastTarget = nil

	local MIN_INTERVAL  = 0.076
	local EMRG_INTERVAL = 0.042

	RunService.Heartbeat:Connect(function()
		if not Enabled then return end
		if not bird or not bird.Parent then findBird() return end

		local now  = tick()
		local b    = getRect(bird)
		local areaPos  = GameArea.AbsolutePosition
		local areaSize = GameArea.AbsoluteSize
		local aT   = areaPos.Y
		local aB   = aT + areaSize.Y

		local dt = math.max(now - lastTime, 1 / 240)
		measurePipeSpeed(dt)

		if lastY then
			velY       = (b.cy - lastY) / dt
			smoothVelY = smoothVelY * 0.42 + velY * 0.58
		end
		lastY    = b.cy
		lastTime = now

		local capH        = areaSize.Y * 0.065
		local capXOverhang = areaSize.X * 0.015

		local cols      = getColumns(b.right)
		local corridors = {}
		for _, col in ipairs(cols) do
			local c = buildCorridor(col, b, capH, capXOverhang)
			if c then table.insert(corridors, c) end
		end

		if #corridors == 0 then
			local midY = (aT + aB) * 0.5
			table.insert(corridors, {
				left = math.huge, right = math.huge,
				hitLeft = math.huge, hitRight = math.huge,
				distLeft = math.huge,
				bodyTop = aT + 8, bodyBottom = aB - 20,
				effTop = aT + 8, effBottom = aB - 20,
				effH = aB - aT - 28,
				safeTop  = aT + 18, safeBottom = aB - 30,
				center   = midY,
				minCY    = aT + b.height * 0.5 + 8,
				maxCY    = aB - b.height * 0.5 - 20,
			})
		end

		local c1 = corridors[1]

		local target = computeTarget(corridors, b.cy)
		if not target then return end

		if lastTarget then
			target = math.clamp(target, lastTarget - 10, lastTarget + 10)
			target = lastTarget * 0.25 + target * 0.75
		end
		lastTarget = target

		local predT   = math.clamp(0.065 + math.abs(smoothVelY) / 3000, 0.050, 0.115)
		local predCY  = b.cy + smoothVelY * predT + 0.5 * GRAVITY * predT * predT
		local predTop = predCY - b.height * 0.5
		local predBot = predCY + b.height * 0.5

		local riskNo  = simulate(b, smoothVelY, corridors, false, aT, aB)
		local riskTap = simulate(b, smoothVelY, corridors, true,  aT, aB)

		local err     = b.cy   - target
		local predErr = predCY - target

		local dz = 5.5
		if     c1.distLeft < 8  then dz = 1.0
		elseif c1.distLeft < 20 then dz = 2.0
		elseif c1.distLeft < 42 then dz = 3.2
		end

		local shouldTap = false
		local emergency = false

		if riskTap < riskNo - 60 then
			shouldTap = true
		end

		if err > dz and predErr > dz and smoothVelY > -80 then
			shouldTap = true
		end

		if smoothVelY > 120 and predErr > -4 then
			shouldTap = true
		end

		if b.bottom >= c1.effBottom - 4 or predBot >= c1.effBottom - 6 then
			shouldTap = true
			emergency = true
		end

		if b.top <= c1.effTop + 4 or predTop <= c1.effTop + 6 then
			shouldTap = false
			emergency = false
			noTapUntil = math.max(noTapUntil, now + 0.110)
		end

		if smoothVelY < -140 and b.cy < target + 8 then
			shouldTap = false
			emergency = false
			noTapUntil = math.max(noTapUntil, now + 0.075)
		end

		if predTop <= aT + 4 then
			shouldTap = false
			emergency = false
			noTapUntil = math.max(noTapUntil, now + 0.125)
		end

		local c2 = corridors[2]
		if c2 and not emergency then
			if c2.center > c1.center + 14 and err < 2 and smoothVelY < 12 then
				shouldTap = false
				noTapUntil = math.max(noTapUntil, now + 0.060)
			end
		end

		if c1.distLeft < b.width * 2.2 then
			if b.top <= c1.effTop + 5 or predTop <= c1.effTop + 7 then
				shouldTap = false
				emergency = false
				noTapUntil = math.max(noTapUntil, now + 0.110)
			end
			if b.bottom >= c1.effBottom - 5 or predBot >= c1.effBottom - 7 then
				shouldTap = true
				emergency = true
			end
		end

		if now < noTapUntil and not emergency then
			shouldTap = false
		end

		local interval = emergency and EMRG_INTERVAL or MIN_INTERVAL
		if shouldTap and (now - lastTap) >= interval then
			tap()
			lastTap    = now
			smoothVelY = TAP_IMPULSE
		end
	end)

	print("[AutoFlappy v4] Pronto.")
end)

updateUI()
