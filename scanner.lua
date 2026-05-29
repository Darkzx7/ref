local RefLib = {}
RefLib.__index = RefLib

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local lp               = Players.LocalPlayer
local pg               = lp:WaitForChild("PlayerGui")

local C = {
    bg      = Color3.fromRGB(18, 14, 30),
    panel   = Color3.fromRGB(28, 22, 45),
    section = Color3.fromRGB(36, 28, 58),
    btn     = Color3.fromRGB(50, 38, 80),
    btnHov  = Color3.fromRGB(68, 52, 108),
    toggle  = Color3.fromRGB(40, 160, 100),
    toggleOff = Color3.fromRGB(80, 60, 100),
    slider  = Color3.fromRGB(80, 120, 220),
    tab     = Color3.fromRGB(44, 34, 70),
    tabSel  = Color3.fromRGB(80, 60, 130),
    text    = Color3.fromRGB(220, 210, 240),
    sub     = Color3.fromRGB(150, 135, 180),
    div     = Color3.fromRGB(60, 48, 90),
}

local function mkCorner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p end
local function mkPad(p,t,b,l,r) local c=Instance.new("UIPadding"); c.PaddingTop=UDim.new(0,t); c.PaddingBottom=UDim.new(0,b); c.PaddingLeft=UDim.new(0,l); c.PaddingRight=UDim.new(0,r); c.Parent=p end
local function mkList(p,pad,dir) local c=Instance.new("UIListLayout"); c.Padding=UDim.new(0,pad or 4); c.FillDirection=dir or Enum.FillDirection.Vertical; c.SortOrder=Enum.SortOrder.LayoutOrder; c.Parent=p; return c end
local function mkLabel(parent, text, size, color, bold, xa)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = size or UDim2.new(1,0,0,16)
    l.Text = text
    l.TextColor3 = color or C.text
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.TextStrokeTransparency = 0.7
    l.Parent = parent
    return l
end

local toastGui
local function ensureToastGui()
    if toastGui and toastGui.Parent then return end
    toastGui = Instance.new("ScreenGui")
    toastGui.Name = "RefLibToast"
    toastGui.ResetOnSpawn = false
    toastGui.DisplayOrder = 200
    toastGui.IgnoreGuiInset = true
    toastGui.Parent = pg
end

local toastQueue = {}
local toastBusy  = false

local function showNextToast()
    if toastBusy or #toastQueue == 0 then return end
    toastBusy = true
    ensureToastGui()
    local t = table.remove(toastQueue, 1)

    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, 280, 0, 52)
    card.Position = UDim2.new(1, 10, 1, -80)
    card.BackgroundColor3 = C.panel
    card.BorderSizePixel = 0
    card.Parent = toastGui
    mkCorner(card, 8)

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 1, 0)
    accent.BackgroundColor3 = t.color or C.toggle
    accent.BorderSizePixel = 0
    accent.Parent = card
    mkCorner(accent, 3)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,-16,0,18)
    title.Position = UDim2.new(0,12,0,6)
    title.BackgroundTransparency = 1
    title.Text = t.title or ""
    title.TextColor3 = t.color or C.text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local msg = Instance.new("TextLabel")
    msg.Size = UDim2.new(1,-16,0,14)
    msg.Position = UDim2.new(0,12,0,26)
    msg.BackgroundTransparency = 1
    msg.Text = t.msg or ""
    msg.TextColor3 = C.sub
    msg.Font = Enum.Font.Gotham
    msg.TextSize = 11
    msg.TextXAlignment = Enum.TextXAlignment.Left
    msg.Parent = card

    TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = UDim2.new(1, -290, 1, -80)}):Play()

    task.delay(2.2, function()
        TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Position = UDim2.new(1, 10, 1, -80)}):Play()
        task.wait(0.22)
        pcall(function() card:Destroy() end)
        toastBusy = false
        showNextToast()
    end)
end

local cfgStore = {}

function RefLib.new(title, icon, key)
    local self = setmetatable({}, RefLib)
    self._key     = key
    self._tabs    = {}
    self._cfg     = {}
    self._tabBtns = {}
    self._curTab  = nil

    local sg = Instance.new("ScreenGui")
    sg.Name = "RefLib_"..key
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 100
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = pg
    self._sg = sg

    local win = Instance.new("Frame")
    win.Name = "Window"
    win.Size = UDim2.new(0, 340, 0, 480)
    win.Position = UDim2.new(0.5, -170, 0.5, -240)
    win.BackgroundColor3 = C.bg
    win.BorderSizePixel = 0
    win.Active = true
    win.Draggable = true
    win.Parent = sg
    mkCorner(win, 10)
    self._win = win

    local stroke = Instance.new("UIStroke")
    stroke.Color = C.div
    stroke.Thickness = 1
    stroke.Parent = win

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = C.panel
    header.BorderSizePixel = 0
    header.Parent = win
    mkCorner(header, 10)

    local headerFill = Instance.new("Frame")
    headerFill.Size = UDim2.new(1,0,0,10)
    headerFill.Position = UDim2.new(0,0,1,-10)
    headerFill.BackgroundColor3 = C.panel
    headerFill.BorderSizePixel = 0
    headerFill.Parent = header

    local titleLbl = mkLabel(header, title, UDim2.new(1,-50,1,0), C.text, true, Enum.TextXAlignment.Center)
    titleLbl.Position = UDim2.new(0,0,0,0)
    titleLbl.TextSize = 13

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0,28,0,28)
    closeBtn.Position = UDim2.new(1,-32,0,4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180,60,60)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.Parent = header
    mkCorner(closeBtn, 6)
    closeBtn.MouseButton1Click:Connect(function()
        win.Visible = not win.Visible
    end)

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1,-8,0,28)
    tabBar.Position = UDim2.new(0,4,0,38)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = win
    self._tabBar = tabBar
    mkList(tabBar, 4, Enum.FillDirection.Horizontal)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1,-8,1,-76)
    scroll.Position = UDim2.new(0,4,0,70)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = C.div
    scroll.CanvasSize = UDim2.new(0,0,0,0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = win
    self._scroll = scroll
    mkList(scroll, 6)
    mkPad(scroll, 4, 4, 0, 0)

    return self
end

function RefLib:Tab(name)
    local tabFrame = Instance.new("Frame")
    tabFrame.Size = UDim2.new(1,0,0,0)
    tabFrame.BackgroundTransparency = 1
    tabFrame.AutomaticSize = Enum.AutomaticSize.Y
    tabFrame.Visible = false
    tabFrame.Parent = self._scroll
    mkList(tabFrame, 6)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 60, 1, 0)
    btn.BackgroundColor3 = C.tab
    btn.BorderSizePixel = 0
    btn.Text = name
    btn.TextColor3 = C.sub
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 11
    btn.Parent = self._tabBar
    mkCorner(btn, 6)

    local tabObj = {_frame=tabFrame, _btn=btn, _ui=self}

    local function selectTab()
        for _, t in ipairs(self._tabs) do
            t._frame.Visible = false
            t._btn.BackgroundColor3 = C.tab
            t._btn.TextColor3 = C.sub
        end
        tabFrame.Visible = true
        btn.BackgroundColor3 = C.tabSel
        btn.TextColor3 = C.text
        self._curTab = tabObj
    end

    btn.MouseButton1Click:Connect(selectTab)
    table.insert(self._tabs, tabObj)

    if #self._tabs == 1 then
        tabFrame.Visible = true
        btn.BackgroundColor3 = C.tabSel
        btn.TextColor3 = C.text
        self._curTab = tabObj
    end

    local count = #self._tabs
    for _, t in ipairs(self._tabs) do
        t._btn.Size = UDim2.new(1/count, -4, 1, 0)
    end

    function tabObj:Section(sname)
        local sec = Instance.new("Frame")
        sec.Size = UDim2.new(1,0,0,0)
        sec.AutomaticSize = Enum.AutomaticSize.Y
        sec.BackgroundColor3 = C.section
        sec.BorderSizePixel = 0
        sec.Parent = tabFrame
        mkCorner(sec, 8)
        mkPad(sec, 6, 6, 8, 8)

        local inner = Instance.new("Frame")
        inner.Size = UDim2.new(1,0,0,0)
        inner.AutomaticSize = Enum.AutomaticSize.Y
        inner.BackgroundTransparency = 1
        inner.Parent = sec
        local lay = mkList(inner, 4)

        local stitle = mkLabel(inner, sname:upper(), UDim2.new(1,0,0,14), C.sub, true)
        stitle.TextSize = 10
        stitle.LayoutOrder = 0

        local order = 1
        local secObj = {}

        function secObj:Button(label, cb)
            order = order + 1
            local btn2 = Instance.new("TextButton")
            btn2.Size = UDim2.new(1,0,0,28)
            btn2.BackgroundColor3 = C.btn
            btn2.BorderSizePixel = 0
            btn2.Text = label
            btn2.TextColor3 = C.text
            btn2.Font = Enum.Font.Gotham
            btn2.TextSize = 12
            btn2.LayoutOrder = order
            btn2.Parent = inner
            mkCorner(btn2, 6)
            btn2.MouseButton1Click:Connect(function() pcall(cb) end)
            btn2.MouseEnter:Connect(function() btn2.BackgroundColor3 = C.btnHov end)
            btn2.MouseLeave:Connect(function() btn2.BackgroundColor3 = C.btn end)
        end

        function secObj:Toggle(label, default, cb)
            order = order + 1
            local state = default or false

            local row = Instance.new("Frame")
            row.Size = UDim2.new(1,0,0,28)
            row.BackgroundColor3 = C.btn
            row.BorderSizePixel = 0
            row.LayoutOrder = order
            row.Parent = inner
            mkCorner(row, 6)

            local lbl2 = mkLabel(row, label, UDim2.new(1,-48,1,0), C.text, false)
            lbl2.Position = UDim2.new(0,8,0,0)

            local pill = Instance.new("Frame")
            pill.Size = UDim2.new(0,36,0,18)
            pill.Position = UDim2.new(1,-44,0.5,-9)
            pill.BackgroundColor3 = state and C.toggle or C.toggleOff
            pill.BorderSizePixel = 0
            pill.Parent = row
            mkCorner(pill, 9)

            local knob = Instance.new("Frame")
            knob.Size = UDim2.new(0,14,0,14)
            knob.Position = state and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
            knob.BackgroundColor3 = Color3.new(1,1,1)
            knob.BorderSizePixel = 0
            knob.Parent = pill
            mkCorner(knob, 7)

            local function setState(v)
                state = v
                pill.BackgroundColor3 = state and C.toggle or C.toggleOff
                knob.Position = state and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
                pcall(cb, state)
            end

            local clickArea = Instance.new("TextButton")
            clickArea.Size = UDim2.new(1,0,1,0)
            clickArea.BackgroundTransparency = 1
            clickArea.Text = ""
            clickArea.Parent = row
            clickArea.MouseButton1Click:Connect(function() setState(not state) end)

            return { Set = function(v) setState(v) end }
        end

        function secObj:Slider(label, min, max, default, cb)
            order = order + 1
            local val = default or min

            local wrap = Instance.new("Frame")
            wrap.Size = UDim2.new(1,0,0,42)
            wrap.BackgroundColor3 = C.btn
            wrap.BorderSizePixel = 0
            wrap.LayoutOrder = order
            wrap.Parent = inner
            mkCorner(wrap, 6)

            local lbl2 = mkLabel(wrap, label.." ["..val.."]", UDim2.new(1,-8,0,16), C.text, false)
            lbl2.Position = UDim2.new(0,8,0,4)

            local track = Instance.new("Frame")
            track.Size = UDim2.new(1,-16,0,6)
            track.Position = UDim2.new(0,8,0,26)
            track.BackgroundColor3 = C.div
            track.BorderSizePixel = 0
            track.Parent = wrap
            mkCorner(track, 3)

            local fill = Instance.new("Frame")
            fill.Size = UDim2.new((val-min)/(max-min),0,1,0)
            fill.BackgroundColor3 = C.slider
            fill.BorderSizePixel = 0
            fill.Parent = track
            mkCorner(fill, 3)

            local function setVal(v)
                v = math.clamp(math.floor(v), min, max)
                val = v
                fill.Size = UDim2.new((val-min)/(max-min), 0, 1, 0)
                lbl2.Text = label.." ["..val.."]"
                pcall(cb, val)
            end

            local dragging = false
            local clickBtn = Instance.new("TextButton")
            clickBtn.Size = UDim2.new(1,0,1,0)
            clickBtn.BackgroundTransparency = 1
            clickBtn.Text = ""
            clickBtn.Parent = track

            local function calcFromInput(input)
                local trackPos = track.AbsolutePosition.X
                local trackW   = track.AbsoluteSize.X
                local rel = math.clamp((input.Position.X - trackPos) / trackW, 0, 1)
                setVal(min + rel * (max - min))
            end

            local activeInput = nil

            local function isSliderInput(input)
                return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
            end

            clickBtn.InputBegan:Connect(function(input)
                if not isSliderInput(input) then return end
                dragging = true
                activeInput = input
                calcFromInput(input)
            end)

            UserInputService.InputChanged:Connect(function(input)
                if not dragging then return end
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    calcFromInput(input)
                end
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                if activeInput and input ~= activeInput and input.UserInputType ~= activeInput.UserInputType then return end
                dragging = false
                activeInput = nil
            end)

            return { Set = function(v) setVal(v) end }
        end

        function secObj:Divider(label)
            order = order + 1
            local row2 = Instance.new("Frame")
            row2.Size = UDim2.new(1,0,0,18)
            row2.BackgroundTransparency = 1
            row2.LayoutOrder = order
            row2.Parent = inner

            local line = Instance.new("Frame")
            line.Size = UDim2.new(0.3,0,0,1)
            line.Position = UDim2.new(0,0,0.5,0)
            line.BackgroundColor3 = C.div
            line.BorderSizePixel = 0
            line.Parent = row2

            local line2 = Instance.new("Frame")
            line2.Size = UDim2.new(0.3,0,0,1)
            line2.Position = UDim2.new(0.7,0,0.5,0)
            line2.BackgroundColor3 = C.div
            line2.BorderSizePixel = 0
            line2.Parent = row2

            local dlbl = mkLabel(row2, label, UDim2.new(0.4,0,1,0), C.sub, false, Enum.TextXAlignment.Center)
            dlbl.Position = UDim2.new(0.3,0,0,0)
            dlbl.TextSize = 10
        end

        return secObj
    end

    return tabObj
