local G2L = {};

local cloneref = cloneref or function(x) return x end
local VoiceInternal = cloneref(game:GetService("VoiceChatInternal"))
local VoiceChatService = cloneref(game:GetService("VoiceChatService"))

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local IMAGE_ON  = [[rbxassetid://72678449388570]]
local IMAGE_OFF = [[rbxassetid://104208878511392]]
local toggleState = true 

local dragging = false
local dragStartPos = nil
local frameStartPos = nil

local first_time = false

local Group = VoiceInternal:GetGroupId()

-- AudioDeviceInput pra manter voice nativo desconectado
local audioInput = nil
local audioAnalyzer = nil

local function destroyInput()
    if audioAnalyzer then pcall(function() audioAnalyzer:Destroy() end) audioAnalyzer = nil end
    if audioInput then pcall(function() audioInput:Destroy() end) audioInput = nil end
end

local function createInput()
    destroyInput()
    local player = game:GetService("Players").LocalPlayer

    local input = Instance.new("AudioDeviceInput")
    input.Name = "VoiceInput_Bypass"
    input.Player = player
    input.Muted = false
    input.Parent = player

    local analyzer = Instance.new("AudioAnalyzer")
    analyzer.Name = "VoiceAnalyzer_Bypass"
    analyzer.Parent = player

    local wire = Instance.new("Wire")
    wire.SourceInstance = input
    wire.TargetInstance = analyzer
    wire.Parent = player

    audioInput = input
    audioAnalyzer = analyzer
end

local function disconnectRobloxVoice()
    pcall(function()
        VoiceChatService:SetMuted(true)
    end)
end

-- [UI igual ao original]
G2L["1"] = Instance.new("ScreenGui", game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"));
G2L["1"]["Name"] = [[RAHHHHH]];
G2L["1"]["ZIndexBehavior"] = Enum.ZIndexBehavior.Sibling;
G2L["2"] = Instance.new("Frame", G2L["1"]);
G2L["2"]["BorderSizePixel"] = 0;
G2L["2"]["BackgroundColor3"] = Color3.fromRGB(153, 8, 138);
G2L["2"]["Size"] = UDim2.new(0, 209, 0, 44);
G2L["2"]["Position"] = UDim2.new(0.09039, 0, 0.58434, 0);
G2L["2"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["3"] = Instance.new("UICorner", G2L["2"]);
G2L["3"]["CornerRadius"] = UDim.new(1, 0);
G2L["4"] = Instance.new("Frame", G2L["2"]);
G2L["4"]["BorderSizePixel"] = 0;
G2L["4"]["BackgroundColor3"] = Color3.fromRGB(67, 67, 67);
G2L["4"]["Size"] = UDim2.new(0, 32, 0, 34);
G2L["4"]["Position"] = UDim2.new(0.04088, 0, 0.12979, 0);
G2L["4"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["4"]["BackgroundTransparency"] = 0.6;
G2L["5"] = Instance.new("UICorner", G2L["4"]);
G2L["5"]["CornerRadius"] = UDim.new(1, 0);
G2L["6"] = Instance.new("UIAspectRatioConstraint", G2L["4"]);
G2L["7"] = Instance.new("TextButton", G2L["4"]);
G2L["7"]["BorderSizePixel"] = 0;
G2L["7"]["TextSize"] = 14;
G2L["7"]["AutoButtonColor"] = false;
G2L["7"]["TextColor3"] = Color3.fromRGB(153, 153, 153);
G2L["7"]["BackgroundColor3"] = Color3.fromRGB(67, 67, 67);
G2L["7"]["FontFace"] = Font.new([[rbxasset://fonts/families/SourceSansPro.json]], Enum.FontWeight.SemiBold, Enum.FontStyle.Normal);
G2L["7"]["BackgroundTransparency"] = 0.6;
G2L["7"]["Size"] = UDim2.new(0, 85, 0, 32);
G2L["7"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["7"]["Text"] = [[Restart]];
G2L["7"]["Visible"] = false;
G2L["7"]["Position"] = UDim2.new(1.25, 0, 0, 0);
G2L["8"] = Instance.new("UICorner", G2L["7"]);
G2L["8"]["CornerRadius"] = UDim.new(1, 0);
G2L["9"] = Instance.new("ImageButton", G2L["4"]);
G2L["9"]["BorderSizePixel"] = 0;
G2L["9"]["BackgroundTransparency"] = 1;
G2L["9"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["9"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["9"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["a"] = Instance.new("ImageLabel", G2L["9"]);
G2L["a"]["BorderSizePixel"] = 0;
G2L["a"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["a"]["Image"] = [[rbxassetid://104208878511392]];
G2L["a"]["Size"] = UDim2.new(0, 20, 0, 19);
G2L["a"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["a"]["BackgroundTransparency"] = 1;
G2L["a"]["Position"] = UDim2.new(0.1875, 0, 0.1875, 0);
G2L["b"] = Instance.new("UIAspectRatioConstraint", G2L["a"]);
G2L["c"] = Instance.new("TextLabel", G2L["2"]);
G2L["c"]["BorderSizePixel"] = 0;
G2L["c"]["TextSize"] = 14;
G2L["c"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["c"]["FontFace"] = Font.new([[rbxasset://fonts/families/SourceSansPro.json]], Enum.FontWeight.SemiBold, Enum.FontStyle.Normal);
G2L["c"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["c"]["BackgroundTransparency"] = 1;
G2L["c"]["Size"] = UDim2.new(0, 98, 0, 12);
G2L["c"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["c"]["Text"] = [[Loading the Method...]];
G2L["c"]["Name"] = [[Status]];
G2L["c"]["Position"] = UDim2.new(0.35713, 0, 0.34091, 0);

G2L["d"] = Instance.new("Frame", G2L["2"]);
G2L["d"]["Name"] = [[DragLine]];
G2L["d"]["BorderSizePixel"] = 0;
G2L["d"]["BackgroundColor3"] = Color3.fromRGB(237, 17, 219);
G2L["d"]["BackgroundTransparency"] = 0.6;
G2L["d"]["Size"] = UDim2.new(0, 55, 0, 4);
G2L["d"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["d"]["Position"] = UDim2.new(0.5, 0, 1.1, 0);
G2L["d"]["BorderColor3"] = Color3.fromRGB(237, 17, 219);
G2L["e"] = Instance.new("UICorner", G2L["d"]);
G2L["e"]["CornerRadius"] = UDim.new(1, 0);

-- Toggle: controla PublishPause + mantém Roblox voice nativo muted
G2L["9"].MouseButton1Click:Connect(function()
    toggleState = not toggleState
    VoiceInternal:PublishPause(not toggleState)

    if toggleState then
        -- unmutou no bypass: garante que o voice nativo continua muted
        disconnectRobloxVoice()
        if audioInput and audioInput.Parent then
            audioInput.Muted = false
        end
    else
        -- mutou: muta o AudioDeviceInput também
        if audioInput and audioInput.Parent then
            audioInput.Muted = true
        end
    end

    G2L["a"]["Image"] = toggleState and IMAGE_ON or IMAGE_OFF
end)

local StatusLabel = G2L["c"]
local DragLine = G2L["d"]

DragLine.MouseEnter:Connect(function()
    TweenService:Create(DragLine, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    }):Play()
end)

DragLine.MouseLeave:Connect(function()
    TweenService:Create(DragLine, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.6,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    }):Play()
end)

DragLine.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStartPos = input.Position
        frameStartPos = G2L["2"].Position
        TweenService:Create(DragLine, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0,
            BackgroundColor3 = Color3.fromRGB(200, 200, 200)
        }):Play()
    end
end)

DragLine.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        TweenService:Create(DragLine, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0,
            BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStartPos
        local viewportSize = workspace.CurrentCamera.ViewportSize
        local newX = frameStartPos.X.Scale + (delta.X / viewportSize.X)
        local newY = frameStartPos.Y.Scale + (delta.Y / viewportSize.Y)
        G2L["2"].Position = UDim2.new(newX, 0, newY, 0)
    end
end)

local function SetStatus(text, waitAfter)
    local fadeOut = TweenService:Create(StatusLabel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        TextTransparency = 1
    })
    fadeOut:Play()
    fadeOut.Completed:Wait()

    StatusLabel.Text = text

    local fadeIn = TweenService:Create(StatusLabel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        TextTransparency = 0
    })
    fadeIn:Play()
    fadeIn.Completed:Wait()

    if waitAfter then
        task.wait(waitAfter)
    end
end

local StartSequence = function()
    StatusLabel.TextTransparency = 1
    StatusLabel.Text = [[Loading the Method...]]

    task.wait(0.5)
    SetStatus("Loading the Method...", 2)
    SetStatus("Checking if Mic is Muted", 2)

    if first_time == true then
        VoiceInternal:PublishPause(false)
        disconnectRobloxVoice()  -- mantém nativo muted no restart
        if toggleState == false then
            toggleState = true
            G2L["a"]["Image"] = IMAGE_ON
        end
    end

    if not game:GetService("CoreGui").TopBarApp.TopBarApp.UnibarLeftFrame.UnibarMenu["2"]["3"]:FindFirstChild("toggle_mic_mute") then
        repeat
            SetStatus("Connect to Voice Chat", 2)
            task.wait(2)
        until game:GetService("CoreGui").TopBarApp.TopBarApp.UnibarLeftFrame.UnibarMenu["2"]["3"]:FindFirstChild("toggle_mic_mute")
    end
    if game:GetService("CoreGui").TopBarApp.TopBarApp.UnibarLeftFrame.UnibarMenu["2"]["3"].toggle_mic_mute.IntegrationIconFrame.IntegrationIcon["1"].Image == "rbxasset://textures/ui/VoiceChat/MicLight/Muted.png" then
        repeat
            SetStatus("Please, unmute your mic!", 2)
            task.wait(2) 
        until game:GetService("CoreGui").TopBarApp.TopBarApp.UnibarLeftFrame.UnibarMenu["2"]["3"].toggle_mic_mute.IntegrationIconFrame.IntegrationIcon["1"].Image ~= "rbxasset://textures/ui/VoiceChat/MicLight/Muted.png"
        SetStatus("Disabling voice chat button", 2)
    end
    SetStatus("Continuing Bypassing!", 2)
    VoiceInternal:JoinByGroupId(Group, false, false)
    task.wait(4)
    VoiceChatService:rejoinVoice()
    task.wait(2)

    for i = 1, 8 do 
        VoiceInternal:JoinByGroupId(Group, false, false)
        task.wait()
    end

    -- Aqui: cria o AudioDeviceInput e mantém o voice nativo desconectado
    disconnectRobloxVoice()
    createInput()

    VoiceInternal:PublishPause(false)
    first_time = true
    G2L["a"]["Image"] = IMAGE_ON

    SetStatus("All Done!", 2)
    SetStatus("Use the UI to mute for now on!", 2)
    SetStatus("Made By Unicorn.Man", 2.5)

    local fadeOutFinal = TweenService:Create(StatusLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        TextTransparency = 1
    })
    fadeOutFinal:Play()
    fadeOutFinal.Completed:Wait()

    G2L["7"].Visible = true
    G2L["7"].BackgroundTransparency = 1
    G2L["7"].TextTransparency = 1

    local expandFrame = TweenService:Create(G2L["2"], TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 140, 0, 44)
    })
    expandFrame:Play()
    expandFrame.Completed:Wait()

    local fadeInBtn = TweenService:Create(G2L["7"], TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.6,
        TextTransparency = 0
    })
    fadeInBtn:Play()
    fadeInBtn.Completed:Wait()
end

G2L["7"].MouseButton1Click:Connect(function()
    local fadeOutBtn = TweenService:Create(G2L["7"], TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1,
        TextTransparency = 1
    })
    fadeOutBtn:Play()
    fadeOutBtn.Completed:Wait()

    G2L["7"].Visible = false

    local shrinkFrame = TweenService:Create(G2L["2"], TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 209, 0, 44)
    })
    shrinkFrame:Play()
    shrinkFrame.Completed:Wait()

    StartSequence()
end)

task.spawn(StartSequence)
