-- voice_custom_button_reconnect_test.client.lua
-- Teste separado para StarterPlayerScripts ou StarterGui.
-- Usa apenas APIs scriptáveis quando disponíveis.
-- Clique: mute/unmute.
-- Segurar por ~0.7s ou botão direito: tenta "soft reconnect" do mic local via AudioDeviceInput.
-- Observação: desconectar/reconectar do servidor de Voice Chat não é exposto oficialmente para LocalScript.

local Players = game:GetService("Players")
local VoiceChatService = game:GetService("VoiceChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "RefVoiceCustomReconnectTest"
local BUTTON_SIZE = 56
local START_MUTED = true
local HOLD_RECONNECT_TIME = 0.7

local muted = START_MUTED
local reconnecting = false
local destroyed = false
local pressToken = 0
local conns = {}

local function safe(label, fn)
	local ok, result = pcall(fn)
	if not ok then
		warn("[voice test]", label, result)
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

local function canUseVoice()
	return safe("IsVoiceEnabledForUserIdAsync", function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end) == true
end

local function getVoiceServiceDiagnostics()
	local data = {
		voiceEnabled = canUseVoice(),
		useAudioApi = "unknown",
		enableDefaultVoice = "unknown",
	}

	safe("read UseAudioApi", function()
		data.useAudioApi = tostring(VoiceChatService.UseAudioApi)
	end)

	safe("read EnableDefaultVoice", function()
		data.enableDefaultVoice = tostring(VoiceChatService.EnableDefaultVoice)
	end)

	return data
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
	local inputs = findLocalInputs()
	return inputs[1]
end

local function createFallbackInput()
	local parent = player:FindFirstChildOfClass("PlayerScripts") or playerGui

	return safe("create fallback AudioDeviceInput", function()
		local input = Instance.new("AudioDeviceInput")
		input.Name = "RefVoiceFallbackInput"
		input.Player = player
		input.Muted = true
		input.Parent = parent
		return input
	end)
end

local function ensureInput()
	return getBestInput() or createFallbackInput()
end

local function applyMuted(nextMuted)
	muted = nextMuted == true

	for _, input in ipairs(findLocalInputs()) do
		safe("set existing input muted", function()
			input.Muted = muted
		end)
	end

	local input = ensureInput()
	if input then
		safe("set ensured input muted", function()
			input.Muted = muted
		end)
	end

	return input ~= nil
end

local function softReconnectMic()
	if reconnecting then return false end
	reconnecting = true

	local wasMuted = muted

	-- Step 1: force mute all known local inputs.
	for _, input in ipairs(findLocalInputs()) do
		safe("soft reconnect mute", function()
			input.Muted = true
		end)
	end

	task.wait(0.22)

	-- Step 2: re-find or create fallback input.
	local input = ensureInput()

	task.wait(0.22)

	-- Step 3: restore the wanted state.
	if input then
		applyMuted(wasMuted)
	else
		applyMuted(true)
	end

	reconnecting = false
	return input ~= nil
end

local old = playerGui:FindFirstChild(GUI_NAME)
if old then
	old:Destroy()
end

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

local buttonStroke = stroke(button, 0.48, Color3.fromRGB(68, 68, 78))

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

local overlay = Instance.new("Frame")
overlay.Name = "overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.38
overlay.BorderSizePixel = 0
overlay.ZIndex = 4
overlay.Parent = button
corner(overlay, 16)

local stateDot = Instance.new("Frame")
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

local label = Instance.new("TextLabel")
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

local tooltip = Instance.new("TextLabel")
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
local tooltipStroke = stroke(tooltip, 1, Color3.fromRGB(68, 68, 78))

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

	if not voiceEnabled then
		label.Text = "no vc"
		stateDot.BackgroundColor3 = Color3.fromRGB(130, 130, 140)
		tooltip.Text = "voice unavailable for this user/place"
		tween(overlay, { BackgroundTransparency = 0.25 }, 0.12)
		tween(buttonStroke, { Transparency = 0.48, Color = Color3.fromRGB(80, 80, 90) }, 0.12)
		return
	end

	if not input then
		label.Text = "no api"
		stateDot.BackgroundColor3 = Color3.fromRGB(238, 186, 85)
		tooltip.Text = "AudioDeviceInput not found yet"
		tween(overlay, { BackgroundTransparency = 0.28 }, 0.12)
		tween(buttonStroke, { Transparency = 0.36, Color = Color3.fromRGB(238, 186, 85) }, 0.12)
		return
	end

	if muted then
		label.Text = "muted"
		stateDot.BackgroundColor3 = Color3.fromRGB(235, 82, 82)
		tooltip.Text = "click: unmute • hold: reconnect"
		tween(overlay, { BackgroundTransparency = 0.38 }, 0.12)
		tween(buttonStroke, { Transparency = 0.48, Color = Color3.fromRGB(68, 68, 78) }, 0.12)
	else
		label.Text = "live"
		stateDot.BackgroundColor3 = Color3.fromRGB(72, 210, 116)
		tooltip.Text = "click: mute • hold: reconnect"
		tween(overlay, { BackgroundTransparency = 0.72 }, 0.12)
		tween(buttonStroke, { Transparency = 0.24, Color = Color3.fromRGB(72, 210, 116) }, 0.12)
	end
end

applyMuted(START_MUTED)
render()

track(button.MouseEnter:Connect(function()
	tween(scale, { Scale = 1.035 }, 0.12)
	setTooltipVisible(true)
end))

track(button.MouseLeave:Connect(function()
	tween(scale, { Scale = 1 }, 0.12)
	setTooltipVisible(false)
end))

local function attemptReconnectWithRender()
	reconnecting = true
	render()
	setTooltipVisible(true)

	local ok = softReconnectMic()

	reconnecting = false
	render()

	tooltip.Text = ok and "mic refreshed" or "reconnect unavailable"
	setTooltipVisible(true)

	task.delay(0.85, function()
		setTooltipVisible(false)
	end)
end

track(button.MouseButton2Click:Connect(function()
	task.spawn(attemptReconnectWithRender)
end))

track(button.MouseButton1Down:Connect(function()
	pressToken += 1
	local myToken = pressToken

	task.delay(HOLD_RECONNECT_TIME, function()
		if destroyed then return end
		if myToken ~= pressToken then return end
		task.spawn(attemptReconnectWithRender)
		pressToken += 1
	end)
end))

track(button.MouseButton1Up:Connect(function()
	local oldToken = pressToken
	pressToken += 1

	task.defer(function()
		if destroyed then return end
		if reconnecting then return end
		if pressToken ~= oldToken + 1 then return end

		if not canUseVoice() then
			render()
			setTooltipVisible(true)
			task.delay(1.1, function()
				setTooltipVisible(false)
			end)
			return
		end

		applyMuted(not muted)
		render()
		setTooltipVisible(true)
		task.delay(0.75, function()
			setTooltipVisible(false)
		end)
	end)
end))

-- Arrastar o botão.
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
			if endConn then
				endConn:Disconnect()
			end
		end
	end)
