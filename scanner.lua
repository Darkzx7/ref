local RefLib = loadstring(game:HttpGet", true))()
if not RefLib then error("[mm2] ERRO: RefLib nao carregou.") end

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local VirtualUser       = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local cam    = workspace.CurrentCamera

local ui = RefLib.new("mm v20", "rbxassetid://131165537896572", "ref_mmv20")

-- ══════════════════════════════════════════════════════════════════════════════
-- REMOTES
-- ══════════════════════════════════════════════════════════════════════════════

local GetCoinEvent
pcall(function() GetCoinEvent = ReplicatedStorage.Remotes.Gameplay.GetCoin end)

local PlayerDataChangedBind
pcall(function()
    PlayerDataChangedBind = ReplicatedStorage
        :WaitForChild("Modules", 5)
        :WaitForChild("CurrentRoundClient", 5)
        :WaitForChild("PlayerDataChanged", 5)
end)

local RoleSelectEvent
pcall(function() RoleSelectEvent = ReplicatedStorage.Remotes.Gameplay.RoleSelect end)

-- ══════════════════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ══════════════════════════════════════════════════════════════════════════════

local KNIFE_NAMES   = { Knife = true }
local GUN_NAMES     = { Gun = true, ["Sheriff's Gun"] = true, Revolver = true, SheriffGun = true, GunDrop = true }
local GUNDROP_NAMES = { GunDrop = true }

local CHARACTER_HIT_PARTS = {
    "HumanoidRootPart","UpperTorso","LowerTorso","Head",
    "RightUpperArm","LeftUpperArm","RightUpperLeg","LeftUpperLeg",
    "RightLowerArm","LeftLowerArm","RightLowerLeg","LeftLowerLeg",
    "RightHand","LeftHand","RightFoot","LeftFoot",
    "Torso","Right Arm","Left Arm","Right Leg","Left Leg",
}

local ROLE_COLOR = {
    murderer = Color3.fromRGB(220, 55, 55),
    sheriff  = Color3.fromRGB(55, 180, 220),
    hero     = Color3.fromRGB(255, 165, 0),
    innocent = Color3.fromRGB(80, 210, 80),
    unknown  = Color3.fromRGB(150, 150, 160),
}
local ROLE_LABEL = {
    murderer="Murderer", sheriff="Sheriff", hero="Hero", innocent="Innocent", unknown="?"
}

-- ══════════════════════════════════════════════════════════════════════════════
-- CACHE
-- ══════════════════════════════════════════════════════════════════════════════

local playerDataCache = {}
local roleCache       = {}

if PlayerDataChangedBind then
    PlayerDataChangedBind.Event:Connect(function(data)
        if type(data) ~= "table" then return end
        for u, i in pairs(data) do playerDataCache[u] = i end
    end)
end

local function hookUD(n) pcall(function()
    local ev = ReplicatedStorage:FindFirstChild(n)
    if ev and ev:IsA("RemoteEvent") then
        ev.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            for u, i in pairs(data) do if type(i) == "table" then playerDataCache[u] = i end end
        end)
    end
end) end
hookUD("UpdateData"); hookUD("UpdateData2"); hookUD("UpdateData3")

pcall(function()
    ReplicatedStorage.Remotes.Gameplay.RoundStart.OnClientEvent:Connect(function()
        playerDataCache = {}; roleCache = {}
    end)
end)

pcall(function()
    ReplicatedStorage.Remotes.Gameplay.GiveWeapon.OnClientEvent:Connect(function(w)
        local n = type(w) == "string" and w:lower() or (typeof(w) == "Instance" and w.Name:lower() or "")
        if n:find("knife") then roleCache[player] = "murderer"
        elseif n:find("gun") or n:find("sheriff") or n:find("revolver") then roleCache[player] = "sheriff" end
    end)
end)

pcall(function()
    ReplicatedStorage.Remotes.Gameplay.PlayerDataChanged.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        for u, i in pairs(data) do
            if type(i) == "table" then
                playerDataCache[u] = i
                if i.Role then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.Name == u then
                            local low = i.Role:lower()
                            roleCache[p] = low:find("murder") and "murderer" or low:find("sheriff") and "sheriff" or "innocent"
                        end
                    end
                end
            end
        end
    end)
end)

pcall(function()
    ReplicatedStorage.Remotes.Gameplay.ShowRoleSelectNew.OnClientEvent:Connect(function()
        task.wait(0.5)
        for _, p in ipairs(Players:GetPlayers()) do
            local bp, chr = p:FindFirstChild("Backpack"), p.Character
            local function hasIn(c, names)
                if not c then return false end
                for n in pairs(names) do if c:FindFirstChild(n) then return true end end
                return false
            end
            if hasIn(chr, KNIFE_NAMES) or hasIn(bp, KNIFE_NAMES) then roleCache[p] = "murderer"
            elseif hasIn(chr, GUN_NAMES) or hasIn(bp, GUN_NAMES) then roleCache[p] = "sheriff" end
        end
    end)
end)

if RoleSelectEvent then
    RoleSelectEvent.OnClientEvent:Connect(function(r)
        if not r then return end
        local low = tostring(r):lower()
        roleCache[player] = low:find("murder") and "murderer" or low:find("sheriff") and "sheriff" or "innocent"
    end)
end

player.CharacterAdded:Connect(function()
    playerDataCache = {}; roleCache[player] = nil
    local bp = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 5)
    if bp then
        bp.ChildAdded:Connect(function(c)
            if KNIFE_NAMES[c.Name] then roleCache[player] = "murderer"
            elseif GUNDROP_NAMES[c.Name] then roleCache[player] = "hero"
            elseif GUN_NAMES[c.Name] then roleCache[player] = "sheriff" end
        end)
    end
end)

local function watchPlayerBackpack(p)
    if p == player then return end
    local function onAdd(c)
        if KNIFE_NAMES[c.Name] then roleCache[p] = "murderer"
        elseif GUNDROP_NAMES[c.Name] then roleCache[p] = "hero"
        elseif c.Name == "Gun" or c.Name == "Sheriff's Gun" or c.Name == "Revolver" or c.Name == "SheriffGun" then
            roleCache[p] = "sheriff" end
    end
    local bp = p:FindFirstChild("Backpack"); if bp then bp.ChildAdded:Connect(onAdd) end
    local chr = p.Character; if chr then chr.ChildAdded:Connect(onAdd) end
end

