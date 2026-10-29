-- REF voice observer 2.1. Read-only diagnostics; no hooks, audio capture or remote replay.
-- Run BEFORE the other script, use its voice toggle, then copy/save this report.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local Input=game:GetService("UserInputService")
local Voice=game:GetService("VoiceChatService")
local player=Players.LocalPlayer
assert(player,"Run this on the client")
local playerGui=player:WaitForChild("PlayerGui",10)
assert(playerGui,"PlayerGui unavailable")
local previous=playerGui:FindFirstChild("RefVoiceObserver")
if previous then previous:Destroy() end

local alive,recording=true,true
local started=os.clock()
local records,connections,capabilities={}, {}, {}
local dropped,watched=0,0
local watchedAudio,watchedUI=0,0
local seen=setmetatable({},{__mode="k"})
local ids=setmetatable({},{__mode="k"})
local nextId,clickId=0,0
local captureState -- Assigned before observation starts.
local runId=Http:GenerateGUID(false):sub(1,8)
local gui=Instance.new("ScreenGui")
gui.Name="RefVoiceObserver"
gui.ResetOnSpawn=false
gui.DisplayOrder=10000
gui.Parent=playerGui

local function path(obj)
    local ok,value=pcall(function()return obj:GetFullName()end)
    return ok and value:gsub(player.Name:gsub("([^%w])","%%%1"),"LocalPlayer") or "unavailable"
end
local function read(obj,key)
    local ok,value=pcall(function()return obj[key]end)
    if not ok then return "unavailable" end
    local t=typeof(value)
    if t=="boolean" or t=="number" then return value end
    if t=="Instance" then return path(value) end
    if t=="Vector2" then return {x=math.floor(value.X),y=math.floor(value.Y)} end
    if t=="Color3" then return {r=math.floor(value.R*255),g=math.floor(value.G*255),b=math.floor(value.B*255)} end
    if value==nil then return "nil" end
    return tostring(value):sub(1,180)
end
local function id(obj)
    if not ids[obj] then nextId+=1;ids[obj]=nextId end
    return ids[obj]
