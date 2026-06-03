-- ref_universal | Murder Mystery tester
-- Features: Coin Collect, Role ESP, Gun Drop Collect

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ─── RefLib (minimal inline) ──────────────────────────────────────────────────

local RefLib = {}

function RefLib.Window(title)
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("RefUniversal")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "RefUniversal"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999997
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 220, 0, 560)
    frame.Position = UDim2.new(0, 14, 0.5, -280)
    frame.BackgroundColor3 = Color3.fromRGB(14, 15, 18)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(55, 60, 72)
    stroke.Thickness = 1
    stroke.Parent = frame

    local bar = Instance.new("Frame")
    bar.Name = "TitleBar"
    bar.Size = UDim2.new(1, 0, 0, 34)
    bar.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
    bar.BorderSizePixel = 0
    bar.Parent = frame

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 10)
    barCorner.Parent = bar

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(1, 0, 0.5, 0)
    barFill.Position = UDim2.new(0, 0, 0.5, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
    barFill.BorderSizePixel = 0
    barFill.Parent = bar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -12, 1, 0)
    titleLabel.Position = UDim2.new(0, 12, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = bar

    -- drag
    do
        local dragging, dragStart, startPos = false, nil, nil
        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Content"
    scroll.Size = UDim2.new(1, 0, 1, -38)
    scroll.Position = UDim2.new(0, 0, 0, 38)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 2
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 90, 110)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = frame

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 5)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.Parent = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = scroll

    local W = { gui = gui, frame = frame, scroll = scroll, _y = 0 }

    function W:Section(label)
        local s = Instance.new("TextLabel")
        s.Size = UDim2.new(1, -16, 0, 20)
        s.BackgroundTransparency = 1
        s.Text = label
        s.TextColor3 = Color3.fromRGB(100, 115, 140)
        s.TextSize = 11
        s.Font = Enum.Font.GothamBold
        s.TextXAlignment = Enum.TextXAlignment.Left
        s.Parent = scroll
    end

    function W:Toggle(label, default, callback)
        local state = default or false

        local holder = Instance.new("Frame")
        holder.Size = UDim2.new(1, -16, 0, 34)
        holder.BackgroundColor3 = Color3.fromRGB(22, 25, 31)
        holder.BorderSizePixel = 0
        holder.Parent = scroll

        local hc = Instance.new("UICorner")
        hc.CornerRadius = UDim.new(0, 7)
        hc.Parent = holder

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -54, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = Color3.fromRGB(210, 215, 225)
        lbl.TextSize = 12
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = holder

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 36, 0, 18)
        track.Position = UDim2.new(1, -46, 0.5, -9)
        track.BackgroundColor3 = state and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(50, 54, 64)
        track.BorderSizePixel = 0
        track.Parent = holder

        local tc = Instance.new("UICorner")
        tc.CornerRadius = UDim.new(1, 0)
        tc.Parent = track

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel = 0
        knob.Parent = track

        local kc = Instance.new("UICorner")
        kc.CornerRadius = UDim.new(1, 0)
        kc.Parent = knob

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = holder

        btn.MouseButton1Click:Connect(function()
            state = not state
            TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = state and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(50, 54, 64) }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7) }):Play()
            if callback then pcall(callback, state) end
        end)

        local T = {}
        function T:Set(v)
            state = v
            TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = state and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(50, 54, 64) }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7) }):Play()
        end
        function T:Get() return state end
        return T
    end

    function W:Slider(label, min, max, default, callback)
        local val = default or min

        local holder = Instance.new("Frame")
        holder.Size = UDim2.new(1, -16, 0, 52)
        holder.BackgroundColor3 = Color3.fromRGB(22, 25, 31)
        holder.BorderSizePixel = 0
        holder.Parent = scroll

        local hc = Instance.new("UICorner")
        hc.CornerRadius = UDim.new(0, 7)
        hc.Parent = holder

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -10, 0, 22)
        lbl.Position = UDim2.new(0, 10, 0, 2)
        lbl.BackgroundTransparency = 1
        lbl.Text = label .. ": " .. tostring(val)
        lbl.TextColor3 = Color3.fromRGB(210, 215, 225)
        lbl.TextSize = 12
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = holder

        local rail = Instance.new("Frame")
        rail.Size = UDim2.new(1, -20, 0, 6)
        rail.Position = UDim2.new(0, 10, 0, 34)
        rail.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
        rail.BorderSizePixel = 0
        rail.Parent = holder

        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(1, 0)
        rc.Parent = rail

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
        fill.BorderSizePixel = 0
        fill.Parent = rail

        local fc = Instance.new("UICorner")
        fc.CornerRadius = UDim.new(1, 0)
        fc.Parent = fill

        local thumb = Instance.new("Frame")
        thumb.Size = UDim2.new(0, 14, 0, 14)
        thumb.Position = UDim2.new((val - min) / (max - min), -7, 0.5, -7)
        thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        thumb.BorderSizePixel = 0
        thumb.ZIndex = 3
        thumb.Parent = rail

        local tс = Instance.new("UICorner")
        tс.CornerRadius = UDim.new(1, 0)
        tс.Parent = thumb

        local dragging = false

        local function update(inputPos)
            local railPos = rail.AbsolutePosition
            local railSize = rail.AbsoluteSize
            local rel = math.clamp((inputPos.X - railPos.X) / railSize.X, 0, 1)
            local rounded = math.floor(min + rel * (max - min) + 0.5)
            if rounded ~= val then
                val = rounded
                local frac = (val - min) / (max - min)
                fill.Size = UDim2.new(frac, 0, 1, 0)
                thumb.Position = UDim2.new(frac, -7, 0.5, -7)
                lbl.Text = label .. ": " .. tostring(val)
                if callback then pcall(callback, val) end
            end
        end

        rail.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                update(input.Position)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                update(input.Position)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        local S = {}
        function S:Get() return val end
        return S
    end

    function W:Button(label, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 34)
        btn.BackgroundColor3 = Color3.fromRGB(34, 38, 50)
        btn.BorderSizePixel = 0
        btn.Text = label
        btn.TextColor3 = Color3.fromRGB(210, 218, 235)
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamSemibold
        btn.Parent = scroll

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 7)
        bc.Parent = btn

        btn.MouseButton1Click:Connect(function()
            if callback then pcall(callback) end
        end)
    end

    function W:Label(text)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -16, 0, 24)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(140, 150, 170)
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.TextWrapped = true
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = scroll
        return lbl
    end

    return W