local function watchPlayerFull(p)
    watchPlayerBackpack(p)
    p.CharacterAdded:Connect(function()
        -- FIX #10: aumentado de 0.3 para 1.2s para dar tempo ao servidor atribuir o papel
        roleCache[p] = nil; task.wait(1.2); watchPlayerBackpack(p)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do if p ~= player then watchPlayerFull(p) end end
Players.PlayerAdded:Connect(function(p) if p ~= player then watchPlayerFull(p) end end)

workspace.DescendantRemoving:Connect(function(obj)
    if not GUNDROP_NAMES[obj.Name] then return end
    task.wait(0.15)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        local bp, chr = p:FindFirstChild("Backpack"), p.Character
        for n in pairs(GUN_NAMES) do
            if (bp and bp:FindFirstChild(n)) or (chr and chr:FindFirstChild(n)) then
                if roleCache[p] ~= "murderer" then roleCache[p] = "hero" end; break
            end
        end
    end
end)

task.defer(function()
    local bp = player:FindFirstChild("Backpack"); if not bp then return end
    for n in pairs(KNIFE_NAMES) do if bp:FindFirstChild(n) then roleCache[player] = "murderer" end end
    for n in pairs(GUNDROP_NAMES) do if bp:FindFirstChild(n) then roleCache[player] = "hero" end end
    for _, n in ipairs({"Gun","Sheriff's Gun","Revolver","SheriffGun"}) do
        if bp:FindFirstChild(n) then roleCache[player] = "sheriff" end
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

local function isAlive(p)
    local d = playerDataCache[p.Name]; if d then return d.Dead ~= true end
    local a = p:GetAttribute("Alive"); if a ~= nil then return a == true end
    local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function getRole(p)
    p = p or player
    local d = playerDataCache[p.Name]
    if d and d.Role then
        local low = d.Role:lower()
        if low == "murderer" then return "murderer" end
        if low == "sheriff"  then return "sheriff"  end
        if low == "hero"     then return "hero"     end
        if low == "innocent" then return "innocent" end
    end
    if roleCache[p] then return roleCache[p] end
    local attr = p:GetAttribute("Role")
    if attr then
        local low = attr:lower()
        if low:find("murder")   then return "murderer" end
        if low:find("sheriff")  then return "sheriff"  end
        if low:find("hero")     then return "hero"     end
        if low:find("innocent") then return "innocent" end
    end
    local bp, chr = p:FindFirstChild("Backpack"), p.Character
    local function hasIn(c, names)
        if not c then return false end
        for n in pairs(names) do if c:FindFirstChild(n) then return true end end
        return false
    end
    if hasIn(chr, KNIFE_NAMES) or hasIn(bp, KNIFE_NAMES) then return "murderer" end
    local function hasDrop(c)
        if not c then return false end
        for n in pairs(GUNDROP_NAMES) do if c:FindFirstChild(n) then return true end end
        return false
    end
    local function hasGunOrig(c)
        if not c then return false end
        local G = {Gun=true,["Sheriff's Gun"]=true,Revolver=true,SheriffGun=true}
        for n in pairs(G) do if c:FindFirstChild(n) then return true end end
        return false
    end
    if hasDrop(chr) or hasDrop(bp) then return "hero" end
    if hasGunOrig(chr) or hasGunOrig(bp) then return "sheriff" end
    return "innocent"
end

local function findByRole(role)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and isAlive(p) and getRole(p) == role then return p end
    end
end

local function myHRP()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function isValidPos(pos)
    return pos and pos == pos and pos.Magnitude < 100000
end

local function isRoundActive()
    for _, o in ipairs(workspace:GetDescendants()) do if o.Name == "GunDrop" then return true end end
    local r = workspace:FindFirstChild("RoundTimerPart")
    return r and #r:GetChildren() > 0
end

-- ══════════════════════════════════════════════════════════════════════════════
-- TOOL HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

local function getGunTool()
    local bp, chr = player:FindFirstChild("Backpack"), player.Character
    for name in pairs(GUN_NAMES) do
        if chr then local t = chr:FindFirstChild(name); if t then return t end end
        if bp  then local t = bp:FindFirstChild(name);  if t then return t end end
    end
end

local function getKnifeTool()
    local bp, chr = player:FindFirstChild("Backpack"), player.Character
    for name in pairs(KNIFE_NAMES) do
        if chr and chr:FindFirstChild(name) then return chr:FindFirstChild(name) end
        if bp  and bp:FindFirstChild(name)  then return bp:FindFirstChild(name)  end
    end
end

local function equipTool(tool)
    local chr = player.Character; if not chr then return false end
    local hum = chr:FindFirstChildOfClass("Humanoid"); if not hum then return false end
    pcall(function() hum:EquipTool(tool) end); task.wait(0.12)
    return chr:FindFirstChild(tool.Name) ~= nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SILENT AIM
-- FIX #7: removido o RenderStepped que travava a câmera continuamente.
-- A câmera agora só é direcionada no momento exato do disparo.
-- ══════════════════════════════════════════════════════════════════════════════

local silentAimOn = false
local SA_PRED     = 0.165
local SA_FOV      = 9999
local _prevPos    = {}
local _prevTime   = {}

local function getPredictedPos(tp)
    if not tp then return nil end
    local chr = tp.Character; if not chr then return nil end
    local part = chr:FindFirstChild("Head") or chr:FindFirstChild("HumanoidRootPart")
    if not part then return nil end
    local now = tick()
    local cur = part.Position
    local prev = _prevPos[tp]; local pt = _prevTime[tp]
    local pred = cur
    if prev and pt then
        local dt = now - pt
        if dt > 0.001 and dt < 0.5 then
            pred = cur + (cur - prev) / dt * SA_PRED
        end
    end
    _prevPos[tp] = cur; _prevTime[tp] = now
    return pred
end

local function getSilentTarget()
    local r = getRole()
    if r == "sheriff" or r == "hero" then return findByRole("murderer") end
    if r == "murderer" then
        local hrp = myHRP(); if not hrp then return nil end
        local best, bestD = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and isAlive(p) then
                local ph = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if ph then
                    local d = (hrp.Position - ph.Position).Magnitude
                    if d < bestD then best = p; bestD = d end
                end
            end
        end
        return best
    end
end

-- FIX #7: atualiza predição no RenderStepped sem travar câmera
RunService.RenderStepped:Connect(function()
    if not silentAimOn then return end
    local target = getSilentTarget(); if not target then return end
    -- apenas atualiza o cache de posição para predição ser mais precisa
    getPredictedPos(target)
end)

local _shootCd = false
local function fireWithSilentAim()
    if _shootCd then return false end
    local target = getSilentTarget(); if not target then return false end
    local hitPos = getPredictedPos(target); if not hitPos then return false end
    local gunTool = getGunTool(); if not gunTool then return false end
    local chr = player.Character; if not chr then return false end
    if not chr:FindFirstChild(gunTool.Name) then
        equipTool(gunTool)
        chr = player.Character; if not chr then return false end
        gunTool = getGunTool(); if not gunTool then return false end
    end
    _shootCd = true
    -- FIX #7: câmera só é virada no momento do disparo, não continuamente
    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, hitPos)
    pcall(function() gunTool:Activate() end)
    task.delay(0.65, function() _shootCd = false end)
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
-- DUMP — FIX #2 e #3: variáveis declaradas + hook implementado no FireServer
-- ══════════════════════════════════════════════════════════════════════════════

local dumpActive   = false  -- FIX #2: declarado corretamente
local dumpCallback = nil    -- FIX #2: declarado corretamente

-- FIX #3: hook real no FireServer para capturar argumentos
local function installHook()
    local mt = getrawmetatable(game)
    if not mt then return end
    local oldIndex = mt.__index
    local oldNamecall = mt.__namecall
    if not oldNamecall then return end
    local ok = pcall(setreadonly, mt, false)
    if not ok then return end
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if dumpActive and method == "FireServer" then
            local args = {...}
            -- Verifica se é a gun do player
            local gunTool = getGunTool()
            if gunTool and self == gunTool then
                dumpActive = false
                local desc = {}
                for i, v in ipairs(args) do
                    local t = typeof(v)
                    local rep = ""
                    if t == "CFrame" then
                        rep = string.format("CFrame(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
                    elseif t == "Vector3" then
                        rep = string.format("Vector3(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
                    elseif t == "Instance" then
                        rep = "Instance: "..v.ClassName.." ["..v.Name.."]"
                    else
                        rep = tostring(v)
                    end
                    table.insert(desc, string.format("[%d] (%s) = %s", i, t, rep))
                end
                if dumpCallback then
                    task.spawn(dumpCallback, desc)
                    dumpCallback = nil
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    pcall(setreadonly, mt, true)
end
task.defer(installHook)

-- ══════════════════════════════════════════════════════════════════════════════
-- KNIFE
-- ══════════════════════════════════════════════════════════════════════════════

local function knifeAt(targetChar)
    if not targetChar then return false end
    local hrp  = myHRP(); if not hrp then return false end
    local tHRP = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Head")
    if not tHRP then return false end
    local knife = getKnifeTool()
    if not knife then
        local bp = player:FindFirstChild("Backpack"); if bp then
            for name in pairs(KNIFE_NAMES) do
                local t = bp:FindFirstChild(name); if t then equipTool(t); knife = getKnifeTool(); break end
            end
        end
    end
    if not knife then return false end
    hrp.CFrame = CFrame.lookAt(hrp.Position, tHRP.Position); task.wait(0.03)
    pcall(function() knife:Activate() end); return true
end

-- ══════════════════════════════════════════════════════════════════════════════
-- HITBOX EXPANDER
-- FIX #9: getMyParts agora tem cache por frame (invalidado no Heartbeat)
-- ══════════════════════════════════════════════════════════════════════════════

local hitboxOn      = false
local hitboxSize    = 12
local hitboxVisible = false
local hitboxCache   = {}

local _myPartsCache = nil
local _myPartsCacheFrame = -1
local function getMyParts()
    local frame = workspace:GetServerTimeNow and workspace:GetServerTimeNow() or tick()
    if _myPartsCache and (tick() - _myPartsCacheFrame) < 0.1 then
        return _myPartsCache
    end
    local chr = player.Character
    if not chr then _myPartsCache = {}; _myPartsCacheFrame = tick(); return {} end
    local parts = {}
    for _, p in ipairs(chr:GetDescendants()) do if p:IsA("BasePart") then table.insert(parts, p) end end
    _myPartsCache = parts
    _myPartsCacheFrame = tick()
    return parts
end

-- Invalida cache quando o character muda
player.CharacterAdded:Connect(function() _myPartsCache = nil end)

local function applyHitboxToChar(p)
    if not p or p == player then return end
    local chr = p.Character; if not chr then return end
    if hitboxCache[p] then return end
    local myParts = getMyParts(); local saved = {}
    for _, part in ipairs(chr:GetDescendants()) do
        if not part:IsA("BasePart") then continue end
        if part.Parent:IsA("Accessory") or part.Parent:IsA("Tool") then continue end
        local os = part.Size; local ot = part.Transparency
        local maxD = math.max(os.X, os.Y, os.Z, 0.1); local sc = hitboxSize / maxD; local cons = {}
        if sc > 1 then pcall(function() part.Size = os * sc end) end
        if hitboxVisible then pcall(function() part.Transparency = 0.5 end) end
        for _, mp in ipairs(myParts) do pcall(function()
            local nc = Instance.new("NoCollisionConstraint")
            nc.Part0 = part; nc.Part1 = mp; nc.Parent = part; table.insert(cons, nc)
        end) end
        table.insert(saved, {part=part, size=os, transp=ot, constraints=cons})
    end
    hitboxCache[p] = saved
end

local function restoreHitbox(p)
    local saved = hitboxCache[p]; if not saved then return end
    for _, d in ipairs(saved) do
        if d.part and d.part.Parent then
            pcall(function() d.part.Size = d.size; d.part.Transparency = d.transp end)
        end
        for _, nc in ipairs(d.constraints) do
            pcall(function() if nc and nc.Parent then nc:Destroy() end end)
        end
    end
    hitboxCache[p] = nil
end

local function restoreAllHitboxes()
    local ps = {}
    for p in pairs(hitboxCache) do table.insert(ps, p) end
    for _, p in ipairs(ps) do restoreHitbox(p) end
    hitboxCache = {}
end

local function applyHBVis(v)
    for _, saved in pairs(hitboxCache) do
        for _, d in ipairs(saved) do
            if d.part and d.part.Parent then
                pcall(function() d.part.Transparency = v and 0.5 or d.transp end)
            end
        end
    end
end

player.CharacterAdded:Connect(function()
    if not hitboxOn then return end; task.wait(1)
    for p in pairs(hitboxCache) do hitboxCache[p] = nil end
    for _, p in ipairs(Players:GetPlayers()) do applyHitboxToChar(p) end
end)
Players.PlayerRemoving:Connect(function(p) hitboxCache[p] = nil end)
Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function()
    hitboxCache[p] = nil; if hitboxOn then task.wait(1); applyHitboxToChar(p) end
end) end)
for _, p in ipairs(Players:GetPlayers()) do if p ~= player then p.CharacterAdded:Connect(function()
    hitboxCache[p] = nil; if hitboxOn then task.wait(1); applyHitboxToChar(p) end
end) end end

-- ══════════════════════════════════════════════════════════════════════════════
-- SKELETON ESP
-- ══════════════════════════════════════════════════════════════════════════════

local espOn  = false
local espMax = 300

local CONN_R15 = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
}
local R6_NAME = {Head="Head",Torso="Torso",LeftArm="Left Arm",RightArm="Right Arm",LeftLeg="Left Leg",RightLeg="Right Leg"}
local CONN_R6 = {
    {"Head","Torso"},{"Torso","LeftArm"},{"Torso","RightArm"},{"Torso","LeftLeg"},{"Torso","RightLeg"},
}

