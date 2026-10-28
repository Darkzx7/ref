-- REF voice observer 1. Read-only diagnostics; no hooks, audio capture or remote replay.
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
local seen=setmetatable({},{__mode="k"})
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
    if value==nil then return "nil" end
    return tostring(value):sub(1,180)
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
end
local function snapshot(obj,kind)
    local data={path=path(obj),class=obj.ClassName}
    if obj:IsA("AudioDeviceInput") then
        for _,key in ipairs({"Muted","Active","IsReady","Volume","Player"})do data[key]=read(obj,key) end
    else
        for _,key in ipairs({"Visible","AbsolutePosition","AbsoluteSize"})do data[key]=read(obj,key)end
        if obj:IsA("ImageButton") or obj:IsA("ImageLabel") then data.Image=read(obj,"Image")end
        -- Never read text boxes, chat messages or microphone samples.
        if obj:IsA("TextButton") then data.Text=read(obj,"Text")end
        local parent=obj.Parent
        while parent and parent~=game do
            if parent:IsA("LayerCollector") then data.layerEnabled=read(parent,"Enabled");break end
            parent=parent.Parent
        end
    end
    add(kind,data)
end
local function inspect(obj,isNew)
    if not alive or seen[obj] or obj:IsDescendantOf(gui) or watched>=300 then return end
    local audio=obj:IsA("AudioDeviceInput")
    if audio then
        local ok,owner=pcall(function()return obj.Player end)
        if not ok or owner~=player then return end
    elseif not (obj:IsA("GuiButton") and (isNew or related(obj)))
        and not (obj:IsA("LayerCollector") and (isNew or related(obj)))
        and not (related(obj) and (obj:IsA("ImageLabel") or obj:IsA("Frame"))) then return end
    watched+=1
    local bucket={}
    seen[obj]=bucket
    local last={}
    snapshot(obj,isNew and "added" or "baseline")
    local keys=audio and {"Muted","Active","IsReady","Volume","Player"}
        or obj:IsA("LayerCollector") and {"Enabled","Name"}
        or {"Visible","Image","ImageRectOffset","ImageRectSize","Text","Name"}
    for _,key in ipairs(keys)do
        local ok,signal=pcall(function()return obj:GetPropertyChangedSignal(key)end)
        if ok then
            last[key]=Http:JSONEncode(read(obj,key))
            connect(signal,function()
                local value=read(obj,key)
                local encoded=Http:JSONEncode(value)
                if encoded~=last[key] then
                    last[key]=encoded
                    add("property",{path=path(obj),property=key,value=value})
                end
            end,bucket)
        end
    end
    if obj:IsA("GuiButton") then
        connect(obj.Activated,function()snapshot(obj,"clicked")end,bucket)
    end
    connect(obj.Destroying,function()
        add("removed",{path=path(obj)})
        for _,c in ipairs(bucket)do c:Disconnect()end
        seen[obj]=nil;watched-=1
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
local title=label("voice observer",12,0,210,34);title.TextXAlignment=Enum.TextXAlignment.Left
local status=label("recording · activate the other script",12,38,286,34)
local function button(text,x,y,w,fn)
    local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,28)
    b.BackgroundColor3=Color3.fromRGB(39,40,45);b.BorderSizePixel=0;b.Font=Enum.Font.Gotham
    b.TextSize=11;b.TextColor3=Color3.fromRGB(240,240,240);b.Text=text;b.Parent=panel
    connect(b.Activated,fn);return b
end
local function export()
    return Http:JSONEncode({version="REF voice observer 1",place=game.PlaceId,
        exported=os.date("!%Y-%m-%dT%H:%M:%SZ"),dropped=dropped,capabilities=capabilities,records=records,
        note="Read-only local state/UI observations. No audio, input interception or remote replay. Does not prove suspension bypass or identify internal function calls."})
end
local controls={status}
local pauseButton
pauseButton=button("pause",12,80,88,function()
    if recording then add("marker",{label="paused"});recording=false
    else recording=true;add("marker",{label="resumed"});for obj in pairs(seen)do snapshot(obj,"resume snapshot")end end
    pauseButton.Text=recording and "pause" or "record"
    status.Text=(recording and "recording" or "paused").." · "..#records.." records"
end)
table.insert(controls,pauseButton)
table.insert(controls,button("mark step",110,80,88,function()
    add("marker",{label="manual step"});status.Text="marked · "..#records.." records"
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
        local filename="voice-"..os.date("%Y%m%d-%H%M%S").."-"..Http:GenerateGUID(false):sub(1,8)..".json"
        writefile("True Ref/Logs/"..filename,export())
    end)
    status.Text=success and "saved: workspace/True Ref/Logs/voice-...json" or tostring(err):sub(1,100)
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
    connect(player.DescendantAdded,function(obj)
        if obj:IsA("AudioDeviceInput")then
            inspect(obj,true)
            for _,delay in ipairs({0.2,1})do
                task.delay(delay,function()if alive and obj.Parent then inspect(obj,true)end end)
            end
        end
    end)
    for _,obj in ipairs(player:GetDescendants())do if obj:IsA("AudioDeviceInput")then inspect(obj,false)end end
    add("ready",{watched=watched})
    if alive then status.Text="ready · activate function, then mute/unmute"end
end)
