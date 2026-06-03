-- ref_universal | Murder Mystery tester
-- Features: Coin Collect, Role ESP, Gun Drop Collect

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- ─── Compat layer ──────────────────────────────────────────────────────────────

local function _wait(n)
    n = n or 0
    if typeof(task) == "table" and type(task.wait) == "function" then
        return task.wait(n)
    end
    return wait(n)
end

local function _spawn(fn)
    if typeof(task) == "table" and type(task.spawn) == "function" then
        task.spawn(fn)
    else
        spawn(fn)
    end
end

local function _defer(fn)
    if typeof(task) == "table" and type(task.defer) == "function" then
        task.defer(fn)
    else
        spawn(fn)
    end
end

-- ─── Estado global ─────────────────────────────────────────────────────────────

local State = {
    coinCollect    = false,
    coinSpeed      = 50,
    esp            = false,
    gunDrop        = false,
    roles          = {},
    espObjects     = {},
    collecting     = false,
    _gunDropConn   = nil,
    _gunDropWatch  = false,
    _espAdded      = nil,
    _espRemoving   = nil,
}

-- ─── Utilitários ───────────────────────────────────────────────────────────────

local function getChar()
    return LocalPlayer.Character
end

local function getRoot()
    local c = getChar()
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
end

local function getRemote(path)
    local cur = ReplicatedStorage
    for _, name in ipairs(path) do
        local child = cur:FindFirstChild(name)
        if not child then return nil end
        cur = child
    end
    return cur
end

local function destroyChild(parent, name)
    if not parent then return end
    local c = parent:FindFirstChild(name)
    if c then pcall(function() c:Destroy() end) end
end

-- ─── RefLib inline ─────────────────────────────────────────────────────────────

local RefLib = {}

