local VERSION = "2026-06-01-mm-scanner-tester-v5"
local ENABLE_OUTBOUND_HOOK = true
local ENABLE_TESTER_UI = true

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
    return false
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
local makefolderFn = envFunction("makefolder")
local isfolderFn = envFunction("isfolder")
local delfileFn = envFunction("delfile")

local folder = "MMScanner"
local bootPath = "MMScanner_boot.txt"
local bootVisiblePath = "MMScanner_BOOT_REACHED.txt"
local rootCrashPath = "MMScanner_crash_last.txt"
local statusPath = "MMScanner_status.txt"
local runningPath = "MMScanner_RUNNING.txt"
local testerPath = "MMScanner_TESTER.txt"

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
    return false
end

local function appendText(path, text)
    text = safeToString(text)
    if callable(writefileFn) then
        local ok = safeCall(writefileFn, path, text)
        if ok then
            return true
        end
    end
    return false
end

local function showStatus(message, lifetime)
    message = safeToString(message)
    lifetime = lifetime or 5

    safeCall(function()
        if not _game or _type(Instance) ~= "table" or not callable(Instance.new) then
            return
        end

        local players = _game:GetService("Players")
        local localPlayer = players and players.LocalPlayer
        if not localPlayer then
            return
        end

        local playerGui = nil
        safeCall(function()
            playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        end)
        if not playerGui then
            safeCall(function()
                playerGui = localPlayer:WaitForChild("PlayerGui", 2)
            end)
        end
        if not playerGui then
            return
        end

        safeCall(function()
            local old = playerGui:FindFirstChild("MMScannerStatus")
            if old then
                old:Destroy()
            end
        end)

        local gui = Instance.new("ScreenGui")
        gui.Name = "MMScannerStatus"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 999999

        local label = Instance.new("TextLabel")
        label.Name = "Status"
        label.AnchorPoint = Vector2.new(0.5, 0)
        label.Position = UDim2.new(0.5, 0, 0, 18)
        label.Size = UDim2.new(0, 360, 0, 34)
        label.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
        label.BackgroundTransparency = 0.08
        label.BorderSizePixel = 0
        label.Text = message
        label.TextColor3 = Color3.fromRGB(235, 255, 235)
        label.TextSize = 14
        label.Font = Enum.Font.GothamSemibold
        label.TextWrapped = true
        label.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = label

        gui.Parent = playerGui

        local destroyGui = function()
            safeCall(function()
                if gui and gui.Parent then
                    gui:Destroy()
                end
            end)
        end

        if _type(task) == "table" and callable(task.delay) then
            task.delay(lifetime, destroyGui)
        elseif callable(delay) then
            delay(lifetime, destroyGui)
        elseif callable(spawn) then
            spawn(function()
                if callable(wait) then
                    wait(lifetime)
                end
                destroyGui()
            end)
        end
    end)
end

writeText(bootPath, "boot reached: " .. VERSION .. "\n")
writeText(bootVisiblePath, "boot reached: " .. VERSION .. "\n")
writeText(statusPath, "boot reached\n")
if folderAvailable then
    writeText(folder .. "/boot.txt", "boot reached: " .. VERSION .. "\n")
