local Players = game:GetService("Players")
local VoiceChatService = game:GetService("VoiceChatService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "RefVoiceCustom"
local BUTTON_SIZE = 56
local HOLD_RECONNECT_TIME = 0.7
local SPEAKING_THRESHOLD = 0.04

local active = false
local reconnecting = false
local destroyed = false
local speaking = false
local pressToken = 0
local conns = {}
local audioInput = nil
local audioAnalyzer = nil
local voiceReady = false

local stateDot
local label
local overlay
local buttonStroke
local tooltip
local tooltipStroke

local function safe(tag, fn)
	local ok, result = pcall(fn)
	if not ok then warn("[voice]", tag, result) return nil end
	return result
end

local function track(conn)
	table.insert(conns, conn)
	return conn
end

local function disconnectAll()
	for _, conn in ipairs(conns) do
		safe("disconnect", function() conn:Disconnect() end)
	end
	table.clear(conns)
end

local function tween(obj, props, t)
	if obj and obj.Parent then
		safe("tween", function()
			TweenService:Create(obj, TweenInfo.new(t or 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
		end)
	end
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, transparency, color)
	local s = Instance.new("UIStroke")
	s.Thickness = 1
	s.Transparency = transparency or 0.45
	s.Color = color or Color3.fromRGB(68, 68, 78)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function render()
	if not label or not stateDot then return end

	if reconnecting then
		label.Text = "recon..."
		stateDot.BackgroundColor3 = Color3.fromRGB(238, 186, 85)
		tooltip.Text = "reconectando microfone..."
		tween(overlay, { BackgroundTransparency = 0.30 }, 0.10)
		tween(buttonStroke, { Transparency = 0.25, Color = Color3.fromRGB(238, 186, 85) }, 0.10)
		return
	end

	if not voiceReady then
		label.Text = "no vc"
		stateDot.BackgroundColor3 = Color3.fromRGB(130, 130, 140)
		tooltip.Text = "voice indisponivel"
		tween(overlay, { BackgroundTransparency = 0.25 }, 0.12)
		tween(buttonStroke, { Transparency = 0.48, Color = Color3.fromRGB(80, 80, 90) }, 0.12)
		return
	end

	if not active then
		label.Text = "muted"
		stateDot.BackgroundColor3 = Color3.fromRGB(235, 82, 82)
		tooltip.Text = "click: ativar mic"
		tween(overlay, { BackgroundTransparency = 0.38 }, 0.12)
		tween(buttonStroke, { Transparency = 0.48, Color = Color3.fromRGB(68, 68, 78) }, 0.12)
	else
		if speaking then
			label.Text = "live"
			stateDot.BackgroundColor3 = Color3.fromRGB(72, 210, 116)
			tween(buttonStroke, { Transparency = 0.12, Color = Color3.fromRGB(72, 210, 116) }, 0.08)
			tween(overlay, { BackgroundTransparency = 0.80 }, 0.08)
		else
			label.Text = "on"
			stateDot.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
			tween(overlay, { BackgroundTransparency = 0.72 }, 0.12)
			tween(buttonStroke, { Transparency = 0.35, Color = Color3.fromRGB(100, 180, 255) }, 0.12)
		end
		tooltip.Text = "click: mutar mic"
	end
end

local function destroyInput()
	if audioAnalyzer then
		safe("destroy analyzer", function() audioAnalyzer:Destroy() end)
		audioAnalyzer = nil
	end
	if audioInput then
		safe("destroy input", function() audioInput:Destroy() end)
		audioInput = nil
	end
end

local speakLoop
local function stopSpeakLoop()
	if speakLoop then
		task.cancel(speakLoop)
		speakLoop = nil
	end
	speaking = false
end

local function startSpeakLoop(analyzer)
	stopSpeakLoop()
	speakLoop = task.spawn(function()
		while analyzer and analyzer.Parent and not destroyed do
			local level = safe("amplitude", function() return analyzer.loudnessSmoothed end) or 0
			local isSpeaking = level > SPEAKING_THRESHOLD
			if isSpeaking ~= speaking then
				speaking = isSpeaking
				render()
			end
			task.wait(0.05)
		end
	end)
end

local function createInput()
	destroyInput()

	local input = Instance.new("AudioDeviceInput")
	input.Name = "VoiceInput_Custom"
	input.Player = player
	input.Muted = false
	input.Parent = player

	local wire = Instance.new("Wire")
	wire.Name = "VoiceWire"

	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.Name = "VoiceAnalyzer"
	analyzer.Parent = player

	wire.SourceInstance = input
	wire.TargetInstance = analyzer
	wire.Parent = player

	audioInput = input
	audioAnalyzer = analyzer
	voiceReady = true

	track(input.AncestryChanged:Connect(function()
		if destroyed then return end
		if not input.Parent then
			stopSpeakLoop()
			audioInput = nil
			audioAnalyzer = nil
			voiceReady = false
			render()
		end
	end))

	startSpeakLoop(analyzer)
	return input
end

local function disconnectRobloxVoice()
	safe("leave voice", function()
		VoiceChatService:SetMuted(true)
	end)
end

local function setActive(state)
	active = state
	if active then
		disconnectRobloxVoice()
		if not audioInput or not audioInput.Parent then
			createInput()
		else
			audioInput.Muted = false
		end
	else
		stopSpeakLoop()
		if audioInput and audioInput.Parent then
			safe("mute input", function()
				audioInput.Muted = true
			end)
		end
		speaking = false
	end
	render()
end

local function softReconnect()
	if reconnecting then return false end
	reconnecting = true
	render()

	local wasActive = active

	stopSpeakLoop()
	destroyInput()
	task.wait(0.35)

	if wasActive then
		disconnectRobloxVoice()
		createInput()
	end

	active = wasActive
	reconnecting = false
	render()
	return true
end

local function initVoice()
	task.spawn(function()
		local hasVoice = safe("IsVoiceEnabledForUserIdAsync", function()
			return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
		end)

		if hasVoice then
			voiceReady = true
			active = false
		else
			voiceReady = false
		end

		render()
	end)
end

local old = playerGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "voice_root"
root.Size = UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE)
root.Position = UDim2.new(0, 18, 0.5, -BUTTON_SIZE / 2)
root.BackgroundTransparency = 1
root.Parent = gui

local shadow = Instance.new("Frame")
shadow.Size = UDim2.new(1, 6, 1, 6)
shadow.Position = UDim2.new(0, 2, 0, 5)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.84
shadow.BorderSizePixel = 0
shadow.ZIndex = 1
shadow.Parent = root
corner(shadow, 17)

local button = Instance.new("ImageButton")
button.Name = "voice_avatar_button"
button.Size = UDim2.new(1, 0, 1, 0)
button.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
button.BackgroundTransparency = 0.03
button.BorderSizePixel = 0
button.AutoButtonColor = false
button.ZIndex = 2
button.Parent = root
corner(button, 16)

buttonStroke = stroke(button, 0.48, Color3.fromRGB(68, 68, 78))

local avatarClip = Instance.new("Frame")
avatarClip.Size = UDim2.new(1, -10, 1, -10)
avatarClip.Position = UDim2.new(0, 5, 0, 5)
avatarClip.BackgroundTransparency = 1
avatarClip.BorderSizePixel = 0
avatarClip.ClipsDescendants = true
avatarClip.ZIndex = 3
avatarClip.Parent = button
corner(avatarClip, 13)

local avatar = Instance.new("ImageLabel")
avatar.Size = UDim2.new(1, 0, 1, 0)
avatar.BackgroundTransparency = 1
avatar.BorderSizePixel = 0
avatar.ScaleType = Enum.ScaleType.Crop
avatar.ZIndex = 3
avatar.Parent = avatarClip

task.spawn(function()
	local image = safe("thumbnail", function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if image and avatar.Parent then
		avatar.Image = image
	end
end)

overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.38
overlay.BorderSizePixel = 0
overlay.ZIndex = 4
overlay.Parent = button
corner(overlay, 16)

stateDot = Instance.new("Frame")
stateDot.AnchorPoint = Vector2.new(1, 1)
stateDot.Size = UDim2.new(0, 12, 0, 12)
stateDot.Position = UDim2.new(1, -6, 1, -6)
stateDot.BackgroundColor3 = Color3.fromRGB(235, 82, 82)
stateDot.BorderSizePixel = 0
stateDot.ZIndex = 8
stateDot.Parent = button
corner(stateDot, 999)
stroke(stateDot, 0.12, Color3.fromRGB(22, 22, 26))

label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Size = UDim2.new(1, -8, 0, 18)
label.Position = UDim2.new(0.5, 0, 0.5, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 11
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Text = "..."
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextTransparency = 0
label.ZIndex = 7
label.Parent = button

tooltip = Instance.new("TextLabel")
tooltip.Size = UDim2.new(0, 190, 0, 34)
tooltip.Position = UDim2.new(1, 10, 0.5, -17)
tooltip.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
tooltip.BackgroundTransparency = 1
tooltip.BorderSizePixel = 0
tooltip.Font = Enum.Font.GothamSemibold
tooltip.TextSize = 11
tooltip.TextColor3 = Color3.fromRGB(230, 230, 238)
tooltip.TextTransparency = 1
tooltip.Text = "click: mute/unmute | hold: reconectar"
tooltip.Visible = false
tooltip.ZIndex = 20
tooltip.Parent = root
corner(tooltip, 9)
tooltipStroke = stroke(tooltip, 1, Color3.fromRGB(68, 68, 78))

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = button

local function setTooltipVisible(state)
	if state then
		tooltip.Visible = true
		tween(tooltip, { BackgroundTransparency = 0.08, TextTransparency = 0 }, 0.12)
		tween(tooltipStroke, { Transparency = 0.56 }, 0.12)
	else
		tween(tooltip, { BackgroundTransparency = 1, TextTransparency = 1 }, 0.10)
		tween(tooltipStroke, { Transparency = 1 }, 0.10)
		task.delay(0.12, function()
			if tooltip and tooltip.Parent and tooltip.TextTransparency > 0.95 then
				tooltip.Visible = false
			end
		end)
	end
end

local function attemptReconnectWithRender()
	local ok = softReconnect()
	tooltip.Text = ok and "mic reconectado!" or "falha ao reconectar"
	setTooltipVisible(true)
	task.delay(1, function() setTooltipVisible(false) end)
end

track(button.MouseButton2Click:Connect(function()
	task.spawn(attemptReconnectWithRender)
end))

track(button.MouseButton1Click:Connect(function()
	if destroyed or reconnecting then return end
	setActive(not active)
	setTooltipVisible(true)
	task.delay(0.75, function() setTooltipVisible(false) end)
end))

track(button.MouseButton1Down:Connect(function()
	pressToken += 1
	local myToken = pressToken
	task.delay(HOLD_RECONNECT_TIME, function()
		if destroyed or reconnecting then return end
		if myToken ~= pressToken then return end
		task.spawn(function()
			tooltip.Text = "reconectando..."
			setTooltipVisible(true)
			attemptReconnectWithRender()
		end)
	end)
end))

track(button.MouseButton1Up:Connect(function()
	pressToken += 1
end))

local dragging = false
local pressed = false
local startInputPos
local startRootPos

track(root.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	pressed = true
	dragging = false
	startInputPos = input.Position
	startRootPos = root.Position
	local endConn
	endConn = input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			pressed = false
			dragging = false
			if endConn then endConn:Disconnect() end
		end
	end)
end))

track(root.InputChanged:Connect(function(input)
	if not pressed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local delta = input.Position - startInputPos
	if not dragging and delta.Magnitude < 9 then return end
	dragging = true
	local cam = workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local x = math.clamp(startRootPos.X.Offset + delta.X, 6, viewport.X - BUTTON_SIZE - 6)
	local y = math.clamp(startRootPos.Y.Offset + delta.Y, inset.Y + 6, viewport.Y - BUTTON_SIZE - 6)
	root.Position = UDim2.new(0, x, 0, y)
end))

track(gui.Destroying:Connect(function()
	destroyed = true
	stopSpeakLoop()
	destroyInput()
	disconnectAll()
end))

initVoice()

_G.RefVoiceCustom = {
	SetActive = setActive,
	SoftReconnect = softReconnect,
	IsReady = function() return voiceReady end,
	IsSpeaking = function() return speaking end,
	Diagnostics = function()
		return {
			voiceReady = voiceReady,
			active = active,
			speaking = speaking,
			hasInput = audioInput ~= nil,
			hasAnalyzer = audioAnalyzer ~= nil,
			inputParent = audioInput and tostring(audioInput.Parent) or "nil",
		}
	end,
	Destroy = function()
		if gui and gui.Parent then gui:Destroy() end
	end,
}