end

function RefLib:Toast(icon, title, msg, color)
    table.insert(toastQueue, {icon=icon, title=title, msg=msg, color=color})
    showNextToast()
end

function RefLib:CfgRegister(key, getter, setter)
    self._cfg[key] = {get=getter, set=setter}
end

function RefLib:BuildConfigTab(tab, key)
    local sec = tab:Section("config (memória)")
    sec:Button("salvar config", function()
        for k, c in pairs(self._cfg) do
            cfgStore[k] = c.get()
        end
        self:Toast("", "Config", "salvo ("..tostring((function() local n=0; for _ in pairs(self._cfg) do n=n+1 end; return n end)()).." chaves)", Color3.fromRGB(80,200,120))
    end)
    sec:Button("carregar config", function()
        for k, v in pairs(cfgStore) do
            if self._cfg[k] then pcall(self._cfg[k].set, v) end
        end
        self:Toast("", "Config", "carregado", Color3.fromRGB(80,180,220))
    end)
    sec:Button("resetar config", function()
        cfgStore = {}
        self:Toast("", "Config", "resetado", Color3.fromRGB(220,100,80))
    end)
end


if not RefLib then error("[mm2] ERRO: RefLib nao carregou.") end

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local VirtualUser       = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local cam    = workspace.CurrentCamera

local ui = RefLib.new("mm v20 v16 v13", "rbxassetid://131165537896572", "ref_mmv20")


local GetCoinEvent
local function refreshCoinRemote()
    if GetCoinEvent and GetCoinEvent.Parent then return GetCoinEvent end
    local names = {
        GetCoin = true,
        CollectCoin = true,
        CoinCollected = true,
        PickupCoin = true,
        ClaimCoin = true,
    }
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if names[d.Name] and (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) then
            GetCoinEvent = d
            return d
        end
    end
end
task.defer(refreshCoinRemote)

local PlayerDataChangedBind
pcall(function()
    PlayerDataChangedBind = ReplicatedStorage
        :WaitForChild("Modules", 5)
        :WaitForChild("CurrentRoundClient", 5)
        :WaitForChild("PlayerDataChanged", 5)
end)

local RoleSelectEvent
pcall(function() RoleSelectEvent = ReplicatedStorage.Remotes.Gameplay.RoleSelect end)


local KNIFE_NAMES   = { Knife = true }
local GUN_NAMES     = { Gun = true, ["Sheriff's Gun"] = true, Revolver = true, SheriffGun = true, GunDrop = true }
local GUNDROP_NAMES = { GunDrop = true }

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


local function getGunTool()
    local containers = {}
    if player.Character then table.insert(containers, player.Character) end
    local bp = player:FindFirstChild("Backpack")
    if bp then table.insert(containers, bp) end
    local wanted = {}
    for name in pairs(GUN_NAMES) do wanted[string.lower(name)] = true end
    local function hasShoot(obj)
        local direct = obj:FindFirstChild("Shoot")
        if direct and direct:IsA("RemoteEvent") then return true end
        for _, d in ipairs(obj:GetDescendants()) do
            if d.Name == "Shoot" and d:IsA("RemoteEvent") then return true end
        end
        return false
    end
    for _, container in ipairs(containers) do
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Tool") and wanted[string.lower(obj.Name)] and hasShoot(obj) then
                return obj
            end
        end
    end
    for _, container in ipairs(containers) do
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Tool") and string.find(string.lower(obj.Name), "gun") and hasShoot(obj) then
                return obj
            end
        end
    end
    for _, container in ipairs(containers) do
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Tool") and wanted[string.lower(obj.Name)] then return obj end
        end
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


local silentAimOn = false
local SA_PRED = 0.17
local SA_SIM_TIMER = 0.05
local SA_INTERVAL = 0.03
local SA_PRIORITIZE_PING = true
local SA_PREDICT_JUMP = true
local SA_PREDICT_LAG = true
local SA_SHARP_SHOOTER = true
local SA_VERTICAL_MULT = 1.45
local SA_HORIZONTAL_MULT = 1.45
local SA_OFFSET_X = 0
local SA_OFFSET_Y = -4
local SA_OFFSET_Z = 0
local _prevPos = {}
local _prevTime = {}
local _predCache = {}

