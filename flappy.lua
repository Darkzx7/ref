-- AutoFlappy v3 — valores calibrados com debug real
-- Bird: 10.5x10.5px (bounds com Tail: 12.5x10.5)
-- Cano corpo: 13.7px largura | Cap: 16.2px largura (1.25px cada lado)
-- Cap_T height: ~1.5px | Cap_B height: ~4.2px
-- Vão típico: ~52px | GameArea: 105x162px

local Players  = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Enabled = true

-- UI
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
	Toggle.Text  = Enabled and "Auto Flappy: ON"  or "Auto Flappy: OFF"
	Toggle.BackgroundColor3 = Enabled
		and Color3.fromRGB(50, 160, 230)
		or  Color3.fromRGB(170, 55, 55)
end

Toggle.MouseButton1Click:Connect(function()
	Enabled = not Enabled
	updateUI()
end)

-- ─── Física calibrada pelo debug ────────────────────────────────────────────
-- Ajuste GRAVITY e TAP_IMPULSE se o bot ainda errar a trajetória
local GRAVITY     =  700   -- px/s²
local TAP_IMPULSE = -168   -- px/s  (negativo = sobe)

-- Margem de segurança fixa em pixels (baseada nos dados reais)
-- Bird real com Tail = 12.5px de largura, 10.5px de altura
-- Cap_B projeta 4.2px no corredor → margem_bottom precisa cobrir isso
-- Cap_T projeta ~1.5px → margem menor em cima
local MARGIN_TOP    = 3.0  -- px acima do rawTop (cap_T é pequeno)
local MARGIN_BOTTOM = 5.0  -- px abaixo do rawBottom (cap_B é maior: 4.2px)
local BIRD_H        = 10.5 -- altura real do hitbox do bird
local BIRD_W_REAL   = 12.5 -- largura real incluindo Tail (usado p/ colisão lateral)

-- ─── Helpers ────────────────────────────────────────────────────────────────
local function clamp(v, a, b)
	return v < a and a or (v > b and b or v)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function getRect(obj)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	return {
		left   = p.X,         right  = p.X + s.X,
		top    = p.Y,         bottom = p.Y + s.Y,
		width  = s.X,         height = s.Y,
		cx     = p.X + s.X/2, cy     = p.Y + s.Y/2,
	}
end

-- retorna o bounding-box real do objeto + todos os descendentes visíveis
local function getGuiBounds(obj)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	local L, R, T, B = p.X, p.X+s.X, p.Y, p.Y+s.Y
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("GuiObject") and d.Visible then
			local dp, ds = d.AbsolutePosition, d.AbsoluteSize
			L = math.min(L, dp.X);        R = math.max(R, dp.X+ds.X)
			T = math.min(T, dp.Y);        B = math.max(B, dp.Y+ds.Y)
		end
	end
	return { left=L, right=R, top=T, bottom=B,
	         width=R-L, height=B-T, cx=(L+R)/2, cy=(T+B)/2 }
end

-- ─── Detecção de canos ──────────────────────────────────────────────────────
local function isPipe(obj)
	-- nomes confirmados pelo debug: Pipe_N_T e Pipe_N_B
	return obj:IsA("GuiObject") and obj.Visible
	       and obj.Name:match("^Pipe_%d+_[TB]$") ~= nil
end

-- ─── Velocidade dos canos (medida em runtime) ────────────────────────────────
local pipeSpeed         = 50   -- chute inicial; vai se auto-calibrar
local lastPipePositions = {}

