


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local REF_ICON = "rbxassetid://131165537896572"

local ASSET_IDS = {
    "138968134586114", "77746803697517", "11716737385", "85411947035535",
    "17486010733", "115937381575157", "5998624788", "29066471",
    "10878218322", "11720475097", "11717828334", "3750055370",
    "7919939616", "11767069621", "11763278624", "136736018133073",
    "5145098542", "94034888832081", "90182849006628", "87812001838953",
    "139297526487043", "103985905025181",
}

local FILE_NAME = "ref_crosshair_settings_v2.json"

local CONFIG = {
    selectedAsset = ASSET_IDS[1],
    size = 36,
    opacity = 1, -- 0 invisible, 1 fully visible
    showOnlyInShiftlock = true,
    hideDefaultMouseIcon = true,
    hideGameCrosshair = true,
    toggleKey = Enum.KeyCode.RightControl,
    color = Color3.fromRGB(255, 255, 255),
}

local Theme = {
    Bg = Color3.fromRGB(15, 15, 20),
    Bg2 = Color3.fromRGB(22, 22, 29),
    Bg3 = Color3.fromRGB(30, 30, 40),
    Bg4 = Color3.fromRGB(37, 36, 48),
    Stroke = Color3.fromRGB(255, 255, 255),
    Text = Color3.fromRGB(240, 240, 248),
    Sub = Color3.fromRGB(165, 165, 182),
    Accent = Color3.fromRGB(120, 80, 255),
    Bad = Color3.fromRGB(235, 85, 85),
}

local oldMouseIcon = mouse.Icon
local oldMouseEnabled = UserInputService.MouseIconEnabled
local imageCache = {}
local cards = {}

local function directAsset(id)
    return "rbxassetid://" .. tostring(id)
end

local function thumbAsset(id)
    return "rbxthumb://type=Asset&id=" .. tostring(id) .. "&w=420&h=420"
end

local function tween(obj, props, time, style)
    if not obj or not obj.Parent then return end

    local ok, tw = pcall(function()
        return TweenService:Create(
            obj,
            TweenInfo.new(time or 0.14, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            props
        )
    end)

    if ok and tw then
        tw:Play()
    end
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 10)
    c.Parent = parent
    return c
end

local function stroke(parent, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Stroke
    s.Transparency = transparency or 0.8
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    pcall(function() s.LineJoinMode = Enum.LineJoinMode.Round end)
    s.Parent = parent
    return s
end

local function resolveDecalTexture(id)
    id = tostring(id)
    if imageCache[id] then return imageCache[id] end

    local resolved = directAsset(id)
    local ok, body = pcall(function()
        return game:HttpGet("https://assetdelivery.roblox.com/v1/asset?id=" .. id, true)
    end)

    if ok and type(body) == "string" then
        local textureId = body:match("rbxassetid://(%d+)")
            or body:match("www%.roblox%.com/asset/%?id=(%d+)")
            or body:match("www%.roblox%.com/asset%?id=(%d+)")
            or body:match("id=(%d+)")
        if textureId then
            resolved = directAsset(textureId)
        end
    end

    imageCache[id] = resolved
    return resolved
end

local function setImageSmart(imageObject, id)
    if not imageObject then return end
    id = tostring(id)

    if imageCache[id] then
        imageObject.Image = imageCache[id]
        return
    end

    local direct = directAsset(id)
    local thumb = thumbAsset(id)
    imageObject.Image = direct

    task.spawn(function()
        pcall(function() ContentProvider:PreloadAsync({ imageObject }) end)
        task.wait(0.25)
        if not imageObject or not imageObject.Parent then return end
        if imageObject.IsLoaded then
            imageCache[id] = direct
            return
        end

        imageObject.Image = thumb
        pcall(function() ContentProvider:PreloadAsync({ imageObject }) end)
        task.wait(0.25)
        if not imageObject or not imageObject.Parent then return end
        if imageObject.IsLoaded then
            imageCache[id] = thumb
            return
        end

        imageObject.Image = resolveDecalTexture(id)
        pcall(function() ContentProvider:PreloadAsync({ imageObject }) end)
    end)
end

local function saveConfig()
    if not writefile then return end
    pcall(function()
        writefile(FILE_NAME, HttpService:JSONEncode({
            version = 2,
            selectedAsset = CONFIG.selectedAsset,
            size = CONFIG.size,
            opacity = CONFIG.opacity,
            showOnlyInShiftlock = CONFIG.showOnlyInShiftlock,
            hideDefaultMouseIcon = CONFIG.hideDefaultMouseIcon,
            hideGameCrosshair = CONFIG.hideGameCrosshair,
        }))
    end)
end

local function loadConfig()
    if not isfile or not readfile or not isfile(FILE_NAME) then return end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(FILE_NAME))
    end)
    if not ok or type(data) ~= "table" then return end

    if data.selectedAsset then
        for _, id in ipairs(ASSET_IDS) do
            if tostring(id) == tostring(data.selectedAsset) then
                CONFIG.selectedAsset = tostring(data.selectedAsset)
                break
            end
        end
    end
    if tonumber(data.size) then CONFIG.size = math.clamp(tonumber(data.size), 16, 90) end
    if tonumber(data.opacity) then
        local value = tonumber(data.opacity)
        CONFIG.opacity = data.version == 2 and math.clamp(value, 0, 1) or math.clamp(1 - value, 0, 1)
    end
    if type(data.hideGameCrosshair) == "boolean" then CONFIG.hideGameCrosshair = data.hideGameCrosshair end
    if type(data.showOnlyInShiftlock) == "boolean" then CONFIG.showOnlyInShiftlock = data.showOnlyInShiftlock end
    if type(data.hideDefaultMouseIcon) == "boolean" then CONFIG.hideDefaultMouseIcon = data.hideDefaultMouseIcon end