local function getAimPart(tp)
    local chr = tp and tp.Character
    if not chr then return nil end
    if SA_SHARP_SHOOTER then
        return chr:FindFirstChild("Head") or chr:FindFirstChild("UpperTorso") or chr:FindFirstChild("Torso") or chr:FindFirstChild("HumanoidRootPart")
    end
    return chr:FindFirstChild("UpperTorso") or chr:FindFirstChild("Torso") or chr:FindFirstChild("HumanoidRootPart") or chr:FindFirstChild("Head")
end

local function getPingSeconds()
    local stats = game:GetService("Stats")
    local network = stats and stats:FindFirstChild("Network")
    local serverStats = network and network:FindFirstChild("ServerStatsItem")
    local ping = serverStats and serverStats:FindFirstChild("Data Ping")
    if not ping or ping.ClassName ~= "StatsItem" then return 0 end
    local ok, val = pcall(function()
        return ping:GetValue()
    end)
    if ok and type(val) == "number" then
        return math.clamp(val / 1000, 0, 0.35)
    end
    local okText, txt = pcall(function()
        return ping:GetValueString()
    end)
    if okText and type(txt) == "string" then
        local n = tonumber(txt:match("[%d%.]+"))
        if n then return math.clamp(n / 1000, 0, 0.35) end
    end
    return 0
end

local function getPredictionTime()
    local t = tonumber(SA_PRED) or 0
    if SA_PREDICT_LAG then t = t + (tonumber(SA_SIM_TIMER) or 0) end
    if SA_PRIORITIZE_PING then t = t + getPingSeconds() end
    return math.clamp(t, 0, 0.75)
end

local function getPredictedPos(tp)
    local part = getAimPart(tp)
    if not part then return nil end
    local now = tick()
    local cached = _predCache[tp]
    if cached and (now - cached.t) < math.max(0.005, SA_INTERVAL) then
        return cached.pos
    end
    local cur = part.Position
    local vel = Vector3.zero
    pcall(function() vel = part.AssemblyLinearVelocity end)
    if typeof(vel) ~= "Vector3" then vel = Vector3.zero end
    local prev = _prevPos[tp]
    local pt = _prevTime[tp]
    if vel.Magnitude < 0.05 and prev and pt then
        local dt = now - pt
        if dt > 0.001 and dt < 0.5 then
            vel = (cur - prev) / dt
        end
    end
    _prevPos[tp] = cur
    _prevTime[tp] = now
    local horizontal = Vector3.new(vel.X, 0, vel.Z) * (tonumber(SA_HORIZONTAL_MULT) or 1)
    local vertical = Vector3.new(0, vel.Y, 0) * (tonumber(SA_VERTICAL_MULT) or 1)
    if not SA_PREDICT_JUMP and vertical.Y > 0 then
        vertical = Vector3.zero
    end
    local pred = cur + (horizontal + vertical) * getPredictionTime() + Vector3.new(SA_OFFSET_X, SA_OFFSET_Y, SA_OFFSET_Z)
    _predCache[tp] = {t = now, pos = pred}
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

RunService.RenderStepped:Connect(function()
    if not silentAimOn then return end
    local target = getSilentTarget(); if not target then return end
    getPredictedPos(target)
end)

local _shootCd = false

local function safeLookAt(origin, target)
    if not origin or not target then return nil end
    if (target - origin).Magnitude < 0.05 then target = origin + cam.CFrame.LookVector end
    return CFrame.lookAt(origin, target)
end

local function getShootRemote(gunTool)
    if not gunTool then return nil end
    local r = gunTool:FindFirstChild("Shoot")
    if r and r:IsA("RemoteEvent") then return r end
    for _, d in ipairs(gunTool:GetDescendants()) do
        if d.Name == "Shoot" and d:IsA("RemoteEvent") then return d end
    end
end

local function getShotOrigin(gunTool)
    local h = gunTool and gunTool:FindFirstChild("Handle")
    if h and h:IsA("BasePart") then return h.Position end
    local hrp = myHRP()
    if hrp then return hrp.Position + Vector3.new(0, 1.5, 0) end
    return cam.CFrame.Position
end

local _manualSilentOverridePos = nil
local _manualSilentOverrideUntil = 0
local _lastSilentShotAt = 0

local fireGunAtPosition
fireGunAtPosition = function(hitPos)
    return fireShootRemoteAtPosition and fireShootRemoteAtPosition(hitPos) or false
end

local function fireWithSilentAim()
    local target = getSilentTarget(); if not target then return false end
    local hitPos = getPredictedPos(target); if not hitPos then return false end
    return fireGunAtPosition(hitPos)
end


local dumpActive   = false
local dumpCallback = nil

local _silentFireGuard = false

local function getRewriteHitPosition()
    if _manualSilentOverridePos and tick() <= _manualSilentOverrideUntil then
        return _manualSilentOverridePos
    end
    local target = getSilentTarget()
    if not target then return nil end
    return getPredictedPos(target)
end

local function buildSilentShootArgs(args, hitPos)
    if type(args) ~= "table" then return nil end
    if not hitPos or hitPos ~= hitPos then return nil end
    if #args >= 2 and typeof(args[1]) == "CFrame" and typeof(args[2]) == "CFrame" then
        local out = {}
        for i, v in ipairs(args) do out[i] = v end
        out[2] = CFrame.new(hitPos)
        return out
    end
    if #args >= 2 and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
        local out = {}
        for i, v in ipairs(args) do out[i] = v end
        out[2] = hitPos
        return out
    end
    return nil
end

local function getReadyGun()
    local gunTool = getGunTool()
    if not gunTool then return nil end
    local chr = player.Character
    if not chr then return nil end
    if not chr:FindFirstChild(gunTool.Name) then
        equipTool(gunTool)
        task.wait(0.06)
        chr = player.Character
        if not chr then return nil end
        gunTool = getGunTool()
    end
    return gunTool
end

local function fireDirectShootAtPosition(hitPos)
    local gunTool = getReadyGun()
    if not gunTool then return false end
    local shootRemote = getShootRemote(gunTool)
    if not shootRemote or not shootRemote:IsA("RemoteEvent") then return false end
    local origin = getShotOrigin(gunTool)
    local shotCF = safeLookAt(origin, hitPos)
    if not shotCF then return false end
    _silentFireGuard = true
    local ok = pcall(function()
        shootRemote:FireServer(shotCF, CFrame.new(hitPos))
    end)
    _silentFireGuard = false
    return ok
end

local function fireShootRemoteAtPosition(hitPos)
    if _shootCd then return false end
    if not hitPos or hitPos ~= hitPos then return false end
    local gunTool = getReadyGun()
    if not gunTool then return false end
    _shootCd = true
    _manualSilentOverridePos = hitPos
    _manualSilentOverrideUntil = tick() + 0.55
    _lastSilentShotAt = 0
    local activated = pcall(function()
        gunTool:Activate()
    end)
    task.delay(0.14, function()
        if tick() <= _manualSilentOverrideUntil and tick() - _lastSilentShotAt > 0.13 then
            fireDirectShootAtPosition(hitPos)
        end
    end)
    task.delay(0.62, function()
        _shootCd = false
        if tick() > _manualSilentOverrideUntil then
            _manualSilentOverridePos = nil
        end
    end)
    return activated
end

fireGunAtPosition = fireShootRemoteAtPosition

