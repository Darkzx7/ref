-- ref_universal | Murder Mystery tester
-- v2026-06-03

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ─── compat ────────────────────────────────────────────────────────────────────

local function _wait(n)
    if type(task) == "table" and type(task.wait) == "function" then
        return task.wait(n or 0)
    end
    return wait(n or 0)
end

local function _spawn(fn)
    if type(task) == "table" and type(task.spawn) == "function" then
        task.spawn(fn)
    else
        spawn(fn)
    end
end

local function _pcall(fn, ...)
    return pcall(fn, ...)
end

-- ─── helpers ───────────────────────────────────────────────────────────────────

local function getChar()        return LocalPlayer.Character end
local function getRoot()
    local c = getChar()
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
end
local function getHumanoid()
    local c = getChar()
    if not c then return nil end
    return c:FindFirstChildOfClass("Humanoid")
end
local function destroyChild(p, name)
    if not p then return end
    local c = p:FindFirstChild(name)
    if c then _pcall(function() c:Destroy() end) end
end
local function getRemote(t)
    local cur = ReplicatedStorage
    for _, n in ipairs(t) do
        cur = cur:FindFirstChild(n)
        if not cur then return nil end
    end
    return cur
end
local function findChild(root, name)
    if not root then return nil end
    local r; _pcall(function() r = root:FindFirstChild(name) end)
    return r
end
local function getBackpack()
    local bp; _pcall(function() bp = LocalPlayer:FindFirstChildOfClass("Backpack") end)
    return bp
end
local function findTool(name)
    local c = getChar()
    local b = getBackpack()
    return (c and findChild(c, name)) or (b and findChild(b, name))
end
local function equipTool(name)
    local tool = findTool(name)
    if not tool then return nil end
    local hum = getHumanoid()
    if hum and tool.Parent ~= getChar() then
        _pcall(function() hum:EquipTool(tool) end)
    end
    return tool
end
local function getPing()
    local ms = 0
    _pcall(function()
        local s = game:GetService("Stats")
        local n = s and s:FindFirstChild("Network")
        local si = n and n:FindFirstChild("ServerStatsItem")
        local dp = si and si:FindFirstChild("Data Ping")
        if dp and dp.GetValue then ms = dp:GetValue() end
    end)
    return math.clamp(type(ms) == "number" and ms or 0, 0, 1000) / 1000
end

-- ─── state ─────────────────────────────────────────────────────────────────────

local State = {
    -- tester
    selectedPart      = "UpperTorso",
    partIndex         = 1,
    predictionIndex   = 3,
    jumpPred          = true,
    pingPred          = true,
    cooldownIndex     = 2,
    targetIndex       = 0,
    selectedPlayerName = nil,
    lastAction        = 0,
    manualSilent      = false,
    -- coin
    coinCollect       = false,
    coinSpeed         = 50,
    collecting        = false,
    -- esp
    espOn             = false,
    roles             = {},
    espObjects        = {},
    _espAdded         = nil,
    _espRemoving      = nil,
    -- gundrop
    gunDropOn         = false,
    _gunDropWatch     = false,
    _gunDropConn      = nil,
}

local PART_OPTIONS       = { "UpperTorso","Head","HumanoidRootPart","Torso","LowerTorso","LeftUpperArm","RightUpperArm" }
local PRED_OPTIONS       = { 0, 0.08, 0.12, 0.18, 0.25, 0.35 }
local COOLDOWN_OPTIONS   = { 0.1, 0.25, 0.45, 0.75, 1.25 }

-- ─── tester utils ──────────────────────────────────────────────────────────────

local function testerTime()
    if type(os) == "table" and type(os.clock) == "function" then
        local ok, v = _pcall(os.clock); if ok then return v end
    end
    if type(tick) == "function" then local ok, v = _pcall(tick); if ok then return v end end
    return 0
end

local function canAct(name)
    local cd = COOLDOWN_OPTIONS[State.cooldownIndex] or 0.25
    if testerTime() - State.lastAction < cd then return false end
    State.lastAction = testerTime()
    return true
end

local function predSec()
    local base = PRED_OPTIONS[State.predictionIndex] or 0
    if State.pingPred then base = base + getPing() * 0.5 end
    return math.min(base, 0.65)
end

local function isAlive(char)
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return true end
    local h = 0; _pcall(function() h = hum.Health end)
    return h > 0
end

local function partPos(part)
    local p; _pcall(function() p = part.Position end); return p
end

local function partVel(part)
    local v
    _pcall(function() v = part.AssemblyLinearVelocity end)
    if not v then _pcall(function() v = part.Velocity end) end
    return v
end

