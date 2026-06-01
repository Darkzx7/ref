local VERSION = "2026-06-01-mm-scanner-ultra-safe-bootstrap"

local _type = type
local _tostring = tostring
local _tonumber = tonumber
local _pcall = pcall
local _xpcall = xpcall
local _pairs = pairs
local _ipairs = ipairs
local _select = select
local _setmetatable = setmetatable
local _math = math
local _table = table
local _string = string
local _os = os
local _coroutine = coroutine
local _unpack = unpack or (_table and _table.unpack)
local _warn = warn
local _print = print
local _game = game
local _G_ref = _G

local function callable(value)
    return _type(value) == "function"
end

local function safeCall(fn, ...)
    if not callable(fn) then
        return false, "not_function"
    end
    if callable(_pcall) then
        return _pcall(fn, ...)
    end
    return false, "pcall_missing"
end

local function safeToString(value)
    if callable(_tostring) then
        local ok, result = safeCall(_tostring, value)
        if ok then
            return result
        end
    end
    return "[tostring unavailable]"
end

local function safeWarn(message)
    message = "[MMScanner] " .. safeToString(message)
    if callable(_warn) then
        safeCall(_warn, message)
    elseif callable(_print) then
        safeCall(_print, message)
    end
end

local function envTable()
    local env = nil
    if callable(getgenv) then
        local ok, result = safeCall(getgenv)
        if ok and _type(result) == "table" then
            env = result
        end
    end
    if _type(env) ~= "table" and _type(_G_ref) == "table" then
        env = _G_ref
    end
    return env
end

local function envFunction(name)
    local env = envTable()
    local value = env and env[name]
    if callable(value) then
        return value
    end
    local globalValue = nil
    safeCall(function()
        globalValue = _G_ref and _G_ref[name]
    end)
    if callable(globalValue) then
        return globalValue
    end
    return nil
end

local writefileFn = envFunction("writefile")
local appendfileFn = envFunction("appendfile")
local makefolderFn = envFunction("makefolder")
local isfolderFn = envFunction("isfolder")
local delfileFn = envFunction("delfile")

local folder = "MMScanner"
local bootPath = "MMScanner_boot.txt"
local rootCrashPath = "MMScanner_crash_last.txt"
local statusPath = "MMScanner_status.txt"

local function ensureBaseFolder()
    if not callable(makefolderFn) then
        return false
    end
    if callable(isfolderFn) then
        local ok, exists = safeCall(isfolderFn, folder)
        if ok and exists == true then
            return true
        end
    end
    safeCall(makefolderFn, folder)
    if callable(isfolderFn) then
        local ok, exists = safeCall(isfolderFn, folder)
        return ok and exists == true
    end
    return true
end

local folderAvailable = ensureBaseFolder()

local function writeText(path, text)
    text = safeToString(text)
    if callable(writefileFn) then
        local ok = safeCall(writefileFn, path, text)
        if ok then
            return true
        end
    end
    if callable(appendfileFn) then
        if callable(delfileFn) then
            safeCall(delfileFn, path)
        end
        local ok = safeCall(appendfileFn, path, text)
        if ok then
            return true
        end
    end
    return false
end

local function appendText(path, text)
    text = safeToString(text)
    if callable(appendfileFn) then
        local ok = safeCall(appendfileFn, path, text)
        if ok then
            return true
        end
    end
    if callable(writefileFn) then
        local ok = safeCall(writefileFn, path, text)
        if ok then
            return true
        end
    end
    return false
end

writeText(bootPath, "boot reached: " .. VERSION .. "\n")
writeText(statusPath, "boot reached\n")
if folderAvailable then
    writeText(folder .. "/boot.txt", "boot reached: " .. VERSION .. "\n")
end
safeWarn("boot reached")

local function tracebackMessage(err)
    local message = safeToString(err)
    if _type(debug) == "table" and callable(debug.traceback) then
        local ok, trace = safeCall(debug.traceback, message)
        if ok and trace then
            message = safeToString(trace)
        end
    end
    return message