end

-- ─── Estado global ─────────────────────────────────────────────────────────────

local State = {
    coinCollect = false,
    coinSpeed = 50,
    esp = false,
    gunDrop = false,
    roles = {},
    espObjects = {},
    collecting = false,
    gunDropConn = nil,
}

-- ─── Utilitários ───────────────────────────────────────────────────────────────

local function getCharacter()
    return LocalPlayer.Character
end

local function getRoot()
    local char = getCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function safeWait(n)
    if task and task.wait then
        task.wait(n)
    else
        wait(n)
    end
end

local function spawnTask(fn)
    if task and task.spawn then
        task.spawn(fn)
    else
        spawn(fn)
    end
end

-- ─── Remote helpers ────────────────────────────────────────────────────────────

local function getRemote(path)
    local current = ReplicatedStorage
    for _, name in ipairs(path) do
        local child = current:FindFirstChild(name)
        if not child then return nil end
        current = child
    end
    return current
end

-- ─── Coin Collect ──────────────────────────────────────────────────────────────

local function findCoins()
    local coins = {}
    local ws = workspace
    for _, obj in ipairs(ws:GetDescendants()) do
        if obj.Name == "Coin_Server" and obj:IsA("BasePart") then
            coins[#coins + 1] = obj
        end
    end
    return coins
end

local function floatTowardPart(part, speed)
    local root = getRoot()
    if not root or not part or not part.Parent then return end

    local bodyPos = root:FindFirstChild("_CoinBodyPos")
    if not bodyPos then
        bodyPos = Instance.new("BodyPosition")
        bodyPos.Name = "_CoinBodyPos"
        bodyPos.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bodyPos.P = 1e4
        bodyPos.Parent = root
    end

    local bodyGyro = root:FindFirstChild("_CoinBodyGyro")
    if not bodyGyro then
        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Name = "_CoinBodyGyro"
        bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
        bodyGyro.P = 1e4
        bodyGyro.Parent = root
    end

    local startPos = root.Position
    local targetPos = part.Position
    local dist = (targetPos - startPos).Magnitude
    local travelTime = dist / math.max(speed, 1)
    local elapsed = 0

    while elapsed < travelTime and State.coinCollect and part and part.Parent do
        local dt = safeWait(0.03) or 0.03
        elapsed = elapsed + dt

        local root2 = getRoot()
        if not root2 then break end

        local t = math.clamp(elapsed / travelTime, 0, 1)
        local pos = startPos + (targetPos - startPos) * t
        bodyPos.Position = pos
        bodyGyro.CFrame = CFrame.new(root2.Position, targetPos)
    end

    local bodyPos2 = root:FindFirstChild("_CoinBodyPos")
    if bodyPos2 then bodyPos2:Destroy() end
    local bodyGyro2 = root:FindFirstChild("_CoinBodyGyro")
    if bodyGyro2 then bodyGyro2:Destroy() end
end

local function startCoinCollect()
    if State.collecting then return end
    State.collecting = true

    spawnTask(function()
        while State.coinCollect do
            local coins = findCoins()
            if #coins == 0 then
                safeWait(1)
            else
                local root = getRoot()
                if root then
                    table.sort(coins, function(a, b)
                        local da = (a.Position - root.Position).Magnitude
                        local db = (b.Position - root.Position).Magnitude
                        return da < db
                    end)
                    for _, coin in ipairs(coins) do
                        if not State.coinCollect then break end
                        if coin and coin.Parent then
                            floatTowardPart(coin, State.coinSpeed)
                            safeWait(0.05)
                        end
                    end
                end
                safeWait(0.5)
            end
        end
        State.collecting = false
    end)
end

local function stopCoinCollect()
    State.coinCollect = false
    local root = getRoot()
    if root then
        local bp = root:FindFirstChild("_CoinBodyPos")
        if bp then bp:Destroy() end
        local bg = root:FindFirstChild("_CoinBodyGyro")
        if bg then bg:Destroy() end
    end
end

-- ─── Role ESP ──────────────────────────────────────────────────────────────────

local ROLE_COLORS = {
    Murderer  = Color3.fromRGB(220, 50,  50),
    Sheriff   = Color3.fromRGB(80,  160, 255),
    Hero      = Color3.fromRGB(255, 200, 50),
    Innocent  = Color3.fromRGB(80,  220, 120),
}

local function clearEsp()
    for _, obj in pairs(State.espObjects) do
        if obj and obj.Parent then
            pcall(function() obj:Destroy() end)
        end
    end
    State.espObjects = {}
end

local function makeEspLabel(player)
    local gui = LocalPlayer:WaitForChild("PlayerGui")
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "RoleESP_" .. player.Name
    billboard.Size = UDim2.new(0, 120, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    billboard.Parent = gui

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    bg.BackgroundTransparency = 0.35
    bg.BorderSizePixel = 0
    bg.Parent = billboard

    local bgc = Instance.new("UICorner")
    bgc.CornerRadius = UDim.new(0, 5)
    bgc.Parent = bg

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name = "NameLbl"
    nameLbl.Size = UDim2.new(1, -6, 0.5, 0)
    nameLbl.Position = UDim2.new(0, 3, 0, 2)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = player.Name
    nameLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
    nameLbl.TextSize = 11
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextScaled = true
    nameLbl.Parent = bg

    local roleLbl = Instance.new("TextLabel")
    roleLbl.Name = "RoleLbl"
    roleLbl.Size = UDim2.new(1, -6, 0.5, 0)
    roleLbl.Position = UDim2.new(0, 3, 0.5, -2)
    roleLbl.BackgroundTransparency = 1
    roleLbl.Text = "?"
    roleLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
    roleLbl.TextSize = 10
    roleLbl.Font = Enum.Font.GothamSemibold
    roleLbl.TextScaled = true
    roleLbl.Parent = bg

    return billboard, roleLbl
end

local function attachEspToPlayer(player)
    if player == LocalPlayer then return end

    local billboard, roleLbl = makeEspLabel(player)
    State.espObjects[player.Name] = billboard

    local function updateAnchor()
        local char = player.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            if root then
                billboard.Adornee = root
            end
        end
    end

    updateAnchor()

    player.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart", 5)
        updateAnchor()
    end)

    local function updateRole()
        local role = State.roles[player.Name] or "?"
        local color = ROLE_COLORS[role] or Color3.fromRGB(180, 180, 180)
        roleLbl.Text = role
        roleLbl.TextColor3 = color
    end

    updateRole()

    return function()
        updateRole()
    end
end

local function refreshEspLabels()
    for playerName, billboard in pairs(State.espObjects) do
        if billboard and billboard.Parent then
            local roleLbl = billboard:FindFirstChild("Frame") and billboard.Frame:FindFirstChild("RoleLbl")
            if not roleLbl then
                roleLbl = billboard:FindFirstChildOfClass("Frame") and billboard:FindFirstChildOfClass("Frame"):FindFirstChild("RoleLbl")
            end
            if roleLbl then
                local role = State.roles[playerName] or "?"
                local color = ROLE_COLORS[role] or Color3.fromRGB(180, 180, 180)
                roleLbl.Text = role
                roleLbl.TextColor3 = color
            end
        end
    end
end

local function enableEsp()
    clearEsp()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            attachEspToPlayer(player)
        end
    end
    State._espPlayerAdded = Players.PlayerAdded:Connect(function(player)
        if State.esp then
            attachEspToPlayer(player)
        end
    end)
    State._espPlayerRemoving = Players.PlayerRemoving:Connect(function(player)
        local obj = State.espObjects[player.Name]
        if obj and obj.Parent then
            pcall(function() obj:Destroy() end)
        end
        State.espObjects[player.Name] = nil
        State.roles[player.Name] = nil
    end)
end

local function disableEsp()
    clearEsp()
    if State._espPlayerAdded then
        State._espPlayerAdded:Disconnect()
        State._espPlayerAdded = nil
    end
    if State._espPlayerRemoving then
        State._espPlayerRemoving:Disconnect()
        State._espPlayerRemoving = nil
    end
end

-- Ouve PlayerDataChanged para capturar roles
local function listenRoles()
    local remote = getRemote({ "Remotes", "Gameplay", "PlayerDataChanged" })
    if not remote or not remote:IsA("RemoteEvent") then return end

    remote.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local playerName = data.Name or data.PlayerName
        local role = data.Role
        if playerName and role then
            State.roles[playerName] = role
            if State.esp then
                refreshEspLabels()
            end
        end
    end)