local function installShootHook()
    if shared and shared.__MMV20_V17_SHOOTH0OK then return end
    if shared then shared.__MMV20_V17_SHOOTH0OK = true end
    local mt = getrawmetatable and getrawmetatable(game)
    if not mt then return end
    local oldNamecall = mt.__namecall
    if not oldNamecall then return end
    pcall(setreadonly, mt, false)
    mt.__namecall = newcclosure and newcclosure(function(self, ...)
        local method = getnamecallmethod and getnamecallmethod()
        if method == "FireServer" then
            local args = {...}
            local gunTool = getGunTool()
            local shootRemote = gunTool and getShootRemote(gunTool)
            local isGunShoot = shootRemote and typeof(self) == "Instance" and self == shootRemote
            if isGunShoot then
                _lastSilentShotAt = tick()
                if dumpActive then
                    dumpActive = false
                    local desc = {}
                    for i, v in ipairs(args) do
                        local t = typeof(v)
                        local rep = t == "CFrame" and string.format("CFrame(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
                            or t == "Vector3" and string.format("Vector3(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
                            or t == "Instance" and ("Instance:"..v.ClassName.."["..v.Name.."]")
                            or tostring(v)
                        table.insert(desc, string.format("[%d] (%s) = %s", i, t, rep))
                    end
                    if dumpCallback then task.spawn(dumpCallback, desc); dumpCallback = nil end
                end
                if silentAimOn and not _silentFireGuard then
                    local hitPos = getRewriteHitPosition()
                    local newArgs = buildSilentShootArgs(args, hitPos)
                    if newArgs then
                        _manualSilentOverridePos = nil
                        return oldNamecall(self, table.unpack(newArgs))
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end) or oldNamecall
    pcall(setreadonly, mt, true)
end
task.defer(installShootHook)

local function getKnifeHandle(knifeTool)
    if not knifeTool then return nil end
    local h = knifeTool:FindFirstChild("Handle")
    if h and h:IsA("BasePart") then return h end
    for _, d in ipairs(knifeTool:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
end

local knifeReachCache = {}

local function restoreKnifeReach()
    for part, d in pairs(knifeReachCache) do
        if d.visual and d.visual.Parent then
            pcall(function() d.visual:Destroy() end)
        end
        if part and part.Parent then
            pcall(function()
                part.Size = d.size
                part.Transparency = d.transparency
                part.LocalTransparencyModifier = d.ltm
                part.CanTouch = d.canTouch
                part.CanCollide = d.canCollide
                part.CanQuery = d.canQuery
                part.Massless = d.massless
                part.Material = d.material
                part.CastShadow = d.castShadow
            end)
        end
    end
    knifeReachCache = {}
end

local function applyKnifeReach(knife, size)
    local h = getKnifeHandle(knife)
    if not h then return nil end
    if not knifeReachCache[h] then
        knifeReachCache[h] = {
            size = h.Size,
            transparency = h.Transparency,
            ltm = h.LocalTransparencyModifier,
            canTouch = h.CanTouch,
            canCollide = h.CanCollide,
            canQuery = h.CanQuery,
            massless = h.Massless,
            material = h.Material,
            castShadow = h.CastShadow,
            visual = nil,
        }
    end
    local d = knifeReachCache[h]
    if not d.visual or not d.visual.Parent then
        local ok, visual = pcall(function()
            local clone = h:Clone()
            clone.Name = "KnifeVisible"
            clone.Size = d.size
            clone.CFrame = h.CFrame
            clone.Transparency = d.transparency
            clone.LocalTransparencyModifier = d.ltm
            clone.CanCollide = false
            clone.CanTouch = false
            clone.CanQuery = false
            clone.Massless = true
            clone.Anchored = false
            for _, obj in ipairs(clone:GetDescendants()) do
                if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("WeldConstraint") or obj:IsA("JointInstance") or obj:IsA("Constraint") then
                    obj:Destroy()
                elseif obj:IsA("BasePart") then
                    obj.CanCollide = false
                    obj.CanTouch = false
                    obj.CanQuery = false
                    obj.Massless = true
                end
            end
            clone.Parent = h.Parent
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = h
            weld.Part1 = clone
            weld.Parent = clone
            return clone
        end)
        if ok then d.visual = visual end
    end
    local n = math.max(3, tonumber(size) or 12)
    pcall(function()
        h.Size = Vector3.new(n, n, n)
        h.Transparency = 1
        h.LocalTransparencyModifier = 1
        h.CanTouch = true
        h.CanCollide = false
        h.CanQuery = false
        h.Massless = true
        h.Material = Enum.Material.SmoothPlastic
        h.CastShadow = false
    end)
    if d.visual and d.visual.Parent then
        pcall(function()
            d.visual.Size = d.size
            d.visual.Transparency = d.transparency
            d.visual.LocalTransparencyModifier = d.ltm
            d.visual.CanCollide = false
            d.visual.CanTouch = false
            d.visual.CanQuery = false
            d.visual.Massless = true
        end)
    end
    return h
end

local function ensureKnifeEquipped()
    local knife = getKnifeTool()
    local chr = player.Character
    if knife and chr and chr:FindFirstChild(knife.Name) then return knife end
    if knife then equipTool(knife); task.wait(0.04); return getKnifeTool() end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for name in pairs(KNIFE_NAMES) do
            local t = bp:FindFirstChild(name)
            if t then equipTool(t); task.wait(0.04); return getKnifeTool() end
        end
    end
end

local function getKnifeTouchParts(targetChar)
    local list = {}
    local used = {}
    local priority = {"HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso", "Head"}
    for _, name in ipairs(priority) do
        local part = targetChar and targetChar:FindFirstChild(name)
        if part and part:IsA("BasePart") and not used[part] then
            used[part] = true
            table.insert(list, part)
        end
    end
    if targetChar then
        for _, part in ipairs(targetChar:GetDescendants()) do
            if part:IsA("BasePart") and not used[part] then
                if not part.Parent:IsA("Accessory") and not part.Parent:IsA("Tool") then
                    used[part] = true
                    table.insert(list, part)
                    if #list >= 10 then break end
                end
            end
        end
    end
    return list
end

local function pulseKnifeTouch(knife, targetChar, pulses)
    local h = getKnifeHandle(knife)
    if not h or not targetChar then return false end
    local parts = getKnifeTouchParts(targetChar)
    if #parts == 0 then return false end
    local ok = false
    local n = math.clamp(tonumber(pulses) or 2, 1, 6)
    for _ = 1, n do
        for _, part in ipairs(parts) do
            if part and part.Parent then
                if firetouchinterest then
                    local good = pcall(function()
                        firetouchinterest(h, part, 0)
                        task.wait()
                        firetouchinterest(h, part, 1)
                    end)
                    ok = ok or good
                else
                    ok = true
                end
            end
        end
        task.wait(0.025)
    end
    return ok
end

local function swingKnifeOnce(knife, targetChar, reachSize, pulses)
    if not knife then return false end
    local ok = false
    pcall(function()
        knife:Activate()
        ok = true
    end)
    return ok
end

local function knifeAt(targetChar, blinkAssist, reachSize, pulses)
    if not targetChar then return false end
    local hrp  = myHRP(); if not hrp then return false end
    local tHRP = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("UpperTorso") or targetChar:FindFirstChild("Torso") or targetChar:FindFirstChild("Head")
    if not tHRP then return false end
    local knife = ensureKnifeEquipped()
    if not knife then return false end
    local oldCF = hrp.CFrame
    local moved = false
    local dist = (hrp.Position - tHRP.Position).Magnitude
    if blinkAssist and dist > 5.5 then
        local dir = hrp.Position - tHRP.Position
        if dir.Magnitude < 0.1 then dir = -tHRP.CFrame.LookVector else dir = dir.Unit end
        hrp.CFrame = CFrame.lookAt(tHRP.Position + dir * 3.15, tHRP.Position)
        moved = true
        task.wait(0.045)
    end
    local ok = swingKnifeOnce(knife, targetChar, reachSize or 12, pulses or 2)
    if moved then
        task.wait(0.055)
        local cur = myHRP()
        if cur then cur.CFrame = oldCF end
    end
    return ok
end

local knifeRangeOn = false
local knifeRange = 18

local hitboxOn      = false
local hitboxSize    = 18
local hitboxVisible = false
local hitboxStrong  = false
local hitboxCache   = {}

local _myPartsCache      = nil
local _myPartsCacheTime  = -1
local function getMyParts()
    if _myPartsCache and (tick() - _myPartsCacheTime) < 0.15 then return _myPartsCache end
    local chr = player.Character
    if not chr then _myPartsCache = {}; _myPartsCacheTime = tick(); return {} end
    local parts = {}
    for _, p in ipairs(chr:GetDescendants()) do
        if p:IsA("BasePart") then table.insert(parts, p) end
    end
    _myPartsCache = parts
    _myPartsCacheTime = tick()
    return parts
end
player.CharacterAdded:Connect(function() _myPartsCache = nil end)

local function hitboxEnabled()
    return hitboxOn or knifeRangeOn
end

local function activeHitboxSize()
    local n = 0
    if hitboxOn then n = math.max(n, tonumber(hitboxSize) or 0) end
    if knifeRangeOn then n = math.max(n, tonumber(knifeRange) or 0) end
    return math.clamp(n, 4, 80)
end

local function isHitboxCandidate(part)
    if not part or not part:IsA("BasePart") then return false end
    if part.Parent and (part.Parent:IsA("Accessory") or part.Parent:IsA("Tool")) then return false end
    if part.Name == "HumanoidRootPart" then return true end
    if not hitboxStrong or not hitboxVisible then return false end
    return part.Name == "UpperTorso"
        or part.Name == "LowerTorso"
        or part.Name == "Torso"
        or part.Name == "Head"
end

local function setHitboxVisual(saved, visible)
    for _, d in ipairs(saved) do
        local part = d.part
        if part and part.Parent then
            pcall(function()
                if visible then
                    part.Transparency = 0.55
                    part.LocalTransparencyModifier = 0
                    part.Material = Enum.Material.ForceField
                else
                    if part.Name == "HumanoidRootPart" then
                        part.Transparency = 1
                        part.LocalTransparencyModifier = 1
                    else
                        part.Transparency = d.transparency
                        part.LocalTransparencyModifier = d.ltm
                    end
                    part.Material = d.material
                end
            end)
        end
    end
end

local function applyHitboxToChar(p)
    if not p or p == player then return end
    local chr = p.Character
    if not chr then return end
    if hitboxCache[p] then return end
    local size = activeHitboxSize()
    local myParts = getMyParts()
    local saved = {}
    for _, part in ipairs(chr:GetDescendants()) do
        if not isHitboxCandidate(part) then continue end
        local os = part.Size
        local targetSize
        if part.Name == "HumanoidRootPart" then
            targetSize = Vector3.new(size, size, size)
        else
            local maxD = math.max(os.X, os.Y, os.Z, 0.1)
            local sc = math.max(1, size / maxD)
            targetSize = os * sc
        end
        local cons = {}
        for _, mp in ipairs(myParts) do
            pcall(function()
                local nc = Instance.new("NoCollisionConstraint")
                nc.Part0 = part
                nc.Part1 = mp
                nc.Parent = part
                table.insert(cons, nc)
            end)
        end
        local d = {
            part = part,
            size = os,
            transparency = part.Transparency,
            ltm = part.LocalTransparencyModifier,
            material = part.Material,
            canTouch = part.CanTouch,
            canCollide = part.CanCollide,
            canQuery = part.CanQuery,
            massless = part.Massless,
            constraints = cons,
        }
        pcall(function()
            part.Size = targetSize
            part.CanTouch = true
            part.CanCollide = false
            part.CanQuery = true
            part.Massless = true
        end)
        table.insert(saved, d)
    end
    hitboxCache[p] = saved
    setHitboxVisual(saved, hitboxVisible)
end

local function restoreHitbox(p)
    local saved = hitboxCache[p]
    if not saved then return end
    for _, d in ipairs(saved) do
        if d.part and d.part.Parent then
            pcall(function()
                d.part.Size = d.size
                d.part.Transparency = d.transparency
                d.part.LocalTransparencyModifier = d.ltm
                d.part.Material = d.material
                d.part.CanTouch = d.canTouch
                d.part.CanCollide = d.canCollide
                d.part.CanQuery = d.canQuery
                d.part.Massless = d.massless
            end)
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

local function rebuildHitboxes()
    restoreAllHitboxes()
    if not hitboxEnabled() then return end
    for _, p in ipairs(Players:GetPlayers()) do applyHitboxToChar(p) end
end

local function applyHBVis(v)
    hitboxVisible = v
    for _, saved in pairs(hitboxCache) do
        setHitboxVisual(saved, v)
    end
end

player.CharacterAdded:Connect(function()
    _myPartsCache = nil
    if not hitboxEnabled() then return end
    task.wait(1)
    rebuildHitboxes()
end)
Players.PlayerRemoving:Connect(function(p) restoreHitbox(p) end)
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        restoreHitbox(p)
        if hitboxEnabled() then task.wait(1); applyHitboxToChar(p) end
    end)
end)
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= player then
        p.CharacterAdded:Connect(function()
            restoreHitbox(p)
            if hitboxEnabled() then task.wait(1); applyHitboxToChar(p) end
        end)
    end
end

local _knifeReachConn = nil
local function refreshKnifeReachLoop()
    if _knifeReachConn then return end
    _knifeReachConn = RunService.Heartbeat:Connect(function()
        if not knifeRangeOn then return end
        local knife = getKnifeTool()
        if knife then applyKnifeReach(knife, knifeRange) end
    end)
end
refreshKnifeReachLoop()

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
        l.Thickness = 2; l.Visible = false; l.Transparency = 1
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
    dl.Font=Enum.Font.Gotham; dl.TextSize=10; dl.TextColor3=Color3.fromRGB(210,210,230)
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
    p.CharacterAdded:Connect(function() freePlayer(p); task.wait(1.5); allocForPlayer(p) end)
end)
Players.PlayerRemoving:Connect(freePlayer)
for _, p in ipairs(Players:GetPlayers()) do if p ~= player then p.CharacterAdded:Connect(function()
    freePlayer(p); task.wait(1.5); allocForPlayer(p)
end) end end

