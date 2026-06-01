local VERSION = "2026-06-01-passive-remote-scanner"

local function safe(fn, ...)
    local args = { ... }
    return pcall(function()
        return fn(table.unpack(args))
    end)
end

local function globalFunction(name)
    local env = (type(getgenv) == "function" and getgenv()) or _G
    local value = env and env[name]
    if type(value) == "function" then
        return value
    end
    return nil
end

local function kind(value)
    if type(typeof) == "function" then
        local ok, result = pcall(typeof, value)
        if ok then
            return result
        end
    end
    return type(value)
end

local function getService(name)
    local ok, service = pcall(function()
        return game:GetService(name)
    end)
    if ok then
        return service
    end
    return nil
end

local Players = getService("Players")
local RunService = getService("RunService")
local LocalPlayer = Players and Players.LocalPlayer

local env = (type(getgenv) == "function" and getgenv()) or _G
local previous = env.__MM_REMOTE_SCANNER
if type(previous) == "table" and type(previous.Stop) == "function" then
    pcall(function()
        previous:Stop("replaced")
    end)
end

local Scanner = {
    active = true,
    buffer = {},
    conns = {},
    counts = {},
    discovered = setmetatable({}, { __mode = "k" }),
    inbound = setmetatable({}, { __mode = "k" }),
    fileText = "",
    flushing = false,
    inHook = false,
}

env.__MM_REMOTE_SCANNER = Scanner

local folder = "MMScanner"
local placeId = tostring(game.PlaceId or "unknown")
local startedAt = tostring(os.time and os.time() or math.floor(tick and tick() or 0))
local filePath = folder .. "/scan_" .. placeId .. "_" .. startedAt .. ".log"

local writefileFn = globalFunction("writefile")
local appendfileFn = globalFunction("appendfile")
local makefolderFn = globalFunction("makefolder")
local isfolderFn = globalFunction("isfolder")
local newcclosureFn = globalFunction("newcclosure") or function(fn)
    return fn
end

local function now()
    local ok, value = pcall(function()
        return DateTime.now():ToIsoDate()
    end)
    if ok then
        return value
    end
    if os.date then
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end
    return tostring(tick and tick() or 0)
end

local function fullName(instance)
    local ok, value = pcall(function()
        return instance:GetFullName()
    end)
    if ok then
        return value
    end
    return tostring(instance)
end

local function prop(instance, name)
    local ok, value = pcall(function()
        return instance[name]
    end)
    if ok then
        return value
    end
    return nil
end

local function isA(instance, className)
    if kind(instance) ~= "Instance" then
        return false
    end
    local ok, value = pcall(function()
        return instance:IsA(className)
    end)
    return ok and value == true
end

local function isRemote(instance)
    return isA(instance, "RemoteEvent") or isA(instance, "RemoteFunction")
end