end

-- ─── Gun Drop Collect ──────────────────────────────────────────────────────────

local function getCurrentMap()
    for _, child in ipairs(workspace:GetChildren()) do
        if child:FindFirstChild("GunDrop") then
            return child
        end
    end
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            local gd = child:FindFirstChild("GunDrop")
            if gd then return child end
        end
    end
    return nil
end

local function findGunDrop()
    for _, child in ipairs(workspace:GetDescendants()) do
        if child.Name == "GunDrop" and child:IsA("BasePart") then
            return child
        end
    end
    return nil
end

local function walkToGunDrop(gunDrop)
    local root = getRoot()
    if not root or not gunDrop or not gunDrop.Parent then return end

    local bodyPos = Instance.new("BodyPosition")
    bodyPos.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bodyPos.P = 8000
    bodyPos.D = 500
    bodyPos.Position = gunDrop.Position
    bodyPos.Parent = root

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bodyGyro.P = 8000
    bodyGyro.CFrame = CFrame.new(root.Position, gunDrop.Position)
    bodyGyro.Parent = root

    local timeout = 8
    local elapsed = 0
    while elapsed < timeout and gunDrop and gunDrop.Parent and State.gunDrop do
        local dt = safeWait(0.05) or 0.05
        elapsed = elapsed + dt
        local r = getRoot()
        if not r then break end
        local dist = (gunDrop.Position - r.Position).Magnitude
        if dist < 4 then break end
        bodyPos.Position = gunDrop.Position
        bodyGyro.CFrame = CFrame.new(r.Position, gunDrop.Position)
    end

    if root and root.Parent then
        local bp = root:FindFirstChild(bodyPos.Name)
        if bp then pcall(function() bp:Destroy() end) end
        bodyPos:Destroy()
        bodyGyro:Destroy()
    end