RunService.RenderStepped:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        local d = espData[p]
        if not espOn then if d then hidePlayer(p) end; continue end
        local chr = p.Character
        local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
        if not chr or not hrp or not isAlive(p) then if d then hidePlayer(p) end; continue end
        local dist = (cam.CFrame.Position - hrp.Position).Magnitude
        if dist > espMax then if d then hidePlayer(p) end; continue end
        if not d then continue end
        if d.bb then d.bb.Enabled = true end
        local col = getESPColor(p)
        if d.nm then d.nm.TextColor3=col; d.nm.Text=p.DisplayName end
        if d.dl then d.dl.Text=math.floor(dist).."m  ["..(isRoundActive() and ROLE_LABEL[getRole(p)] or "Lobby").."]" end
        local function getPart(name)
            if d.isR15 then return chr:FindFirstChild(name) end
            return chr:FindFirstChild(R6_NAME[name] or name)
        end
        for i, conn in ipairs(d.conns) do
            local line = d.lines[i]; if not line then continue end
            local jA = getPart(conn[1]); local jB = getPart(conn[2])
            if jA and jB then
                local pA = cam:WorldToViewportPoint(jA.Position)
                local pB = cam:WorldToViewportPoint(jB.Position)
                line.Color=col; line.From=Vector2.new(pA.X,pA.Y); line.To=Vector2.new(pB.X,pB.Y)
                line.Visible=(pA.Z>0 or pB.Z>0)
            else line.Visible=false end
        end
    end
end)


local function findDroppedGuns()
    local found = {}
    for _, o in ipairs(workspace:GetDescendants()) do
        if GUNDROP_NAMES[o.Name] and o:IsA("BasePart") then
            table.insert(found, {tool=o, handle=o})
        end
    end
    return found
end

local function isCoinName(name)
    name = tostring(name or ""):lower()
    return name == "coin_server" or name == "coin" or name == "coinpart" or name == "maincoin" or name:find("coin") ~= nil
end

local function getCoinPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart and obj.PrimaryPart:IsA("BasePart") then return obj.PrimaryPart end
        local h = obj:FindFirstChild("Handle") or obj:FindFirstChild("Coin") or obj:FindFirstChild("Coin_Server") or obj:FindFirstChild("MainCoin")
        if h and h:IsA("BasePart") then return h end
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("BasePart") then return d end
        end
    end
end

local function findAllCoinServers()
    local coins = {}
    local seen = {}
    for _, o in ipairs(workspace:GetDescendants()) do
        if isCoinName(o.Name) then
            local part = getCoinPart(o)
            if part and part.Parent and not seen[part] and isValidPos(part.Position) then
                seen[part] = true
                table.insert(coins, part)
            end
        end
    end
    return coins
end


local FARM_FLY_SPEED   = 16
local farmPauseBetween = 0.8

local function flyTo(dest)
    local hrp = myHRP(); if not hrp then return end
    local chr = player.Character; if not chr then return end
    local collisionStates = {}
    for _, p in ipairs(chr:GetDescendants()) do
        if p:IsA("BasePart") then collisionStates[p]=p.CanCollide; pcall(function() p.CanCollide=false end) end
    end
    local s = hrp.Position; local dist = (dest-s).Magnitude
    if dist >= 0.5 then
        local steps = math.max(3,math.ceil(dist)); local st = 1/FARM_FLY_SPEED
        for i = 1, steps do
            hrp = myHRP(); if not hrp then break end
            hrp.CFrame = CFrame.new(s:Lerp(dest, i/steps)); task.wait(st)
        end
        hrp = myHRP(); if hrp then hrp.CFrame = CFrame.new(dest) end
    end
    chr = player.Character
    if chr then
        for _, p in ipairs(chr:GetDescendants()) do
            if p:IsA("BasePart") and collisionStates[p]~=nil then
                pcall(function() p.CanCollide=collisionStates[p] end)
            end
        end
    end
end

local function fireCoinRemote(c)
    local r = refreshCoinRemote()
    if not r then return false end
    local argSets = {
        {},
        {c},
        {c and c.Parent or nil},
        {c and c.Name or nil},
        {c and c.Position or nil},
        {c and c.CFrame or nil},
    }
    local ok = false
    for _, args in ipairs(argSets) do
        local good = pcall(function()
            if r:IsA("RemoteEvent") then
                r:FireServer(table.unpack(args))
            else
                r:InvokeServer(table.unpack(args))
            end
        end)
        ok = ok or good
        task.wait(0.03)
    end
    return ok
end

local function touchCoinPart(c)
    local hrp = myHRP()
    if not hrp or not c or not c.Parent then return false end
    local ok = false
    if firetouchinterest then
        ok = pcall(function()
            firetouchinterest(hrp, c, 0)
            task.wait()
            firetouchinterest(hrp, c, 1)
        end)
    end
    hrp.CFrame = CFrame.new(c.Position + Vector3.new(0, 0.2, 0))
    task.wait(0.08)
    return ok
end

local function collectCoin(c)
    if not c or not c.Parent then return end
    flyTo(c.Position + Vector3.new(0, 0.4, 0))
    touchCoinPart(c)
    fireCoinRemote(c)
    task.wait(farmPauseBetween)
end


local T = {
    panel = Color3.fromRGB(36, 26, 56),
    sub   = Color3.fromRGB(150, 130, 190),
    ok    = Color3.fromRGB(85, 205, 115),
    err   = Color3.fromRGB(208, 52, 72),
    warn  = Color3.fromRGB(195, 160, 38),
}


local tabMain   = ui:Tab("main")
local tabESP    = ui:Tab("esp")
local tabCombat = ui:Tab("combat")
local tabFarm   = ui:Tab("farm")
local tabCfg    = ui:Tab("config")

do

local secInfo = tabMain:Section("round info")

secInfo:Button("checar meu papel", function()
    local role = getRole(); local alive = 0
    for _, p in ipairs(Players:GetPlayers()) do if isAlive(p) then alive=alive+1 end end
    ui:Toast("", "["..ROLE_LABEL[role].."] "..player.DisplayName, "vivos: "..alive, ROLE_COLOR[role])
end)

