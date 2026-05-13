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
		if v < a then return a end
		if v > b then return b end
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

	-- FIX 1: isPipe agora aceita qualquer nome que contenha "pipe" (case-insensitive)
	-- além do padrão original, para não perder caps ou variantes de nome
	local function isPipe(obj)
		if not obj:IsA("GuiObject") or not obj.Visible then return false end
		local n = obj.Name
		-- aceita Pipe_N_T, Pipe_N_B e também nomes como "PipeTop", "PipeBottom", etc.
		if n:match("^Pipe_%d+_[TB]$") then return true end
		if n:lower():find("pipe") then return true end
		return false
	end

	local function getRect(obj)
		local p = obj.AbsolutePosition
		local s = obj.AbsoluteSize
		return {
			obj    = obj,
			name   = obj.Name,
			left   = p.X,
			right  = p.X + s.X,
			top    = p.Y,
			bottom = p.Y + s.Y,
			width  = s.X,
			height = s.Y,
			cx     = p.X + s.X / 2,
			cy     = p.Y + s.Y / 2,
		}
	end

	-- FIX 2: getGuiBounds inclui TODOS os descendentes visíveis (caps inclusos)
	-- e retorna também a largura máxima real (para detecção lateral do cap)
	local function getGuiBounds(obj)
		local p = obj.AbsolutePosition
		local s = obj.AbsoluteSize

		local left   = p.X
		local right  = p.X + s.X
		local top    = p.Y
		local bottom = p.Y + s.Y

		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("GuiObject") and d.Visible then
				local dp = d.AbsolutePosition
				local ds = d.AbsoluteSize
				left   = math.min(left,   dp.X)
				right  = math.max(right,  dp.X + ds.X)
				top    = math.min(top,    dp.Y)
				bottom = math.max(bottom, dp.Y + ds.Y)
			end
		end

		return {
			obj    = obj,
			name   = obj.Name,
			left   = left,
			right  = right,
			top    = top,
			bottom = bottom,
			width  = right - left,
			height = bottom - top,
			cx     = (left + right) / 2,
			cy     = (top + bottom) / 2,
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
					if speed > 18 and speed < 120 then
						total = total + speed
						count = count + 1
					end
				end

				lastPipePositions[obj] = { left = r.left, t = now }
			end
		end

		for obj in pairs(lastPipePositions) do
			if not obj.Parent then
				lastPipePositions[obj] = nil
			end
		end

		if count > 0 then
			local measured = total / count
			-- FIX 3: alpha menor = suavização maior, menos ruído na velocidade
			pipeSpeed = pipeSpeed * 0.88 + measured * 0.12
			pipeSpeed = clamp(pipeSpeed, 28, 90)
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

		local columns   = {}
		-- FIX 4: tolerância maior para agrupar cano+cap na mesma coluna
		local xTolerance = 14

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
					left  = r.left,
					right = r.right,
					cx    = r.cx,
					rects = {},
				}
				table.insert(columns, found)
			end

			found.left  = math.min(found.left,  r.left)
			found.right = math.max(found.right, r.right)
			found.cx    = (found.left + found.right) / 2
			table.insert(found.rects, r)
		end

		table.sort(columns, function(a, b)
			return a.left < b.left
		end)

		return columns
	end

	-- FIX 5: buildCorridor totalmente revisado
	-- • separa topo/base usando o nome _T/_B E também pela posição (acima/abaixo do meio da área)
	-- • clearances aumentados para respeitar o CAP (tampa) que é mais largo
	-- • margem lateral: se a coluna for mais larga que o corpo (tem cap), adiciona margem extra
	local function buildCorridor(col, b)
		local areaTop    = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y
		local areaMid    = (areaTop + areaBottom) / 2

		local rawTop    = areaTop
		local rawBottom = areaBottom

		-- largura mínima do corpo do cano (sem o cap) — estimativa
		-- o cap costuma ser ~20% mais largo; guardamos a maior largura vista
		local maxBodyWidth = 0

		for _, r in ipairs(col.rects) do
			maxBodyWidth = math.max(maxBodyWidth, r.width)

			local side = r.name:match("^Pipe_%d+_([TB])$")

			if side == "T" then
				-- cano de cima: sua borda inferior define o teto do corredor
				rawTop = math.max(rawTop, r.bottom)
			elseif side == "B" then
				-- cano de baixo: sua borda superior define o chão do corredor
				rawBottom = math.min(rawBottom, r.top)
			else
				-- nome não padrão: decidir pelo cy em relação ao meio da área
				if r.cy < areaMid then
					rawTop = math.max(rawTop, r.bottom)
				else
					rawBottom = math.min(rawBottom, r.top)
				end
			end
		end

		local rawHeight = rawBottom - rawTop

		-- corredor tem que caber o bird com folga mínima
		if rawHeight <= b.height + 6 then
			return nil
		end

		-- FIX 6: clearances baseados no tamanho do bird, não valores fixos minúsculos
		-- O CAP se projeta ~8-12px além do corpo — adicionamos essa margem
		local capExtra = math.max(maxBodyWidth * 0.12, 6)

		local dist = col.left - b.cx

		-- clearance base: metade do bird + margem do cap
		local baseClear = b.height * 0.52 + capExtra

		local topClearance    = baseClear
		local bottomClearance = baseClear + 1.5   -- um pouco mais embaixo (gravidade)

		-- quanto mais perto do cano, mais cauteloso
		if dist < 60 then
			topClearance    = topClearance    + 3
			bottomClearance = bottomClearance + 3.5
		end

		if dist < 30 then
			topClearance    = topClearance    + 3
			bottomClearance = bottomClearance + 3.5
		end

		if dist < 14 then
			topClearance    = topClearance    + 2
			bottomClearance = bottomClearance + 2
		end

		-- não deixar clearances maiores do que o corredor permite
		local maxTotalClearance = rawHeight - b.height - 4
		if maxTotalClearance < 2 then maxTotalClearance = 2 end

		if topClearance + bottomClearance > maxTotalClearance then
			local scale = maxTotalClearance / (topClearance + bottomClearance)
			topClearance    = topClearance    * scale
			bottomClearance = bottomClearance * scale
		end

		topClearance    = math.max(topClearance,    3.5)
		bottomClearance = math.max(bottomClearance, 4.0)

		local safeTop    = rawTop    + topClearance
		local safeBottom = rawBottom - bottomClearance
		local safeHeight = safeBottom - safeTop

		if safeHeight < b.height + 2 then
			local remaining = rawHeight - b.height - 2
			if remaining < 2 then remaining = 2 end
			topClearance    = remaining * 0.44
			bottomClearance = remaining * 0.56
			safeTop         = rawTop    + topClearance
			safeBottom      = rawBottom - bottomClearance
			safeHeight      = safeBottom - safeTop
		end

		local minCenter = rawTop    + b.height / 2 + topClearance
		local maxCenter = rawBottom - b.height / 2 - bottomClearance

		if minCenter > maxCenter then
			local mid = (rawTop + rawBottom) / 2
			minCenter = mid - 1
			maxCenter = mid + 1
		end

		return {
			left  = col.left,
			right = col.right,
			dist  = dist,

			rawTop    = rawTop,
			rawBottom = rawBottom,
			rawHeight = rawHeight,

			top    = safeTop,
			bottom = safeBottom,
			height = safeHeight,
			center = safeTop + safeHeight * 0.5,

			minCenter = minCenter,
			maxCenter = maxCenter,

			topClearance    = topClearance,
			bottomClearance = bottomClearance,
		}
	end

	local function getCorridors()
		if not bird or not bird.Parent then return {} end

		local b    = getRect(bird)
		local cols = getPipeColumns()
		local corridors = {}

		for _, col in ipairs(cols) do
			-- FIX 7: usa col.right para não ignorar colunas que já passaram pelo cx do bird
			if col.right >= b.left - b.width * 0.3 then
				local c = buildCorridor(col, b)
				if c then
					table.insert(corridors, c)
				end
			end
		end

		local areaTop    = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		if #corridors == 0 then
			table.insert(corridors, {
				left  = math.huge,
				right = math.huge,
				dist  = math.huge,

				rawTop    = areaTop  + 10,
				rawBottom = areaBottom - 24,
				rawHeight = areaBottom - areaTop - 34,

				top    = areaTop  + 18,
				bottom = areaBottom - 32,
				height = areaBottom - areaTop - 50,
				center = areaTop + (areaBottom - areaTop) * 0.48,

				minCenter = areaTop  + 26,
				maxCenter = areaBottom - 40,

				topClearance    = 8,
				bottomClearance = 8,
			})
		end

		return corridors
	end

	-- FIX 8: constantes de física calibradas — ajuste GRAVITY e TAP_IMPULSE
	-- se o bot ainda errar muito, altere esses dois valores primeiro
	local GRAVITY    = 700   -- px/s² (original era 680)
	local TAP_IMPULSE = -170  -- px/s  (original era -165)

	local function predictY(birdCy, vel, t, tapped)
		local v = tapped and TAP_IMPULSE or vel
		local y = birdCy + v * t + 0.5 * GRAVITY * t * t
		local newV = v + GRAVITY * t
		return y, newV
	end

	local function timeToColumn(b, c)
		-- FIX 9: usa b.right (borda direita do bird) vs col.left para tempo real de chegada
		if c.left <= b.right and c.right >= b.left then
			return 0
		end
		local t = (c.left - b.right) / math.max(pipeSpeed, 30)
		return clamp(t, 0, 1.2)
	end

	local function scoreAction(tapped, b, vel, corridors)
		local risk    = tapped and 25 or 0
		local areaTop    = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		for i = 1, math.min(#corridors, 4) do
			local c = corridors[i]
			local t = timeToColumn(b, c)
			local y, v = predictY(b.cy, vel, t, tapped)
			local top    = y - b.height / 2
			local bottom = y + b.height / 2

			local weight = 1
			if i == 1 then
				weight = 5.0
			elseif i == 2 then
				weight = 2.5
			elseif i == 3 then
				weight = 1.2
			else
				weight = 0.6
			end

			-- colisão real (rawTop/rawBottom) — penalidade máxima
			if top < c.rawTop then
				risk = risk + (10000 + (c.rawTop - top) * 500) * weight
			end
			if bottom > c.rawBottom then
				risk = risk + (10000 + (bottom - c.rawBottom) * 500) * weight
			end

			-- zona segura (com clearance do cap)
			if y < c.minCenter then
				local d = c.minCenter - y
				risk = risk + (d * d * 12 + d * 140) * weight
			end
			if y > c.maxCenter then
				local d = y - c.maxCenter
				risk = risk + (d * d * 12 + d * 140) * weight
			end

			if top    < c.top    then risk = risk + (c.top    - top)    * 40 * weight end
			if bottom > c.bottom then risk = risk + (bottom - c.bottom) * 40 * weight end

			-- antecipação do próximo corredor
			local nextC = corridors[i + 1]
			if nextC then
				local nextLower  = nextC.center > c.center + 12
				local nextHigher = nextC.center < c.center - 12
				if nextLower  and v < -20  then risk = risk + 600 * weight end
				if nextHigher and v > 200  then risk = risk + 500 * weight end
			end

			-- bordas da área de jogo
			if top    < areaTop    + 8  then risk = risk + (3500 + ((areaTop + 8)       - top)    * 180) * weight end
			if bottom > areaBottom - 22 then risk = risk + (3500 + (bottom - (areaBottom - 22)) * 180) * weight end
		end

		-- snapshots temporais para evitar batida nas bordas entre canos
		for _, t in ipairs({0.10, 0.20, 0.32, 0.46}) do
			local y, v = predictY(b.cy, vel, t, tapped)
			local top    = y - b.height / 2
			local bottom = y + b.height / 2

			if top    < areaTop    + 8  then risk = risk + 2800 + ((areaTop + 8)       - top)    * 120 end
			if bottom > areaBottom - 22 then risk = risk + 2800 + (bottom - (areaBottom - 22)) * 120 end

			if v < -160 and top    < areaTop    + 38 then risk = risk + 1000 end
			if v >  250 and bottom > areaBottom - 50 then risk = risk + 1000 end
		end

		return risk
	end

	local function computeTarget(corridors, b, vel)
		local c1 = corridors[1]
		local c2 = corridors[2]
		local c3 = corridors[3]

		if not c1 then return nil end

		local target = c1.center

		if c2 then
			local d12  = c2.center - c1.center
			local bias = 0.50

			if     d12 < -28 then bias = 0.28
			elseif d12 < -16 then bias = 0.36
			elseif d12 <  -8 then bias = 0.42
			elseif d12 >  28 then bias = 0.82
			elseif d12 >  16 then bias = 0.74
			elseif d12 >   8 then bias = 0.65
			end

			if c3 then
				local d23 = c3.center - c2.center
				if d23 < -24 then bias = math.min(bias, 0.40) end
				if d23 >  24 then bias = math.max(bias, 0.68) end
			end

			local exitY     = c1.top + c1.height * bias
			local timeToC1  = c1.dist / math.max(pipeSpeed, 30)
			local prep      = 0

			if timeToC1 < 1.60 then prep = 0.20 end
			if timeToC1 < 1.20 then prep = 0.38 end
			if timeToC1 < 0.85 then prep = 0.58 end
			if timeToC1 < 0.55 then prep = 0.78 end
			if timeToC1 < 0.30 then prep = 0.96 end

			target = lerp(c1.center, exitY, prep)
		end

		-- restringe target à zona segura real (não a raw)
		local futureMin = c1.minCenter
		local futureMax = c1.maxCenter

		for i = 1, math.min(#corridors, 3) do
			local c = corridors[i]
			if c.dist < 130 then
				futureMin = math.max(futureMin, c.minCenter)
				futureMax = math.min(futureMax, c.maxCenter)
			end
		end

		if futureMin <= futureMax and c1.dist < 90 then
			target = clamp(target, futureMin, futureMax)
		else
			target = clamp(target, c1.minCenter, c1.maxCenter)
		end

		if c1.dist < 26 then
			target = clamp(target, c1.minCenter + 2.5, c1.maxCenter - 2.5)
		end

		return target, c1, c2, c3
	end

	local lastTap        = 0
	local lastY
	local lastTime       = tick()
	local velY           = 0
	-- FIX 10: smoothVelY com alpha menor = mais estável, menos overshooting
	local smoothVelY     = 0
	local lastTarget
	local noTapUntil     = 0
	local postTapLockUntil = 0

	-- FIX 11: intervalos revisados — tap rápido emergencial, normal com debounce seguro
	local MIN_INTERVAL  = 0.10    -- era 0.092
	local FAST_INTERVAL = 0.058   -- era 0.054

	RunService.Heartbeat:Connect(function()
		if not Enabled then return end

		if not bird or not bird.Parent then
			scanBird()
			return
		end

		updatePipeSpeed()

		local now = tick()
		local b   = getRect(bird)

		if lastY then
			local dt = math.max(now - lastTime, 1 / 240)
			velY      = (b.cy - lastY) / dt
			-- FIX 10: alpha 0.35 = mais suave que 0.48 original
			smoothVelY = smoothVelY * 0.65 + velY * 0.35
		end

		lastY    = b.cy
		lastTime = now

		local corridors = getCorridors()
		local target, c1, c2 = computeTarget(corridors, b, smoothVelY)

		if not target or not c1 then return end

		-- suavização do target (evita mudanças bruscas de objetivo)
		if lastTarget then
			local maxStep = 9
			local diff    = target - lastTarget
			if diff >  maxStep then target = lastTarget + maxStep
			elseif diff < -maxStep then target = lastTarget - maxStep
			end
			target = lastTarget * 0.28 + target * 0.72
		end
		lastTarget = target

		local noTapRisk = scoreAction(false, b, smoothVelY, corridors)
		local tapRisk   = scoreAction(true,  b, smoothVelY, corridors)

		-- FIX 12: predição com horizonte um pouco maior (0.16s)
		local predT  = 0.16
		local predY, predVel = predictY(b.cy, smoothVelY, predT, false)
		local predTop    = predY - b.height / 2
		local predBottom = predY + b.height / 2

		local shouldTap = false
		local emergency = false

		local error_now  = b.cy   - target
		local predError  = predY  - target

		-- FIX 13: topDanger e bottomDanger com clearance real do corridoro
		local topDanger    = b.top    <= c1.rawTop    + c1.topClearance    + 1.5
			or predTop    <= c1.rawTop    + c1.topClearance    + 2.5
		local bottomDanger = b.bottom >= c1.rawBottom - c1.bottomClearance - 1.5
			or predBottom >= c1.rawBottom - c1.bottomClearance - 2.5

		-- zona morta adaptativa
		local deadZone = 6
		if c1.dist < 55 then deadZone = 4   end
		if c1.dist < 28 then deadZone = 2.5 end
		if c1.dist < 14 then deadZone = 1.5 end

		-- decisão principal por risco comparado
		if noTapRisk < 1000 and not bottomDanger then
			shouldTap = false
		elseif tapRisk + 300 < noTapRisk then
			shouldTap = true
		end

		-- bird está caindo em direção ao target ou abaixo dele
		if error_now > deadZone and predError > deadZone and smoothVelY > -100 then
			shouldTap = true
		end

		if smoothVelY > 130 and predError > -8 then
			shouldTap = true
		end

		-- emergência: vai bater embaixo
		if bottomDanger then
			shouldTap  = true
			emergency  = true
		end

		-- emergência inversa: vai bater em cima — inibe tap
		if topDanger then
			shouldTap  = false
			emergency  = false
			noTapUntil = now + 0.15
		end

		local areaTop    = GameArea.AbsolutePosition.Y
		local areaBottom = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y

		if predTop <= areaTop + 9 then
			shouldTap  = false
			emergency  = false
			noTapUntil = now + 0.15
		end

		if predBottom >= areaBottom - 22 then
			shouldTap = true
			emergency = true
		end

		-- bird subindo rápido e já no target — aguarda
		if smoothVelY < -120 and b.cy < target + 16 then
			shouldTap  = false
			emergency  = false
			noTapUntil = now + 0.095
		end

		-- antecipação do próximo cano
		if c2 then
			local nextLower     = c2.center > c1.center + 10
			local nextMuchLower = c2.center > c1.center + 22
			local nextHigher    = c2.center < c1.center - 14

			if nextLower and (b.cy < target + 4 or smoothVelY < 25) then
				shouldTap  = false
				emergency  = false
				noTapUntil = math.max(noTapUntil, now + 0.095)
			end

			if nextMuchLower and smoothVelY < 65 then
				shouldTap  = false
				emergency  = false
				noTapUntil = math.max(noTapUntil, now + 0.12)
			end

			if nextHigher and smoothVelY > 75 and b.cy > target - 7 then
				shouldTap = true
			end
		end

		-- FIX 14: zona crítica perto do cano usa clearance real com margem extra
		local critDist = b.width * 3.0
		if c1.dist < critDist then
			-- muito perto do topo do vão
			if b.top    <= c1.rawTop    + c1.topClearance    + 2
			or predTop  <= c1.rawTop    + c1.topClearance    + 3 then
				shouldTap  = false
				emergency  = false
				noTapUntil = now + 0.16
			end

			-- muito perto do fundo do vão
			if b.bottom  >= c1.rawBottom - c1.bottomClearance - 2
			or predBottom >= c1.rawBottom - c1.bottomClearance - 3 then
				shouldTap = true
				emergency = true
			end
		end

		-- respeita travas de tempo (exceto emergência)
		if now < noTapUntil       and not emergency then shouldTap = false end
		if now < postTapLockUntil and not emergency then shouldTap = false end

		local interval = emergency and FAST_INTERVAL or MIN_INTERVAL

		if shouldTap and (now - lastTap) >= interval then
			tap()
			lastTap = now

			-- FIX 15: lock pós-tap maior para não tapear duas vezes no mesmo flap
			if c2 and c2.center > c1.center + 10 then
				postTapLockUntil = now + 0.16
			else
				postTapLockUntil = now + 0.095
			end
		end
	end)

	print("Auto Flappy gate-risk v2 iniciado.")
end)

updateUI()
print("Auto Flappy UI criada.")