local function getPart(char, preferred)
    if not char then return nil end
    local order = { preferred }
    for _, n in ipairs(PART_OPTIONS) do
        if n ~= preferred then order[#order+1] = n end
    end
    for _, n in ipairs(order) do
        local p = findChild(char, n)
        if p then return p end
    end
    local ch; _pcall(function() ch = char:GetChildren() end)
    if ch then
        for _, c in ipairs(ch) do
            local ok, r = _pcall(function() return c:IsA("BasePart") end)
            if ok and r then return c end
        end
    end
    return nil
end

local function predictedPos(part)
    local pos = partPos(part)
    if not pos then return nil end
    local lead = predSec()
    if lead <= 0 then return pos end
    local vel = partVel(part)
    if not vel then return pos end
    local ok, pred = _pcall(function()
        local v = pos + vel * lead
        if State.jumpPred and math.abs(vel.Y) > 3 then
            v = v + Vector3.new(0, vel.Y * lead * 0.85, 0)
        end
        return v
    end)
    return (ok and pred) or pos
end

local function getPlayerList()
    local list = {}
    local pl; _pcall(function() pl = Players:GetPlayers() end)
    if not pl then return list end
    for _, p in ipairs(pl) do
        if p ~= LocalPlayer and isAlive(p.Character) then
            list[#list+1] = p
        end
    end
    return list
end

local function selectedPlayer()
    if not State.selectedPlayerName then return nil end
    for _, p in ipairs(getPlayerList()) do
        if p.Name == State.selectedPlayerName then return p end
    end
    State.selectedPlayerName = nil
    State.targetIndex = 0
    return nil
end

local function nearestTarget()
    local myRoot = getPart(getChar(), "HumanoidRootPart")
    local myPos  = myRoot and partPos(myRoot)
    if not myPos then return nil, nil, "no local position" end

    local locked = selectedPlayer()
    if locked then
        local lp = getPart(locked.Character, State.selectedPart)
        if lp then return locked, lp, "locked:"..locked.Name end
        return nil, nil, "locked target missing part"
    end

    local best, bestPart, bestDist = nil, nil, 999999
    for _, p in ipairs(getPlayerList()) do
        local pt = getPart(p.Character, State.selectedPart)
        local pos = pt and partPos(pt)
        if pos then
            local d = (myPos - pos).Magnitude
            if d < bestDist then bestDist = d; best = p; bestPart = pt end
        end
    end
    if not bestPart then return nil, nil, "no target" end
    return best, bestPart, "nearest:"..best.Name
end

local function makeCFrames(originPart, targetPart, originOverride)
    local op = originOverride or partPos(originPart)
    local tp = predictedPos(targetPart)
    if not op or not tp then return nil, nil, "missing positions" end
    local oc, tc
    local ok = _pcall(function()
        oc = CFrame.new(op, tp)
        tc = CFrame.new(tp)
    end)
    if not ok then return nil, nil, "cframe failed" end
    return oc, tc, "ok"
end

-- ─── tester actions ────────────────────────────────────────────────────────────

local Tester = {}

function Tester.ShootTarget()
    if not canAct("Shoot") then return false end
    local tool = equipTool("Gun")
    local remote = tool and findChild(tool, "Shoot")
    if not remote then return false end
    local _, targetPart, st = nearestTarget()
    if not targetPart then return false end
    local handle = findChild(tool, "Handle") or getPart(getChar(), "HumanoidRootPart")
    local oc, tc = makeCFrames(handle, targetPart)
    if not oc then return false end
    _pcall(function() remote:FireServer(oc, tc) end)
    return true
end

function Tester.ThrowKnife()
    if not canAct("Throw") then return false end
    local tool = equipTool("Knife")
    local events = tool and findChild(tool, "Events")
    local remote = events and findChild(events, "KnifeThrown")
    if not remote then return false end
    local _, targetPart = nearestTarget()
    if not targetPart then return false end
    local handle = findChild(tool, "Handle") or getPart(getChar())
    local oc, tc = makeCFrames(handle, targetPart)
    if not oc then return false end
    _pcall(function() remote:FireServer(oc, tc) end)
    return true
end

function Tester.TouchTarget()
    if not canAct("Touch") then return false end
    local tool = equipTool("Knife")
    local events = tool and findChild(tool, "Events")
    local remote = events and findChild(events, "HandleTouched")
    if not remote then return false end
    local _, targetPart = nearestTarget()
    if not targetPart then return false end
    _pcall(function() remote:FireServer(targetPart) end)
    return true
end

function Tester.StabTarget()
    if not canAct("Stab") then return false end
    local tool = equipTool("Knife")
    local events = tool and findChild(tool, "Events")
    local remote = events and findChild(events, "KnifeStabbed")
    if not remote then return false end
    _pcall(function() remote:FireServer() end)
    local old = State.lastAction
    State.lastAction = 0
    Tester.TouchTarget()
    State.lastAction = old
    return true
end

function Tester.CycleTarget()
    local pl = getPlayerList()
    if #pl == 0 then
        State.targetIndex = 0
        State.selectedPlayerName = nil
        return "nearest"
    end
    State.targetIndex = State.targetIndex + 1
    if State.targetIndex > #pl then
        State.targetIndex = 0
        State.selectedPlayerName = nil
        return "nearest"
    end
    State.selectedPlayerName = pl[State.targetIndex].Name
    return State.selectedPlayerName
end

function Tester.CyclePart()
    State.partIndex = State.partIndex + 1
    if State.partIndex > #PART_OPTIONS then State.partIndex = 1 end
    State.selectedPart = PART_OPTIONS[State.partIndex]
    return State.selectedPart
end

function Tester.CyclePrediction()
    State.predictionIndex = State.predictionIndex + 1
    if State.predictionIndex > #PRED_OPTIONS then State.predictionIndex = 1 end
    return PRED_OPTIONS[State.predictionIndex]
end

function Tester.CycleCooldown()
    State.cooldownIndex = State.cooldownIndex + 1
    if State.cooldownIndex > #COOLDOWN_OPTIONS then State.cooldownIndex = 1 end
    return COOLDOWN_OPTIONS[State.cooldownIndex]
end

-- ─── manual silent input ───────────────────────────────────────────────────────

local function installManualSilent()
    _pcall(function()
        local uis = game:GetService("UserInputService")
        uis.InputBegan:Connect(function(input, gp)
            if gp or not State.manualSilent then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
            if not findChild(getChar(), "Gun") then return end
            _spawn(function() Tester.ShootTarget() end)
        end)
    end)
end

-- ─── COIN COLLECT ──────────────────────────────────────────────────────────────

local function findCoins()
    local list = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "Coin_Server" and obj:IsA("BasePart") then
            list[#list+1] = obj
        end
    end
    return list
end

local function layDown()
    -- deita o personagem usando CFrame no HRP + inclina o torso
    local root = getRoot()
    if not root then return end
    _pcall(function()
        root.CFrame = CFrame.new(root.Position)
            * CFrame.Angles(math.rad(90), 0, 0)
    end)
end

local function setCollide(char, state)
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            _pcall(function() p.CanCollide = state end)
        end
    end
end

local function noclipLoop()
    -- mantém noclip enquanto coin collect estiver on
    local conn
    conn = RunService.Stepped:Connect(function()
        if not State.coinCollect then
            conn:Disconnect()
            return
        end
        local c = getChar()
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                _pcall(function() p.CanCollide = false end)
            end
        end
    end)
end

local function floatToCoin(target, speed)
    local root = getRoot()
    if not root or not target or not target.Parent then return end

    local bp = Instance.new("BodyPosition")
    bp.Name     = "_CBP"
    bp.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bp.P        = 1e4
    bp.D        = 400
    bp.Position = target.Position
    bp.Parent   = root

    local bg = Instance.new("BodyGyro")
    bg.Name     = "_CBG"
    bg.MaxTorque = Vector3.new(0, 0, 0)
    bg.Parent   = root

    local timeout = (root.Position - target.Position).Magnitude / math.max(speed, 1) + 3
    local elapsed = 0

    while elapsed < timeout and State.coinCollect and target and target.Parent do
        _wait(0.05)
        elapsed = elapsed + 0.05
        local r = getRoot()
        if not r then break end
        if (target.Position - r.Position).Magnitude < 2.5 then break end
        bp.Position = target.Position
    end

    local r2 = getRoot()
    if r2 then
        destroyChild(r2, "_CBP")
        destroyChild(r2, "_CBG")
    end
    _pcall(function() bp:Destroy() end)
    _pcall(function() bg:Destroy() end)
end

local function startCoinCollect()
    if State.collecting then return end
    State.collecting = true
    noclipLoop()
    _spawn(function()
        while State.coinCollect do
            layDown()
            local coins = findCoins()
            if #coins == 0 then
                _wait(1)
            else
                local root = getRoot()
                if root then
                    local rp = root.Position
                    table.sort(coins, function(a, b)
                        return (a.Position - rp).Magnitude < (b.Position - rp).Magnitude
                    end)
                    for _, coin in ipairs(coins) do
                        if not State.coinCollect then break end
                        if coin and coin.Parent then
                            floatToCoin(coin, State.coinSpeed)
                            _wait(0.05)
                        end
                    end
                end
                _wait(0.3)
            end
        end
        -- cleanup ao desativar
        local c = getChar()
        if c then setCollide(c, true) end
        local r = getRoot()
        if r then
            destroyChild(r, "_CBP")
            destroyChild(r, "_CBG")
            -- levanta de volta
            _pcall(function()
                r.CFrame = CFrame.new(r.Position)
            end)
        end
        State.collecting = false
    end)
end

local function stopCoinCollect()
    State.coinCollect = false
end

-- ─── ROLE ESP ──────────────────────────────────────────────────────────────────
-- Roles chegam via PlayerDataChanged com campo Role no payload
-- Path confirmado: ReplicatedStorage.Remotes.Gameplay.PlayerDataChanged

local ROLE_COLOR = {
    Murderer = Color3.fromRGB(220, 50,  50),
    Sheriff  = Color3.fromRGB(80,  160, 255),
    Hero     = Color3.fromRGB(255, 200, 50),
    Innocent = Color3.fromRGB(80,  220, 120),
}

local function clearEsp()
    for k, obj in pairs(State.espObjects) do
        if obj and obj.Parent then _pcall(function() obj:Destroy() end) end
        State.espObjects[k] = nil
    end
end

local function updateEspLabel(pname)
    local bb = State.espObjects[pname]
    if not bb or not bb.Parent then return end
    local bg = bb:FindFirstChildOfClass("Frame")
    if not bg then return end
    local rl = bg:FindFirstChild("RoleLbl")
    if not rl then return end
    local role  = State.roles[pname] or "?"
    local color = ROLE_COLOR[role] or Color3.fromRGB(180, 180, 180)
    rl.Text       = role
    rl.TextColor3 = color
end

local function attachEsp(player)
    if player == LocalPlayer then return end
    if State.espObjects[player.Name] then return end

    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then return end

    local bb = Instance.new("BillboardGui")
    bb.Name         = "RESP_"..player.Name
    bb.Size         = UDim2.new(0, 120, 0, 44)
    bb.StudsOffset  = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop  = true
    bb.ResetOnSpawn = false
    bb.Parent       = gui

    State.espObjects[player.Name] = bb

    local bg = Instance.new("Frame")
    bg.Size                   = UDim2.new(1,0,1,0)
    bg.BackgroundColor3       = Color3.fromRGB(10,10,14)
    bg.BackgroundTransparency = 0.3
    bg.BorderSizePixel        = 0
    bg.Parent                 = bb

    local bgc = Instance.new("UICorner")
    bgc.CornerRadius = UDim.new(0,5)
    bgc.Parent = bg

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name               = "NameLbl"
    nameLbl.Size               = UDim2.new(1,-6,0.5,0)
    nameLbl.Position           = UDim2.new(0,3,0,2)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text               = player.Name
    nameLbl.TextColor3         = Color3.fromRGB(240,240,240)
    nameLbl.TextSize           = 11
    nameLbl.Font               = Enum.Font.GothamBold
    nameLbl.TextScaled         = true
    nameLbl.Parent             = bg

    local roleLbl = Instance.new("TextLabel")
    roleLbl.Name               = "RoleLbl"
    roleLbl.Size               = UDim2.new(1,-6,0.5,0)
    roleLbl.Position           = UDim2.new(0,3,0.5,-2)
    roleLbl.BackgroundTransparency = 1
    roleLbl.Text               = State.roles[player.Name] or "?"
    roleLbl.TextColor3         = ROLE_COLOR[State.roles[player.Name]] or Color3.fromRGB(180,180,180)
    roleLbl.TextSize           = 10
    roleLbl.Font               = Enum.Font.GothamSemibold
    roleLbl.TextScaled         = true
    roleLbl.Parent             = bg

    local function anchorTo(char)
        if not char then return end
        local r = char:FindFirstChild("HumanoidRootPart")
                or char:FindFirstChild("UpperTorso")
                or char:FindFirstChild("Torso")
        if r then bb.Adornee = r end
    end

    anchorTo(player.Character)
    player.CharacterAdded:Connect(function(char)
        _pcall(function() char:WaitForChild("HumanoidRootPart", 5) end)
        anchorTo(char)
    end)
end

local function enableEsp()
    clearEsp()
    for _, p in ipairs(Players:GetPlayers()) do attachEsp(p) end
    State._espAdded    = Players.PlayerAdded:Connect(function(p)
        if State.espOn then attachEsp(p) end
    end)
    State._espRemoving = Players.PlayerRemoving:Connect(function(p)
        local obj = State.espObjects[p.Name]
        if obj and obj.Parent then _pcall(function() obj:Destroy() end) end
        State.espObjects[p.Name] = nil
        State.roles[p.Name]      = nil
    end)
end

local function disableEsp()
    clearEsp()
    if State._espAdded    then State._espAdded:Disconnect();    State._espAdded    = nil end
    if State._espRemoving then State._espRemoving:Disconnect(); State._espRemoving = nil end
end

-- PlayerDataChanged listener — fonte principal de roles
-- payload pode ser tabela com Role + PlayerName/Name, ou array de tabelas
local function listenRoles()
    local remote = getRemote({"Remotes","Gameplay","PlayerDataChanged"})
    if not remote or not remote:IsA("RemoteEvent") then return end
    remote.OnClientEvent:Connect(function(...)
        local args = {...}
        -- tenta todos os formatos que o scan observou
        local function tryParse(t)
            if type(t) ~= "table" then return end
            local role  = t.Role
            local pname = t.Name or t.PlayerName or t.Username
            if type(role) == "string" and type(pname) == "string" then
                State.roles[pname] = role
                if State.espOn then updateEspLabel(pname) end
            end
            -- campos locais (próprio player)
            if type(role) == "string" then
                -- pode vir sem nome quando é sobre o LocalPlayer
                local lp = LocalPlayer.Name
                -- só seta se não vier de outro player
                if not pname then
                    State.roles[lp] = role
                    if State.espOn then updateEspLabel(lp) end
                end
            end
        end
        for _, v in ipairs(args) do
            if type(v) == "table" then
                -- pode ser array de entradas
                if v[1] and type(v[1]) == "table" then
                    for _, entry in ipairs(v) do tryParse(entry) end
                else
                    tryParse(v)
                end
            end
        end
    end)
end

-- ─── GUN DROP COLLECT ──────────────────────────────────────────────────────────
-- GunDrop: Workspace.<Mapa>.GunDrop, classe Part, pickup por contato físico

local function findGunDrop()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "GunDrop" and obj:IsA("BasePart") then return obj end
    end
    return nil
end

local function walkToGunDrop(gd)
    local root = getRoot()
    if not root or not gd or not gd.Parent then return end

    local bp = Instance.new("BodyPosition")
    bp.Name     = "_GDBP"
    bp.MaxForce = Vector3.new(1e5,1e5,1e5)
    bp.P        = 8000
    bp.D        = 500
    bp.Position = gd.Position
    bp.Parent   = root

    local bg = Instance.new("BodyGyro")
    bg.Name      = "_GDBG"
    bg.MaxTorque = Vector3.new(1e5,1e5,1e5)
    bg.P         = 8000
    bg.CFrame    = CFrame.new(root.Position, gd.Position)
    bg.Parent    = root

    local elapsed = 0
    while elapsed < 10 and State.gunDropOn and gd and gd.Parent do
        _wait(0.05)
        elapsed = elapsed + 0.05
        local r = getRoot()
        if not r then break end
        if (gd.Position - r.Position).Magnitude < 4 then break end
        bp.Position = gd.Position
        bg.CFrame   = CFrame.new(r.Position, gd.Position)
    end

    local r2 = getRoot()
    if r2 then destroyChild(r2,"_GDBP"); destroyChild(r2,"_GDBG") end
    _pcall(function() bp:Destroy() end)
    _pcall(function() bg:Destroy() end)
end

local function startGunDropWatch()
    if State._gunDropWatch then return end
    State._gunDropWatch = true
    _spawn(function()
        while State.gunDropOn do
            local gd = findGunDrop()
            if gd then walkToGunDrop(gd) end
            _wait(1.5)
        end
        State._gunDropWatch = false
    end)
    State._gunDropConn = workspace.DescendantAdded:Connect(function(inst)
        if inst.Name == "GunDrop" and inst:IsA("BasePart") and State.gunDropOn then
            _spawn(function() _wait(0.15); walkToGunDrop(inst) end)
        end
    end)
end

local function stopGunDropWatch()
    State.gunDropOn     = false
    State._gunDropWatch = false
    if State._gunDropConn then State._gunDropConn:Disconnect(); State._gunDropConn = nil end
    local r = getRoot()
    if r then destroyChild(r,"_GDBP"); destroyChild(r,"_GDBG") end
end

-- ─── REFLIB UI ─────────────────────────────────────────────────────────────────

local RefLib = {}

function RefLib.Window(title)
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("RefUniversal")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name           = "RefUniversal"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 999997
    gui.Parent         = playerGui

    -- frame principal
    local frame = Instance.new("Frame")
    frame.Name                   = "Main"
    frame.Size                   = UDim2.new(0, 228, 0, 620)
    frame.Position               = UDim2.new(0, 14, 0.5, -310)
    frame.BackgroundColor3       = Color3.fromRGB(14,15,18)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel        = 0
    frame.Active                 = true
    frame.ClipsDescendants       = false
    frame.Parent                 = gui

    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0,10)
    fCorner.Parent = frame

    local fStroke = Instance.new("UIStroke")
    fStroke.Color     = Color3.fromRGB(55,62,78)
    fStroke.Thickness = 1
    fStroke.Parent    = frame

    -- barra de título
    local bar = Instance.new("Frame")
    bar.Name             = "Bar"
    bar.Size             = UDim2.new(1,0,0,36)
    bar.BackgroundColor3 = Color3.fromRGB(20,22,28)
    bar.BorderSizePixel  = 0
    bar.ZIndex           = 4
    bar.Parent           = frame

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0,10)
    bCorner.Parent = bar

    -- patch pra cobrir canto inferior da bar
    local bPatch = Instance.new("Frame")
    bPatch.Size             = UDim2.new(1,0,0.5,0)
    bPatch.Position         = UDim2.new(0,0,0.5,0)
    bPatch.BackgroundColor3 = Color3.fromRGB(20,22,28)
    bPatch.BorderSizePixel  = 0
    bPatch.ZIndex           = 3
    bPatch.Parent           = bar

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size               = UDim2.new(1,-80,1,0)
    titleLbl.Position           = UDim2.new(0,12,0,0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text               = title
    titleLbl.TextColor3         = Color3.fromRGB(200,212,232)
    titleLbl.TextSize           = 13
    titleLbl.Font               = Enum.Font.GothamBold
    titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
    titleLbl.ZIndex             = 5
    titleLbl.Parent             = bar

    -- botão minimizar
    local minimized = false
    local fullSize  = UDim2.new(0,228,0,620)
    local miniSize  = UDim2.new(0,228,0,36)

    local minBtn = Instance.new("TextButton")
    minBtn.Size               = UDim2.new(0,28,0,24)
    minBtn.Position           = UDim2.new(1,-34,0.5,-12)
    minBtn.BackgroundColor3   = Color3.fromRGB(40,44,55)
    minBtn.BorderSizePixel    = 0
    minBtn.Text               = "─"
    minBtn.TextColor3         = Color3.fromRGB(180,190,210)
    minBtn.TextSize           = 13
    minBtn.Font               = Enum.Font.GothamBold
    minBtn.ZIndex             = 6
    minBtn.Parent             = bar

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0,5)
    minCorner.Parent = minBtn

    -- scroll de conteúdo
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name                  = "Content"
    scroll.Size                  = UDim2.new(1,0,1,-40)
    scroll.Position              = UDim2.new(0,0,0,40)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel       = 0
    scroll.ScrollBarThickness    = 2
    scroll.ScrollBarImageColor3  = Color3.fromRGB(80,90,110)
    scroll.CanvasSize            = UDim2.new(0,0,0,0)
    scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    scroll.ClipsDescendants      = true
    scroll.Parent                = frame

    local list = Instance.new("UIListLayout")
    list.Padding             = UDim.new(0,5)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.Parent              = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingTop    = UDim.new(0,8)
    pad.PaddingBottom = UDim.new(0,10)
    pad.Parent        = scroll

    -- minimizar
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Size = minimized and miniSize or fullSize
        }):Play()
        minBtn.Text = minimized and "+" or "─"
        scroll.Visible = not minimized
    end)

    -- drag pela barra
    do
        local dragging, dragStart, startPos = false, nil, nil
        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging  = true
                dragStart = input.Position
                startPos  = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                          or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - dragStart
                frame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end)
    end

    -- ── W methods ──────────────────────────────────────────────────────────────

    local W = { gui = gui, frame = frame, scroll = scroll }

    function W:Section(label)
        local s = Instance.new("TextLabel")
        s.Size                   = UDim2.new(1,-16,0,20)
        s.BackgroundTransparency = 1
        s.Text                   = label
        s.TextColor3             = Color3.fromRGB(100,115,140)
        s.TextSize               = 11
        s.Font                   = Enum.Font.GothamBold
        s.TextXAlignment         = Enum.TextXAlignment.Left
        s.Parent                 = scroll
    end

    function W:Toggle(label, default, callback)
        local state   = default == true
        local onCol   = Color3.fromRGB(80,200,120)
        local offCol  = Color3.fromRGB(50,54,64)
        local onPos   = UDim2.new(1,-16,0.5,-7)
        local offPos  = UDim2.new(0,2,0.5,-7)

        local holder = Instance.new("Frame")
        holder.Size             = UDim2.new(1,-16,0,36)
        holder.BackgroundColor3 = Color3.fromRGB(22,25,31)
        holder.BorderSizePixel  = 0
        holder.Parent           = scroll

        local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0,7); hc.Parent = holder

        local lbl = Instance.new("TextLabel")
        lbl.Size               = UDim2.new(1,-54,1,0)
        lbl.Position           = UDim2.new(0,10,0,0)
        lbl.BackgroundTransparency = 1
        lbl.Text               = label
        lbl.TextColor3         = Color3.fromRGB(210,215,225)
        lbl.TextSize           = 12
        lbl.Font               = Enum.Font.Gotham
        lbl.TextXAlignment     = Enum.TextXAlignment.Left
        lbl.Parent             = holder

        local track = Instance.new("Frame")
        track.Size             = UDim2.new(0,36,0,18)
        track.Position         = UDim2.new(1,-46,0.5,-9)
        track.BackgroundColor3 = state and onCol or offCol
        track.BorderSizePixel  = 0
        track.Parent           = holder
        local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1,0); tc.Parent = track

        local knob = Instance.new("Frame")
        knob.Size             = UDim2.new(0,14,0,14)
        knob.Position         = state and onPos or offPos
        knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
        knob.BorderSizePixel  = 0
        knob.Parent           = track
        local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(1,0); kc.Parent = knob

        local btn = Instance.new("TextButton")
        btn.Size               = UDim2.new(1,0,1,0)
        btn.BackgroundTransparency = 1
        btn.Text               = ""
        btn.Parent             = holder

        btn.MouseButton1Click:Connect(function()
            state = not state
            _pcall(function()
                TweenService:Create(track, TweenInfo.new(0.15), {BackgroundColor3 = state and onCol or offCol}):Play()
                TweenService:Create(knob,  TweenInfo.new(0.15), {Position = state and onPos or offPos}):Play()
            end)
            if type(callback) == "function" then _pcall(callback, state) end
        end)

        local T = {}
        function T:Set(v)
            state = v == true
            _pcall(function()
                TweenService:Create(track, TweenInfo.new(0.15), {BackgroundColor3 = state and onCol or offCol}):Play()
                TweenService:Create(knob,  TweenInfo.new(0.15), {Position = state and onPos or offPos}):Play()
            end)
        end
        function T:Get() return state end
        return T
    end

    function W:Slider(label, min, max, default, callback)
        local val = math.clamp(default or min, min, max)

        local holder = Instance.new("Frame")
        holder.Size             = UDim2.new(1,-16,0,54)
        holder.BackgroundColor3 = Color3.fromRGB(22,25,31)
        holder.BorderSizePixel  = 0
        holder.Parent           = scroll
        local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0,7); hc.Parent = holder

        local lbl = Instance.new("TextLabel")
        lbl.Size               = UDim2.new(1,-10,0,24)
        lbl.Position           = UDim2.new(0,10,0,3)
        lbl.BackgroundTransparency = 1
        lbl.Text               = label..": "..tostring(val)
        lbl.TextColor3         = Color3.fromRGB(210,215,225)
        lbl.TextSize           = 12
        lbl.Font               = Enum.Font.Gotham
        lbl.TextXAlignment     = Enum.TextXAlignment.Left
        lbl.Parent             = holder

        local rail = Instance.new("Frame")
        rail.Size             = UDim2.new(1,-20,0,6)
        rail.Position         = UDim2.new(0,10,0,38)
        rail.BackgroundColor3 = Color3.fromRGB(40,44,54)
        rail.BorderSizePixel  = 0
        rail.Parent           = holder
        local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1,0); rc.Parent = rail

        local frac0 = (val - min) / (max - min)
        local fill = Instance.new("Frame")
        fill.Size             = UDim2.new(frac0,0,1,0)
        fill.BackgroundColor3 = Color3.fromRGB(80,160,255)
        fill.BorderSizePixel  = 0
        fill.Parent           = rail
        local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1,0); fc.Parent = fill

        local thumb = Instance.new("Frame")
        thumb.Size             = UDim2.new(0,14,0,14)
        thumb.Position         = UDim2.new(frac0,-7,0.5,-7)
        thumb.BackgroundColor3 = Color3.fromRGB(255,255,255)
        thumb.BorderSizePixel  = 0
        thumb.ZIndex           = 3
        thumb.Parent           = rail
        local thc = Instance.new("UICorner"); thc.CornerRadius = UDim.new(1,0); thc.Parent = thumb

        local dragging = false
        local function upd(ip)
            local rp = rail.AbsolutePosition
            local rs = rail.AbsoluteSize
            if rs.X == 0 then return end
            local rel  = math.clamp((ip.X - rp.X) / rs.X, 0, 1)
            local newV = math.floor(min + rel*(max-min) + 0.5)
            if newV ~= val then
                val = newV
                local f = (val-min)/(max-min)
                fill.Size      = UDim2.new(f,0,1,0)
                thumb.Position = UDim2.new(f,-7,0.5,-7)
                lbl.Text       = label..": "..tostring(val)
                if type(callback) == "function" then _pcall(callback, val) end
            end
        end
        rail.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true; upd(i.Position)
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                         or  i.UserInputType == Enum.UserInputType.Touch) then upd(i.Position) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)

        local S = {}; function S:Get() return val end; return S
    end

    function W:Button(label, callback)
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(1,-16,0,34)
        btn.BackgroundColor3 = Color3.fromRGB(34,38,50)
        btn.BorderSizePixel  = 0
        btn.Text             = label
        btn.TextColor3       = Color3.fromRGB(210,218,235)
        btn.TextSize         = 12
        btn.Font             = Enum.Font.GothamSemibold
        btn.Parent           = scroll
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,7); bc.Parent = btn
        btn.MouseButton1Click:Connect(function()
            if type(callback) == "function" then _pcall(callback) end
        end)
        return btn
    end

    function W:Label(text)
        local lbl = Instance.new("TextLabel")
        lbl.Size               = UDim2.new(1,-16,0,28)
        lbl.BackgroundTransparency = 1
        lbl.Text               = text
        lbl.TextColor3         = Color3.fromRGB(130,140,160)
        lbl.TextSize           = 11
        lbl.Font               = Enum.Font.Gotham
        lbl.TextWrapped        = true
        lbl.TextXAlignment     = Enum.TextXAlignment.Left
        lbl.Parent             = scroll
        return lbl
    end

    function W:CycleButton(label, options, startIndex, callback)
        local idx = startIndex or 1
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(1,-16,0,34)
        btn.BackgroundColor3 = Color3.fromRGB(28,32,42)
        btn.BorderSizePixel  = 0
        btn.Text             = label..": "..tostring(options[idx])
        btn.TextColor3       = Color3.fromRGB(180,200,230)
        btn.TextSize         = 12
        btn.Font             = Enum.Font.GothamSemibold
        btn.Parent           = scroll
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,7); bc.Parent = btn
        btn.MouseButton1Click:Connect(function()
            idx = idx + 1
            if idx > #options then idx = 1 end
            btn.Text = label..": "..tostring(options[idx])
            if type(callback) == "function" then _pcall(callback, idx, options[idx]) end
        end)
        local C = {}
        function C:SetIndex(i) idx = i; btn.Text = label..": "..tostring(options[idx]) end
        function C:SetText(t)  btn.Text = t end
        return C
    end

    return W