end

loadConfig()

local oldGui = playerGui:FindFirstChild("ref_crosshair_selector")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ref_crosshair_selector"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local crosshair = Instance.new("ImageLabel")
crosshair.Name = "crosshair"
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(CONFIG.size, CONFIG.size)
crosshair.BackgroundTransparency = 1
crosshair.ImageColor3 = CONFIG.color
crosshair.ImageTransparency = 1 - CONFIG.opacity
crosshair.ScaleType = Enum.ScaleType.Fit
crosshair.Visible = false
crosshair.Parent = gui
setImageSmart(crosshair, CONFIG.selectedAsset)

local panel = Instance.new("Frame")
panel.Name = "panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(374, 412)
panel.BackgroundColor3 = Theme.Bg
panel.BackgroundTransparency = 0.16
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 16)
stroke(panel, Theme.Stroke, 0.8, 1)

local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(23, 23, 31)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 13, 18)),
})
gradient.Parent = panel

local accent = Instance.new("Frame")
accent.AnchorPoint = Vector2.new(0.5, 0)
accent.Position = UDim2.new(0.5, 0, 0, -1)
accent.Size = UDim2.new(0.58, 0, 0, 2)
accent.BackgroundColor3 = Theme.Accent
accent.BackgroundTransparency = 0.24
accent.BorderSizePixel = 0
accent.Parent = panel
corner(accent, 999)

local header = Instance.new("Frame")
header.Name = "header"
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = Theme.Bg2
header.BackgroundTransparency = 0.1
header.BorderSizePixel = 0
header.Active = true
header.Parent = panel
corner(header, 16)

local headerFix = Instance.new("Frame")
headerFix.Position = UDim2.new(0, 0, 1, -20)
headerFix.Size = UDim2.new(1, 0, 0, 20)
headerFix.BackgroundColor3 = Theme.Bg2
headerFix.BackgroundTransparency = 0.1
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local devTitle = Instance.new("TextLabel")
devTitle.Name = "dev_title"
devTitle.BackgroundTransparency = 1
devTitle.Position = UDim2.fromOffset(14, 0)
devTitle.Size = UDim2.new(0, 120, 1, 0)
devTitle.Text = "c: deka dev"
devTitle.TextColor3 = Theme.Sub
devTitle.TextTransparency = 0.06
devTitle.TextSize = 12
devTitle.Font = Enum.Font.GothamSemibold
devTitle.TextXAlignment = Enum.TextXAlignment.Left
devTitle.Parent = header

