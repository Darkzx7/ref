-- One attempt for the next manually started fishing round. No hooks or input injection.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local old=pg:FindFirstChild("REF_ParkSkipTest")
if old then old:Destroy() end
local shared=assert(RS:FindFirstChild("Shared"),"Shared missing")
local modules=assert(shared:FindFirstChild("Modules"),"Modules missing")
local eventModule=assert(modules:FindFirstChild("events"),"events missing")
local remote=assert(eventModule:FindFirstChild("RemoteEvent"),"RemoteEvent missing")
local info=assert(modules:FindFirstChild("Information"),"Information missing")
local fightModule=assert(info:FindFirstChild("fishFightInfo"),"fishFightInfo missing")
local alive,armed,ready=false,false,false
local mode="native timed"
local nativeInit
local fightInfo,active
local connections,records,counts={},{},{}
local started=os.clock()
local gui=Instance.new("ScreenGui")
gui.Name="REF_ParkSkipTest";gui.ResetOnSpawn=false;gui.DisplayOrder=1000;gui.Parent=pg
alive=true
local function make(class,parent,props)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent;return o
end
local frame=make("Frame",gui,{Size=UDim2.fromOffset(310,226),Position=UDim2.new(0.5,-155,0,40),
    BackgroundColor3=Color3.fromRGB(22,22,24),BorderSizePixel=0})
make("UICorner",frame,{CornerRadius=UDim.new(0,10)})
make("TextLabel",frame,{Text="park · one-round skip test",Size=UDim2.new(1,-45,0,35),BackgroundTransparency=1,
    Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=Color3.new(1,1,1)})
local status=make("TextLabel",frame,{Text="loading timing information...",Position=UDim2.fromOffset(12,40),
    Size=UDim2.new(1,-24,0,70),BackgroundTransparency=1,TextWrapped=true,
    Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(205,205,210)})
local function log(kind,data)
    if #records<250 then records[#records+1]={t=math.floor((os.clock()-started)*1000)/1000,kind=kind,data=data} end
end
local function message(text) if alive then status.Text=text end end
local function connect(signal,fn)
    local c=signal:Connect(fn);connections[#connections+1]=c;return c
end
local function button(text,x,y,w,fn)
    local b=make("TextButton",frame,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,30),
        BackgroundColor3=Color3.fromRGB(45,45,48),BorderSizePixel=0,Font=Enum.Font.GothamMedium,
        TextColor3=Color3.new(1,1,1),TextSize=11})
    make("UICorner",b,{CornerRadius=UDim.new(0,6)});connect(b.Activated,fn);return b
end
connect(gui.Destroying,function()
    alive=false;armed=false;active=nil
    for _,c in ipairs(connections) do c:Disconnect() end
end)
button("×",270,3,30,function() gui:Destroy() end)
local armButton
armButton=button("test next fish",12,152,286,function()
    if not ready then message("timing module not ready");return end
    if active and active.sent then message("attempt already sent; waiting for the result");return end
    if active or armed then
        active=nil;armed=false;armButton.Text="test next fish";log("cancel",{});message("cancelled; no pending request")
    else
        armed=true;armButton.Text="cancel";log("armed",{mode=mode});message("cast manually; leave the minigame untouched")
    end
end)
local modeButton
modeButton=button("mode: native timed",12,116,286,function()
    if active or armed then message("cancel or finish the current attempt before changing mode");return end
    mode=mode=="native timed" and "native early" or mode=="native early" and "remote timed" or "native timed"
    modeButton.Text="mode: "..mode
    message(mode=="native early" and "native finish when the fight opens; early acceptance unverified" or mode=="native timed" and "native progress + finish after the observed timing" or "direct result request after the observed timing")
end)
local function export()
    return Http:JSONEncode({version="Park skip test 3",place=game.PlaceId,records=records,
        note="Native modes set the matching live session progress to 100 once and let the original minigame finish. This does not prove server acceptance. Timed remote mode sends one direct result request."})
end
button("copy log",12,188,139,function()
    local ok,err=pcall(function()
        local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
        assert(copy,"clipboard unavailable");copy(export())
    end)
    message(ok and "log copied" or tostring(err))
end)
button("save log",159,188,139,function()
    local filename="park-skip-test-"..os.date("%Y%m%d-%H%M%S")..".json"
    local ok,err=pcall(function() assert(type(writefile)=="function","writefile unavailable");writefile(filename,export()) end)
    message(ok and ("workspace/"..filename) or tostring(err))
end)
local function sessionFrom(fn,round)
    local getter=type(getupvalues)=="function" and getupvalues
        or type(debug)=="table" and type(debug.getupvalues)=="function" and debug.getupvalues
    if not getter or type(fn)~="function" then return nil end
    local ok,values=pcall(getter,fn)
    if not ok or type(values)~="table" then return nil end
    for _,value in pairs(values) do
        if type(value)=="table" and rawget(value,"id")==round.id and rawget(value,"fish")==round.fish
            and rawget(value,"pattern")==round.pattern and type(rawget(value,"progress"))=="number"
            and type(rawget(value,"timeLeft"))=="number" then
            return value
        end
    end
end
local function findSession(round)
    local state=sessionFrom(nativeInit,round)
    if state then return state end
    -- Some executors isolate require caches; existing input handlers reference the live session.
    if type(getconnections)=="function" then
        local ok,connections=pcall(getconnections,game:GetService("UserInputService").InputBegan)
        if ok and type(connections)=="table" then
            local checked=0
            for _,connection in pairs(connections) do
                checked+=1;if checked>128 then break end
                local got,fn=pcall(function() return connection.Function end)
                if got then state=sessionFrom(fn,round);if state then return state end end
            end
        end
    end