local espData = {}

local function getESPColor(p)
    if not isRoundActive() then return Color3.new(1,1,1) end
    return ROLE_COLOR[getRole(p)] or ROLE_COLOR.unknown
end

local function allocForPlayer(p)
    if espData[p] then return end
    local chr = p.Character; if not chr then return end
    local hrp = chr:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local hum = chr:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local isR15 = hum.RigType == Enum.HumanoidRigType.R15
    local conns = isR15 and CONN_R15 or CONN_R6

    local lines = {}
    for i = 1, #conns do
        local l = Drawing.new("Line")
        l.Thickness    = 2
        l.Visible      = false
        l.Transparency = 1
        lines[i] = l
    end

    local bb = Instance.new("BillboardGui")
    bb.Size=UDim2.new(0,120,0,32); bb.StudsOffset=Vector3.new(0,3.2,0)
    bb.AlwaysOnTop=true; bb.ResetOnSpawn=false; bb.Adornee=hrp; bb.Parent=hrp

    local nm = Instance.new("TextLabel")
    nm.BackgroundTransparency=1; nm.Size=UDim2.new(1,0,0,18)
    nm.Font=Enum.Font.GothamBold; nm.TextSize=12; nm.TextColor3=getESPColor(p)
    nm.TextStrokeTransparency=0.05; nm.TextXAlignment=Enum.TextXAlignment.Center
    nm.Text=p.DisplayName; nm.Parent=bb

    local dl = Instance.new("TextLabel")
    dl.BackgroundTransparency=1; dl.Size=UDim2.new(1,0,0,12); dl.Position=UDim2.new(0,0,0,19)
    dl.Font=Enum.Font.Gotham; dl.TextSize=10
    dl.TextColor3=Color3.fromRGB(210,210,230)
    dl.TextXAlignment=Enum.TextXAlignment.Center; dl.Parent=bb

    espData[p] = { lines=lines, conns=conns, isR15=isR15, bb=bb, nm=nm, dl=dl }
end

local function freePlayer(p)
    local d = espData[p]; if not d then return end
    for _, l in ipairs(d.lines) do pcall(function() l:Remove() end) end
    pcall(function() if d.bb and d.bb.Parent then d.bb:Destroy() end end)
    espData[p] = nil
end

local function hidePlayer(p)
    local d = espData[p]; if not d then return end
    for _, l in ipairs(d.lines) do l.Visible = false end
    if d.bb then d.bb.Enabled = false end
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= player then task.spawn(function() task.wait(2); allocForPlayer(p) end) end
end
Players.PlayerAdded:Connect(function(p)
    if p == player then return end
    p.CharacterAdded:Connect(function()
        freePlayer(p)
        task.wait(1.5); allocForPlayer(p)
    end)
end)
Players.PlayerRemoving:Connect(freePlayer)
for _, p in ipairs(Players:GetPlayers()) do if p ~= player then p.CharacterAdded:Connect(function()
    freePlayer(p); task.wait(1.5); allocForPlayer(p)
end) end end

RunService.RenderStepped:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        local d = espData[p]

        if not espOn then
            if d then hidePlayer(p) end
            continue
        end

        local chr = p.Character
        local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
        if not chr or not hrp or not isAlive(p) then
            if d then hidePlayer(p) end; continue
        end

        local dist = (cam.CFrame.Position - hrp.Position).Magnitude
        if dist > espMax then
            if d then hidePlayer(p) end; continue
        end

        if not d then continue end

        if d.bb then d.bb.Enabled = true end
        local col = getESPColor(p)
        if d.nm then d.nm.TextColor3 = col; d.nm.Text = p.DisplayName end
        if d.dl then d.dl.Text = math.floor(dist).."m  ["..(isRoundActive() and ROLE_LABEL[getRole(p)] or "Lobby").."]" end

        local function getPart(name)
            if d.isR15 then return chr:FindFirstChild(name) end
            return chr:FindFirstChild(R6_NAME[name] or name)
        end

        for i, conn in ipairs(d.conns) do
            local line = d.lines[i]; if not line then continue end
            local jA = getPart(conn[1])
            local jB = getPart(conn[2])
            if jA and jB then
                local pA = cam:WorldToViewportPoint(jA.Position)
                local pB = cam:WorldToViewportPoint(jB.Position)
                line.Color   = col
                line.From    = Vector2.new(pA.X, pA.Y)
                line.To      = Vector2.new(pB.X, pB.Y)
                line.Visible = (pA.Z > 0 or pB.Z > 0)
            else
                line.Visible = false
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- FINDERS
-- ══════════════════════════════════════════════════════════════════════════════

local function findDroppedGuns()
    local found = {}
    for _, o in ipairs(workspace:GetDescendants()) do
        if GUNDROP_NAMES[o.Name] and o:IsA("BasePart") then
            table.insert(found, {tool=o, handle=o})
        end
    end
    return found
end

local function findAllCoinServers()
    local coins = {}; local seen = {}
    local CN = {Coin_Server=true, Coin=true, CoinPart=true, MainCoin=true, CoinValue=true}
    for _, o in ipairs(workspace:GetDescendants()) do
        if CN[o.Name] and o:IsA("BasePart") and not seen[o] and isValidPos(o.Position) then
            seen[o] = true; table.insert(coins, o)
        end
    end
    return coins