local logo = Instance.new("ImageLabel")
logo.Name = "ref_icon"
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.5)
logo.Size = UDim2.fromOffset(28, 28)
logo.BackgroundTransparency = 1
logo.Image = REF_ICON
logo.ImageColor3 = Color3.fromRGB(255, 255, 255)
logo.ScaleType = Enum.ScaleType.Fit
logo.Parent = header

local minimize = Instance.new("TextButton")
minimize.AnchorPoint = Vector2.new(1, 0.5)
minimize.Position = UDim2.new(1, -48, 0.5, 0)
minimize.Size = UDim2.fromOffset(26, 24)
minimize.BackgroundColor3 = Theme.Bg3
minimize.BackgroundTransparency = 0.08
minimize.BorderSizePixel = 0
minimize.Text = "-"
minimize.TextColor3 = Theme.Sub
minimize.TextSize = 15
minimize.Font = Enum.Font.GothamBold
minimize.AutoButtonColor = false
minimize.Parent = header
corner(minimize, 8)
stroke(minimize, Theme.Stroke, 0.88, 1)

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0.5)
close.Position = UDim2.new(1, -14, 0.5, 0)
close.Size = UDim2.fromOffset(26, 24)
close.BackgroundColor3 = Theme.Bg3
close.BackgroundTransparency = 0.08
close.BorderSizePixel = 0
close.Text = "x"
close.TextColor3 = Theme.Sub
close.TextSize = 12
close.Font = Enum.Font.GothamBold
close.AutoButtonColor = false
close.Parent = header
corner(close, 8)
stroke(close, Theme.Stroke, 0.88, 1)

local miniButton = Instance.new("ImageButton")
miniButton.Name = "ref_open_button"
miniButton.AnchorPoint = Vector2.new(0, 0.5)
miniButton.Position = UDim2.new(0, 14, 0.5, 0)
miniButton.Size = UDim2.fromOffset(44, 44)
miniButton.BackgroundColor3 = Theme.Bg
miniButton.BackgroundTransparency = 0.06
miniButton.BorderSizePixel = 0
miniButton.Image = REF_ICON
miniButton.ImageColor3 = Color3.fromRGB(255, 255, 255)
miniButton.ScaleType = Enum.ScaleType.Fit
miniButton.Visible = false
miniButton.AutoButtonColor = false
miniButton.Parent = gui
corner(miniButton, 14)
local miniStroke = stroke(miniButton, Theme.Accent, 0.5, 1)

local previewBox = Instance.new("Frame")
previewBox.Position = UDim2.fromOffset(14, 66)
previewBox.Size = UDim2.new(1, -28, 0, 78)
previewBox.BackgroundColor3 = Theme.Bg2
previewBox.BackgroundTransparency = 0.12
previewBox.BorderSizePixel = 0
previewBox.Parent = panel
corner(previewBox, 14)
stroke(previewBox, Theme.Stroke, 0.88, 1)

local previewCircle = Instance.new("Frame")
previewCircle.Position = UDim2.fromOffset(13, 11)
previewCircle.Size = UDim2.fromOffset(56, 56)
previewCircle.BackgroundColor3 = Theme.Bg
previewCircle.BackgroundTransparency = 0.12
previewCircle.BorderSizePixel = 0
previewCircle.Parent = previewBox
corner(previewCircle, 999)
stroke(previewCircle, Theme.Stroke, 0.9, 1)

local previewImage = Instance.new("ImageLabel")
previewImage.AnchorPoint = Vector2.new(0.5, 0.5)
previewImage.Position = UDim2.fromScale(0.5, 0.5)
previewImage.Size = UDim2.fromOffset(38, 38)
previewImage.BackgroundTransparency = 1
previewImage.ImageColor3 = CONFIG.color
previewImage.ImageTransparency = 1 - CONFIG.opacity
previewImage.ScaleType = Enum.ScaleType.Fit
previewImage.Parent = previewCircle
setImageSmart(previewImage, CONFIG.selectedAsset)