end

-- ─── BUILD UI ──────────────────────────────────────────────────────────────────

local W = RefLib.Window("ref_universal")

-- ── WEAPON TESTER ──────────────────────────────────────────────────────────────

W:Section("  WEAPON TESTER")

local targetBtn = W:CycleButton("Target", {"nearest"}, 1, nil)
local partBtn   = W:CycleButton("Part", PART_OPTIONS, 1, function(i, v)
    State.partIndex   = i
    State.selectedPart = v
end)
local predBtn   = W:CycleButton("Prediction", PRED_OPTIONS, 3, function(i)
    State.predictionIndex = i
end)
local cdBtn     = W:CycleButton("Cooldown", COOLDOWN_OPTIONS, 2, function(i)
    State.cooldownIndex = i
end)

W:Toggle("Jump Prediction", true, function(v) State.jumpPred = v end)
W:Toggle("Ping Prediction", true, function(v) State.pingPred = v end)
W:Toggle("Manual Silent", false, function(v) State.manualSilent = v end)

W:Button("Shoot Target", function()
    local ok = Tester.ShootTarget()
    if not ok then -- feedback visual curto
        _spawn(function() _wait(0.1) end)
    end
end)
W:Button("Throw Knife",  function() Tester.ThrowKnife()  end)
W:Button("Stab Target",  function() Tester.StabTarget()  end)
W:Button("Touch Target", function() Tester.TouchTarget() end)

