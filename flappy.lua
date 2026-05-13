-- AutoFlappy v4 — calibrado com scan real de 60s
--
-- Dados confirmados:
--   GameArea:  left=772.17  top=129.08  right=877.62  bottom=291.31  w=105.45  h=162.23
--   Ground:    top=275.09   h=16.22
--   Bird cx:   801.70 (fixo, nunca se move horizontalmente)
--   Bird body: w=10.54  h=10.54  |  com Tail: w~=12.55
--   Bird left: ~796.43   right: ~806.97
--   Cano corpo: w=13.71
--   Cap:        w=16.18  (0 left=corpo.left-1.23  right=corpo.right+1.24)
--   Cap_T height: 1.07~2.34px  (pequeno, topo do vao = corpo_T.bottom)
--   Cap_B height: 1.75~4.57px  (maior,  fundo vao  = BOUNDS_TOTAL_B.top = corpo_B.top)
--   GAP fixo:   51.91px
--   Velocidade canos: ~67px/s (medido: 7.77px por 0.34s * 60fps = ~22.8px/frame)
--   Impulso tap: ~-155px/s (média real dos 44 taps detectados)
--   GRAVITY:    ~700px/s² (estimado)
--
-- Bug crítico corrigido: canos com mesmo número (ex: Pipe_4_T) aparecem multiplos
-- pares na tela — o agrupamento por nome causava coluna errada.
-- Solução: agrupar SOMENTE por posição X, nunca por nome.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Enabled = true

-- ── UI ────────────────────────────────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFlappyUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size       = UDim2.new(0,150,0,45)
Main.Position   = UDim2.new(0,20,0.5,-22)
Main.BackgroundColor3 = Color3.fromRGB(25,25,25)
Main.BorderSizePixel  = 0
Main.Active    = true
Main.Draggable = true
Main.Parent    = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0,10)

local Toggle = Instance.new("TextButton")
Toggle.Size   = UDim2.new(1,-10,1,-10)
Toggle.Position = UDim2.new(0,5,0,5)
Toggle.BackgroundColor3 = Color3.fromRGB(50,160,230)
Toggle.BorderSizePixel  = 0
Toggle.Text      = "Auto Flappy: ON"
Toggle.TextColor3 = Color3.fromRGB(255,255,255)
Toggle.TextSize  = 14
Toggle.Font      = Enum.Font.GothamBold
Toggle.Parent    = Main
Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0,8)

local function updateUI()
	Toggle.Text = Enabled and "Auto Flappy: ON" or "Auto Flappy: OFF"
	Toggle.BackgroundColor3 = Enabled
		and Color3.fromRGB(50,160,230)
		or  Color3.fromRGB(170,55,55)
end
Toggle.MouseButton1Click:Connect(function()
	Enabled = not Enabled
	updateUI()
end)

-- ── Constantes calibradas ─────────────────────────────────────────────────────
local GRAVITY     =  700    -- px/s²   (ajuste se trajetória errar)
local TAP_IMPULSE = -155    -- px/s    (média medida: -155)

-- Hitbox real do bird (com Tail)
local BIRD_LEFT_OFFSET = -1.37   -- Tail projeta ~1.37px à esquerda de body.left
local BIRD_RIGHT_OFFSET =  0.63  -- Beak projeta ~0.63px à direita de body.right
-- altura do hitbox = 10.54px (sem filhos que ficam dentro)

-- Margens de segurança no corredor (em px)
-- Cap_T é pequeno (<=2.34px) — margem mínima
-- Cap_B é maior  (<=4.57px) — margem maior
-- Somamos ~2px extra de folga para erros de predição
local SAFE_MARGIN_TOP    = 3.5   -- acima do rawTop
local SAFE_MARGIN_BOTTOM = 7.0   -- abaixo do rawBottom (cap_B maior + folga)