local function updatePipeSpeed(GameArea)
	local now   = tick()
	local total, count = 0, 0
	for _, obj in ipairs(GameArea:GetChildren()) do
		if isPipe(obj) then
			local r   = getGuiBounds(obj)
			local old = lastPipePositions[obj]
			if old then
				local dt    = math.max(now - old.t, 1/240)
				local speed = (old.left - r.left) / dt
				if speed > 15 and speed < 130 then
					total = total + speed
					count = count + 1
				end
			end
			lastPipePositions[obj] = { left = r.left, t = now }
		end
	end
	-- limpa objetos removidos
	for obj in pairs(lastPipePositions) do
		if not obj.Parent then lastPipePositions[obj] = nil end
	end
	if count > 0 then
		local measured = total / count
		pipeSpeed = pipeSpeed * 0.90 + measured * 0.10
		pipeSpeed = clamp(pipeSpeed, 25, 120)
	end
end

-- ─── Agrupamento de colunas de canos ────────────────────────────────────────
local function getPipeColumns(GameArea)
	local rects = {}
	for _, obj in ipairs(GameArea:GetChildren()) do
		if isPipe(obj) then
			table.insert(rects, { r = getGuiBounds(obj), name = obj.Name })
		end
	end

	-- agrupa por cx com tolerância generosa (cap = 16.2px, corpo = 13.7px)
	local columns    = {}
	local X_TOL      = 4   -- canos do mesmo par têm cx idêntico; tolerância pequena evita
	                       -- juntar pares diferentes que por acaso estejam próximos

	for _, entry in ipairs(rects) do
		local r    = entry.r
		local found
		for _, col in ipairs(columns) do
			if math.abs(r.cx - col.cx) <= X_TOL then
				found = col; break
			end
		end
		if not found then
			found = { cx = r.cx, left = r.left, right = r.right, rects = {} }
			table.insert(columns, found)
		end
		found.left  = math.min(found.left,  r.left)
		found.right = math.max(found.right, r.right)
		found.cx    = (found.left + found.right) / 2
		table.insert(found.rects, { r = r, name = entry.name })
	end

	table.sort(columns, function(a, b) return a.left < b.left end)
	return columns
end

-- ─── Construção do corredor seguro ──────────────────────────────────────────
-- Usa os bounds REAIS (getGuiBounds já inclui caps).
-- rawTop  = fundo do cano de cima (inclui cap_T)
-- rawBottom = topo do cano de baixo (inclui cap_B que projeta para dentro do vão)
local function buildCorridor(col, birdRect, GameArea)
	local areaT = GameArea.AbsolutePosition.Y
	local areaB = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y
	local areaMid = (areaT + areaB) / 2

	local rawTop    = areaT
	local rawBottom = areaB

	for _, entry in ipairs(col.rects) do
		local r    = entry.r
		local side = entry.name:match("^Pipe_%d+_([TB])$")
		if side == "T" then
			-- cano de cima: rawTop = sua borda inferior (já inclui cap_T)
			rawTop = math.max(rawTop, r.bottom)
		elseif side == "B" then
			-- cano de baixo: rawBottom = sua borda superior (já inclui cap_B)
			rawBottom = math.min(rawBottom, r.top)
		else
			-- fallback por posição
			if r.cy < areaMid then
				rawTop = math.max(rawTop, r.bottom)
			else
				rawBottom = math.min(rawBottom, r.top)
			end
		end
	end

	local rawHeight = rawBottom - rawTop

	-- vão tem que ser maior que o bird + margens fixas
	local minNeeded = BIRD_H + MARGIN_TOP + MARGIN_BOTTOM + 2
	if rawHeight < minNeeded then
		return nil  -- corredor impossível, ignora
	end

	-- zona segura: contrai o vão pelas margens calibradas
	local safeTop    = rawTop    + MARGIN_TOP
	local safeBottom = rawBottom - MARGIN_BOTTOM
	local safeHeight = safeBottom - safeTop

	-- centro ideal do corredor (bird quer ficar aqui)
	local center = safeTop + safeHeight * 0.5

	-- limites para o CY do bird (não encostar nos extremos da zona segura)
	local halfBird  = BIRD_H / 2
	local minCenter = safeTop    + halfBird
	local maxCenter = safeBottom - halfBird

	if minCenter > maxCenter then
		local mid = (rawTop + rawBottom) / 2
		minCenter = mid - 0.5
		maxCenter = mid + 0.5
	end

	local dist = col.left - birdRect.right   -- distância da borda direita do bird até o cano

	return {
		left  = col.left,
		right = col.right,
		dist  = dist,

		rawTop    = rawTop,
		rawBottom = rawBottom,
		rawHeight = rawHeight,

		safeTop    = safeTop,
		safeBottom = safeBottom,
		safeHeight = safeHeight,
		center     = center,

		minCenter  = minCenter,
		maxCenter  = maxCenter,
	}
