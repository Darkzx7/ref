-- ref_universal | Murder Mystery tester
-- v2026-06-03-v20-coin-lower-sweep

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
    lastAction         = 0,
    manualSilent       = false,
    coinCollect        = false,
    coinSpeed          = 4,
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
    _lastGiveWeaponAt  = 0,
    _lastGiveWeaponName = "None",
    _roleRefreshRunning = false,
    currentPhase       = "Unknown",
    lastRoundSignal    = "None",
    lastLobbySignal    = "None",
    localRole          = nil,
    localDead          = false,
    _coinLockConn      = nil,
    _coinMoveBP        = nil,
    _coinMoveBG        = nil,
    _coinAnimateSaved  = nil,
    _coinDesiredCF     = nil,
    _coinSavedHumanoid = nil,
    _coinSavedRootAnchored = nil,
    _coinSavedCollide  = nil,
    _coinStagePlatform = nil,
    _coinStageCF       = nil,
    _coinLastSafeCF    = nil,
    _coinLastTarget    = nil,
    _coinIgnoreUntil   = {},
    _coinLieForward    = nil,
    _coinStageAnchor   = nil,
    coinCount          = 0,
    coinLimit          = 40,
    coinStatus         = "Idle",
    _coinToggle        = nil,
    _gunDropToggle     = nil,
    _coinEntryPrime    = 0,
    _coinStartedInLobby = false,
    _coinDidInitialStage = false,
    _coinHadPhysicalMove = false,
    _coinFirstApproach  = false,
    _coinUnderOffset    = 3.55,
    _coinApproachExtra   = 1.35,
    _coinCloseBoost      = false,
    _returningLobby    = false,
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
local function restoreCoinPhysics()
    local hadCoinPhysics = State._coinLockConn ~= nil
        or State._coinDesiredCF ~= nil
        or State._coinSavedHumanoid ~= nil
        or State._coinSavedCollide ~= nil
        or State._coinSavedRootAnchored ~= nil
        or State._coinMoveBP ~= nil
        or State._coinMoveBG ~= nil
        or State._coinAnimateSaved ~= nil

    if not hadCoinPhysics then
        State._coinDesiredCF = nil
        return
    end

    safeDisconnect(State._coinLockConn)
    State._coinLockConn = nil
    State._coinDesiredCF = nil

    safeDestroy(State._coinMoveBP)
    safeDestroy(State._coinMoveBG)
    State._coinMoveBP = nil
    State._coinMoveBG = nil

    local char = getChar()
    if char then
        if State._coinSavedCollide then
            for part, oldValue in pairs(State._coinSavedCollide) do
                if part and part.Parent and part:IsA("BasePart") then
                    _pcall(function() part.CanCollide = oldValue end)
                end
            end
        else
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    _pcall(function() part.CanCollide = true end)
                end
            end
        end
        if State._coinAnimateSaved then
            local animate = char:FindFirstChild("Animate")
            if animate then
                _pcall(function() animate.Disabled = State._coinAnimateSaved.Disabled end)
            end
        end
    end
    State._coinSavedCollide = nil
    State._coinAnimateSaved = nil

    local root = getRoot()
    if root then
        clearRuntimeForRoot(root)
        _pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            if State._coinSavedRootAnchored ~= nil then
                root.Anchored = State._coinSavedRootAnchored
            else
                root.Anchored = false
            end
        end)
    end
    State._coinSavedRootAnchored = nil

    local hum = getHumanoid()
    if hum then
        local saved = State._coinSavedHumanoid
        _pcall(function()
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                track:Stop(0)
            end
            hum.Sit = false
            hum.PlatformStand = false
            if saved and saved.WalkSpeed then hum.WalkSpeed = saved.WalkSpeed end
            if saved and saved.JumpPower then hum.JumpPower = saved.JumpPower end
            if saved and saved.AutoRotate ~= nil then
                hum.AutoRotate = saved.AutoRotate
            else
                hum.AutoRotate = true
            end
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
    State._coinSavedHumanoid = nil

    root = getRoot()
    if root then
        _pcall(function()
            local _, yaw, _ = root.CFrame:ToOrientation()
            root.CFrame = CFrame.new(root.Position + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, yaw, 0)
        end)
    end
end

local function saveAndApplyNoclip(char)
    if not char then return end
    if not State._coinSavedCollide then
        State._coinSavedCollide = {}
    end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if State._coinSavedCollide[part] == nil then
                local old = true
                _pcall(function() old = part.CanCollide end)
                State._coinSavedCollide[part] = old
            end
            _pcall(function() part.CanCollide = false end)
        end
    end
end

local function beginCoinPhysicsLock()
    State._coinHadPhysicalMove = true
    local char = getChar()
    local hum = getHumanoid()
    local root = getRoot()

    if char and not State._coinAnimateSaved then
        local animate = char:FindFirstChild("Animate")
        if animate then
            local disabled = false
            _pcall(function() disabled = animate.Disabled end)
            State._coinAnimateSaved = { Disabled = disabled }
            _pcall(function() animate.Disabled = true end)
        else
            State._coinAnimateSaved = { Disabled = false }
        end
    end

    if hum and not State._coinSavedHumanoid then
        local autoRotate = true
        local walkSpeed = 16
        local jumpPower = 50
        _pcall(function() autoRotate = hum.AutoRotate end)
        _pcall(function() walkSpeed = hum.WalkSpeed end)
        _pcall(function() jumpPower = hum.JumpPower end)
        State._coinSavedHumanoid = { AutoRotate = autoRotate, WalkSpeed = walkSpeed, JumpPower = jumpPower }
    end
    if hum then
        _pcall(function()
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                track:Stop(0)
            end
            hum.Sit = false
            hum.AutoRotate = false
            hum.PlatformStand = true
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end)
    end
    saveAndApplyNoclip(char)

    if root and State._coinSavedRootAnchored == nil then
        local oldAnchored = false
        _pcall(function() oldAnchored = root.Anchored end)
        State._coinSavedRootAnchored = oldAnchored
    end
    if root then
        _pcall(function()
            root.Anchored = false
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)

        if not State._coinMoveBP or State._coinMoveBP.Parent ~= root then
            safeDestroy(State._coinMoveBP)
            local bp = Instance.new("BodyPosition")
            bp.Name = "_CBP"
            bp.MaxForce = Vector3.new(9e8, 9e8, 9e8)
            bp.P = 85000
            bp.D = 3200
            bp.Position = root.Position
            bp.Parent = root
            State._coinMoveBP = bp
        end

        if not State._coinMoveBG or State._coinMoveBG.Parent ~= root then
            safeDestroy(State._coinMoveBG)
            local bg = Instance.new("BodyGyro")
            bg.Name = "_CBG"
            bg.MaxTorque = Vector3.new(9e8, 9e8, 9e8)
            bg.P = 85000
            bg.D = 2200
            bg.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(90), 0, 0)
            bg.Parent = root
            State._coinMoveBG = bg
        end
    end

    if State._coinLockConn then return end
    State._coinLockConn = trackConn(RunService.Stepped:Connect(function()
        if not Alive or not State.coinCollect or State.currentPhase ~= "Round" then
            return
        end
        local c = getChar()
        local r = getRoot()
        local h = getHumanoid()
        if c then saveAndApplyNoclip(c) end
        if h then
            _pcall(function()
                for _, track in ipairs(h:GetPlayingAnimationTracks()) do
                    track:Stop(0)
                end
                h.Sit = false
                h.AutoRotate = false
                h.PlatformStand = true
                h.WalkSpeed = 0
                h.JumpPower = 0
                h:ChangeState(Enum.HumanoidStateType.Physics)
            end)
        end
        if r then
            _pcall(function()
                r.Anchored = false
                if State._coinDesiredCF then
                    if State._coinMoveBP and State._coinMoveBP.Parent == r then
                        State._coinMoveBP.Position = State._coinDesiredCF.Position
                    end
                    if State._coinMoveBG and State._coinMoveBG.Parent == r then
                        State._coinMoveBG.CFrame = State._coinDesiredCF
                    end
                end
            end)
        end
    end))