function RefLib.Window(title)
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("RefUniversal")
    if old then old:Destroy() end

    -- ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name            = "RefUniversal"
    gui.ResetOnSpawn    = false
    gui.IgnoreGuiInset  = true
    gui.DisplayOrder    = 999997
    gui.Parent          = playerGui

    -- Frame principal
    local frame = Instance.new("Frame")
    frame.Name                  = "Main"
    frame.Size                  = UDim2.new(0, 224, 0, 570)
    frame.Position              = UDim2.new(0, 14, 0.5, -285)
    frame.BackgroundColor3      = Color3.fromRGB(14, 15, 18)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel       = 0
    frame.Active                = true
    frame.Parent                = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color     = Color3.fromRGB(55, 60, 72)
    stroke.Thickness = 1
    stroke.Parent    = frame

    -- Barra de título
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(1, 0, 0, 36)
    bar.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    bar.BorderSizePixel  = 0
    bar.ZIndex           = 2
    bar.Parent           = frame

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 10)
    barCorner.Parent = bar

    -- patch pra cobrir os cantos inferiores arredondados da bar
    local barPatch = Instance.new("Frame")
    barPatch.Size             = UDim2.new(1, 0, 0.5, 0)
    barPatch.Position         = UDim2.new(0, 0, 0.5, 0)
    barPatch.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    barPatch.BorderSizePixel  = 0
    barPatch.ZIndex           = 2
    barPatch.Parent           = bar

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size               = UDim2.new(1, -12, 1, 0)
    titleLbl.Position           = UDim2.new(0, 12, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text               = title
    titleLbl.TextColor3         = Color3.fromRGB(200, 212, 232)
    titleLbl.TextSize           = 13
    titleLbl.Font               = Enum.Font.GothamBold
    titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
    titleLbl.ZIndex             = 3
    titleLbl.Parent             = bar

    -- drag
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

    -- ScrollingFrame de conteúdo
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size                 = UDim2.new(1, 0, 1, -40)
    scroll.Position             = UDim2.new(0, 0, 0, 40)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel      = 0
    scroll.ScrollBarThickness   = 2
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 90, 110)
    scroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
    scroll.Parent               = frame

    local list = Instance.new("UIListLayout")
    list.Padding              = UDim.new(0, 5)
    list.HorizontalAlignment  = Enum.HorizontalAlignment.Center
    list.Parent               = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingTop    = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent        = scroll

    -- ── métodos do W ───────────────────────────────────────────────────────────

    local W = { gui = gui, frame = frame, scroll = scroll }

    function W:Section(label)
        local s = Instance.new("TextLabel")
        s.Size                  = UDim2.new(1, -16, 0, 20)
        s.BackgroundTransparency = 1
        s.Text                  = label
        s.TextColor3            = Color3.fromRGB(100, 115, 140)
        s.TextSize              = 11
        s.Font                  = Enum.Font.GothamBold
        s.TextXAlignment        = Enum.TextXAlignment.Left
        s.Parent                = scroll
    end

    function W:Toggle(label, default, callback)
        local state = default == true

        local holder = Instance.new("Frame")
        holder.Size             = UDim2.new(1, -16, 0, 36)
        holder.BackgroundColor3 = Color3.fromRGB(22, 25, 31)
        holder.BorderSizePixel  = 0
        holder.Parent           = scroll

        local hc = Instance.new("UICorner")
        hc.CornerRadius = UDim.new(0, 7)
        hc.Parent = holder

        local lbl = Instance.new("TextLabel")
        lbl.Size                = UDim2.new(1, -54, 1, 0)
        lbl.Position            = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text                = label
        lbl.TextColor3          = Color3.fromRGB(210, 215, 225)
        lbl.TextSize            = 12
        lbl.Font                = Enum.Font.Gotham
        lbl.TextXAlignment      = Enum.TextXAlignment.Left
        lbl.Parent              = holder

        local track = Instance.new("Frame")
        track.Size             = UDim2.new(0, 36, 0, 18)
        track.Position         = UDim2.new(1, -46, 0.5, -9)
        track.BackgroundColor3 = state and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(50, 54, 64)
        track.BorderSizePixel  = 0
        track.Parent           = holder

        local tc = Instance.new("UICorner")
        tc.CornerRadius = UDim.new(1, 0)
        tc.Parent = track

        local knob = Instance.new("Frame")
        knob.Size             = UDim2.new(0, 14, 0, 14)
        knob.Position         = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel  = 0
        knob.Parent           = track

        local kc = Instance.new("UICorner")
        kc.CornerRadius = UDim.new(1, 0)
        kc.Parent = knob

        local btn = Instance.new("TextButton")
        btn.Size               = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text               = ""
        btn.Parent             = holder

        local onColor  = Color3.fromRGB(80, 200, 120)
        local offColor = Color3.fromRGB(50, 54, 64)
        local onPos    = UDim2.new(1, -16, 0.5, -7)
        local offPos   = UDim2.new(0, 2, 0.5, -7)

        btn.MouseButton1Click:Connect(function()
            state = not state
            pcall(function()
                TweenService:Create(track, TweenInfo.new(0.15), {
                    BackgroundColor3 = state and onColor or offColor
                }):Play()
                TweenService:Create(knob, TweenInfo.new(0.15), {
                    Position = state and onPos or offPos
                }):Play()
            end)
            if type(callback) == "function" then
                pcall(callback, state)
            end
        end)

        local T = {}
        function T:Set(v)
            state = v == true
            pcall(function()
                TweenService:Create(track, TweenInfo.new(0.15), {
                    BackgroundColor3 = state and onColor or offColor
                }):Play()
                TweenService:Create(knob, TweenInfo.new(0.15), {
                    Position = state and onPos or offPos
                }):Play()
            end)
        end
        function T:Get() return state end
        return T
    end

    function W:Slider(label, min, max, default, callback)
        local val = math.clamp(default or min, min, max)

        local holder = Instance.new("Frame")
        holder.Size             = UDim2.new(1, -16, 0, 54)
        holder.BackgroundColor3 = Color3.fromRGB(22, 25, 31)
        holder.BorderSizePixel  = 0
        holder.Parent           = scroll

        local hc = Instance.new("UICorner")
        hc.CornerRadius = UDim.new(0, 7)
        hc.Parent = holder

        local lbl = Instance.new("TextLabel")
        lbl.Size                = UDim2.new(1, -10, 0, 24)
        lbl.Position            = UDim2.new(0, 10, 0, 3)
        lbl.BackgroundTransparency = 1
        lbl.Text                = label .. ": " .. tostring(val)
        lbl.TextColor3          = Color3.fromRGB(210, 215, 225)
        lbl.TextSize            = 12
        lbl.Font                = Enum.Font.Gotham
        lbl.TextXAlignment      = Enum.TextXAlignment.Left
        lbl.Parent              = holder

        local rail = Instance.new("Frame")
        rail.Size             = UDim2.new(1, -20, 0, 6)
        rail.Position         = UDim2.new(0, 10, 0, 38)
        rail.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
        rail.BorderSizePixel  = 0
        rail.Parent           = holder

        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(1, 0)
        rc.Parent = rail

        local frac0 = (val - min) / (max - min)

        local fill = Instance.new("Frame")
        fill.Size             = UDim2.new(frac0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
        fill.BorderSizePixel  = 0
        fill.Parent           = rail

        local fc = Instance.new("UICorner")
        fc.CornerRadius = UDim.new(1, 0)
        fc.Parent = fill

        local thumb = Instance.new("Frame")
        thumb.Size             = UDim2.new(0, 14, 0, 14)
        thumb.Position         = UDim2.new(frac0, -7, 0.5, -7)
        thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        thumb.BorderSizePixel  = 0
        thumb.ZIndex           = 3
        thumb.Parent           = rail

        local thc = Instance.new("UICorner")
        thc.CornerRadius = UDim.new(1, 0)
        thc.Parent = thumb

        local dragging = false

        local function updateSlider(inputPos)
            local rp   = rail.AbsolutePosition
            local rs   = rail.AbsoluteSize
            if rs.X == 0 then return end
            local rel  = math.clamp((inputPos.X - rp.X) / rs.X, 0, 1)
            local newV = math.floor(min + rel * (max - min) + 0.5)
            if newV ~= val then
                val = newV
                local f = (val - min) / (max - min)
                fill.Size     = UDim2.new(f, 0, 1, 0)
                thumb.Position = UDim2.new(f, -7, 0.5, -7)
                lbl.Text      = label .. ": " .. tostring(val)
                if type(callback) == "function" then pcall(callback, val) end
            end
        end

        rail.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                updateSlider(input.Position)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                          or input.UserInputType == Enum.UserInputType.Touch) then
                updateSlider(input.Position)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        local S = {}
        function S:Get() return val end
        return S
    end

    function W:Label(text)
        local lbl = Instance.new("TextLabel")
        lbl.Size                = UDim2.new(1, -16, 0, 28)
        lbl.BackgroundTransparency = 1
        lbl.Text                = text
        lbl.TextColor3          = Color3.fromRGB(130, 140, 160)
        lbl.TextSize            = 11
        lbl.Font                = Enum.Font.Gotham
        lbl.TextWrapped         = true
        lbl.TextXAlignment      = Enum.TextXAlignment.Left
        lbl.Parent              = scroll
        return lbl
    end

    return W
