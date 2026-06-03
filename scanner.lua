-- ref_universal | Murder Mystery tester
-- v2026-06-03-r3

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

local SESSION_KEY = "__REF_UNIVERSAL_MM_TESTER_CLEANUP"
local previousCleanup = nil
_pcall(function()
    if type(getgenv) == "function" then
        previousCleanup = getgenv()[SESSION_KEY]
    end
end)
if type(previousCleanup) == "function" then
    _pcall(previousCleanup)
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
    selectedPart       = "UpperTorso",
    partIndex          = 1,
    predictionIndex    = 3,
    jumpPred           = true,
    pingPred           = true,
    cooldownIndex      = 2,
    targetIndex        = 0,
    selectedPlayerName = nil,
    lastAction         = 0,
    manualSilent       = false,
    coinCollect        = false,
    coinSpeed          = 5,
    collecting         = false,
    espOn              = false,
    roles              = {},
    espObjects         = {},
    espCharConns       = {},
    _espAdded          = nil,
    _espRemoving       = nil,
    _roleConn          = nil,
    _manualConn        = nil,
    _noclipConn        = nil,
    gunDropOn          = false,
    gunDropEspOn       = false,
    _gunDropWatch      = false,
    _gunDropConn       = nil,
    _gunDropEsp        = nil,
    _gunDropEspConn    = nil,
    _gunDropEspLoop    = false,
    lastGunDropStatus  = "Missing",
    lastGunDropPath    = "None",
    lastGunDropDistance = "N/A",
    _roleRefreshRunning = false,
    currentPhase       = "Unknown",
    lastRoundSignal    = "None",
    lastLobbySignal    = "None",
    localRole          = nil,
    coinCount          = 0,
    coinLimit          = 40,
    lastEndReason      = nil,
    lastWinnerRole     = nil,
    lastCreditedPlayer = nil,
}

local Alive = true
local Connections = {}
local RuntimeObjects = {}