end

local function setCoinCFrame(cf)
    if cf then State._coinHadPhysicalMove = true end
    State._coinDesiredCF = cf
    local root = getRoot()
    if root and cf then
        beginCoinPhysicsLock()
        _pcall(function()
            root.Anchored = false
            if State._coinMoveBP and State._coinMoveBP.Parent == root then
                State._coinMoveBP.Position = cf.Position
            end
            if State._coinMoveBG and State._coinMoveBG.Parent == root then
                State._coinMoveBG.CFrame = cf
            end
        end)
    end
end

local function destroyCoinStagePlatform()
    local p = State._coinStagePlatform
    State._coinStagePlatform = nil
    State._coinStageCF = nil
    State._coinStageAnchor = nil
    if p then
        safeDestroy(p)
    end
end

local function rememberSafeCFrame(force)
    local root = getRoot()
    if not root then return end
    local pos = root.Position
    if force or (pos.Y > -20 and not State._coinDesiredCF and not State._coinStagePlatform) then
        State._coinLastSafeCF = CFrame.new(pos + Vector3.new(0, 2.5, 0))
    end
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

    destroyCoinStagePlatform()

    safeDestroy(State._gunDropEsp)
    State._gunDropEsp = nil
    safeDisconnect(State._gunDropConn)
    State._gunDropConn = nil
    safeDisconnect(State._gunDropEspConn)
    State._gunDropEspConn = nil

    restoreCoinPhysics()

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

local function isLocalAlive()
    return isAlive(getChar())
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

local function roleOfPlayer(player)
    if not player then return nil end
    if player == LocalPlayer and State.localRole then return State.localRole end
    local r = State.roles[player.Name]
    if r == "?" or r == "" then return nil end
    return r
end

local function isValidCombatTarget(player)
    if not player or player == LocalPlayer then return false end
    if not isAlive(player.Character) then return false end
    local r = roleOfPlayer(player)
    if r == "?" then return false end
    return true
end

local function nearestByFilter(filterFn, reasonLabel)
    local myRoot = getPart(getChar(), "HumanoidRootPart")
    local myPos  = myRoot and partPos(myRoot)
    if not myPos then return nil, nil, "no local position" end

    local best, bestPart, bestDist = nil, nil, 999999
    for _, p in ipairs(getPlayerList()) do
        if not filterFn or filterFn(p) then
            local pt = getPart(p.Character, State.selectedPart)
            local pos = pt and partPos(pt)
            if pos then
                local d = (myPos - pos).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = p
                    bestPart = pt
                end
            end
        end
    end

    if not bestPart then return nil, nil, reasonLabel or "no target" end
    return best, bestPart, (reasonLabel or "target")..":"..best.Name
end

local function nearestMurdererTarget()
    return nearestByFilter(function(p)
        return isValidCombatTarget(p) and roleOfPlayer(p) == "Murderer"
    end, "no murderer")
end

local function nearestKnifeTarget()
    return nearestByFilter(function(p)
        return isValidCombatTarget(p)
    end, "no knife target")
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

function Tester.ShootMurderer()
    if not canAct("Shoot") then return false end
    local tool = equipTool("Gun")
    local remote = tool and findChild(tool, "Shoot")
    if not remote then return false end
    local _, targetPart = nearestMurdererTarget()
    if not targetPart then return false end
    local handle = findChild(tool, "Handle") or getPart(getChar(), "HumanoidRootPart")
    local oc, tc = makeCFrames(handle, targetPart)
    if not oc then return false end
    _pcall(function() remote:FireServer(oc, tc) end)
    return true
end

function Tester.ShootTarget()
    return Tester.ShootMurderer()
end

function Tester.ThrowKnife()
    if not canAct("Throw") then return false end
    local tool = equipTool("Knife")
    local events = tool and findChild(tool, "Events")
    local remote = events and findChild(events, "KnifeThrown")
    if not remote then return false end
    local _, targetPart = nearestKnifeTarget()
    if not targetPart then return false end
    local handle = findChild(tool, "Handle") or getPart(getChar(), "HumanoidRootPart")
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
    local _, targetPart = nearestKnifeTarget()
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
    if not obj then return nil end
    local nm = tostring(obj.Name or "")
    if nm ~= "Coin_Server" and not nm:find("Coin_Server", 1, true) then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") or obj:IsA("Folder") then
        local pp = nil
        _pcall(function() pp = obj.PrimaryPart end)
        return pp or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function getTopWorkspaceChild(obj)
    local cur = obj
    while cur and cur.Parent and cur.Parent ~= workspace do
        cur = cur.Parent
    end
    return cur
end

local function isCoinCollectPhase()
    -- Coin collect must be blocked in lobby/ending, but it cannot depend only on role data.
    -- If the script is executed after the round already started, RoleSelect/PlayerDataChanged may be missed,
    -- so requiring localRole here makes the collector never move.
    if State.currentPhase ~= "Round" then return false end
    if State.localDead == true then return false end
    if not isLocalAlive() then return false end
    return true