end

-- ══════════════════════════════════════════════════════════════════════════════
-- COIN FARM
-- FIX #5: flyTo agora restaura CanCollide ao terminar
-- FIX #8: myHRP() chamado apenas uma vez por uso
-- ══════════════════════════════════════════════════════════════════════════════

local FARM_FLY_SPEED   = 16
local farmPauseBetween = 0.8

local function flyTo(dest)
    local hrp = myHRP(); if not hrp then return end
    local chr = player.Character; if not chr then return end

    -- Desativa colisão
    local collisionStates = {}
    for _, p in ipairs(chr:GetDescendants()) do
        if p:IsA("BasePart") then
            collisionStates[p] = p.CanCollide
            pcall(function() p.CanCollide = false end)
        end
    end

    local s = hrp.Position; local dist = (dest - s).Magnitude
    if dist >= 0.5 then
        local steps = math.max(3, math.ceil(dist)); local st = 1 / FARM_FLY_SPEED
        for i = 1, steps do
            hrp = myHRP(); if not hrp then break end
            hrp.CFrame = CFrame.new(s:Lerp(dest, i / steps)); task.wait(st)
        end
        hrp = myHRP(); if hrp then hrp.CFrame = CFrame.new(dest) end
    end

    -- FIX #5: restaura colisão após chegar
    chr = player.Character
    if chr then
        for _, p in ipairs(chr:GetDescendants()) do
            if p:IsA("BasePart") and collisionStates[p] ~= nil then
                pcall(function() p.CanCollide = collisionStates[p] end)
            end
        end
    end
end

local function collectCoin(c)
    if not c or not c.Parent then return end
    flyTo(c.Position)
    local hrp = myHRP()
    if hrp and c.Parent then
        hrp.CFrame = CFrame.new(c.Position + Vector3.new(0.3, 0, 0)); task.wait(0.05)
        hrp = myHRP(); if hrp and c.Parent then hrp.CFrame = CFrame.new(c.Position) end
    end
    if GetCoinEvent then pcall(function() GetCoinEvent:FireServer() end) end
    task.wait(farmPauseBetween)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- TEMA
-- ══════════════════════════════════════════════════════════════════════════════

local T = {
    panel = Color3.fromRGB(36, 26, 56),
    sub   = Color3.fromRGB(150, 130, 190),
    ok    = Color3.fromRGB(85, 205, 115),
    err   = Color3.fromRGB(208, 52, 72),
    warn  = Color3.fromRGB(195, 160, 38),
}

-- ══════════════════════════════════════════════════════════════════════════════
-- TABS
-- ══════════════════════════════════════════════════════════════════════════════

local tabMain   = ui:Tab("main")
local tabESP    = ui:Tab("esp")
local tabCombat = ui:Tab("combat")
local tabFarm   = ui:Tab("farm")
local tabCfg    = ui:Tab("config")

-- ══════════════════════════════════════════════════════════════════════════════
-- TAB: MAIN
-- ══════════════════════════════════════════════════════════════════════════════
do

local secInfo = tabMain:Section("round info")

secInfo:Button("checar meu papel", function()
    local role = getRole(); local alive = 0
    for _, p in ipairs(Players:GetPlayers()) do if isAlive(p) then alive = alive + 1 end end
    ui:Toast("rbxassetid://131165537896572",
        "["..ROLE_LABEL[role].."] "..player.DisplayName, "vivos: "..alive, ROLE_COLOR[role])
end)

secInfo:Button("scan todos os papeis", function()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local r = getRole(p); if r ~= "innocent" then table.insert(list, {p=p, r=r}) end
    end
    if #list == 0 then
        ui:Toast("rbxassetid://131165537896572","scan","nenhum killer/sheriff",ROLE_COLOR.unknown); return
    end
    for _, info in ipairs(list) do
        task.spawn(function()
            ui:Toast("rbxassetid://131165537896572",
                "["..ROLE_LABEL[info.r].."] "..info.p.DisplayName, info.p.Name, ROLE_COLOR[info.r])
        end)
        task.wait(0.4)
    end
end)

secInfo:Divider("role esp (highlight)")
local roleEspOn = false; local roleEspCache = {}

local function removeRoleEsp(p)
    local d = roleEspCache[p]; if not d then return end
    pcall(function() if d.hl  and d.hl.Parent  then d.hl:Destroy()  end end)
    pcall(function() if d.bb  and d.bb.Parent  then d.bb:Destroy()  end end)
    roleEspCache[p] = nil
end

local function buildRoleEsp(p)
    if roleEspCache[p] then return end
    local chr = p.Character; if not chr then return end
    local hrp = chr:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local role = getRole(p); local col = ROLE_COLOR[role] or ROLE_COLOR.unknown
    local hl = Instance.new("Highlight")
    hl.FillColor=col; hl.OutlineColor=Color3.new(1,1,1); hl.FillTransparency=0.42
    hl.OutlineTransparency=0; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee=chr; hl.Parent=chr
    local bb = Instance.new("BillboardGui")
    bb.Size=UDim2.new(0,130,0,30); bb.StudsOffset=Vector3.new(0,3.2,0)
    bb.AlwaysOnTop=true; bb.ResetOnSpawn=false; bb.Adornee=hrp; bb.Parent=hrp
    local nm = Instance.new("TextLabel")
    nm.BackgroundTransparency=1; nm.Size=UDim2.new(1,0,0,20)
    nm.Font=Enum.Font.GothamBold; nm.TextSize=13; nm.TextColor3=Color3.new(1,1,1)
    nm.TextStrokeTransparency=0.12; nm.TextXAlignment=Enum.TextXAlignment.Center
    nm.Text=p.DisplayName; nm.Parent=bb
    local rl = Instance.new("TextLabel")
    rl.BackgroundTransparency=1; rl.Size=UDim2.new(1,0,0,14); rl.Position=UDim2.new(0,0,0,18)
    rl.Font=Enum.Font.GothamSemibold; rl.TextSize=11; rl.TextColor3=col
    rl.TextStrokeTransparency=0.2; rl.TextXAlignment=Enum.TextXAlignment.Center
    rl.Text="["..ROLE_LABEL[role].."]"; rl.Parent=bb
    roleEspCache[p] = {hl=hl, bb=bb, nm=nm, rl=rl}
end

RunService.RenderStepped:Connect(function()
    if not roleEspOn then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        if not isAlive(p) then removeRoleEsp(p); continue end
        if not roleEspCache[p] then buildRoleEsp(p) end
        local d = roleEspCache[p]; if not d then continue end
        local role = getRole(p); local col = ROLE_COLOR[role] or ROLE_COLOR.unknown
        d.hl.FillColor=col; d.rl.TextColor3=col
        d.rl.Text="["..ROLE_LABEL[role].."]"; d.nm.Text=p.DisplayName
    end
end)
Players.PlayerRemoving:Connect(removeRoleEsp)
for _, p in ipairs(Players:GetPlayers()) do if p ~= player then p.CharacterAdded:Connect(function()
    removeRoleEsp(p); task.wait(1); if roleEspOn then buildRoleEsp(p) end
end) end end
Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function()
    task.wait(1); if roleEspOn then buildRoleEsp(p) end
end) end)

local t_rEsp = secInfo:Toggle("role esp (highlight)", false, function(v)
    roleEspOn = v
    if not v then for p in pairs(roleEspCache) do removeRoleEsp(p) end end
end)
ui:CfgRegister("mm2_role_esp", function() return roleEspOn end, function(v) t_rEsp.Set(v) end)

-- MOVEMENT
local secMove = tabMain:Section("movement")
local DEF_WS = 16; local speedOn = false; local speedVal = 26
local function applySpeed(chr)
    chr = chr or player.Character; if not chr then return end
    local h = chr:FindFirstChildOfClass("Humanoid"); if not h then return end
    h.WalkSpeed = speedOn and speedVal or DEF_WS
