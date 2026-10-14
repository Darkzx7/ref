-- Mush music recorder: manual play only; no replay, module execution or input simulation.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local PPS=game:GetService("ProximityPromptService")
local Http=game:GetService("HttpService")
local Run=game:GetService("RunService")
local player=Players.LocalPlayer
assert(player,"Run on the client")
local pg=player:WaitForChild("PlayerGui")
local env=type(getgenv)=="function" and getgenv() or _G
local KEY="__REF_MUSH_MUSIC_RECORDER_V1"
local bridge=env[KEY]
if type(bridge)~="table" then bridge={};env[KEY]=bridge end
if type(bridge.close)=="function" then pcall(bridge.close) end
local alive,running,remoteOn=true,false,true
local records,queue,connections={},{},{}
local origin,bytes,dropped=0,0,0
local epoch=0
local LIMIT,MAX_BYTES,MAX_QUEUE=16000,8*1024*1024,256
local note,gui,refresh="ready",nil,nil
local ids=setmetatable({},{__mode="k"});local nextId=0
local function id(obj)
    if not ids[obj] then nextId+=1;ids[obj]=nextId end
    return ids[obj]
end
local function connect(signal,fn)
    local c=signal:Connect(fn);connections[#connections+1]=c;return c
end
local function round(n) return math.floor(n*10000+.5)/10000 end
local function stamp()return round(os.clock()-origin)end
local function describe(obj)
    local parts,at={},obj
    for _=1,48 do
        if not at or at==game then break end
        table.insert(parts,1,at.Name);at=at.Parent
    end
    return {id=id(obj),class=obj.ClassName,path=table.concat(parts,"."),parts=parts}
end
local function vec(v)return {round(v.X),round(v.Y),round(v.Z)}end
-- Snapshots must be taken before the original call reuses its BLINK buffer.
-- This function deliberately does not inspect Instances, yield, or call remotes.
local function snapshot(v,depth,seen,budget)
    local kind=typeof(v)
    if kind=="buffer" then
        local length=buffer.len(v)
        return {__musicBuffer=true,length=length,bytes=buffer.readstring(v,0,math.min(length,65536))}
    end
    if kind=="string" and #v>65536 then return {__text=v:sub(1,65536),truncated=true,length=#v} end
    if kind~="table" then return v end
    if seen[v] then return seen[v] end
    if depth>=7 then return {truncated=true} end
    local copy={};seen[v]=copy
    for k,value in next,v do
        budget.n+=1
        if budget.n>1024 then copy.__truncated=true;break end
        copy[k]=snapshot(value,depth+1,seen,budget)
    end
    return copy
end
local function encode(v,depth,seen,budget)
    depth,seen,budget=depth or 0,seen or {},budget or {n=0}
    local kind=typeof(v)
    if kind=="nil" then return {type="nil"} end
    if kind=="boolean" or kind=="string" then return v end
    if kind=="number" then return (v==v and math.abs(v)~=math.huge) and v or tostring(v) end
    if kind=="Instance" then return describe(v) end
    if kind=="Vector3" then return {type=kind,value=vec(v)} end
    if kind=="Vector2" then return {type=kind,value={v.X,v.Y}} end
    if kind=="Color3" then return {type=kind,value={v.R,v.G,v.B}} end
    if kind=="CFrame" then return {type=kind,value={v:GetComponents()}} end
    if kind=="EnumItem" then return {type=kind,value=tostring(v)} end
    if kind~="table" then return {type=kind,value=tostring(v)} end
    if rawget(v,"__musicBuffer")==true then
        return {type="buffer",length=v.length,truncated=#v.bytes<v.length,
            hex=v.bytes:gsub(".",function(c)return string.format("%02x",string.byte(c))end)}
    end
    if seen[v] then return {type="reference"} end
    if depth>=9 then return {type="table",truncated=true} end
    seen[v]=true
    local entries={}
    for k,value in next,v do
        budget.n+=1
        if budget.n>4096 then return {type="table",entries=entries,truncated=true} end
        entries[#entries+1]={key=encode(k,depth+1,seen,budget),value=encode(value,depth+1,seen,budget)}
    end
    return {type="table",entries=entries}
end
local function append(kind,data,time)
    if not running or not alive then return end
    local row={t=time or stamp(),kind=kind,data=data}
    local ok,json=pcall(Http.JSONEncode,Http,row)
    if not ok then dropped+=1;return end
    if #records>=LIMIT or bytes+#json>MAX_BYTES then
        dropped+=1;running=false;epoch+=1;note="log full - save before restarting";return
    end
    records[#records+1]=row;bytes+=#json
end
local function enqueue(remote,method,args,direction)
    if not running or not alive or not remoteOn then return end
    if #queue>=MAX_QUEUE then dropped+=1;return end
    queue[#queue+1]={t=stamp(),remote=remote,method=method,direction=direction,n=args.n,args=snapshot(args,0,{}, {n=0})}
end
local function drain(limit)
    local batch=queue;queue={}
    local count=math.min(#batch,limit or #batch)
    for i=count+1,#batch do queue[#queue+1]=batch[i] end
    for i=1,count do
        local r=batch[i]
        local ok,data=pcall(function()
            return {remote=describe(r.remote),method=r.method,direction=r.direction,n=r.n,args=encode(r.args)}
        end)
        if ok then append("remote",data,r.t) else dropped+=1 end
    end
end
local skipRemotes=setmetatable({},{__mode="k"})
local sink=function(obj,method,...)
    if not running or not alive or not remoteOn or skipRemotes[obj] then return end
    enqueue(obj,method,table.pack(...),"outgoing")
end
bridge.sink=sink
local function installHook()
    if bridge.installed then return true end
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return false end
    local ok,err=pcall(function()
        local old
        local function handler(self,...)
            local worked,method=pcall(getnamecallmethod)
            if worked and (method=="FireServer" or method=="InvokeServer") then
                local callback=bridge.sink
                if callback then pcall(callback,self,method,...) end
            end
            return old(self,...)
        end
        old=hookmetamethod(game,"__namecall",type(newcclosure)=="function" and newcclosure(handler) or handler)
        bridge.installed=true
    end)
    if not ok then bridge.error=tostring(err) end
    return ok and bridge.installed==true
end
local words={"music","instrument","piano","guitar","drum","rhythm","song","note","beat","violin","flute","sax","ukulele","keyboard"}
local function named(obj)
    local name=obj.Name:lower()
    for _,word in ipairs(words) do if name:find(word,1,true) then return true end end
    return false
end
local function relevant(obj)
    local at=obj
    for _=1,16 do
        if not at or at==game or at==pg or at==workspace or at==RS then break end
        if named(at) then return true end
        at=at.Parent
    end
    return false
end
local function visible(obj)
    local at=obj
    while at and at~=pg do
        if at:IsA("GuiObject") and not at.Visible then return false end
        if at:IsA("ScreenGui") and not at.Enabled then return false end
        at=at.Parent
    end
    return at==pg
end
local function ours(obj)return gui and (obj==gui or obj:IsDescendantOf(gui))end
local uiNodes,uiSeen,uiLast={},{},{}
local uiRoots=setmetatable({},{__mode="k"})
local uiSkipped=0
local sounds,soundSeen,soundLast={},{},{}
local buttons=setmetatable({},{__mode="k"})
local panels=setmetatable({},{__mode="k"})
local toolsSeen=setmetatable({},{__mode="k"})
local remoteSeen=setmetatable({},{__mode="k"})
local inputIds=setmetatable({},{__mode="k"})
local remoteCount=0
local function trackUI(obj)
    if not obj:IsA("GuiObject") or ours(obj) or uiSeen[obj] then return end
    local at=obj
    while at and at~=pg do
        if at.Name:lower():find("chat",1,true) then return end
        at=at.Parent
    end
    if #uiNodes>=320 then uiSkipped+=1;return end
    uiSeen[obj]=true;uiNodes[#uiNodes+1]=obj
end
local function addTree(root)
    uiRoots[root]=true
    trackUI(root)
    for _,obj in ipairs(root:GetDescendants()) do trackUI(obj) end
end
local function uiRow(obj)
    local p,s=obj.AbsolutePosition,obj.AbsoluteSize
    local pos,size=obj.Position,obj.Size
    local color=obj.BackgroundColor3
    local row={id=id(obj),rect={round(p.X),round(p.Y),round(s.X),round(s.Y)},visible=visible(obj),
        position={pos.X.Scale,pos.X.Offset,pos.Y.Scale,pos.Y.Offset},size={size.X.Scale,size.X.Offset,size.Y.Scale,size.Y.Offset},
        rotation=obj.Rotation,z=obj.ZIndex,color={color.R,color.G,color.B},alpha=obj.BackgroundTransparency}
    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        row.text=obj.Text:sub(1,200);row.textColor={obj.TextColor3.R,obj.TextColor3.G,obj.TextColor3.B}
    end
    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then row.image=obj.Image;row.imageColor={obj.ImageColor3.R,obj.ImageColor3.G,obj.ImageColor3.B} end
    return row
end
local function sampleUI()
    local changes={}
    for i=#uiNodes,1,-1 do
        local obj=uiNodes[i]
        if not obj.Parent or not obj:IsDescendantOf(pg) then
            changes[#changes+1]={id=id(obj),removed=true}
            uiSeen[obj]=nil;uiLast[obj]=nil;table.remove(uiNodes,i)
        else
            local row=uiRow(obj)
            local key=Http:JSONEncode(row)
            if key~=uiLast[obj] then
                if not uiLast[obj] then row.object=describe(obj);row.attributes=encode(obj:GetAttributes());row.parent=obj.Parent and id(obj.Parent) end
                changes[#changes+1]=row;uiLast[obj]=key
            end
        end
        if #changes>=24 then append("ui",changes);changes={} end
    end
    if #changes>0 then append("ui",changes) end
end
local function watchUI(obj)
    if ours(obj) then return end
    if not panels[obj] and (obj:IsA("ScreenGui") or (obj:IsA("GuiObject") and obj.Parent and obj.Parent:IsA("ScreenGui"))) then
        panels[obj]=true
        local property=obj:IsA("ScreenGui") and "Enabled" or "Visible"
        connect(obj:GetPropertyChangedSignal(property),function()
            if running and obj[property] then
                append("panel opened",{object=describe(obj)})
                addTree(obj)
            end
        end)
    end
    if obj:IsA("GuiObject") then
        local selected=false
        local at=obj.Parent
        while at and at~=pg do
            if at.Name:lower():find("chat",1,true) then return end
            if uiRoots[at] then selected=true end
            at=at.Parent
        end
        if relevant(obj) or selected then trackUI(obj) end
        if running and obj.Parent and obj.Parent:IsA("ScreenGui") then addTree(obj) end
    end
    if obj:IsA("GuiButton") and not buttons[obj] then
        buttons[obj]=true
        connect(obj.Activated,function()
            if not running or UIS:GetFocusedTextBox() then return end
            append("button",{object=describe(obj)})
            local parent=obj.Parent
            if parent and parent~=pg then addTree(parent) end
        end)
    end
end
local function watchRemote(obj)
    if remoteSeen[obj] or not (obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent") or obj:IsA("RemoteFunction")) then return end
    remoteSeen[obj]=true
    local path=obj:GetFullName():lower()
    if path:find("chat",1,true) then skipRemotes[obj]=true;return end
    if obj:IsA("RemoteFunction") then return end
    if remoteCount>=192 then return end
    remoteCount+=1
    connect(obj.OnClientEvent,function(...)
        if running and remoteOn then pcall(enqueue,obj,"OnClientEvent",table.pack(...),"incoming") end
    end)
end
local function trackSound(obj)
    if obj:IsA("Sound") and not soundSeen[obj] and #sounds<96 then
        soundSeen[obj]=true;sounds[#sounds+1]=obj
    end
end
local function sampleSounds()
    for i=#sounds,1,-1 do
        local obj=sounds[i]
        if not obj.Parent then soundSeen[obj]=nil;soundLast[obj]=nil;table.remove(sounds,i)
        elseif obj.IsPlaying or soundLast[obj] then
            local row={id=id(obj),playing=obj.IsPlaying,position=round(obj.TimePosition),speed=obj.PlaybackSpeed,length=round(obj.TimeLength),soundId=obj.SoundId,volume=obj.Volume}
            local key=Http:JSONEncode(row)
            if key~=soundLast[obj] then
                if not soundLast[obj] then row.object=describe(obj) end
                soundLast[obj]=key;append("sound",row)
            end
        end
    end
end
local function context()
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return {root=root and {root.CFrame:GetComponents()},camera=workspace.CurrentCamera and {workspace.CurrentCamera.CFrame:GetComponents()}}
end
local function watchTool(obj)
    if not obj:IsA("Tool") or toolsSeen[obj] then return end
    toolsSeen[obj]=true
    for _,event in ipairs({"Equipped","Unequipped","Activated","Deactivated"}) do
        connect(obj[event],function()append("tool "..event:lower(),{object=describe(obj),attributes=encode(obj:GetAttributes())})end)
    end
end
local function discover(token)
    for _,root in ipairs({RS,pg,workspace,game:GetService("SoundService"),player}) do
        for i,obj in ipairs(root:GetDescendants()) do
            if not alive or not running or token~=epoch then return end
            if root==pg then watchUI(obj) end
            if root==RS then
                watchRemote(obj)
                if obj:IsA("ModuleScript") and relevant(obj) then append("module",{object=describe(obj),attributes=encode(obj:GetAttributes())}) end
            end
            if root==player then watchTool(obj) end
            if obj:IsA("Sound") then trackSound(obj) end
            if root==workspace and named(obj) and (obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("ProximityPrompt")) then
                local row={object=describe(obj),attributes=encode(obj:GetAttributes())}
                if obj:IsA("BasePart") then row.position=vec(obj.Position);row.size=vec(obj.Size) end
                append("instrument object",row)
            end
            if i%160==0 then task.wait() end
        end
    end
    if running and token==epoch then append("discovery complete",{uiNodes=#uiNodes,sounds=#sounds,incomingRemotes=remoteCount}) end
end
connect(pg.DescendantAdded,function(obj)
    watchUI(obj)
    if running and obj:IsA("ScreenGui") and obj~=gui then
        append("screen added",{object=describe(obj),enabled=obj.Enabled})
        task.defer(function()if alive and running and obj.Parent then addTree(obj) end end)
    end
end)
connect(RS.DescendantAdded,function(obj)watchRemote(obj);trackSound(obj)end)
connect(workspace.DescendantAdded,function(obj)trackSound(obj)end)
connect(player.DescendantAdded,watchTool)
connect(PPS.PromptTriggered,function(prompt,who)
    if running and (who==nil or who==player) then
        append("prompt",{object=describe(prompt),action=prompt.ActionText,context=context()})
    end
end)
local function hitAt(x,y)
    local result={}
    local ok,list=pcall(pg.GetGuiObjectsAtPosition,pg,x,y)
    if ok then
        for _,obj in ipairs(list) do
            if ours(obj) then return nil,true end
            if #result<8 then result[#result+1]=describe(obj) end
            if relevant(obj) then trackUI(obj);if obj.Parent then addTree(obj.Parent) end end
        end
    end
    return result,false
end
local function inputEvent(kind,input,processed)
    if not running or UIS:GetFocusedTextBox() then return end
    local t=input.UserInputType
    if t~=Enum.UserInputType.Keyboard and t~=Enum.UserInputType.Touch and t~=Enum.UserInputType.MouseButton1
        and t~=Enum.UserInputType.MouseButton2 and not tostring(t):find("Gamepad",1,true) then return end
    local hits,isOwn
    if t==Enum.UserInputType.Touch or t==Enum.UserInputType.MouseButton1 or t==Enum.UserInputType.MouseButton2 then
        hits,isOwn=hitAt(input.Position.X,input.Position.Y)
        if isOwn then return end
    end
    if kind=="input began" then inputIds[input]=id(input) end
    local inputId=inputIds[input] or id(input)
    append(kind,{id=inputId,key=tostring(input.KeyCode),device=tostring(t),processed=processed==true,position=vec(input.Position),targets=hits})
    if kind=="input ended" then inputIds[input]=nil end
end
connect(UIS.InputBegan,function(input,p)inputEvent("input began",input,p)end)
connect(UIS.InputEnded,function(input,p)inputEvent("input ended",input,p)end)
-- Small standalone UI.
gui=Instance.new("ScreenGui");gui.Name="MushMusicRecorder";gui.ResetOnSpawn=false;gui.DisplayOrder=999;gui.Parent=pg
local function create(class,props,parent)
    local obj=Instance.new(class);for k,v in pairs(props)do obj[k]=v end;obj.Parent=parent;return obj
end
local function corner(obj)create("UICorner",{CornerRadius=UDim.new(0,7)},obj)end
local frame=create("Frame",{Size=UDim2.fromOffset(304,238),Position=UDim2.new(.5,-152,.2,0),BackgroundColor3=Color3.fromRGB(22,23,26),BorderSizePixel=0},gui);corner(frame)
local title=create("TextLabel",{Text="music recorder",TextSize=14,Font=Enum.Font.GothamMedium,TextColor3=Color3.fromRGB(235,235,240),BackgroundTransparency=1,Active=true,TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(12,0),Size=UDim2.fromOffset(208,36)},frame)
local body=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(12,40),Size=UDim2.fromOffset(280,190)},frame)
local label=create("TextLabel",{Text="ready",TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(190,195,205),BackgroundTransparency=1,Size=UDim2.fromOffset(280,54)},body)
local function button(text,x,y,w,parent)
    local b=create("TextButton",{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,32),BackgroundColor3=Color3.fromRGB(42,44,49),TextColor3=Color3.fromRGB(235,235,240),TextSize=12,Font=Enum.Font.GothamMedium,BorderSizePixel=0},parent or body);corner(b);return b
end
local start=button("start",0,60,136);local mark=button("mark",144,60,136)
local copy=button("copy",0,100,136);local save=button("save",144,100,136)
local remoteButton=button("remotes: on",0,140,280)
local mini=button("-",228,2,30,frame);local close=button("x",264,2,30,frame)
refresh=function()
    if not alive then return end
    label.Text=string.format("%s | %d records | %.1f MB\n%s",running and "recording" or "stopped",#records,bytes/1048576,note)
    start.Text=running and "stop" or "start"
end
local function report(text)note=text;refresh()end
local function pause()
    if running then pcall(sampleUI);pcall(sampleSounds);drain();append("stopped",{}) end
    running=false;epoch+=1;refresh()
end
local function export()
    return Http:JSONEncode({version="Mush music recorder 1",place=game.PlaceId,exported=os.date("!%Y-%m-%dT%H:%M:%SZ"),
        outgoingHook=bridge.installed==true,hookError=bridge.error,remotesEnabled=remoteOn,dropped=dropped,uiNodesOmitted=uiSkipped,records=records,
        note="Passive manual recording. UI sampled up to 20 Hz; sounds 5 Hz. Hook preserves calls and results; direct/cached calls may be missed. Incoming RemoteFunction callbacks are not replaced. No replay or inferred server success."})
end
connect(start.Activated,function()
    if running then pause();report("stopped - copy or save");return end
    if #records>=LIMIT or bytes>=MAX_BYTES-65536 then report("log full - save and run again");return end
    if #records==0 then origin=os.clock() end
    running=true;epoch+=1;uiLast={};soundLast={}
    local token=epoch
    local hooked=remoteOn and installHook()
    append("started",{place=game.PlaceId,serverTime=workspace:GetServerTimeNow(),context=context(),hook=hooked==true,remotes=remoteOn})
    for _,obj in ipairs(pg:GetChildren()) do
        if obj~=gui then append("screen",{object=describe(obj),enabled=obj:IsA("ScreenGui") and obj.Enabled or nil}) end
    end
    task.spawn(function()local ok,err=pcall(discover,token);if not ok then append("discovery error",{error=tostring(err)})end end)
    report(hooked and "open the instrument and play manually" or "UI/input scan active; outgoing hook unavailable/off")
end)
connect(mark.Activated,function()
    append("marker",context());pcall(sampleUI);report("marked")
end)
connect(remoteButton.Activated,function()
    remoteOn=not remoteOn;remoteButton.Text=remoteOn and "remotes: on" or "remotes: off"
    if remoteOn and running then installHook() end
    append("remote capture",{enabled=remoteOn});report(remoteOn and "remote capture enabled" or "UI and inputs only")
end)
connect(copy.Activated,function()
    pause()
    local clip=setclipboard or toclipboard
    if type(clip)~="function" then report("clipboard unavailable - use save");return end
    local ok,err=pcall(function()clip(export())end)
    report(ok and "copied; recording stopped" or tostring(err):sub(1,110))
end)
connect(save.Activated,function()
    pause()
    if type(writefile)~="function" then report("writefile unavailable - use copy");return end
    local folder="True Ref/Scans/music/"
    if type(makefolder)=="function" then
        for _,dir in ipairs({"True Ref","True Ref/Scans","True Ref/Scans/music"})do pcall(makefolder,dir)end
    end
    local name="music_"..os.date("%Y%m%d_%H%M%S").."_"..math.floor(os.clock()*1000)..".json"
    local ok,err=pcall(function()writefile(folder..name,export())end)
    if not ok then folder="";ok,err=pcall(function()writefile(name,export())end)end
    report(ok and ("saved: "..folder..name) or tostring(err):sub(1,110))
end)
local small=false
connect(mini.Activated,function()small=not small;body.Visible=not small;frame.Size=UDim2.fromOffset(304,small and 36 or 238);mini.Text=small and "+" or "-"end)
local drag,dragStart,frameStart
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then drag=input;dragStart=input.Position;frameStart=frame.Position end
end)
connect(UIS.InputChanged,function(input)
    if not drag then return end
    if drag.UserInputType==Enum.UserInputType.Touch and input~=drag then return end
    if drag.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local d=input.Position-dragStart
    frame.Position=UDim2.new(frameStart.X.Scale,frameStart.X.Offset+d.X,frameStart.Y.Scale,frameStart.Y.Offset+d.Y)
end)
connect(UIS.InputEnded,function(input)if input==drag then drag=nil end end)
local function shutdown()
    if not alive then return end
    running=false;alive=false;epoch+=1
    if bridge.sink==sink then bridge.sink=nil end
    for _,c in ipairs(connections)do c:Disconnect()end
    gui:Destroy()
end
bridge.close=shutdown
connect(close.Activated,shutdown);connect(gui.Destroying,shutdown)
local uiTime,soundTime,statusTime=0,0,0
connect(Run.Heartbeat,function()
    if not running or not alive then return end
    local now=os.clock()
    drain(24)
    if now-uiTime>=.05 then
        uiTime=now;local ok,err=pcall(sampleUI)
        if not ok then note="UI sample: "..tostring(err):sub(1,80) end
    end
    if now-soundTime>=.2 then soundTime=now;pcall(sampleSounds)end
    if now-statusTime>=.3 then statusTime=now;refresh()end
end)
refresh()