end
showStatus("MMScanner boot reached", 4)

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
        showStatus("MMScanner crashed - check crash file", 8)
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
    local filePath = "MMScanner_scan_" .. placeId .. "_" .. startedAt .. ".log"

    local function now()
        -- Do not use DateTime.now():ToIsoDate() here.
        -- In some executors, calling any namecall while a __namecall hook is forwarding
        -- can corrupt the pending method and break remotes such as FireServer.
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
        local rawArgs = { ... }
        local values = {}
        local limit = count
        if limit > 20 then
            limit = 20
        end
        for index = 1, limit do
            local item = rawArgs[index]
            local ok, result = safeCall(function()
                return serialize(item)
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

    local function lowerText(value)
        value = safeToString(value or "")
        if _type(_string) == "table" and callable(_string.lower) then
            local ok, result = safeCall(_string.lower, value)
            if ok and result then
                return result
            end
        end
        return value
    end

    local function containsText(text, needle)
        text = lowerText(text)
        needle = lowerText(needle)
        if _type(_string) == "table" and callable(_string.find) then
            local ok, result = safeCall(_string.find, text, needle, 1, true)
            return ok and result ~= nil
        end
        return false
    end

    local function simpleRemotePath(remote)
        local parts = {}
        local current = remote
        local depth = 0
        while current and depth < 10 do
            local name = prop(current, "Name")
            if name then
                parts[#parts + 1] = safeToString(name)
            end
            current = prop(current, "Parent")
            depth = depth + 1
        end

        local ordered = {}
        for index = #parts, 1, -1 do
            ordered[#ordered + 1] = parts[index]
        end

        if _type(_table) == "table" and callable(_table.concat) then
            local ok, result = safeCall(_table.concat, ordered, ".")
            if ok and result then
                return result
            end
        end
        return safeToString(prop(remote, "Name") or "")
    end

    local function shouldCaptureOutbound(remote, method)
        if method ~= "FireServer" and method ~= "InvokeServer" then
            return false
        end

        local className = safeToString(prop(remote, "ClassName") or "")
        if className ~= "RemoteEvent" and className ~= "RemoteFunction" then
            return false
        end

        local path = simpleRemotePath(remote)
        local tokens = {
            "gun",
            "knife",
            "weapon",
            "shoot",
            "stab",
            "touch",
            "throw",
            "hit",
            "beam",
        }

        for _, token in _ipairs(tokens) do
            if containsText(path, token) then
                return true
            end
        end

        return false
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
        if Scanner.active and not Scanner.inHook and shouldCaptureOutbound(remote, method) then
            Scanner.inHook = true
            protected("remote_outbound", function(...)
                logRecord({ event = "remote_outbound", method = method, remote = remoteInfo(remote), args = packArgs(...) })
            end, ...)
            Scanner.inHook = false
        end
    end

    local function installNamecallHook()
        if ENABLE_OUTBOUND_HOOK ~= true then
            logRecord({
                event = "scanner_hook_skipped",
                reason = "outbound hook disabled to avoid interfering with RemoteEvent/RemoteFunction calls"
            })
            return false
        end

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

                if callable(original) then
                    if Scanner.active and not Scanner.inHook and shouldCaptureOutbound(self, method) then
                        local argc = _select("#", ...)
                        local rawArgs = { ... }
                        local results = { original(self, ...) }
                        protected("remote_outbound_after_forward", function()
                            logOutbound(method, self, _unpack(rawArgs, 1, argc))
                        end)
                        return _unpack(results)
                    end
                    return original(self, ...)
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
            if Scanner.active and not Scanner.inHook and shouldCaptureOutbound(self, method) then
                local argc = _select("#", ...)
                local rawArgs = { ... }
                local results = { original(self, ...) }
                protected("remote_outbound_after_forward", function()
                    logOutbound(method, self, _unpack(rawArgs, 1, argc))
                end)
                return _unpack(results)
            end
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
            hookmetamethod = callable(envFunction("hookmetamethod")),
            getnamecallmethod = callable(envFunction("getnamecallmethod")),
        },
        outboundMode = ENABLE_OUTBOUND_HOOK and "selective_weapon_remotes" or "disabled",
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
    local runningText = "running: " .. VERSION .. "\nmode: selective weapon outbound hook\nfile: " .. filePath .. "\nhook: " .. safeToString(Scanner.namecallHook or "none") .. "\n"
    writeText(statusPath, runningText)
    writeText(runningPath, runningText)
    if folderAvailable then
        writeText(folder .. "/status.txt", runningText)
        writeText(folder .. "/RUNNING.txt", runningText)
    end
    showStatus("MMScanner running - weapon outbound ON", 7)
    safeWarn("running; output: " .. filePath)
end

local ok, err = protected("main", main)
if not ok then
    safeWarn("main failed; check MMScanner_crash_last.txt")
end

local function installTester()
    if ENABLE_TESTER_UI ~= true then
        return
    end

    local Players = nil
    local LocalPlayer = nil
    safeCall(function()
        Players = _game:GetService("Players")
        LocalPlayer = Players and Players.LocalPlayer
    end)
    if not Players or not LocalPlayer then
        writeText(testerPath, "tester failed: players/localplayer unavailable\n")
        return
    end

    local testerState = {
        last = "ready",
        targetIndex = 0,
        selectedPlayerName = nil,
        selectedPart = "UpperTorso",
        partIndex = 1,
        predictionIndex = 3,
        cooldownIndex = 2,
        pingPrediction = true,
        lastAction = 0,
    }

    local partOptions = { "UpperTorso", "Head", "HumanoidRootPart", "Torso", "LeftUpperArm", "RightUpperArm" }
    local predictionOptions = { 0, 0.08, 0.12, 0.18, 0.25, 0.35 }
    local cooldownOptions = { 0.1, 0.25, 0.45, 0.75, 1.25 }

    local function testerLog(message)
        message = safeToString(message)
        testerState.last = message
        writeText(testerPath, message .. "\n")
        if folderAvailable then
            writeText(folder .. "/TESTER.txt", message .. "\n")
        end
        showStatus(message, 4)
    end

    local function testerFullName(instance)
        local value = nil
        safeCall(function()
            value = instance:GetFullName()
        end)
        return safeToString(value or instance)
    end

    local function testerTime()
        if _type(_os) == "table" and callable(_os.clock) then
            local okClock, value = safeCall(_os.clock)
            if okClock and value then
                return value
            end
        end
        if callable(tick) then
            local okTick, value = safeCall(tick)
            if okTick and value then
                return value
            end
        end
        return 0
    end

    local function canRunAction(name)
        local nowValue = testerTime()
        local cooldown = cooldownOptions[testerState.cooldownIndex] or 0.25
        if nowValue - testerState.lastAction < cooldown then
            testerLog(safeToString(name) .. " cooldown")
            return false
        end
        testerState.lastAction = nowValue
        return true
    end

    local function getPingSeconds()
        local pingMs = 0
        safeCall(function()
            local stats = _game:GetService("Stats")
            local network = stats and stats:FindFirstChild("Network")
            local serverStats = network and network:FindFirstChild("ServerStatsItem")
            local dataPing = serverStats and serverStats:FindFirstChild("Data Ping")
            if dataPing and dataPing.GetValue then
                pingMs = dataPing:GetValue()
            end
        end)
        if _type(pingMs) ~= "number" then
            pingMs = 0
        end
        if pingMs > 1000 then
            pingMs = 1000
        end
        return pingMs / 1000
    end

    local function predictionSeconds()
        local base = predictionOptions[testerState.predictionIndex] or 0
        if testerState.pingPrediction then
            base = base + (getPingSeconds() * 0.5)
        end
        if base > 0.65 then
            base = 0.65
        end
        return base
    end

    local function getCharacter(player)
        return player and (player.Character or nil)
    end

    local function getBackpack()
        local backpack = nil
        safeCall(function()
            backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        end)
        safeCall(function()
            backpack = backpack or LocalPlayer:FindFirstChild("Backpack")
        end)
        return backpack
    end

    local function findChild(root, name, recursive)
        if not root then
            return nil
        end
        local result = nil
        safeCall(function()
            result = root:FindFirstChild(name, recursive == true)
        end)
        return result
    end

    local function isAlive(character)
        if not character then
            return false
        end
        local humanoid = findChild(character, "Humanoid", false)
        if not humanoid then
            return true
        end
        local health = 0
        safeCall(function()
            health = humanoid.Health
        end)
        return health > 0
    end

    local function getPart(character, preferredName)
        if not character then
            return nil
        end
        local names = {}
        if preferredName and preferredName ~= "" then
            names[#names + 1] = preferredName
        end
        for _, name in _ipairs(partOptions) do
            if name ~= preferredName then
                names[#names + 1] = name
            end
        end
        for _, name in _ipairs(names) do
            local part = findChild(character, name, false)
            if part then
                return part
            end
        end
        local children = {}
        safeCall(function()
            children = character:GetChildren()
        end)
        for _, child in _ipairs(children) do
            local ok, isPart = safeCall(function()
                return child:IsA("BasePart")
            end)
            if ok and isPart then
                return child
            end
        end
        return nil
    end

    local function partPosition(part)
        local pos = nil
        safeCall(function()
            pos = part.Position
        end)
        return pos
    end

    local function partVelocity(part)
        local velocity = nil
        safeCall(function()
            velocity = part.AssemblyLinearVelocity
        end)
        if not velocity then
            safeCall(function()
                velocity = part.Velocity
            end)
        end
        return velocity
    end

    local function predictedPartPosition(part)
        local pos = partPosition(part)
        if not pos then
            return nil
        end
        local lead = predictionSeconds()
        if lead <= 0 then
            return pos
        end
        local velocity = partVelocity(part)
        if not velocity then
            return pos
        end
        local ok, predicted = safeCall(function()
            return pos + (velocity * lead)
        end)
        if ok and predicted then
            return predicted
        end
        return pos
    end

    local function distance(a, b)
        local ok, result = safeCall(function()
            return (a - b).Magnitude
        end)
        if ok and result then
            return result
        end
        return 999999
    end

    local function getPlayersList()
        local players = {}
        safeCall(function()
            players = Players:GetPlayers()
        end)
        local result = {}
        for _, player in _ipairs(players) do
            if player ~= LocalPlayer and isAlive(getCharacter(player)) then
                result[#result + 1] = player
            end
        end
        return result
    end

    local function selectedPlayer()
        if not testerState.selectedPlayerName then
            return nil
        end
        local players = getPlayersList()
        for _, player in _ipairs(players) do
            if safeToString(player.Name) == testerState.selectedPlayerName then
                return player
            end
        end
        testerState.selectedPlayerName = nil
        testerState.targetIndex = 0
        return nil
    end

    local function nearestTarget()
        local myCharacter = getCharacter(LocalPlayer)
        local myPart = getPart(myCharacter, "HumanoidRootPart")
        local myPos = myPart and partPosition(myPart)
        if not myPos then
            return nil, nil, "no local position"
        end

        local lockedPlayer = selectedPlayer()
        if lockedPlayer then
            local lockedCharacter = getCharacter(lockedPlayer)
            local lockedPart = getPart(lockedCharacter, testerState.selectedPart)
            if lockedPart then
                return lockedPlayer, lockedPart, "target " .. safeToString(lockedPlayer.Name) .. " part " .. safeToString(lockedPart.Name)
            end
            return nil, nil, "selected target missing part"
        end

        local players = getPlayersList()
        local bestPlayer = nil
        local bestPart = nil
        local bestDistance = 999999
        for _, player in _ipairs(players) do
            local character = getCharacter(player)
            local part = getPart(character, testerState.selectedPart)
            local pos = part and partPosition(part)
            if pos then
                local dist = distance(myPos, pos)
                if dist < bestDistance then
                    bestDistance = dist
                    bestPlayer = player
                    bestPart = part
                end
            end
        end

        if not bestPart then
            return nil, nil, "no target"
        end
        return bestPlayer, bestPart, "target " .. safeToString(bestPlayer.Name) .. " part " .. safeToString(bestPart.Name)
    end

    local function equipTool(name)
        local character = getCharacter(LocalPlayer)
        local backpack = getBackpack()
        local tool = findChild(character, name, false) or findChild(backpack, name, false)
        if not tool then
            return nil, "missing " .. name
        end

        if character and tool.Parent ~= character then
            local humanoid = findChild(character, "Humanoid", false)
            if humanoid then
                safeCall(function()
                    humanoid:EquipTool(tool)
                end)
            end
        end

        return tool, "ok"
    end

    local function findToolRemote(toolName, remotePath)
        local character = getCharacter(LocalPlayer)
        local backpack = getBackpack()
        local tool = findChild(character, toolName, false) or findChild(backpack, toolName, false)
        if not tool then
            tool = equipTool(toolName)
        end
        if not tool then
            return nil, nil, "missing " .. toolName
        end

        local current = tool
        for _, name in _ipairs(remotePath) do
            current = findChild(current, name, false)
            if not current then
                local text = ""
                safeCall(function()
                    text = _table.concat(remotePath, ".")
                end)
                return tool, nil, "missing remote " .. safeToString(text)
            end
        end
        return tool, current, "ok"
    end

    local function makeShotCFrames(originPart, targetPart)
        local originPos = partPosition(originPart)
        local targetPos = predictedPartPosition(targetPart)
        if not originPos or not targetPos then
            return nil, nil, "missing positions"
        end
        local originCf = nil
        local targetCf = nil
        local ok = safeCall(function()
            originCf = CFrame.new(originPos, targetPos)
            targetCf = CFrame.new(targetPos)
        end)
        if not ok or not originCf or not targetCf then
            return nil, nil, "cframe build failed"
        end
        return originCf, targetCf, "ok"
    end

    local Tester = {}

    function Tester.ShootTarget()
        if not canRunAction("Shoot") then
            return false
        end
        local tool, remote, remoteStatus = findToolRemote("Gun", { "Shoot" })
        if not remote then
            testerLog("Shoot failed: " .. safeToString(remoteStatus))
            return false
        end

        local _, targetPart, targetStatus = nearestTarget()
        if not targetPart then
            testerLog("Shoot failed: " .. safeToString(targetStatus))
            return false
        end

        local handle = findChild(tool, "Handle", false) or getPart(getCharacter(LocalPlayer))
        local originCf, targetCf, cfStatus = makeShotCFrames(handle, targetPart)
        if not originCf then
            testerLog("Shoot failed: " .. safeToString(cfStatus))
            return false
        end

        local okFire, errFire = safeCall(function()
            remote:FireServer(originCf, targetCf)
        end)
        testerLog(okFire and ("Shoot fired -> " .. testerFullName(targetPart) .. " pred=" .. safeToString(predictionSeconds())) or ("Shoot failed: " .. safeToString(errFire)))
        return okFire
    end

    function Tester.ThrowKnife()
        if not canRunAction("Throw") then
            return false
        end
        local tool, remote, remoteStatus = findToolRemote("Knife", { "Events", "KnifeThrown" })
        if not remote then
            testerLog("Throw failed: " .. safeToString(remoteStatus))
            return false
        end

        local _, targetPart, targetStatus = nearestTarget()
        if not targetPart then
            testerLog("Throw failed: " .. safeToString(targetStatus))
            return false
        end

        local handle = findChild(tool, "Handle", false) or getPart(getCharacter(LocalPlayer))
        local originCf, targetCf, cfStatus = makeShotCFrames(handle, targetPart)
        if not originCf then
            testerLog("Throw failed: " .. safeToString(cfStatus))
            return false
        end

        local okFire, errFire = safeCall(function()
            remote:FireServer(originCf, targetCf)
        end)
        testerLog(okFire and ("Knife thrown -> " .. testerFullName(targetPart) .. " pred=" .. safeToString(predictionSeconds())) or ("Throw failed: " .. safeToString(errFire)))
        return okFire
    end

    function Tester.TouchTarget()
        if not canRunAction("Touch") then
            return false
        end
        local _, remote, remoteStatus = findToolRemote("Knife", { "Events", "HandleTouched" })
        if not remote then
            testerLog("Touch failed: " .. safeToString(remoteStatus))
            return false
        end

        local _, targetPart, targetStatus = nearestTarget()
        if not targetPart then
            testerLog("Touch failed: " .. safeToString(targetStatus))
            return false
        end

        local okFire, errFire = safeCall(function()
            remote:FireServer(targetPart)
        end)
        testerLog(okFire and ("Knife touch -> " .. testerFullName(targetPart)) or ("Touch failed: " .. safeToString(errFire)))
        return okFire
    end

    function Tester.StabTarget()
        if not canRunAction("Stab") then
            return false
        end
        local _, stabRemote, stabStatus = findToolRemote("Knife", { "Events", "KnifeStabbed" })
        if not stabRemote then
            testerLog("Stab failed: " .. safeToString(stabStatus))
            return false
        end

        local okStab, errStab = safeCall(function()
            stabRemote:FireServer()
        end)
        if not okStab then
            testerLog("Stab failed: " .. safeToString(errStab))
            return false
        end

        local oldLastAction = testerState.lastAction
        testerState.lastAction = 0
        Tester.TouchTarget()
        testerState.lastAction = oldLastAction
        testerLog("Stab fired")
        return true
    end

    local env = envTable()
    if _type(env) == "table" then
        env.__MM_TESTER = Tester
        env.__MM_TESTER_STATE = testerState
    end

    local stateLabels = {}

    local function currentTargetText()
        local player = selectedPlayer()
        if player then
            return "Target: " .. safeToString(player.Name)
        end
        return "Target: nearest"
    end

    local function refreshUi()
        local labels = {
            target = currentTargetText(),
            part = "Part: " .. safeToString(testerState.selectedPart),
            prediction = "Pred: " .. safeToString(predictionOptions[testerState.predictionIndex] or 0),
            ping = testerState.pingPrediction and "Ping: on" or "Ping: off",
            cooldown = "CD: " .. safeToString(cooldownOptions[testerState.cooldownIndex] or 0.25),
        }
        for key, text in _pairs(labels) do
            local label = stateLabels[key]
            if label then
                safeCall(function()
                    label.Text = text
                end)
            end
        end
    end

    function Tester.CycleTarget()
        local players = getPlayersList()
        if #players == 0 then
            testerState.targetIndex = 0
            testerState.selectedPlayerName = nil
            testerLog("Target: no players")
            refreshUi()
            return nil
        end

        testerState.targetIndex = (testerState.targetIndex or 0) + 1
        if testerState.targetIndex > #players then
            testerState.targetIndex = 0
            testerState.selectedPlayerName = nil
            testerLog("Target: nearest")
        else
            local player = players[testerState.targetIndex]
            testerState.selectedPlayerName = safeToString(player.Name)
            testerLog("Target: " .. testerState.selectedPlayerName)
        end
        refreshUi()
        return testerState.selectedPlayerName
    end

    function Tester.CyclePart()
        testerState.partIndex = (testerState.partIndex or 1) + 1
        if testerState.partIndex > #partOptions then
            testerState.partIndex = 1
        end
        testerState.selectedPart = partOptions[testerState.partIndex] or "UpperTorso"
        testerLog("Part: " .. safeToString(testerState.selectedPart))
        refreshUi()
        return testerState.selectedPart
    end

    function Tester.CyclePrediction()
        testerState.predictionIndex = (testerState.predictionIndex or 1) + 1
        if testerState.predictionIndex > #predictionOptions then
            testerState.predictionIndex = 1
        end
        testerLog("Prediction: " .. safeToString(predictionOptions[testerState.predictionIndex] or 0))
        refreshUi()
        return predictionOptions[testerState.predictionIndex]
    end

    function Tester.TogglePingPrediction()
        testerState.pingPrediction = not testerState.pingPrediction
        testerLog(testerState.pingPrediction and "Ping prediction on" or "Ping prediction off")
        refreshUi()
        return testerState.pingPrediction
    end

    function Tester.CycleCooldown()
        testerState.cooldownIndex = (testerState.cooldownIndex or 1) + 1
        if testerState.cooldownIndex > #cooldownOptions then
            testerState.cooldownIndex = 1
        end
        testerLog("Cooldown: " .. safeToString(cooldownOptions[testerState.cooldownIndex] or 0.25))
        refreshUi()
        return cooldownOptions[testerState.cooldownIndex]
    end

    local function makeButton(parent, text, y, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -12, 0, 30)
        button.Position = UDim2.new(0, 6, 0, y)
        button.BackgroundColor3 = Color3.fromRGB(36, 41, 48)
        button.BorderSizePixel = 0
        button.TextColor3 = Color3.fromRGB(245, 245, 245)
        button.TextSize = 13
        button.Font = Enum.Font.GothamSemibold
        button.Text = text
        button.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = button

        button.MouseButton1Click:Connect(function()
            protected("tester_button_" .. text, callback)
        end)

        return button
    end

    local function makeStateButton(parent, key, y, callback)
        local button = makeButton(parent, "", y, callback)
        stateLabels[key] = button
        return button
    end

    local function createUi()
        safeCall(function()
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 2)
            if not playerGui then
                testerLog("Tester ready: no PlayerGui")
                return
            end

            local old = playerGui:FindFirstChild("MMWeaponTester")
            if old then
                old:Destroy()
            end

            local gui = Instance.new("ScreenGui")
            gui.Name = "MMWeaponTester"
            gui.ResetOnSpawn = false
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = 999998

            local frame = Instance.new("Frame")
            frame.Name = "Panel"
            frame.AnchorPoint = Vector2.new(1, 0.5)
            frame.Position = UDim2.new(1, -14, 0.5, 0)
            frame.Size = UDim2.new(0, 190, 0, 346)
            frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
            frame.BackgroundTransparency = 0.06
            frame.BorderSizePixel = 0
            frame.Parent = gui

            local frameCorner = Instance.new("UICorner")
            frameCorner.CornerRadius = UDim.new(0, 8)
            frameCorner.Parent = frame

            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -12, 0, 28)
            title.Position = UDim2.new(0, 6, 0, 4)
            title.BackgroundTransparency = 1
            title.TextColor3 = Color3.fromRGB(210, 245, 220)
            title.TextSize = 13
            title.Font = Enum.Font.GothamBold
            title.Text = "MM Weapon Tester"
            title.Parent = frame

            makeStateButton(frame, "target", 36, Tester.CycleTarget)
            makeStateButton(frame, "part", 70, Tester.CyclePart)
            makeStateButton(frame, "prediction", 104, Tester.CyclePrediction)
            makeStateButton(frame, "ping", 138, Tester.TogglePingPrediction)
            makeStateButton(frame, "cooldown", 172, Tester.CycleCooldown)

            makeButton(frame, "Shoot Target", 214, Tester.ShootTarget)
            makeButton(frame, "Throw Knife", 248, Tester.ThrowKnife)
            makeButton(frame, "Stab Target", 282, Tester.StabTarget)
            makeButton(frame, "Touch Target", 316, Tester.TouchTarget)

            gui.Parent = playerGui
            refreshUi()
            testerLog("Tester ready - buttons loaded")
        end)
    end

    createUi()
end

protected("install_tester", installTester)