end

local function isCoinArmedOnlyPhase()
    return State.currentPhase == "Lobby" or State.currentPhase == "Unknown"
end

local function isCoinStagePhase()
    -- Do not touch the character in the real lobby.
    -- Staging only starts when the actual map/loading flow begins.
    return State.currentPhase == "Loading Map" or State.currentPhase == "Role Select"
end

local function isValidCoinPart(part)
    if not part or not part.Parent then return false end
    if not part:IsA("BasePart") then return false end
    if part.Position.Y < -50 then return false end
    local okTouch, canTouch = _pcall(function() return part.CanTouch end)
    if okTouch and canTouch == false then return false end
    local okTrans, trans = _pcall(function() return part.Transparency end)
    if okTrans and type(trans) == "number" and trans >= 1 then
        local hasTouch = false
        _pcall(function()
            hasTouch = part:FindFirstChildOfClass("TouchTransmitter") ~= nil or part:FindFirstChild("TouchInterest") ~= nil
        end)
        if not hasTouch then return false end
    end
    return true
end

local function findCoins(allowFar, ignorePhase)
    local list = {}
    if not ignorePhase and not isCoinCollectPhase() then
        State.coinStatus = "Waiting for round"
        return list
    end

    local root = getRoot()
    if not root then
        State.coinStatus = "No character"
        return list
    end

    local desc = nil
    _pcall(function() desc = workspace:GetDescendants() end)
    if not desc then return list end

    local groups = {}
    local seen = {}
    local rootPos = root.Position

    for _, obj in ipairs(desc) do
        local part = getCoinPart(obj)
        if part and not seen[part] and isValidCoinPart(part) then
            seen[part] = true
            local top = getTopWorkspaceChild(part) or workspace
            local bucket = groups[top]
            if not bucket then
                bucket = { root = top, coins = {}, nearest = math.huge }
                groups[top] = bucket
            end
            bucket.coins[#bucket.coins + 1] = part
            local d = (part.Position - rootPos).Magnitude
            if d < bucket.nearest then bucket.nearest = d end
        end
    end

    local best = nil
    for _, bucket in pairs(groups) do
        if #bucket.coins > 0 then
            if not best or bucket.nearest < best.nearest then
                best = bucket
            end
        end
    end

    if not best then
        State.coinStatus = "No coins"
        return list
    end

    -- In normal mode, never crawl from lobby/void to a far preloaded map.
    -- During the first seconds of a real round, allow one safe entry stage.
    if best.nearest > 450 and not allowFar then
        State.coinStatus = "Coins too far"
        return list
    end
    if best.nearest > 450 and allowFar then
        State.coinStatus = "Entry staging"
    end

    for _, coin in ipairs(best.coins) do
        list[#list + 1] = coin
    end
    State.coinStatus = "Map: "..tostring(best.root and best.root.Name or "Unknown")
    return list
end

local function coinSpeedStuds(speed)
    speed = tonumber(speed) or 4
    speed = math.clamp(speed, 1, 6)
    local map = { 85, 125, 175, 235, 315, 410 }
    return map[speed] or 175
end

local function getCoinLieForward()
    local f = State._coinLieForward
    if typeof(f) == "Vector3" and f.Magnitude > 0.05 then
        return f.Unit
    end
    local root = getRoot()
    local look = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
    look = Vector3.new(look.X, 0, look.Z)
    if look.Magnitude < 0.05 then look = Vector3.new(0, 0, -1) end
    State._coinLieForward = look.Unit
    return State._coinLieForward
end

local function resetCoinLieForward()
    local root = getRoot()
    if root then
        local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        if look.Magnitude > 0.05 then
            State._coinLieForward = look.Unit
            return
        end
    end
    State._coinLieForward = Vector3.new(0, 0, -1)
end

local function lyingCoinCFrame(pos)
    local cf
    _pcall(function()
        local forward = getCoinLieForward()
        -- Fixed facing direction: no spinning between coins.
        cf = CFrame.new(pos, pos + forward) * CFrame.Angles(math.rad(90), 0, 0)
    end)
    return cf or CFrame.new(pos)
end

local function layDown()
    local root = getRoot()
    if not root then return end
    beginCoinPhysicsLock()
    setCoinCFrame(lyingCoinCFrame(root.Position))
end

local function setCollide(char, state)
    if not char then return end
    if state == false then
        saveAndApplyNoclip(char)
        return
    end
    if State._coinSavedCollide then
        for part, oldValue in pairs(State._coinSavedCollide) do
            if part and part.Parent and part:IsA("BasePart") then
                _pcall(function() part.CanCollide = oldValue end)
            end
        end
        State._coinSavedCollide = nil
        return
    end
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
        if not isCoinCollectPhase() then return end
        beginCoinPhysicsLock()
        local c = getChar()
        if not c then return end
        saveAndApplyNoclip(c)
    end))
end

local function fireTouchCoin(target)
    if not target or not target.Parent then return false end
    local char = getChar()
    if not char then return false end
    local touchFn = nil
    _pcall(function()
        if type(firetouchinterest) == "function" then
            touchFn = firetouchinterest
        end
    end)
    if not touchFn then return false end

    local fired = false
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            _pcall(function()
                touchFn(part, target, 0)
                touchFn(part, target, 1)
                fired = true
            end)
        end
    end
    return fired
end