end
player.CharacterAdded:Connect(function(c) c:WaitForChild("Humanoid"); task.wait(0.2); applySpeed(c) end)
local t_spd = secMove:Toggle("fast walk", false, function(v) speedOn=v; applySpeed() end)
ui:CfgRegister("mm2_spd_on", function() return speedOn end, function(v) t_spd.Set(v) end)
local s_spd = secMove:Slider("speed (studs/s)", 8, 80, 26, function(v) speedVal=v; if speedOn then applySpeed() end end)
ui:CfgRegister("mm2_spd_val", function() return speedVal end, function(v) s_spd.Set(v) end)
local jumpOn = false; local jumpConn = nil
local t_jump = secMove:Toggle("infinite jump", false, function(v)
    jumpOn=v; if jumpConn then jumpConn:Disconnect(); jumpConn=nil end
    if v then jumpConn=UserInputService.JumpRequest:Connect(function()
        local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end) end
end)
ui:CfgRegister("mm2_jump", function() return jumpOn end, function(v) t_jump.Set(v) end)
local noclipOn = false
RunService.Stepped:Connect(function()
    if not noclipOn then return end
    local chr = player.Character; if not chr then return end
    for _, p in ipairs(chr:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end
end)
local t_nc = secMove:Toggle("noclip", false, function(v)
    noclipOn=v
    if not v then
        local chr = player.Character; if chr then
            for _, p in ipairs(chr:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end
        end
    end
end)
ui:CfgRegister("mm2_noclip", function() return noclipOn end, function(v) t_nc.Set(v) end)

end -- MAIN

-- ══════════════════════════════════════════════════════════════════════════════
-- TAB: ESP
-- FIX #1: corrigido espCache/removeESP → espData/hidePlayer (variáveis corretas)
-- ══════════════════════════════════════════════════════════════════════════════
do

local secESP = tabESP:Section("skeleton esp (wall)")
-- FIX #1: era `espCache` e `removeESP` (inexistentes) — corrigido para `espData` e `hidePlayer`
local t_esp = secESP:Toggle("skeleton esp (vê atrás da parede)", false, function(v)
    espOn = v
    if not v then
        for p in pairs(espData) do hidePlayer(p) end
    end
end)
ui:CfgRegister("mm2_esp", function() return espOn end, function(v) t_esp.Set(v) end)
local s_dist = secESP:Slider("distancia max (studs)", 50, 1000, 300, function(v) espMax = v end)
ui:CfgRegister("mm2_esp_dist", function() return espMax end, function(v) s_dist.Set(v) end)

-- ITEM ESP
local secItemEsp = tabESP:Section("item esp (gun)")
local itemEspOn = false; local itemBBs = {}
local function removeItemBB(obj)
    local bb = itemBBs[obj]; if bb and bb.Parent then pcall(function() bb:Destroy() end) end; itemBBs[obj]=nil
end
local function makeItemBB(obj, adornee)
    if itemBBs[obj] then return end; if not adornee or not adornee.Parent then return end
    local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(0,108,0,44)
    bb.StudsOffset=Vector3.new(0,4,0); bb.AlwaysOnTop=true; bb.ResetOnSpawn=false
    bb.Adornee=adornee; bb.Parent=adornee
    local nm = Instance.new("TextLabel"); nm.BackgroundTransparency=1; nm.Size=UDim2.new(1,0,0,22)
    nm.Font=Enum.Font.GothamBold; nm.TextSize=14; nm.TextColor3=ROLE_COLOR.sheriff
    nm.TextStrokeTransparency=0.12; nm.TextXAlignment=Enum.TextXAlignment.Center; nm.Text="[ GUN ]"; nm.Parent=bb
    local dl = Instance.new("TextLabel"); dl.BackgroundTransparency=1; dl.Size=UDim2.new(1,0,0,14); dl.Position=UDim2.new(0,0,0,24)
    dl.Font=Enum.Font.Gotham; dl.TextSize=10; dl.TextColor3=Color3.fromRGB(200,200,220)
    dl.TextXAlignment=Enum.TextXAlignment.Center; dl.Text=""; dl.Parent=bb
    itemBBs[obj] = bb
    local conn; conn=RunService.RenderStepped:Connect(function()
        if not itemEspOn or not bb.Parent then conn:Disconnect(); return end
        local hrp = myHRP(); if hrp and adornee and adornee.Parent then
            dl.Text = math.floor((hrp.Position-adornee.Position).Magnitude).."m"
        end
    end)
    obj.AncestryChanged:Connect(function()
        if not obj:IsDescendantOf(workspace) then removeItemBB(obj) end
    end)
end
local function scanItems()
    for _, o in ipairs(workspace:GetDescendants()) do
        if GUNDROP_NAMES[o.Name] and o:IsA("BasePart") then task.spawn(makeItemBB, o, o) end
    end
end
workspace.DescendantAdded:Connect(function(o)
    if not itemEspOn then return end; task.wait(0.1)
    if GUNDROP_NAMES[o.Name] and o:IsA("BasePart") then makeItemBB(o, o) end
end)
local t_item = secItemEsp:Toggle("gun dropped esp", false, function(v)
    itemEspOn=v; if v then scanItems() end
    for _, bb in pairs(itemBBs) do bb.Enabled=v end
end)
ui:CfgRegister("mm2_item_esp", function() return itemEspOn end, function(v) t_item.Set(v) end)
secItemEsp:Button("tp to gun", function()
    if not isAlive(player) then
        ui:Toast("rbxassetid://131165537896572","tp gun","voce esta morto",ROLE_COLOR.unknown); return end
    local hrp = myHRP(); if not hrp then return end
    local guns = findDroppedGuns(); local best, bestD = nil, math.huge
    for _, g in ipairs(guns) do
        local d = (hrp.Position - g.handle.Position).Magnitude; if d < bestD then best=g.handle; bestD=d end
    end
    if best then
        hrp.CFrame = CFrame.new(best.Position + Vector3.new(0,3,0))
        ui:Toast("rbxassetid://131165537896572","[Gun] tp","encontrada! "..math.floor(bestD).."m",ROLE_COLOR.sheriff)
    else
        ui:Toast("rbxassetid://131165537896572","tp gun","nenhuma gun dropada",ROLE_COLOR.unknown)
    end
end)

end -- ESP

-- ══════════════════════════════════════════════════════════════════════════════
-- TAB: COMBAT
-- ══════════════════════════════════════════════════════════════════════════════
do

local secSheriff = tabCombat:Section("sheriff")

-- DUMP — FIX #2/#3: variáveis declaradas no topo + hook implementado
secSheriff:Divider("dump (debug — use 1x pra confirmar assinatura)")
secSheriff:Button("DUMP gun (equipa e clica, depois atira)", function()
    local gunTool = getGunTool()
    if not gunTool then
        ui:Toast("rbxassetid://131165537896572","Dump","sem gun equipada",ROLE_COLOR.unknown); return
    end
    dumpActive   = true
    dumpCallback = function(desc)
        local lines = {
            "=== FIRESERVER CAPTURADO ===",
            "Gun: "..gunTool.Name,
            "Total args: "..#desc,
            "",
        }
        for _, l in ipairs(desc) do table.insert(lines, l) end
        table.insert(lines, "")
        table.insert(lines, "Silent aim substitui arg[2] (alvo CFrame)")

        local old = player.PlayerGui:FindFirstChild("MM2DumpGui"); if old then old:Destroy() end
        local sg = Instance.new("ScreenGui"); sg.Name="MM2DumpGui"; sg.ResetOnSpawn=false
        sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=player.PlayerGui
        local frame = Instance.new("Frame"); frame.Size=UDim2.new(0,400,0,240)
        frame.Position=UDim2.new(0.5,-200,0.5,-120); frame.BackgroundColor3=Color3.fromRGB(18,18,28)
        frame.BorderSizePixel=0; frame.Parent=sg; Instance.new("UICorner",frame).CornerRadius=UDim.new(0,8)
        local title = Instance.new("TextLabel"); title.Size=UDim2.new(1,-36,0,32); title.Position=UDim2.new(0,8,0,0)
        title.BackgroundTransparency=1; title.Text="DUMP — FireServer args"
        title.TextColor3=Color3.fromRGB(200,200,210); title.Font=Enum.Font.GothamBold; title.TextSize=12
        title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=frame
        local closeBtn = Instance.new("TextButton"); closeBtn.Size=UDim2.new(0,32,0,32); closeBtn.Position=UDim2.new(1,-34,0,0)
        closeBtn.BackgroundTransparency=1; closeBtn.Text="✕"; closeBtn.TextColor3=Color3.fromRGB(180,80,80)
        closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=16; closeBtn.Parent=frame
        closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)
        local scroll = Instance.new("ScrollingFrame"); scroll.Size=UDim2.new(1,-16,1,-72); scroll.Position=UDim2.new(0,8,0,36)
        scroll.BackgroundColor3=Color3.fromRGB(12,12,18); scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4
        scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=frame
        Instance.new("UICorner",scroll).CornerRadius=UDim.new(0,6)
        local txt = Instance.new("TextLabel"); txt.Size=UDim2.new(1,-8,0,0); txt.AutomaticSize=Enum.AutomaticSize.Y
        txt.Position=UDim2.new(0,4,0,4); txt.BackgroundTransparency=1; txt.Text=table.concat(lines,"\n")
        txt.TextColor3=Color3.fromRGB(140,220,140); txt.Font=Enum.Font.Code; txt.TextSize=11
        txt.TextXAlignment=Enum.TextXAlignment.Left; txt.TextYAlignment=Enum.TextYAlignment.Top
        txt.TextWrapped=true; txt.Parent=scroll
        local copyBtn = Instance.new("TextButton"); copyBtn.Size=UDim2.new(1,-16,0,28); copyBtn.Position=UDim2.new(0,8,1,-36)
        copyBtn.BackgroundColor3=Color3.fromRGB(55,180,100); copyBtn.BorderSizePixel=0
        copyBtn.Text="📋 COPIAR"; copyBtn.TextColor3=Color3.new(1,1,1); copyBtn.Font=Enum.Font.GothamBold; copyBtn.TextSize=12; copyBtn.Parent=frame
        Instance.new("UICorner",copyBtn).CornerRadius=UDim.new(0,6)
        copyBtn.MouseButton1Click:Connect(function()
            pcall(function() setclipboard(table.concat(lines,"\n")) end)
            copyBtn.Text="✔ COPIADO!"; copyBtn.BackgroundColor3=Color3.fromRGB(40,130,70)
            task.delay(2, function() pcall(function() sg:Destroy() end) end)
        end)
    end
    task.delay(20, function() if dumpActive then dumpActive=false; dumpCallback=nil end end)
    ui:Toast("rbxassetid://131165537896572","[Dump]","atire 1x — vou capturar os args",ROLE_COLOR.sheriff)
end)

-- SILENT AIM
secSheriff:Divider("silent aim")
local t_sa = secSheriff:Toggle("silent aim (trava mira no murder)", false, function(v)
    silentAimOn = v
    if v then
        ui:Toast("rbxassetid://131165537896572","[Silent Aim]","ativo — clique pra atirar",ROLE_COLOR.sheriff)
    else
        ui:Toast("rbxassetid://131165537896572","[Silent Aim]","desativado",ROLE_COLOR.unknown)
    end
end)
ui:CfgRegister("mm2_silentaim", function() return silentAimOn end, function(v) t_sa.Set(v) end)
local s_pred = secSheriff:Slider("prediction (x0.01s)", 0, 40, 17, function(v) SA_PRED = v/100 end)
ui:CfgRegister("mm2_sa_pred", function() return SA_PRED*100 end, function(v) s_pred.Set(v) end)

-- HITBOX
secSheriff:Divider("hitbox expander")
local t_hb = secSheriff:Toggle("hitbox expander", false, function(v)
    hitboxOn = v
    if v then
        for _, p in ipairs(Players:GetPlayers()) do applyHitboxToChar(p) end
        ui:Toast("rbxassetid://131165537896572","[Hitbox]","ativo — "..hitboxSize.."x",ROLE_COLOR.sheriff)
    else
        restoreAllHitboxes()
        ui:Toast("rbxassetid://131165537896572","[Hitbox]","desativado",ROLE_COLOR.unknown)
    end
end)
ui:CfgRegister("mm2_hitbox", function() return hitboxOn end, function(v) t_hb.Set(v) end)
local s_hbsize = secSheriff:Slider("tamanho hitbox (studs)", 4, 40, 12, function(v) hitboxSize=v end)
ui:CfgRegister("mm2_hitboxsize", function() return hitboxSize end, function(v) s_hbsize.Set(v) end)
local t_hbvis = secSheriff:Toggle("mostrar hitbox (debug)", false, function(v) hitboxVisible=v; applyHBVis(v) end)
ui:CfgRegister("mm2_hitboxvis", function() return hitboxVisible end, function(v) t_hbvis.Set(v) end)

-- SHOOT BUTTON
secSheriff:Divider("shoot button (usa silent aim)")
local shootBtnGui = nil; local shootBtnOn = false
local function destroyShootBtn()
    if shootBtnGui and shootBtnGui.Parent then pcall(function() shootBtnGui:Destroy() end) end; shootBtnGui=nil
end
local function buildShootBtn()
    destroyShootBtn()
    local sg = Instance.new("ScreenGui"); sg.Name="MM2ShootBtn"; sg.ResetOnSpawn=false
    sg.IgnoreGuiInset=true; sg.DisplayOrder=99; sg.Parent=player.PlayerGui
    local card = Instance.new("Frame"); card.Size=UDim2.new(0,110,0,56); card.Position=UDim2.new(1,-120,1,-220)
    card.BackgroundColor3=T.panel; card.BackgroundTransparency=0.08; card.BorderSizePixel=0; card.Parent=sg
    Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
    local stroke = Instance.new("UIStroke"); stroke.Color=ROLE_COLOR.sheriff; stroke.Thickness=1.5
    stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stroke.Parent=card
    local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,0,14); lbl.BackgroundTransparency=1
    lbl.Font=Enum.Font.Gotham; lbl.TextSize=9; lbl.TextColor3=T.sub
    lbl.TextXAlignment=Enum.TextXAlignment.Center; lbl.Text="SILENT AIM"; lbl.Position=UDim2.new(0,0,0,4); lbl.Parent=card
    local btn = Instance.new("TextButton"); btn.Size=UDim2.new(1,-10,0,30); btn.Position=UDim2.new(0,5,0,20)
    btn.BackgroundColor3=ROLE_COLOR.sheriff; btn.BorderSizePixel=0; btn.Text="ATIRAR"
    btn.Font=Enum.Font.GothamBold; btn.TextSize=14; btn.TextColor3=Color3.new(1,1,1)
    btn.AutoButtonColor=true; btn.Parent=card
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6); shootBtnGui=sg
    local busy = false
    local function set(text, col) if btn.Parent then btn.Text=text; btn.BackgroundColor3=col end end
    btn.Activated:Connect(function()
        if busy then return end
        if not getGunTool() then
            set("SEM GUN", T.err); task.delay(1.2, function() set("ATIRAR", ROLE_COLOR.sheriff) end); return
        end
        local target = getSilentTarget()
        if not target then
            set("SEM ALVO", T.warn); task.delay(1.2, function() set("ATIRAR", ROLE_COLOR.sheriff) end); return
        end
        busy = true; set("...", Color3.fromRGB(80,80,80))
        local hitPos = getPredictedPos(target)
        if hitPos then
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, hitPos)
        end
        local ok = fireWithSilentAim()
        task.wait(0.15); set(ok and "FIRED!" or "MISS", ok and T.ok or T.err)
        task.wait(0.8); set("ATIRAR", ROLE_COLOR.sheriff); busy = false
    end)