secInfo:Button("scan todos os papeis", function()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local r = getRole(p); if r ~= "innocent" then table.insert(list, {p=p,r=r}) end
    end
    if #list == 0 then ui:Toast("","scan","nenhum killer/sheriff",ROLE_COLOR.unknown); return end
    for _, info in ipairs(list) do
        task.spawn(function()
            ui:Toast("","["..ROLE_LABEL[info.r].."] "..info.p.DisplayName, info.p.Name, ROLE_COLOR[info.r])
        end)
        task.wait(0.4)
    end
end)

secInfo:Divider("role esp (highlight)")
local roleEspOn = false; local roleEspCache = {}

local function removeRoleEsp(p)
    local d = roleEspCache[p]; if not d then return end
    pcall(function() if d.hl and d.hl.Parent then d.hl:Destroy() end end)
    pcall(function() if d.bb and d.bb.Parent then d.bb:Destroy() end end)
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
    roleEspCache[p] = {hl=hl,bb=bb,nm=nm,rl=rl}
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
    roleEspOn=v
    if not v then for p in pairs(roleEspCache) do removeRoleEsp(p) end end
end)
ui:CfgRegister("mm2_role_esp", function() return roleEspOn end, function(v) t_rEsp.Set(v) end)

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

end

do

local secESP = tabESP:Section("skeleton esp (wall)")
local t_esp = secESP:Toggle("skeleton esp (ve atras da parede)", false, function(v)
    espOn=v
    if not v then for p in pairs(espData) do hidePlayer(p) end end
end)
ui:CfgRegister("mm2_esp", function() return espOn end, function(v) t_esp.Set(v) end)
local s_dist = secESP:Slider("distancia max (studs)", 50, 1000, 300, function(v) espMax=v end)
ui:CfgRegister("mm2_esp_dist", function() return espMax end, function(v) s_dist.Set(v) end)

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
    if GUNDROP_NAMES[o.Name] and o:IsA("BasePart") then makeItemBB(o,o) end
end)
local t_item = secItemEsp:Toggle("gun dropped esp", false, function(v)
    itemEspOn=v; if v then scanItems() end
    for _, bb in pairs(itemBBs) do bb.Enabled=v end
end)
ui:CfgRegister("mm2_item_esp", function() return itemEspOn end, function(v) t_item.Set(v) end)
secItemEsp:Button("tp to gun", function()
    if not isAlive(player) then ui:Toast("","tp gun","voce esta morto",ROLE_COLOR.unknown); return end
    local hrp = myHRP(); if not hrp then return end
    local guns = findDroppedGuns(); local best,bestD=nil,math.huge
    for _, g in ipairs(guns) do
        local d=(hrp.Position-g.handle.Position).Magnitude; if d<bestD then best=g.handle; bestD=d end
    end
    if best then
        hrp.CFrame=CFrame.new(best.Position+Vector3.new(0,3,0))
        ui:Toast("","[Gun] tp","encontrada! "..math.floor(bestD).."m",ROLE_COLOR.sheriff)
    else ui:Toast("","tp gun","nenhuma gun dropada",ROLE_COLOR.unknown) end
end)

end

do

local secSheriff = tabCombat:Section("sheriff")

secSheriff:Divider("dump (debug)")
secSheriff:Button("DUMP gun (equipa e atira 1x)", function()
    local gunTool = getGunTool()
    if not gunTool then ui:Toast("","Dump","sem gun equipada",ROLE_COLOR.unknown); return end
    dumpActive=true
    dumpCallback=function(desc)
        local lines = {"=== FIRESERVER CAPTURADO ===","Gun: "..gunTool.Name,"Total args: "..#desc,""}
        for _, l in ipairs(desc) do table.insert(lines,l) end
        table.insert(lines,""); table.insert(lines,"Silent aim substitui arg[2] (alvo CFrame)")
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
        local closeBtn=Instance.new("TextButton"); closeBtn.Size=UDim2.new(0,32,0,32); closeBtn.Position=UDim2.new(1,-34,0,0)
        closeBtn.BackgroundTransparency=1; closeBtn.Text="✕"; closeBtn.TextColor3=Color3.fromRGB(180,80,80)
        closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=16; closeBtn.Parent=frame
        closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)
        local scroll=Instance.new("ScrollingFrame"); scroll.Size=UDim2.new(1,-16,1,-72); scroll.Position=UDim2.new(0,8,0,36)
        scroll.BackgroundColor3=Color3.fromRGB(12,12,18); scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4
        scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=frame
        Instance.new("UICorner",scroll).CornerRadius=UDim.new(0,6)
        local txt=Instance.new("TextLabel"); txt.Size=UDim2.new(1,-8,0,0); txt.AutomaticSize=Enum.AutomaticSize.Y
        txt.Position=UDim2.new(0,4,0,4); txt.BackgroundTransparency=1; txt.Text=table.concat(lines,"\n")
        txt.TextColor3=Color3.fromRGB(140,220,140); txt.Font=Enum.Font.Code; txt.TextSize=11
        txt.TextXAlignment=Enum.TextXAlignment.Left; txt.TextYAlignment=Enum.TextYAlignment.Top
        txt.TextWrapped=true; txt.Parent=scroll
        local copyBtn=Instance.new("TextButton"); copyBtn.Size=UDim2.new(1,-16,0,28); copyBtn.Position=UDim2.new(0,8,1,-36)
        copyBtn.BackgroundColor3=Color3.fromRGB(55,180,100); copyBtn.BorderSizePixel=0
        copyBtn.Text="COPIAR"; copyBtn.TextColor3=Color3.new(1,1,1); copyBtn.Font=Enum.Font.GothamBold; copyBtn.TextSize=12; copyBtn.Parent=frame
        Instance.new("UICorner",copyBtn).CornerRadius=UDim.new(0,6)
        copyBtn.MouseButton1Click:Connect(function()
            pcall(function() setclipboard(table.concat(lines,"\n")) end)
            copyBtn.Text="COPIADO!"; copyBtn.BackgroundColor3=Color3.fromRGB(40,130,70)
            task.delay(2, function() pcall(function() sg:Destroy() end) end)
        end)
    end
    task.delay(20, function() if dumpActive then dumpActive=false; dumpCallback=nil end end)
    ui:Toast("","[Dump]","atire 1x — capturando args",ROLE_COLOR.sheriff)
end)

secSheriff:Divider("silent aim")
local t_sa = secSheriff:Toggle("silent aim manual shot", false, function(v)
    silentAimOn=v
    ui:Toast("","[Silent Aim]", v and "manual shots redirected" or "disabled", v and ROLE_COLOR.sheriff or ROLE_COLOR.unknown)
end)
ui:CfgRegister("mm2_silentaim", function() return silentAimOn end, function(v) t_sa.Set(v) end)
local s_pred = secSheriff:Slider("prediction base (x0.01s)", 0, 60, 17, function(v) SA_PRED=v/100 end)
ui:CfgRegister("mm2_sa_pred", function() return SA_PRED*100 end, function(v) s_pred.Set(v) end)
local s_sim = secSheriff:Slider("prediction simulation timer (x0.01s)", 0, 80, 5, function(v) SA_SIM_TIMER=v/100 end)
ui:CfgRegister("mm2_sa_sim", function() return SA_SIM_TIMER*100 end, function(v) s_sim.Set(v) end)
local s_int = secSheriff:Slider("prediction interval (x0.01s)", 1, 20, 3, function(v) SA_INTERVAL=v/100 end)
ui:CfgRegister("mm2_sa_interval", function() return SA_INTERVAL*100 end, function(v) s_int.Set(v) end)
local t_ping = secSheriff:Toggle("prioritize ping", true, function(v) SA_PRIORITIZE_PING=v end)
ui:CfgRegister("mm2_sa_ping", function() return SA_PRIORITIZE_PING end, function(v) t_ping.Set(v) end)
local t_jump = secSheriff:Toggle("predict jump", true, function(v) SA_PREDICT_JUMP=v end)
ui:CfgRegister("mm2_sa_jump", function() return SA_PREDICT_JUMP end, function(v) t_jump.Set(v) end)
local t_lag = secSheriff:Toggle("predict lag", true, function(v) SA_PREDICT_LAG=v end)
ui:CfgRegister("mm2_sa_lag", function() return SA_PREDICT_LAG end, function(v) t_lag.Set(v) end)
local t_sharp = secSheriff:Toggle("sharp shooter", true, function(v) SA_SHARP_SHOOTER=v end)
ui:CfgRegister("mm2_sa_sharp", function() return SA_SHARP_SHOOTER end, function(v) t_sharp.Set(v) end)
local s_vmult = secSheriff:Slider("vertical multiplier (%)", 0, 300, 145, function(v) SA_VERTICAL_MULT=v/100 end)
ui:CfgRegister("mm2_sa_vmult", function() return SA_VERTICAL_MULT*100 end, function(v) s_vmult.Set(v) end)
local s_hmult = secSheriff:Slider("horizontal multiplier (%)", 0, 300, 145, function(v) SA_HORIZONTAL_MULT=v/100 end)
ui:CfgRegister("mm2_sa_hmult", function() return SA_HORIZONTAL_MULT*100 end, function(v) s_hmult.Set(v) end)
local s_offx = secSheriff:Slider("offset X", -30, 30, 0, function(v) SA_OFFSET_X=v end)
ui:CfgRegister("mm2_sa_offx", function() return SA_OFFSET_X end, function(v) s_offx.Set(v) end)
local s_offy = secSheriff:Slider("offset Y", -30, 30, -4, function(v) SA_OFFSET_Y=v end)
ui:CfgRegister("mm2_sa_offy", function() return SA_OFFSET_Y end, function(v) s_offy.Set(v) end)
local s_offz = secSheriff:Slider("offset Z", -30, 30, 0, function(v) SA_OFFSET_Z=v end)
ui:CfgRegister("mm2_sa_offz", function() return SA_OFFSET_Z end, function(v) s_offz.Set(v) end)