local function getCharacterTouchParts()
    local parts = {}
    local char = getChar()
    if not char then return parts end
    local preferred = {"HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso", "Head"}
    local seen = {}
    for _, name in ipairs(preferred) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") and not seen[part] then
            seen[part] = true
            parts[#parts + 1] = part
        end
    end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") and not seen[obj] then
            seen[obj] = true
            parts[#parts + 1] = obj
            if #parts >= 12 then break end
        end
    end
    return parts
end

local function fireTouchCoinWithParts(target)
    if not target or not target.Parent then return false end
    local touchFn = nil
    _pcall(function()
        if type(firetouchinterest) == "function" then
            touchFn = firetouchinterest
        end
    end)
    if not touchFn then return false end

    local fired = false
    for _, part in ipairs(getCharacterTouchParts()) do
        if part and part.Parent then
            _pcall(function()
                touchFn(part, target, 0)
                touchFn(part, target, 1)
                fired = true
            end)
        end
    end
    return fired
end

local moveCoinRootDirect

local function physicalCoinContactPulse(target, cf)
    local root = getRoot()
    if not root or not target or not target.Parent or not isCoinCollectPhase() then return end
    State.coinStatus = "Physical coin contact"
    setCoinCFrame(cf)
    fireTouchCoinWithParts(target)
    _pcall(function() RunService.Heartbeat:Wait() end)
    fireTouchCoinWithParts(target)
    _pcall(function() RunService.Heartbeat:Wait() end)
    fireTouchCoinWithParts(target)
end

local function touchCoinSweep(root, target)
    if not root or not target or not target.Parent then return end
    State.coinStatus = State._coinCloseBoost and "Close coin boost" or "Collecting low underside"
    fireTouchCoin(target)
    fireTouchCoinWithParts(target)

    local pos = target.Position
    local sizeY = 1.5
    _pcall(function() sizeY = math.max(target.Size.Y, 1.5) end)
    local under = math.max(State._coinUnderOffset or 3.55, sizeY * 1.30)
    local passSpeed = coinSpeedStuds(State.coinSpeed) * (State._coinCloseBoost and 1.58 or 1.45)

    local forward = getCoinLieForward()
    local side = forward:Cross(Vector3.new(0, 1, 0))
    if side.Magnitude < 0.05 then side = Vector3.new(1, 0, 0) end
    side = side.Unit

    -- Low touch sweep: stay under the coin, cross the lower/center hitbox, and avoid lifting too high.
    -- The highest point is just above the coin center instead of over the top.
    local lowPeak = math.min(sizeY * 0.22, 0.34)
    local path = {
        pos + Vector3.new(0, -under, 0),
        pos + Vector3.new(0, -under * 0.70, 0),
        pos + Vector3.new(0, -under * 0.38, 0),
        pos + Vector3.new(0, -0.72, 0),
        pos + Vector3.new(0, -0.28, 0),
        pos + Vector3.new(0,  lowPeak, 0),
        pos + forward * 0.46 + Vector3.new(0, 0.08, 0),
        pos - forward * 0.46 + Vector3.new(0, 0.08, 0),
        pos + side * 0.42 + Vector3.new(0, 0.06, 0),
        pos - side * 0.42 + Vector3.new(0, 0.06, 0),
        pos + Vector3.new(0, -0.34, 0),
    }

    for i, p in ipairs(path) do
        if not Alive or not State.coinCollect or not target.Parent or not isCoinCollectPhase() then break end
        local cf = lyingCoinCFrame(p)
        moveCoinRootDirect(p, passSpeed, 0.13)
        fireTouchCoin(target)
        fireTouchCoinWithParts(target)
        if i >= 3 and i <= 7 then
            physicalCoinContactPulse(target, cf)
        else
            _pcall(function() RunService.Heartbeat:Wait() end)
        end
    end

    fireTouchCoin(target)
    fireTouchCoinWithParts(target)
    State._coinIgnoreUntil[target] = testerTime() + 0.001
end

local function getNearestCoin(allowFar, ignorePhase)
    local coins = findCoins(allowFar, ignorePhase)
    local root = getRoot()
    if not root or #coins == 0 then return nil end
    local now = testerTime()
    local rp = root.Position
    local best, bestDist = nil, math.huge
    for _, coin in ipairs(coins) do
        if coin and coin.Parent and (not State._coinIgnoreUntil[coin] or State._coinIgnoreUntil[coin] <= now) then
            local d = (coin.Position - rp).Magnitude
            if d < bestDist then
                best = coin
                bestDist = d
            end
        end
    end
    return best, bestDist
end

local function getBestCoinGroupForStage()
    local desc = nil
    _pcall(function() desc = workspace:GetDescendants() end)
    if not desc then return nil end

    local root = getRoot()
    local rp = root and root.Position or Vector3.new()
    local groups = {}
    local seen = {}

    for _, obj in ipairs(desc) do
        local part = getCoinPart(obj)
        if part and not seen[part] and isValidCoinPart(part) then
            seen[part] = true
            local top = getTopWorkspaceChild(part) or workspace
            local bucket = groups[top]
            if not bucket then
                bucket = { root = top, coins = {}, nearest = math.huge, minY = math.huge, maxY = -math.huge }
                groups[top] = bucket
            end
            bucket.coins[#bucket.coins + 1] = part
            local pos = part.Position
            local d = (pos - rp).Magnitude
            if d < bucket.nearest then bucket.nearest = d end
            if pos.Y < bucket.minY then bucket.minY = pos.Y end
            if pos.Y > bucket.maxY then bucket.maxY = pos.Y end
        end
    end

    local best = nil
    for _, bucket in pairs(groups) do
        if #bucket.coins > 0 then
            -- Prefer the real map cluster: lots of coins beats a small/old cluster.
            if not best
            or #bucket.coins > #best.coins
            or (#bucket.coins == #best.coins and bucket.nearest < best.nearest) then
                best = bucket
            end
        end
    end
    return best
end

local function getGroundBelowCoin(coin)
    if not coin then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local blacklist = { coin }
    local char = getChar()
    if char then blacklist[#blacklist + 1] = char end
    if State._coinStagePlatform then blacklist[#blacklist + 1] = State._coinStagePlatform end
    params.FilterDescendantsInstances = blacklist
    local result = nil
    _pcall(function()
        result = workspace:Raycast(coin.Position + Vector3.new(0, 8, 0), Vector3.new(0, -90, 0), params)
    end)
    if result and result.Position then return result.Position end
    return nil
end


local function isBadReturnHit(inst)
    if not inst then return true end
    if inst == State._coinStagePlatform then return true end
    local name = tostring(inst.Name or "")
    if name == "Coin_Server" or name == "GunDrop" or name == "_REF_COIN_STAGE_PLATFORM" then return true end
    local okBase, isBase = _pcall(function() return inst:IsA("BasePart") end)
    if okBase and isBase then
        local okTouch, canCollide = _pcall(function() return inst.CanCollide end)
        if okTouch and canCollide == false and not inst:IsA("SpawnLocation") then return true end
    end
    return false
end

local function raycastFloorNear(pos, maxAbove)
    if typeof(pos) ~= "Vector3" then return nil end
    local char = getChar()
    local blacklist = {}
    if char then blacklist[#blacklist + 1] = char end
    if State._coinStagePlatform then blacklist[#blacklist + 1] = State._coinStagePlatform end

    for _ = 1, 14 do
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = blacklist
        local result = nil
        _pcall(function()
            result = workspace:Raycast(pos + Vector3.new(0, 1.5, 0), Vector3.new(0, -180, 0), params)
        end)
        if not result then return nil end

        local inst = result.Instance
        if isBadReturnHit(inst) then
            blacklist[#blacklist + 1] = inst
        elseif result.Normal and result.Normal.Y >= 0.45 and result.Position.Y > -120 and result.Position.Y <= pos.Y + (maxAbove or 0.8) then
            return CFrame.new(result.Position + Vector3.new(0, 4.2, 0))
        else
            blacklist[#blacklist + 1] = inst
        end
    end
    return nil
end

local function prepareCoinStagePlatform(force)
    if not Alive or not State.coinCollect or ((not force) and not isCoinStagePhase()) then return false end
    local root = getRoot()
    if not root then return false end

    if State._coinStagePlatform and State._coinStagePlatform.Parent then
        local cf = State._coinStageCF
        if cf then
            _pcall(function()
                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                State._coinHadPhysicalMove = true
                root.CFrame = cf + Vector3.new(0, 3.6, 0)
            end)
        end
        State._coinDidInitialStage = true
        State.coinStatus = "Staged below map"
        return true
    end

    rememberSafeCFrame(true)

    local bucket = getBestCoinGroupForStage()
    if not bucket or not bucket.coins or #bucket.coins == 0 then
        State.coinStatus = "Armed - waiting for map"
        return false
    end

    local coin = nil
    local nearest = math.huge
    local rp = root.Position
    for _, c in ipairs(bucket.coins) do
        if c and c.Parent then
            local d = (c.Position - rp).Magnitude
            if d < nearest then coin = c; nearest = d end
        end
    end
    if not coin then
        State.coinStatus = "Armed - waiting for coins"
        return false
    end

    local ground = getGroundBelowCoin(coin)
    local floorY = ground and ground.Y or (bucket.minY - 4)
    -- Platform must be actually below the playable floor, not on the map.
    local stageY = floorY - 38
    if stageY < -140 then stageY = -140 end

    local platformPos = Vector3.new(coin.Position.X, stageY, coin.Position.Z)

    local platform = Instance.new("Part")
    platform.Name = "_REF_COIN_STAGE_PLATFORM"
    platform.Anchored = true
    platform.CanCollide = true
    platform.CanTouch = false
    platform.Size = Vector3.new(68, 1.4, 68)
    platform.Material = Enum.Material.SmoothPlastic
    platform.Color = Color3.fromRGB(135, 95, 255)
    platform.Transparency = 1
    platform.CFrame = CFrame.new(platformPos)
    platform.Parent = workspace

    State._coinStagePlatform = platform
    State._coinStageCF = platform.CFrame
    State._coinStageAnchor = coin
    trackObject(platform)

    _pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        State._coinHadPhysicalMove = true
        root.CFrame = platform.CFrame + Vector3.new(0, 3.6, 0)
    end)

    State._coinDidInitialStage = true
    State.coinStatus = "Staged below map"
    return true
end

local function findCoinReturnCFrame()
    local target = State._coinLastTarget
    if target and target.Parent then
        local cf = raycastFloorNear(target.Position, 2)
        if cf then return cf end
    end

    local nearest = nil
    _pcall(function()
        nearest = getNearestCoin(true, true)
    end)
    if nearest and nearest.Parent then
        local cf = raycastFloorNear(nearest.Position, 2)
        if cf then return cf end
    end

    local root = getRoot()
    if root then
        local cf = raycastFloorNear(root.Position, 1)
        if cf then return cf end
    end

    if State._coinLastSafeCF then return State._coinLastSafeCF end
    return nil
end

moveCoinRootDirect = function(goalPos, moveSpeed, maxTime)
    local root = getRoot()
    if not root or typeof(goalPos) ~= "Vector3" then return false end
    beginCoinPhysicsLock()

    local started = testerTime()
    local last = started
    local timeout = maxTime or math.clamp((goalPos - root.Position).Magnitude / math.max(moveSpeed, 1) + 0.18, 0.18, 1.15)

    while Alive and State.coinCollect and isCoinCollectPhase() do
        local r = getRoot()
        if not r then return false end
        local now = testerTime()
        local dt = math.clamp(now - last, 1/240, 1/30)
        last = now

        local cur = r.Position
        local diff = goalPos - cur
        local dist = diff.Magnitude
        if dist <= 1.15 then break end
        if now - started > timeout then break end

        local step = math.min(dist, moveSpeed * dt)
        local nextPos = cur + diff.Unit * step
        setCoinCFrame(lyingCoinCFrame(nextPos))
        _pcall(function() RunService.Heartbeat:Wait() end)
    end

    setCoinCFrame(lyingCoinCFrame(goalPos))
    local settleStarted = testerTime()
    while Alive and State.coinCollect and isCoinCollectPhase() do
        local r = getRoot()
        if not r then break end
        if (r.Position - goalPos).Magnitude <= 1.4 then break end
        if testerTime() - settleStarted > 0.12 then break end
        _pcall(function() RunService.Heartbeat:Wait() end)
    end
    return true
end

local function floatToCoin(target, speed)
    local root = getRoot()
    if not root or not target or not target.Parent then return end
    if not isCoinCollectPhase() then return end

    speed = tonumber(speed) or 4
    speed = math.clamp(speed, 1, 6)
    local moveSpeed = coinSpeedStuds(speed)
    local allowEntryStage = (State._coinEntryPrime or 0) > testerTime()

    local startDist = (root.Position - target.Position).Magnitude
    if startDist > 720 and not allowEntryStage then
        State.coinStatus = "Skipped far coin"
        return
    end

    if not State._coinLieForward then
        resetCoinLieForward()
    end
    beginCoinPhysicsLock()
    local previousTarget = State._coinLastTarget
    local closeBoost = false
    if previousTarget and previousTarget ~= target and previousTarget.Parent then
        local okClose, closeDist = _pcall(function()
            return (previousTarget.Position - target.Position).Magnitude
        end)
        if okClose and closeDist and closeDist <= 15 then
            closeBoost = true
        end
    end
    if startDist <= 12 and not State._coinFirstApproach then
        closeBoost = true
    end
    if State._coinFirstApproach then
        closeBoost = false
    end
    State._coinCloseBoost = closeBoost
    if closeBoost then
        moveSpeed = moveSpeed * 1.14
    end
    State._coinLastTarget = target

    local sizeY = 1.5
    _pcall(function() sizeY = math.max(target.Size.Y, 1.5) end)
    local under = math.max(State._coinUnderOffset or 3.55, sizeY * 1.30)
    local approachUnder = under + (State._coinApproachExtra or 1.35)
    local approach = target.Position + Vector3.new(0, -approachUnder, 0)

    -- First coin after enabling should enter smoothly, not snap across the map.
    local firstFactor = State._coinFirstApproach and 0.52 or 1
    local approachSpeed = math.max(45, moveSpeed * firstFactor)
    local approachMax = State._coinFirstApproach and 1.55 or 0.95
    State.coinStatus = State._coinFirstApproach and "Smooth first coin entry" or (closeBoost and "Close coin boost" or "Moving low under nearest coin")
    moveCoinRootDirect(approach, approachSpeed, math.clamp(startDist / math.max(approachSpeed, 1) + 0.16, 0.20, approachMax))
    State._coinFirstApproach = false

    if not Alive or not State.coinCollect or not target.Parent or not isCoinCollectPhase() then return end

    touchCoinSweep(getRoot(), target)
end

local function hasCoinPhysicsActive()
    return State._coinLockConn ~= nil
        or State._coinDesiredCF ~= nil
        or State._coinSavedHumanoid ~= nil
        or State._coinSavedCollide ~= nil
        or State._coinSavedRootAnchored ~= nil
        or State._coinMoveBP ~= nil
        or State._coinMoveBG ~= nil
end

local function suspendCoinMovement(statusText, keepStage)
    safeDisconnect(State._noclipConn)
    State._noclipConn = nil
    if hasCoinPhysicsActive() then
        restoreCoinPhysics()
    end
    if not keepStage then
        destroyCoinStagePlatform()
    end
    State._coinDesiredCF = nil
    State._coinLieForward = nil
    State._coinCloseBoost = false
    if statusText then
        State.coinStatus = statusText
    end
end

local function detectRoundFromNearbyCoins()
    if State.currentPhase ~= "Unknown" and State.currentPhase ~= "Role Select" then return false end
    if State.localDead == true or not isLocalAlive() then return false end
    local coin, dist = getNearestCoin(true, true)
    if coin and dist and dist < 380 then
        State.currentPhase = "Round"
        State.lastRoundSignal = "CoinFallback"
        State.coinStatus = "Round detected by coins"
        return true
    end
    return false
end

local function startCoinCollect()
    if State.collecting then return end
    State.collecting = true
    _spawn(function()
        while Alive and State.coinCollect do
            if not isCoinCollectPhase() then
                detectRoundFromNearbyCoins()
            end

            if not isCoinCollectPhase() then
                if hasCoinPhysicsActive() then
                    restoreCoinPhysics()
                end
                safeDisconnect(State._noclipConn)
                State._noclipConn = nil

                if isCoinStagePhase() then
                    prepareCoinStagePlatform()
                elseif isCoinArmedOnlyPhase() then
                    -- Fully passive in lobby: no noclip, no PlatformStand, no CFrame, no Humanoid state changes.
                    State.coinStatus = "Armed - waiting for map"
                else
                    State.coinStatus = "Waiting for round"
                end
                _wait(0.05)
            else
                if tonumber(State.coinLimit) and tonumber(State.coinCount) and State.coinLimit > 0 and State.coinCount >= State.coinLimit then
                    suspendCoinMovement("Coin bag full - grounded wait", false)
                    State._coinIgnoreUntil = {}
                    _wait(0.25)
                else
                    local allowFar = (State._coinEntryPrime or 0) > testerTime()
                    local coin = getNearestCoin(allowFar, false)
                    if coin and coin.Parent then
                        if State._coinStartedInLobby and not State._coinDidInitialStage then
                            if prepareCoinStagePlatform(true) then
                                _wait(0.20)
                            end
                            State._coinDidInitialStage = true
                        end
                        if State._coinStagePlatform then
                            destroyCoinStagePlatform()
                        end
                        if not State._coinLieForward then
                            resetCoinLieForward()
                        end
                        if not hasCoinPhysicsActive() then
                            beginCoinPhysicsLock()
                            noclipLoop()
                            local root = getRoot()
                            if root then
                                setCoinCFrame(lyingCoinCFrame(root.Position))
                            end
                        end
                        floatToCoin(coin, State.coinSpeed)
                    else
                        -- Keep the toggle/function armed, but release every physical controller.
                        -- This lets the character naturally stand/fall onto the map floor after the coin bag is empty.
                        suspendCoinMovement("No coins - grounded wait", false)
                        State._coinFirstApproach = true
                        State._coinIgnoreUntil = {}
                        _wait(0.22)
                    end
                end
            end
        end
        State.coinStatus = "Idle"
        safeDisconnect(State._noclipConn)
        State._noclipConn = nil
        restoreCoinPhysics()
        destroyCoinStagePlatform()
        State.collecting = false
    end)
end

local function stopCoinCollect()
    local hadPhysicalMove = State._coinHadPhysicalMove == true
        or hasCoinPhysicsActive()
        or State._coinStagePlatform ~= nil
    local returnCF = hadPhysicalMove and findCoinReturnCFrame() or nil

    State.coinCollect = false
    State.coinStatus = "Idle"
    State._coinEntryPrime = 0
    State._coinIgnoreUntil = {}
    State._coinLieForward = nil
    State._coinStartedInLobby = false
    State._coinDidInitialStage = false
    State._coinFirstApproach = false
    State._coinCloseBoost = false
    safeDisconnect(State._noclipConn)
    State._noclipConn = nil
    restoreCoinPhysics()
    destroyCoinStagePlatform()

    local root = getRoot()
    if hadPhysicalMove and root and returnCF then
        _pcall(function()
            root.Anchored = false
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            root.CFrame = returnCF
        end)
    end
    State._coinHadPhysicalMove = false
end

local function primeCoinEntry(reason)
    if not Alive or not State.coinCollect then return end
    State._coinEntryPrime = testerTime() + 4
    State.coinStatus = "Entry armed"
    if not State.collecting then startCoinCollect() end
end

local function suspendCoinMovementOnRoundEnd()
    local hadPhysicalMove = State._coinHadPhysicalMove == true
        or hasCoinPhysicsActive()
        or State._coinStagePlatform ~= nil
    local returnCF = hadPhysicalMove and findCoinReturnCFrame() or nil
    suspendCoinMovement("Round ended - grounded wait", false)
    State._coinEntryPrime = 0
    State._coinIgnoreUntil = {}
    State._coinDidInitialStage = false
    State._coinStartedInLobby = true
    State._coinFirstApproach = true
    State._coinCloseBoost = false

    local root = getRoot()
    if hadPhysicalMove and root and returnCF then
        _pcall(function()
            root.Anchored = false
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            root.CFrame = returnCF
        end)
    end
    State._coinHadPhysicalMove = false
end

local function scoreLobbyCandidate(part)
    if not part or not part:IsA("BasePart") then return -1 end
    local path = string.lower(getObjectPath(part))
    local name = string.lower(part.Name or "")
    local score = 0
    if path:find("lobby", 1, true) then score = score + 120 end
    if name:find("lobby", 1, true) then score = score + 120 end
    if name:find("spawn", 1, true) then score = score + 35 end
    if path:find("spawn", 1, true) then score = score + 25 end
    if part:IsA("SpawnLocation") then score = score + 25 end
    if path:find("bank2", 1, true) or path:find("factory", 1, true) or path:find("office3", 1, true)
    or path:find("hotel", 1, true) or path:find("hospital3", 1, true) or path:find("mansion2", 1, true)
    or path:find("researchfacility", 1, true) or path:find("milbase", 1, true) then
        score = score - 80
    end
    if part.Position.Y < -20 then score = score - 100 end
    return score
end

local function findLobbySpawn()
    local best, bestScore = nil, -1
    local desc = nil
    _pcall(function() desc = workspace:GetDescendants() end)
    if not desc then return nil end
    for _, obj in ipairs(desc) do
        local ok, isPart = _pcall(function() return obj:IsA("BasePart") end)
        if ok and isPart then
            local score = scoreLobbyCandidate(obj)
            if score > bestScore then
                best = obj
                bestScore = score
            end
        end
    end
    if bestScore >= 35 then return best end
    return nil
end

local function returnToLobby()
    if State._returningLobby then return end
    State._returningLobby = true
    _spawn(function()
        _wait(0.12)
        local root = getRoot()
        local spawnPart = findLobbySpawn()
        if root and spawnPart then
            _pcall(function()
                root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                root.CFrame = CFrame.new(spawnPart.Position + Vector3.new(0, 4, 0))
            end)
        end
        State._returningLobby = false
    end)
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
    State.localDead = false
end

local function setRoleForPlayer(pname, role)
    if type(role) ~= "string" or role == "" then return end
    if type(pname) ~= "string" or pname == "" then
        pname = LocalPlayer.Name
    end
    State.roles[pname] = role
    if pname == LocalPlayer.Name then
        State.localRole = role ~= "?" and role or nil
        if role ~= "?" then
            State.localDead = false
        end
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
        if not pname or pname == LocalPlayer.Name then
            State.localDead = true
            State.localRole = nil
            State.lastGunDropStatus = "Dead / no role"
        end
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
        State.localDead = false
        resetAllRoles()
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("RoundStart")
        if State.coinCollect then primeCoinEntry(State.lastRoundSignal) end
    end)

    bindRemoteEvent({"Remotes","Gameplay","RoleSelect"}, function(...)
        State.currentPhase = "Role Select"
        State.lastRoundSignal = "RoleSelect"
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("RoleSelect")
        if State.coinCollect then
            if not State.collecting then startCoinCollect() end
            _spawn(function()
                for _ = 1, 8 do
                    if not Alive or not State.coinCollect or not isCoinStagePhase() then break end
                    if prepareCoinStagePlatform() then break end
                    _wait(0.08)
                end
            end)
        end
    end)

    bindRemoteEvent({"Remotes","Gameplay","GiveWeapon"}, function(...)
        State.lastRoundSignal = "GiveWeapon"
        State._lastGiveWeaponAt = testerTime()
        State._lastGiveWeaponName = "Unknown"
        if State.currentPhase == "Unknown" or State.currentPhase == "Lobby" or State.currentPhase == "Role Select" then
            State.currentPhase = "Round"
        end
        for _, v in ipairs({...}) do
            if type(v) == "string" then
                State._lastGiveWeaponName = v
            elseif type(v) == "table" then
                State._lastGiveWeaponName = tostring(v.Weapon or v.Tool or v.Name or State._lastGiveWeaponName)
            end
            parsePlayerDataPayload(v, nil, 0)
        end
        if State.gunDropOn and isLocalAlive() and findTool("Gun") ~= nil then
            State.lastGunDropStatus = "GiveWeapon"
        end
        refreshRolesBurst("GiveWeapon")
        if State.coinCollect then primeCoinEntry(State.lastRoundSignal) end
    end)

    bindRemoteEvent({"Remotes","Gameplay","LoadingMap"}, function(...)
        State.currentPhase = "Loading Map"
        State.lastRoundSignal = "LoadingMap"
        resetAllRoles()
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("LoadingMap")
        if State.coinCollect then
            if not State.collecting then startCoinCollect() end
            _spawn(function()
                for _ = 1, 12 do
                    if not Alive or not State.coinCollect or not isCoinStagePhase() then break end
                    if prepareCoinStagePlatform() then break end
                    _wait(0.12)
                end
            end)
        end
    end)

    bindRemoteEvent({"Remotes","Gameplay","ShowRoleSelect"}, function(...)
        State.currentPhase = "Role Select"
        State.lastRoundSignal = "ShowRoleSelect"
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("ShowRoleSelect")
        if State.coinCollect then
            if not State.collecting then startCoinCollect() end
            _spawn(function()
                for _ = 1, 8 do
                    if not Alive or not State.coinCollect or not isCoinStagePhase() then break end
                    if prepareCoinStagePlatform() then break end
                    _wait(0.08)
                end
            end)
        end
    end)

    bindRemoteEvent({"Remotes","Gameplay","ShowRoleSelectNew"}, function(...)
        State.currentPhase = "Role Select"
        State.lastRoundSignal = "ShowRoleSelectNew"
        for _, v in ipairs({...}) do
            parsePlayerDataPayload(v, nil, 0)
        end
        refreshRolesBurst("ShowRoleSelectNew")
        if State.coinCollect then
            if not State.collecting then startCoinCollect() end
            _spawn(function()
                for _ = 1, 8 do
                    if not Alive or not State.coinCollect or not isCoinStagePhase() then break end
                    if prepareCoinStagePlatform() then break end
                    _wait(0.08)
                end
            end)
        end
    end)

    bindRemoteEvent({"Remotes","Gameplay","VictoryScreen"}, function(...)
        local hadCoinCollect = State.coinCollect == true
        local hadCoinPhysical = State._coinHadPhysicalMove == true or hasCoinPhysicsActive() or State._coinStagePlatform ~= nil
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
        if hadCoinCollect then
            suspendCoinMovementOnRoundEnd()
        end
    end)

    local function markLobby(signal)
        local hadCoinCollect = State.coinCollect == true
        local hadCoinPhysical = State._coinHadPhysicalMove == true or hasCoinPhysicsActive() or State._coinStagePlatform ~= nil
        State.currentPhase = "Lobby"
        State.lastLobbySignal = signal
        State.lastRoundSignal = signal
        State.localRole = nil
        State.localDead = true
        resetAllRoles()
        State.localDead = true
        if hadCoinCollect then
            suspendCoinMovementOnRoundEnd()
        end
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
                if player == LocalPlayer then
                    State.localDead = true
                    State.localRole = nil
                    State.lastGunDropStatus = "Dead / no role"
                    State.gunDropOn = false
                    State._gunDropWatch = false
                    safeDisconnect(State._gunDropConn)
                    State._gunDropConn = nil
                    if State._gunDropToggle and State._gunDropToggle.Set then
                        _pcall(function() State._gunDropToggle:Set(false) end)
                    end
                end
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

local function canCollectGunDrop()
    if not State.gunDropOn then return false, "Off" end
    if State.currentPhase == "Lobby" or State.currentPhase == "Ending" or State.currentPhase == "Loading Map" then
        return false, "Waiting for round"
    end
    if State.localDead == true then return false, "Dead / no role" end
    if not State.localRole or State.localRole == "?" then return false, "No role" end
    if State.localRole == "Murderer" then return false, "Murderer - ignored" end
    if not isLocalAlive() then return false, "Dead" end
    return true, "OK"
end

local function hasGunTool()
    return findTool("Gun") ~= nil
end

local function tryGiveWeaponRequest(gd)
    local remote = getRemote({"Remotes","Gameplay","GiveWeapon"})
    if not remote then return false end
    local okAny = false
    if remote:IsA("RemoteFunction") then
        local tries = {
            function() return remote:InvokeServer("Gun") end,
            function() return remote:InvokeServer("Gun", gd) end,
            function() return remote:InvokeServer(gd) end,
        }
        for _, fn in ipairs(tries) do
            local ok = _pcall(fn)
            okAny = okAny or ok
            if hasGunTool() then return true end
        end
    elseif remote:IsA("RemoteEvent") then
        local tries = {
            function() remote:FireServer("Gun") end,
            function() remote:FireServer("Gun", gd) end,
            function() remote:FireServer(gd) end,
        }
        for _, fn in ipairs(tries) do
            local ok = _pcall(fn)
            okAny = okAny or ok
            if hasGunTool() then return true end
        end
    end
    return okAny
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
        if not Alive or not State.gunDropOn or not gd or not gd.Parent or not canCollectGunDrop() then break end
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
        local can = canCollectGunDrop()
        if not can then break end
        local r = getRoot()
        if not r then break end
        local targetPos = gd.Position + Vector3.new(0, 2.15, 0)
        local delta = targetPos - r.Position
        local dist = delta.Magnitude
        if dist <= 3.2 then break end
        local stepTime = 0.025
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
    local can, why = canCollectGunDrop()
    if not can then
        State.lastGunDropStatus = why
        return false
    end

    State.lastGunDropStatus = "Collecting"
    State.lastGunDropPath = getObjectPath(gd)
    ensureGunDropEsp(gd)

    if hasGunTool() then
        State.lastGunDropStatus = "Already armed"
        return true
    end

    local char = getChar()
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                _pcall(function() part.CanCollide = false end)
            end
        end
    end

    local giveStart = State._lastGiveWeaponAt or 0

    fireTouchGunDrop(gd)
    tryGiveWeaponRequest(gd)
    if hasGunTool() or (State._lastGiveWeaponAt or 0) > giveStart then
        State.lastGunDropStatus = "GiveWeapon"
        return true
    end
    if not (gd and gd.Parent) then
        State.lastGunDropStatus = "Collected"
        return true
    end

    moveNearGunDrop(gd)

    local attempts = 0
    while Alive and State.gunDropOn and gd and gd.Parent and attempts < 9 do
        local okNow = canCollectGunDrop()
        if not okNow then break end
        attempts = attempts + 1
        fireTouchGunDrop(gd)
        hardTouchGunDrop(gd)
        tryGiveWeaponRequest(gd)
        if hasGunTool() or (State._lastGiveWeaponAt or 0) > giveStart then
            State.lastGunDropStatus = "GiveWeapon"
            return true
        end
        _wait(0.1)
    end

    local collected = not (gd and gd.Parent) or hasGunTool() or (State._lastGiveWeaponAt or 0) > giveStart
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
                local can = canCollectGunDrop()
                if Alive and State.gunDropOn and can and gd and gd.Parent then
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
            local can, why = canCollectGunDrop()
            if gd and can then
                collectGunDrop(gd)
                _wait(0.22)
            else
                if not can then State.lastGunDropStatus = why end
                _wait(0.45)
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

W:Section("  COMBAT TESTER")

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
W:Toggle("Manual Shoot Murderer", false, function(v) State.manualSilent = v end)

W:Button("Shoot Murderer", function()
    local ok = Tester.ShootMurderer()
    if not ok then -- feedback visual curto
        _spawn(function() _wait(0.1) end)
    end
end)
W:Button("Throw Knife Nearest",  function() Tester.ThrowKnife()  end)
W:Button("Stab Nearest",  function() Tester.StabTarget()  end)
W:Button("Touch Nearest", function() Tester.TouchTarget() end)


-- ── COIN COLLECT ───────────────────────────────────────────────────────────────

W:Section("  COINS")

State._coinToggle = W:Toggle("Coin Collect", false, function(v)
    State.coinCollect = v
    if v then
        State._coinStartedInLobby = isCoinArmedOnlyPhase()
        State._coinDidInitialStage = false
        State._coinHadPhysicalMove = false
        State._coinFirstApproach = true
        State._coinUnderOffset = 3.55
        rememberSafeCFrame(true)
        startCoinCollect()
    else
        stopCoinCollect()
    end
end)

W:Slider("Speed", 1, 6, 4, function(v)
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

State._gunDropToggle = W:Toggle("Auto Collect GunDrop", false, function(v)
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
            dataLbl.Text = "Role: "..tostring(localRole).." | Coins: "..tostring(State.coinCount or 0).."/"..tostring(State.coinLimit or 40).." | Coin: "..tostring(State.coinStatus or "Idle")
            gunDropLbl.Text = "GunDrop: "..tostring(State.lastGunDropStatus or "Missing").." | "..tostring(State.lastGunDropDistance or "N/A").." | GiveWeapon: "..tostring(State._lastGiveWeaponName or "None")
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