end
local t_btn = secSheriff:Toggle("shoot button (mobile safe)", false, function(v)
    shootBtnOn=v; if v then buildShootBtn()
        ui:Toast("rbxassetid://131165537896572","[Btn]","canto inf-direito",ROLE_COLOR.sheriff)
    else destroyShootBtn() end
end)
ui:CfgRegister("mm2_shootbtn", function() return shootBtnOn end, function(v) t_btn.Set(v) end)
player.CharacterAdded:Connect(function() if shootBtnOn then task.wait(1); buildShootBtn() end end)

-- GUN AURA
-- FIX #6: guard adicionado no início do loop para evitar disparo duplo
secSheriff:Divider("gun aura")
local gunAuraOn=false; local lastGA=0; local gaCD=0.8; local gaDist=18
local function gunAuraLoop()
    while gunAuraOn do
        task.wait(0.1)
        if not gunAuraOn then break end  -- FIX #6: check após o yield
        if getRole()~="sheriff" and getRole()~="hero" then continue end
        if tick()-lastGA<gaCD then continue end
        local m = findByRole("murderer"); if not m then continue end
        local mChr = m.Character; if not mChr then continue end
        local mHRP = mChr:FindFirstChild("HumanoidRootPart"); if not mHRP then continue end
        local hrp = myHRP(); if not hrp then continue end
        if (hrp.Position-mHRP.Position).Magnitude > gaDist then
            hrp.CFrame = mHRP.CFrame * CFrame.new(0,0,-gaDist*0.6); task.wait(0.08)
            if not gunAuraOn then break end  -- FIX #6
            hrp = myHRP(); if not hrp then continue end
        end
        hrp.CFrame = CFrame.lookAt(hrp.Position, mHRP.Position); task.wait(0.04)
        if not gunAuraOn then break end  -- FIX #6
        lastGA = tick(); fireWithSilentAim()
    end