secSheriff:Divider("hitbox expander")
local t_hb = secSheriff:Toggle("hitbox expander", false, function(v)
    hitboxOn=v
    if v then
        rebuildHitboxes()
        ui:Toast("","[Hitbox]","invisivel — "..activeHitboxSize().." studs",ROLE_COLOR.sheriff)
    else
        if knifeRangeOn then rebuildHitboxes() else restoreAllHitboxes() end
        ui:Toast("","[Hitbox]","desativado",ROLE_COLOR.unknown)
    end
end)
ui:CfgRegister("mm2_hitbox", function() return hitboxOn end, function(v) t_hb.Set(v) end)
local s_hbsize = secSheriff:Slider("tamanho hitbox (studs)", 4, 60, 18, function(v) hitboxSize=v; rebuildHitboxes() end)
ui:CfgRegister("mm2_hitboxsize", function() return hitboxSize end, function(v) s_hbsize.Set(v) end)
local t_hbstrong = secSheriff:Toggle("full body hitbox", false, function(v) hitboxStrong=v; rebuildHitboxes() end)
ui:CfgRegister("mm2_hitboxstrong", function() return hitboxStrong end, function(v) t_hbstrong.Set(v) end)
local t_hbvis = secSheriff:Toggle("mostrar hitbox (debug)", false, function(v) hitboxVisible=v; applyHBVis(v) end)
ui:CfgRegister("mm2_hitboxvis", function() return hitboxVisible end, function(v) t_hbvis.Set(v) end)

secSheriff:Divider("shoot button (silent aim)")
local shootBtnGui=nil; local shootBtnOn=false
local function destroyShootBtn()
    if shootBtnGui and shootBtnGui.Parent then pcall(function() shootBtnGui:Destroy() end) end; shootBtnGui=nil
end
local function buildShootBtn()
    destroyShootBtn()
    local sg=Instance.new("ScreenGui"); sg.Name="MM2ShootBtn"; sg.ResetOnSpawn=false
    sg.IgnoreGuiInset=true; sg.DisplayOrder=99; sg.Parent=player.PlayerGui
    local card=Instance.new("Frame"); card.Size=UDim2.new(0,110,0,56); card.Position=UDim2.new(1,-120,1,-220)
    card.BackgroundColor3=T.panel; card.BackgroundTransparency=0.08; card.BorderSizePixel=0; card.Parent=sg
    Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
    local stroke=Instance.new("UIStroke"); stroke.Color=ROLE_COLOR.sheriff; stroke.Thickness=1.5
    stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stroke.Parent=card
    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,0,14); lbl.BackgroundTransparency=1
    lbl.Font=Enum.Font.Gotham; lbl.TextSize=9; lbl.TextColor3=T.sub
    lbl.TextXAlignment=Enum.TextXAlignment.Center; lbl.Text="SILENT AIM"; lbl.Position=UDim2.new(0,0,0,4); lbl.Parent=card
    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,-10,0,30); btn.Position=UDim2.new(0,5,0,20)
    btn.BackgroundColor3=ROLE_COLOR.sheriff; btn.BorderSizePixel=0; btn.Text="ATIRAR"
    btn.Font=Enum.Font.GothamBold; btn.TextSize=14; btn.TextColor3=Color3.new(1,1,1)
    btn.AutoButtonColor=true; btn.Parent=card
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6); shootBtnGui=sg
    local busy=false
    local function set(text,col) if btn.Parent then btn.Text=text; btn.BackgroundColor3=col end end
    btn.Activated:Connect(function()
        if busy then return end
        if not getGunTool() then set("SEM GUN",T.err); task.delay(1.2,function() set("ATIRAR",ROLE_COLOR.sheriff) end); return end
        local target=getSilentTarget()
        if not target then set("SEM ALVO",T.warn); task.delay(1.2,function() set("ATIRAR",ROLE_COLOR.sheriff) end); return end
        busy=true; set("...",Color3.fromRGB(80,80,80))
        local ok=fireWithSilentAim()
        task.wait(0.15); set(ok and "FIRED!" or "MISS", ok and T.ok or T.err)
        task.wait(0.8); set("ATIRAR",ROLE_COLOR.sheriff); busy=false
    end)
end
local t_btn=secSheriff:Toggle("shoot button (mobile safe)", false, function(v)
    shootBtnOn=v
    if v then buildShootBtn(); ui:Toast("","[Btn]","canto inf-direito",ROLE_COLOR.sheriff)
    else destroyShootBtn() end
end)
ui:CfgRegister("mm2_shootbtn", function() return shootBtnOn end, function(v) t_btn.Set(v) end)
player.CharacterAdded:Connect(function() if shootBtnOn then task.wait(1); buildShootBtn() end end)

secSheriff:Divider("gun aura")
local gunAuraOn=false; local lastGA=0; local gaCD=0.8; local gaDist=18
local function gunAuraLoop()
    while gunAuraOn do
        task.wait(0.1); if not gunAuraOn then break end
        if getRole()~="sheriff" and getRole()~="hero" then continue end
        if tick()-lastGA<gaCD then continue end
        local m=findByRole("murderer"); if not m then continue end
        local mChr=m.Character; if not mChr then continue end
        local mHRP=mChr:FindFirstChild("HumanoidRootPart"); if not mHRP then continue end
        local hrp=myHRP(); if not hrp then continue end
        if (hrp.Position-mHRP.Position).Magnitude>gaDist then
            hrp.CFrame=mHRP.CFrame*CFrame.new(0,0,-gaDist*0.6); task.wait(0.08)
            if not gunAuraOn then break end
            hrp=myHRP(); if not hrp then continue end
        end
        hrp.CFrame=CFrame.lookAt(hrp.Position,mHRP.Position); task.wait(0.04)
        if not gunAuraOn then break end
        lastGA=tick(); fireWithSilentAim()
    end
