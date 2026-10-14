-- Mush auto music v2. Standalone. Uses native Judge and Release from the live music session.
-- Does not change keyboard connections, fabricate scores or replay raw remote packets.
local Core=(function()
local Core = {}
local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end
local function propsIn(values)
    for _,v in pairs(values) do
        if type(v)=="table" and type(rawget(v,"Sheet"))=="table"
            and type(rawget(v,"Instrument"))=="table" and finite(rawget(v,"StartAt"))
            and type(rawget(v,"OnNote"))=="function" then return v end
    end
end
function Core.inspector(readValues, readName, readConstants, pause)
    local cache=setmetatable({}, {__mode="k"})
    local function values(fn)
        if cache[fn] then return cache[fn] end
        local ok,v=pcall(readValues,fn)
        v=ok and type(v)=="table" and v or {}
        cache[fn]=v
        return v
    end
    local function named(fn,name,required)
        local ok,n=pcall(readName,fn)
        if ok and n==name then return true end
        if not readConstants then return false end
        local good,cs=pcall(readConstants,fn)
        if not good or type(cs)~="table" then return false end
        local found={}
        for _,c in pairs(cs) do if type(c)=="string" then found[c]=true end end
        for _,s in ipairs(required) do if not found[s] then return false end end
        return true
    end
    local function graph(roots,depth)
        local queue,seen,out={},{},{}
        for _,f in ipairs(roots) do if type(f)=="function" then table.insert(queue,{f,0}) end end
        local i=1
        while i<=#queue and #out<160 do
            local item=queue[i]; i+=1
            local f,d=item[1],item[2]
            if seen[f] then continue end
            seen[f]=true; table.insert(out,f)
            if d<depth then
                for _,v in pairs(values(f)) do
                    if type(v)=="function" and not seen[v] then table.insert(queue,{v,d+1}) end
                end
            end
        end
        return out
    end
    local api={}
    function api.press(roots)
        for _,f in ipairs(graph(roots,3)) do
            if not named(f,"Press",{"OnPress","IsHold"}) then continue end
            local ups=values(f)
            local props=propsIn(ups)
            if not props then continue end
            for _,judge in pairs(ups) do
                if type(judge)=="function" and named(judge,"Judge",{"OnNote","GetJudgement","GetStart"})
                    and propsIn(values(judge))==props then
                    return {press=f,judge=judge,props=props}
                end
            end
        end
    end
    -- Press and Judge share only the rendered song clock in the captured module.
    -- Release is shared by all lanes: it does not require a matching keyboard wrapper.
    function api.native(lane,endedRoots,extraFunctions)
        local pressFns={}
        for _,v in pairs(values(lane.press)) do
            if type(v)=="function" then pressFns[v]=true end
        end
        local clocks,seenClocks={},{}
        for _,v in pairs(values(lane.judge)) do
            if type(v)=="function" and pressFns[v] and not seenClocks[v] then
                seenClocks[v]=true; table.insert(clocks,v)
            end
        end
        if #clocks~=1 then return nil,"clock candidates="..#clocks end
        lane.clock=clocks[1]
        local function releaseCandidate(f)
            if type(f)~="function" or not named(f,"Release",{"OnNote","GetFinish"}) then return end
            local ups=values(f)
            if propsIn(ups)~=lane.props then return end
            for _,v in pairs(ups) do
                if v==lane.clock then lane.nativeRelease=f; return lane end
            end
        end
        -- Each root gets its own traversal budget. A busy game's unrelated input
        -- listeners cannot exhaust a global cap before reaching the music callback.
        for _,root in ipairs(endedRoots) do
            for _,fn in ipairs(graph({root},3)) do
                local found=releaseCandidate(fn)
                if found then return found end
            end
        end
        if extraFunctions then
            for i,fn in ipairs(extraFunctions) do
                if pause and i%500==0 then pause() end
                local found=releaseCandidate(fn)
                if found then return found end
            end
        end
        return nil,"release missing; ended roots="..#endedRoots..", extra functions="..#(extraFunctions or {})
    end
    return api
end
function Core.new(sheet,lanes,startTime)
    assert(finite(startTime),"Invalid music clock")
    local self={notes={},byIndex={},accepted={},lanes=lanes,cursor=1,active={},last=nil,presses=0,releases=0,late=0,rejected=0,attempts=0}
    for index,n in ipairs(sheet) do
        assert(type(n)=="table" and type(n.Position)=="table","Invalid note "..index)
        local a,b=n.Position[1],n.Position[#n.Position]
        assert(finite(a) and finite(b) and b>=a and lanes[n.Key],"Unsupported note/lane "..index)
        table.insert(self.notes,{index=index,key=n.Key,start=a,finish=b,hold=#n.Position>1})
    end
    for _,n in ipairs(self.notes) do self.byIndex[n.index]=n end
    table.sort(self.notes,function(a,b) return a.start==b.start and a.index<b.index or a.start<b.start end)
    while self.notes[self.cursor] and self.notes[self.cursor].start<startTime-0.005 do self.cursor+=1 end
    return self
end
function Core.release(self,key)
    local held=self.active[key]
    if not held then return end
    self.active[key]=nil
    local ok,err=pcall(self.lanes[key].up)
    if ok then self.releases+=1 else
        local fallback=self.lanes[key].fallback
        if fallback then pcall(fallback) end
        error("Release: "..tostring(err),0)
    end
end
function Core.stop(self)
    local keys={}
    for key in pairs(self.active) do table.insert(keys,key) end
    local errors={}
    for _,key in ipairs(keys) do
        local ok,e=pcall(Core.release,self,key)
        if not ok then table.insert(errors,tostring(e)) end
    end
    return errors
end
function Core.step(self,t)
    if not finite(t) or (self.last and t<=self.last) then return end
    local dt=self.last and t-self.last or 1/60
    self.last=t
    local lead=math.min(dt*0.5,0.016)
    local releases={}
    for key,held in pairs(self.active) do
        if t>=held.finish then table.insert(releases,key) end
    end
    for _,key in ipairs(releases) do Core.release(self,key) end
    while self.notes[self.cursor] and self.notes[self.cursor].start<=t+lead do
        local n=self.notes[self.cursor]
        self.cursor+=1
        if t-n.start>0.12 then self.late+=1; continue end
        if self.accepted[n.index] then continue end
        self.attempts+=1
        local ok,hit=pcall(self.lanes[n.key].down,n.index)
        if not ok then
            -- Judge can send the down event before a later callback throws.
            pcall(self.lanes[n.key].up)
            Core.stop(self)
            error("Judge: "..tostring(hit),0)
        end
        local accepted=self.byIndex[hit]
        if not accepted or accepted.key~=n.key or self.accepted[hit] then
            self.rejected+=1
            continue
        end
        self.accepted[hit]=true
        self.presses+=1
        if accepted.hold then
            local held=self.active[n.key]
            self.active[n.key]={finish=math.max(accepted.finish,held and held.finish or -math.huge)}
        end
    end
end
return Core

end)()
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")
local player=Players.LocalPlayer
assert(player,"Run this script on the client")
local pg=player:WaitForChild("PlayerGui")
local previous=pg:FindFirstChild("MushAutoMusicStandalone")
if previous then previous:Destroy() end
local gui=Instance.new("ScreenGui")
gui.Name="MushAutoMusicStandalone"
gui.ResetOnSpawn=false
gui.DisplayOrder=1000
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=pg
local alive,enabled=false,false
alive=true
local connections={}
local session=nil
local generation=0
local attaching=false
local lastFault=nil
local retryAt=0
local logs={}
local function log(message)
    logs[#logs+1]=os.date("%H:%M:%S").." "..tostring(message)
    if #logs>100 then table.remove(logs,1) end
end
local function connect(signal,fn)
    local c=signal:Connect(fn); connections[#connections+1]=c; return c
end
local function create(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent; return o
end
local function round(o,r)
    create("UICorner",{CornerRadius=UDim.new(0,r or 8)},o)
end
local frame=create("Frame",{Size=UDim2.fromOffset(310,184),Position=UDim2.new(0,16,0.15,0),BackgroundColor3=Color3.fromRGB(21,22,25),BackgroundTransparency=0.08,BorderSizePixel=0,Active=true},gui)
round(frame,10)
create("UIStroke",{Color=Color3.fromRGB(70,72,79),Transparency=0.3,Thickness=1},frame)
local scale=create("UIScale",{Scale=1},frame)
local title=create("TextLabel",{Size=UDim2.fromOffset(220,36),Position=UDim2.fromOffset(12,0),Text="auto music",TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.fromRGB(233,234,238),TextSize=14,Font=Enum.Font.GothamMedium,BackgroundTransparency=1,Active=true},frame)
local body=create("Frame",{Position=UDim2.fromOffset(12,38),Size=UDim2.fromOffset(286,138),BackgroundTransparency=1},frame)
local status=create("TextLabel",{Size=UDim2.fromOffset(286,39),Text="choose a song in the game",TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.fromRGB(182,187,196),TextSize=12,Font=Enum.Font.Gotham,BackgroundTransparency=1},body)
local detail=create("TextLabel",{Position=UDim2.fromOffset(0,40),Size=UDim2.fromOffset(286,20),Text="off",TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.fromRGB(140,145,155),TextSize=11,Font=Enum.Font.Gotham,BackgroundTransparency=1},body)
local function button(text,x,y,width,parent)
    local b=create("TextButton",{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,30),BackgroundColor3=Color3.fromRGB(42,45,51),TextColor3=Color3.fromRGB(223,226,232),TextSize=12,Font=Enum.Font.GothamMedium,BorderSizePixel=0},parent or body)
    round(b,6); return b
end
local toggle=button("auto music: off",0,66,286)
local copy=button("copy log",0,103,138)
local save=button("save log",148,103,138)
local mini=button("-",240,3,28,frame)
local close=button("x",275,3,28,frame)
local function report(message)
    if alive then status.Text=tostring(message) end
end
local inspectValues=(debug and debug.getupvalues) or getupvalues
local inspectConstants=(debug and debug.getconstants) or getconstants
local function nameOf(fn)
    if debug and type(debug.info)=="function" then
        local ok,name=pcall(debug.info,fn,"n")
        if ok and type(name)=="string" and name~="" then return name end
    end
    if debug and type(debug.getinfo)=="function" then
        local ok,info=pcall(debug.getinfo,fn)
        if ok and type(info)=="table" then return info.name end
    end
    return ""
end
local function roots(signal)
    local ok,list=pcall(getconnections,signal)
    if not ok or type(list)~="table" then return {} end
    local out={}
    for _,c in ipairs(list) do
        local good,f=pcall(function() return c.Connected~=false and c.Function or nil end)
        if good and type(f)=="function" then out[#out+1]=f end
    end
    return out
end
local function visible(o)
    if not o or not o:IsDescendantOf(pg) then return false end
    while o and o~=pg do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o=o.Parent
    end
    return true
end
local function findMain()
    for _,root in ipairs(pg:GetChildren()) do
        local music=root:FindFirstChild("music")
        local main=music and music:FindFirstChild("Main")
        if main and main:FindFirstChild("Hotbar") and main:FindFirstChild("Topbar") and visible(main) then return main end
    end
end
local function attach(main)
    local inspector=Core.inspector(inspectValues,nameOf,inspectConstants,function() task.wait() end)
    local ended=roots(UIS.InputEnded)
    local lanes,props,clock={}
    local laneCount=0
    local releaseCache=nil
    local gcFunctions=nil
    log("connecting; input-ended callbacks="..#ended)
    for _,row in ipairs(main.Hotbar:GetChildren()) do
        if not row:IsA("GuiObject") then continue end
        local b=row:FindFirstChild("ImageButton")
        if not b or not b:IsA("GuiButton") then continue end
        local lane=inspector.press(roots(b.InputBegan))
        if not lane then error("Music Press handler unavailable; copy log",0) end
        if props and props~=lane.props then error("Music session changed while connecting",0) end
        props=lane.props
        if releaseCache and releaseCache.props==lane.props and releaseCache.judge==lane.judge then
            lane.clock=releaseCache.clock
            lane.nativeRelease=releaseCache.nativeRelease
        else
            local candidate,reason=inspector.native(lane,ended)
            if not candidate and lane.clock and type(getgc)=="function" then
                if not gcFunctions then
                    local ok,objects=pcall(getgc,false)
                    gcFunctions={}
                    if ok and type(objects)=="table" then
                        for _,object in pairs(objects) do
                            if type(object)=="function" then gcFunctions[#gcFunctions+1]=object end
                        end
                    end
                    log("native lookup fallback: "..#gcFunctions.." loaded functions")
                end
                candidate,reason=inspector.native(lane,{},gcFunctions)
            end
            if not candidate then error("Native music lookup: "..tostring(reason).."; getgc="..type(getgc),0) end
            lane=candidate; releaseCache=lane
        end
        if clock and clock~=lane.clock then error("Music lanes have different clocks",0) end
        clock=lane.clock
        local key,laneName
        for id,item in pairs(props.Instrument.Keys) do
            if typeof(item.Key)=="EnumItem" and item.Key.Value==row.LayoutOrder then
                key,laneName=item.Key,id; break
            end
        end
        if not key or lanes[key] then error("Unrecognized or duplicate music lane",0) end
        local entry={}
        entry.down=function()
            if type(props.OnPress)=="function" then props.OnPress() end
            return lane.judge(key)
        end
        entry.up=function() lane.nativeRelease(key) end
        lanes[key]=entry; laneCount+=1
    end
    assert(props and clock and laneCount>0,"Music controls are still loading")
    local t=clock()
    assert(type(t)=="number" and math.abs((Workspace:GetServerTimeNow()-props.StartAt)-t)<0.5,"Music clock is not running")
    local engine=Core.new(props.Sheet,lanes,t)
    log("connected: "..laneCount.." lanes, "..#engine.notes.." notes; Judge + Release; native clock "..string.format("%.3f",t))
    return {main=main,props=props,clock=clock,engine=engine,lastTime=t,clockChanged=os.clock()}
end
local function detach()
    if session then
        if session.main:IsDescendantOf(pg) then
            for _,e in ipairs(Core.stop(session.engine)) do log(e) end
        else
            -- The game UI cleanup already releases its notes. Avoid stale callbacks.
            table.clear(session.engine.active)
        end
        session=nil
    end
end
local function fault(err)
    detach()
    local msg=tostring(err)
    if msg~=lastFault then log(msg); lastFault=msg end
    retryAt=os.clock()+2
    report(msg)
end
connect(toggle.Activated,function()
    generation+=1
    enabled=not enabled
    toggle.Text=enabled and "auto music: on" or "auto music: off"
    toggle.BackgroundColor3=enabled and Color3.fromRGB(52,68,63) or Color3.fromRGB(42,45,51)
    detach(); retryAt=0; lastFault=nil
    log(enabled and "enabled" or "disabled; released held notes")
    report(enabled and "waiting for a song" or "off")
    detail.Text=enabled and "select the instrument and song in the game" or "off"
end)
local function export()
    return "Mush auto music v2 | Place: "..game.PlaceId.."\n"..table.concat(logs,"\n")
end
connect(copy.Activated,function()
    local clipboard=type(setclipboard)=="function" and setclipboard or toclipboard
    if type(clipboard)~="function" then report("clipboard unavailable; use save log"); return end
    local ok,e=pcall(clipboard,export()); report(ok and "log copied" or tostring(e))
end)
connect(save.Activated,function()
    if type(writefile)~="function" then report("writefile unavailable; use copy log"); return end
    local prefix=""
    if type(makefolder)=="function" and type(isfolder)=="function" then
        local ok=pcall(function()
            for _,dir in ipairs({"True Ref","True Ref/Logs","True Ref/Logs/music"}) do
                if not isfolder(dir) then makefolder(dir) end
            end
        end)
        if ok then prefix="True Ref/Logs/music/" end
    end
    local filename=prefix.."auto_music_"..os.date("%Y%m%d_%H%M%S")..".txt"
    local ok,e=pcall(writefile,filename,export()); report(ok and ("saved: "..filename) or tostring(e))
end)
local minimized=false
connect(mini.Activated,function()
    minimized=not minimized; body.Visible=not minimized
    frame.Size=UDim2.fromOffset(310,minimized and 36 or 184)
    mini.Text=minimized and "+" or "-"
end)
local drag,dragStart,frameStart
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        drag=input; dragStart=input.Position; frameStart=frame.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if not drag then return end
    if drag.UserInputType==Enum.UserInputType.Touch and input~=drag then return end
    if drag.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local delta=(input.Position-dragStart)
    local camera=Workspace.CurrentCamera
    if not camera then return end
    local view=camera.ViewportSize
    local x=frameStart.X.Scale*view.X+frameStart.X.Offset+delta.X
    local y=frameStart.Y.Scale*view.Y+frameStart.Y.Offset+delta.Y
    frame.Position=UDim2.fromOffset(math.clamp(x,0,math.max(0,view.X-frame.AbsoluteSize.X)),math.clamp(y,0,math.max(0,view.Y-frame.AbsoluteSize.Y)))
end)
connect(UIS.InputEnded,function(input) if input==drag then drag=nil end end)
local function cleanup()
    if not alive then return end
    generation+=1
    enabled=false; alive=false; detach()
    for _,c in ipairs(connections) do c:Disconnect() end
    table.clear(connections)
end
connect(gui.Destroying,cleanup)
connect(close.Activated,function() cleanup(); gui:Destroy() end)
local supported=type(getconnections)=="function" and type(inspectValues)=="function"
if not supported then
    log("missing executor support: getconnections="..type(getconnections)..", getupvalues="..type(inspectValues))
    report("executor needs getconnections + getupvalues; copy log")
    toggle.Active=false; toggle.AutoButtonColor=false; toggle.Text="executor unsupported"
else
    log("ready; native Judge + Release; no keyboard wrapper required")
    log("executor: getconnections="..type(getconnections)..", getupvalues="..type(inspectValues)..", getconstants="..type(inspectConstants)..", getgc="..type(getgc))
end
local nextUI=0
connect(Run.Heartbeat,function()
    if not alive then return end
    local now=os.clock()
    if now>=nextUI then
        nextUI=now+0.25
        local camera=Workspace.CurrentCamera
        if camera then scale.Scale=math.clamp((camera.ViewportSize.X-24)/310,0.5,1) end
    end
    if not enabled or not supported then return end
    if session and not visible(session.main) then detach(); retryAt=0 end
    if not session then
        if now<retryAt then return end
        retryAt=now+0.5
        local main=findMain()
        if not main then report("waiting for a song"); return end
        if attaching then return end
        attaching=true
        local token=generation
        report("connecting to the music session...")
        task.spawn(function()
            local ok,value=pcall(attach,main)
            attaching=false
            if not alive or not enabled or token~=generation or not visible(main) then return end
            if not ok then fault(value); return end
            session=value; lastFault=nil
            report("following the current song")
        end)
        return
    end
    local s=session
    local ok,err=pcall(function()
        local t=s.clock()
        assert(type(t)=="number","Music clock returned no time")
        if t~=s.lastTime then s.lastTime=t; s.clockChanged=now end
        if now-s.clockChanged>1 then error("Music clock stopped; reconnecting",0) end
        -- Judge reads this same rendered clock. Do not act on a stale frame.
        if math.abs((Workspace:GetServerTimeNow()-s.props.StartAt)-t)>0.08 then return end
        Core.step(s.engine,t)
        if s.engine.rejected>(s.reportedRejects or 0) then
            s.reportedRejects=s.engine.rejected
            if s.reportedRejects<=5 then log("Judge returned no new note at t="..string.format("%.3f",t)) end
        end
        if now>=(s.nextStats or 0) then
            s.nextStats=now+0.3
            local score=s.main:FindFirstChild("Score")
            local label=score and score:FindFirstChild("TextLabel")
            detail.Text=string.format("%d hits | %d skipped | %s",s.engine.presses,s.engine.late+s.engine.rejected,label and label.Text or "")
            if s.engine.cursor>#s.engine.notes and next(s.engine.active)==nil then report("chart finished; waiting for the next song") end
        end
        if now>=(s.nextLog or 0) then
            s.nextLog=now+15
            log(string.format("t=%.3f | hits=%d | attempts=%d | rejected=%d | late=%d",t,s.engine.presses,s.engine.attempts,s.engine.rejected,s.engine.late))
        end
    end)
    if not ok then fault(err) end
end)