end

local function getCorridors(GameArea, birdRect)
	local cols     = getPipeColumns(GameArea)
	local corridors = {}

	for _, col in ipairs(cols) do
		-- inclui colunas que ainda não passaram pela borda esquerda do bird
		if col.right >= birdRect.left - 2 then
			local c = buildCorridor(col, birdRect, GameArea)
			if c then
				table.insert(corridors, c)
			end
		end
	end

	-- fallback sem canos: usa a área inteira
	if #corridors == 0 then
		local areaT = GameArea.AbsolutePosition.Y
		local areaB = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y
		local groundT = areaB - 16.2  -- altura do Ground real
		table.insert(corridors, {
			left = math.huge, right = math.huge, dist = math.huge,
			rawTop = areaT + 2, rawBottom = groundT - 2,
			safeTop = areaT + 6, safeBottom = groundT - 6,
			safeHeight = groundT - areaT - 12,
			center = areaT + (groundT - areaT) * 0.5,
			minCenter = areaT + 12, maxCenter = groundT - 12,
		})
	end

	return corridors
end

-- ─── Física ─────────────────────────────────────────────────────────────────
-- Prediz posição Y do centro do bird após t segundos
-- tapped=true aplica o impulso de tap imediatamente
local function predictY(cy, vel, t, tapped)
	local v  = tapped and TAP_IMPULSE or vel
	local y  = cy + v*t + 0.5*GRAVITY*t*t
	local nv = v  + GRAVITY*t
	return y, nv
end

-- Tempo em segundos para a borda direita do bird chegar à borda esquerda do cano
local function timeToColumn(birdRect, col)
	if col.left <= birdRect.right and col.right >= birdRect.left then
		return 0  -- bird já está dentro da coluna
	end
	local t = (col.left - birdRect.right) / math.max(pipeSpeed, 20)
	return clamp(t, 0, 1.5)
end