local function trackConn(conn)
    if conn then
        Connections[#Connections + 1] = conn
    end
    return conn
end

local function trackObject(obj)
    if obj then
        RuntimeObjects[#RuntimeObjects + 1] = obj
    end
    return obj
end

local function safeDisconnect(conn)
    if conn then
        _pcall(function() conn:Disconnect() end)
    end
end

local function safeDestroy(obj)
    if obj and obj.Parent then
        _pcall(function() obj:Destroy() end)
    elseif obj then
        _pcall(function() obj:Destroy() end)
    end
end

local function clearRuntimeForRoot(root)
    if not root then return end
    destroyChild(root, "_CBP")
    destroyChild(root, "_CBG")
    destroyChild(root, "_GDBP")
    destroyChild(root, "_GDBG")
end

local function getObjectPath(obj)
    if not obj then return "None" end
    local names = {}
    local cur = obj
    while cur and cur ~= game do
        table.insert(names, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(names, ".")
end

local function cleanup()
    Alive = false
    State.manualSilent = false
    State.coinCollect = false
    State.gunDropOn = false
    State.gunDropEspOn = false
    State.espOn = false

    for _, conn in ipairs(Connections) do
        safeDisconnect(conn)
    end
    for i = #Connections, 1, -1 do
        Connections[i] = nil
    end

    for _, obj in ipairs(RuntimeObjects) do
        safeDestroy(obj)
    end
    for i = #RuntimeObjects, 1, -1 do
        RuntimeObjects[i] = nil
    end

    for _, obj in pairs(State.espObjects) do
        safeDestroy(obj)
    end
    for k in pairs(State.espObjects) do
        State.espObjects[k] = nil
    end
    for _, conn in pairs(State.espCharConns) do
        safeDisconnect(conn)
    end
    for k in pairs(State.espCharConns) do
        State.espCharConns[k] = nil
    end

    safeDestroy(State._gunDropEsp)
    State._gunDropEsp = nil
    safeDisconnect(State._gunDropConn)
    State._gunDropConn = nil
    safeDisconnect(State._gunDropEspConn)
    State._gunDropEspConn = nil

    local root = getRoot()
    clearRuntimeForRoot(root)
    local char = getChar()
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                _pcall(function() part.CanCollide = true end)
            end
        end
    end

    local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local oldGui = pg and pg:FindFirstChild("RefUniversal")
    safeDestroy(oldGui)

    _pcall(function()
        if type(getgenv) == "function" and getgenv()[SESSION_KEY] == cleanup then
            getgenv()[SESSION_KEY] = nil
        end
    end)
end

_pcall(function()
    if type(getgenv) == "function" then
        getgenv()[SESSION_KEY] = cleanup
    end
end)

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
    safeDisconnect(State._manualConn)
    State._manualConn = nil
    local uis = UserInputService
    State._manualConn = trackConn(uis.InputBegan:Connect(function(input, gp)
        if gp or not Alive or not State.manualSilent then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not findChild(getChar(), "Gun") then return end
        _spawn(function()
            if Alive and State.manualSilent then
                Tester.ShootTarget()
            end
        end)
    end))
end

-- ─── COIN COLLECT ──────────────────────────────────────────────────────────────

local function getCoinPart(obj)
    if not obj or obj.Name ~= "Coin_Server" then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function findCoins()
    local list = {}
    local seen = {}
    local desc = nil
    _pcall(function() desc = workspace:GetDescendants() end)
    if not desc then return list end
    for _, obj in ipairs(desc) do
        local part = getCoinPart(obj)
        if part and part.Parent and not seen[part] then
            seen[part] = true
            list[#list + 1] = part
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
    safeDisconnect(State._noclipConn)
    State._noclipConn = trackConn(RunService.Stepped:Connect(function()
        if not Alive or not State.coinCollect then
            safeDisconnect(State._noclipConn)
            State._noclipConn = nil
            return
        end
        local c = getChar()
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                _pcall(function() p.CanCollide = false end)
            end
        end
    end))
end

local function floatToCoin(target, speed)
    local root = getRoot()
    if not root or not target or not target.Parent then return end

    speed = tonumber(speed) or 5
    speed = math.clamp(speed, 1, 9)

    local timeout = math.clamp((root.Position - target.Position).Magnitude / math.max(speed, 1) + 4, 4, 35)
    local elapsed = 0
    local stepTime = 0.035

    while Alive and elapsed < timeout and State.coinCollect and target and target.Parent do
        local r = getRoot()
        if not r then break end

        local targetPos = target.Position + Vector3.new(0, 0.35, 0)
        local delta = targetPos - r.Position
        local dist = delta.Magnitude
        if dist < 2.4 then break end

        local move = math.min(dist, speed * stepTime)
        local nextPos = r.Position + delta.Unit * move

        _pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            r.CFrame = CFrame.new(nextPos) * CFrame.Angles(math.rad(90), 0, 0)
        end)

        _wait(stepTime)
        elapsed = elapsed + stepTime
    end
end

local function startCoinCollect()
    if State.collecting then return end
    State.collecting = true
    noclipLoop()
    _spawn(function()
        while Alive and State.coinCollect do
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
    if not Alive or player == LocalPlayer then return end
    if State.espObjects[player.Name] then return end

    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then return end

    local bb = Instance.new("BillboardGui")
    bb.Name         = "RESP_"..player.Name
    bb.Size         = UDim2.new(0, 132, 0, 46)
    bb.StudsOffset  = Vector3.new(0, 3.6, 0)
    bb.AlwaysOnTop  = true
    bb.ResetOnSpawn = false
    bb.Parent       = gui

    State.espObjects[player.Name] = bb

    local bg = Instance.new("Frame")
    bg.Size                   = UDim2.new(1,0,1,0)
    bg.BackgroundColor3       = Color3.fromRGB(10,10,14)
    bg.BackgroundTransparency = 0.28
    bg.BorderSizePixel        = 0
    bg.Parent                 = bb

    local bgc = Instance.new("UICorner")
    bgc.CornerRadius = UDim.new(0,6)
    bgc.Parent = bg

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(54, 60, 76)
    stroke.Thickness = 1
    stroke.Transparency = 0.35
    stroke.Parent = bg

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name               = "NameLbl"
    nameLbl.Size               = UDim2.new(1,-8,0.5,0)
    nameLbl.Position           = UDim2.new(0,4,0,2)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text               = player.Name
    nameLbl.TextColor3         = Color3.fromRGB(240,240,240)
    nameLbl.TextSize           = 11
    nameLbl.Font               = Enum.Font.GothamBold
    nameLbl.TextScaled         = true
    nameLbl.Parent             = bg

    local roleLbl = Instance.new("TextLabel")
    roleLbl.Name               = "RoleLbl"
    roleLbl.Size               = UDim2.new(1,-8,0.5,0)
    roleLbl.Position           = UDim2.new(0,4,0.5,-2)
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
        if r and bb.Parent then
            bb.Adornee = r
        end
    end

    anchorTo(player.Character)
    safeDisconnect(State.espCharConns[player.Name])
    State.espCharConns[player.Name] = trackConn(player.CharacterAdded:Connect(function(char)
        if not Alive or not State.espOn then return end
        _pcall(function() char:WaitForChild("HumanoidRootPart", 5) end)
        anchorTo(char)
    end))
end

local function disableEsp()
    clearEsp()
    safeDisconnect(State._espAdded)
    safeDisconnect(State._espRemoving)
    State._espAdded = nil
    State._espRemoving = nil
    for _, conn in pairs(State.espCharConns) do
        safeDisconnect(conn)
    end
    for k in pairs(State.espCharConns) do
        State.espCharConns[k] = nil
    end
end

local function enableEsp()
    disableEsp()
    if not Alive then return end
    for _, p in ipairs(Players:GetPlayers()) do
        attachEsp(p)
    end
    State._espAdded = trackConn(Players.PlayerAdded:Connect(function(p)
        if Alive and State.espOn then attachEsp(p) end
    end))
    State._espRemoving = trackConn(Players.PlayerRemoving:Connect(function(p)
        local obj = State.espObjects[p.Name]
        safeDestroy(obj)
        State.espObjects[p.Name] = nil
        State.roles[p.Name] = nil
        safeDisconnect(State.espCharConns[p.Name])
        State.espCharConns[p.Name] = nil
    end))
end

local function resetAllRoles()
    for _, p in ipairs(Players:GetPlayers()) do
        State.roles[p.Name] = "?"
        if State.espOn then
            updateEspLabel(p.Name)
        end
    end
    State.localRole = nil
end

local function setRoleForPlayer(pname, role)
    if type(role) ~= "string" or role == "" then return end
    if type(pname) ~= "string" or pname == "" then
        pname = LocalPlayer.Name
    end
    State.roles[pname] = role
    if pname == LocalPlayer.Name then
        State.localRole = role ~= "?" and role or nil
    end
    if State.espOn then
        updateEspLabel(pname)
    end
end

local function playerNameFromUserId(userId)
    if type(userId) ~= "number" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.UserId == userId then return p.Name end
    end
    return nil
end

local function parsePlayerDataPayload(value, fallbackName, depth)
    if depth > 4 or type(value) ~= "table" then return end

    local role = value.Role or value.role
    local pname = value.Name or value.PlayerName or value.Username or value.UserName or fallbackName
    if typeof and typeof(pname) == "Instance" and pname:IsA("Player") then
        pname = pname.Name
    end
    if type(pname) ~= "string" then
        pname = playerNameFromUserId(value.UserId or value.userId)
    end

    local isDead = value.Dead == true or value.dead == true or value.IsDead == true
    if isDead then
        setRoleForPlayer(pname, "?")
    elseif State.currentPhase ~= "Lobby" and type(role) == "string" then
        setRoleForPlayer(pname, role)
    end

    if value.Coins ~= nil and (not pname or pname == LocalPlayer.Name) then
        local coins = tonumber(value.Coins)
        if coins then State.coinCount = coins end
    end

    for k, v in pairs(value) do
        if type(v) == "table" then
            local nextFallback = type(k) == "string" and k or nil
            parsePlayerDataPayload(v, nextFallback, depth + 1)
        end
    end
end

local function listenRoles()
    safeDisconnect(State._roleConn)
    State._roleConn = nil
    local remote = getRemote({"Remotes","Gameplay","PlayerDataChanged"})
    if not remote or not remote:IsA("RemoteEvent") then return end
    State._roleConn = trackConn(remote.OnClientEvent:Connect(function(...)
        if not Alive then return end
        local args = {...}
        for _, v in ipairs(args) do
            parsePlayerDataPayload(v, nil, 0)
        end
    end))
end

local function bindRemoteEvent(path, callback)
    local remote = getRemote(path)
    if remote and remote:IsA("RemoteEvent") then
        return trackConn(remote.OnClientEvent:Connect(function(...)
            if Alive then callback(...) end
        end))
    end
    return nil
end

local function parseReturnedPlayerData(result)
    if type(result) == "table" then
        parsePlayerDataPayload(result, nil, 0)
        return true
    end
    return false
end

local function refreshCurrentPlayerData()
    if not Alive then return false end
    local got = false

    local gameplay = getRemote({"Remotes","Gameplay","GetCurrentPlayerData"})
    if gameplay then
        if gameplay:IsA("RemoteFunction") then
            local ok, result = _pcall(function()
                return gameplay:InvokeServer()
            end)
            if ok then got = parseReturnedPlayerData(result) or got end
        elseif gameplay:IsA("RemoteEvent") then
            _pcall(function() gameplay:FireServer() end)
        end
    end

    local extras = getRemote({"Remotes","Extras","GetPlayerData"})
    if extras then
        if extras:IsA("RemoteFunction") then
            local ok, result = _pcall(function()
                return extras:InvokeServer()
            end)
            if ok then got = parseReturnedPlayerData(result) or got end
        elseif extras:IsA("RemoteEvent") then
            _pcall(function() extras:FireServer() end)
        end
    end

    return got
end

local function refreshRolesBurst(reason)
    if State._roleRefreshRunning then
        refreshCurrentPlayerData()
        return
    end
    State._roleRefreshRunning = true
    _spawn(function()
        for i = 1, 14 do
            if not Alive then break end
            if State.currentPhase == "Lobby" then break end
            refreshCurrentPlayerData()
            _wait(i <= 6 and 0.25 or 0.6)
        end
        State._roleRefreshRunning = false
    end)
end

local function listenRoundSignals()
    bindRemoteEvent({"Remotes","Gameplay","RoundStart"}, function(...)
        State.currentPhase = "Round"
        State.lastRoundSignal = "RoundStart"
        State.lastEndReason = nil
        State.lastWinnerRole = nil
        State.lastCreditedPlayer = nil
        State.coinCount = 0
        resetAllRoles()
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("RoundStart")
    end)

    bindRemoteEvent({"Remotes","Gameplay","RoleSelect"}, function(...)
        State.currentPhase = "Role Select"
        State.lastRoundSignal = "RoleSelect"
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("RoleSelect")
    end)

    bindRemoteEvent({"Remotes","Gameplay","GiveWeapon"}, function(...)
        State.lastRoundSignal = "GiveWeapon"
        if State.currentPhase == "Unknown" or State.currentPhase == "Lobby" or State.currentPhase == "Role Select" then
            State.currentPhase = "Round"
        end
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("GiveWeapon")
    end)

    bindRemoteEvent({"Remotes","Gameplay","LoadingMap"}, function(...)
        State.currentPhase = "Loading Map"
        State.lastRoundSignal = "LoadingMap"
        resetAllRoles()
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("LoadingMap")
    end)

    bindRemoteEvent({"Remotes","Gameplay","ShowRoleSelect"}, function(...)
        State.currentPhase = "Role Select"
        State.lastRoundSignal = "ShowRoleSelect"
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("ShowRoleSelect")
    end)

    bindRemoteEvent({"Remotes","Gameplay","ShowRoleSelectNew"}, function(...)
        State.currentPhase = "Role Select"
        State.lastRoundSignal = "ShowRoleSelectNew"
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("ShowRoleSelectNew")
    end)

    bindRemoteEvent({"Remotes","Gameplay","VictoryScreen"}, function(...)
        State.currentPhase = "Ending"
        State.lastRoundSignal = "VictoryScreen"
        for _, v in ipairs({...}) do
            if type(v) == "table" then
                State.lastEndReason = v.Reason or v.RoundEndReason or v.EndReason or State.lastEndReason
                State.lastWinnerRole = v.WinnerRole or v.Winner or v.WinRole or State.lastWinnerRole
                State.lastCreditedPlayer = v.CreditedPlayer or v.Player or v.PlayerName or State.lastCreditedPlayer
                parsePlayerDataPayload(v, nil, 0)
            elseif type(v) == "string" then
                State.lastEndReason = State.lastEndReason or v
            end
        end
    end)

    local function markLobby(signal)
        State.currentPhase = "Lobby"
        State.lastLobbySignal = signal
        State.lastRoundSignal = signal
        State.localRole = nil
        resetAllRoles()
    end

    bindRemoteEvent({"Remotes","Gameplay","RoundEndFade"}, function() markLobby("RoundEndFade") end)
    bindRemoteEvent({"Remotes","CustomGames","Clear1v1"}, function() markLobby("Clear1v1") end)
    bindRemoteEvent({"Remotes","CustomGames","Cancelled1v1"}, function() markLobby("Cancelled1v1") end)

    bindRemoteEvent({"Remotes","Gameplay","CoinCollected"}, function(...)
        local args = {...}
        for _, v in ipairs(args) do
            if type(v) == "number" then
                if v > State.coinLimit then
                    State.coinLimit = v
                elseif v >= 0 then
                    State.coinCount = v
                end
            elseif type(v) == "table" then
                local current = tonumber(v.Count or v.Current or v.Coins or v[2])
                local limit = tonumber(v.Limit or v.Max or v[3])
                if current then State.coinCount = current end
                if limit then State.coinLimit = limit end
            end
        end
        if type(args[2]) == "number" then State.coinCount = args[2] end
        if type(args[3]) == "number" then State.coinLimit = args[3] end
    end)
end

local function listenPlayerRespawns()
    local function bindPlayer(player)
        if not player then return end
        trackConn(player.CharacterAdded:Connect(function()
            if not Alive then return end
            if State.currentPhase == "Round" or State.currentPhase == "Ending" then
                setRoleForPlayer(player.Name, "?")
            end
        end))
    end

    for _, p in ipairs(Players:GetPlayers()) do
        bindPlayer(p)
    end

    trackConn(Players.PlayerAdded:Connect(function(p)
        bindPlayer(p)
    end))
end
-- ─── GUN DROP COLLECT / ESP ───────────────────────────────────────────────────
-- GunDrop: Workspace.<Mapa>.GunDrop, classe Part, pickup por contato físico

local function getGunDropPart(obj)
    if not obj then return nil end
    if obj.Name == "GunDrop" and obj:IsA("BasePart") then return obj end
    if obj.Name == "GunDrop" and obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function findGunDrop()
    local desc = nil
    _pcall(function() desc = workspace:GetDescendants() end)
    if not desc then return nil end
    for _, obj in ipairs(desc) do
        local part = getGunDropPart(obj)
        if part and part.Parent then
            return part
        end
    end
    return nil
end

local function updateGunDropState(gd)
    if gd and gd.Parent then
        State.lastGunDropStatus = "Found"
        State.lastGunDropPath = getObjectPath(gd)
        local root = getRoot()
        if root then
            local ok, dist = _pcall(function()
                return math.floor((root.Position - gd.Position).Magnitude + 0.5)
            end)
            State.lastGunDropDistance = ok and tostring(dist).." studs" or "N/A"
        else
            State.lastGunDropDistance = "N/A"
        end
    else
        State.lastGunDropStatus = "Missing"
        State.lastGunDropPath = "None"
        State.lastGunDropDistance = "N/A"
    end
end

local function clearGunDropEsp()
    safeDestroy(State._gunDropEsp)
    State._gunDropEsp = nil
end

local function ensureGunDropEsp(gd)
    if not State.gunDropEspOn then
        clearGunDropEsp()
        return
    end
    if not gd or not gd.Parent then
        clearGunDropEsp()
        return
    end

    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then return end

    local bb = State._gunDropEsp
    if not bb or not bb.Parent then
        bb = Instance.new("BillboardGui")
        bb.Name = "REF_GunDrop_ESP"
        bb.Size = UDim2.new(0, 128, 0, 38)
        bb.StudsOffset = Vector3.new(0, 2.7, 0)
        bb.AlwaysOnTop = true
        bb.ResetOnSpawn = false
        bb.Parent = gui
        State._gunDropEsp = bb

        local frame = Instance.new("Frame")
        frame.Name = "Card"
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundColor3 = Color3.fromRGB(14, 15, 18)
        frame.BackgroundTransparency = 0.18
        frame.BorderSizePixel = 0
        frame.Parent = bb

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 7)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 205, 85)
        stroke.Thickness = 1
        stroke.Transparency = 0.15
        stroke.Parent = frame

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, -8, 1, 0)
        label.Position = UDim2.new(0, 4, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = "GunDrop"
        label.TextColor3 = Color3.fromRGB(255, 215, 95)
        label.TextSize = 13
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = frame
    end

    bb.Adornee = gd
end

local function startGunDropEsp()
    if State._gunDropEspLoop then return end
    State._gunDropEspLoop = true
    safeDisconnect(State._gunDropEspConn)
    State._gunDropEspConn = trackConn(workspace.DescendantAdded:Connect(function(inst)
        if not Alive or not State.gunDropEspOn then return end
        local gd = getGunDropPart(inst)
        if gd then
            updateGunDropState(gd)
            ensureGunDropEsp(gd)
        end
    end))

    _spawn(function()
        while Alive and State.gunDropEspOn do
            local gd = findGunDrop()
            updateGunDropState(gd)
            ensureGunDropEsp(gd)
            _wait(0.45)
        end
        State._gunDropEspLoop = false
        clearGunDropEsp()
    end)
end

local function stopGunDropEsp()
    State.gunDropEspOn = false
    State._gunDropEspLoop = false
    safeDisconnect(State._gunDropEspConn)
    State._gunDropEspConn = nil
    clearGunDropEsp()
end

local function fireTouchGunDrop(gd)
    if not gd or not gd.Parent then return false end
    local char = getChar()
    if not char then return false end
    local fired = false

    local touchFn = nil
    _pcall(function()
        if type(firetouchinterest) == "function" then
            touchFn = firetouchinterest
        end
    end)

    if touchFn then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                _pcall(function()
                    touchFn(part, gd, 0)
                    _wait(0.015)
                    touchFn(part, gd, 1)
                    fired = true
                end)
            end
        end
    end

    return fired
end

local function hardTouchGunDrop(gd)
    local root = getRoot()
    if not root or not gd or not gd.Parent then return false end

    local offsets = {
        Vector3.new(0, 2.4, 0),
        Vector3.new(0, 1.25, 0),
        Vector3.new(0, 0.25, 0),
        Vector3.new(1.6, 1.25, 0),
        Vector3.new(-1.6, 1.25, 0),
        Vector3.new(0, 1.25, 1.6),
        Vector3.new(0, 1.25, -1.6),
    }

    for _, offset in ipairs(offsets) do
        if not Alive or not State.gunDropOn or not gd or not gd.Parent then break end
        _pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            root.CFrame = CFrame.new(gd.Position + offset)
        end)
        fireTouchGunDrop(gd)
        _wait(0.07)
    end

    return not (gd and gd.Parent)
end

local function moveNearGunDrop(gd)
    local root = getRoot()
    if not root or not gd or not gd.Parent then return end

    local started = testerTime()
    local maxTime = 7
    local speed = 85

    while Alive and State.gunDropOn and gd and gd.Parent and testerTime() - started < maxTime do
        local r = getRoot()
        if not r then break end
        local targetPos = gd.Position + Vector3.new(0, 2.15, 0)
        local delta = targetPos - r.Position
        local dist = delta.Magnitude
        if dist <= 3.2 then break end
        local stepTime = 0.035
        local move = math.min(dist, speed * stepTime)
        local nextPos = r.Position + delta.Unit * move
        _pcall(function()
            r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            r.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            r.CFrame = CFrame.new(nextPos)
        end)
        _wait(stepTime)
    end
end

local function collectGunDrop(gd)
    if not gd or not gd.Parent then return false end
    State.lastGunDropStatus = "Collecting"
    State.lastGunDropPath = getObjectPath(gd)
    ensureGunDropEsp(gd)

    local char = getChar()
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                _pcall(function() part.CanCollide = false end)
            end
        end
    end

    fireTouchGunDrop(gd)
    if not (gd and gd.Parent) then
        State.lastGunDropStatus = "Collected"
        return true
    end

    moveNearGunDrop(gd)

    local attempts = 0
    while Alive and State.gunDropOn and gd and gd.Parent and attempts < 7 do
        attempts = attempts + 1
        fireTouchGunDrop(gd)
        hardTouchGunDrop(gd)
        _wait(0.12)
    end

    local collected = not (gd and gd.Parent)
    State.lastGunDropStatus = collected and "Collected" or "Touched"
    return collected
end

local function startGunDropWatch()
    if State._gunDropWatch then return end
    State._gunDropWatch = true

    if State.gunDropEspOn then
        startGunDropEsp()
    end

    safeDisconnect(State._gunDropConn)
    State._gunDropConn = trackConn(workspace.DescendantAdded:Connect(function(inst)
        if not Alive or not State.gunDropOn then return end
        local gd = getGunDropPart(inst)
        if gd then
            _spawn(function()
                _wait(0.08)
                if Alive and State.gunDropOn and gd and gd.Parent then
                    updateGunDropState(gd)
                    collectGunDrop(gd)
                end
            end)
        end
    end))

    _spawn(function()
        while Alive and State.gunDropOn do
            local gd = findGunDrop()
            updateGunDropState(gd)
            if gd then
                collectGunDrop(gd)
                _wait(0.25)
            else
                _wait(0.65)
            end
        end
        State._gunDropWatch = false
    end)
end

local function stopGunDropWatch()
    State.gunDropOn = false
    State._gunDropWatch = false
    safeDisconnect(State._gunDropConn)
    State._gunDropConn = nil
    local r = getRoot()
    if r then
        destroyChild(r,"_GDBP")
        destroyChild(r,"_GDBG")
    end
end

-- ─── REFLIB UI ─────────────────────────────────────────────────────────────────

local RefLib = {}

function RefLib.Window(title)
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("RefUniversal")
    if old then safeDestroy(old) end

    local gui = Instance.new("ScreenGui")
    gui.Name           = "RefUniversal"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 999997
    gui.Parent         = playerGui

    -- frame principal
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local winW = math.clamp(math.floor(viewport.X * 0.86), 300, 360)
    local winH = math.clamp(math.floor(viewport.Y * 0.72), 390, 500)
    local barH = 44

    local frame = Instance.new("Frame")
    frame.Name                   = "Main"
    frame.Size                   = UDim2.new(0, winW, 0, winH)
    frame.Position               = UDim2.new(0, 14, 0.5, -math.floor(winH / 2))
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
    bar.Size             = UDim2.new(1,0,0,barH)
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
    titleLbl.Size               = UDim2.new(1,-112,1,0)
    titleLbl.Position           = UDim2.new(0,14,0,0)
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
    local fullSize  = UDim2.new(0, winW, 0, winH)
    local miniSize  = UDim2.new(0, winW, 0, barH)

    local minBtn = Instance.new("TextButton")
    minBtn.Size               = UDim2.new(0,36,0,30)
    minBtn.Position           = UDim2.new(1,-82,0.5,-15)
    minBtn.BackgroundColor3   = Color3.fromRGB(40,44,55)
    minBtn.BorderSizePixel    = 0
    minBtn.Text               = "─"
    minBtn.TextColor3         = Color3.fromRGB(180,190,210)
    minBtn.TextSize           = 16
    minBtn.Font               = Enum.Font.GothamBold
    minBtn.ZIndex             = 6
    minBtn.Parent             = bar

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0,7)
    minCorner.Parent = minBtn

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size               = UDim2.new(0,36,0,30)
    closeBtn.Position           = UDim2.new(1,-42,0.5,-15)
    closeBtn.BackgroundColor3   = Color3.fromRGB(44,34,42)
    closeBtn.BorderSizePixel    = 0
    closeBtn.Text               = "×"
    closeBtn.TextColor3         = Color3.fromRGB(220,190,205)
    closeBtn.TextSize           = 18
    closeBtn.Font               = Enum.Font.GothamBold
    closeBtn.ZIndex             = 6
    closeBtn.Parent             = bar

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0,7)
    closeCorner.Parent = closeBtn

    trackConn(closeBtn.MouseButton1Click:Connect(function()
        cleanup()
    end))

    -- scroll de conteúdo
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name                  = "Content"
    scroll.Size                  = UDim2.new(1,0,1,-(barH + 6))
    scroll.Position              = UDim2.new(0,0,0,barH + 6)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel       = 0
    scroll.ScrollBarThickness    = 0
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
    trackConn(minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Size = minimized and miniSize or fullSize
        }):Play()
        minBtn.Text = minimized and "+" or "─"
        scroll.Visible = not minimized
    end))

    -- drag pela barra
    do
        local dragging, dragStart, startPos = false, nil, nil
        trackConn(bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging  = true
                dragStart = input.Position
                startPos  = frame.Position
                trackConn(input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end))
            end
        end))
        trackConn(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                          or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - dragStart
                frame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end))
    end

    -- ── W methods ──────────────────────────────────────────────────────────────

    local W = { gui = gui, frame = frame, scroll = scroll }

    function W:Section(label)
        local s = Instance.new("TextLabel")
        s.Size                   = UDim2.new(1,-18,0,22)
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
        holder.Size             = UDim2.new(1,-18,0,40)
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

        trackConn(btn.MouseButton1Click:Connect(function()
            state = not state
            _pcall(function()
                TweenService:Create(track, TweenInfo.new(0.15), {BackgroundColor3 = state and onCol or offCol}):Play()
                TweenService:Create(knob,  TweenInfo.new(0.15), {Position = state and onPos or offPos}):Play()
            end)
            if type(callback) == "function" then _pcall(callback, state) end
        end))

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
        holder.Size             = UDim2.new(1,-18,0,60)
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
        rail.Position         = UDim2.new(0,10,0,43)
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
        trackConn(rail.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true; upd(i.Position)
            end
        end))
        trackConn(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                         or  i.UserInputType == Enum.UserInputType.Touch) then upd(i.Position) end
        end))
        trackConn(UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end))

        local S = {}; function S:Get() return val end; return S
    end

    function W:Button(label, callback)
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(1,-18,0,38)
        btn.BackgroundColor3 = Color3.fromRGB(34,38,50)
        btn.BorderSizePixel  = 0
        btn.Text             = label
        btn.TextColor3       = Color3.fromRGB(210,218,235)
        btn.TextSize         = 12
        btn.Font             = Enum.Font.GothamSemibold
        btn.Parent           = scroll
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,7); bc.Parent = btn
        trackConn(btn.MouseButton1Click:Connect(function()
            if type(callback) == "function" then _pcall(callback) end
        end))
        return btn
    end

    function W:Label(text)
        local lbl = Instance.new("TextLabel")
        lbl.Size               = UDim2.new(1,-18,0,32)
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
        btn.Size             = UDim2.new(1,-18,0,38)
        btn.BackgroundColor3 = Color3.fromRGB(28,32,42)
        btn.BorderSizePixel  = 0
        btn.Text             = label..": "..tostring(options[idx])
        btn.TextColor3       = Color3.fromRGB(180,200,230)
        btn.TextSize         = 12
        btn.Font             = Enum.Font.GothamSemibold
        btn.Parent           = scroll
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,7); bc.Parent = btn
        trackConn(btn.MouseButton1Click:Connect(function()
            idx = idx + 1
            if idx > #options then idx = 1 end
            btn.Text = label..": "..tostring(options[idx])
            if type(callback) == "function" then _pcall(callback, idx, options[idx]) end
        end))
        local C = {}
        function C:SetIndex(i) idx = i; btn.Text = label..": "..tostring(options[idx]) end
        function C:SetText(t)  btn.Text = t end
        return C
    end

    return W