-- cycle target personalizado — atualiza label
local _origCycle = Tester.CycleTarget
function Tester.CycleTarget()
    local result = _origCycle()
    local pl     = getPlayerList()
    local labels = {"nearest"}
    for _, p in ipairs(pl) do labels[#labels+1] = p.Name end
    targetBtn:SetText("Target: "..(result or "nearest"))
    return result
end

W:Button("Cycle Target", function() Tester.CycleTarget() end)

-- ── COIN COLLECT ───────────────────────────────────────────────────────────────

W:Section("  COINS")

W:Toggle("Coin Collect", false, function(v)
    State.coinCollect = v
    if v then startCoinCollect() else stopCoinCollect() end
end)

W:Slider("Speed", 10, 200, 50, function(v)
    State.coinSpeed = v
end)

-- ── ROLE ESP ───────────────────────────────────────────────────────────────────

W:Section("  ESP")

W:Toggle("Role ESP", false, function(v)
    State.espOn = v
    if v then enableEsp() else disableEsp() end
end)

W:Label("Murderer=vermelho  Sheriff=azul  Hero=amarelo  Innocent=verde")

-- ── GUN DROP ───────────────────────────────────────────────────────────────────

W:Section("  GUN DROP")

W:Toggle("Auto Collect GunDrop", false, function(v)
    State.gunDropOn = v
    if v then startGunDropWatch() else stopGunDropWatch() end
end)

-- ── STATUS ─────────────────────────────────────────────────────────────────────

W:Section("  STATUS")
local statusLbl = W:Label("Pronto.")

_spawn(function()
    while true do
        _wait(2)
        local parts = {}
        if State.coinCollect then parts[#parts+1] = "coins"   end
        if State.espOn        then parts[#parts+1] = "esp"     end
        if State.gunDropOn    then parts[#parts+1] = "gundrop" end
        local myRole = State.roles[LocalPlayer.Name]
        local roleStr = myRole and (" | role: "..myRole) or ""
        local txt = #parts > 0
            and ("Ativo: "..table.concat(parts,", ")..roleStr)
            or  ("Inativo"..roleStr)
        _pcall(function() statusLbl.Text = txt end)
    end
end)

-- ─── INIT ──────────────────────────────────────────────────────────────────────

listenRoles()
installManualSilent()