end

-- ─── Coin Collect ──────────────────────────────────────────────────────────────

local function findCoins()
    local list = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "Coin_Server" and obj:IsA("BasePart") then
            list[#list + 1] = obj
        end
    end
    return list
end

local function floatToward(target, speed)
    local root = getRoot()
    if not root or not target or not target.Parent then return end

    local bp = Instance.new("BodyPosition")
    bp.Name      = "_CoinBP"
    bp.MaxForce  = Vector3.new(1e5, 1e5, 1e5)
    bp.P         = 1e4
    bp.D         = 400
    bp.Position  = target.Position
    bp.Parent    = root

    local bg = Instance.new("BodyGyro")
    bg.Name      = "_CoinBG"
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.P         = 1e4
    bg.Parent    = root

    local timeout = (root.Position - target.Position).Magnitude / math.max(speed, 1) + 3
    local elapsed = 0

    while elapsed < timeout and State.coinCollect
          and target and target.Parent do
        _wait(0.05)
        elapsed = elapsed + 0.05
        local r = getRoot()
        if not r then break end
        local dist = (target.Position - r.Position).Magnitude
        if dist < 3 then break end
        bp.Position = target.Position
        bg.CFrame   = CFrame.new(r.Position, target.Position)
    end

    local r2 = getRoot()
    if r2 then
        destroyChild(r2, "_CoinBP")
        destroyChild(r2, "_CoinBG")
    end
    pcall(function() bp:Destroy() end)
    pcall(function() bg:Destroy() end)
end

local function startCoinCollect()
    if State.collecting then return end
    State.collecting = true
    _spawn(function()
        while State.coinCollect do
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
                            floatToward(coin, State.coinSpeed)
                            _wait(0.05)
                        end
                    end
                end
                _wait(0.3)
            end
        end
        State.collecting = false
    end)
end

local function stopCoinCollect()
    State.coinCollect = false
    local root = getRoot()
    if root then
        destroyChild(root, "_CoinBP")
        destroyChild(root, "_CoinBG")
    end
end

-- ─── Role ESP ──────────────────────────────────────────────────────────────────

local ROLE_COLOR = {
    Murderer = Color3.fromRGB(220, 50,  50),
    Sheriff  = Color3.fromRGB(80,  160, 255),
    Hero     = Color3.fromRGB(255, 200, 50),
    Innocent = Color3.fromRGB(80,  220, 120),
}

local function clearEsp()
    for k, obj in pairs(State.espObjects) do
        if obj and obj.Parent then
            pcall(function() obj:Destroy() end)
        end
        State.espObjects[k] = nil
    end
end

local function updateEspLabel(player)
    local bb = State.espObjects[player.Name]
    if not bb or not bb.Parent then return end
    local bg    = bb:FindFirstChildOfClass("Frame")
    if not bg then return end
    local rl    = bg:FindFirstChild("RoleLbl")
    if not rl then return end
    local role  = State.roles[player.Name] or "?"
    local color = ROLE_COLOR[role] or Color3.fromRGB(180, 180, 180)
    rl.Text        = role
    rl.TextColor3  = color
end

local function attachEsp(player)
    if player == LocalPlayer then return end
    if State.espObjects[player.Name] then return end

    local gui = LocalPlayer:WaitForChild("PlayerGui")

    local bb = Instance.new("BillboardGui")
    bb.Name        = "RESP_" .. player.Name
    bb.Size        = UDim2.new(0, 120, 0, 42)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop = true
    bb.ResetOnSpawn = false
    bb.Parent      = gui

    State.espObjects[player.Name] = bb

    local bg = Instance.new("Frame")
    bg.Size                 = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3     = Color3.fromRGB(10, 10, 14)
    bg.BackgroundTransparency = 0.35
    bg.BorderSizePixel      = 0
    bg.Parent               = bb

    local bgc = Instance.new("UICorner")
    bgc.CornerRadius = UDim.new(0, 5)
    bgc.Parent = bg

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name               = "NameLbl"
    nameLbl.Size               = UDim2.new(1, -6, 0.5, 0)
    nameLbl.Position           = UDim2.new(0, 3, 0, 2)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text               = player.Name
    nameLbl.TextColor3         = Color3.fromRGB(240, 240, 240)
    nameLbl.TextSize           = 11
    nameLbl.Font               = Enum.Font.GothamBold
    nameLbl.TextScaled         = true
    nameLbl.Parent             = bg

    local roleLbl = Instance.new("TextLabel")
    roleLbl.Name               = "RoleLbl"
    roleLbl.Size               = UDim2.new(1, -6, 0.5, 0)
    roleLbl.Position           = UDim2.new(0, 3, 0.5, -2)
    roleLbl.BackgroundTransparency = 1
    roleLbl.Text               = State.roles[player.Name] or "?"
    roleLbl.TextColor3         = ROLE_COLOR[State.roles[player.Name]] or Color3.fromRGB(180, 180, 180)
    roleLbl.TextSize           = 10
    roleLbl.Font               = Enum.Font.GothamSemibold
    roleLbl.TextScaled         = true
    roleLbl.Parent             = bg

    local function anchorTo(char)
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
                  or char:FindFirstChild("UpperTorso")
                  or char:FindFirstChild("Torso")
        if root then bb.Adornee = root end
    end

    anchorTo(player.Character)
    player.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart", 5)
        anchorTo(char)
    end)
