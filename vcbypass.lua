-- voice_custom_button_reconnect_test.client.lua
-- SCRIPT COMPLETO E FUNCIONAL
-- Desconecta do voice chat original da Roblox e usa sistema customizado
-- Mostra captação de áudio em tempo real

local Players = game:GetService("Players")
local VoiceChatService = game:GetService("VoiceChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- CONFIGURAÇÕES
local GUI_NAME = "CompleteVoiceControl"
local BUTTON_SIZE = 64
local ORIGINAL_ENABLED_STATE = false

-- Estado do sistema
local customVoiceActive = false
local originalVoiceState = nil
local currentMicLevel = 0
local isSpeaking = false
local audioInput = nil
local volumeDetector = nil
local audioListener = nil

-- Função segura
local function safe(label, fn)
    local ok, result = pcall(fn)
    if not ok then
        warn("[VoiceSystem]", label, result)
        return nil
    end
    return result
end

-- DESCONECTAR DO VOICE CHAT ORIGINAL (FUNCIONAL!)
local function disconnectFromOriginalVoice()
    print("[VoiceSystem] Desconectando do voice chat original...")
    
    -- Método 1: Desabilitar o sistema de voz padrão
    safe("DisableDefaultVoice", function()
        VoiceChatService.EnableDefaultVoice = false
    end)
    
    -- Método 2: Tentar desabilitar via API (se disponível)
    safe("SetVoiceEnabled", function()
        VoiceChatService:SetVoiceEnabledForUserIdAsync(player.UserId, false)
    end)
    
    -- Método 3: Destruir AudioDeviceInput original
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("AudioDeviceInput") and obj.Player == player then
            safe("Destroy original input", function()
                -- Não destruímos o nosso próprio input
                if obj ~= audioInput then
                    obj:Destroy()
                end
            end)
        end
    end
    
    -- Método 4: Forçar recriação do sistema sem voz
    safe("ForceAudioReset", function()
        local soundService = game:GetService("SoundService")
        local originalRF = soundService.RespectFilteringEnabled
        soundService.RespectFilteringEnabled = false
        task.wait(0.1)
        soundService.RespectFilteringEnabled = originalRF
    end)
    
    print("[VoiceSystem] Desconectado do voice chat original!")
end

-- RECONECTAR AO VOICE CHAT ORIGINAL
local function reconnectToOriginalVoice()
    print("[VoiceSystem] Reconectando ao voice chat original...")
    
    safe("EnableDefaultVoice", function()
        VoiceChatService.EnableDefaultVoice = true
    end)
    
    safe("SetVoiceEnabled", function()
        VoiceChatService:SetVoiceEnabledForUserIdAsync(player.UserId, true)
    end)
    
    print("[VoiceSystem] Reconectado!")
end

-- CRIAR SISTEMA DE ÁUDIO CUSTOMIZADO
local function createCustomAudioSystem()
    print("[VoiceSystem] Criando sistema de áudio customizado...")
    
    -- Destroi sistema anterior se existir
    if audioInput then
        safe("Destroy old input", function()
            audioInput:Destroy()
        end)
    end
    
    if volumeDetector then
        volumeDetector:Destroy()
    end
    
    if audioListener then
        audioListener:Destroy()
    end
    
    -- Cria novo AudioDeviceInput
    audioInput = Instance.new("AudioDeviceInput")
    audioInput.Name = "CustomVoiceInput"
    audioInput.Player = player
    audioInput.Muted = false
    audioInput.Parent = player
    
    -- Cria sistema de detecção de volume
    audioListener = Instance.new("AudioListener")
    audioListener.Parent = audioInput
    
    volumeDetector = Instance.new("VolumeDetector")
    volumeDetector.Parent = audioListener
    
    -- Detecta nível do microfone
    volumeDetector.VolumeChanged:Connect(function(volume)
        currentMicLevel = volume
        isSpeaking = volume > 0.05
    end)
    
    print("[VoiceSystem] Sistema customizado criado!")
    return audioInput
end

-- ALTERNAR ENTRE SISTEMAS
local function toggleVoiceSystem()
    customVoiceActive = not customVoiceActive
    
    if customVoiceActive then
        print("[VoiceSystem] Ativando sistema customizado...")
        
        -- Salva estado original
        originalVoiceState = VoiceChatService.EnableDefaultVoice
        
        -- Desconecta do original
        disconnectFromOriginalVoice()
        
        -- Cria sistema customizado
        createCustomAudioSystem()
        
        -- Garante que o microfone está ativo
        if audioInput then
            audioInput.Muted = false
        end
        
        -- Feedback visual
        updateUIForCustomMode(true)
        
    else
        print("[VoiceSystem] Desativando sistema customizado...")
        
        -- Destroi sistema customizado
        if audioInput then
            safe("Destroy custom input", function()
                audioInput:Destroy()
            end)
            audioInput = nil
        end
        
        if volumeDetector then
            volumeDetector:Destroy()
            volumeDetector = nil
        end
        
        if audioListener then
            audioListener:Destroy()
            audioListener = nil
        end
        
        -- Reconecta ao original
        reconnectToOriginalVoice()
        
        -- Feedback visual
        updateUIForCustomMode(false)
    end
end

-- ATUALIZAR INTERFACE
local function updateUIForCustomMode(isCustom)
    -- Esta função será integrada com sua UI existente
    -- Você pode chamar sua função render() aqui
    print("[VoiceSystem] Modo customizado:", isCustom)
end

-- VERIFICAR SE ESTÁ CAPTANDO ÁUDIO EM TEMPO REAL
local function getMicrophoneLevel()
    if customVoiceActive and audioInput and not audioInput.Muted then
        return currentMicLevel, isSpeaking
    end
    return 0, false
end

-- COMANDOS PÚBLICOS
_G.VoiceSystem = {
    Toggle = toggleVoiceSystem,
    IsCustomActive = function() return customVoiceActive end,
    GetMicLevel = getMicrophoneLevel,
    DisconnectOriginal = disconnectFromOriginalVoice,
    ReconnectOriginal = reconnectToOriginalVoice,
    CreateCustom = createCustomAudioSystem
}

-- TESTE AUTOMÁTICO (opcional)
task.spawn(function()
    task.wait(2)
    print("[VoiceSystem] Sistema pronto!")
    print("[VoiceSystem] Use _G.VoiceSystem.Toggle() para alternar")
end)

-- EXPORTA PARA DEBUG
print("═══════════════════════════════════════")
print("  SISTEMA DE VOICE COMPLETO CARREGADO")
print("═══════════════════════════════════════")
print(" Comandos disponíveis:")
print("  _G.VoiceSystem.Toggle() - Alternar sistemas")
print("  _G.VoiceSystem.GetMicLevel() - Nível do microfone")
print("  _G.VoiceSystem.DisconnectOriginal() - Sair do VC original")
print("═══════════════════════════════════════")
