-- Park fishing diagnostic: observes manual play; no remote replay or input hooks.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "Run this scanner on the client")
local pg = player:WaitForChild("PlayerGui")
local previous = pg:FindFirstChild("REF_ParkFishingScanner")
if previous then previous:Destroy() end
local alive, recording, started = true, false, os.clock()
local records, connections, last = {}, {}, {}
local dropped, watched, totalRemotes = 0, 0, 0
local MAX = 6000
local status
local function path(o)
    local ok, value = pcall(function() return o:GetFullName() end)
    return ok and value or "removed"
end
local function matches(name)
    name = name:lower()
    for _, word in ipairs({"fish", "rod", "buoy", "catch", "reel", "strike", "pesca", "bait"}) do
        if name:find(word, 1, true) then return true end
    end
    return false
end
local function encode(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    local kind = typeof(value)
    if kind == "nil" then return {type="nil"} end
    if kind == "boolean" then return value end
    if kind == "number" then
        return value == value and math.abs(value) < math.huge and value or tostring(value)
    end
    if kind == "string" then return value:sub(1, 400) end
    if kind == "Instance" then return {type=kind, path=path(value), class=value.ClassName} end
    if kind == "buffer" then
        local length = buffer.len(value)
        local bytes = {}
        for i=0, math.min(length, 256)-1 do bytes[#bytes+1]=string.format("%02x", buffer.readu8(value,i)) end
        return {type=kind,length=length,hex=table.concat(bytes),truncated=length>256}
    end
    if kind ~= "table" then return {type=kind,value=tostring(value)} end
    if depth >= 4 or seen[value] then return {type="table",truncated=true} end
    seen[value]=true
    local entries, count = {}, 0
    for k,v in pairs(value) do
        count+=1
        if count>30 then break end
        entries[#entries+1]={key=encode(k,depth+1,seen),value=encode(v,depth+1,seen)}
    end
    seen[value]=nil
    return {type="table",entries=entries,truncated=count>30}
end
local function add(kind, data)
    if not alive or not recording then return end
    if #records >= MAX then dropped+=1; return end
    records[#records+1]={t=math.floor((os.clock()-started)*1000)/1000,kind=kind,data=data}
end
local function connect(signal, callback)
    local c=signal:Connect(callback); connections[#connections+1]=c; return c
end
local function changed(key, value)
    local ok, signature=pcall(Http.JSONEncode,Http,value)
    if ok and last[key]~=signature then last[key]=signature;add(key,value) end
end
local function attrs(o) return encode(o:GetAttributes()) end
local function round(n) return math.floor(n*1000+0.5)/1000 end
local function pair(v) return {round(v.X),round(v.Y)} end
local function visible(o)
    while o and o~=pg do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o=o.Parent
    end
    return true
end
local function uiState(o)
    local data={path=path(o),class=o.ClassName,attributes=attrs(o)}
    if o:IsA("ScreenGui") then data.enabled=o.Enabled end
    if o:IsA("GuiObject") then
        data.visible=visible(o); data.position=pair(o.AbsolutePosition); data.size=pair(o.AbsoluteSize)
        data.scalePosition=tostring(o.Position);data.scaleSize=tostring(o.Size)
        data.color=tostring(o.BackgroundColor3)
    end
    if o:IsA("TextLabel") or o:IsA("TextButton") then data.text=o.Text:sub(1,200) end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then data.image=o.Image end
    return data
end

local gui=Instance.new("ScreenGui")
gui.Name="REF_ParkFishingScanner"; gui.ResetOnSpawn=false; gui.DisplayOrder=1000;gui.Parent=pg
local function make(class, parent, props)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent;return o
end
local frame=make("Frame",gui,{Size=UDim2.fromOffset(300,178),Position=UDim2.new(0,16,0.25,0),
    BackgroundColor3=Color3.fromRGB(20,20,22),BorderSizePixel=0,Active=true})
make("UICorner",frame,{CornerRadius=UDim.new(0,10)})
local title=make("TextLabel",frame,{Text="park · fishing scan",Size=UDim2.new(1,-82,0,38),Position=UDim2.fromOffset(12,0),
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium,TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Active=true})
local body=make("Frame",frame,{Position=UDim2.fromOffset(10,42),Size=UDim2.new(1,-20,1,-50),BackgroundTransparency=1})
status=make("TextLabel",body,{Text="ready · record a manual fishing cycle",Size=UDim2.new(1,0,0,44),BackgroundTransparency=1,
    TextWrapped=true,TextColor3=Color3.fromRGB(190,190,195),TextSize=11,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left})
local function button(parent, text, x,y,w,callback)
    local b=make("TextButton",parent,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,30),
        BackgroundColor3=Color3.fromRGB(40,40,44),BorderSizePixel=0,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium,TextSize=11})
    make("UICorner",b,{CornerRadius=UDim.new(0,6)})
    connect(b.Activated,callback);return b
end
local noticeUntil=0
local function notice(text) status.Text=text;noticeUntil=os.clock()+5 end
local minimized=false
button(frame,"−",222,4,30,function()
    minimized=not minimized;body.Visible=not minimized;frame.Size=UDim2.fromOffset(300,minimized and 38 or 178)
end)
button(frame,"×",258,4,30,function() gui:Destroy() end)
connect(gui.Destroying,function()
    alive=false;recording=false
    for _,c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
end)
local dragging, origin, position, dragInput
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true;origin=input.Position;position=frame.Position;dragInput=input
    end
end)
connect(UIS.InputChanged,function(input)
    if dragging and (input==dragInput or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-origin
        frame.Position=UDim2.new(position.X.Scale,position.X.Offset+d.X,position.Y.Scale,position.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input) if input==dragInput then dragging=false end end)
local inventory={modules={},remotes={},truncated=false}
local function export()
    return Http:JSONEncode({version="Park fishing scan 1",place=game.PlaceId,exported=os.date("!%Y-%m-%dT%H:%M:%SZ"),
        note="Manual observations only. No outgoing interception, remote replay, module execution or synthetic input. Incoming events do not prove server success.",
        records=records,dropped=dropped,inventory=inventory,incomingRemotesWatched=watched,remoteCount=totalRemotes})
end
local recordButton
recordButton=button(body,"record",0,50,88,function()
    if recording then add("recording",{active=false});recording=false
    else
        recording=true;last={};add("recording",{active=true})
    end
    recordButton.Text=recording and "pause" or "record"
end)
button(body,"copy",96,50,88,function()
    local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
    local ok,err=pcall(function() assert(copy,"clipboard unavailable; use save");copy(export()) end)
    notice(ok and "copied · send the full log" or tostring(err):sub(1,180))
end)
button(body,"save",192,50,88,function()
    local filename="park-fishing-"..os.date("%Y%m%d-%H%M%S").."-"..tostring(math.floor(os.clock()*1000))..".json"
    local ok,err=pcall(function()
        assert(type(writefile)=="function","executor does not support writefile")
        writefile(filename,export())
    end)
    notice(ok and ("workspace/"..filename) or tostring(err):sub(1,180))
end)
make("TextLabel",body,{Text="record → fish manually → pause → save",Position=UDim2.fromOffset(0,88),Size=UDim2.new(1,0,0,25),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(150,150,155),TextSize=10,Font=Enum.Font.Gotham})

local seenRemotes=setmetatable({},{__mode="k"})
local function inspect(o)
    if o:IsA("ModuleScript") and matches(path(o)) and #inventory.modules<150 then
        inventory.modules[#inventory.modules+1]=path(o)
    end
    if not (o:IsA("RemoteEvent") or o:IsA("UnreliableRemoteEvent") or o:IsA("RemoteFunction")) or seenRemotes[o] then return end
    seenRemotes[o]=true;totalRemotes+=1
    if #inventory.remotes<300 then inventory.remotes[#inventory.remotes+1]={path=path(o),class=o.ClassName}
    else inventory.truncated=true end
    if o:IsA("RemoteFunction") or watched>=128 then return end
    watched+=1
    connect(o.OnClientEvent,function(...)
        if not recording or not alive then return end
        local args=table.pack(...)
        local ok,data=pcall(encode,args)
        if ok then add("incoming",{remote=path(o),args=data,n=args.n}) end
    end)
end
connect(RS.DescendantAdded,inspect)
task.spawn(function()
    for i,o in ipairs(RS:GetDescendants()) do
        if not alive then return end
        inspect(o)
        if i%250==0 then task.wait() end
    end
end)
local function inputLog(phase,input,processed)
    if not recording or input.UserInputType==Enum.UserInputType.MouseMovement then return end
    local p=input.Position
    local hit=pg:GetGuiObjectsAtPosition(p.X,p.Y)
    local ui={}
    for _,o in ipairs(hit) do
        if o:IsDescendantOf(gui) then return end
        if #ui<6 then ui[#ui+1]=path(o) end
    end
    add("input",{phase=phase,type=input.UserInputType.Name,key=input.KeyCode.Name,processed=processed,position={p.X,p.Y},ui=ui})
end
connect(UIS.InputBegan,function(i,p) inputLog("begin",i,p) end)
connect(UIS.InputEnded,function(i,p) inputLog("end",i,p) end)

local function sample()
    changed("player attributes",attrs(player))
    local character=player.Character
    if character then
        changed("character attributes",attrs(character))
        local tools={}
        for _,o in ipairs(character:GetChildren()) do
            if o:IsA("Tool") then tools[#tools+1]={path=path(o),attributes=attrs(o)} end
        end
        changed("equipped tools",tools)
    end
    local roots, present={},{}
    for _,screen in ipairs(pg:GetChildren()) do
        if screen~=gui then
            roots[#roots+1]={name=screen.Name,class=screen.ClassName,visible=visible(screen)}
            local candidates={}
            if matches(screen.Name) then candidates=screen:GetDescendants();table.insert(candidates,1,screen)
            else
                -- Find renamed fishing widgets nested inside a general HUD.
                for _,o in ipairs(screen:GetDescendants()) do
                    if matches(o.Name) then
                        candidates[#candidates+1]=o
                        for _,child in ipairs(o:GetDescendants()) do if #candidates<220 then candidates[#candidates+1]=child end end
                    end
                end
            end
            local count=0
            for _,o in ipairs(candidates) do
                if count>=220 then break end
                if o:IsA("GuiObject") or o:IsA("ScreenGui") then
                    local key="ui:"..path(o)
                    if not present[key] then present[key]=true;count+=1;changed(key,uiState(o)) end
                end
            end
        end
    end
    changed("screens",roots)
    for key in pairs(last) do
        if key:sub(1,3)=="ui:" and not present[key] then add("removed",{path=key:sub(4)});last[key]=nil end
    end
    local temp=workspace:FindFirstChild("Temp")
    local objects={}
    if temp then
        for _,o in ipairs(temp:GetChildren()) do
            if matches(o.Name) and #objects<60 then
                local data={path=path(o),class=o.ClassName,attributes=attrs(o)}
                if o:IsA("BasePart") then data.position=tostring(o.Position) end
                objects[#objects+1]=data
            end
        end
    end
    changed("fishing objects",objects)
end
task.spawn(function()
    while alive do
        if recording and #records<MAX then
            local ok,err=pcall(sample)
            if not ok then changed("sample error",{message=tostring(err)}) end
        end
        if os.clock()>=noticeUntil then
            status.Text=(recording and "recording" or "paused").." · "..#records.." records · "..watched.." event listeners"
                ..(#records>=MAX and "\nlog full · pause and save" or "")
        end
        task.wait(0.15)
    end
end)