end

local function enableEsp()
    clearEsp()
    for _, p in ipairs(Players:GetPlayers()) do
        attachEsp(p)
    end
    State._espAdded = Players.PlayerAdded:Connect(function(p)
        if State.esp then attachEsp(p) end
    end)
    State._espRemoving = Players.PlayerRemoving:Connect(function(p)
        local obj = State.espObjects[p.Name]
        if obj and obj.Parent then pcall(function() obj:Destroy() end) end
        State.espObjects[p.Name] = nil
        State.roles[p.Name] = nil
    end)
end

local function disableEsp()
    clearEsp()
    if State._espAdded   then State._espAdded:Disconnect();   State._espAdded   = nil end
    if State._espRemoving then State._espRemoving:Disconnect(); State._espRemoving = nil end
end

-- ─── PlayerDataChanged → roles ─────────────────────────────────────────────────

local function listenRoles()
    local remote = getRemote({ "Remotes", "Gameplay", "PlayerDataChanged" })
    if not remote then return end
    if not remote:IsA("RemoteEvent") then return end

    remote.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local pname = data.Name or data.PlayerName or data.Username
        local role  = data.Role
        if type(pname) == "string" and type(role) == "string" then
            State.roles[pname] = role
            if State.esp then
                local p = Players:FindFirstChild(pname)
                if p then updateEspLabel(p) end
            end
        end
    end)