end
local function conclude(round,reason)
    if not alive or active~=round then return end
    log("observation",{id=round.id,reason=reason,sent=round.sent or false,effect=round.effect or false,
        inventoryUpdate=round.inventoryUpdate or false,before=round.before,after=round.after})
    active=nil;armButton.Text="test next fish"
    if round.sent and round.effect and round.inventoryUpdate then
        message("capture effect + inventory update observed; save log")
    elseif not round.sent then message("round ended before the test request; save log")
    else message("no confirmed capture from this test; save log") end
end
local watched=setmetatable({},{__mode="k"})
local function watchInventory(o)
    if not o:IsA("RemoteEvent") or watched[o] then return end
    if not o.Parent or o.Parent.Name~="DataService" then return end
    watched[o]=true
    connect(o.OnClientEvent,function(operation,keys,value)
        if operation~=1 or type(keys)~="table" or keys[1]~="fishes" or type(keys[2])~="string" or type(value)~="number" then return end
        local fish=keys[2];local before=counts[fish];counts[fish]=value
        local round=active
        if round and round.sent and round.fish==fish then
            round.before=round.before or before;round.after=value
            round.inventoryUpdate=round.before~=nil and value>round.before or round.before==nil and value>0
            log("inventory",{fish=fish,before=round.before,after=value,baselineKnown=round.before~=nil})
        end
    end)
end
for _,o in ipairs(RS:GetDescendants()) do watchInventory(o) end
connect(RS.DescendantAdded,watchInventory)
connect(remote.OnClientEvent,function(event,owner,payload,fish)
    if event=="FishFightStart" and owner==player.Name then
        if active then conclude(active,"new round") end
        if not armed or not ready or type(payload)~="table" or type(payload.id)~="string" or type(payload.fish)~="string" then return end
        armed=false
        local ok,minimum=pcall(fightInfo.MinWinSeconds,payload.fish,payload.skills or {},payload.pattern)
        if not ok or type(minimum)~="number" or minimum~=minimum or minimum<0 or minimum>60 then
            armButton.Text="test next fish";log("timing error",{error=tostring(minimum)});message("invalid timing; no request sent");return
        end
        local round={id=payload.id,fish=payload.fish,pattern=payload.pattern,before=counts[payload.fish],sent=false,mode=mode}
        active=round
        -- Immediate tests server acceptance without falsifying the progress display.
        local delay=mode=="native early" and 0 or minimum+1.6
        log("round",{id=round.id,fish=round.fish,pattern=round.pattern,minimum=minimum,delay=delay,mode=mode})
        message(string.format("%s · %s\none attempt in %.1fs",round.fish,tostring(round.pattern),delay))
        local function submit()
            if not alive or active~=round then return end
            if delay>0 and player:GetAttribute("fishingState")~="battle" then conclude(round,"not in battle");return end
            if round.mode~="remote timed" then
                local deadline=os.clock()+4
                local session
                repeat
                    if not alive or active~=round then return end
                    session=findSession(round)
                    if session and session.phase=="fight" then break end
                    if session and session.phase=="done" then conclude(round,"native session already done");return end
                    task.wait(0.05)
                until os.clock()>=deadline
                if not alive or active~=round then return end
                if not session or session.phase~="fight" then
                    log("native unavailable",{id=round.id,phase=session and session.phase or "missing",
                        bulkUpvalues=type(getupvalues),connections=type(getconnections)})
                    conclude(round,"live native session unavailable; no request sent")
                    message("live session unavailable; save log (no remote fallback)")
                    return
                end
                local previous=session.progress
                round.sent=true -- completion requested locally, not proof of an outgoing packet
                session.progress=100
                log("native completion requested",{id=round.id,before=previous,progress=session.progress,
                    phase=session.phase,timeLeft=session.timeLeft,mode=round.mode})
                message("native progress set; waiting for game completion and inventory")
                task.delay(0.25,function()
                    if alive then log("native state",{id=round.id,phase=session.phase,progress=session.progress,displayProgress=session.disp}) end
                end)
            else
                round.sent=true
                local sent,err=pcall(function() remote:FireServer("fishFightResult",round.id,"win",100) end)
                log("submission",{id=round.id,localCallSucceeded=sent,error=not sent and tostring(err) or nil,mode=round.mode})
                if not sent then conclude(round,"local call failed");return end
                message("request sent once; checking server observations")
            end
            task.delay(8,function() conclude(round,"observation timeout") end)
        end
        if delay==0 then task.spawn(submit) else task.delay(delay,submit) end
    elseif event=="Effect" and owner=="createFish" and payload==player then
        local round=active
        if round and round.sent and fish==round.fish then round.effect=true;log("capture effect",{fish=fish}) end
    elseif (event=="FishFightEnd" or event=="FishFightCancel") and owner==player.Name then
        local round=active
        if round and (event~="FishFightCancel" or not payload or payload==round.id) then
            log(event,{id=round.id,sent=round.sent})
            if not round.sent then conclude(round,event)
            else task.delay(1,function() conclude(round,event) end) end
        end
    end
end)
task.spawn(function()
    local ok,result=pcall(require,fightModule)
    if not alive then return end
    if not ok or type(result)~="table" or type(result.MinWinSeconds)~="function" then
        log("module error",{error=tostring(result)});message("timing unavailable; no requests will be sent");return
    end
    fightInfo=result
    local uiFolder=shared:FindFirstChild("UI")
    local hud=uiFolder and uiFolder:FindFirstChild("HUD")
    local nativeModule=hud and hud:FindFirstChild("FishFight")
    if nativeModule then
        local good,native=pcall(require,nativeModule)
        if good and type(native)=="table" and type(native.init)=="function" then nativeInit=native.init end
    end
    if not alive then return end
    ready=true;message("native timed ready; disable autofish, arm and cast manually")
end)