local previewTitle = Instance.new("TextLabel")
previewTitle.BackgroundTransparency = 1
previewTitle.Position = UDim2.fromOffset(82, 14)
previewTitle.Size = UDim2.new(1, -96, 0, 20)
previewTitle.Text = "selected"
previewTitle.TextColor3 = Theme.Text
previewTitle.TextSize = 13
previewTitle.Font = Enum.Font.GothamBold
previewTitle.TextXAlignment = Enum.TextXAlignment.Left
previewTitle.Parent = previewBox

local previewId = Instance.new("TextLabel")
previewId.BackgroundTransparency = 1
previewId.Position = UDim2.fromOffset(82, 36)
previewId.Size = UDim2.new(1, -96, 0, 18)
previewId.Text = CONFIG.selectedAsset
previewId.TextColor3 = Theme.Sub
previewId.TextSize = 11
previewId.Font = Enum.Font.Gotham
previewId.TextXAlignment = Enum.TextXAlignment.Left
previewId.Parent = previewBox

local controls = Instance.new("Frame")
controls.Position = UDim2.fromOffset(14, 154)
controls.Size = UDim2.new(1, -28, 0, 90)
controls.BackgroundTransparency = 1
controls.Parent = panel

local controlLayout = Instance.new("UIListLayout")
controlLayout.Padding = UDim.new(0, 8)
controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
controlLayout.Parent = controls

local function refreshOpacity()
    local transparency = 1 - CONFIG.opacity
    crosshair.ImageTransparency = transparency
    previewImage.ImageTransparency = transparency

    for assetId, card in pairs(cards) do
        local selected = tostring(assetId) == tostring(CONFIG.selectedAsset)
        card.image.ImageTransparency = math.clamp(transparency + (selected and 0 or 0.12), 0, 1)
    end
end

local function createSlider(parent, labelText, min, max, default, step, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 41)
    holder.BackgroundTransparency = 1
    holder.Parent = parent

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -74, 0, 16)
    label.Text = labelText
    label.TextColor3 = Theme.Text
    label.TextSize = 11
    label.Font = Enum.Font.GothamSemibold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = holder

    local box = Instance.new("TextBox")
    box.AnchorPoint = Vector2.new(1, 0)
    box.Position = UDim2.new(1, 0, 0, -1)
    box.Size = UDim2.fromOffset(58, 20)
    box.BackgroundColor3 = Theme.Bg2
    box.BackgroundTransparency = 0.05
    box.BorderSizePixel = 0
    box.TextColor3 = Theme.Text
    box.PlaceholderColor3 = Theme.Sub
    box.TextSize = 10
    box.Font = Enum.Font.GothamSemibold
    box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Center
    box.Parent = holder
    corner(box, 7)
    stroke(box, Theme.Stroke, 0.88, 1)

    local bar = Instance.new("Frame")
    bar.Position = UDim2.fromOffset(0, 25)
    bar.Size = UDim2.new(1, -70, 0, 5)
    bar.BackgroundColor3 = Theme.Bg2
    bar.BackgroundTransparency = 0.05
    bar.BorderSizePixel = 0
    bar.Parent = holder
    corner(bar, 999)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bar
    corner(fill, 999)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(13, 13)
    knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
    knob.BorderSizePixel = 0
    knob.Parent = bar
    corner(knob, 999)
    stroke(knob, Theme.Accent, 0.35, 1)

    local dragging = false
    local current = default

    local function roundToStep(value)
        if not step or step <= 0 then return value end
        return math.floor((value / step) + 0.5) * step
    end

    local function setValue(value, instant, fromBox)
        value = tonumber(value) or current
        current = math.clamp(roundToStep(value), min, max)
        local alpha = (current - min) / (max - min)

        if max <= 1 then
            box.Text = tostring(math.floor(current * 100 + 0.5))
        else
            box.Text = tostring(math.floor(current + 0.5))
        end

        if instant then
            fill.Size = UDim2.new(alpha, 0, 1, 0)
            knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        else
            tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, 0.12)
            tween(knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, 0.12)
        end

        callback(current)
        if fromBox then saveConfig() end
    end

    local function fromInput(input)
        local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        setValue(min + (max - min) * alpha)
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromInput(input)
        end
    end)

    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then saveConfig() end
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            fromInput(input)
        end
    end)

    box.FocusLost:Connect(function()
        local value = tonumber(box.Text)
        if max <= 1 and value and value > 1 then value = value / 100 end
        setValue(value, false, true)
    end)

    setValue(default, true)
    return { Set = setValue, Get = function() return current end }