end

local function protected(name, fn, ...)
    if not callable(fn) then
        return false, "not_function"
    end
    local args = { ... }
    args.n = _select("#", ...)
    local function run()
        if callable(_unpack) then
            return fn(_unpack(args, 1, args.n))
        end
        return fn()
    end
    local handler = function(err)
        return tracebackMessage(err)
    end
    local ok, result
    if callable(_xpcall) then
        ok, result = _xpcall(run, handler)
    else
        ok, result = safeCall(run)
        if not ok then
            result = handler(result)
        end
    end
    if not ok then
        local msg = "section=" .. safeToString(name) .. "\n" .. safeToString(result)
        writeText(rootCrashPath, msg)
        writeText(statusPath, "crash in " .. safeToString(name) .. "\n" .. msg)
        if folderAvailable then
            writeText(folder .. "/crash_last.txt", msg)
        end
        safeWarn(msg)
    end
    return ok, result
end

local function main()
    local function kind(value)
        if callable(typeof) then
            local ok, result = safeCall(typeof, value)
            if ok then
                return result
            end
        end
        return _type(value)
    end

    local function getService(name)
        local ok, service = safeCall(function()
            return _game:GetService(name)
        end)
        if ok then
            return service
        end
        return nil
    end

    if _type(_game) ~= "userdata" and kind(_game) ~= "DataModel" then
        safeWarn("game/DataModel unavailable")
    end

    local Players = getService("Players")
    local LocalPlayer = Players and Players.LocalPlayer or nil

    local env = envTable()
    if _type(env) ~= "table" then
        env = {}
    end

    local previous = env.__MM_REMOTE_SCANNER
    if _type(previous) == "table" and callable(previous.Stop) then
        safeCall(function()
            previous:Stop("replaced")
        end)
    end

    local weakMode = { __mode = "k" }
    local Scanner = {
        active = true,
        buffer = {},
        conns = {},
        counts = {},
        discovered = callable(_setmetatable) and _setmetatable({}, weakMode) or {},
        inbound = callable(_setmetatable) and _setmetatable({}, weakMode) or {},
        fileText = "",
        flushing = false,
        inHook = false,
        lastFlush = 0,
    }

    env.__MM_REMOTE_SCANNER = Scanner

    local function timeNumber()
        if _type(_os) == "table" and callable(_os.time) then
            local ok, value = safeCall(_os.time)
            if ok and value then
                return value
            end
        end
        if callable(tick) then
            local ok, value = safeCall(tick)
            if ok and value then
                return value
            end
        end
        return 0
    end

    local placeId = "unknown"
    safeCall(function()
        placeId = safeToString(_game.PlaceId or "unknown")
    end)

    local startedAt = safeToString(timeNumber())
    local filePath = (folderAvailable and (folder .. "/") or "") .. "scan_" .. placeId .. "_" .. startedAt .. ".log"

    local function now()
        if _type(DateTime) == "table" and DateTime.now then
            local ok, value = safeCall(function()
                return DateTime.now():ToIsoDate()
            end)
            if ok and value then
                return value
            end
        end
        if _type(_os) == "table" and callable(_os.date) then
            local ok, value = safeCall(_os.date, "!%Y-%m-%dT%H:%M:%SZ")
            if ok and value then
                return value
            end
        end
        return safeToString(timeNumber())
    end

    local function fullName(instance)
        local ok, value = safeCall(function()
            return instance:GetFullName()
        end)
        if ok then
            return safeToString(value)
        end
        return safeToString(instance)
    end

    local function prop(instance, name)
        local ok, value = safeCall(function()
            return instance[name]
        end)
        if ok then
            return value
        end
        return nil
    end

    local function isA(instance, className)
        local k = kind(instance)
        if k ~= "Instance" then
            return false
        end
        local ok, value = safeCall(function()
            return instance:IsA(className)
        end)
        return ok and value == true
    end

    local function isRemote(instance)
        return isA(instance, "RemoteEvent") or isA(instance, "RemoteFunction")
    end

    local function stringGsub(text, pattern, repl)
        if _type(_string) == "table" and callable(_string.gsub) then
            local ok, result = safeCall(_string.gsub, text, pattern, repl)
            if ok then
                return result
            end
        end
        return text
    end

    local function stringByte(char)
        if _type(_string) == "table" and callable(_string.byte) then
            local ok, result = safeCall(_string.byte, char)
            if ok and result then
                return result
            end
        end
        return 0
    end

    local function stringFormat(fmt, ...)
        if _type(_string) == "table" and callable(_string.format) then
            local ok, result = safeCall(_string.format, fmt, ...)
            if ok and result then
                return result
            end
        end
        return ""
    end

    local function stringSub(text, a, b)
        if _type(_string) == "table" and callable(_string.sub) then
            local ok, result = safeCall(_string.sub, text, a, b)
            if ok then
                return result
            end
        end
        return text
    end

    local function quote(value)
        value = safeToString(value or "")
        value = stringGsub(value, "\\", "\\\\")
        value = stringGsub(value, "\"", "\\\"")
        value = stringGsub(value, "\b", "\\b")
        value = stringGsub(value, "\f", "\\f")
        value = stringGsub(value, "\n", "\\n")
        value = stringGsub(value, "\r", "\\r")
        value = stringGsub(value, "\t", "\\t")
        value = stringGsub(value, "[%z\1-\31]", function(char)
            return stringFormat("\\u%04x", stringByte(char))
        end)
        return "\"" .. value .. "\""
    end

    local function isArray(tbl)
        if _type(tbl) ~= "table" then
            return false
        end
        local count = 0
        local maxIndex = 0
        for key in _pairs(tbl) do
            if _type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
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
        local valueType = _type(value)
        if value == nil then
            return "null"
        end
        if valueType == "boolean" or valueType == "number" then
            return safeToString(value)
        end
        if valueType == "string" then
            return quote(value)
        end
        if valueType ~= "table" then
            return quote(safeToString(value))
        end
        if depth > 6 then
            return quote("[max-depth]")
        end

        local parts = {}
        if isArray(value) then
            for index = 1, #value do
                parts[#parts + 1] = encode(value[index], depth + 1)
            end
            return "[" .. _table.concat(parts, ",") .. "]"
        end

        for key, item in _pairs(value) do
            parts[#parts + 1] = quote(safeToString(key)) .. ":" .. encode(item, depth + 1)
        end
        if _type(_table) == "table" and callable(_table.sort) then
            safeCall(_table.sort, parts)
        end
        return "{" .. _table.concat(parts, ",") .. "}"
    end

    local function shortString(value, maxLength)
        value = safeToString(value)
        maxLength = maxLength or 300
        if #value > maxLength then
            return stringSub(value, 1, maxLength) .. "...[truncated]"
        end
        return value
    end

    local function numberValue(value)
        if _type(value) ~= "number" then
            return safeToString(value)
        end
        if _type(_math) == "table" and callable(_math.floor) then
            local ok, rounded = safeCall(function()
                return _math.floor(value * 10000 + 0.5) / 10000
            end)
            if ok then
                return rounded
            end
        end
        return value
    end

    local function tableCount(tbl)
        local n = 0
        if _type(tbl) == "table" then
            for _ in _pairs(tbl) do
                n = n + 1
            end
        end
        return n
    end

    local serialize
    serialize = function(value, depth, seen)
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
                class = safeToString(prop(value, "ClassName") or "Unknown"),
                name = safeToString(prop(value, "Name") or "Unknown"),
                path = fullName(value),
            }
        end
        if valueType == "Vector2" then
            return { type = "Vector2", x = numberValue(value.X), y = numberValue(value.Y) }
        end
        if valueType == "Vector3" then
            return { type = "Vector3", x = numberValue(value.X), y = numberValue(value.Y), z = numberValue(value.Z) }
        end
        if valueType == "CFrame" then
            local ok, components = safeCall(function()
                return { value:GetComponents() }
            end)
            return { type = "CFrame", components = ok and components or safeToString(value) }
        end
        if valueType == "Color3" then
            return { type = "Color3", r = numberValue(value.R), g = numberValue(value.G), b = numberValue(value.B) }
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
            return { type = "EnumItem", value = safeToString(value) }
        end
        if valueType == "Ray" then
            return { type = "Ray", origin = serialize(value.Origin, depth + 1, seen), direction = serialize(value.Direction, depth + 1, seen) }
        end
        if valueType == "table" then
            if seen[value] then
                return { type = "table", circular = true }
            end
            if depth >= 3 then
                return { type = "table", count = tableCount(value), truncated = "max-depth" }
            end
            seen[value] = true
            local entries = {}
            local total = 0
            for key, item in _pairs(value) do
                total = total + 1
                if #entries < 40 then
                    entries[#entries + 1] = { key = shortString(key, 120), keyType = kind(key), value = serialize(item, depth + 1, seen) }
                end
            end
            seen[value] = nil
            return { type = "table", count = total, entries = entries, truncated = total > #entries }
        end
        return { type = safeToString(valueType), value = shortString(value, 300) }
    end

    local function packArgs(...)
        local count = _select("#", ...)
        local values = {}
        local limit = count
        if limit > 20 then
            limit = 20
        end
        for index = 1, limit do
            local ok, result = safeCall(function()
                return serialize(_select(index, ...))
            end)
            values[index] = ok and result or { type = "serialization_error", value = shortString(result, 300) }
        end
        return { count = count, values = values, truncated = count > limit }
    end

    local function remoteInfo(remote)
        return {
            class = safeToString(prop(remote, "ClassName") or "Unknown"),
            name = safeToString(prop(remote, "Name") or "Unknown"),
            path = fullName(remote),
        }
    end

    local function inc(eventName)
        eventName = eventName or "unknown"
        Scanner.counts[eventName] = (Scanner.counts[eventName] or 0) + 1
    end

    local function flush()
        if Scanner.flushing or #Scanner.buffer == 0 then
            return
        end
        Scanner.flushing = true
        local chunk = _table.concat(Scanner.buffer, "\n") .. "\n"
        Scanner.buffer = {}
        Scanner.fileText = (Scanner.fileText or "") .. chunk
        if #Scanner.fileText > 4000000 then
            Scanner.fileText = stringSub(Scanner.fileText, #Scanner.fileText - 3000000)
            Scanner.fileText = "{\"event\":\"scanner_file_trimmed\",\"time\":" .. quote(now()) .. "}\n" .. Scanner.fileText
        end
        writeText(filePath, Scanner.fileText)
        Scanner.flushing = false
    end

    local function logRecord(record)
        if not Scanner.active then
            return
        end
        record.time = now()
        local ok, encoded = safeCall(function()
            return encode(record)
        end)
        if not ok then
            encoded = encode({ event = "encode_error", message = shortString(encoded, 500) })
        end
        Scanner.buffer[#Scanner.buffer + 1] = encoded
        inc(record.event or "unknown")
        if #Scanner.buffer >= 75 then
            flush()
        end
    end

    function Scanner:Connect(signal, callback)
        if not self.active or not signal or not callable(callback) then
            return nil
        end
        local ok, conn = safeCall(function()
            if signal.Connect then
                return signal:Connect(callback)
            end
            return nil
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
        logRecord({ event = "scanner_stop", reason = safeToString(reason or "manual") })
        self.active = false
        for _, conn in _ipairs(self.conns) do
            safeCall(function()
                if conn and conn.Disconnect then
                    conn:Disconnect()
                end
            end)
        end
        flush()
    end

    writeText(filePath, "")

    local function attachInbound(remote)
        if Scanner.inbound[remote] or not isA(remote, "RemoteEvent") then
            return
        end
        Scanner.inbound[remote] = true
        local signal = prop(remote, "OnClientEvent")
        Scanner:Connect(signal, function(...)
            protected("OnClientEvent", function(...)
                logRecord({ event = "remote_inbound", method = "OnClientEvent", remote = remoteInfo(remote), args = packArgs(...) })
            end, ...)
        end)
    end

    local function rememberRemote(remote)
        if not isRemote(remote) or Scanner.discovered[remote] then
            return
        end
        Scanner.discovered[remote] = true
        logRecord({ event = "remote_discovered", remote = remoteInfo(remote) })
        attachInbound(remote)
    end

    local RunService = getService("RunService")

    local function safeWait(seconds)
        if _type(task) == "table" and callable(task.wait) then
            local ok = safeCall(task.wait, seconds)
            if ok then
                return
            end
        end
        if callable(wait) then
            safeCall(wait, seconds)
            return
        end
        if _type(RunService) == "userdata" or kind(RunService) == "Instance" then
            local heartbeat = prop(RunService, "Heartbeat")
            if heartbeat and heartbeat.Wait then
                safeCall(function()
                    heartbeat:Wait()
                end)
                return
            end
        end
    end

    local function scanRoot(root)
        if not root or not Scanner.active then
            return
        end
        rememberRemote(root)
        local ok, descendants = safeCall(function()
            return root:GetDescendants()
        end)
        if ok and _type(descendants) == "table" then
            for index, instance in _ipairs(descendants) do
                rememberRemote(instance)
                if index % 250 == 0 then
                    safeWait()
                end
            end
        end
        local signal = prop(root, "DescendantAdded")
        Scanner:Connect(signal, function(instance)
            if _type(task) == "table" and callable(task.defer) then
                local okDefer = safeCall(task.defer, function()
                    protected("descendant_added", function()
                        rememberRemote(instance)
                    end)
                end)
                if okDefer then
                    return
                end
            end
            protected("descendant_added_direct", function()
                rememberRemote(instance)
            end)
        end)
    end

    local function roots()
        local list = {}
        local names = { "ReplicatedStorage", "ReplicatedFirst", "Workspace", "Lighting", "StarterGui", "StarterPack", "StarterPlayer" }
        for _, name in _ipairs(names) do
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
            if playerGui then list[#list + 1] = playerGui end
            if backpack then list[#list + 1] = backpack end
            if character then list[#list + 1] = character end
        end
        return list
    end

    local function makeClosure(fn)
        local newcclosureFn = envFunction("newcclosure")
        if callable(newcclosureFn) then
            local ok, result = safeCall(newcclosureFn, fn)
            if ok and callable(result) then
                return result
            end
        end
        return fn
    end

    local function logOutbound(method, remote, ...)
        if Scanner.active and not Scanner.inHook and (method == "FireServer" or method == "InvokeServer") and isRemote(remote) then
            Scanner.inHook = true
            protected("remote_outbound", function(...)
                logRecord({ event = "remote_outbound", method = method, remote = remoteInfo(remote), args = packArgs(...) })
            end, ...)
            Scanner.inHook = false
        end
    end

    local function installNamecallHook()
        local hookmetamethodFn = envFunction("hookmetamethod")
        local getnamecallmethodFn = envFunction("getnamecallmethod")
        if callable(hookmetamethodFn) and callable(getnamecallmethodFn) then
            local original = nil
            local replacement
            replacement = makeClosure(function(self, ...)
                local method = nil
                safeCall(function()
                    method = getnamecallmethodFn()
                end)
                logOutbound(method, self, ...)
                if callable(original) then
                    return original(self, ...)
                end
                if method and self then
                    local direct = nil
                    safeCall(function()
                        direct = self[method]
                    end)
                    if callable(direct) then
                        return direct(self, ...)
                    end
                end
                return nil
            end)
            local ok, result = safeCall(hookmetamethodFn, _game, "__namecall", replacement)
            if ok and callable(result) then
                original = result
                Scanner.namecallHook = "hookmetamethod"
                return true
            end
            logRecord({ event = "scanner_hook_failed", method = "hookmetamethod", reason = ok and "original_missing" or shortString(result, 300) })
            return false
        end

        local getrawmetatableFn = envFunction("getrawmetatable")
        local setreadonlyFn = envFunction("setreadonly")
        local makewriteableFn = envFunction("makewriteable") or envFunction("make_writeable")
        local makereadonlyFn = envFunction("makereadonly") or envFunction("make_readonly")
        if not callable(getrawmetatableFn) or not callable(getnamecallmethodFn) then
            return false
        end
        if not callable(setreadonlyFn) and not callable(makewriteableFn) then
            return false
        end
        local okMt, mt = safeCall(getrawmetatableFn, _game)
        if not okMt or _type(mt) ~= "table" or not callable(mt.__namecall) then
            return false
        end
        local original = mt.__namecall
        if callable(setreadonlyFn) then
            safeCall(setreadonlyFn, mt, false)
        elseif callable(makewriteableFn) then
            safeCall(makewriteableFn, mt)
        end
        mt.__namecall = makeClosure(function(self, ...)
            local method = nil
            safeCall(function()
                method = getnamecallmethodFn()
            end)
            logOutbound(method, self, ...)
            return original(self, ...)
        end)
        if callable(setreadonlyFn) then
            safeCall(setreadonlyFn, mt, true)
        elseif callable(makereadonlyFn) then
            safeCall(makereadonlyFn, mt)
        end
        Scanner.namecallHook = "rawmetatable"
        return true
    end

    logRecord({
        event = "scanner_start",
        version = VERSION,
        file = filePath,
        placeId = prop(_game, "PlaceId"),
        jobId = safeToString(prop(_game, "JobId") or ""),
        localPlayer = LocalPlayer and { name = safeToString(prop(LocalPlayer, "Name") or ""), userId = prop(LocalPlayer, "UserId") } or nil,
        capabilities = {
            writefile = callable(writefileFn),
            appendfile = callable(appendfileFn),
            hookmetamethod = callable(envFunction("hookmetamethod")),
            getnamecallmethod = callable(envFunction("getnamecallmethod")),
        },
    })

    local hookInstalled = protected("installNamecallHook", installNamecallHook)
    logRecord({ event = "scanner_hook_status", installed = hookInstalled == true, method = Scanner.namecallHook or "none" })

    local function spawnTask(name, callback)
        local runner = function()
            protected(name, callback)
        end
        if _type(task) == "table" and callable(task.spawn) then
            local ok = safeCall(task.spawn, runner)
            if ok then
                return
            end
        end
        if callable(spawn) then
            local ok = safeCall(spawn, runner)
            if ok then
                return
            end
        end
        if _type(_coroutine) == "table" and callable(_coroutine.wrap) then
            local ok, wrapped = safeCall(_coroutine.wrap, runner)
            if ok and callable(wrapped) then
                safeCall(wrapped)
                return
            end
        end
        runner()
    end

    spawnTask("initial_scan", function()
        for _, root in _ipairs(roots()) do
            if Scanner.active then
                scanRoot(root)
            end
        end
        if LocalPlayer then
            Scanner:Connect(prop(LocalPlayer, "CharacterAdded"), function(character)
                protected("character_added", function()
                    scanRoot(character)
                end)
            end)
        end
        flush()
    end)

    spawnTask("flush_loop", function()
        while Scanner.active do
            safeWait(2)
            flush()
        end
    end)

    spawnTask("heartbeat_loop", function()
        while Scanner.active do
            safeWait(15)
            logRecord({ event = "scanner_heartbeat", counts = Scanner.counts, bufferSize = #Scanner.buffer })
            flush()
        end
    end)

    flush()
    writeText(statusPath, "running: " .. VERSION .. "\nfile: " .. filePath .. "\n")
    if folderAvailable then
        writeText(folder .. "/status.txt", "running: " .. VERSION .. "\nfile: " .. filePath .. "\n")
    end
    safeWarn("running; output: " .. filePath)
end

local ok, err = protected("main", main)
if not ok then
    safeWarn("main failed; check MMScanner_crash_last.txt")
end