local function quote(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("\b", "\\b")
    value = value:gsub("\f", "\\f")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
    value = value:gsub("[%z\1-\31]", function(char)
        return string.format("\\u%04x", string.byte(char))
    end)
    return "\"" .. value .. "\""
end

local function isArray(tbl)
    local count = 0
    local maxIndex = 0
    for key in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        if key > maxIndex then
            maxIndex = key
        end
    end
    return maxIndex == count
end

local function encode(value, depth)
    depth = depth or 0
    local valueType = type(value)

    if value == nil then
        return "null"
    end
    if valueType == "boolean" or valueType == "number" then
        return tostring(value)
    end
    if valueType == "string" then
        return quote(value)
    end
    if valueType ~= "table" then
        return quote(tostring(value))
    end
    if depth > 6 then
        return quote("[max-depth]")
    end

    local parts = {}
    if isArray(value) then
        for index = 1, #value do
            parts[#parts + 1] = encode(value[index], depth + 1)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    for key, item in pairs(value) do
        parts[#parts + 1] = quote(tostring(key)) .. ":" .. encode(item, depth + 1)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

local function shortString(value, maxLength)
    value = tostring(value)
    maxLength = maxLength or 300
    if #value > maxLength then
        return value:sub(1, maxLength) .. "...[truncated]"
    end
    return value
end

local function numberValue(value)
    local ok, rounded = pcall(function()
        return math.floor(value * 10000 + 0.5) / 10000
    end)
    if ok then
        return rounded
    end
    return tostring(value)
end

local function serialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local valueType = kind(value)
    if value == nil then
        return { type = "nil" }
    end
    if valueType == "boolean" or valueType == "number" then
        return { type = valueType, value = value }
    end
    if valueType == "string" then
        return { type = "string", value = shortString(value, 800), length = #value }
    end
    if valueType == "Instance" then
        return {
            type = "Instance",
            class = tostring(prop(value, "ClassName") or "Unknown"),
            name = tostring(prop(value, "Name") or "Unknown"),
            path = fullName(value),
        }
    end
    if valueType == "Vector2" then
        return {
            type = "Vector2",
            x = numberValue(value.X),
            y = numberValue(value.Y),
        }
    end
    if valueType == "Vector3" then
        return {
            type = valueType,
            x = numberValue(value.X),
            y = numberValue(value.Y),
            z = numberValue(value.Z),
        }
    end
    if valueType == "CFrame" then
        local ok, components = pcall(function()
            return { value:GetComponents() }
        end)
        return { type = "CFrame", components = ok and components or tostring(value) }
    end
    if valueType == "Color3" then
        return {
            type = "Color3",
            r = numberValue(value.R),
            g = numberValue(value.G),
            b = numberValue(value.B),
        }
    end
    if valueType == "UDim" then
        return { type = "UDim", scale = numberValue(value.Scale), offset = value.Offset }
    end
    if valueType == "UDim2" then
        return {
            type = "UDim2",
            x = { scale = numberValue(value.X.Scale), offset = value.X.Offset },
            y = { scale = numberValue(value.Y.Scale), offset = value.Y.Offset },
        }
    end
    if valueType == "EnumItem" then
        return { type = "EnumItem", value = tostring(value) }
    end
    if valueType == "Ray" then
        return {
            type = "Ray",
            origin = serialize(value.Origin, depth + 1, seen),
            direction = serialize(value.Direction, depth + 1, seen),
        }
    end
    if valueType == "table" then
        if seen[value] then
            return { type = "table", circular = true }
        end
        if depth >= 3 then
            local count = 0
            for _ in pairs(value) do
                count = count + 1
            end
            return { type = "table", count = count, truncated = "max-depth" }
        end

        seen[value] = true
        local entries = {}
        local total = 0
        for key, item in pairs(value) do
            total = total + 1
            if #entries < 40 then
                entries[#entries + 1] = {
                    key = shortString(tostring(key), 120),
                    keyType = kind(key),
                    value = serialize(item, depth + 1, seen),
                }
            end
        end
        seen[value] = nil
        return { type = "table", count = total, entries = entries, truncated = total > #entries }
    end

    return { type = tostring(valueType), value = shortString(tostring(value), 300) }
end

local function packArgs(...)
    local count = select("#", ...)
    local values = {}
    local limit = math.min(count, 20)
    for index = 1, limit do
        local ok, result = pcall(function()
            return serialize(select(index, ...))
        end)
        values[index] = ok and result or {
            type = "serialization_error",
            value = shortString(tostring(result), 300),
        }
    end
    return {
        count = count,
        values = values,
        truncated = count > limit,
    }
end

local function remoteInfo(remote)
    return {
        class = tostring(prop(remote, "ClassName") or "Unknown"),
        name = tostring(prop(remote, "Name") or "Unknown"),
        path = fullName(remote),
    }
end

local function count(eventName)
    Scanner.counts[eventName] = (Scanner.counts[eventName] or 0) + 1
end

local function flush()
    if Scanner.flushing or #Scanner.buffer == 0 or not writefileFn then
        return
    end

    Scanner.flushing = true
    local chunk = table.concat(Scanner.buffer, "\n") .. "\n"
    Scanner.buffer = {}

    if appendfileFn then
        local ok = pcall(function()
            appendfileFn(filePath, chunk)
        end)
        if ok then
            Scanner.flushing = false
            return
        end
    end

    Scanner.fileText = (Scanner.fileText or "") .. chunk
    if #Scanner.fileText > 6000000 then
        Scanner.fileText = Scanner.fileText:sub(#Scanner.fileText - 5000000)
    end
    pcall(function()
        writefileFn(filePath, Scanner.fileText)
    end)
    Scanner.flushing = false
end

local function logRecord(record)
    if not Scanner.active then
        return
    end

    record.time = now()
    Scanner.buffer[#Scanner.buffer + 1] = encode(record)
    count(record.event or "unknown")

    if #Scanner.buffer >= 75 then
        flush()
    end
end

function Scanner:Connect(signal, callback)
    if not self.active or not signal then
        return nil
    end

    local ok, conn = pcall(function()
        return signal:Connect(callback)
    end)
    if ok and conn then
        self.conns[#self.conns + 1] = conn
        return conn
    end
    return nil
end

function Scanner:Stop(reason)
    if not self.active then
        return
    end
    logRecord({ event = "scanner_stop", reason = tostring(reason or "manual") })
    self.active = false
    for _, conn in ipairs(self.conns) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    flush()
end

local function ensureFolder()
    if not writefileFn then
        return
    end
    if makefolderFn then
        local exists = false
        if isfolderFn then
            local ok, result = pcall(function()
                return isfolderFn(folder)
            end)
            exists = ok and result == true
        end
        if not exists then
            pcall(function()
                makefolderFn(folder)
            end)
        end
    end
    pcall(function()
        writefileFn(filePath, "")
    end)
end

local function attachInbound(remote)
    if Scanner.inbound[remote] or not isA(remote, "RemoteEvent") then
        return
    end
    Scanner.inbound[remote] = true

    local signal = prop(remote, "OnClientEvent")
    Scanner:Connect(signal, function(...)
        logRecord({
            event = "remote_inbound",
            method = "OnClientEvent",
            remote = remoteInfo(remote),
            args = packArgs(...),
        })
    end)
end

local function rememberRemote(remote)
    if not isRemote(remote) or Scanner.discovered[remote] then
        return
    end
    Scanner.discovered[remote] = true
    logRecord({
        event = "remote_discovered",
        remote = remoteInfo(remote),
    })
    attachInbound(remote)
end

local function scanRoot(root)
    if not root or not Scanner.active then
        return
    end

    rememberRemote(root)

    local ok, descendants = pcall(function()
        return root:GetDescendants()
    end)
    if ok and type(descendants) == "table" then
        for index, instance in ipairs(descendants) do
            rememberRemote(instance)
            if index % 250 == 0 and task and task.wait then
                task.wait()
            end
        end
    end

    local signal = prop(root, "DescendantAdded")
    Scanner:Connect(signal, function(instance)
        if task and task.defer then
            task.defer(function()
                rememberRemote(instance)
            end)
        else
            rememberRemote(instance)
        end
    end)
end

local function roots()
    local list = {}
    local names = {
        "ReplicatedStorage",
        "ReplicatedFirst",
        "Workspace",
        "Lighting",
        "StarterGui",
        "StarterPack",
        "StarterPlayer",
    }

    for _, name in ipairs(names) do
        local service = getService(name)
        if service then
            list[#list + 1] = service
        end
    end

    if LocalPlayer then
        list[#list + 1] = LocalPlayer
        local playerGui = prop(LocalPlayer, "PlayerGui")
        local backpack = prop(LocalPlayer, "Backpack")
        local character = prop(LocalPlayer, "Character")
        if playerGui then
            list[#list + 1] = playerGui
        end
        if backpack then
            list[#list + 1] = backpack
        end
        if character then
            list[#list + 1] = character
        end
    end

    return list
end

local function installNamecallHook()
    local hookmetamethodFn = globalFunction("hookmetamethod")
    local getnamecallmethodFn = globalFunction("getnamecallmethod")

    if hookmetamethodFn and getnamecallmethodFn then
        local original
        original = hookmetamethodFn(game, "__namecall", newcclosureFn(function(self, ...)
            local method = nil
            pcall(function()
                method = getnamecallmethodFn()
            end)

            if Scanner.active
                and not Scanner.inHook
                and (method == "FireServer" or method == "InvokeServer")
                and isRemote(self)
            then
                Scanner.inHook = true
                pcall(function(...)
                    logRecord({
                        event = "remote_outbound",
                        method = method,
                        remote = remoteInfo(self),
                        args = packArgs(...),
                    })
                end, ...)
                Scanner.inHook = false
            end

            return original(self, ...)
        end))

        Scanner.namecallHook = "hookmetamethod"
        return true
    end

    local getrawmetatableFn = globalFunction("getrawmetatable")
    local setreadonlyFn = globalFunction("setreadonly")
    local makewriteableFn = globalFunction("makewriteable") or globalFunction("make_writeable")
    local makereadonlyFn = globalFunction("makereadonly") or globalFunction("make_readonly")
    if not getrawmetatableFn or not getnamecallmethodFn or (not setreadonlyFn and not makewriteableFn) then
        return false
    end

    local ok, mt = pcall(function()
        return getrawmetatableFn(game)
    end)
    if not ok or type(mt) ~= "table" or type(mt.__namecall) ~= "function" then
        return false
    end

    local original = mt.__namecall
    if setreadonlyFn then
        pcall(function()
            setreadonlyFn(mt, false)
        end)
    elseif makewriteableFn then
        pcall(function()
            makewriteableFn(mt)
        end)
    end
    mt.__namecall = newcclosureFn(function(self, ...)
        local method = nil
        if getnamecallmethodFn then
            pcall(function()
                method = getnamecallmethodFn()
            end)
        end

        if Scanner.active
            and not Scanner.inHook
            and (method == "FireServer" or method == "InvokeServer")
            and isRemote(self)
        then
            Scanner.inHook = true
            pcall(function(...)
                logRecord({
                    event = "remote_outbound",
                    method = method,
                    remote = remoteInfo(self),
                    args = packArgs(...),
                })
            end, ...)
            Scanner.inHook = false
        end

        return original(self, ...)
    end)
    if setreadonlyFn then
        pcall(function()
            setreadonlyFn(mt, true)
        end)
    elseif makereadonlyFn then
        pcall(function()
            makereadonlyFn(mt)
        end)
    end

    Scanner.namecallHook = "rawmetatable"
    return true
end

ensureFolder()

logRecord({
    event = "scanner_start",
    version = VERSION,
    file = filePath,
    placeId = game.PlaceId,
    jobId = tostring(game.JobId or ""),
    localPlayer = LocalPlayer and {
        name = tostring(prop(LocalPlayer, "Name") or ""),
        userId = prop(LocalPlayer, "UserId"),
    } or nil,
    capabilities = {
        writefile = writefileFn ~= nil,
        appendfile = appendfileFn ~= nil,
        hookmetamethod = globalFunction("hookmetamethod") ~= nil,
        getnamecallmethod = globalFunction("getnamecallmethod") ~= nil,
    },
})

local hookInstalled = installNamecallHook()
logRecord({
    event = "scanner_hook_status",
    installed = hookInstalled,
    method = Scanner.namecallHook or "none",
})

local function spawnTask(callback)
    if task and task.spawn then
        task.spawn(callback)
    else
        coroutine.wrap(callback)()
    end
end

spawnTask(function()
    for _, root in ipairs(roots()) do
        if Scanner.active then
            scanRoot(root)
        end
    end

    if LocalPlayer then
        Scanner:Connect(prop(LocalPlayer, "CharacterAdded"), function(character)
            scanRoot(character)
        end)
    end

    flush()
end)

spawnTask(function()
    while Scanner.active do
        if task and task.wait then
            task.wait(2)
        else
            wait(2)
        end
        flush()
    end
end)

spawnTask(function()
    while Scanner.active do
        if task and task.wait then
            task.wait(15)
        else
            wait(15)
        end
        logRecord({
            event = "scanner_heartbeat",
            counts = Scanner.counts,
            bufferSize = #Scanner.buffer,
        })
        flush()
    end
end)