end

createSlider(controls, "size", 16, 90, CONFIG.size, 1, function(value)
    CONFIG.size = value
    crosshair.Size = UDim2.fromOffset(value, value)
    local previewSize = math.clamp(value, 24, 46)
    previewImage.Size = UDim2.fromOffset(previewSize, previewSize)
end)

createSlider(controls, "opacity", 0, 1, CONFIG.opacity, 0.01, function(value)
    CONFIG.opacity = value
    refreshOpacity()
end)

local gridLabel = Instance.new("TextLabel")
gridLabel.BackgroundTransparency = 1
gridLabel.Position = UDim2.fromOffset(14, 250)
gridLabel.Size = UDim2.new(1, -28, 0, 18)
gridLabel.Text = "previews"
gridLabel.TextColor3 = Theme.Text
gridLabel.TextSize = 11
gridLabel.Font = Enum.Font.GothamBold
gridLabel.TextXAlignment = Enum.TextXAlignment.Left
gridLabel.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "preview_grid"
scroll.Position = UDim2.fromOffset(14, 272)
scroll.Size = UDim2.new(1, -28, 1, -286)
scroll.BackgroundColor3 = Theme.Bg2
scroll.BackgroundTransparency = 0.22
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Theme.Accent
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.Parent = panel
corner(scroll, 13)
stroke(scroll, Theme.Stroke, 0.9, 1)

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(52, 52)
grid.CellPadding = UDim2.fromOffset(7, 7)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingTop = UDim.new(0, 9)
scrollPad.PaddingBottom = UDim.new(0, 9)
scrollPad.PaddingLeft = UDim.new(0, 9)
scrollPad.PaddingRight = UDim.new(0, 9)
scrollPad.Parent = scroll

local function applyCrosshair(id)
    CONFIG.selectedAsset = tostring(id)
    setImageSmart(crosshair, id)
    setImageSmart(previewImage, id)
    previewId.Text = tostring(id)
    saveConfig()

    for assetId, card in pairs(cards) do
        local selected = tostring(assetId) == tostring(id)
        tween(card.frame, { BackgroundColor3 = selected and Color3.fromRGB(32, 29, 47) or Theme.Bg3 }, 0.12)
        tween(card.stroke, {
            Color = selected and Theme.Accent or Theme.Stroke,
            Transparency = selected and 0.25 or 0.84,
        }, 0.12)
        tween(card.image, {
            ImageTransparency = math.clamp((1 - CONFIG.opacity) + (selected and 0 or 0.12), 0, 1),
            Size = selected and UDim2.fromOffset(38, 38) or UDim2.fromOffset(34, 34),
        }, 0.12)
    end
end

for index, id in ipairs(ASSET_IDS) do
    local button = Instance.new("TextButton")
    button.Name = "asset_" .. tostring(index)
    button.BackgroundColor3 = Theme.Bg3
    button.BackgroundTransparency = 0.05
    button.BorderSizePixel = 0
    button.Text = ""
    button.AutoButtonColor = false
    button.LayoutOrder = index
    button.Parent = scroll
    corner(button, 12)
    local buttonStroke = stroke(button, Theme.Stroke, 0.84, 1)

    local img = Instance.new("ImageLabel")
    img.AnchorPoint = Vector2.new(0.5, 0.5)
    img.Position = UDim2.fromScale(0.5, 0.5)
    img.Size = UDim2.fromOffset(34, 34)
    img.BackgroundTransparency = 1
    img.ImageColor3 = CONFIG.color
    img.ImageTransparency = math.clamp((1 - CONFIG.opacity) + 0.12, 0, 1)
    img.ScaleType = Enum.ScaleType.Fit
    img.Parent = button
    setImageSmart(img, id)

    button.MouseEnter:Connect(function()
        tween(button, { BackgroundColor3 = Theme.Bg4 }, 0.12)
        tween(buttonStroke, { Transparency = 0.62 }, 0.12)
        tween(img, { Size = UDim2.fromOffset(38, 38) }, 0.12)
    end)

    button.MouseLeave:Connect(function()
        applyCrosshair(CONFIG.selectedAsset)
    end)

    button.MouseButton1Click:Connect(function()
        applyCrosshair(id)
    end)

    cards[id] = { frame = button, stroke = buttonStroke, image = img }
