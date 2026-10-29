-- REF voice prototype 2: manual voice control and an opt-in local listener experiment.
-- No automatic reconnect, remote replay or audio recording. Does not establish ban protection.
-- Startup does not change microphone state. Only StateChanged listeners are candidates;
-- LocalPlayerModerated is observed, never disabled. Restoration is best-effort and logged.
local Players=game:GetService("Players")
local Voice=game:GetService("VoiceChatService")
local Http=game:GetService("HttpService")
local Input=game:GetService("UserInputService")
local player=Players.LocalPlayer
assert(player,"Run on the client")
local playerGui=player:WaitForChild("PlayerGui",10)
assert(playerGui,"PlayerGui unavailable")
local internalOK,Internal=pcall(function()return game:GetService("VoiceChatInternal")end)
if not internalOK then Internal=nil end
local previous=playerGui:FindFirstChild("RefVoicePrototype")
if previous then previous:Destroy()end
local gui=Instance.new("ScreenGui")
gui.Name="RefVoicePrototype";gui.ResetOnSpawn=false;gui.DisplayOrder=10001;gui.Parent=playerGui
local alive,busy=true,false
local connections,records={},{}
local ownCallbacks={}
local changedListeners={}
local experimentActive=false
local started=os.clock()
local runId=Http:GenerateGUID(false):sub(1,8)
local dropped=0
local message="ready"
local function log(kind,data,allowClosed)
    if not alive and not allowClosed then return end
    if #records>=500 then table.remove(records,1);dropped+=1 end
    records[#records+1]={t=math.floor((os.clock()-started)*1000)/1000,kind=kind,data=data}
end
local function connect(signal,callback)
    local ok,c=pcall(function()return signal:Connect(callback)end)
    if ok then connections[#connections+1]=c;ownCallbacks[callback]=true end
    return ok
end

-- CORE BEGIN: keep commands separate from readback and never infer success from pcall.
local function restoreListeners()
    experimentActive=false
    local remaining={}
    for _,entry in ipairs(changedListeners)do
        local ok,connected=pcall(function()return entry.connection.Connected end)
        if ok and connected==false then
            log("listener restore",{index=entry.index,result="already disconnected"},true)
        else
            local restored=pcall(function()entry.connection:Enable()end)
            local readable,enabled=pcall(function()return entry.connection.Enabled end)
            local confirmed=restored and readable and enabled==true
            log("listener restore",{index=entry.index,confirmed=confirmed},true)
            if not confirmed then remaining[#remaining+1]=entry end
        end
    end
    changedListeners=remaining
    if #remaining>0 then return false,"could not confirm restoration of "..#remaining.." listeners; use restore again"end
    return true
end
local function disableExperimentalListeners(checkOnly)
    if not alive then return false,"closed"end
    if #changedListeners>0 then return false,"restore the previous test first"end
    if type(getconnections)~="function"then return false,"getconnections unavailable; experiment not applied"end
    local ok,list=pcall(function()return getconnections(Internal.StateChanged)end)
    if not ok or type(list)~="table"then return false,"StateChanged connections unavailable"end
    -- Match the inspected source's index range, without assuming a callback's purpose.
    -- Do not disable anything we cannot inspect AND subsequently enable again.
    local candidates={}
    for index=10,#list do
        local connection=list[index]
        local readable,enabled,callback,disable,enable=pcall(function()
            return connection.Enabled,connection.Function,connection.Disable,connection.Enable
        end)
        if not readable or type(enabled)~="boolean" or type(callback)~="function"
            or type(disable)~="function" or type(enable)~="function"then
            log("listener preflight",{index=index,result="unsupported metadata; no changes applied"})
            return false,"executor cannot verify/restore listener "..index.."; experiment cancelled"
        end
        if enabled and not ownCallbacks[callback]then
            candidates[#candidates+1]={index=index,connection=connection}
        end
    end
    log("listener preflight",{total=#list,eligible=#candidates,firstIndex=10})
    if #candidates==0 then return false,"no eligible listeners from index 10; experiment not applied"end
    if checkOnly then return true end
    for _,entry in ipairs(candidates)do
        if not alive then restoreListeners();return false,"closed"end
        -- Record before the call: a failed call could still have partially changed state.
        changedListeners[#changedListeners+1]=entry
        local disabled=pcall(function()entry.connection:Disable()end)
        local readable,enabled=pcall(function()return entry.connection.Enabled end)
        local confirmed=disabled and readable and enabled==false
        log("listener disabled",{index=entry.index,confirmed=confirmed})
        if not confirmed then
            local restored=restoreListeners()
            return false,restored and "listener change failed; restored" or "listener change failed; restoration incomplete"
        end
    end
    return true
end
local function getState()
    local result={connection="unavailable",mute="unavailable"}
    local ok,value=pcall(function()return Internal.VoiceChatState.Name end)
    if ok and type(value)=="string" then result.connection=value end
    ok,value=pcall(function()return Internal:IsPublishPaused()end)
    if not ok or type(value)~="boolean" then
        ok,value=pcall(function()return Voice:isInternalPublishPaused()end)
    end
    if ok and type(value)=="boolean" then result.mute=value end
    return result
end
local function command(service,name,...)
    if not alive then return false,"closed"end
    local args=table.pack(...)
    local ok,value=pcall(function()
        return service[name](service,table.unpack(args,1,args.n))
    end)
    log("command",{name=name,localCallSucceeded=ok,resultType=ok and typeof(value) or "error",
        booleanResult=ok and type(value)=="boolean" and tostring(value) or nil,
        error=not ok and tostring(value):sub(1,240) or nil})
    if not ok then return false,name..": "..tostring(value):sub(1,160)end
    return true
end
local function waitState(test,seconds)
    local deadline=os.clock()+seconds
    while alive do
        local state=getState()
        if test(state)then return true,state end
        if os.clock()>=deadline then return false,state end
        task.wait(0.1)
    end
    return false,getState()
end
local function setMute(value)
    if not alive then return false,"closed"end
    if getState().connection~="Joined"then return false,"voice is not connected"end
    local ok,err=command(Internal,"PublishPause",value)
    if not ok then return false,err end
    local confirmed,state=waitState(function(s)return s.connection=="Joined" and s.mute==value end,3)
    log("mute readback",{requested=value,confirmed=confirmed,state=state})
    if not confirmed then return false,"mute change not confirmed; request was not repeated"end
    return true
end
local function toggleMute()
    local state=getState()
    if type(state.mute)~="boolean"then return false,"mute state unavailable on this executor"end
    return setMute(not state.mute)
end
local function reconnect(experimental)
    local before=getState()
    if before.connection=="unavailable"then return false,"connection state unavailable on this executor"end
    if before.connection=="Joining" or before.connection=="Leaving"then
        return false,"voice is already changing connection; wait and try again"
    end
    if type(before.mute)~="boolean"then return false,"cannot read microphone state; reconnect cancelled"end
    if experimental then
        local supported,supportError=disableExperimentalListeners(true)
        if not supported then return false,supportError end
    end
    -- A disconnected session reconnects muted. A connected session retains its known preference.
    local restoreMuted=before.connection~="Joined" or before.mute
    log("reconnect requested",{before=before,restoreMuted=restoreMuted})
    if before.connection=="Joined"then
        message="disconnecting..."
        local ok,err=command(Voice,"leaveVoice")
        if not ok then return false,err end
        local left=waitState(function(s)return s.connection=="Ended" or s.connection=="Idle"end,6)
        if not left then return false,"disconnect not confirmed; join was not sent"end
    elseif before.connection~="Ended" and before.connection~="Idle"then
        return false,"unsupported connection state: "..before.connection
    end
    if not alive then return false,"closed"end
    if experimental then
        message="applying listener experiment..."
        local applied,applyError=disableExperimentalListeners()
        if not applied then return false,applyError end
    end
    message="connecting..."
    local method="joinVoice"
    if experimental then
        local exists,value=pcall(function()return Voice.rejoinVoice end)
        if exists and type(value)=="function"then method="rejoinVoice"end
    end
    local ok,err=command(Voice,method)
    if not ok then return false,err end
    local joined,state=waitState(function(s)return s.connection=="Joined"end,15)
    if not joined then return false,"connection not confirmed; no automatic retry"end
    if not alive then return false,"closed"end
    -- Restore only after readback. This does not guarantee mute throughout the engine's join transition.
    if state.mute~=restoreMuted then
        message="restoring microphone state..."
        local restored,restoreError=setMute(restoreMuted)
        if not restored then return false,"connected, but "..restoreError end
    end
    log("reconnect confirmed",{state=getState()})
    experimentActive=experimental==true
    return true
end
-- CORE END

local panel=Instance.new("Frame")
panel.Size=UDim2.fromOffset(292,226);panel.Position=UDim2.new(0.5,-146,0,70)
panel.BackgroundColor3=Color3.fromRGB(20,21,24);panel.BorderSizePixel=0;panel.Parent=gui
local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,9);corner.Parent=panel
local function text(value,x,y,w,h)
    local v=Instance.new("TextLabel");v.Position=UDim2.fromOffset(x,y);v.Size=UDim2.fromOffset(w,h)
    v.BackgroundTransparency=1;v.TextColor3=Color3.fromRGB(230,230,232)
    v.Font=Enum.Font.Gotham;v.TextSize=12;v.TextWrapped=true;v.Text=value;v.Parent=panel
    return v
end
local title=text("voice prototype v2",12,0,190,32);title.TextXAlignment=Enum.TextXAlignment.Left
local function button(value,x,y,w,h,callback)
    local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h)
    b.BackgroundColor3=Color3.fromRGB(38,39,44);b.BorderSizePixel=0
    b.Font=Enum.Font.Gotham;b.TextSize=11;b.TextColor3=Color3.fromRGB(235,235,235)
    b.Text=value;b.Parent=panel
    local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,6);c.Parent=b
    connect(b.Activated,callback);return b
end
local render
local function run(name,fn)
    if busy or not alive then return end
    busy=true;message=name.."..."
    task.spawn(function()
        local safe,ok,err=pcall(fn)
        if not alive then return end
        busy=false
        if not safe then err=tostring(ok);ok=false end
        if name=="experiment" and not ok then
            local restored=restoreListeners()
            if not restored then err=tostring(err).."; restoration incomplete"end
        end
        message=ok and "ready" or tostring(err or "operation failed")
        log("operation result",{operation=name,confirmed=ok==true,message=message})
        render()
    end)
end
local mic=button("",12,40,44,44,function()run("mute",toggleMute)end)
local icon=Instance.new("ImageLabel");icon.BackgroundTransparency=1
icon.Size=UDim2.fromOffset(30,30);icon.Position=UDim2.fromOffset(7,7);icon.Parent=mic
local muteLabel=text("checking microphone",64,40,216,20);muteLabel.TextXAlignment=Enum.TextXAlignment.Left
local connectionLabel=text("checking connection",64,61,216,20);connectionLabel.TextXAlignment=Enum.TextXAlignment.Left
local status=text("ready",12,90,268,40);status.TextSize=11
local reconnectButton=button("reconnect",12,140,92,30,function()
    if #changedListeners>0 then message="restore the experiment before reconnecting";render();return end
    run("reconnect",function()return reconnect(false)end)
end)
local experimentButton=button("start experiment",12,182,268,30,function()
    if #changedListeners>0 then run("restore",restoreListeners)
    else run("experiment",function()return reconnect(true)end)end
end)
local function export()
    return Http:JSONEncode({version="REF voice prototype 2",runId=runId,place=game.PlaceId,
        experimentActive=experimentActive,listenersPendingRestore=#changedListeners,
        exported=os.date("!%Y-%m-%dT%H:%M:%SZ"),records=records,dropped=dropped,state=getState(),
        note="Opt-in StateChanged listener experiment with best-effort restoration. Local readback is not proof of remote audibility or protection against moderation. No audio or credentials recorded."})
end
local copyButton=button("copy log",112,140,80,30,function()
    local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
    local success=copy and pcall(function()copy(export())end)
    message=success and "log copied" or "clipboard unavailable; use save";render()
end)
local saveButton=button("save",200,140,80,30,function()
    local success,err=pcall(function()
        assert(type(writefile)=="function" and type(isfolder)=="function" and type(makefolder)=="function","file access unavailable")
        for _,folder in ipairs({"True Ref","True Ref/Logs"})do if not isfolder(folder)then makefolder(folder)end end
        writefile("True Ref/Logs/voice-prototype-v2-"..os.date("%Y%m%d-%H%M%S").."-"..runId..".json",export())
    end)
    message=success and "saved in workspace/True Ref/Logs" or tostring(err):sub(1,160);render()
end)
local contents={mic,muteLabel,connectionLabel,status,reconnectButton,copyButton,saveButton,experimentButton}
local minimized=false
button("-",222,3,27,26,function()
    minimized=not minimized
    panel.Size=UDim2.fromOffset(292,minimized and 32 or 226)
    for _,v in ipairs(contents)do v.Visible=not minimized end
end)
button("x",253,3,27,26,function()gui:Destroy()end)
render=function()
    if not alive then return end
    local state=getState()
    local known=type(state.mute)=="boolean"
    muteLabel.Text=known and (state.mute and "muted" or "unmuted") or "mute unavailable"
    connectionLabel.Text="voice: "..state.connection:lower()
    icon.Image=known and (state.mute and "rbxasset://textures/ui/VoiceChat/MicLight/Muted.png"
        or "rbxasset://textures/ui/VoiceChat/MicLight/Unmuted0.png") or "rbxasset://textures/ui/VoiceChat/MicDark/Connecting.png"
    mic.Active=not busy and known and state.connection=="Joined"
    icon.ImageTransparency=mic.Active and 0 or 0.5
    reconnectButton.Active=not busy and #changedListeners==0
    experimentButton.Active=not busy
    experimentButton.Text=#changedListeners>0 and (experimentActive and "stop experiment / restore" or "retry restore") or "start experiment"
    status.Text=message
end
local drag,startPointer,startPosition
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        drag=input;startPointer=input.Position;startPosition=panel.Position
    end
end)
connect(Input.InputChanged,function(input)
    if drag and (input==drag or input.UserInputType==Enum.UserInputType.MouseMovement)then
        local delta=input.Position-startPointer
        panel.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,startPosition.Y.Scale,startPosition.Y.Offset+delta.Y)
    end
end)
connect(Input.InputEnded,function(input)if input==drag then drag=nil end end)
connect(gui.Destroying,function()
    -- Stop pending work first, but retain diagnostics during the restoration attempt.
    alive=false
    restoreListeners()
    if #changedListeners>0 then warn("[REF voice prototype] Listener restoration incomplete; rejoin the game to reset the client.")end
    for _,c in ipairs(connections)do c:Disconnect()end
end)
if Internal then
    local ok,signal=pcall(function()return Internal.StateChanged end)
    if ok then connect(signal,function(old,new)log("connection event",{old=tostring(old),new=tostring(new)})end)end
    ok,signal=pcall(function()return Internal.LocalPlayerModerated end)
    if ok then connect(signal,function()
        log("moderation event",{name="LocalPlayerModerated"})
        message="Roblox reported voice moderation";render()
    end)end
end
log("started",{state=getState()})
render()
task.spawn(function()
    local last
    while alive do
        local state=getState()
        local key=state.connection..":"..tostring(state.mute)
        if key~=last then last=key;log("state",state)end
        render()
        task.wait(0.25)
    end
end)