end
local function add(kind,data)
    if not alive or not recording then return end
    if #records>=1800 then table.remove(records,1);dropped+=1 end
    records[#records+1]={t=math.floor((os.clock()-started)*1000)/1000,kind=kind,data=data}
end
local function connect(signal,callback,bucket)
    local ok,c=pcall(function()return signal:Connect(callback)end)
    if ok then table.insert(bucket or connections,c) end
    return ok
end
local function related(obj)
    local text=path(obj):lower()
    return text:find("voice",1,true) or text:find("microphone",1,true)
        or text:find("mute",1,true) or text:find("micbutton",1,true)
        or text:find("mictoggle",1,true)
        or text:find("vcbypass",1,true)
end
local audioKeys={
    AudioDeviceInput={"Muted","Active","IsReady","Volume","Player"},
    AudioDeviceOutput={"Player"},
    AudioEmitter={},AudioListener={},AudioFader={"Volume","Bypass"},
    Wire={"Connected","SourceInstance","TargetInstance","SourceName","TargetName"},
}
local function snapshot(obj,kind)
    local data={id=id(obj),path=path(obj),class=obj.ClassName}
    if audioKeys[obj.ClassName] then
        for _,key in ipairs(audioKeys[obj.ClassName])do data[key]=read(obj,key) end
    else
        for _,key in ipairs({"Visible","AbsolutePosition","AbsoluteSize"})do data[key]=read(obj,key)end
        if obj:IsA("ImageButton") or obj:IsA("ImageLabel") then
            for _,key in ipairs({"Image","ImageColor3","ImageTransparency","ImageRectOffset","ImageRectSize"})do data[key]=read(obj,key)end
        end
        -- Never read text boxes, chat messages or microphone samples.
        if obj:IsA("TextButton") or (obj:IsA("TextLabel") and related(obj)) then data.Text=read(obj,"Text")end
        local parent=obj.Parent
        while parent and parent~=game do
            if parent:IsA("LayerCollector") then data.layerEnabled=read(parent,"Enabled");break end
            parent=parent.Parent
        end
    end
    add(kind,data)
    return data
end
local function inspect(obj,isNew)
    if not alive or seen[obj] or obj==gui or obj:IsDescendantOf(gui) then return end
    local audio=audioKeys[obj.ClassName]~=nil
    if obj:IsA("AudioDeviceInput") then
        local ok,owner=pcall(function()return obj.Player end)
        -- Observe unassigned new inputs too: their owner may be assigned later.
        if not ok or (owner~=nil and owner~=player) then return end
    elseif not audio and not (obj:IsA("GuiButton") and related(obj))
        and not (obj:IsA("LayerCollector") and related(obj))
        and not (related(obj) and (obj:IsA("ImageLabel") or obj:IsA("Frame") or obj:IsA("TextLabel"))) then return end
    -- Unrelated command lists must not consume the microphone observation budget.
    -- Audio and UI have separate limits, released when instances are destroyed.
    if audio then
        if watchedAudio>=128 then capabilities.audioLimitReached=true;return end
        watchedAudio+=1
    else
        if watchedUI>=300 then capabilities.voiceUILimitReached=true;return end
        watchedUI+=1
    end
    watched+=1
    local bucket={}
    seen[obj]=bucket
    local last={}
    local lastPath=path(obj)
    snapshot(obj,isNew and "added" or "baseline")
    local keys=audio and audioKeys[obj.ClassName]
        or obj:IsA("LayerCollector") and {"Enabled","Name"}
        or {"Visible","Image","ImageColor3","ImageTransparency","ImageRectOffset","ImageRectSize","Text","TextColor3","BackgroundColor3","Name"}
    for _,key in ipairs(keys)do
        local ok,signal=pcall(function()return obj:GetPropertyChangedSignal(key)end)
        if ok then
            last[key]=Http:JSONEncode(read(obj,key))
            connect(signal,function()
                local value=read(obj,key)
                local encoded=Http:JSONEncode(value)
                if encoded~=last[key] then
                    last[key]=encoded
                    add("property",{id=id(obj),path=path(obj),property=key,value=value})
                end
            end,bucket)
        end
    end
    connect(obj.AncestryChanged,function(_,parent)
        if parent then lastPath=path(obj) end
        add("ancestry",{id=id(obj),path=lastPath,parent=parent and path(parent) or "nil"})
    end,bucket)
    if obj:IsA("GuiButton") then
        connect(obj.Activated,function()
            if not alive or not recording then return end
            snapshot(obj,"clicked")
            if captureState then
                clickId+=1
                local n=clickId
                -- The Activated handler can run after the other script's callback.
                -- Compare with continuous pre-click samples; do not call this "before".
                for _,delay in ipairs({0,0.25,1})do
                    task.delay(delay,function()
                        if alive and recording then
                            captureState("after click",n,delay)
                            if obj.Parent then snapshot(obj,"button follow-up")end
                        end
                    end)
                end
            end
        end,bucket)
    end
    connect(obj.Destroying,function()
        add("removed",{id=id(obj),path=lastPath})
        for _,c in ipairs(bucket)do c:Disconnect()end
        seen[obj]=nil;watched-=1
        if audio then watchedAudio-=1 else watchedUI-=1 end
    end,bucket)
end
local roots,rootSet={},{}
local function addRoot(root)
    if not root or rootSet[root] then return end
    rootSet[root]=true;roots[#roots+1]=root
end
addRoot(playerGui)
local ok,core=pcall(function()return game:GetService("CoreGui")end)
if ok then addRoot(core)end
if type(gethui)=="function" then local success,root=pcall(gethui);if success then addRoot(root)end end

local panel=Instance.new("Frame")
panel.Size=UDim2.fromOffset(310,158)
panel.Position=UDim2.new(0.5,-155,0,70)
panel.BackgroundColor3=Color3.fromRGB(20,21,24)
panel.BorderSizePixel=0
panel.Parent=gui
local scale=Instance.new("UIScale");scale.Parent=panel
local function fit()
    local camera=workspace.CurrentCamera
    if camera then scale.Scale=math.min(1,math.max(0.5,(camera.ViewportSize.X-16)/310))end
end
fit()
local function label(text,x,y,w,h)
    local v=Instance.new("TextLabel");v.BackgroundTransparency=1
    v.Position=UDim2.fromOffset(x,y);v.Size=UDim2.fromOffset(w,h)
    v.Font=Enum.Font.Gotham;v.TextSize=12;v.TextColor3=Color3.fromRGB(230,230,232)
    v.Text=text;v.TextWrapped=true;v.Parent=panel;return v
end
local title=label("voice observer v2.1",12,0,210,34);title.TextXAlignment=Enum.TextXAlignment.Left
local status=label("recording · activate the other script",12,38,286,34)
local function button(text,x,y,w,fn)
    local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,28)
    b.BackgroundColor3=Color3.fromRGB(39,40,45);b.BorderSizePixel=0;b.Font=Enum.Font.Gotham
    b.TextSize=11;b.TextColor3=Color3.fromRGB(240,240,240);b.Text=text;b.Parent=panel
    connect(b.Activated,fn);return b
end
local function export()
    return Http:JSONEncode({version="REF voice observer 2.1",runId=runId,place=game.PlaceId,
        watched={audio=watchedAudio,voiceUI=watchedUI},
        exported=os.date("!%Y-%m-%dT%H:%M:%SZ"),dropped=dropped,capabilities=capabilities,records=records,
        note="Read-only state/UI/audio-graph observations. No audio samples, tokens, hooks, privilege changes or remote replay. Click samples are AFTER callbacks; compare earlier state samples. Unavailable is not false. Does not prove suspension bypass or identify internal function calls."})
end
local controls={status}
local pauseButton
pauseButton=button("pause",12,80,88,function()
    if recording then add("marker",{label="paused"});recording=false
    else recording=true;add("marker",{label="resumed"});for obj in pairs(seen)do snapshot(obj,"resume snapshot")end;if captureState then captureState("resumed")end end
    pauseButton.Text=recording and "pause" or "record"
    status.Text=(recording and "recording" or "paused").." · "..#records.." records"
end)
table.insert(controls,pauseButton)
table.insert(controls,button("mark step",110,80,88,function()
    add("marker",{label="manual step"});if captureState then captureState("manual step")end;status.Text="marked · "..#records.." records"
end))
table.insert(controls,button("copy",208,80,88,function()
    local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
    local success=copy and pcall(function()copy(export())end)
    status.Text=success and ("copied · "..#records.." records") or "clipboard unavailable; use save"
end))
table.insert(controls,button("save json",12,118,284,function()
    local success,err=pcall(function()
        assert(type(writefile)=="function" and type(makefolder)=="function" and type(isfolder)=="function","file access unavailable")
        for _,dir in ipairs({"True Ref","True Ref/Logs"})do if not isfolder(dir)then makefolder(dir)end end
        local filename="voice-v2.1-"..os.date("%Y%m%d-%H%M%S").."-"..runId..".json"
        writefile("True Ref/Logs/"..filename,export())
    end)
    status.Text=success and "saved: workspace/True Ref/Logs/voice-v2.1-...json" or tostring(err):sub(1,100)
end))
local minimized=false
button("-",242,3,27,function()
    minimized=not minimized
    panel.Size=UDim2.fromOffset(310,minimized and 34 or 158)
    for _,control in ipairs(controls)do control.Visible=not minimized end
end)
button("x",275,3,27,function()gui:Destroy()end)
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
    alive=false
    for _,c in ipairs(connections)do c:Disconnect()end
    for _,bucket in pairs(seen)do for _,c in ipairs(bucket)do c:Disconnect()end end
end)
-- Strict allowlist: only boolean getters. No group/session IDs, credentials,
-- connectivity dumps, GetAndClear methods, module loading or voice commands.
local readers={}
local function getter(service,serviceName,name)
    local key=serviceName.."."..name
    local r={key=key,service=service,name=name,blocked=service==nil}
    readers[#readers+1]=r
    if r.blocked then capabilities[key]="service unavailable"end
end
local internalOk,internal=pcall(function()return game:GetService("VoiceChatInternal")end)
if not internalOk then internal=nil end
getter(Voice,"VoiceChatService","getInternalPublishPause")
getter(Voice,"VoiceChatService","isInternalPublishPaused")
getter(internal,"VoiceChatInternal","IsPublishPaused")
getter(internal,"VoiceChatInternal","IsContextVoiceEnabled")
local function readBoolean(r)
    if r.blocked then return "unavailable"end
    local success,value=pcall(function()return r.service[r.name](r.service)end)
    if success and type(value)=="boolean"then
        capabilities[r.key]="readable"
        return value
    end
    r.blocked=true -- No repeated permission failures or retries in the render loop.
    capabilities[r.key]=success and "unexpected result type" or "unavailable or denied"
    return "unavailable"
end
local lastState
captureState=function(reason,n,delay)
    if not alive or not recording then return end
    local data={voice={},audio={}}
    for _,r in ipairs(readers)do data.voice[r.key]=readBoolean(r)end
    if internal then data.voice.VoiceChatState=read(internal,"VoiceChatState")end
    for obj in pairs(seen)do
        if audioKeys[obj.ClassName] then
            local entry={id=id(obj),path=path(obj),class=obj.ClassName}
            for _,key in ipairs(audioKeys[obj.ClassName])do entry[key]=read(obj,key)end
            data.audio[#data.audio+1]=entry
        end
    end
    table.sort(data.audio,function(a,b)return a.id<b.id end)
    local encoded=Http:JSONEncode(data)
    if reason~="poll" or encoded~=lastState then
        lastState=encoded
        add("state",{reason=reason,click=n,delay=delay,voice=data.voice,audio=data.audio})
    end
end
local function observeEvent(service,serviceName,name,callback)
    local key=serviceName.."."..name
    local success,signal=pcall(function()return service[name]end)
    local subscribed=success and connect(signal,callback)
    capabilities[key]=subscribed and "subscribed" or "unavailable or denied"
end
if internal then
    capabilities["VoiceChatInternal.VoiceChatState"]=read(internal,"VoiceChatState")
    observeEvent(internal,"VoiceChatInternal","StateChanged",function(old,new)
        add("voice connection",{old=tostring(old),new=tostring(new)})
        captureState("connection event")
    end)
    observeEvent(internal,"VoiceChatInternal","LocalPlayerModerated",function()
        add("voice event",{name="LocalPlayerModerated"})
    end)
end
for _,key in ipairs({"UseAudioApi","EnableDefaultVoice","EnableVoiceVolumeControls"})do
    capabilities[key]=read(Voice,key)
    local success,signal=pcall(function()return Voice:GetPropertyChangedSignal(key)end)
    if success then connect(signal,function()add("voice setting",{property=key,value=read(Voice,key)})end)end
end
-- One eligibility read, never a reconnect, opt-in or microphone command.
task.spawn(function()
    local success,value=pcall(function()return Voice:IsVoiceEnabledForUserIdAsync(player.UserId)end)
    capabilities.eligibility=success and tostring(value) or "unavailable"
    local result="unavailable"
    if success then result=value end
    add("eligibility",{available=success,value=result})
end)
task.spawn(function()
    for _,root in ipairs(roots)do
        local success,list=pcall(function()return root:GetDescendants()end)
        capabilities[path(root)]=success and "readable" or "unavailable"
        if success then
            connect(root.DescendantAdded,function(obj)task.defer(function()if alive then inspect(obj,true)end end)end)
            for i,obj in ipairs(list)do
                if not alive then return end
                inspect(obj,false)
                if i%200==0 then task.wait()end
            end
        end
    end
    -- Audio instances can be parented outside Players (e.g. Workspace or SoundService).
    -- One yielded baseline scan; thereafter only new audio nodes are examined.
    local function inspectAudio(obj,isNew)
        if not alive or not audioKeys[obj.ClassName]then return end
        inspect(obj,isNew)
    end
    connect(game.DescendantAdded,function(obj)
        if audioKeys[obj.ClassName]then task.defer(function()inspectAudio(obj,true)end)end
    end)
    local success,list=pcall(function()return game:GetDescendants()end)
    capabilities.audioBaseline=success and "readable" or "unavailable"
    if success then
        for i,obj in ipairs(list)do
            if not alive then return end
            inspectAudio(obj,false)
            if i%200==0 then task.wait()end
        end
    end
    captureState("baseline complete")
    add("ready",{watched=watched})
    if alive then status.Text="ready · activate function, then mute/unmute"end
    while alive do
        task.wait(0.25)
        if alive and recording then captureState("poll")end
    end
end)