-- GameArea constantes (do scan — não mudam)
local GA_LEFT   = 772.17
local GA_TOP    = 129.08
local GA_RIGHT  = 877.62
local GA_BOTTOM = 291.31
local GROUND_TOP = 275.09   -- topo do chão (limite inferior real do bird)

-- Velocidade dos canos (auto-calibrada em runtime)
local pipeSpeed = 67.0   -- px/s  (valor inicial medido)

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function clamp(v,a,b) return v<a and a or (v>b and b or v) end
local function lerp(a,b,t)  return a+(b-a)*t end

local function getRect(obj)
	local p,s = obj.AbsolutePosition, obj.AbsoluteSize
	return {
		left=p.X, right=p.X+s.X, top=p.Y, bottom=p.Y+s.Y,
		width=s.X, height=s.Y, cx=p.X+s.X/2, cy=p.Y+s.Y/2,
	}
end

-- ── Velocidade dos canos ──────────────────────────────────────────────────────
local lastPipeLeft = {}   -- [obj] = {x, t}

local function updatePipeSpeed(GameArea)
	local now   = tick()
	local total, count = 0, 0

	for _, obj in ipairs(GameArea:GetChildren()) do
		if obj:IsA("GuiObject") and obj.Visible
		   and obj.Name:match("^Pipe_%d+_[TB]$") then
			local x   = obj.AbsolutePosition.X
			local old = lastPipeLeft[obj]
			if old then
				local dt    = math.max(now - old.t, 1/120)
				local speed = (old.x - x) / dt
				if speed > 20 and speed < 200 then
					total = total + speed
					count = count + 1
				end
			end
			lastPipeLeft[obj] = {x=x, t=now}
		end
	end

	for obj in pairs(lastPipeLeft) do
		if not obj.Parent then lastPipeLeft[obj] = nil end
	end

	if count > 0 then
		local m = total / count
		pipeSpeed = pipeSpeed * 0.92 + m * 0.08
		pipeSpeed = clamp(pipeSpeed, 30, 150)
	end
end

-- ── Detecção e agrupamento de canos ──────────────────────────────────────────
-- CRÍTICO: agrupa por posição X real, NÃO por nome.
-- Cada par (T+B) tem o mesmo left/right — tolerância pequena (2px) para não
-- juntar pares vizinhos que possam estar próximos.

local function getPairs(GameArea)
	-- coleta todos os canos visíveis com seus bounds incluindo cap
	local pipes = {}
	for _, obj in ipairs(GameArea:GetChildren()) do
		if obj:IsA("GuiObject") and obj.Visible
		   and obj.Name:match("^Pipe_%d+_[TB]$") then
			local p, s = obj.AbsolutePosition, obj.AbsoluteSize
			-- bounds com cap: cap sempre tem mesma left do obj - 1.23px
			-- mas usamos getChildren para pegar o cap exato
			local capLeft  = p.X - 1.24
			local capRight = p.X + s.X + 1.24
			local isTop = obj.Name:match("_T$") ~= nil

			-- procura cap filho para bounds exatos
			for _, child in ipairs(obj:GetChildren()) do
				if child:IsA("GuiObject") and child.Visible
				   and child.Name:lower():find("cap") then
					local cp, cs = child.AbsolutePosition, child.AbsoluteSize
					capLeft  = math.min(capLeft,  cp.X)
					capRight = math.max(capRight, cp.X + cs.X)
				end
			end

			table.insert(pipes, {
				obj      = obj,
				isTop    = isTop,
				bodyLeft = p.X,
				bodyRight= p.X + s.X,
				capLeft  = capLeft,
				capRight = capRight,
				top      = p.Y,
				bottom   = p.Y + s.Y,
				cx       = p.X + s.X / 2,
			})
		end
	end

	-- agrupa por cx com tolerância de 2px (pares têm cx idêntico)
	local groups = {}
	local X_TOL  = 2.5

	for _, pipe in ipairs(pipes) do
		local found
		for _, g in ipairs(groups) do
			if math.abs(pipe.cx - g.cx) <= X_TOL then
				found = g; break
			end
		end
		if not found then
			found = {cx=pipe.cx, capLeft=pipe.capLeft, capRight=pipe.capRight,
			         top_pipe=nil, bot_pipe=nil}
			table.insert(groups, found)
		end
		found.capLeft  = math.min(found.capLeft,  pipe.capLeft)
		found.capRight = math.max(found.capRight, pipe.capRight)
		if pipe.isTop then
			found.top_pipe = pipe
		else
			found.bot_pipe = pipe
		end
	end

	-- ordena da esquerda para a direita
	table.sort(groups, function(a,b) return a.cx < b.cx end)
	return groups
