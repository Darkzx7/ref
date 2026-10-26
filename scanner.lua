-- Passive comparison recorder. No hooks, require, input injection, remote sends or state writes.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local player=assert(Players.LocalPlayer,"Run on the client")
local pg=player:WaitForChild("PlayerGui")
local previous=pg:FindFirstChild("REF_ParkFishingCompare")
if previous then previous:Destroy() end
local alive,recording=true,true
local started=os.clock()
local runId=Http:GenerateGUID(false):gsub("-",""):sub(1,8)
local serial,dropped=0,0
local records,connections,counts,last={},{},{},{}
local rounds={}
local MAX=16000
local function elapsed() return math.floor((os.clock()-started)*1000)/1000 end
local function log(kind,data)
    if not alive or not recording then return end
    if #records>=MAX then dropped+=1;return end
    records[#records+1]={t=elapsed(),kind=kind,data=data}
end
local function connect(signal,fn)
    local c=signal:Connect(fn);connections[#connections+1]=c;return c
end
local function path(o)
    local ok,p=pcall(function() return o:GetFullName() end)
    return ok and p or "removed"
end
local function changed(key,value)
    local ok,s=pcall(Http.JSONEncode,Http,value)
    if ok and last[key]~=s then last[key]=s;log(key,value) end
end
local function candidates(fish)
    local ids={};local now=elapsed()
    for i=#rounds,1,-1 do
        local r=rounds[i]
        if now-r.start>180 then break end
        if (not fish or r.fish==fish) and (not r.ended or now-r.ended<=15) then ids[#ids+1]=r.id end
    end
    return ids
end
local watched=setmetatable({},{__mode="k"})
local eventListeners,inventoryListeners=0,0
local function inspect(o)
    if not o:IsA("RemoteEvent") or watched[o] then return end
    local full=path(o)
    if full=="ReplicatedStorage.Shared.Modules.events.RemoteEvent" then
        watched[o]=true;eventListeners+=1
        connect(o.OnClientEvent,function(event,owner,payload,fish)
            if not recording then return end
            if event=="FishFightStart" and owner==player.Name and type(payload)=="table" then
                if type(payload.id)~="string" or type(payload.fish)~="string" then return end
                if #rounds>=200 then table.remove(rounds,1) end
                rounds[#rounds+1]={id=payload.id,fish=payload.fish,start=elapsed()}
                local skills={}
                for _,key in ipairs({"Power","Line","Breath"}) do
                    if type(payload.skills)=="table" and type(payload.skills[key])=="number" then skills[key]=payload.skills[key] end
                end
                log("round start",{id=payload.id,fish=payload.fish,pattern=tostring(payload.pattern),skills=skills,
                    knownInventory=counts[payload.fish],testMode=payload.testMode==true})
            elseif (event=="FishFightEnd" or event=="FishFightCancel") and owner==player.Name then
                local id
                for i=#rounds,1,-1 do
                    local r=rounds[i]
                    if not r.ended and (event~="FishFightCancel" or not payload or payload==r.id) then
                        r.ended=elapsed();id=r.id;break
                    end
                end
                log("round end",{event=event,id=id,explicitId=type(payload)=="string" and payload or nil})
                task.delay(15,function() log("post-round window",{id=id,seconds=15}) end)
            elseif event=="Effect" and owner=="createFish" and payload==player then
                log("capture effect",{fish=tostring(fish),candidateRounds=candidates(fish)})
            end
        end)
    elseif o.Parent and o.Parent.Name=="DataService" and full:find("_remotes",1,true) then
        watched[o]=true;inventoryListeners+=1
        connect(o.OnClientEvent,function(operation,keys,value)
            if operation~=1 or type(keys)~="table" then return end
            if keys[1]=="fishes" and type(keys[2])=="string" and type(value)=="number" then
                local fish=keys[2];local before=counts[fish];counts[fish]=value
                log("inventory",{fish=fish,before=before,after=value,baselineKnown=before~=nil,
                    delta=before and value-before or nil,candidateRounds=candidates(fish)})
            elseif keys[1]=="fishing" and (keys[2]=="XP" or keys[2]=="TotalXP") and type(value)=="number" then
                log("fishing xp",{field=keys[2],value=value})
            end
        end)
    end
end

local gui=Instance.new("ScreenGui")
gui.Name="REF_ParkFishingCompare";gui.ResetOnSpawn=false;gui.DisplayOrder=1000;gui.Parent=pg
local function make(class,parent,props)
    local o=Instance.new(class);for k,v in pairs(props) do o[k]=v end;o.Parent=parent;return o
end
local frame=make("Frame",gui,{Size=UDim2.fromOffset(300,162),Position=UDim2.new(0,12,0,60),
    BackgroundColor3=Color3.fromRGB(22,22,25),BorderSizePixel=0})
make("UICorner",frame,{CornerRadius=UDim.new(0,9)})
local title=make("TextLabel",frame,{Text="park · passive compare v1",Size=UDim2.new(1,-80,0,34),
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium,TextSize=11,Active=true})
local body=make("Frame",frame,{Size=UDim2.new(1,-20,1,-40),Position=UDim2.fromOffset(10,36),BackgroundTransparency=1})
local status=make("TextLabel",body,{Text="recording...",Size=UDim2.new(1,0,0,65),BackgroundTransparency=1,
    TextWrapped=true,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(200,200,205)})
local noticeUntil=0
local function notice(s) status.Text=s;noticeUntil=os.clock()+6 end
local function button(parent,text,x,y,w,fn)
    local b=make("TextButton",parent,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,28),
        BackgroundColor3=Color3.fromRGB(43,43,47),BorderSizePixel=0,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium,TextSize=11})
    make("UICorner",b,{CornerRadius=UDim.new(0,6)});connect(b.Activated,fn);return b
end
local minimized=false
button(frame,"−",226,3,28,function()
    minimized=not minimized;body.Visible=not minimized;frame.Size=UDim2.fromOffset(300,minimized and 34 or 162)
end)
button(frame,"×",264,3,28,function() gui:Destroy() end)
connect(gui.Destroying,function()
    alive=false;recording=false;for _,c in ipairs(connections) do c:Disconnect() end
end)
local drag,origin,base
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        drag=input;origin=input.Position;base=frame.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if drag and (input==drag or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-origin;frame.Position=UDim2.new(base.X.Scale,base.X.Offset+d.X,base.Y.Scale,base.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input) if input==drag then drag=nil end end)
local pause
pause=button(body,"pause",0,75,88,function()
    if recording then log("pause",{});recording=false
    else recording=true;last={};log("resume",{}) end
    pause.Text=recording and "pause" or "record"
end)
local function export()
    return Http:JSONEncode({version="Park passive compare 1",runId=runId,place=game.PlaceId,
        exported=os.date("!%Y-%m-%dT%H:%M:%SZ"),records=records,dropped=dropped,
        coverage={events=eventListeners,inventory=inventoryListeners},
        note="Passive incoming events, replicated attributes, local tool activation and sampled UI only. No outgoing hooks, remote calls, module loading or game state changes. Tool activation does not prove casting. Candidate rounds are correlations, not server acknowledgements. UI sampling interval 0.2s; only positive known inventory deltas prove an observed count increase."})
end
button(body,"copy",96,75,88,function()
    local ok,err=pcall(function()
        local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
        assert(copy,"clipboard unavailable; use save");copy(export())
    end)
    notice(ok and "copied" or tostring(err))
end)
button(body,"save",192,75,88,function()
    serial+=1
    local name="park-compare-v1-"..os.date("%Y%m%d-%H%M%S").."-"..runId.."-"..serial..".json"
    local ok,err=pcall(function() assert(type(writefile)=="function","writefile unavailable");writefile(name,export()) end)
    notice(ok and ("workspace/"..name) or tostring(err))
end)
local toolsSeen=setmetatable({},{__mode="k"})
local function tool(o)
    if not o:IsA("Tool") or toolsSeen[o] then return end
    toolsSeen[o]=true
    connect(o.Activated,function() log("tool activated",{name=o.Name,path=path(o)}) end)
    connect(o.Equipped,function() log("tool equipped",{name=o.Name}) end)
    connect(o.Unequipped,function() log("tool unequipped",{name=o.Name}) end)
end
connect(player.DescendantAdded,tool)
connect(player.CharacterAdded,function(character)
    log("respawn",{})
    connect(character.ChildAdded,tool)
    for _,o in ipairs(character:GetChildren()) do tool(o) end
end)
if player.Character then
    connect(player.Character.ChildAdded,tool)
    for _,o in ipairs(player.Character:GetChildren()) do tool(o) end
end
for _,o in ipairs(player:GetDescendants()) do tool(o) end
connect(player:GetAttributeChangedSignal("fishingState"),function()
    log("fishing state",{value=tostring(player:GetAttribute("fishingState"))})
end)
log("start",{state=tostring(player:GetAttribute("fishingState"))})
connect(RS.DescendantAdded,inspect)
task.spawn(function()
    for i,o in ipairs(RS:GetDescendants()) do
        if not alive then return end
        inspect(o);if i%300==0 then task.wait() end
    end
end)
local ids=setmetatable({},{__mode="k"});local nextId=0
local function objectId(o)
    if not ids[o] then nextId+=1;ids[o]=nextId end
    return ids[o]
end
local function visible(o)
    while o and o~=pg do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o=o.Parent
    end
    return o==pg
end
local cached,refreshAt={},0
local function sample()
    if os.clock()>=refreshAt then
        cached={};refreshAt=os.clock()+1
        local screen=pg:FindFirstChild("FishFightUI")
        if screen then
            cached[1]=screen
            for _,o in ipairs(screen:GetDescendants()) do
                if #cached>=180 then break end
                if o:IsA("GuiObject") and not o:FindFirstAncestorWhichIsA("ViewportFrame") then cached[#cached+1]=o end
            end
        end
    end
    for _,o in ipairs(cached) do
        if o.Parent then
            local data={id=objectId(o),path=path(o),class=o.ClassName,visible=visible(o)}
            if o:IsA("GuiObject") and data.visible then
                data.position=tostring(o.Position);data.size=tostring(o.Size);data.rotation=o.Rotation
                if o:IsA("TextLabel") or o:IsA("TextButton") then data.text=o.Text:sub(1,160) end
            end
            changed("ui:"..data.id,data)
        end
    end
    local screen=pg:FindFirstChild("FishFightUI")
    changed("fight screen",{exists=screen~=nil,visible=screen and visible(screen) or false})
    local temp=workspace:FindFirstChild("Temp")
    local buoy=temp and temp:FindFirstChild(tostring(player.UserId)..".buoy")
    changed("buoy",{exists=buoy~=nil,path=buoy and path(buoy) or nil})
end
task.spawn(function()
    while alive do
        if recording and #records<MAX then
            local ok,err=pcall(sample)
            if not ok then changed("sample error",{message=tostring(err)}) end
        end
        if os.clock()>=noticeUntil then
            status.Text=(recording and "recording" or "paused").." · "..#records.." records\n"
                ..eventListeners.." game / "..inventoryListeners.." inventory listeners"
                ..(#records>=MAX and "\nlog full · save now" or "\nkeep recording 15s after the last catch")
        end
        task.wait(0.2)
    end
end)