end))

track(root.InputChanged:Connect(function(input)
	if not pressed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local delta = input.Position - startInput
	if not dragging and delta.Magnitude < 9 then
		return
	end

	dragging = true

	local cam = workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()

	local x = math.clamp(startPos.X.Offset + delta.X, 6, viewport.X - BUTTON_SIZE - 6)
	local y = math.clamp(startPos.Y.Offset + delta.Y, inset.Y + 6, viewport.Y - BUTTON_SIZE - 6)

	root.Position = UDim2.new(0, x, 0, y)
end))

track(game.DescendantAdded:Connect(function(obj)
	if destroyed then return end
	if obj:IsA("AudioDeviceInput") then
		task.defer(function()
			if ownsInput(obj) then
				safe("sync new input", function()
					obj.Muted = muted
				end)
				render()
			end
		end)
	end
end))

-- Atualização leve para quando o Roblox criar/remover AudioDeviceInput depois.
task.spawn(function()
	while not destroyed and gui.Parent do
		render()
		task.wait(1.2)
	end
end)

track(gui.Destroying:Connect(function()
	destroyed = true
	applyMuted(true)
	disconnectAll()
end))

_G.RefVoiceCustomReconnectTest = {
	SetMuted = function(value)
		applyMuted(value == true)
		render()
	end,

	Toggle = function()
		applyMuted(not muted)
		render()
	end,

	SoftReconnect = function()
		return softReconnectMic()
	end,

	Diagnostics = function()
		local data = getVoiceServiceDiagnostics()
		data.localAudioInputs = #findLocalInputs()
		data.muted = muted
		return data
	end,

	Destroy = function()
		if gui and gui.Parent then
			gui:Destroy()
		end
	end,
}