end

grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scroll.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 18)
end)

local function makeDraggable(dragObject, target)
    local dragging = false
    local dragStart
    local startPosition
    local moved = false

    dragObject.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        moved = false
        dragStart = input.Position
        startPosition = target.Position

        local changed
        changed = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                if changed then changed:Disconnect() end
            end
        end)
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 2 or math.abs(delta.Y) > 2 then moved = true end
        target.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end)

    return function()
        return moved
    end
end

makeDraggable(header, panel)
local miniMoved = makeDraggable(miniButton, miniButton)

local function setMinimized(state)
    panel.Visible = not state
    miniButton.Visible = state
end

minimize.MouseEnter:Connect(function()
    tween(minimize, { BackgroundColor3 = Theme.Bg4, TextColor3 = Theme.Text }, 0.12)
end)
minimize.MouseLeave:Connect(function()
    tween(minimize, { BackgroundColor3 = Theme.Bg3, TextColor3 = Theme.Sub }, 0.12)
end)
close.MouseEnter:Connect(function()
    tween(close, { BackgroundColor3 = Color3.fromRGB(42, 24, 28), TextColor3 = Theme.Bad }, 0.12)
end)
close.MouseLeave:Connect(function()
    tween(close, { BackgroundColor3 = Theme.Bg3, TextColor3 = Theme.Sub }, 0.12)
end)
miniButton.MouseEnter:Connect(function()
    tween(miniButton, { BackgroundColor3 = Theme.Bg3 }, 0.12)
    tween(miniStroke, { Transparency = 0.28 }, 0.12)
end)
miniButton.MouseLeave:Connect(function()
    tween(miniButton, { BackgroundColor3 = Theme.Bg }, 0.12)
    tween(miniStroke, { Transparency = 0.5 }, 0.12)
end)

minimize.MouseButton1Click:Connect(function() setMinimized(true) end)
miniButton.MouseButton1Click:Connect(function()
    if miniMoved and miniMoved() then return end
    setMinimized(false)
end)
close.MouseButton1Click:Connect(function() panel.Visible = false end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == CONFIG.toggleKey then
        panel.Visible = not panel.Visible
        miniButton.Visible = false
    end
end)

local function hideGameTopbarCrosshair()
    if not CONFIG.hideGameCrosshair then return end
    local gameTopbar = playerGui:FindFirstChild("GameTopbar")
    local defaultCrosshair = gameTopbar and gameTopbar:FindFirstChild("Crosshair")
    if not defaultCrosshair then return end

    pcall(function() defaultCrosshair.Visible = false end)
    pcall(function() defaultCrosshair.ImageTransparency = 1 end)

    for _, obj in ipairs(defaultCrosshair:GetDescendants()) do
        if obj:IsA("GuiObject") then pcall(function() obj.Visible = false end) end
        if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
            pcall(function() obj.ImageTransparency = 1 end)
        end
    end
end

RunService.RenderStepped:Connect(function()
    local inShiftlock = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
    local shouldShow = CONFIG.showOnlyInShiftlock and inShiftlock or not CONFIG.showOnlyInShiftlock

    crosshair.Visible = shouldShow
    hideGameTopbarCrosshair()
    refreshOpacity()

    if CONFIG.hideDefaultMouseIcon then
        if shouldShow then
            UserInputService.MouseIconEnabled = false
            mouse.Icon = ""
        else
            UserInputService.MouseIconEnabled = oldMouseEnabled
            mouse.Icon = oldMouseIcon
        end
    end
end)

player.CharacterAdded:Connect(function()
    task.wait(0.5)
    gui.Parent = playerGui
end)

applyCrosshair(CONFIG.selectedAsset)
refreshOpacity()
