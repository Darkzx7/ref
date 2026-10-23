-- Inspect only the fishing client modules found in the manual recording.
-- Does not require modules, replace functions, send remotes or modify the game.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player,"Run on the client")
local pg=player:WaitForChild("PlayerGui")
local old=pg:FindFirstChild("REF_ParkFishingProtocol")
if old then old:Destroy() end
local alive=true
local report={version="Park fishing protocol 1",place=game.PlaceId,
    exported=os.date("!%Y-%m-%dT%H:%M:%SZ"),
    note="Read-only client source inspection. Decompiled source may be inaccurate. No module execution or remote calls.",
    decompilerAvailable=type(decompile)=="function",modules={}}
local paths={
    {"Shared","UI","HUD","FishFight"},
    {"Shared","Modules","Tools","FishingRod"},
    {"Shared","Modules","Information","fishFightInfo"},
    {"Shared","Modules","Information","fishOrientInfo"},
    {"Shared","Modules","Information","fishGripInfo"},
    {"Shared","Modules","Information","fishingInfo"},
    {"Shared","Modules","events"},
}
local gui=Instance.new("ScreenGui")
gui.Name="REF_ParkFishingProtocol";gui.ResetOnSpawn=false;gui.DisplayOrder=1000;gui.Parent=pg
gui.Destroying:Connect(function() alive=false end)
local function make(class,parent,props)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent;return o
end
local frame=make("Frame",gui,{Size=UDim2.fromOffset(300,170),Position=UDim2.new(0.5,-150,0,44),
    BackgroundColor3=Color3.fromRGB(21,21,24),BorderSizePixel=0})
make("UICorner",frame,{CornerRadius=UDim.new(0,10)})
make("TextLabel",frame,{Text="park · fishing protocol",Size=UDim2.new(1,-45,0,35),BackgroundTransparency=1,
    Font=Enum.Font.GothamMedium,TextSize=13,TextColor3=Color3.new(1,1,1)})
local status=make("TextLabel",frame,{Text="inspecting fishing modules...",Size=UDim2.new(1,-24,0,72),
    Position=UDim2.fromOffset(12,40),BackgroundTransparency=1,TextWrapped=true,
    Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(195,195,200)})
local function button(text,x,y,w,callback)
    local b=make("TextButton",frame,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,30),
        BackgroundColor3=Color3.fromRGB(43,43,47),BorderSizePixel=0,Font=Enum.Font.GothamMedium,
        TextSize=12,TextColor3=Color3.new(1,1,1)})
    make("UICorner",b,{CornerRadius=UDim.new(0,6)})
    b.Activated:Connect(callback)
end
button("×",262,3,30,function() gui:Destroy() end)
local ready=false
local function export() return Http:JSONEncode(report) end
local filename="park-fishing-protocol-"..os.date("%Y%m%d-%H%M%S")..".json"
local function save()
    assert(type(writefile)=="function","writefile unavailable; use copy")
    writefile(filename,export())
end
button("copy",12,126,134,function()
    if not ready then status.Text="inspection still running...";return end
    local ok,err=pcall(function()
        local copy=type(setclipboard)=="function" and setclipboard or type(toclipboard)=="function" and toclipboard
        assert(copy,"clipboard unavailable; use save")
        copy(export())
    end)
    status.Text=ok and "copied · send the complete JSON" or tostring(err)
end)
button("save",154,126,134,function()
    if not ready then status.Text="inspection still running...";return end
    local ok,err=pcall(save)
    status.Text=ok and ("workspace/"..filename) or tostring(err)
end)
local function find(parts)
    local o=RS
    for _,name in ipairs(parts) do o=o and o:FindFirstChild(name) end
    return o
end
local function sourceOf(module)
    local ok,source=pcall(function() return module.Source end)
    if ok and type(source)=="string" and #source>0 then return source,"Source" end
    if type(decompile)~="function" then return nil,"executor cannot read or decompile source" end
    local good,result=pcall(decompile,module)
    if not good or type(result)~="string" or result=="" then return nil,tostring(result) end
    return result,"decompile"
end
task.spawn(function()
    local count=0
    for index,parts in ipairs(paths) do
        if not alive then return end
        local item={path="ReplicatedStorage."..table.concat(parts,".")}
        report.modules[#report.modules+1]=item
        status.Text="inspecting "..index.."/"..#paths.."\n"..parts[#parts]
        local module=find(parts)
        if not module then item.error="not found"
        elseif not module:IsA("ModuleScript") then item.error="expected ModuleScript; got "..module.ClassName
        else
            local finished,expired,source,method=false,false,nil,nil
            task.spawn(function()
                local result,how=sourceOf(module)
                if not expired and alive then source=result;method=how;finished=true end
            end)
            local deadline=os.clock()+18
            while alive and not finished and os.clock()<deadline do task.wait(0.1) end
            if not alive then return end
            expired=true
            if not finished then item.error="source inspection timed out"
            elseif not source then item.error=method
            else
                item.source=source:sub(1,350000);item.method=method;item.truncated=#source>350000
                count+=1
            end
        end
        task.wait()
    end
    if not alive then return end
    ready=true;report.sourcesRead=count
    local ok,err=pcall(save)
    status.Text=count.."/"..#paths.." sources read\n"..(ok and ("saved: workspace/"..filename) or ("auto-save failed; try copy\n"..tostring(err):sub(1,110)))
end)