end
local t_ga=secSheriff:Toggle("gun aura (tp + silent aim + shoot)", false, function(v)
    gunAuraOn=v
    if v then task.spawn(gunAuraLoop); ui:Toast("","[Gun Aura]","ativo",ROLE_COLOR.sheriff)
    else ui:Toast("","[Gun Aura]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_gunaura", function() return gunAuraOn end, function(v) t_ga.Set(v) end)
local s_gacd=secSheriff:Slider("gun aura cooldown (x0.1s)", 2, 30, 8, function(v) gaCD=v/10 end)
ui:CfgRegister("mm2_gacd", function() return gaCD*10 end, function(v) s_gacd.Set(v) end)

secSheriff:Divider("auto shoot")
local autoShootOn=false; local lastShot=0; local shotCD=0.6
local function autoShootLoop()
    while autoShootOn do
        task.wait(0.15); if not autoShootOn then break end
        if getRole()~="sheriff" and getRole()~="hero" then continue end
        if tick()-lastShot<shotCD then continue end
        local m=findByRole("murderer"); if not m then continue end
        local mHrp=m.Character and m.Character:FindFirstChild("HumanoidRootPart")
        local hrp=myHRP()
        if not mHrp or not hrp then continue end
        if (hrp.Position-mHrp.Position).Magnitude>300 then continue end
        lastShot=tick(); fireWithSilentAim()
    end
end
local t_as=secSheriff:Toggle("auto shoot murderer", false, function(v)
    autoShootOn=v
    if v then task.spawn(autoShootLoop); ui:Toast("","[Auto Shoot]","ativo",ROLE_COLOR.sheriff)
    else ui:Toast("","[Auto Shoot]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_autoshoot", function() return autoShootOn end, function(v) t_as.Set(v) end)
local s_scd=secSheriff:Slider("cooldown (x0.1s)", 1, 20, 6, function(v) shotCD=v/10 end)
ui:CfgRegister("mm2_shot_cd", function() return shotCD*10 end, function(v) s_scd.Set(v) end)

secSheriff:Divider("manual")
secSheriff:Button("atirar no murderer (1x)", function()
    if getRole()~="sheriff" and getRole()~="hero" then
        ui:Toast("","[Shoot]","voce nao e xerife",ROLE_COLOR.unknown); return end
    local m=findByRole("murderer")
    if not m then ui:Toast("","[Shoot]","murderer nao detectado",ROLE_COLOR.unknown); return end
    local ok=fireWithSilentAim()
    ui:Toast("","[Shoot]",(ok and "disparado" or "falhou").." -> "..m.DisplayName,ROLE_COLOR.sheriff)
end)
secSheriff:Button("tp para murderer", function()
    local m=findByRole("murderer")
    if not m then ui:Toast("","tp","murderer nao detectado",ROLE_COLOR.unknown); return end
    local mh=m.Character and m.Character:FindFirstChild("HumanoidRootPart"); local hrp=myHRP()
    if mh and hrp then hrp.CFrame=mh.CFrame*CFrame.new(0,0,-4)
        ui:Toast("","[TP]","-> "..m.DisplayName,ROLE_COLOR.murderer) end
end)

local secMurd=tabCombat:Section("murderer")
secMurd:Divider("knife range")

local t_ka=secMurd:Toggle("knife range (enemy hitbox)", false, function(v)
    knifeRangeOn=v
    if v then
        restoreKnifeReach()
        local knife = getKnifeTool()
        if knife then applyKnifeReach(knife, knifeRange) end
        rebuildHitboxes()
        ui:Toast("","[Knife Range]","hitbox ativo, faca visivel",ROLE_COLOR.murderer)
    else
        if hitboxOn then rebuildHitboxes() else restoreAllHitboxes() end
        ui:Toast("","[Knife Range]","desativado",ROLE_COLOR.unknown)
    end
end)
ui:CfgRegister("mm2_knifeaura", function() return knifeRangeOn end, function(v) t_ka.Set(v) end)
local s_kr=secMurd:Slider("range knife hitbox", 4, 80, 18, function(v)
    knifeRange=v
    if knifeRangeOn then
        restoreKnifeReach()
        local knife = getKnifeTool()
        if knife then applyKnifeReach(knife, knifeRange) end
        rebuildHitboxes()
    end
end)
ui:CfgRegister("mm2_kniferange", function() return knifeRange end, function(v) s_kr.Set(v) end)
player.CharacterAdded:Connect(function()
    restoreKnifeReach()
    if hitboxEnabled() then task.wait(0.8); rebuildHitboxes() end
end)
secMurd:Button("tp para sheriff", function()
    local s=findByRole("sheriff"); if not s then ui:Toast("","tp","sheriff nao detectado",ROLE_COLOR.unknown); return end
    local sh=s.Character and s.Character:FindFirstChild("HumanoidRootPart"); local hrp=myHRP()
    if sh and hrp then hrp.CFrame=sh.CFrame*CFrame.new(0,0,-4)
        ui:Toast("","[TP]","-> "..s.DisplayName,ROLE_COLOR.sheriff) end
end)

local secCI=tabCombat:Section("info")
secCI:Button("quem e o murderer / sheriff", function()
    local m=findByRole("murderer"); local s=findByRole("sheriff"); local alive=0
    for _,p in ipairs(Players:GetPlayers()) do if isAlive(p) then alive=alive+1 end end
    ui:Toast("","M: "..(m and m.DisplayName or "?").."  |  S: "..(s and s.DisplayName or "?"),
        "vivos: "..alive, ROLE_COLOR.unknown)
end)

end

do

local secFarm=tabFarm:Section("coin farm")
local farmOn=false; local farmCount=0
local function collectCoinsLoop()
    farmCount=0; while farmOn do
        local hum=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        local hrp=myHRP()
        if not hrp or not hum or hum.Health<=0 then task.wait(2); continue end
        local coins=findAllCoinServers(); if #coins==0 then task.wait(3); continue end
        local myPos=hrp.Position
        table.sort(coins,function(a,b)
            if not(a and a.Parent) then return false end; if not(b and b.Parent) then return true end
            return (a.Position-myPos).Magnitude<(b.Position-myPos).Magnitude
        end)
        for _,c in ipairs(coins) do
            if not farmOn then break end; if not c or not c.Parent then continue end
            if not myHRP() then break end; collectCoin(c); farmCount=farmCount+1
        end; task.wait(2)
    end
end
local t_farm=secFarm:Toggle("auto farm coins", false, function(v)
    farmOn=v
    if v then task.spawn(collectCoinsLoop); ui:Toast("","[Farm] iniciado","vel: "..FARM_FLY_SPEED.."s/s",Color3.fromRGB(255,210,50))
    else ui:Toast("","[Farm] parado","coletadas: "..farmCount,Color3.fromRGB(255,210,50)) end
end)
ui:CfgRegister("mm2_farm", function() return farmOn end, function(v) t_farm.Set(v) end)
local s_fspd=secFarm:Slider("velocidade (studs/s)", 4, 40, 16, function(v) FARM_FLY_SPEED=v end)
ui:CfgRegister("mm2_farm_speed", function() return FARM_FLY_SPEED end, function(v) s_fspd.Set(v) end)
local s_fpause=secFarm:Slider("pausa entre coins (x0.1s)", 2, 30, 8, function(v) farmPauseBetween=v/10 end)
ui:CfgRegister("mm2_farm_pause", function() return farmPauseBetween*10 end, function(v) s_fpause.Set(v) end)
secFarm:Button("status do farm", function()
    local coins=findAllCoinServers()
    ui:Toast("",farmOn and "[Farm] rodando" or "[Farm] parado",
        "mapa: "..#coins.."  coletadas: "..farmCount, Color3.fromRGB(255,210,50))
end)
secFarm:Button("collect coins (1x)", function()
    if not myHRP() then return end
    local coins=findAllCoinServers(); if #coins==0 then
        ui:Toast("","coins","nenhuma coin encontrada",ROLE_COLOR.unknown); return end
    ui:Toast("","[Coins]","coletando "..#coins.."...",Color3.fromRGB(255,210,50))
    task.spawn(function()
        local hrp=myHRP(); local myPos=hrp and hrp.Position or Vector3.zero
        table.sort(coins,function(a,b)
            if not(a and a.Parent) then return false end; if not(b and b.Parent) then return true end
            return (a.Position-myPos).Magnitude<(b.Position-myPos).Magnitude
        end); local count=0
        for _,c in ipairs(coins) do if c and c.Parent then collectCoin(c); count=count+1 end end
        ui:Toast("","[Coins] feito!","coletadas: "..count,Color3.fromRGB(255,210,50))
    end)
end)

local secGrab=tabFarm:Section("gun grab (inocente)")
local grabOn=false
local function grabLoop()
    while grabOn do task.wait(0.6)
        if not grabOn then break end
        if not isRoundActive() then continue end
        if getRole()=="murderer" then continue end
        local hrp=myHRP(); if not hrp then continue end
        if getGunTool() then continue end
        local best,bestD=nil,math.huge
        for _,g in ipairs(findDroppedGuns()) do
            local d=(hrp.Position-g.handle.Position).Magnitude; if d<bestD then best=g.handle; bestD=d end
        end
        if best then
            hrp=myHRP(); if not hrp then continue end
            local s=hrp.CFrame; hrp.CFrame=CFrame.new(best.Position+Vector3.new(0,2.5,0)); task.wait(0.35)
            hrp=myHRP(); if not hrp then continue end; hrp.CFrame=s; task.wait(0.3)
        end
    end
end
local t_grab=secGrab:Toggle("auto pegar gun (vai e volta)", false, function(v)
    grabOn=v
    if v then task.spawn(grabLoop); ui:Toast("","[Gun Grab]","buscando GunDrop...",ROLE_COLOR.sheriff)
    else ui:Toast("","[Gun Grab]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_grab", function() return grabOn end, function(v) t_grab.Set(v) end)

local secSurv=tabFarm:Section("survival")
local survOn=false; local fleeDist=20
local function surviveLoop()
    while survOn do task.wait(0.2)
        if not survOn then break end
        if getRole()=="murderer" then continue end
        local m=findByRole("murderer"); if not m then continue end
        local mh=m.Character and m.Character:FindFirstChild("HumanoidRootPart"); local hrp=myHRP()
        if not mh or not hrp then continue end
        if (hrp.Position-mh.Position).Magnitude<fleeDist then
            local dir=(hrp.Position-mh.Position).Unit; local np=hrp.Position+dir*32
            if isValidPos(np) then hrp.CFrame=CFrame.new(np) end
        end
    end
end
local t_surv=secSurv:Toggle("auto fugir do murderer", false, function(v)
    survOn=v
    if v then task.spawn(surviveLoop); ui:Toast("","[Survive]","ativo",ROLE_COLOR.innocent)
    else ui:Toast("","[Survive]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_survive", function() return survOn end, function(v) t_surv.Set(v) end)
local s_fl=secSurv:Slider("range de fuga (studs)", 5, 60, 20, function(v) fleeDist=v end)
ui:CfgRegister("mm2_flee", function() return fleeDist end, function(v) s_fl.Set(v) end)

local secAfk=tabFarm:Section("anti-afk")
local afkOn=false; local afkConn=nil
local t_afk=secAfk:Toggle("anti-afk", false, function(v)
    afkOn=v; if afkConn then afkConn:Disconnect(); afkConn=nil end
    if v then
        afkConn=RunService.Heartbeat:Connect(function()
            pcall(function()
                VirtualUser:Button2Down(Vector2.zero,cam.CFrame)
                VirtualUser:Button2Up(Vector2.zero,cam.CFrame)
            end)
        end)
        ui:Toast("","[Anti-AFK]","ativo",Color3.fromRGB(200,200,255))
    else ui:Toast("","[Anti-AFK]","desativado",ROLE_COLOR.unknown) end
end)
ui:CfgRegister("mm2_afk", function() return afkOn end, function(v) t_afk.Set(v) end)

end

ui:BuildConfigTab(tabCfg, "ref_mm2v20")

task.delay(0.9, function()
    local role=getRole()
    ui:Toast("","mm2 v20  ["..ROLE_LABEL[role].."]",
        "bem-vindo, "..player.DisplayName, ROLE_COLOR[role])
end)