end

-- ── Corredor seguro ────────────────────────────────────────────────────────────
-- rawTop    = bottom do Pipe_T (inclui cap_T no bounds_total)
-- rawBottom = top    do Pipe_B (é onde o cap_B começa — é a borda real do vão)
--
-- O cap_B projeta PARA DENTRO do vão: cap_B.top == pipe_B.top == rawBottom
-- Então o bird já colide no rawBottom, sem precisar subtrair nada extra.
-- SAFE_MARGIN_BOTTOM já cobre o cap_B.

local function buildCorridor(group, birdRight)
	local tp = group.top_pipe
	local bp = group.bot_pipe
	if not tp or not bp then return nil end

	-- rawTop  = fundo do cano de cima (bounds total inclui cap_T)
	-- cap_T fica na parte INFERIOR do Pipe_T, então tp.bottom já o inclui
	local rawTop    = tp.bottom

	-- rawBottom = topo do cano de baixo
	-- cap_B fica na parte SUPERIOR do Pipe_B — bp.top é exatamente a borda
	local rawBottom = bp.top

	local rawHeight = rawBottom - rawTop  -- deve ser ~51.91

	if rawHeight < 18 then return nil end  -- vão impossível

	-- zona segura
	local safeTop    = rawTop    + SAFE_MARGIN_TOP
	local safeBottom = rawBottom - SAFE_MARGIN_BOTTOM
	local safeHeight = safeBottom - safeTop

	if safeHeight < 5 then
		-- vão muito pequeno: usa o centro sem margem
		local mid = (rawTop + rawBottom) / 2
		safeTop    = mid - rawHeight * 0.45
		safeBottom = mid + rawHeight * 0.45
		safeHeight = safeBottom - safeTop
	end

	local center    = (safeTop + safeBottom) / 2
	local halfBird  = 10.54 / 2   -- metade do hitbox do bird

	local minCenter = safeTop    + halfBird
	local maxCenter = safeBottom - halfBird
	if minCenter > maxCenter then
		local mid = (rawTop + rawBottom) / 2
		minCenter = mid - 0.5
		maxCenter = mid + 0.5
	end

	-- dist = distância da borda direita do bird até a borda esquerda do cap
	-- (cap é mais largo que o corpo, é o que colide primeiro)
	local dist = group.capLeft - birdRight

	return {
		cx       = group.cx,
		capLeft  = group.capLeft,
		capRight = group.capRight,
		dist     = dist,

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

local function getCorridors(GameArea, birdRight, birdLeft)
	local groups    = getPairs(GameArea)
	local corridors = {}

	for _, g in ipairs(groups) do
		-- inclui colunas cujo cap ainda não passou completamente pelo bird
		if g.capRight >= birdLeft - 4 then
			local c = buildCorridor(g, birdRight)
			if c then
				table.insert(corridors, c)
			end
		end
	end

	-- fallback sem canos
	if #corridors == 0 then
		local mid = GA_TOP + (GROUND_TOP - GA_TOP) * 0.5
		table.insert(corridors, {
			cx=math.huge, capLeft=math.huge, capRight=math.huge, dist=math.huge,
			rawTop=GA_TOP+10, rawBottom=GROUND_TOP-10,
			safeTop=GA_TOP+16, safeBottom=GROUND_TOP-16,
			safeHeight=GROUND_TOP-GA_TOP-32,
			center=mid, minCenter=mid-20, maxCenter=mid+20,
		})
	end

	return corridors
end

-- ── Física ────────────────────────────────────────────────────────────────────
local function predictY(cy, vel, t, tapped)
	local v  = tapped and TAP_IMPULSE or vel
	local y  = cy + v*t + 0.5*GRAVITY*t*t
	local nv = v  + GRAVITY*t
	return y, nv
end

-- Tempo para borda direita do bird chegar ao capLeft do corredor
local function timeToReach(birdRight, corridor)
	if corridor.capLeft <= birdRight then return 0 end
	return clamp((corridor.capLeft - birdRight) / math.max(pipeSpeed, 30), 0, 2.0)
end

-- ── Score de risco ─────────────────────────────────────────────────────────────
local function scoreAction(tapped, birdCy, birdTop, birdBot, birdRight, vel, corridors)
	local risk = tapped and 18 or 0
	local W    = {5.5, 2.8, 1.4, 0.6}

	for i = 1, math.min(#corridors, 4) do
		local c = corridors[i]
		local t = timeToReach(birdRight, c)
		local y, v = predictY(birdCy, vel, t, tapped)
		local top    = y - 10.54/2
		local bottom = y + 10.54/2
		local w = W[i] or 0.4

		-- colisão real (penalidade máxima)
		if top    < c.rawTop    then risk = risk + (14000 + (c.rawTop - top)       * 700) * w end
		if bottom > c.rawBottom then risk = risk + (14000 + (bottom - c.rawBottom) * 700) * w end

		-- saída da zona segura
		if top    < c.safeTop    then risk = risk + (c.safeTop    - top)    * 55 * w end
		if bottom > c.safeBottom then risk = risk + (bottom - c.safeBottom) * 55 * w end

		-- desvio do centro seguro
		if y < c.minCenter then
			local d = c.minCenter - y
			risk = risk + (d*d*15 + d*180) * w
		end
		if y > c.maxCenter then
			local d = y - c.maxCenter
			risk = risk + (d*d*15 + d*180) * w
		end

		-- antecipação do próximo corredor
		local nxt = corridors[i+1]
		if nxt then
			if nxt.center > c.center + 14 and v < -10 then risk = risk + 750 * w end
			if nxt.center < c.center - 14 and v > 220  then risk = risk + 650 * w end
		end

		-- bordas da área
		if top    < GA_TOP   + 9  then risk = risk + (4500 + (GA_TOP+9 - top)         * 220) * w end
		if bottom > GROUND_TOP-5  then risk = risk + (4500 + (bottom - (GROUND_TOP-5))* 220) * w end
	end

	-- snapshots temporais
	for _, t in ipairs({0.07, 0.14, 0.24, 0.36}) do
		local y, v = predictY(birdCy, vel, t, tapped)
		local top    = y - 10.54/2
		local bottom = y + 10.54/2
		if top    < GA_TOP   + 9  then risk = risk + 3200 + (GA_TOP+9 - top)          * 140 end
		if bottom > GROUND_TOP-5  then risk = risk + 3200 + (bottom - (GROUND_TOP-5)) * 140 end
		if v < -200 and top    < GA_TOP   + 42 then risk = risk + 1400 end
		if v >  280 and bottom > GROUND_TOP-55 then risk = risk + 1400 end
	end

	return risk
end

-- ── Target Y ──────────────────────────────────────────────────────────────────
local function computeTarget(corridors, vel)
	local c1 = corridors[1]
	local c2 = corridors[2]
	local c3 = corridors[3]
	if not c1 then return nil end

	local target = c1.center

	if c2 then
		local d12  = c2.center - c1.center
		local bias = 0.50
		if     d12 < -32 then bias = 0.24
		elseif d12 < -20 then bias = 0.33
		elseif d12 <  -9 then bias = 0.41
		elseif d12 >  32 then bias = 0.86
		elseif d12 >  20 then bias = 0.77
		elseif d12 >   9 then bias = 0.65
		end

		if c3 then
			local d23 = c3.center - c2.center
			if d23 < -28 then bias = math.min(bias, 0.36) end
			if d23 >  28 then bias = math.max(bias, 0.72) end
		end

		local timeToC1 = math.max(c1.dist, 0) / math.max(pipeSpeed, 30)
		local prep     = 0
		if timeToC1 < 1.60 then prep = 0.16 end
		if timeToC1 < 1.20 then prep = 0.34 end
		if timeToC1 < 0.85 then prep = 0.54 end
		if timeToC1 < 0.55 then prep = 0.74 end
		if timeToC1 < 0.30 then prep = 0.94 end

		local exitY = c1.safeTop + c1.safeHeight * bias
		target = lerp(c1.center, exitY, prep)
	end

	-- restringe ao corredor atual
	local fMin = c1.minCenter
	local fMax = c1.maxCenter
	for i = 1, math.min(#corridors, 3) do
		local c = corridors[i]
		if c.dist < 150 then
			fMin = math.max(fMin, c.minCenter)
			fMax = math.min(fMax, c.maxCenter)
		end
	end
	if fMin <= fMax and c1.dist < 110 then
		target = clamp(target, fMin, fMax)
	else
		target = clamp(target, c1.minCenter, c1.maxCenter)
	end
	if c1.dist < 22 then
		target = clamp(target, c1.minCenter + 2, c1.maxCenter - 2)
	end

	return target
end

-- ── Loop principal ─────────────────────────────────────────────────────────────
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
				bird = obj; return
			end
		end
	end

	scanBird()
	GameArea.ChildAdded:Connect(function(obj)
		if obj:IsA("GuiObject") and obj.Name == "Bird" then bird = obj end
	end)

	-- estado
	local lastTap          = 0
	local lastBirdCY
	local lastTime         = tick()
	local velY             = 0
	local smoothVelY       = 0
	local lastTarget
	local noTapUntil       = 0
	local postTapLockUntil = 0

	local MIN_INTERVAL  = 0.10
	local FAST_INTERVAL = 0.055

	RunService.Heartbeat:Connect(function()
		if not Enabled then return end

		if not bird or not bird.Parent then
			scanBird(); return
		end

		updatePipeSpeed(GameArea)

		local now = tick()
		local p   = bird.AbsolutePosition
		local s   = bird.AbsoluteSize

		local bCY     = p.Y + s.Y / 2
		local bTop    = p.Y
		local bBottom = p.Y + s.Y
		local bLeft   = p.X  + BIRD_LEFT_OFFSET
		local bRight  = p.X + s.X + BIRD_RIGHT_OFFSET

		-- velocidade vertical
		if lastBirdCY then
			local dt = math.max(now - lastTime, 1/240)
			velY      = (bCY - lastBirdCY) / dt
			smoothVelY = smoothVelY * 0.70 + velY * 0.30
		end
		lastBirdCY = bCY
		lastTime   = now

		local corridors = getCorridors(GameArea, bRight, bLeft)
		local target    = computeTarget(corridors, smoothVelY)
		if not target then return end

		-- suaviza target
		if lastTarget then
			local diff = target - lastTarget
			diff = clamp(diff, -10, 10)
			target = lastTarget * 0.32 + (lastTarget + diff) * 0.68
		end
		lastTarget = target

		local c1 = corridors[1]
		local c2 = corridors[2]

		local noTapRisk = scoreAction(false, bCY, bTop, bBottom, bRight, smoothVelY, corridors)
		local tapRisk   = scoreAction(true,  bCY, bTop, bBottom, bRight, smoothVelY, corridors)

		-- predição sem tap
		local predT           = 0.16
		local predY, predVel  = predictY(bCY, smoothVelY, predT, false)
		local predTop         = predY - 10.54/2
		local predBottom      = predY + 10.54/2

		local shouldTap = false
		local emergency = false

		local errNow  = bCY   - target
		local errPred = predY - target

		-- perigos imediatos
		local topDanger    = bTop    <= c1.rawTop    + SAFE_MARGIN_TOP    + 1.5
		                  or predTop <= c1.rawTop    + SAFE_MARGIN_TOP    + 2.0
		local bottomDanger = bBottom  >= c1.rawBottom - SAFE_MARGIN_BOTTOM - 1.5
		                  or predBottom >= c1.rawBottom - SAFE_MARGIN_BOTTOM - 2.0

		-- dead zone adaptativa
		local dz = 6.0
		if c1.dist < 65  then dz = 4.5 end
		if c1.dist < 32  then dz = 2.8 end
		if c1.dist < 15  then dz = 1.8 end

		-- decisão por risco
		if noTapRisk < 800 and not bottomDanger then
			shouldTap = false
		elseif tapRisk + 300 < noTapRisk then
			shouldTap = true
		end

		if errNow > dz and errPred > dz and smoothVelY > -80 then
			shouldTap = true
		end
		if smoothVelY > 130 and errPred > -8 then
			shouldTap = true
		end

		if bottomDanger then shouldTap = true;  emergency = true  end
		if topDanger    then
			shouldTap = false; emergency = false
			noTapUntil = now + 0.16
		end

		-- bordas da área de jogo
		if predTop    <= GA_TOP    + 9 then
			shouldTap = false; emergency = false
			noTapUntil = now + 0.16
		end
		if predBottom >= GROUND_TOP - 5 then
			shouldTap = true; emergency = true
		end

		-- subindo rápido e já no target — aguarda
		if smoothVelY < -140 and bCY < target + 16 then
			shouldTap = false; emergency = false
			noTapUntil = now + 0.10
		end

		-- antecipação próximo cano
		if c2 then
			local nL  = c2.center > c1.center + 10
			local nML = c2.center > c1.center + 24
			local nH  = c2.center < c1.center - 14

			if nL  and (bCY < target + 4 or smoothVelY < 30) then
				shouldTap = false; emergency = false
				noTapUntil = math.max(noTapUntil, now + 0.10)
			end
			if nML and smoothVelY < 72 then
				shouldTap = false; emergency = false
				noTapUntil = math.max(noTapUntil, now + 0.14)
			end
			if nH  and smoothVelY > 82 and bCY > target - 7 then
				shouldTap = true
			end
		end

		-- zona crítica: perto do cano
		local critDist = 38   -- px  (largura cap 16.18 + folga)
		if c1.dist < critDist then
			if bTop     <= c1.rawTop    + SAFE_MARGIN_TOP    + 2.5
			or predTop  <= c1.rawTop    + SAFE_MARGIN_TOP    + 3.5 then
				shouldTap = false; emergency = false
				noTapUntil = now + 0.17
			end
			if bBottom   >= c1.rawBottom - SAFE_MARGIN_BOTTOM - 2.5
			or predBottom >= c1.rawBottom - SAFE_MARGIN_BOTTOM - 3.5 then
				shouldTap = true; emergency = true
			end
		end

		-- travas de tempo
		if now < noTapUntil       and not emergency then shouldTap = false end
		if now < postTapLockUntil and not emergency then shouldTap = false end

		local interval = emergency and FAST_INTERVAL or MIN_INTERVAL

		if shouldTap and (now - lastTap) >= interval then
			tap()
			lastTap = now
			postTapLockUntil = now + (c2 and c2.center > c1.center + 10 and 0.18 or 0.10)
		end
	end)

	print("AutoFlappy v4 iniciado. pipeSpeed inicial = " .. pipeSpeed)
end)

updateUI()
print("AutoFlappy v4 UI criada.")