end

local function startGunDropWatch()
    if State._gunDropWatching then return end
    State._gunDropWatching = true

    spawnTask(function()
        while State.gunDrop do
            local gunDrop = findGunDrop()
            if gunDrop then
                local role = State.roles[LocalPlayer.Name]
                if role == "Sheriff" or role == "Hero" or role == nil then
                    walkToGunDrop(gunDrop)
                end
            end
            safeWait(1.5)
        end
        State._gunDropWatching = false
    end)

    -- também escuta DescendantAdded para reação rápida
    State._gunDropConn = workspace.DescendantAdded:Connect(function(inst)
        if inst.Name == "GunDrop" and inst:IsA("BasePart") and State.gunDrop then
            spawnTask(function()
                safeWait(0.2)
                local role = State.roles[LocalPlayer.Name]
                if role == "Sheriff" or role == "Hero" or role == nil then
                    walkToGunDrop(inst)
                end
            end)
        end
    end)
end

local function stopGunDropWatch()
    State.gunDrop = false
    if State._gunDropConn then
        State._gunDropConn:Disconnect()
        State._gunDropConn = nil
    end
    State._gunDropWatching = false
end

-- ─── UI ────────────────────────────────────────────────────────────────────────

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
    if v then
        enableEsp()
    else
        disableEsp()
    end
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

W:Label("Detecta e vai buscar a GunDrop quando aparecer no mapa.")

W:Section("  INFO")
local statusLbl = W:Label("Pronto.")

-- ─── Status loop ───────────────────────────────────────────────────────────────

spawnTask(function()
    while true do
        safeWait(2)
        local parts = {}
        if State.coinCollect then parts[#parts + 1] = "coins" end
        if State.esp then parts[#parts + 1] = "esp" end
        if State.gunDrop then parts[#parts + 1] = "gundrop" end
        local role = State.roles[LocalPlayer.Name]
        local roleStr = role and (" | role: " .. role) or ""
        if statusLbl then
            local txt = #parts > 0 and ("Ativo: " .. table.concat(parts, ", ") .. roleStr) or ("Inativo" .. roleStr)
            pcall(function() statusLbl.Text = txt end)
        end
    end
end)

-- ─── Inicialização ─────────────────────────────────────────────────────────────

listenRoles()
