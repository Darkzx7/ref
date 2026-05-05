local Players = game:GetService("Players")
local VoiceChatService = game:GetService("VoiceChatService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "RefVoiceCustomReconnectTest"
local BUTTON_SIZE = 56
local HOLD_RECONNECT_TIME = 0.7

local customVoiceActive = false
local muted = true
local reconnecting = false
local destroyed = false
local pressToken = 0
local conns = {}
local customAudioInput = nil

local stateDot
local label
local overlay
local buttonStroke
local tooltip
local tooltipStroke

local function safe(label_tag, fn)
	local ok, result = pcall(fn)
	if not ok then
		warn("[voice test]", label_tag, result)
		return nil
	end
	return result
end

local function track(conn)
	table.insert(conns, conn)
	return conn
end

local function disconnectAll()
	for _, conn in ipairs(conns) do
		safe("disconnect", function()
			conn:Disconnect()
		end)
	end
	table.clear(conns)
end

local function tween(obj, props, t)
	if obj and obj.Parent then
		safe("tween", function()
			TweenService:Create(
				obj,
				TweenInfo.new(t or 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				props
			):Play()
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

local function disconnectFromOriginalVoice()
	safe("DisableDefaultVoice", function()
		VoiceChatService.EnableDefaultVoice = false
	end)

	for _, obj in ipairs(game:GetDescendants()) do
		if obj:IsA("AudioDeviceInput") and obj.Player == player and obj ~= customAudioInput then
			safe("Destroy original input", function()
				obj.Parent = nil
				obj:Destroy()
			end)
		end
	end
end

local function reconnectToOriginalVoice()
	safe("EnableDefaultVoice", function()
		VoiceChatService.EnableDefaultVoice = true
	end)
end

local function createCustomAudioInput()
	if customAudioInput then
		safe("Destroy old input", function()
			customAudioInput:Destroy()
		end)
	end

	customAudioInput = Instance.new("AudioDeviceInput")
	customAudioInput.Name = "CustomVoiceInput"
	customAudioInput.Player = player
	customAudioInput.Muted = muted
	customAudioInput.Parent = player

	return customAudioInput
end

local function destroyCustomAudioInput()
	if customAudioInput then
		safe("Destroy custom input", function()
			customAudioInput:Destroy()
		end)
		customAudioInput = nil
	end
end

local function simulateVoiceDetection()
	task.spawn(function()
		while customVoiceActive and not destroyed and customAudioInput do
			if not muted and customAudioInput and customAudioInput.Parent then
				local fakeVolume = math.random() * 0.3
				local isFakeSpeaking = fakeVolume > 0.1

				if isFakeSpeaking then
					stateDot.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
					label.Text = "LIVE"
				else
					stateDot.BackgroundColor3 = Color3.fromRGB(72, 210, 116)
					label.Text = "CUSTOM"
				end
			end
			task.wait(0.15)
		end
	end)
end

local function canUseVoice()
	return safe("IsVoiceEnabledForUserIdAsync", function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end) == true
end

local function getVoiceServiceDiagnostics()
	return {
		voiceEnabled = canUseVoice(),
		enableDefaultVoice = tostring(VoiceChatService.EnableDefaultVoice),
		customMode = customVoiceActive,
		hasCustomInput = customAudioInput ~= nil,
	}
end

local function ownsInput(input)
	if not input or not input:IsA("AudioDeviceInput") then
		return false
	end
	local ok, owner = pcall(function()
		return input.Player
	end)
	return ok and owner == player
end

local function findLocalInputs()
	local found = {}
	for _, obj in ipairs(game:GetDescendants()) do
		if obj:IsA("AudioDeviceInput") and ownsInput(obj) then
			table.insert(found, obj)
		end
	end
	return found
end

local function getBestInput()
	if customVoiceActive and customAudioInput then
		return customAudioInput
	end
	local inputs = findLocalInputs()
	return inputs[1]
end

local function render()
	local voiceEnabled = canUseVoice()
	local input = getBestInput()

	if reconnecting then
		label.Text = "recon..."
		stateDot.BackgroundColor3 = Color3.fromRGB(238, 186, 85)
		tooltip.Text = "trying soft mic reconnect"
		tween(overlay, { BackgroundTransparency = 0.30 }, 0.10)
		tween(buttonStroke, { Transparency = 0.25, Color = Color3.fromRGB(238, 186, 85) }, 0.10)
		return
	end

	if not voiceEnabled and not customVoiceActive then
		label.Text = "no vc"
		stateDot.BackgroundColor3 = Color3.fromRGB(130, 130, 140)
		tooltip.Text = "voice unavailable"
		tween(overlay, { BackgroundTransparency = 0.25 }, 0.12)
		tween(buttonStroke, { Transparency = 0.48, Color = Color3.fromRGB(80, 80, 90) }, 0.12)
		return
	end

	if customVoiceActive then
		if not muted then
			label.Text = "CUSTOM"
			stateDot.BackgroundColor3 = Color3.fromRGB(72, 210, 116)
			tooltip.Text = "Modo Custom • falando"
		else
			label.Text = "MUTE"
			stateDot.BackgroundColor3 = Color3.fromRGB(235, 82, 82)
			tooltip.Text = "Modo Custom (mutado)"
		end
		tween(overlay, { BackgroundTransparency = muted and 0.55 or 0.72 }, 0.12)
		tween(buttonStroke, { Transparency = muted and 0.48 or 0.24 }, 0.12)
		return
	end

	if not input then
		label.Text = "no api"
		stateDot.BackgroundColor3 = Color3.fromRGB(238, 186, 85)
		tooltip.Text = "AudioDeviceInput not found"
		return
	end

	if muted then
		label.Text = "muted"
		stateDot.BackgroundColor3 = Color3.fromRGB(235, 82, 82)
		tooltip.Text = "click: unmute"
	else
		label.Text = "live"
		stateDot.BackgroundColor3 = Color3.fromRGB(72, 210, 116)
		tooltip.Text = "click: mute"
	end
	tween(overlay, { BackgroundTransparency = muted and 0.38 or 0.72 }, 0.12)
end

local function applyMuted(nextMuted)
	muted = nextMuted == true
	if customVoiceActive and customAudioInput then
		safe("set custom input muted", function()
			customAudioInput.Muted = muted
		end)
	else
		for _, input in ipairs(findLocalInputs()) do
			safe("set existing input muted", function()
				input.Muted = muted
			end)
		end
	end
	render()
end

local function toggleCustomVoice()
	customVoiceActive = not customVoiceActive

	if customVoiceActive then
		disconnectFromOriginalVoice()
		createCustomAudioInput()
		simulateVoiceDetection()
		muted = false
		if customAudioInput then
			customAudioInput.Muted = false
		end
	else
		destroyCustomAudioInput()
		reconnectToOriginalVoice()
		muted = true
	end

	render()
end

local function softReconnectMic()
	if reconnecting then return false end
	reconnecting = true
	render()

	local wasMuted = muted

	if customVoiceActive and customAudioInput then
		customAudioInput.Muted = true
		task.wait(0.22)
		destroyCustomAudioInput()
		task.wait(0.22)
		createCustomAudioInput()
		if customAudioInput then
			customAudioInput.Muted = wasMuted
		end
	else
		for _, input in ipairs(findLocalInputs()) do
			safe("soft reconnect", function()
				input.Muted = true
			end)
		end
		task.wait(0.3)
		applyMuted(wasMuted)
	end

	reconnecting = false
	render()
	return true
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
shadow.Name = "shadow"
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
avatarClip.Name = "avatar_clip"
avatarClip.Size = UDim2.new(1, -10, 1, -10)
avatarClip.Position = UDim2.new(0, 5, 0, 5)
avatarClip.BackgroundTransparency = 1
avatarClip.BorderSizePixel = 0
avatarClip.ClipsDescendants = true
avatarClip.ZIndex = 3
avatarClip.Parent = button
corner(avatarClip, 13)

local avatar = Instance.new("ImageLabel")
avatar.Name = "avatar"
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
overlay.Name = "overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.38
overlay.BorderSizePixel = 0
overlay.ZIndex = 4
overlay.Parent = button
corner(overlay, 16)

stateDot = Instance.new("Frame")
stateDot.Name = "state_dot"
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
label.Name = "state_label"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Size = UDim2.new(1, -8, 0, 18)
label.Position = UDim2.new(0.5, 0, 0.5, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 11
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Text = "muted"
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextTransparency = 0
label.ZIndex = 7
label.Parent = button

tooltip = Instance.new("TextLabel")
tooltip.Name = "tooltip"
tooltip.Size = UDim2.new(0, 190, 0, 34)
tooltip.Position = UDim2.new(1, 10, 0.5, -17)
tooltip.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
tooltip.BackgroundTransparency = 1
tooltip.BorderSizePixel = 0
tooltip.Font = Enum.Font.GothamSemibold
tooltip.TextSize = 11
tooltip.TextColor3 = Color3.fromRGB(230, 230, 238)
tooltip.TextTransparency = 1
tooltip.Text = "click: mute/unmute • hold: reconnect"
tooltip.Visible = false
tooltip.ZIndex = 20
tooltip.Parent = root
corner(tooltip, 9)
tooltipStroke = stroke(tooltip, 1, Color3.fromRGB(68, 68, 78))

local scale = Instance.new("UIScale")
scale.Scale = 1
scale.Parent = button

local function setTooltipVisible(state)
	if state then
		tooltip.Visible = true
		tween(tooltip, { BackgroundTransparency = 0.08, TextTransparency = 0 }, 0.12)
		tween(tooltipStroke, { Transparency = 0.56 }, 0.12)
	else
		tween(tooltip, { BackgroundTransparency = 1, TextTransparency = 1 }, 0.10)
		tween(tooltipStroke, { Transparency = 1 }, 0.10)
		task.delay(0.11, function()
			if tooltip and tooltip.Parent and tooltip.TextTransparency > 0.95 then
				tooltip.Visible = false
			end
		end)
	end
end

local function attemptReconnectWithRender()
	reconnecting = true
	render()
	setTooltipVisible(true)
	local ok = softReconnectMic()
	reconnecting = false
	render()
	tooltip.Text = ok and "mic refreshed" or "reconnect failed"
	setTooltipVisible(true)
	task.delay(0.85, function()
		setTooltipVisible(false)
	end)
end

track(button.MouseButton2Click:Connect(function()
	task.spawn(attemptReconnectWithRender)
end))

track(button.MouseButton1Click:Connect(function()
	if destroyed or reconnecting then return end
	applyMuted(not muted)
	setTooltipVisible(true)
	task.delay(0.75, function()
		setTooltipVisible(false)
	end)
end))

track(button.MouseButton1Down:Connect(function()
	pressToken += 1
	local myToken = pressToken
	task.delay(HOLD_RECONNECT_TIME, function()
		if destroyed or reconnecting then return end
		if myToken ~= pressToken then return end
		toggleCustomVoice()
		setTooltipVisible(true)
		task.delay(1, function()
			setTooltipVisible(false)
		end)
	end)
end))

track(button.MouseButton1Up:Connect(function()
	pressToken += 1
end))

local dragging = false
local pressed = false
local startInput
local startPos

track(root.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	pressed = true
	dragging = false
	startInput = input.Position
	startPos = root.Position
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
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local delta = input.Position - startInput
	if not dragging and delta.Magnitude < 9 then return end
	dragging = true
	local cam = workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local x = math.clamp(startPos.X.Offset + delta.X, 6, viewport.X - BUTTON_SIZE - 6)
	local y = math.clamp(startPos.Y.Offset + delta.Y, inset.Y + 6, viewport.Y - BUTTON_SIZE - 6)
	root.Position = UDim2.new(0, x, 0, y)
end))

track(gui.Destroying:Connect(function()
	destroyed = true
	if customVoiceActive then
		destroyCustomAudioInput()
		reconnectToOriginalVoice()
	end
	disconnectAll()
end))

applyMuted(true)
render()

_G.RefVoiceCustomReconnectTest = {
	SetMuted = applyMuted,
	ToggleCustom = toggleCustomVoice,
	IsCustomActive = function() return customVoiceActive end,
	SoftReconnect = softReconnectMic,
	Diagnostics = getVoiceServiceDiagnostics,
	Destroy = function()
		if gui and gui.Parent then gui:Destroy() end
	end,
}