end

-- ─── BUILD UI ──────────────────────────────────────────────────────────────────

local W = RefLib.Window("ref_universal | tester")

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

W:Slider("Speed", 1, 9, 5, function(v)
    State.coinSpeed = v
end)

-- ── ROLE ESP ───────────────────────────────────────────────────────────────────

W:Section("  ESP")

W:Toggle("Role ESP", false, function(v)
    State.espOn = v
    if v then
        enableEsp()
        refreshRolesBurst("RoleESP")
    else
        disableEsp()
    end
end)

W:Button("Refresh Roles", function()
    if State.currentPhase == "Lobby" then
        resetAllRoles()
    else
        refreshRolesBurst("Manual")
    end
end)

W:Label("Murderer=Red  Sheriff=Blue  Hero=Yellow  Innocent=Green")

W:Section("  GUN DROP")

W:Toggle("GunDrop ESP", false, function(v)
    State.gunDropEspOn = v
    if v then startGunDropEsp() else stopGunDropEsp() end
end)

W:Toggle("Auto Collect GunDrop", false, function(v)
    State.gunDropOn = v
    if v then startGunDropWatch() else stopGunDropWatch() end
end)

W:Button("Collect GunDrop Now", function()
    local gd = findGunDrop()
    updateGunDropState(gd)
    if gd then
        _spawn(function()
            collectGunDrop(gd)
        end)
    end
end)