end

-- ─── Gun Drop Collect ──────────────────────────────────────────────────────────

local function findGunDrop()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "GunDrop" and obj:IsA("BasePart") then
            return obj
        end
    end
    return nil
end

local function walkToGunDrop(gunDrop)
    local root = getRoot()
    if not root or not gunDrop or not gunDrop.Parent then return end

    local bp = Instance.new("BodyPosition")
    bp.Name     = "_GunDropBP"
    bp.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bp.P        = 8000
    bp.D        = 500
    bp.Position = gunDrop.Position
    bp.Parent   = root

    local bg = Instance.new("BodyGyro")
    bg.Name     = "_GunDropBG"
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.P        = 8000
    bg.CFrame   = CFrame.new(root.Position, gunDrop.Position)
    bg.Parent   = root

    local elapsed = 0
    while elapsed < 10 and State.gunDrop
          and gunDrop and gunDrop.Parent do
        _wait(0.05)
        elapsed = elapsed + 0.05
        local r = getRoot()
        if not r then break end
        if (gunDrop.Position - r.Position).Magnitude < 4 then break end
        bp.Position = gunDrop.Position
        bg.CFrame   = CFrame.new(r.Position, gunDrop.Position)
    end

    local r2 = getRoot()
    if r2 then
        destroyChild(r2, "_GunDropBP")
        destroyChild(r2, "_GunDropBG")
    end
    pcall(function() bp:Destroy() end)
    pcall(function() bg:Destroy() end)
end

local function startGunDropWatch()
    if State._gunDropWatch then return end
    State._gunDropWatch = true

    _spawn(function()
        while State.gunDrop do
            local gd = findGunDrop()
            if gd then
                walkToGunDrop(gd)
            end
            _wait(1.5)
        end
        State._gunDropWatch = false
    end)

    State._gunDropConn = workspace.DescendantAdded:Connect(function(inst)
        if inst.Name == "GunDrop" and inst:IsA("BasePart") and State.gunDrop then
            _spawn(function()
                _wait(0.15)
                walkToGunDrop(inst)
            end)
        end
    end)
end

local function stopGunDropWatch()
    State.gunDrop       = false
    State._gunDropWatch = false
    if State._gunDropConn then
        State._gunDropConn:Disconnect()
        State._gunDropConn = nil
    end
    local root = getRoot()
    if root then
        destroyChild(root, "_GunDropBP")
        destroyChild(root, "_GunDropBG")
    end
end

-- ─── Build UI ──────────────────────────────────────────────────────────────────

local W = RefLib.Window("ref_universal")

W:Section("  COINS")

W:Toggle("Coin Collect", false, function(v)
    State.coinCollect = v
    if v then
        startCoinCollect()
    else
        stopCoinCollect()
    end
end)

W:Slider("Speed", 10, 200, 50, function(v)
    State.coinSpeed = v
end)

W:Label("Flutua até cada coin no mapa, da mais próxima à mais longe.")

W:Section("  ESP")

W:Toggle("Role ESP", false, function(v)
    State.esp = v
    if v then enableEsp() else disableEsp() end
end)

W:Label("Murderer=vermelho  Sheriff=azul  Hero=amarelo  Innocent=verde")

W:Section("  GUN DROP")

W:Toggle("Auto Collect Gun Drop", false, function(v)
    State.gunDrop = v
    if v then
        startGunDropWatch()
    else
        stopGunDropWatch()
    end
end)

W:Label("Detecta e vai até a GunDrop quando aparecer no mapa.")

W:Section("  STATUS")
local statusLbl = W:Label("Pronto.")

-- ─── Status loop ───────────────────────────────────────────────────────────────

_spawn(function()
    while true do
        _wait(2)
        local parts = {}
        if State.coinCollect then parts[#parts + 1] = "coins" end
        if State.esp         then parts[#parts + 1] = "esp"   end
        if State.gunDrop     then parts[#parts + 1] = "gundrop" end
        local roleStr = ""
        local myRole  = State.roles[LocalPlayer.Name]
        if myRole then roleStr = " | role: " .. myRole end
        local txt = #parts > 0
            and ("Ativo: " .. table.concat(parts, ", ") .. roleStr)
            or  ("Inativo" .. roleStr)
        pcall(function() statusLbl.Text = txt end)
    end
end)

-- ─── Init ──────────────────────────────────────────────────────────────────────

listenRoles()