end
local t_ga = secSheriff:Toggle("gun aura (tp + silent aim + shoot)", false, function(v)
    gunAuraOn=v
    if v then task.spawn(gunAuraLoop)
        ui:Toast("rbxassetid://131165537896572","[Gun Aura]","ativo",ROLE_COLOR.sheriff)
    else ui:Toast("rbxassetid://131165537896572","[Gun Aura]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_gunaura", function() return gunAuraOn end, function(v) t_ga.Set(v) end)
local s_gacd = secSheriff:Slider("gun aura cooldown (x0.1s)", 2, 30, 8, function(v) gaCD=v/10 end)
ui:CfgRegister("mm2_gacd", function() return gaCD*10 end, function(v) s_gacd.Set(v) end)

-- AUTO SHOOT
-- FIX #6: guard adicionado para evitar disparo duplo após desativar
secSheriff:Divider("auto shoot")
local autoShootOn=false; local lastShot=0; local shotCD=0.6
local function autoShootLoop()
    while autoShootOn do
        task.wait(0.15)
        if not autoShootOn then break end  -- FIX #6
        if getRole()~="sheriff" and getRole()~="hero" then continue end
        if tick()-lastShot<shotCD then continue end
        local m = findByRole("murderer"); if not m then continue end
        local mHrp = m.Character and m.Character:FindFirstChild("HumanoidRootPart")
        local hrp = myHRP()  -- FIX #8: chamado uma vez e reutilizado
        if not mHrp or not hrp then continue end
        if (hrp.Position-mHrp.Position).Magnitude > 300 then continue end
        lastShot=tick(); fireWithSilentAim()
    end
end
local t_as = secSheriff:Toggle("auto shoot murderer", false, function(v)
    autoShootOn=v
    if v then task.spawn(autoShootLoop)
        ui:Toast("rbxassetid://131165537896572","[Auto Shoot]","ativo",ROLE_COLOR.sheriff)
    else ui:Toast("rbxassetid://131165537896572","[Auto Shoot]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_autoshoot", function() return autoShootOn end, function(v) t_as.Set(v) end)
local s_scd = secSheriff:Slider("cooldown (x0.1s)", 1, 20, 6, function(v) shotCD=v/10 end)
ui:CfgRegister("mm2_shot_cd", function() return shotCD*10 end, function(v) s_scd.Set(v) end)

secSheriff:Divider("manual")
secSheriff:Button("atirar no murderer (1x)", function()
    if getRole()~="sheriff" and getRole()~="hero" then
        ui:Toast("rbxassetid://131165537896572","[Shoot]","voce nao e xerife",ROLE_COLOR.unknown); return end
    local m = findByRole("murderer")
    if not m then ui:Toast("rbxassetid://131165537896572","[Shoot]","murderer nao detectado",ROLE_COLOR.unknown); return end
    local ok = fireWithSilentAim()
    ui:Toast("rbxassetid://131165537896572","[Shoot]",(ok and "disparado" or "falhou").." -> "..m.DisplayName,ROLE_COLOR.sheriff)
end)
secSheriff:Button("tp para murderer", function()
    local m = findByRole("murderer")
    if not m then ui:Toast("rbxassetid://131165537896572","tp","murderer nao detectado",ROLE_COLOR.unknown); return end
    local mh = m.Character and m.Character:FindFirstChild("HumanoidRootPart"); local hrp=myHRP()
    if mh and hrp then hrp.CFrame=mh.CFrame*CFrame.new(0,0,-4)
        ui:Toast("rbxassetid://131165537896572","[TP]","-> "..m.DisplayName,ROLE_COLOR.murderer) end
end)

-- MURDERER
local secMurd = tabCombat:Section("murderer")
secMurd:Divider("knife aura (auto swing)")
local knifeAura=false; local knifeRange=12; local knifeCd=0.35; local _kConn=nil

-- FIX #4: equipar faca de forma correta, aguardando character e usando referência fresca
local function equipKnifeForAura()
    local chr = player.Character; if not chr then return end
    local hum = chr:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local bp = player:FindFirstChild("Backpack"); if not bp then return end
    for name in pairs(KNIFE_NAMES) do
        local t = bp:FindFirstChild(name)
        if t then
            pcall(function() hum:EquipTool(t) end)
            task.wait(0.15)
            return
        end
    end
end

local function knifeAuraLoop()
    if _kConn then _kConn:Disconnect(); _kConn=nil end
    equipKnifeForAura()  -- FIX #4: equipa corretamente antes do loop
    local accum=0; local cRole="unknown"; local rTimer=0; local pHRPs={}
    _kConn = RunService.Heartbeat:Connect(function(dt)
        if not knifeAura then _kConn:Disconnect(); _kConn=nil; return end
        accum=accum+dt; rTimer=rTimer+dt
        if rTimer>=0.5 then rTimer=0; cRole=getRole(); pHRPs={}
            for _,p in ipairs(Players:GetPlayers()) do if p~=player and isAlive(p) then
                local ph = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if ph then pHRPs[p]=ph end
            end end
        end
        if accum<knifeCd then return end; accum=0
        if cRole~="murderer" then return end
        local hrp = myHRP(); if not hrp then return end
        local knife = getKnifeTool()
        if not knife then
            -- FIX #4: tenta equipar novamente se a faca sumiu
            task.spawn(equipKnifeForAura)
            return
        end
        local hp = hrp.Position; local best,bestD=nil,knifeRange
        for p,ph in pairs(pHRPs) do
            if not ph.Parent then pHRPs[p]=nil; continue end
            local d = (hp-ph.Position).Magnitude; if d<bestD then best=ph; bestD=d end
        end
        if best then
            local lCF = CFrame.lookAt(hp, best.Position)
            if math.abs(hrp.CFrame.LookVector:Dot(lCF.LookVector)-1)>0.01 then hrp.CFrame=lCF end
            pcall(function() knife:Activate() end)
        end
    end)
end
local t_ka = secMurd:Toggle("knife aura", false, function(v)
    knifeAura=v
    if v then knifeAuraLoop()
        ui:Toast("rbxassetid://131165537896572","[Knife Aura]","ativo",ROLE_COLOR.murderer)
    else
        if _kConn then _kConn:Disconnect(); _kConn=nil end
        ui:Toast("rbxassetid://131165537896572","[Knife Aura]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_knifeaura", function() return knifeAura end, function(v) t_ka.Set(v) end)
local s_kr = secMurd:Slider("range aura (studs)", 4, 60, 12, function(v) knifeRange=v end)
ui:CfgRegister("mm2_kniferange", function() return knifeRange end, function(v) s_kr.Set(v) end)
secMurd:Button("matar sheriff (1x)", function()
    if getRole()~="murderer" then
        ui:Toast("rbxassetid://131165537896572","[Knife]","voce nao e murderer",ROLE_COLOR.unknown); return end
    local s = findByRole("sheriff"); if not s then
        ui:Toast("rbxassetid://131165537896572","[Knife]","sheriff nao detectado",ROLE_COLOR.unknown); return end
    knifeAt(s.Character)
    ui:Toast("rbxassetid://131165537896572","[Knife]","-> "..s.DisplayName,ROLE_COLOR.murderer)
end)
secMurd:Button("matar mais proximo", function()
    if getRole()~="murderer" then
        ui:Toast("rbxassetid://131165537896572","[Knife]","voce nao e murderer",ROLE_COLOR.unknown); return end
    local hrp = myHRP(); if not hrp then return end; local best,bestD=nil,math.huge
    for _,p in ipairs(Players:GetPlayers()) do if p~=player then
        local ph = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if ph and isAlive(p) then local d=(hrp.Position-ph.Position).Magnitude; if d<bestD then best=p; bestD=d end end
    end end
    if not best then ui:Toast("rbxassetid://131165537896572","[Knife]","nenhum alvo",ROLE_COLOR.unknown); return end
    knifeAt(best.Character)
    ui:Toast("rbxassetid://131165537896572","[Knife]","-> "..best.DisplayName,ROLE_COLOR.murderer)
end)
secMurd:Button("tp para sheriff", function()
    local s = findByRole("sheriff"); if not s then
        ui:Toast("rbxassetid://131165537896572","tp","sheriff nao detectado",ROLE_COLOR.unknown); return end
    local sh = s.Character and s.Character:FindFirstChild("HumanoidRootPart"); local hrp=myHRP()
    if sh and hrp then hrp.CFrame=sh.CFrame*CFrame.new(0,0,-4)
        ui:Toast("rbxassetid://131165537896572","[TP]","-> "..s.DisplayName,ROLE_COLOR.sheriff) end
end)

local secCI = tabCombat:Section("info")
secCI:Button("quem e o murderer / sheriff", function()
    local m=findByRole("murderer"); local s=findByRole("sheriff"); local alive=0
    for _,p in ipairs(Players:GetPlayers()) do if isAlive(p) then alive=alive+1 end end
    ui:Toast("rbxassetid://131165537896572",
        "M: "..(m and m.DisplayName or "?").."  |  S: "..(s and s.DisplayName or "?"),
        "vivos: "..alive, ROLE_COLOR.unknown)
end)

end -- COMBAT

-- ══════════════════════════════════════════════════════════════════════════════
-- TAB: FARM
-- ══════════════════════════════════════════════════════════════════════════════
do

local secFarm = tabFarm:Section("coin farm")
local farmOn=false; local farmCount=0
local function collectCoinsLoop()
    farmCount=0; while farmOn do
        if not isRoundActive() then task.wait(3); continue end
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        -- FIX #8: myHRP() chamado uma vez e reutilizado
        local hrp = myHRP()
        if not hrp or not hum or hum.Health<=0 then task.wait(2); continue end
        local coins = findAllCoinServers(); if #coins==0 then task.wait(3); continue end
        local myPos = hrp.Position  -- FIX #8: usa hrp já obtido
        table.sort(coins, function(a,b)
            if not(a and a.Parent) then return false end; if not(b and b.Parent) then return true end
            return (a.Position-myPos).Magnitude < (b.Position-myPos).Magnitude
        end)
        for _, c in ipairs(coins) do
            if not farmOn then break end; if not c or not c.Parent then continue end
            if not myHRP() then break end; collectCoin(c); farmCount=farmCount+1
        end; task.wait(2)
    end
end
local t_farm = secFarm:Toggle("auto farm coins", false, function(v)
    farmOn=v
    if v then task.spawn(collectCoinsLoop)
        ui:Toast("rbxassetid://131165537896572","[Farm] iniciado","vel: "..FARM_FLY_SPEED.."s/s",Color3.fromRGB(255,210,50))
    else ui:Toast("rbxassetid://131165537896572","[Farm] parado","coletadas: "..farmCount,Color3.fromRGB(255,210,50)) end
end)
ui:CfgRegister("mm2_farm", function() return farmOn end, function(v) t_farm.Set(v) end)
local s_fspd = secFarm:Slider("velocidade (studs/s)", 4, 40, 16, function(v) FARM_FLY_SPEED=v end)
ui:CfgRegister("mm2_farm_speed", function() return FARM_FLY_SPEED end, function(v) s_fspd.Set(v) end)
local s_fpause = secFarm:Slider("pausa entre coins (x0.1s)", 2, 30, 8, function(v) farmPauseBetween=v/10 end)
ui:CfgRegister("mm2_farm_pause", function() return farmPauseBetween*10 end, function(v) s_fpause.Set(v) end)
secFarm:Button("status do farm", function()
    local coins = findAllCoinServers()
    ui:Toast("rbxassetid://131165537896572",
        farmOn and "[Farm] rodando" or "[Farm] parado",
        "mapa: "..#coins.."  coletadas: "..farmCount, Color3.fromRGB(255,210,50))
end)
secFarm:Button("collect coins (1x)", function()
    if not myHRP() then return end
    local coins = findAllCoinServers(); if #coins==0 then
        ui:Toast("rbxassetid://131165537896572","coins","nenhuma coin encontrada",ROLE_COLOR.unknown); return end
    ui:Toast("rbxassetid://131165537896572","[Coins]","coletando "..#coins.."...",Color3.fromRGB(255,210,50))
    task.spawn(function()
        local hrp = myHRP()  -- FIX #8
        local myPos = hrp and hrp.Position or Vector3.zero
        table.sort(coins, function(a,b)
            if not(a and a.Parent) then return false end; if not(b and b.Parent) then return true end
            return (a.Position-myPos).Magnitude < (b.Position-myPos).Magnitude
        end); local count=0
        for _, c in ipairs(coins) do if c and c.Parent then collectCoin(c); count=count+1 end end
        ui:Toast("rbxassetid://131165537896572","[Coins] feito!","coletadas: "..count,Color3.fromRGB(255,210,50))
    end)
end)

local secGrab = tabFarm:Section("gun grab (inocente)")
local grabOn=false
local function grabLoop()
    while grabOn do task.wait(0.6)
        if not grabOn then break end
        if not isRoundActive() then continue end
        if getRole()=="murderer" then continue end
        local hrp = myHRP(); if not hrp then continue end
        if getGunTool() then continue end
        local best,bestD=nil,math.huge
        for _, g in ipairs(findDroppedGuns()) do
            local d=(hrp.Position-g.handle.Position).Magnitude; if d<bestD then best=g.handle; bestD=d end
        end
        if best then
            hrp=myHRP(); if not hrp then continue end
            local s=hrp.CFrame; hrp.CFrame=CFrame.new(best.Position+Vector3.new(0,2.5,0)); task.wait(0.35)
            hrp=myHRP(); if not hrp then continue end; hrp.CFrame=s; task.wait(0.3)
        end
    end
end
local t_grab = secGrab:Toggle("auto pegar gun (vai e volta)", false, function(v)
    grabOn=v
    if v then task.spawn(grabLoop)
        ui:Toast("rbxassetid://131165537896572","[Gun Grab]","buscando GunDrop...",ROLE_COLOR.sheriff)
    else ui:Toast("rbxassetid://131165537896572","[Gun Grab]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_grab", function() return grabOn end, function(v) t_grab.Set(v) end)

local secSurv = tabFarm:Section("survival")
local survOn=false; local fleeDist=20
local function surviveLoop()
    while survOn do task.wait(0.2)
        if not survOn then break end
        if getRole()=="murderer" then continue end
        local m = findByRole("murderer"); if not m then continue end
        local mh = m.Character and m.Character:FindFirstChild("HumanoidRootPart"); local hrp=myHRP()
        if not mh or not hrp then continue end
        if (hrp.Position-mh.Position).Magnitude < fleeDist then
            local dir=(hrp.Position-mh.Position).Unit; local np=hrp.Position+dir*32
            if isValidPos(np) then hrp.CFrame=CFrame.new(np) end
        end
    end
end
local t_surv = secSurv:Toggle("auto fugir do murderer", false, function(v)
    survOn=v
    if v then task.spawn(surviveLoop)
        ui:Toast("rbxassetid://131165537896572","[Survive]","ativo",ROLE_COLOR.innocent)
    else ui:Toast("rbxassetid://131165537896572","[Survive]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_survive", function() return survOn end, function(v) t_surv.Set(v) end)
local s_fl = secSurv:Slider("range de fuga (studs)", 5, 60, 20, function(v) fleeDist=v end)
ui:CfgRegister("mm2_flee", function() return fleeDist end, function(v) s_fl.Set(v) end)

local secAfk = tabFarm:Section("anti-afk")
local afkOn=false; local afkConn=nil
local t_afk = secAfk:Toggle("anti-afk", false, function(v)
    afkOn=v; if afkConn then afkConn:Disconnect(); afkConn=nil end
    if v then
        afkConn=RunService.Heartbeat:Connect(function()
            pcall(function()
                VirtualUser:Button2Down(Vector2.zero,cam.CFrame)
                VirtualUser:Button2Up(Vector2.zero,cam.CFrame)
            end)
        end)
        ui:Toast("rbxassetid://131165537896572","[Anti-AFK]","ativo",Color3.fromRGB(200,200,255))
    else ui:Toast("rbxassetid://131165537896572","[Anti-AFK]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_afk", function() return afkOn end, function(v) t_afk.Set(v) end)

end -- FARM

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════════════════════════════
ui:BuildConfigTab(tabCfg, "ref_mm2v20")


task.delay(0.9, function()
    local role = getRole()
    ui:Toast("rbxassetid://131165537896572",
        "mm2 v20  ["..ROLE_LABEL[role].."]",
        "bem-vindo, "..player.DisplayName, ROLE_COLOR[role])
end)