W:Section("  STATUS")
local statusLbl = W:Label("Ready.")
local phaseLbl = W:Label("Phase: Unknown")
local dataLbl = W:Label("Role: ? | Coins: 0/40")
local gunDropLbl = W:Label("GunDrop: Missing | N/A")

_spawn(function()
    while Alive and W.gui and W.gui.Parent do
        _wait(1)
        local parts = {}
        if State.coinCollect then parts[#parts+1] = "coins" end
        if State.espOn then parts[#parts+1] = "esp" end
        if State.gunDropOn then parts[#parts+1] = "gundrop" end
        if State.gunDropEspOn then parts[#parts+1] = "gundrop esp" end
        local activeText = #parts > 0 and ("Active: "..table.concat(parts, ", ")) or "Inactive"
        local localRole = State.currentPhase == "Lobby" and "?" or (State.localRole or State.roles[LocalPlayer.Name] or "?")
        local endText = ""
        if State.lastEndReason then
            endText = " | End: "..tostring(State.lastEndReason)
        end
        _pcall(function()
            statusLbl.Text = activeText
            phaseLbl.Text = "Phase: "..tostring(State.currentPhase or "Unknown").." | Signal: "..tostring(State.lastRoundSignal or "None")..endText
            dataLbl.Text = "Role: "..tostring(localRole).." | Coins: "..tostring(State.coinCount or 0).."/"..tostring(State.coinLimit or 40)
            gunDropLbl.Text = "GunDrop: "..tostring(State.lastGunDropStatus or "Missing").." | "..tostring(State.lastGunDropDistance or "N/A")
        end)
    end
end)
-- ─── INIT ──────────────────────────────────────────────────────────────────────

listenRoles()
listenRoundSignals()
listenPlayerRespawns()
installManualSilent()
_spawn(function()
    _wait(0.5)
    if Alive and State.currentPhase ~= "Lobby" then
        refreshRolesBurst("Init")
    end
end)