-- ─── Scoring de risco ────────────────────────────────────────────────────────
-- Compara custo de tapping vs não-tapping; menor score = melhor ação
local function scoreAction(tapped, birdRect, vel, corridors, GameArea)
	-- penalidade base do tap (evita taps desnecessários)
	local risk   = tapped and 20 or 0
	local areaT  = GameArea.AbsolutePosition.Y
	local areaB  = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y
	local groundT = areaB - 16.2  -- topo do chão

	local weights = { 6.0, 3.0, 1.5, 0.7 }

	for i = 1, math.min(#corridors, 4) do
		local c = corridors[i]
		local t = timeToColumn(birdRect, c)
		local y, v = predictY(birdRect.cy, vel, t, tapped)
		local top    = y - BIRD_H/2
		local bottom = y + BIRD_H/2
		local w = weights[i] or 0.5

		-- colisão com rawTop/rawBottom (zona proibida real)
		if top    < c.rawTop    then risk = risk + (12000 + (c.rawTop    - top)    * 600) * w end
		if bottom > c.rawBottom then risk = risk + (12000 + (bottom - c.rawBottom) * 600) * w end

		-- saída da zona segura (inclui margens do cap)
		if top    < c.safeTop    then risk = risk + (c.safeTop    - top)    * 60 * w end
		if bottom > c.safeBottom then risk = risk + (bottom - c.safeBottom) * 60 * w end

		-- desvio do centro seguro
		if y < c.minCenter then
			local d = c.minCenter - y
			risk = risk + (d*d*14 + d*160) * w
		end
		if y > c.maxCenter then
			local d = y - c.maxCenter
			risk = risk + (d*d*14 + d*160) * w
		end

		-- antecipação: velocidade incompatível com próximo corredor
		local next = corridors[i+1]
		if next then
			if next.center > c.center + 12 and v < -15 then risk = risk + 700 * w end
			if next.center < c.center - 12 and v > 210  then risk = risk + 600 * w end
		end

		-- teto e chão da área
		if top    < areaT   + 8  then risk = risk + (4000 + (areaT + 8 - top)      * 200) * w end
		if bottom > groundT - 4  then risk = risk + (4000 + (bottom - (groundT-4)) * 200) * w end
	end

	-- snapshots temporais (entre canos)
	for _, t in ipairs({0.08, 0.16, 0.26, 0.38}) do
		local y, v = predictY(birdRect.cy, vel, t, tapped)
		local top    = y - BIRD_H/2
		local bottom = y + BIRD_H/2
		if top    < areaT   + 8  then risk = risk + 3000 + (areaT + 8 - top)      * 130 end
		if bottom > groundT - 4  then risk = risk + 3000 + (bottom - (groundT-4)) * 130 end
		if v < -180 and top    < areaT   + 40 then risk = risk + 1200 end
		if v >  270 and bottom > groundT - 55 then risk = risk + 1200 end
	end

	return risk
end

-- ─── Cálculo do target Y ─────────────────────────────────────────────────────
local function computeTarget(corridors, vel)
	local c1 = corridors[1]
	local c2 = corridors[2]
	local c3 = corridors[3]
	if not c1 then return nil end

	local target = c1.center

	if c2 then
		local d12  = c2.center - c1.center
		local bias = 0.50
		if     d12 < -30 then bias = 0.26
		elseif d12 < -18 then bias = 0.34
		elseif d12 <  -8 then bias = 0.42
		elseif d12 >  30 then bias = 0.84
		elseif d12 >  18 then bias = 0.76
		elseif d12 >   8 then bias = 0.65
		end

		if c3 then
			local d23 = c3.center - c2.center
			if d23 < -26 then bias = math.min(bias, 0.38) end
			if d23 >  26 then bias = math.max(bias, 0.70) end
		end

		local exitY    = c1.safeTop + c1.safeHeight * bias
		local timeToC1 = math.max(c1.dist, 0) / math.max(pipeSpeed, 20)
		local prep     = 0
		if timeToC1 < 1.60 then prep = 0.18 end
		if timeToC1 < 1.20 then prep = 0.36 end
		if timeToC1 < 0.85 then prep = 0.56 end
		if timeToC1 < 0.55 then prep = 0.76 end
		if timeToC1 < 0.30 then prep = 0.95 end

		target = lerp(c1.center, exitY, prep)
	end

	-- restringe ao mínimo/máximo do corredor atual (e próximos próximos)
	local futureMin = c1.minCenter
	local futureMax = c1.maxCenter
	for i = 1, math.min(#corridors, 3) do
		local c = corridors[i]
		if c.dist < 140 then
			futureMin = math.max(futureMin, c.minCenter)
			futureMax = math.min(futureMax, c.maxCenter)
		end
	end

	if futureMin <= futureMax and c1.dist < 100 then
		target = clamp(target, futureMin, futureMax)
	else
		target = clamp(target, c1.minCenter, c1.maxCenter)
	end

	-- muito perto: aperta ainda mais
	if c1.dist < 20 then
		target = clamp(target, c1.minCenter + 1.5, c1.maxCenter - 1.5)
	end

	return target
end

-- ─── Loop principal ──────────────────────────────────────────────────────────
task.spawn(function()
	local BaseFlappy

	while true do
		local ok = pcall(function()
			BaseFlappy = PlayerGui.Game.Sections.ParkPhoneUI.BaseFlappy
		end)
		if ok and BaseFlappy then break end
		task.wait(0.5)
	end

	local GameArea   = BaseFlappy:WaitForChild("GameArea", 30)
	local TapOverlay = GameArea:WaitForChild("TapOverlay", 30)

	local function tap()
		if typeof(firesignal) == "function" then
			pcall(firesignal, TapOverlay.MouseButton1Down)
			pcall(firesignal, TapOverlay.MouseButton1Click)
		end
		if typeof(firebutton) == "function" then
			pcall(firebutton, TapOverlay, "")
		end
		pcall(function() TapOverlay:Activate() end)
	end

	local bird

	local function scanBird()
		for _, obj in ipairs(GameArea:GetChildren()) do
			if obj:IsA("GuiObject") and obj.Name == "Bird" then
				bird = obj; return obj
			end
		end
	end

	scanBird()
	GameArea.ChildAdded:Connect(function(obj)
		if obj:IsA("GuiObject") and obj.Name == "Bird" then bird = obj end
	end)

	-- estado
	local lastTap          = 0
	local lastY
	local lastTime         = tick()
	local velY             = 0
	local smoothVelY       = 0
	local lastTarget
	local noTapUntil       = 0
	local postTapLockUntil = 0

	-- intervalos mínimos entre taps
	local MIN_INTERVAL  = 0.10
	local FAST_INTERVAL = 0.055

	RunService.Heartbeat:Connect(function()
		if not Enabled then return end

		if not bird or not bird.Parent then
			scanBird(); return
		end

		updatePipeSpeed(GameArea)

		local now = tick()
		local b   = getRect(bird)

		-- estima velocidade vertical atual
		if lastY then
			local dt = math.max(now - lastTime, 1/240)
			velY      = (b.cy - lastY) / dt
			smoothVelY = smoothVelY * 0.68 + velY * 0.32
		end
		lastY    = b.cy
		lastTime = now

		-- usa b.width real (10.5) mas compensa a Tail manualmente para colisão lateral
		-- o hitbox real é ~12.5px; ajustamos left
		local birdForCollision = {
			left   = b.left   - 1.0,   -- Tail projeta ~1px à esquerda
			right  = b.right  + 0.5,   -- Beak projeta ~0.5px à direita
			top    = b.top,
			bottom = b.bottom,
			cx     = b.cx,
			cy     = b.cy,
			width  = BIRD_W_REAL,
			height = BIRD_H,
		}

		local corridors = getCorridors(GameArea, birdForCollision)
		local target    = computeTarget(corridors, smoothVelY)

		if not target then return end

		-- suaviza o target para evitar mudanças bruscas de objetivo
		if lastTarget then
			local maxStep = 9
			local diff    = target - lastTarget
			if diff >  maxStep then target = lastTarget + maxStep
			elseif diff < -maxStep then target = lastTarget - maxStep
			end
			target = lastTarget * 0.30 + target * 0.70
		end
		lastTarget = target

		local c1 = corridors[1]
		local c2 = corridors[2]

		-- calcula riscos das duas ações
		local noTapRisk = scoreAction(false, birdForCollision, smoothVelY, corridors, GameArea)
		local tapRisk   = scoreAction(true,  birdForCollision, smoothVelY, corridors, GameArea)

		-- predição a curto prazo (sem tap)
		local predT           = 0.15
		local predY, predVel  = predictY(b.cy, smoothVelY, predT, false)
		local predTop         = predY - BIRD_H/2
		local predBottom      = predY + BIRD_H/2

		local shouldTap = false
		local emergency = false

		local errNow  = b.cy  - target
		local errPred = predY - target

		-- perigo de bater no teto do vão (cima do cap_T)
		local topDanger = b.top    <= c1.rawTop  + MARGIN_TOP  + 1
		               or predTop  <= c1.rawTop  + MARGIN_TOP  + 1.5

		-- perigo de bater no chão do vão (cap_B)
		local bottomDanger = b.bottom  >= c1.rawBottom - MARGIN_BOTTOM - 1
		                  or predBottom >= c1.rawBottom - MARGIN_BOTTOM - 1.5

		-- zona morta proporcional à distância
		local deadZone = 5.5
		if c1.dist < 60  then deadZone = 4.0 end
		if c1.dist < 30  then deadZone = 2.5 end
		if c1.dist < 14  then deadZone = 1.5 end

		-- decisão por risco comparado
		if noTapRisk < 900 and not bottomDanger then
			shouldTap = false
		elseif tapRisk + 280 < noTapRisk then
			shouldTap = true
		end

		-- bird caindo abaixo do target
		if errNow > deadZone and errPred > deadZone and smoothVelY > -90 then
			shouldTap = true
		end

		-- velocidade descendente alta e ainda vai passar do target
		if smoothVelY > 125 and errPred > -10 then
			shouldTap = true
		end

		-- emergência: vai bater embaixo
		if bottomDanger then
			shouldTap = true
			emergency = true
		end

		-- emergência inversa: vai bater em cima → não tapa
		if topDanger then
			shouldTap  = false
			emergency  = false
			noTapUntil = now + 0.15
		end

		-- bordas da área de jogo
		local areaT  = GameArea.AbsolutePosition.Y
		local groundT = GameArea.AbsolutePosition.Y + GameArea.AbsoluteSize.Y - 16.2

		if predTop <= areaT + 9 then
			shouldTap  = false
			emergency  = false
			noTapUntil = now + 0.15
		end

		if predBottom >= groundT - 4 then
			shouldTap = true
			emergency = true
		end

		-- subindo rápido e já no target
		if smoothVelY < -130 and b.cy < target + 14 then
			shouldTap  = false
			emergency  = false
			noTapUntil = now + 0.10
		end

		-- antecipação do próximo cano
		if c2 then
			local nextLower     = c2.center > c1.center + 10
			local nextMuchLower = c2.center > c1.center + 22
			local nextHigher    = c2.center < c1.center - 14

			if nextLower and (b.cy < target + 4 or smoothVelY < 30) then
				shouldTap  = false
				emergency  = false
				noTapUntil = math.max(noTapUntil, now + 0.10)
			end

			if nextMuchLower and smoothVelY < 70 then
				shouldTap  = false
				emergency  = false
				noTapUntil = math.max(noTapUntil, now + 0.13)
			end

			if nextHigher and smoothVelY > 80 and b.cy > target - 7 then
				shouldTap = true
			end
		end

		-- zona crítica: bird chegando ao cano
		local critDist = BIRD_W_REAL * 3
		if c1.dist < critDist then
			if b.top    <= c1.rawTop    + MARGIN_TOP    + 2
			or predTop  <= c1.rawTop    + MARGIN_TOP    + 3 then
				shouldTap  = false
				emergency  = false
				noTapUntil = now + 0.16
			end

			if b.bottom  >= c1.rawBottom - MARGIN_BOTTOM - 2
			or predBottom >= c1.rawBottom - MARGIN_BOTTOM - 3 then
				shouldTap = true
				emergency = true
			end
		end

		-- respeita travas de tempo
		if now < noTapUntil       and not emergency then shouldTap = false end
		if now < postTapLockUntil and not emergency then shouldTap = false end

		local interval = emergency and FAST_INTERVAL or MIN_INTERVAL

		if shouldTap and (now - lastTap) >= interval then
			tap()
			lastTap = now
			-- lock pós-tap: evita double-tap no mesmo flap
			if c2 and c2.center > c1.center + 10 then
				postTapLockUntil = now + 0.17
			else
				postTapLockUntil = now + 0.10
			end
		end
	end)

	print("AutoFlappy v3 iniciado.")
end)

updateUI()
print("AutoFlappy v3 UI criada.")
