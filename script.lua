--!strict
-- 99 Nights in the Forest
-- Structural client framework for controlled/private testing.
-- No game object paths, RemoteEvent names, RemoteFunction names, or server APIs are invented here.
-- No anti-detection, moderation-evasion, HWID spoofing, admin avoidance, or remote bypass logic is included.

-- =========================================================
-- PART 1: SERVICES AND BOOTSTRAP
-- =========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local Framework = {
    Name = "ForestCore",
    Version = 1,
    Destroyed = false,
}


local function now()
    return os.clock()
end

local function shallowCopy(source)
    local out = {}
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local out = {}
    seen[value] = out

    for key, child in pairs(value) do
        out[deepCopy(key, seen)] = deepCopy(child, seen)
    end

    return out
end

local function splitPath(path)
    local parts = {}
    for part in string.gmatch(path, "[^%.]+") do
        table.insert(parts, part)
    end
    return parts
end

local function safeCall(fn, ...)
    local args = table.pack(...)
    return pcall(function()
        return fn(table.unpack(args, 1, args.n))
    end)
end

local function makeResult(ok, code, message, retryAfter)
    return {
        Ok = ok,
        Code = code,
        Message = message,
        RetryAfter = retryAfter,
    }
end

-- =========================================================
-- PART 2: CAPABILITY DETECTION
-- =========================================================

local Capabilities = {
    SharedEnvironment = type(getgenv) == "function",

    Files = {
        Read = type(readfile) == "function",
        Write = type(writefile) == "function",
        CheckFile = type(isfile) == "function",
        CheckFolder = type(isfolder) == "function",
        CreateFolder = type(makefolder) == "function",
        DeleteFile = type(delfile) == "function",
        ListFiles = type(listfiles) == "function",
    },

    Clipboard = type(setclipboard) == "function",
    QueueOnTeleport = type(queue_on_teleport) == "function",
}

Framework.Capabilities = Capabilities


-- =========================================================
-- PART 3: STATE STORE
-- =========================================================

local StateStore = {}
StateStore.__index = StateStore

function StateStore.new(defaults)
    local self = setmetatable({}, StateStore)
    self._defaults = deepCopy(defaults or {})
    self._state = deepCopy(defaults or {})
    self._listeners = {}
    return self
end

function StateStore:Get(path, defaultValue)
    if not path or path == "" then
        return self._state
    end

    local cursor = self._state
    for _, part in ipairs(splitPath(path)) do
        if type(cursor) ~= "table" or cursor[part] == nil then
            return defaultValue
        end
        cursor = cursor[part]
    end

    return cursor
end

function StateStore:Set(path, value)
    assert(type(path) == "string" and path ~= "", "StateStore:Set requires a non-empty path")

    local parts = splitPath(path)
    local cursor = self._state

    for index = 1, #parts - 1 do
        local part = parts[index]
        if type(cursor[part]) ~= "table" then
            cursor[part] = {}
        end
        cursor = cursor[part]
    end

    local leaf = parts[#parts]
    local oldValue = cursor[leaf]
    cursor[leaf] = value

    local listeners = self._listeners[path]
    if listeners then
        for _, callback in ipairs(listeners) do
            task.spawn(callback, value, oldValue)
        end
    end
end

function StateStore:Subscribe(path, callback)
    assert(type(callback) == "function", "StateStore:Subscribe requires a callback")

    self._listeners[path] = self._listeners[path] or {}
    table.insert(self._listeners[path], callback)

    local disconnected = false

    return function()
        if disconnected then
            return
        end
        disconnected = true

        local listeners = self._listeners[path]
        if not listeners then
            return
        end

        local index = table.find(listeners, callback)
        if index then
            table.remove(listeners, index)
        end
    end
end

function StateStore:Reset(path)
    if not path or path == "" then
        self._state = deepCopy(self._defaults)
        return
    end

    local defaultValue = self:GetDefault(path)
    self:Set(path, deepCopy(defaultValue))
end

function StateStore:GetDefault(path)
    if not path or path == "" then
        return self._defaults
    end

    local cursor = self._defaults
    for _, part in ipairs(splitPath(path)) do
        if type(cursor) ~= "table" or cursor[part] == nil then
            return nil
        end
        cursor = cursor[part]
    end

    return cursor
end

function StateStore:ResetAll()
    self._state = deepCopy(self._defaults)
end

function StateStore:Export()
    return deepCopy(self._state)
end

function StateStore:Import(newState)
    assert(type(newState) == "table", "StateStore:Import requires a table")
    self._state = deepCopy(newState)
end

local Defaults = {
    Features = {},
    Values = {
        MainFarm = {
            FarmDistance = 150,
            MovementMethod = "Path",
            MovementSpeed = 24,
            DepositThreshold = 85,
            InventoryThreshold = 85,
        },
        Combat = {
            MaxTargetDistance = 80,
            AttackInterval = 0.45,
            TargetSwitchDelay = 0.35,
            HealthThreshold = 35,
        },
        Survival = {
            FoodThreshold = 35,
            DrinkThreshold = 35,
            HealthThreshold = 40,
            DangerRadius = 40,
        },
        Movement = {
            WalkSpeed = 16,
            JumpPower = 50,
            FlightSpeed = 45,
            VerticalFlightSpeed = 30,
            TravelSpeed = 32,
            TweenClearance = 12,
        },
        ESP = {
            MaxDistance = 600,
            UpdateRate = 0.1,
        },
        Runtime = {
            ScanInterval = 2.5,
            RateLimitEnabled = true,
            MaxActionsPerSecond = 4,
            ErrorNotifications = true,
        },
        Settings = {
            AutoLoad = false,
            RememberLastConfig = true,
            Notifications = true,
            NotificationDuration = 5,
            StreamerMode = false,
            HideDisplayName = false,
        },
    },
    UI = {
        Visible = true,
        LoadedTabs = {},
    },
    Runtime = {
        Status = "Initializing",
        CharacterBound = false,
        CurrentTask = nil,
        CurrentTargetId = nil,
    },
    Config = {
        ActiveProfile = "Default",
        LastProfile = "Default",
    },
}

local State = StateStore.new(Defaults)
Framework.State = State

-- =========================================================
-- PART 4: DIAGNOSTICS
-- =========================================================

local Diagnostics = {}
Diagnostics.__index = Diagnostics

function Diagnostics.new()
    local self = setmetatable({}, Diagnostics)
    self.ErrorCount = 0
    self.Errors = {}
    self.SchedulerSamples = {}
    self.Counters = {
        Features = 0,
        Threads = 0,
        Connections = 0,
        Instances = 0,
        SchedulerJobs = 0,
        RuntimeIndex = 0,
    }
    return self
end

function Diagnostics:RecordError(scope, err)
    self.ErrorCount += 1
    table.insert(self.Errors, {
        Time = now(),
        Scope = tostring(scope),
        Error = tostring(err),
    })

    if #self.Errors > 100 then
        table.remove(self.Errors, 1)
    end
end

function Diagnostics:RecordSchedulerSample(duration)
    table.insert(self.SchedulerSamples, duration)
    if #self.SchedulerSamples > 120 then
        table.remove(self.SchedulerSamples, 1)
    end
end

function Diagnostics:GetAverageSchedulerTick()
    if #self.SchedulerSamples == 0 then
        return 0
    end

    local total = 0
    for _, sample in ipairs(self.SchedulerSamples) do
        total += sample
    end

    return total / #self.SchedulerSamples
end

function Diagnostics:Reset()
    self.ErrorCount = 0
    table.clear(self.Errors)
    table.clear(self.SchedulerSamples)
end

function Diagnostics:Summary()
    return {
        ErrorCount = self.ErrorCount,
        AverageSchedulerTick = self:GetAverageSchedulerTick(),
        Counters = shallowCopy(self.Counters),
    }
end

local DiagnosticsManager = Diagnostics.new()
Framework.Diagnostics = DiagnosticsManager

-- =========================================================
-- PART 5: THREAD MANAGER
-- =========================================================

local ThreadManager = {}
ThreadManager.__index = ThreadManager

function ThreadManager.new(diagnostics)
    local self = setmetatable({}, ThreadManager)
    self._threads = {}
    self._diagnostics = diagnostics
    return self
end

function ThreadManager:Spawn(id, callback)
    assert(type(id) == "string", "ThreadManager:Spawn requires id")
    assert(type(callback) == "function", "ThreadManager:Spawn requires callback")

    self:Cancel(id)

    local token = {
        Cancelled = false,
        Generation = (self._threads[id] and self._threads[id].Generation or 0) + 1,
    }

    local record = {
        Token = token,
        Thread = nil,
        Generation = token.Generation,
    }

    local thread = task.spawn(function()
        local ok, err = pcall(callback, token)
        if not ok then
            self._diagnostics:RecordError("Thread:" .. id, err)
        end

        local current = self._threads[id]
        if current == record then
            self._threads[id] = nil
            self._diagnostics.Counters.Threads = math.max(0, self._diagnostics.Counters.Threads - 1)
        end
    end)

    record.Thread = thread
    self._threads[id] = record
    self._diagnostics.Counters.Threads += 1

    return token
end

function ThreadManager:IsActive(id)
    local record = self._threads[id]
    return record ~= nil and not record.Token.Cancelled
end

function ThreadManager:Cancel(id)
    local record = self._threads[id]
    if not record then
        return
    end

    record.Token.Cancelled = true

    if record.Thread and coroutine.status(record.Thread) ~= "dead" then
        pcall(task.cancel, record.Thread)
    end

    self._threads[id] = nil
    self._diagnostics.Counters.Threads = math.max(0, self._diagnostics.Counters.Threads - 1)
end

function ThreadManager:CancelAll()
    local ids = {}
    for id in pairs(self._threads) do
        table.insert(ids, id)
    end

    for _, id in ipairs(ids) do
        self:Cancel(id)
    end
end

function ThreadManager:Count()
    local count = 0
    for _ in pairs(self._threads) do
        count += 1
    end
    return count
end

local Threads = ThreadManager.new(DiagnosticsManager)
Framework.ThreadManager = Threads

-- =========================================================
-- PART 6: CONNECTION MANAGER
-- =========================================================

local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

function ConnectionManager.new(diagnostics)
    local self = setmetatable({}, ConnectionManager)
    self._groups = {}
    self._diagnostics = diagnostics
    return self
end

function ConnectionManager:Add(group, connection)
    assert(connection ~= nil, "ConnectionManager:Add requires connection")

    self._groups[group] = self._groups[group] or {}
    table.insert(self._groups[group], connection)
    self._diagnostics.Counters.Connections += 1

    return connection
end

function ConnectionManager:DisconnectGroup(group)
    local list = self._groups[group]
    if not list then
        return
    end

    for _, connection in ipairs(list) do
        pcall(function()
            connection:Disconnect()
        end)
        self._diagnostics.Counters.Connections = math.max(0, self._diagnostics.Counters.Connections - 1)
    end

    self._groups[group] = nil
end

function ConnectionManager:DisconnectAll()
    local groups = {}
    for group in pairs(self._groups) do
        table.insert(groups, group)
    end

    for _, group in ipairs(groups) do
        self:DisconnectGroup(group)
    end
end

function ConnectionManager:Count()
    local count = 0
    for _, list in pairs(self._groups) do
        count += #list
    end
    return count
end

local Connections = ConnectionManager.new(DiagnosticsManager)
Framework.ConnectionManager = Connections

-- =========================================================
-- PART 7: INSTANCE MANAGER
-- =========================================================

local InstanceManager = {}
InstanceManager.__index = InstanceManager

function InstanceManager.new(diagnostics)
    local self = setmetatable({}, InstanceManager)
    self._groups = {}
    self._diagnostics = diagnostics
    return self
end

function InstanceManager:Add(group, instance)
    assert(typeof(instance) == "Instance", "InstanceManager:Add requires Instance")

    self._groups[group] = self._groups[group] or {}
    table.insert(self._groups[group], instance)
    self._diagnostics.Counters.Instances += 1

    return instance
end

function InstanceManager:DestroyGroup(group)
    local list = self._groups[group]
    if not list then
        return
    end

    for _, instance in ipairs(list) do
        if instance and instance.Parent then
            pcall(function()
                instance:Destroy()
            end)
        end
        self._diagnostics.Counters.Instances = math.max(0, self._diagnostics.Counters.Instances - 1)
    end

    self._groups[group] = nil
end

function InstanceManager:DestroyAll()
    local groups = {}
    for group in pairs(self._groups) do
        table.insert(groups, group)
    end

    for _, group in ipairs(groups) do
        self:DestroyGroup(group)
    end
end

function InstanceManager:Count()
    local count = 0
    for _, list in pairs(self._groups) do
        count += #list
    end
    return count
end

local Instances = InstanceManager.new(DiagnosticsManager)
Framework.InstanceManager = Instances

-- =========================================================
-- PART 8: CONFIG BACKENDS
-- =========================================================

local MemoryBackend = {}
MemoryBackend.__index = MemoryBackend

function MemoryBackend.new()
    local self = setmetatable({}, MemoryBackend)
    self._profiles = {}
    return self
end

function MemoryBackend:Save(name, payload)
    self._profiles[name] = payload
    return true
end

function MemoryBackend:Load(name)
    return self._profiles[name]
end

function MemoryBackend:Delete(name)
    self._profiles[name] = nil
    return true
end

function MemoryBackend:List()
    local names = {}
    for name in pairs(self._profiles) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

local FileBackend = {}
FileBackend.__index = FileBackend

function FileBackend.new(folder)
    local self = setmetatable({}, FileBackend)
    self._folder = folder
    self._extension = ".json"
    return self
end

function FileBackend:_path(name)
    return self._folder .. "/" .. name .. self._extension
end

function FileBackend:_ensureFolder()
    if not Capabilities.Files.CheckFolder or not Capabilities.Files.CreateFolder then
        return false, "folder capability unavailable"
    end

    local ok, exists = pcall(isfolder, self._folder)
    if not ok then
        return false, exists
    end

    if not exists then
        local created, createErr = pcall(makefolder, self._folder)
        if not created then
            return false, createErr
        end
    end

    return true
end

function FileBackend:Save(name, payload)
    local folderOk, folderErr = self:_ensureFolder()
    if not folderOk then
        error(folderErr)
    end

    writefile(self:_path(name), payload)
    return true
end

function FileBackend:Load(name)
    local path = self:_path(name)

    if Capabilities.Files.CheckFile then
        local exists = isfile(path)
        if not exists then
            return nil
        end
    end

    return readfile(path)
end

function FileBackend:Delete(name)
    if not Capabilities.Files.DeleteFile then
        return false
    end

    local path = self:_path(name)
    if Capabilities.Files.CheckFile and not isfile(path) then
        return true
    end

    delfile(path)
    return true
end

function FileBackend:List()
    if not Capabilities.Files.ListFiles then
        return {}
    end

    local files = listfiles(self._folder)
    local names = {}

    for _, path in ipairs(files) do
        local normalized = string.gsub(path, "\\", "/")
        local fileName = string.match(normalized, "([^/]+)%.json$")
        if fileName then
            table.insert(names, fileName)
        end
    end

    table.sort(names)
    return names
end

-- =========================================================
-- PART 9: CONFIG MANAGER WITH SILENT FALLBACK
-- =========================================================

local ConfigManager = {}
ConfigManager.__index = ConfigManager

function ConfigManager.new(stateStore, diagnostics)
    local self = setmetatable({}, ConfigManager)
    self._state = stateStore
    self._diagnostics = diagnostics
    self._memory = MemoryBackend.new()
    self._backend = self._memory
    self._backendName = "MemoryBackend"
    self._schemaVersion = 1

    if Capabilities.Files.Read and Capabilities.Files.Write then
        self._backend = FileBackend.new("ForestCore/Configs")
        self._backendName = "FileBackend"
    end

    return self
end

function ConfigManager:_fallbackToMemory()
    -- Required behavior: silent runtime fallback.
    -- No warning, notification, or repeated retry loop.
    self._backend = self._memory
    self._backendName = "MemoryBackend"
end

function ConfigManager:GetBackendName()
    return self._backendName
end

function ConfigManager:_encode(profileName)
    local payload = {
        Version = self._schemaVersion,
        ProfileName = profileName,
        Values = self._state:Export(),
        Keybinds = {},
        UI = deepCopy(self._state:Get("UI", {})),
    }

    return HttpService:JSONEncode(payload)
end

function ConfigManager:_decode(payload)
    local decoded = HttpService:JSONDecode(payload)
    if type(decoded) ~= "table" then
        error("invalid config root")
    end

    if decoded.Version ~= self._schemaVersion then
        error("unsupported config schema")
    end

    if type(decoded.Values) ~= "table" then
        error("config missing Values table")
    end

    return decoded
end

function ConfigManager:Save(profileName)
    profileName = tostring(profileName or "Default")

    local okEncode, payloadOrErr = pcall(function()
        return self:_encode(profileName)
    end)

    if not okEncode then
        self._diagnostics:RecordError("Config.Encode", payloadOrErr)
        return false
    end

    local payload = payloadOrErr
    local backend = self._backend

    local okSave = pcall(function()
        backend:Save(profileName, payload)
    end)

    if okSave then
        return true
    end

    if backend ~= self._memory then
        self:_fallbackToMemory()

        local memoryOk = pcall(function()
            self._memory:Save(profileName, payload)
        end)

        return memoryOk
    end

    return false
end

function ConfigManager:Load(profileName)
    profileName = tostring(profileName or "Default")

    local backend = self._backend
    local okLoad, payload = pcall(function()
        return backend:Load(profileName)
    end)

    if not okLoad then
        if backend ~= self._memory then
            self:_fallbackToMemory()
            payload = self._memory:Load(profileName)
        else
            return false
        end
    end

    if not payload then
        return false
    end

    local okDecode, decoded = pcall(function()
        return self:_decode(payload)
    end)

    if not okDecode then
        self._diagnostics:RecordError("Config.Decode", decoded)
        return false
    end

    self._state:Import(decoded.Values)
    self._state:Set("Config.ActiveProfile", profileName)
    self._state:Set("Config.LastProfile", profileName)

    return true
end

function ConfigManager:Delete(profileName)
    local backend = self._backend
    local okDelete = pcall(function()
        return backend:Delete(profileName)
    end)

    if okDelete then
        return true
    end

    if backend ~= self._memory then
        self:_fallbackToMemory()
        return self._memory:Delete(profileName)
    end

    return false
end

function ConfigManager:List()
    local backend = self._backend
    local okList, profiles = pcall(function()
        return backend:List()
    end)

    if okList then
        return profiles
    end

    if backend ~= self._memory then
        self:_fallbackToMemory()
        return self._memory:List()
    end

    return {}
end

local Configs = ConfigManager.new(State, DiagnosticsManager)
Framework.ConfigManager = Configs

-- =========================================================
-- PART 10: RATE LIMITER
-- =========================================================

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(stateStore)
    local self = setmetatable({}, RateLimiter)
    self._state = stateStore
    self._history = {}
    return self
end

function RateLimiter:_trim(key, windowSeconds)
    local list = self._history[key]
    if not list then
        return
    end

    local cutoff = now() - windowSeconds
    local firstValid = 1

    while firstValid <= #list and list[firstValid] < cutoff do
        firstValid += 1
    end

    if firstValid > 1 then
        for _ = 1, firstValid - 1 do
            table.remove(list, 1)
        end
    end
end

function RateLimiter:CanRun(key, limit, windowSeconds)
    if not self._state:Get("Values.Runtime.RateLimitEnabled", true) then
        return true
    end

    limit = limit or self._state:Get("Values.Runtime.MaxActionsPerSecond", 4)
    windowSeconds = windowSeconds or 1

    self._history[key] = self._history[key] or {}
    self:_trim(key, windowSeconds)

    return #self._history[key] < limit
end

function RateLimiter:Commit(key)
    self._history[key] = self._history[key] or {}
    table.insert(self._history[key], now())
end

function RateLimiter:Reset(key)
    if key then
        self._history[key] = nil
    else
        table.clear(self._history)
    end
end

local Limiter = RateLimiter.new(State)
Framework.RateLimiter = Limiter

-- =========================================================
-- BLOCK A: ACTION QUEUE WITH TELEMETRY + LOAD RECOVERY
-- Replace PART 11: ACTION QUEUE
-- =========================================================

local ActionQueue = {}
ActionQueue.__index = ActionQueue

function ActionQueue.new(threadManager, rateLimiter, diagnostics)
    local self = setmetatable({}, ActionQueue)
    self._threads = threadManager
    self._limiter = rateLimiter
    self._diagnostics = diagnostics
    self._pauseGate = nil
    self._queues = {}
    self._running = {}
    self._telemetry = {}
    return self
end

function ActionQueue:SetPauseGate(pauseGate)
    self._pauseGate = pauseGate
end

function ActionQueue:_waitUntilResumed(token, pollInterval)
    if not self._pauseGate then
        return not token.Cancelled
    end

    return self._pauseGate:WaitUntilResumed(token, pollInterval or 0.05)
end

function ActionQueue:_getTelemetry(queueName)
    local record = self._telemetry[queueName]
    if record then
        return record
    end

    record = {
        Executed = 0,
        Succeeded = 0,
        Failed = 0,
        TransientFailures = 0,
        Retried = 0,
        LastStartedAt = 0,
        LastCompletedAt = 0,
        LastDuration = 0,
        AverageDuration = 0,
        ConsecutiveFailures = 0,
        QueueHighWatermark = 0,
    }

    self._telemetry[queueName] = record
    return record
end

function ActionQueue:GetTelemetry(queueName)
    if queueName then
        local source = self:_getTelemetry(queueName)
        return shallowCopy(source)
    end

    local out = {}
    for name, record in pairs(self._telemetry) do
        out[name] = shallowCopy(record)
    end
    return out
end

function ActionQueue:_updateDurationTelemetry(record, duration)
    record.LastDuration = duration

    if record.Executed <= 1 then
        record.AverageDuration = duration
    else
        local alpha = 0.2
        record.AverageDuration = record.AverageDuration + alpha * (duration - record.AverageDuration)
    end
end

function ActionQueue:_calculateSpacing(action, telemetry, queueDepth)
    local spacing = math.max(action.MinSpacing or 0, 0)

    if action.Limit and action.Window and action.Limit > 0 then
        spacing = math.max(spacing, action.Window / action.Limit)
    end

    -- Congestion penalty is deterministic and based on measured local load.
    local queuePenalty = math.min(queueDepth * 0.01, 0.2)
    local durationPenalty = math.min(telemetry.AverageDuration * 0.25, 0.25)

    return spacing + queuePenalty + durationPenalty
end

function ActionQueue:_waitForSpacing(token, telemetry, spacing)
    if spacing <= 0 then
        return not token.Cancelled
    end

    local deadline = telemetry.LastStartedAt + spacing

    while not token.Cancelled and now() < deadline do
        if not self:_waitUntilResumed(token, 0.05) then
            return false
        end

        task.wait(math.min(0.05, math.max(deadline - now(), 0.01)))
    end

    return not token.Cancelled
end

function ActionQueue:Enqueue(queueName, actionId, callback, options)
    assert(type(queueName) == "string" and queueName ~= "", "queueName required")
    assert(type(actionId) == "string" and actionId ~= "", "actionId required")
    assert(type(callback) == "function", "callback required")

    options = options or {}
    self._queues[queueName] = self._queues[queueName] or {}

    local queue = self._queues[queueName]
    table.insert(queue, {
        Id = actionId,
        Callback = callback,
        Limit = options.Limit,
        Window = options.Window,
        MinSpacing = options.MinSpacing or 0,
        MaxRetries = options.MaxRetries or 2,
        RetryCount = 0,
        BaseBackoff = options.BaseBackoff or 0.25,
        Timeout = options.Timeout,
        Metadata = options.Metadata,
    })

    local telemetry = self:_getTelemetry(queueName)
    telemetry.QueueHighWatermark = math.max(telemetry.QueueHighWatermark, #queue)

    self:_ensureWorker(queueName)
end

function ActionQueue:_executeAction(queueName, action, telemetry)
    telemetry.Executed += 1
    telemetry.LastStartedAt = now()
    local startedAt = telemetry.LastStartedAt

    self._limiter:Commit(queueName)

    local ok, result = pcall(action.Callback)
    local duration = now() - startedAt

    telemetry.LastCompletedAt = now()
    self:_updateDurationTelemetry(telemetry, duration)

    if not ok then
        telemetry.Failed += 1
        telemetry.ConsecutiveFailures += 1
        self._diagnostics:RecordError("ActionQueue:" .. queueName, result)
        return makeResult(false, "INTERNAL_ERROR", tostring(result))
    end

    if type(result) ~= "table" then
        result = makeResult(true, "OK")
    end

    if result.Ok then
        telemetry.Succeeded += 1
        telemetry.ConsecutiveFailures = 0
    else
        telemetry.Failed += 1
        telemetry.ConsecutiveFailures += 1
    end

    return result
end

function ActionQueue:_calculateRetryDelay(action, result)
    if type(result.RetryAfter) == "number" and result.RetryAfter > 0 then
        return result.RetryAfter
    end

    local exponential = action.BaseBackoff * (2 ^ math.max(action.RetryCount - 1, 0))

    -- Small bounded de-synchronization only for retry storms/load recovery.
    local retryDesync = math.random() * math.min(0.12, exponential * 0.2)
    return exponential + retryDesync
end

function ActionQueue:_ensureWorker(queueName)
    if self._running[queueName] then
        return
    end

    self._running[queueName] = true

    self._threads:Spawn("ActionQueue:" .. queueName, function(token)
        local telemetry = self:_getTelemetry(queueName)

        while not token.Cancelled do
            if not self:_waitUntilResumed(token, 0.05) then
                break
            end

            local queue = self._queues[queueName]
            if not queue or #queue == 0 then
                break
            end

            local action = table.remove(queue, 1)
            local spacing = self:_calculateSpacing(action, telemetry, #queue)

            if not self:_waitForSpacing(token, telemetry, spacing) then
                break
            end

            while not token.Cancelled and not self._limiter:CanRun(
                queueName,
                action.Limit,
                action.Window
            ) do
                if not self:_waitUntilResumed(token, 0.05) then
                    break
                end
                task.wait(0.05)
            end

            if token.Cancelled then
                break
            end

            local result = self:_executeAction(queueName, action, telemetry)
            local transient = result.Code == "RATE_LIMITED"
                or result.Code == "TEMPORARY_UNAVAILABLE"
                or result.Code == "TIMEOUT"

            if transient then
                telemetry.TransientFailures += 1
            end

            if transient and action.RetryCount < action.MaxRetries and not token.Cancelled then
                action.RetryCount += 1
                telemetry.Retried += 1

                local delaySeconds = self:_calculateRetryDelay(action, result)
                local deadline = now() + delaySeconds

                while not token.Cancelled and now() < deadline do
                    if not self:_waitUntilResumed(token, 0.05) then
                        break
                    end
                    task.wait(math.min(0.05, math.max(deadline - now(), 0.01)))
                end

                if not token.Cancelled then
                    table.insert(queue, action)
                end
            end

            task.wait()
        end

        self._running[queueName] = nil
    end)
end

function ActionQueue:Clear(queueName)
    if queueName then
        self._queues[queueName] = {}
        self._threads:Cancel("ActionQueue:" .. queueName)
        self._running[queueName] = nil
        return
    end

    local names = {}
    for name in pairs(self._queues) do
        table.insert(names, name)
    end

    for _, name in ipairs(names) do
        self:Clear(name)
    end
end

function ActionQueue:ResetTelemetry(queueName)
    if queueName then
        self._telemetry[queueName] = nil
    else
        table.clear(self._telemetry)
    end
end

local Actions = ActionQueue.new(Threads, Limiter, DiagnosticsManager)
Framework.ActionQueue = Actions


-- =========================================================
-- PART 12: SCHEDULER
-- =========================================================

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(threadManager, diagnostics)
    local self = setmetatable({}, Scheduler)
    self._threads = threadManager
    self._diagnostics = diagnostics
    self._jobs = {}
    self._running = false
    self._generation = 0
    return self
end

function Scheduler:RegisterJob(id, interval, callback, enabled)
    assert(type(id) == "string", "Scheduler:RegisterJob requires id")
    assert(type(interval) == "number" and interval > 0, "Scheduler interval must be > 0")
    assert(type(callback) == "function", "Scheduler callback required")

    self._jobs[id] = {
        Id = id,
        Interval = interval,
        Callback = callback,
        Enabled = enabled ~= false,
        Running = false,
        LastRun = 0,
        NextRun = now() + interval,
        ErrorCount = 0,
        Generation = 0,
    }

    self._diagnostics.Counters.SchedulerJobs = self:Count()
end

function Scheduler:SetEnabled(id, enabled)
    local job = self._jobs[id]
    if not job then
        return false
    end

    job.Enabled = enabled
    job.Generation += 1
    job.NextRun = now() + job.Interval
    return true
end

function Scheduler:SetInterval(id, interval)
    local job = self._jobs[id]
    if not job then
        return false
    end

    job.Interval = math.max(interval, 0.01)
    job.NextRun = now() + job.Interval
    return true
end

function Scheduler:RemoveJob(id)
    self._jobs[id] = nil
    self._diagnostics.Counters.SchedulerJobs = self:Count()
end

function Scheduler:Count()
    local count = 0
    for _ in pairs(self._jobs) do
        count += 1
    end
    return count
end

function Scheduler:Start()
    if self._running then
        return
    end

    self._running = true
    self._generation += 1
    local generation = self._generation

    self._threads:Spawn("Scheduler.Main", function(token)
        while not token.Cancelled and self._running and generation == self._generation do
            local tickStart = now()
            local current = tickStart

            for id, job in pairs(self._jobs) do
                if token.Cancelled then
                    break
                end

                if job.Enabled and not job.Running and current >= job.NextRun then
                    job.Running = true
                    job.LastRun = current
                    job.NextRun = current + job.Interval
                    local jobGeneration = job.Generation

                    task.spawn(function()
                        local ok, err = pcall(job.Callback, {
                            Id = id,
                            Generation = jobGeneration,
                            IsCurrent = function()
                                local currentJob = self._jobs[id]
                                return currentJob ~= nil
                                    and currentJob.Enabled
                                    and currentJob.Generation == jobGeneration
                                    and not token.Cancelled
                            end,
                        })

                        local currentJob = self._jobs[id]
                        if currentJob then
                            currentJob.Running = false
                        end

                        if not ok then
                            if currentJob then
                                currentJob.ErrorCount += 1
                            end
                            self._diagnostics:RecordError("Scheduler:" .. id, err)
                        end
                    end)
                end
            end

            self._diagnostics:RecordSchedulerSample(now() - tickStart)
            task.wait(0.03)
        end
    end)
end

function Scheduler:Stop()
    self._running = false
    self._generation += 1
    self._threads:Cancel("Scheduler.Main")
end

function Scheduler:StopAllJobs()
    for _, job in pairs(self._jobs) do
        job.Enabled = false
        job.Generation += 1
        job.Running = false
    end
end

local Jobs = Scheduler.new(Threads, DiagnosticsManager)
Framework.Scheduler = Jobs

-- =========================================================
-- BLOCK B: AUTOMATION PAUSE GATE + OPERATIONAL PACING
-- =========================================================

local AutomationPauseGate = {}
AutomationPauseGate.__index = AutomationPauseGate

function AutomationPauseGate.new(stateStore, diagnostics)
    local self = setmetatable({}, AutomationPauseGate)
    self._state = stateStore
    self._diagnostics = diagnostics
    self._reasons = {}
    self._listeners = {}
    self._generation = 0
    self._state:Set("Runtime.AutomationPaused", false)
    self._state:Set("Runtime.AutomationPauseReasons", {})
    return self
end

function AutomationPauseGate:_publish()
    local reasons = {}
    for reason in pairs(self._reasons) do
        table.insert(reasons, reason)
    end
    table.sort(reasons)

    local paused = #reasons > 0
    self._state:Set("Runtime.AutomationPaused", paused)
    self._state:Set("Runtime.AutomationPauseReasons", reasons)
    self._generation += 1

    for _, callback in ipairs(self._listeners) do
        task.spawn(function()
            local ok, err = pcall(callback, paused, reasons, self._generation)
            if not ok then
                self._diagnostics:RecordError("AutomationPauseGate.Listener", err)
            end
        end)
    end
end

function AutomationPauseGate:Pause(reason, metadata)
    assert(type(reason) == "string" and reason ~= "", "Pause reason required")

    self._reasons[reason] = {
        Since = now(),
        Metadata = metadata,
    }

    self:_publish()
end

function AutomationPauseGate:Resume(reason)
    if self._reasons[reason] == nil then
        return false
    end

    self._reasons[reason] = nil
    self:_publish()
    return true
end

function AutomationPauseGate:ResumeAll()
    table.clear(self._reasons)
    self:_publish()
end

function AutomationPauseGate:IsPaused()
    return next(self._reasons) ~= nil
end

function AutomationPauseGate:GetGeneration()
    return self._generation
end

function AutomationPauseGate:GetSnapshot()
    local reasons = {}

    for reason, record in pairs(self._reasons) do
        reasons[reason] = {
            Since = record.Since,
            Metadata = record.Metadata,
        }
    end

    return {
        Paused = self:IsPaused(),
        Generation = self._generation,
        Reasons = reasons,
    }
end

function AutomationPauseGate:Subscribe(callback)
    assert(type(callback) == "function", "PauseGate subscriber must be a function")
    table.insert(self._listeners, callback)

    local disconnected = false
    return function()
        if disconnected then
            return
        end
        disconnected = true

        local index = table.find(self._listeners, callback)
        if index then
            table.remove(self._listeners, index)
        end
    end
end

function AutomationPauseGate:WaitUntilResumed(token, pollInterval)
    pollInterval = pollInterval or 0.05

    while self:IsPaused() do
        if token and token.Cancelled then
            return false
        end
        task.wait(pollInterval)
    end

    return true
end

local PauseGate = AutomationPauseGate.new(State, DiagnosticsManager)
Framework.AutomationPauseGate = PauseGate

-- OperationalPacing is a stability guard, not a human-behavior simulator.
-- It pauses work only when measurable local health signals indicate overload.
local OperationalPacing = {}
OperationalPacing.__index = OperationalPacing

function OperationalPacing.new(pauseGate, diagnostics)
    local self = setmetatable({}, OperationalPacing)
    self._pauseGate = pauseGate
    self._diagnostics = diagnostics
    self._recoverySince = {}
    self._thresholds = {
        RecentErrorWindow = 10,
        RecentErrorLimit = 8,
        SchedulerTickLimit = 0.08,
        RecoveryHold = 4,
    }
    return self
end

function OperationalPacing:_countRecentErrors(windowSeconds)
    local cutoff = now() - windowSeconds
    local count = 0

    for index = #self._diagnostics.Errors, 1, -1 do
        local entry = self._diagnostics.Errors[index]
        if entry.Time < cutoff then
            break
        end
        count += 1
    end

    return count
end

function OperationalPacing:_setCondition(reason, active, metadata)
    if active then
        self._recoverySince[reason] = nil
        self._pauseGate:Pause(reason, metadata)
        return
    end

    if not self._pauseGate:GetSnapshot().Reasons[reason] then
        self._recoverySince[reason] = nil
        return
    end

    local started = self._recoverySince[reason]
    if not started then
        self._recoverySince[reason] = now()
        return
    end

    if now() - started >= self._thresholds.RecoveryHold then
        self._pauseGate:Resume(reason)
        self._recoverySince[reason] = nil
    end
end

function OperationalPacing:Evaluate()
    local recentErrors = self:_countRecentErrors(self._thresholds.RecentErrorWindow)
    local averageTick = self._diagnostics:GetAverageSchedulerTick()

    self:_setCondition(
        "ErrorBurst",
        recentErrors >= self._thresholds.RecentErrorLimit,
        { RecentErrors = recentErrors }
    )

    self:_setCondition(
        "SchedulerOverload",
        averageTick >= self._thresholds.SchedulerTickLimit,
        { AverageTick = averageTick }
    )
end

local Pacing = OperationalPacing.new(PauseGate, DiagnosticsManager)
Framework.OperationalPacing = Pacing

Actions:SetPauseGate(PauseGate)

Jobs:RegisterJob("OperationalPacing", 1.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Pacing:Evaluate()
end, true)

-- Central scheduler pause bridge. It preserves each job's previous enabled state.
local schedulerPauseSnapshot = {}

PauseGate:Subscribe(function(paused)
    if paused then
        table.clear(schedulerPauseSnapshot)

        for id, job in pairs(Jobs._jobs) do
            local exempt = id == "OperationalPacing" or id == "DiagnosticsUpdate"
            if not exempt then
                schedulerPauseSnapshot[id] = job.Enabled
                if job.Enabled then
                    Jobs:SetEnabled(id, false)
                end
            end
        end

        return
    end

    for id, wasEnabled in pairs(schedulerPauseSnapshot) do
        if wasEnabled and Jobs._jobs[id] then
            Jobs:SetEnabled(id, true)
        end
    end

    table.clear(schedulerPauseSnapshot)
end)



-- =========================================================
-- PART 13: LOCK MANAGER
-- =========================================================

local LockManager = {}
LockManager.__index = LockManager

function LockManager.new()
    local self = setmetatable({}, LockManager)
    self._locks = {}
    return self
end

function LockManager:Acquire(lockName, ownerId)
    local owner = self._locks[lockName]
    if owner and owner ~= ownerId then
        return false
    end

    self._locks[lockName] = ownerId
    return true
end

function LockManager:Release(lockName, ownerId)
    if self._locks[lockName] == ownerId then
        self._locks[lockName] = nil
        return true
    end
    return false
end

function LockManager:ForceRelease(lockName)
    self._locks[lockName] = nil
end

function LockManager:ReleaseAllByOwner(ownerId)
    for lockName, owner in pairs(self._locks) do
        if owner == ownerId then
            self._locks[lockName] = nil
        end
    end
end

function LockManager:Reset()
    table.clear(self._locks)
end

local Locks = LockManager.new()
Framework.LockManager = Locks

-- =========================================================
-- PART 14: RUNTIME INDEX
-- =========================================================

local RuntimeIndex = {}
RuntimeIndex.__index = RuntimeIndex

function RuntimeIndex.new(diagnostics)
    local self = setmetatable({}, RuntimeIndex)
    self._diagnostics = diagnostics

    self.Resources = {}
    self.Items = {}
    self.Loot = {}
    self.Hostiles = {}
    self.Players = {}
    self.Interactables = {}
    self.Objectives = {}

    self.Locations = {
        Camp = nil,
        Campfire = nil,
        Merchant = nil,
        Spawn = nil,
        SafePositions = {},
    }

    self.LastRefresh = {}
    return self
end

function RuntimeIndex:_bucket(name)
    local bucket = self[name]
    assert(type(bucket) == "table", "Unknown RuntimeIndex bucket: " .. tostring(name))
    return bucket
end

function RuntimeIndex:Replace(name, descriptors)
    local bucket = self:_bucket(name)
    table.clear(bucket)

    for _, descriptor in ipairs(descriptors or {}) do
        if descriptor.Id then
            bucket[descriptor.Id] = descriptor
        end
    end

    self.LastRefresh[name] = now()
    self:_updateCount()
end

function RuntimeIndex:Upsert(name, descriptor)
    assert(descriptor and descriptor.Id, "RuntimeIndex:Upsert requires descriptor.Id")
    self:_bucket(name)[descriptor.Id] = descriptor
    self:_updateCount()
end

function RuntimeIndex:Remove(name, id)
    self:_bucket(name)[id] = nil
    self:_updateCount()
end

function RuntimeIndex:GetAll(name)
    local out = {}
    for _, descriptor in pairs(self:_bucket(name)) do
        table.insert(out, descriptor)
    end
    return out
end

function RuntimeIndex:Prune(name, validator)
    local bucket = self:_bucket(name)

    for id, descriptor in pairs(bucket) do
        local ok, valid = pcall(validator, descriptor)
        if not ok or not valid then
            bucket[id] = nil
        end
    end

    self.LastRefresh[name] = now()
    self:_updateCount()
end

function RuntimeIndex:SetLocation(name, descriptor)
    assert(self.Locations[name] ~= nil or name == "Camp" or name == "Campfire"
        or name == "Merchant" or name == "Spawn",
        "Unknown RuntimeIndex location: " .. tostring(name))

    self.Locations[name] = descriptor
    self.LastRefresh["Location." .. name] = now()
end

function RuntimeIndex:ReplaceSafePositions(descriptors)
    table.clear(self.Locations.SafePositions)

    for _, descriptor in ipairs(descriptors or {}) do
        if descriptor.Id then
            self.Locations.SafePositions[descriptor.Id] = descriptor
        end
    end

    self.LastRefresh["Location.SafePositions"] = now()
end

function RuntimeIndex:GetLocation(name)
    return self.Locations[name]
end

function RuntimeIndex:GetSafePositions()
    local out = {}
    for _, descriptor in pairs(self.Locations.SafePositions) do
        table.insert(out, descriptor)
    end
    return out
end

function RuntimeIndex:Clear()
    table.clear(self.Resources)
    table.clear(self.Items)
    table.clear(self.Loot)
    table.clear(self.Hostiles)
    table.clear(self.Players)
    table.clear(self.Interactables)
    table.clear(self.Objectives)

    self.Locations.Camp = nil
    self.Locations.Campfire = nil
    self.Locations.Merchant = nil
    self.Locations.Spawn = nil
    table.clear(self.Locations.SafePositions)

    table.clear(self.LastRefresh)
    self:_updateCount()
end

function RuntimeIndex:_updateCount()
    local total = 0

    for _, name in ipairs({
        "Resources",
        "Items",
        "Loot",
        "Hostiles",
        "Players",
        "Interactables",
        "Objectives",
    }) do
        for _ in pairs(self[name]) do
            total += 1
        end
    end

    self._diagnostics.Counters.RuntimeIndex = total
end

function RuntimeIndex:GetCounts()
    local counts = {}

    for _, name in ipairs({
        "Resources",
        "Items",
        "Loot",
        "Hostiles",
        "Players",
        "Interactables",
        "Objectives",
    }) do
        local count = 0
        for _ in pairs(self[name]) do
            count += 1
        end
        counts[name] = count
    end

    local safeCount = 0
    for _ in pairs(self.Locations.SafePositions) do
        safeCount += 1
    end

    counts.SafePositions = safeCount
    return counts
end

local Index = RuntimeIndex.new(DiagnosticsManager)
Framework.RuntimeIndex = Index

-- =========================================================
-- PART 15: TARGET RESOLVER
-- =========================================================

local TargetResolver = {}
TargetResolver.__index = TargetResolver

function TargetResolver.new(runtimeIndex)
    local self = setmetatable({}, TargetResolver)
    self._index = runtimeIndex
    self._current = nil
    return self
end

local function getDescriptorPosition(descriptor)
    if descriptor.Position and typeof(descriptor.Position) == "Vector3" then
        return descriptor.Position
    end

    if descriptor.Root and descriptor.Root:IsA("BasePart") then
        return descriptor.Root.Position
    end

    return nil
end

function TargetResolver:Select(bucketName, origin, options)
    options = options or {}

    local candidates = {}
    local maxDistance = options.MaxDistance or math.huge
    local category = options.Category

    for _, descriptor in pairs(self._index[bucketName] or {}) do
        local position = getDescriptorPosition(descriptor)
        local valid = descriptor.IsValid ~= false and position ~= nil

        if valid and category and descriptor.Category ~= category then
            valid = false
        end

        if valid then
            local distance = (position - origin).Magnitude
            if distance <= maxDistance then
                table.insert(candidates, {
                    Descriptor = descriptor,
                    Distance = distance,
                })
            end
        end
    end

    local priority = options.Priority or "Nearest"

    table.sort(candidates, function(a, b)
        if priority == "Lowest Health" then
            local aHealth = (a.Descriptor.Metadata and a.Descriptor.Metadata.Health) or math.huge
            local bHealth = (b.Descriptor.Metadata and b.Descriptor.Metadata.Health) or math.huge
            return aHealth < bHealth
        elseif priority == "Highest Threat" then
            local aThreat = (a.Descriptor.Metadata and a.Descriptor.Metadata.Threat) or 0
            local bThreat = (b.Descriptor.Metadata and b.Descriptor.Metadata.Threat) or 0
            return aThreat > bThreat
        end

        return a.Distance < b.Distance
    end)

    if #candidates == 0 then
        return nil
    end

    self._current = candidates[1].Descriptor
    return self._current
end

function TargetResolver:GetCurrent()
    return self._current
end

function TargetResolver:Clear()
    self._current = nil
end

local Targets = TargetResolver.new(Index)
Framework.TargetResolver = Targets

-- =========================================================
-- PART 16: STRUCTURALLY MAPPED GAME ADAPTER
-- =========================================================

local GameAdapter = {}
GameAdapter.__index = GameAdapter

local HOSTILE_NAME_SET = {
    ["Cultist"] = true,
    ["Crossbow Cultist"] = true,
    ["Wolf"] = true,
    ["Alpha Wolf"] = true,
    ["Bear"] = true,
    ["Alien Commander"] = true,
    ["Bat"] = true,
}

local CAMP_INTERACTABLE_NAMES = {
    ["Warp"] = true,
    ["NoticeBoard"] = true,
    ["CraftingBench"] = true,
    ["Scrapper"] = true,
    ["MainFire"] = true,
}

local LANDMARK_INTERACTABLE_NAMES = {
    ["ToolSmith"] = true,
    ["Bank"] = true,
    ["Well"] = true,
    ["Firewood Stack"] = true,
    ["Hunters Lodge"] = true,
    ["Flashlight Tower"] = true,
    ["Treehouse"] = true,
}

local REMOTE_ROUTE_NAMES = {
    "RequestDestroyFoliage",
    "ToolDamageObject",
    "ProjectileDamageEnemy",
    "ExplosiveProjectileDamageEnemy",
    "RequestConsumeItem",
    "RequestOpenItemChest",
    "RequestHotbarItem",
    "ItemSelected",
    "RequestStartDraggingItem",
    "StopDraggingItem",
    "RequestBagStoreItem",
    "RequestBagDropItem",
    "RequestDropItem",
    "RequestThrowItem",
    "RequestBurnItem",
    "RequestTeleport",
    "RequestCookItem",
}

local ACTION_ROUTE_NAMES = {
    HarvestResource = {
        "RequestDestroyFoliage",
    },

    PickupItem = {
        "RequestStartDraggingItem",
        "StopDraggingItem",
        "RequestBagStoreItem",
    },

    OpenLootContainer = {
        "RequestOpenItemChest",
    },

    EquipTool = {
        "RequestHotbarItem",
        "ItemSelected",
    },

    Attack = {
        "ToolDamageObject",
        "ProjectileDamageEnemy",
        "ExplosiveProjectileDamageEnemy",
    },

    ConsumeItem = {
        "RequestConsumeItem",
    },

    PerformWarmthAction = {
        "RequestBurnItem",
    },

    Rest = {},

    CureStatus = {
        "RequestConsumeItem",
    },

    MaintainCampfire = {
        "RequestBurnItem",
    },

    Interact = {},
}

local function directChildren(container)
    if not container then
        return {}
    end
    return container:GetChildren()
end

local function findDirect(parent, name)
    if not parent then
        return nil
    end
    return parent:FindFirstChild(name)
end

local function findRootPart(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance
    end

    if instance:IsA("Model") then
        if instance.PrimaryPart then
            return instance.PrimaryPart
        end

        local preferred = {
            "HumanoidRootPart",
            "Main",
            "Handle",
            "RootPart",
            "ItemDrop",
        }

        for _, childName in ipairs(preferred) do
            local child = instance:FindFirstChild(childName, true)
            if child and child:IsA("BasePart") then
                return child
            end
        end
    end

    return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getPosition(instance, rootPart)
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart.Position
    end

    if instance and instance:IsA("Model") then
        local ok, pivot = pcall(function()
            return instance:GetPivot()
        end)

        if ok then
            return pivot.Position
        end
    end

    return nil
end

local function isAliveInstance(instance)
    return instance ~= nil and instance.Parent ~= nil
end

local function isChestName(name)
    local lower = string.lower(name)
    return string.find(lower, "chest", 1, true) ~= nil
        or string.find(lower, "crate", 1, true) ~= nil
end

local function classifyResourceName(name)
    local lower = string.lower(name)

    if string.find(lower, "tree", 1, true) then
        return "Wood"
    end

    if string.find(lower, "stone", 1, true)
        or string.find(lower, "basalt pile", 1, true)
    then
        return "Stone"
    end

    return nil
end

local function getNpcHumanoid(model)
    if not model or not model:IsA("Model") then
        return nil
    end

    local named = model:FindFirstChild("NPC")
    if named and named:IsA("Humanoid") then
        return named
    end

    return model:FindFirstChildOfClass("Humanoid")
end

function GameAdapter.new(runtimeIndex)
    local self = setmetatable({}, GameAdapter)

    self.Initialized = false
    self.Index = runtimeIndex

    self.Paths = {}
    self.Remotes = {}
    self.ActionRoutes = {}

    self._instanceIds = setmetatable({}, {
        __mode = "k",
    })

    return self
end

function GameAdapter:_idFor(instance)
    local existing = self._instanceIds[instance]
    if existing then
        return existing
    end

    local generated = HttpService:GenerateGUID(false)
    self._instanceIds[instance] = generated
    return generated
end

function GameAdapter:_descriptor(instance, category, metadata, displayName)
    if not instance then
        return nil
    end

    local root = findRootPart(instance)
    local position = getPosition(instance, root)

    return {
        Id = self:_idFor(instance),
        Category = category,
        DisplayName = displayName or instance.Name,
        Instance = instance,
        Root = root,
        Position = position,
        IsValid = isAliveInstance(instance),
        Metadata = metadata or {},
    }
end

function GameAdapter:_required(methodName)
    return makeResult(
        false,
        "ADAPTER_REQUIRED",
        methodName .. " requires a verified argument contract, not only a hierarchy path."
    )
end

function GameAdapter:_refreshPaths()
    local map = workspace:FindFirstChild("Map")
    local campground = findDirect(map, "Campground")
    local landmarks = findDirect(map, "Landmarks")

    self.Paths = {
        Workspace = workspace,

        Characters = workspace:FindFirstChild("Characters"),
        Items = workspace:FindFirstChild("Items"),

        Map = map,
        Foliage = findDirect(map, "Foliage"),
        Campground = campground,
        MainFire = findDirect(campground, "MainFire"),
        MissingKids = findDirect(map, "MissingKids"),
        Landmarks = landmarks,
        SpawnLocation = findDirect(map, "SpawnLocation"),
        ToolSmith = findDirect(landmarks, "ToolSmith"),

        RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents"),
        Databases = ReplicatedStorage:FindFirstChild("Databases"),
        ToolsDatabase = ReplicatedStorage:FindFirstChild("Tools"),

        PlayerInventory = LocalPlayer and LocalPlayer:FindFirstChild("Inventory") or nil,
        PlayerItemBag = LocalPlayer and LocalPlayer:FindFirstChild("ItemBag") or nil,
        PlayerArmour = LocalPlayer and LocalPlayer:FindFirstChild("Armour") or nil,
        PlayerBackpack = LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack") or nil,
    }

    local databases = self.Paths.Databases
    self.Paths.CampfireSettings = findDirect(databases, "CampfireSettings")
    self.Paths.FoodIcons = findDirect(databases, "FoodIcons")
end

function GameAdapter:_refreshRemoteRegistry()
    table.clear(self.Remotes)
    table.clear(self.ActionRoutes)

    local remoteFolder = self.Paths.RemoteEvents

    for _, remoteName in ipairs(REMOTE_ROUTE_NAMES) do
        local remote = findDirect(remoteFolder, remoteName)
        if remote and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
            self.Remotes[remoteName] = remote
        end
    end

    for actionName, routeNames in pairs(ACTION_ROUTE_NAMES) do
        local resolved = {}

        for _, remoteName in ipairs(routeNames) do
            local remote = self.Remotes[remoteName]
            if remote then
                table.insert(resolved, remote)
            end
        end

        self.ActionRoutes[actionName] = resolved
    end
end

function GameAdapter:Initialize()
    self:_refreshPaths()
    self:_refreshRemoteRegistry()
    self.Initialized = true

    local rebuildResult = self:RebuildIndex()
    if not rebuildResult.Ok then
        return rebuildResult
    end

    return makeResult(true, "OK")
end

function GameAdapter:Destroy()
    self.Initialized = false
    table.clear(self.Paths)
    table.clear(self.Remotes)
    table.clear(self.ActionRoutes)
end

function GameAdapter:GetActionRoute(actionName)
    local route = self.ActionRoutes[actionName]
    if not route then
        return {}
    end

    return shallowCopy(route)
end

function GameAdapter:RebuildIndex()
    self:_refreshPaths()
    self:_refreshRemoteRegistry()

    self.Index:Replace("Resources", self:GetResources(nil))
    self.Index:Replace("Items", self:GetDroppedItems())
    self.Index:Replace("Loot", self:GetLootContainers())
    self.Index:Replace("Hostiles", self:GetHostileNPCs())
    self.Index:Replace("Players", self:GetPlayers())
    self.Index:Replace("Interactables", self:GetInteractableObjects())
    self.Index:Replace("Objectives", self:GetMissingChildren())

    local camp = self:GetCampDescriptor()
    local campfire = self:GetCampfireDescriptor()
    local merchant = self:GetMerchant()
    local spawn = self:GetSpawnDescriptor()

    self.Index:SetLocation("Camp", camp)
    self.Index:SetLocation("Campfire", campfire)
    self.Index:SetLocation("Merchant", merchant)
    self.Index:SetLocation("Spawn", spawn)
    self.Index:ReplaceSafePositions(self:GetSafePositions())

    return makeResult(true, "OK")
end

function GameAdapter:GetResources(resourceType)
    local out = {}

    for _, child in ipairs(directChildren(self.Paths.Foliage)) do
        local category = classifyResourceName(child.Name)

        if category and (resourceType == nil or resourceType == category) then
            local descriptor = self:_descriptor(child, category, {
                SourceContainer = "Workspace.Map.Foliage",
                ResourceType = category,
            })

            if descriptor then
                table.insert(out, descriptor)
            end
        end
    end

    return out
end

function GameAdapter:GetResourceTypes()
    return {
        "Wood",
        "Stone",
    }
end

function GameAdapter:IsResourceValid(target)
    if not target or not target.Instance then
        return false
    end

    return target.Instance.Parent == self.Paths.Foliage
        and classifyResourceName(target.Instance.Name) ~= nil
end

function GameAdapter:GetDroppedItems()
    local out = {}

    for _, child in ipairs(directChildren(self.Paths.Items)) do
        local isNpcModel = child:IsA("Model") and getNpcHumanoid(child) ~= nil

        if not isChestName(child.Name) and not isNpcModel then
            local descriptor = self:_descriptor(child, "DroppedItem", {
                SourceContainer = "Workspace.Items",
                ItemName = child.Name,
            })

            if descriptor then
                table.insert(out, descriptor)
            end
        end
    end

    return out
end

function GameAdapter:GetLootContainers()
    local out = {}

    for _, child in ipairs(directChildren(self.Paths.Items)) do
        if isChestName(child.Name) then
            local descriptor = self:_descriptor(child, "LootContainer", {
                SourceContainer = "Workspace.Items",
                ContainerName = child.Name,
            })

            if descriptor then
                table.insert(out, descriptor)
            end
        end
    end

    return out
end

function GameAdapter:GetItemCatalog()
    local names = {}
    local seen = {}

    local function addChildren(container)
        for _, child in ipairs(directChildren(container)) do
            if not seen[child.Name] then
                seen[child.Name] = true
                table.insert(names, child.Name)
            end
        end
    end

    addChildren(self.Paths.Items)
    addChildren(self.Paths.PlayerInventory)
    addChildren(self.Paths.PlayerItemBag)
    addChildren(self.Paths.PlayerBackpack)

    table.sort(names)
    return names
end

function GameAdapter:GetInventorySnapshot()
    self:_refreshPaths()

    local items = {}
    local count = 0

    local containers = {
        {
            Name = "Inventory",
            Instance = self.Paths.PlayerInventory,
        },
        {
            Name = "ItemBag",
            Instance = self.Paths.PlayerItemBag,
        },
        {
            Name = "Backpack",
            Instance = self.Paths.PlayerBackpack,
        },
        {
            Name = "Armour",
            Instance = self.Paths.PlayerArmour,
        },
    }

    for _, containerInfo in ipairs(containers) do
        for _, child in ipairs(directChildren(containerInfo.Instance)) do
            count += 1

            local descriptor = self:_descriptor(child, "InventoryItem", {
                Container = containerInfo.Name,
                ItemName = child.Name,
            })

            if descriptor then
                table.insert(items, descriptor)
            end
        end
    end

    return {
        Used = count,
        Capacity = nil,
        Items = items,
        CapacitySource = "UNMAPPED",
    }
end

function GameAdapter:GetInventoryUsage()
    local snapshot = self:GetInventorySnapshot()

    if snapshot.Capacity == nil or snapshot.Capacity <= 0 then
        return nil
    end

    return snapshot.Used / snapshot.Capacity
end

function GameAdapter:GetHostileNPCs()
    local out = {}

    for _, child in ipairs(directChildren(self.Paths.Characters)) do
        if child:IsA("Model") and HOSTILE_NAME_SET[child.Name] then
            local humanoid = getNpcHumanoid(child)

            local descriptor = self:_descriptor(child, child.Name, {
                SourceContainer = "Workspace.Characters",
                Health = humanoid and humanoid.Health or nil,
                MaxHealth = humanoid and humanoid.MaxHealth or nil,
                Humanoid = humanoid,
                ClassificationSource = "ConservativeNameWhitelist",
            })

            if descriptor then
                table.insert(out, descriptor)
            end
        end
    end

    return out
end

function GameAdapter:GetHostileTypes()
    local names = {}

    for name in pairs(HOSTILE_NAME_SET) do
        table.insert(names, name)
    end

    table.sort(names)
    return names
end

function GameAdapter:GetTargetHealth(target)
    if not target or not target.Instance then
        return nil
    end

    local humanoid = getNpcHumanoid(target.Instance)
    return humanoid and humanoid.Health or nil
end

function GameAdapter:GetThreatScore(_target, _originPosition)
    return nil
end

function GameAdapter:IsHostileValid(target)
    if not target or not target.Instance then
        return false
    end

    if target.Instance.Parent ~= self.Paths.Characters then
        return false
    end

    if not HOSTILE_NAME_SET[target.Instance.Name] then
        return false
    end

    local humanoid = getNpcHumanoid(target.Instance)
    if humanoid then
        return humanoid.Health > 0
    end

    return isAliveInstance(target.Instance)
end

function GameAdapter:GetMissingChildren()
    local out = {}

    for _, child in ipairs(directChildren(self.Paths.MissingKids)) do
        local descriptor = self:_descriptor(child, "MissingChild", {
            SourceContainer = "Workspace.Map.MissingKids",
            ObjectiveName = child.Name,
        })

        if descriptor then
            table.insert(out, descriptor)
        end
    end

    return out
end

function GameAdapter:GetObjectiveStatus()
    local objectives = self:GetMissingChildren()

    return {
        VisibleObjectiveCount = #objectives,
        ContainerExists = self.Paths.MissingKids ~= nil,
        Objectives = objectives,
    }
end

function GameAdapter:GetCampDescriptor()
    return self:_descriptor(self.Paths.MainFire, "Camp", {
        SourcePath = "Workspace.Map.Campground.MainFire",
    }, "Camp")
end

function GameAdapter:GetCampfireDescriptor()
    return self:_descriptor(self.Paths.MainFire, "Campfire", {
        SourcePath = "Workspace.Map.Campground.MainFire",
    }, "MainFire")
end

function GameAdapter:GetSpawnDescriptor()
    return self:_descriptor(self.Paths.SpawnLocation, "SafePosition", {
        SourcePath = "Workspace.Map.SpawnLocation",
    }, "SpawnLocation")
end

function GameAdapter:GetCampPosition()
    local descriptor = self:GetCampDescriptor()
    return descriptor and descriptor.Position or nil
end

function GameAdapter:GetSafePositions()
    local out = {}

    local spawn = self:GetSpawnDescriptor()
    if spawn then
        table.insert(out, spawn)
    end

    local camp = self:GetCampDescriptor()
    if camp then
        camp.Category = "SafePosition"
        table.insert(out, camp)
    end

    return out
end

function GameAdapter:GetMerchant()
    return self:_descriptor(self.Paths.ToolSmith, "MerchantCandidate", {
        SourcePath = "Workspace.Map.Landmarks.ToolSmith",
        StructuralRole = "ToolSmith",
        SemanticConfidence = "STRUCTURAL_CANDIDATE",
    }, "ToolSmith")
end

function GameAdapter:GetInteractableObjects()
    local out = {}
    local seenIds = {}

    local function appendDescriptor(descriptor)
        if descriptor and not seenIds[descriptor.Id] then
            seenIds[descriptor.Id] = true
            table.insert(out, descriptor)
        end
    end

    for _, descriptor in ipairs(self:GetDroppedItems()) do
        appendDescriptor(descriptor)
    end

    for _, descriptor in ipairs(self:GetLootContainers()) do
        appendDescriptor(descriptor)
    end

    for _, child in ipairs(directChildren(self.Paths.Campground)) do
        if CAMP_INTERACTABLE_NAMES[child.Name] then
            appendDescriptor(self:_descriptor(child, "CampObject", {
                SourceContainer = "Workspace.Map.Campground",
            }))
        end
    end

    for _, child in ipairs(directChildren(self.Paths.Landmarks)) do
        if LANDMARK_INTERACTABLE_NAMES[child.Name] then
            appendDescriptor(self:_descriptor(child, "LandmarkCandidate", {
                SourceContainer = "Workspace.Map.Landmarks",
                SemanticConfidence = "STRUCTURAL_CANDIDATE",
            }))
        end
    end

    return out
end

function GameAdapter:GetInteractionTypes()
    return {
        "DroppedItem",
        "LootContainer",
        "CampObject",
        "LandmarkCandidate",
    }
end

function GameAdapter:GetPlayerNeeds()
    local character = LocalPlayer and LocalPlayer.Character or nil
    local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil

    return {
        Health = humanoid and humanoid.Health or nil,
        MaxHealth = humanoid and humanoid.MaxHealth or nil,

        Stamina = nil,
        Food = nil,
        Water = nil,
        Warmth = nil,

        Unmapped = {
            "Stamina",
            "Food",
            "Water",
            "Warmth",
        },
    }
end

function GameAdapter:GetStatusEffects()
    return {}
end

function GameAdapter:GetCurrentNight()
    return nil
end

function GameAdapter:GetCampStatus()
    local descriptor = self:GetCampDescriptor()

    return {
        Exists = descriptor ~= nil and descriptor.IsValid,
        Position = descriptor and descriptor.Position or nil,
        Instance = descriptor and descriptor.Instance or nil,
        Fuel = nil,
        Level = nil,
    }
end

function GameAdapter:GetCampfireStatus()
    local descriptor = self:GetCampfireDescriptor()

    return {
        Exists = descriptor ~= nil and descriptor.IsValid,
        Position = descriptor and descriptor.Position or nil,
        Instance = descriptor and descriptor.Instance or nil,
        Fuel = nil,
        Lit = nil,
    }
end

function GameAdapter:GetAvailableTools()
    self:_refreshPaths()

    local out = {}
    local seen = {}

    local function appendFrom(container, containerName)
        for _, child in ipairs(directChildren(container)) do
            local key = containerName .. ":" .. child.Name
            if not seen[key] then
                seen[key] = true

                local descriptor = self:_descriptor(child, "ToolCandidate", {
                    Container = containerName,
                    ToolName = child.Name,
                })

                if descriptor then
                    table.insert(out, descriptor)
                end
            end
        end
    end

    appendFrom(self.Paths.PlayerInventory, "Inventory")
    appendFrom(self.Paths.PlayerBackpack, "Backpack")

    return out
end

function GameAdapter:GetEquippedTool()
    local character = LocalPlayer and LocalPlayer.Character or nil
    if not character then
        return nil
    end

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then
        return nil
    end

    return self:_descriptor(tool, "EquippedTool", {
        Container = "Character",
        ToolName = tool.Name,
    })
end

function GameAdapter:GetPlayers()
    local out = {}

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart") or nil

        local descriptor = {
            Id = self:_idFor(player),
            Category = "Player",
            DisplayName = player.DisplayName,
            Instance = player,
            Root = root,
            Position = root and root.Position or nil,
            IsValid = player.Parent == Players,
            Metadata = {
                UserId = player.UserId,
                Name = player.Name,
            },
        }

        table.insert(out, descriptor)
    end

    return out
end

-- The hierarchy dump proves these remote routes exist, but it does not define
-- their argument contracts. Actions remain intentionally non-invoking.

function GameAdapter:HarvestResource(_target)
    return self:_required("HarvestResource")
end

function GameAdapter:PickupItem(_target)
    return self:_required("PickupItem")
end

function GameAdapter:OpenLootContainer(_target)
    return self:_required("OpenLootContainer")
end

function GameAdapter:DepositItem(_item)
    return self:_required("DepositItem")
end

function GameAdapter:DiscardItem(_item)
    return self:_required("DiscardItem")
end

function GameAdapter:EquipTool(_tool)
    return self:_required("EquipTool")
end

function GameAdapter:Attack(_target)
    return self:_required("Attack")
end

function GameAdapter:PerformDefensiveAction(_target)
    return self:_required("PerformDefensiveAction")
end

function GameAdapter:ConsumeItem(_item)
    return self:_required("ConsumeItem")
end

function GameAdapter:PerformWarmthAction(_context)
    return self:_required("PerformWarmthAction")
end

function GameAdapter:Rest(_context)
    return self:_required("Rest")
end

function GameAdapter:CureStatus(_statusName)
    return self:_required("CureStatus")
end

function GameAdapter:MaintainCampfire(_context)
    return self:_required("MaintainCampfire")
end

function GameAdapter:Interact(_target)
    return self:_required("Interact")
end

local Adapter = GameAdapter.new(Index)
Framework.GameAdapter = Adapter

-- =========================================================
-- PART 17: CHARACTER CONTEXT
-- =========================================================

local CharacterContext = {
    Character = nil,
    Humanoid = nil,
    Root = nil,
}

local function bindCharacter(character)
    CharacterContext.Character = character
    CharacterContext.Humanoid = character:FindFirstChildOfClass("Humanoid")
        or character:WaitForChild("Humanoid", 5)
    CharacterContext.Root = character:FindFirstChild("HumanoidRootPart")
        or character:WaitForChild("HumanoidRootPart", 5)

    State:Set("Runtime.CharacterBound", CharacterContext.Humanoid ~= nil and CharacterContext.Root ~= nil)
end

local function unbindCharacter()
    CharacterContext.Character = nil
    CharacterContext.Humanoid = nil
    CharacterContext.Root = nil
    State:Set("Runtime.CharacterBound", false)
end

if LocalPlayer and LocalPlayer.Character then
    bindCharacter(LocalPlayer.Character)
end

if LocalPlayer then
    Connections:Add("Character", LocalPlayer.CharacterAdded:Connect(function(character)
        unbindCharacter()
        bindCharacter(character)
    end))

    Connections:Add("Character", LocalPlayer.CharacterRemoving:Connect(function()
        unbindCharacter()
    end))
end

Framework.CharacterContext = CharacterContext

-- =========================================================
-- BLOCK C: MOVEMENT CONTROLLER WITH CUBIC BEZIER SMOOTHING
-- Replace PART 18: MOVEMENT CONTROLLER
-- =========================================================

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(stateStore, threadManager, lockManager, diagnostics, pauseGate)
    local self = setmetatable({}, MovementController)
    self._state = stateStore
    self._threads = threadManager
    self._locks = lockManager
    self._diagnostics = diagnostics
    self._pauseGate = pauseGate
    self._ownerId = "MovementController"
    self._activeOperationId = 0
    self._previousPosition = nil
    self._original = {
        WalkSpeed = nil,
        JumpPower = nil,
        UseJumpPower = nil,
        Lighting = nil,
    }
    return self
end

function MovementController:_getHumanoidAndRoot()
    local humanoid = CharacterContext.Humanoid
    local root = CharacterContext.Root

    if not humanoid or not root or not root.Parent then
        return nil, nil
    end

    return humanoid, root
end

function MovementController:CaptureOriginalCharacterState()
    local humanoid = CharacterContext.Humanoid
    if not humanoid then
        return
    end

    if self._original.WalkSpeed == nil then
        self._original.WalkSpeed = humanoid.WalkSpeed
        self._original.JumpPower = humanoid.JumpPower
        self._original.UseJumpPower = humanoid.UseJumpPower
    end
end

function MovementController:RestoreCharacterState()
    local humanoid = CharacterContext.Humanoid
    if not humanoid then
        return
    end

    if self._original.WalkSpeed ~= nil then
        humanoid.WalkSpeed = self._original.WalkSpeed
    end

    if self._original.JumpPower ~= nil then
        humanoid.JumpPower = self._original.JumpPower
    end

    if self._original.UseJumpPower ~= nil then
        humanoid.UseJumpPower = self._original.UseJumpPower
    end
end

function MovementController:SaveCurrentPosition()
    local _, root = self:_getHumanoidAndRoot()
    if not root then
        return false
    end

    self._previousPosition = root.CFrame
    return true
end

function MovementController:GetPreviousPosition()
    return self._previousPosition
end

function MovementController:Cancel()
    self._activeOperationId += 1
    self._threads:Cancel("Movement.Active")
    self._locks:Release("MovementLock", self._ownerId)
    State:Set("Runtime.CurrentTask", nil)
end

function MovementController:_cubicBezier(p0, p1, p2, p3, t)
    local inverse = 1 - t
    local inverse2 = inverse * inverse
    local t2 = t * t

    return (inverse2 * inverse) * p0
        + (3 * inverse2 * t) * p1
        + (3 * inverse * t2) * p2
        + (t2 * t) * p3
end

function MovementController:_buildControlPoints(startPosition, destination, operationId)
    local delta = destination - startPosition
    local horizontal = Vector3.new(delta.X, 0, delta.Z)
    local distance = delta.Magnitude
    local horizontalDistance = horizontal.Magnitude

    local forward
    if horizontalDistance > 0.001 then
        forward = horizontal.Unit
    else
        forward = Vector3.new(0, 0, -1)
    end

    local side = Vector3.new(-forward.Z, 0, forward.X)
    local sign = operationId % 2 == 0 and 1 or -1

    local configuredClearance = self._state:Get("Values.Movement.TweenClearance", 12)
    local lift = math.clamp(
        math.max(configuredClearance, horizontalDistance * 0.08),
        6,
        28
    )

    local lateral = math.clamp(horizontalDistance * 0.06, 0, 8)
    local p1 = startPosition
        + delta * 0.30
        + Vector3.new(0, lift, 0)
        + side * lateral * sign

    local p2 = startPosition
        + delta * 0.72
        + Vector3.new(0, lift * 0.65, 0)
        - side * lateral * 0.35 * sign

    if distance < 8 then
        p1 = startPosition + delta * 0.33 + Vector3.new(0, math.min(lift, 3), 0)
        p2 = startPosition + delta * 0.66 + Vector3.new(0, math.min(lift * 0.5, 2), 0)
    end

    return p1, p2
end

function MovementController:_estimateBezierLength(p0, p1, p2, p3, samples)
    samples = samples or 16
    local length = 0
    local previous = p0

    for index = 1, samples do
        local t = index / samples
        local current = self:_cubicBezier(p0, p1, p2, p3, t)
        length += (current - previous).Magnitude
        previous = current
    end

    return length
end

function MovementController:_computeStableApproach(destination, options, rootPosition)
    local targetPart = options.TargetPart
    local approachRadius = options.ApproachRadius

    if not targetPart or not targetPart:IsA("BasePart") or not approachRadius then
        return destination
    end

    local center = targetPart.Position
    local away = rootPosition - center
    local horizontalAway = Vector3.new(away.X, 0, away.Z)

    if horizontalAway.Magnitude <= 0.001 then
        horizontalAway = Vector3.new(0, 0, 1)
    else
        horizontalAway = horizontalAway.Unit
    end

    local halfExtent = math.max(targetPart.Size.X, targetPart.Size.Z) * 0.5
    local standOff = math.max(approachRadius, halfExtent + 1.5)
    local position = center + horizontalAway * standOff

    return CFrame.new(position) * destination.Rotation
end

function MovementController:_tweenSegment(root, destinationCFrame, duration, token, operationId)
    local tween = TweenService:Create(
        root,
        TweenInfo.new(math.max(duration, 0.03), Enum.EasingStyle.Linear),
        { CFrame = destinationCFrame }
    )

    tween:Play()

    while not token.Cancelled
        and operationId == self._activeOperationId
        and tween.PlaybackState == Enum.PlaybackState.Playing
    do
        if self._pauseGate:IsPaused() then
            tween:Pause()

            if not self._pauseGate:WaitUntilResumed(token, 0.05) then
                tween:Cancel()
                return false
            end

            if token.Cancelled or operationId ~= self._activeOperationId then
                tween:Cancel()
                return false
            end

            tween:Play()
        end

        task.wait()
    end

    if token.Cancelled or operationId ~= self._activeOperationId then
        tween:Cancel()
        return false
    end

    return tween.PlaybackState == Enum.PlaybackState.Completed
end

function MovementController:_followBezier(root, destinationCFrame, speed, token, operationId, options)
    local p0 = root.Position
    local p3 = destinationCFrame.Position
    local p1, p2 = self:_buildControlPoints(p0, p3, operationId)

    local estimatedLength = self:_estimateBezierLength(p0, p1, p2, p3, 20)
    local sampleSpacing = options.SampleSpacing or 3.5
    local segmentCount = math.clamp(math.ceil(estimatedLength / sampleSpacing), 6, 64)

    local previousPosition = p0

    for index = 1, segmentCount do
        if token.Cancelled or operationId ~= self._activeOperationId then
            return false
        end

        if not self._pauseGate:WaitUntilResumed(token, 0.05) then
            return false
        end

        local t = index / segmentCount
        local position = self:_cubicBezier(p0, p1, p2, p3, t)
        local nextT = math.min(1, t + (1 / segmentCount))
        local lookPoint = self:_cubicBezier(p0, p1, p2, p3, nextT)
        local direction = lookPoint - position

        local segmentCFrame
        if direction.Magnitude > 0.001 then
            segmentCFrame = CFrame.lookAt(position, lookPoint)
        else
            segmentCFrame = CFrame.new(position) * destinationCFrame.Rotation
        end

        if index == segmentCount then
            segmentCFrame = destinationCFrame
        end

        local segmentDistance = (position - previousPosition).Magnitude
        local duration = segmentDistance / math.max(speed, 1)

        if not self:_tweenSegment(root, segmentCFrame, duration, token, operationId) then
            return false
        end

        previousPosition = position
    end

    return true
end

function MovementController:_settleAtDestination(root, destination, token, operationId, options)
    local settleDelay = options.SettleDelay or 0.12
    local tolerance = options.FinalTolerance or 1.25
    local deadline = now() + settleDelay

    while not token.Cancelled and now() < deadline do
        if operationId ~= self._activeOperationId then
            return false
        end

        if not self._pauseGate:WaitUntilResumed(token, 0.05) then
            return false
        end

        task.wait(0.02)
    end

    local remaining = (root.Position - destination.Position).Magnitude
    if remaining <= tolerance then
        return true
    end

    local correctionSpeed = options.CorrectionSpeed
        or math.max(self._state:Get("Values.Movement.TravelSpeed", 32) * 0.5, 8)

    local duration = remaining / correctionSpeed
    return self:_tweenSegment(root, destination, duration, token, operationId)
end

function MovementController:TravelTo(destination, options)
    options = options or {}

    local humanoid, root = self:_getHumanoidAndRoot()
    if not humanoid or not root then
        return makeResult(false, "CHARACTER_UNAVAILABLE")
    end

    if typeof(destination) == "Vector3" then
        destination = CFrame.new(destination)
    end

    if typeof(destination) ~= "CFrame" then
        return makeResult(false, "INVALID_DESTINATION")
    end

    if not self._locks:Acquire("MovementLock", self._ownerId) then
        return makeResult(false, "LOCKED")
    end

    self:SaveCurrentPosition()
    self._activeOperationId += 1
    local operationId = self._activeOperationId
    local method = options.Method or self._state:Get("Values.MainFarm.MovementMethod", "Path")
    local speed = options.Speed or self._state:Get("Values.Movement.TravelSpeed", 32)
    local stableDestination = self:_computeStableApproach(destination, options, root.Position)

    State:Set("Runtime.CurrentTask", "Travel")

    self._threads:Spawn("Movement.Active", function(token)
        local ok = false

        if not self._pauseGate:WaitUntilResumed(token, 0.05) then
            self._locks:Release("MovementLock", self._ownerId)
            State:Set("Runtime.CurrentTask", nil)
            return
        end

        if method == "Walk" then
            humanoid:MoveTo(stableDestination.Position)

            local deadline = now()
                + math.max((root.Position - stableDestination.Position).Magnitude / math.max(speed, 1) * 2, 3)

            while not token.Cancelled and operationId == self._activeOperationId and now() < deadline do
                if self._pauseGate:IsPaused() then
                    humanoid:MoveTo(root.Position)
                    if not self._pauseGate:WaitUntilResumed(token, 0.05) then
                        break
                    end
                    humanoid:MoveTo(stableDestination.Position)
                end

                if (root.Position - stableDestination.Position).Magnitude <= 4 then
                    ok = true
                    break
                end

                task.wait(0.05)
            end

        elseif method == "Path" then
            local path = PathfindingService:CreatePath()

            local pathOk = pcall(function()
                path:ComputeAsync(root.Position, stableDestination.Position)
            end)

            if pathOk and path.Status == Enum.PathStatus.Success then
                for _, waypoint in ipairs(path:GetWaypoints()) do
                    if token.Cancelled or operationId ~= self._activeOperationId then
                        break
                    end

                    if not self._pauseGate:WaitUntilResumed(token, 0.05) then
                        break
                    end

                    if waypoint.Action == Enum.PathWaypointAction.Jump then
                        humanoid.Jump = true
                    end

                    humanoid:MoveTo(waypoint.Position)

                    local finished = false
                    local reached = false
                    local connection

                    connection = humanoid.MoveToFinished:Connect(function(success)
                        reached = success
                        finished = true
                    end)

                    local deadline = now() + 4
                    while not token.Cancelled
                        and operationId == self._activeOperationId
                        and not finished
                        and now() < deadline
                    do
                        if self._pauseGate:IsPaused() then
                            humanoid:MoveTo(root.Position)
                            if not self._pauseGate:WaitUntilResumed(token, 0.05) then
                                break
                            end
                            humanoid:MoveTo(waypoint.Position)
                        end

                        task.wait(0.05)
                    end

                    connection:Disconnect()

                    if not reached then
                        break
                    end
                end

                ok = (root.Position - stableDestination.Position).Magnitude <= 6
            end

        elseif method == "Tween Adapter" then
            ok = self:_followBezier(
                root,
                stableDestination,
                speed,
                token,
                operationId,
                options
            )

            if ok and not token.Cancelled then
                ok = self:_settleAtDestination(
                    root,
                    stableDestination,
                    token,
                    operationId,
                    options
                )
            end
        end

        self._locks:Release("MovementLock", self._ownerId)
        State:Set("Runtime.CurrentTask", nil)

        if not ok and not token.Cancelled then
            self._diagnostics:RecordError("Movement", "Travel operation did not complete")
        end
    end)

    return makeResult(true, "STARTED")
end

function MovementController:ReturnToPrevious(options)
    if not self._previousPosition then
        return makeResult(false, "TARGET_NOT_FOUND", "No previous position recorded.")
    end

    return self:TravelTo(self._previousPosition, options)
end

function MovementController:Destroy()
    self:Cancel()
    self:RestoreCharacterState()
end

local Movement = MovementController.new(
    State,
    Threads,
    Locks,
    DiagnosticsManager,
    PauseGate
)
Framework.MovementController = Movement

-- =========================================================
-- PART 19: ESP MANAGER SHELL
-- =========================================================

local ESPManager = {}
ESPManager.__index = ESPManager

function ESPManager.new(instanceManager, connectionManager, runtimeIndex)
    local self = setmetatable({}, ESPManager)
    self._instances = instanceManager
    self._connections = connectionManager
    self._index = runtimeIndex
    self._tracked = {}
    self._running = false
    return self
end

function ESPManager:Track(id, descriptor)
    self._tracked[id] = descriptor
end

function ESPManager:Untrack(id)
    self._tracked[id] = nil
end

function ESPManager:Clear()
    table.clear(self._tracked)
    self._instances:DestroyGroup("ESP")
end

function ESPManager:Start()
    if self._running then
        return
    end
    self._running = true

    Connections:Add("ESP", RunService.RenderStepped:Connect(function()
        if not self._running then
            return
        end

        -- Structural single-pipeline renderer.
        -- Actual visual primitives are intentionally not instantiated here.
        -- Consume RuntimeIndex descriptors here after a renderer is selected.
    end))
end

function ESPManager:Stop()
    self._running = false
    self._connections:DisconnectGroup("ESP")
end

function ESPManager:Destroy()
    self:Stop()
    self:Clear()
end

local ESP = ESPManager.new(Instances, Connections, Index)
Framework.ESPManager = ESP

-- =========================================================
-- PART 20: FEATURE REGISTRY
-- =========================================================

local FeatureRegistry = {}
FeatureRegistry.__index = FeatureRegistry

function FeatureRegistry.new(diagnostics)
    local self = setmetatable({}, FeatureRegistry)
    self._features = {}
    self._diagnostics = diagnostics
    return self
end

function FeatureRegistry:Register(id, feature)
    assert(type(id) == "string", "Feature id must be string")
    assert(type(feature) == "table", "Feature must be table")

    feature.Name = feature.Name or id
    feature.Enabled = feature.Enabled == true
    self._features[id] = feature
    self._diagnostics.Counters.Features = self:Count()
end

function FeatureRegistry:Get(id)
    return self._features[id]
end

function FeatureRegistry:SetEnabled(id, enabled)
    local feature = self._features[id]
    if not feature then
        return false, "unknown feature"
    end

    if feature.Enabled == enabled then
        return true
    end

    local methodName = enabled and "Enable" or "Disable"
    local method = feature[methodName]

    if type(method) == "function" then
        local ok, err = pcall(method, feature)
        if not ok then
            self._diagnostics:RecordError("Feature:" .. id, err)
            return false, err
        end
    end

    feature.Enabled = enabled
    State:Set("Features." .. id, enabled)

    return true
end

function FeatureRegistry:DisableAll()
    for id, feature in pairs(self._features) do
        if feature.Enabled then
            self:SetEnabled(id, false)
        end
    end
end

function FeatureRegistry:DestroyAll()
    self:DisableAll()

    for id, feature in pairs(self._features) do
        if type(feature.Destroy) == "function" then
            local ok, err = pcall(feature.Destroy, feature)
            if not ok then
                self._diagnostics:RecordError("FeatureDestroy:" .. id, err)
            end
        end
    end

    table.clear(self._features)
    self._diagnostics.Counters.Features = 0
end

function FeatureRegistry:Count()
    local count = 0
    for _ in pairs(self._features) do
        count += 1
    end
    return count
end

local Features = FeatureRegistry.new(DiagnosticsManager)
Framework.FeatureRegistry = Features

-- =========================================================
-- PART 21: CONTROLLER SHELLS
-- =========================================================

local FarmController = {}
FarmController.__index = FarmController

function FarmController.new(adapter, runtimeIndex, targetResolver, movementController, scheduler, actionQueue)
    local self = setmetatable({}, FarmController)
    self.Adapter = adapter
    self.Index = runtimeIndex
    self.Targets = targetResolver
    self.Movement = movementController
    self.Scheduler = scheduler
    self.Actions = actionQueue
    self.Enabled = false
    self.CurrentTargetId = nil
    self.ReservedTargetIds = {}
    self.RecentFailureCooldowns = {}
    return self
end

function FarmController:Enable()
    self.Enabled = true
    self.Scheduler:SetEnabled("FarmEvaluation", true)
end

function FarmController:Disable()
    self.Enabled = false
    self.Scheduler:SetEnabled("FarmEvaluation", false)
    self.CurrentTargetId = nil
    table.clear(self.ReservedTargetIds)
end

function FarmController:Evaluate(context)
    if not self.Enabled or not context.IsCurrent() then
        return
    end

    -- Deliberately no game-specific action.
    -- Read candidates from RuntimeIndex and route verified operations through GameAdapter.
end

local SurvivalController = {}
SurvivalController.__index = SurvivalController

function SurvivalController.new(adapter, scheduler, actionQueue)
    local self = setmetatable({}, SurvivalController)
    self.Adapter = adapter
    self.Scheduler = scheduler
    self.Actions = actionQueue
    self.Enabled = false
    return self
end

function SurvivalController:Enable()
    self.Enabled = true
    self.Scheduler:SetEnabled("SurvivalEvaluation", true)
end

function SurvivalController:Disable()
    self.Enabled = false
    self.Scheduler:SetEnabled("SurvivalEvaluation", false)
end

function SurvivalController:Evaluate(context)
    if not self.Enabled or not context.IsCurrent() then
        return
    end

    local snapshot = self.Adapter:GetPlayerNeeds()
    if type(snapshot) ~= "table" then
        return
    end

    -- One consolidated evaluation point.
    -- No fabricated consume, rest, warmth, or cure implementation.
end

local CombatController = {}
CombatController.__index = CombatController

function CombatController.new(adapter, runtimeIndex, targetResolver, scheduler, actionQueue)
    local self = setmetatable({}, CombatController)
    self.Adapter = adapter
    self.Index = runtimeIndex
    self.Targets = targetResolver
    self.Scheduler = scheduler
    self.Actions = actionQueue
    self.Enabled = false
    return self
end

function CombatController:Enable()
    self.Enabled = true
    self.Scheduler:SetEnabled("CombatEvaluation", true)
end

function CombatController:Disable()
    self.Enabled = false
    self.Scheduler:SetEnabled("CombatEvaluation", false)
    self.Targets:Clear()
end

function CombatController:Evaluate(context)
    if not self.Enabled or not context.IsCurrent() then
        return
    end

    -- Select only from shared RuntimeIndex.Hostiles.
    -- Verified attack operation must be implemented in GameAdapter:Attack.
end

local Farm = FarmController.new(Adapter, Index, Targets, Movement, Jobs, Actions)
local Survival = SurvivalController.new(Adapter, Jobs, Actions)
local Combat = CombatController.new(Adapter, Index, Targets, Jobs, Actions)

Framework.FarmController = Farm
Framework.SurvivalController = Survival
Framework.CombatController = Combat

-- =========================================================
-- PART 22: SCHEDULER JOB REGISTRATION
-- =========================================================

Jobs:RegisterJob("ResourceIndexRefresh", 3.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:Replace("Resources", Adapter:GetResources(nil))
end, true)

Jobs:RegisterJob("ItemIndexRefresh", 2.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:Replace("Items", Adapter:GetDroppedItems())
end, true)

Jobs:RegisterJob("LootIndexRefresh", 3.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:Replace("Loot", Adapter:GetLootContainers())
end, true)

Jobs:RegisterJob("TargetIndexRefresh", 1.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:Replace("Hostiles", Adapter:GetHostileNPCs())
end, true)

Jobs:RegisterJob("PlayerIndexRefresh", 1.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:Replace("Players", Adapter:GetPlayers())
end, true)

Jobs:RegisterJob("ObjectiveRefresh", 5.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:Replace("Objectives", Adapter:GetMissingChildren())
end, true)

Jobs:RegisterJob("InteractableRefresh", 3.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:Replace("Interactables", Adapter:GetInteractableObjects())
end, true)

Jobs:RegisterJob("LocationRefresh", 5.0, function(context)
    if not context.IsCurrent() then
        return
    end

    Index:SetLocation("Camp", Adapter:GetCampDescriptor())
    Index:SetLocation("Campfire", Adapter:GetCampfireDescriptor())
    Index:SetLocation("Merchant", Adapter:GetMerchant())
    Index:SetLocation("Spawn", Adapter:GetSpawnDescriptor())
    Index:ReplaceSafePositions(Adapter:GetSafePositions())
end, true)

Jobs:RegisterJob("FarmEvaluation", 0.2, function(context)
    Farm:Evaluate(context)
end, false)

Jobs:RegisterJob("SurvivalEvaluation", 0.35, function(context)
    Survival:Evaluate(context)
end, false)

Jobs:RegisterJob("CombatEvaluation", 0.15, function(context)
    Combat:Evaluate(context)
end, false)

Jobs:RegisterJob("DiagnosticsUpdate", 1.0, function()
    DiagnosticsManager.Counters.Threads = Threads:Count()
    DiagnosticsManager.Counters.Connections = Connections:Count()
    DiagnosticsManager.Counters.Instances = Instances:Count()
    DiagnosticsManager.Counters.SchedulerJobs = Jobs:Count()
end, true)

-- =========================================================
-- PART 23: FEATURE REGISTRATIONS
-- =========================================================

Features:Register("MainFarm.AutoWood", {
    Enable = function()
        Farm:Enable()
    end,
    Disable = function()
        Farm:Disable()
    end,
})

Features:Register("Combat.Master", {
    Enable = function()
        Combat:Enable()
    end,
    Disable = function()
        Combat:Disable()
    end,
})

Features:Register("Survival.Master", {
    Enable = function()
        Survival:Enable()
    end,
    Disable = function()
        Survival:Disable()
    end,
})

Features:Register("ESP.Master", {
    Enable = function()
        ESP:Start()
    end,
    Disable = function()
        ESP:Stop()
        ESP:Clear()
    end,
})

-- =========================================================
-- PART 24: LAZY TAB HOST
-- =========================================================

local LazyTabHost = {}
LazyTabHost.__index = LazyTabHost

function LazyTabHost.new(stateStore, diagnostics)
    local self = setmetatable({}, LazyTabHost)
    self._state = stateStore
    self._diagnostics = diagnostics
    self._tabs = {}
    self._selectionUnsubscribe = nil
    return self
end

function LazyTabHost:Register(name, rayfieldTab, builder)
    assert(type(name) == "string", "LazyTabHost:Register requires tab name")
    assert(type(builder) == "function", "LazyTabHost:Register requires builder")

    self._tabs[name] = {
        Name = name,
        Tab = rayfieldTab,
        Builder = builder,
        Loaded = false,
        Loading = false,
    }
end

function LazyTabHost:NotifySelected(name)
    local record = self._tabs[name]
    if not record or record.Loaded or record.Loading then
        return
    end

    record.Loading = true

    local ok, err = pcall(record.Builder, record.Tab)

    record.Loading = false

    if not ok then
        self._diagnostics:RecordError("LazyTab:" .. name, err)
        return
    end

    record.Loaded = true
    self._state:Set("UI.LoadedTabs." .. name, true)
end

function LazyTabHost:AttachSelectionSource(subscribe)
    -- Rayfield's documented stable API exposes CreateTab but not a public tab-selected callback.
    -- Keep selection wiring isolated here. A supported integration source should call:
    -- callback("Main Farm"), callback("Combat & Targeting"), etc.
    assert(type(subscribe) == "function", "selection source must be a function")

    if self._selectionUnsubscribe then
        self._selectionUnsubscribe()
        self._selectionUnsubscribe = nil
    end

    self._selectionUnsubscribe = subscribe(function(tabName)
        self:NotifySelected(tabName)
    end)
end

function LazyTabHost:Destroy()
    if self._selectionUnsubscribe then
        self._selectionUnsubscribe()
        self._selectionUnsubscribe = nil
    end

    table.clear(self._tabs)
end

local LazyTabs = LazyTabHost.new(State, DiagnosticsManager)
Framework.LazyTabHost = LazyTabs

-- =========================================================
-- PART 25: RAYFIELD UI SHELL
-- =========================================================

local UI = {
    Rayfield = nil,
    Window = nil,
    Tabs = {},
    Ready = false,
}

local TabDefinitions = {
    { Name = "Main Farm", Icon = "trees" },
    { Name = "Combat & Targeting", Icon = "crosshair" },
    { Name = "Survival Automation", Icon = "heart-pulse" },
    { Name = "Movement & Physics", Icon = "move-3d" },
    { Name = "Visuals & ESP", Icon = "eye" },
    { Name = "Teleports & Map", Icon = "map" },
    { Name = "World & Interactions", Icon = "globe-2" },
    { Name = "Player & Session", Icon = "user-round" },
    { Name = "Runtime Safety", Icon = "activity" },
    { Name = "Settings & Configs", Icon = "settings" },
}

local function bindToggle(tab, name, flag, featureId, defaultValue)
    return tab:CreateToggle({
        Name = name,
        CurrentValue = defaultValue == true,
        Flag = flag,
        Callback = function(value)
            State:Set("Features." .. featureId, value)
            Features:SetEnabled(featureId, value)
        end,
    })
end

local function bindSlider(tab, name, flag, statePath, range, increment, suffix, defaultValue)
    return tab:CreateSlider({
        Name = name,
        Range = range,
        Increment = increment,
        Suffix = suffix or "",
        CurrentValue = defaultValue,
        Flag = flag,
        Callback = function(value)
            State:Set(statePath, value)
        end,
    })
end

local function buildMainFarm(tab)
    tab:CreateSection("Farming")
    bindToggle(tab, "Auto Farm Wood", "MainFarm.AutoWood", "MainFarm.AutoWood", false)
    bindSlider(
        tab,
        "Farm Distance",
        "MainFarm.FarmDistance",
        "Values.MainFarm.FarmDistance",
        { 25, 500 },
        5,
        " studs",
        State:Get("Values.MainFarm.FarmDistance", 150)
    )

    tab:CreateDropdown({
        Name = "Movement Method",
        Options = { "Walk", "Path", "Tween Adapter" },
        CurrentOption = { State:Get("Values.MainFarm.MovementMethod", "Path") },
        MultipleOptions = false,
        Flag = "MainFarm.MovementMethod",
        Callback = function(options)
            State:Set("Values.MainFarm.MovementMethod", options[1])
        end,
    })

    tab:CreateSection("Adapter status")
    tab:CreateParagraph({
        Title = "Game-specific actions",
        Content = "Harvesting, pickup, loot, deposit, and inventory cleanup remain ADAPTER REQUIRED until verified runtime mapping is supplied.",
    })
end

local function buildCombat(tab)
    tab:CreateSection("Combat")
    bindToggle(tab, "Combat Automation Master Toggle", "Combat.Master", "Combat.Master", false)

    bindSlider(
        tab,
        "Maximum Target Distance",
        "Combat.MaxTargetDistance",
        "Values.Combat.MaxTargetDistance",
        { 10, 250 },
        5,
        " studs",
        State:Get("Values.Combat.MaxTargetDistance", 80)
    )

    bindSlider(
        tab,
        "Attack Evaluation Interval",
        "Combat.AttackInterval",
        "Values.Combat.AttackInterval",
        { 0.1, 2 },
        0.05,
        " s",
        State:Get("Values.Combat.AttackInterval", 0.45)
    )

    tab:CreateParagraph({
        Title = "Adapter boundary",
        Content = "No attack remote or weapon internals are defined. GameAdapter:Attack(target) is intentionally empty.",
    })
end

local function buildSurvival(tab)
    tab:CreateSection("Survival")
    bindToggle(tab, "Survival Master Toggle", "Survival.Master", "Survival.Master", false)

    bindSlider(
        tab,
        "Health Threshold",
        "Survival.HealthThreshold",
        "Values.Survival.HealthThreshold",
        { 1, 100 },
        1,
        "%",
        State:Get("Values.Survival.HealthThreshold", 40)
    )

    bindSlider(
        tab,
        "Danger Radius",
        "Survival.DangerRadius",
        "Values.Survival.DangerRadius",
        { 5, 150 },
        5,
        " studs",
        State:Get("Values.Survival.DangerRadius", 40)
    )
end

local function buildMovement(tab)
    tab:CreateSection("Character movement")

    bindSlider(
        tab,
        "Travel Speed",
        "Movement.TravelSpeed",
        "Values.Movement.TravelSpeed",
        { 5, 100 },
        1,
        " studs/s",
        State:Get("Values.Movement.TravelSpeed", 32)
    )

    bindSlider(
        tab,
        "Tween Clearance",
        "Movement.TweenClearance",
        "Values.Movement.TweenClearance",
        { 8, 28 },
        1,
        " studs",
        State:Get("Values.Movement.TweenClearance", 12)
    )

    tab:CreateButton({
        Name = "Stop Current Movement",
        Callback = function()
            Movement:Cancel()
        end,
    })

    tab:CreateButton({
        Name = "Save Current Position",
        Callback = function()
            Movement:SaveCurrentPosition()
        end,
    })

    tab:CreateButton({
        Name = "Return to Previous Position",
        Callback = function()
            Movement:ReturnToPrevious({
                Method = State:Get("Values.MainFarm.MovementMethod", "Path"),
            })
        end,
    })
end

local function buildVisuals(tab)
    tab:CreateSection("ESP pipeline")
    bindToggle(tab, "ESP Master", "ESP.Master", "ESP.Master", false)

    bindSlider(
        tab,
        "ESP Update Rate",
        "ESP.UpdateRate",
        "Values.ESP.UpdateRate",
        { 0.03, 0.5 },
        0.01,
        " s",
        State:Get("Values.ESP.UpdateRate", 0.1)
    )

    tab:CreateButton({
        Name = "Clear All ESP Objects",
        Callback = function()
            ESP:Clear()
        end,
    })
end

local function buildTeleports(tab)
    tab:CreateSection("Waypoints")
    tab:CreateButton({
        Name = "Save Current Position",
        Callback = function()
            Movement:SaveCurrentPosition()
        end,
    })

    tab:CreateButton({
        Name = "Cancel Travel",
        Callback = function()
            Movement:Cancel()
        end,
    })

    tab:CreateParagraph({
        Title = "Map destinations",
        Content = "Camp, merchant, children, and safe destinations require verified GameAdapter resolvers. No coordinates are hardcoded.",
    })
end

local function buildWorld(tab)
    tab:CreateSection("Local environment")
    tab:CreateButton({
        Name = "Restore Environment Settings",
        Callback = function()
            -- Hook local lighting snapshot restoration here.
            -- No server world state is modified.
        end,
    })

    tab:CreateParagraph({
        Title = "Interaction adapter",
        Content = "Auto pickup, resource interaction, and other game interactions remain behind GameAdapter.",
    })
end

local function buildPlayerSession(tab)
    tab:CreateSection("Session")
    tab:CreateLabel("Health Monitor: bound to local character lifecycle")
    tab:CreateLabel("Current Automation Task: read from State.Runtime.CurrentTask")
    tab:CreateButton({
        Name = "Reset Session Diagnostics",
        Callback = function()
            DiagnosticsManager:Reset()
        end,
    })
end

local function buildRuntime(tab)
    tab:CreateSection("Runtime")

    bindSlider(
        tab,
        "Maximum Actions Per Second",
        "Runtime.MaxActionsPerSecond",
        "Values.Runtime.MaxActionsPerSecond",
        { 1, 20 },
        1,
        "",
        State:Get("Values.Runtime.MaxActionsPerSecond", 4)
    )

    tab:CreateButton({
        Name = "Stop All Automation",
        Callback = function()
            Features:DisableAll()
            Actions:Clear()
            Movement:Cancel()
            Targets:Clear()
        end,
    })

    tab:CreateButton({
        Name = "Print Local Diagnostic Summary",
        Callback = function()
            print(HttpService:JSONEncode(DiagnosticsManager:Summary()))
        end,
    })
end

local function buildSettings(tab)
    tab:CreateSection("Configuration")

    tab:CreateInput({
        Name = "Config Name",
        CurrentValue = State:Get("Config.ActiveProfile", "Default"),
        PlaceholderText = "Default",
        RemoveTextAfterFocusLost = false,
        Flag = "Settings.ConfigName",
        Callback = function(text)
            State:Set("Config.ActiveProfile", text ~= "" and text or "Default")
        end,
    })

    tab:CreateButton({
        Name = "Save Current Config",
        Callback = function()
            Configs:Save(State:Get("Config.ActiveProfile", "Default"))
        end,
    })

    tab:CreateButton({
        Name = "Load Selected Config",
        Callback = function()
            Configs:Load(State:Get("Config.ActiveProfile", "Default"))
        end,
    })

    tab:CreateButton({
        Name = "Reset Everything",
        Callback = function()
            Features:DisableAll()
            State:ResetAll()
        end,
    })

    tab:CreateButton({
        Name = "Full Script Unload",
        Callback = function()
            Framework:Destroy()
        end,
    })
end

local Builders = {
    ["Main Farm"] = buildMainFarm,
    ["Combat & Targeting"] = buildCombat,
    ["Survival Automation"] = buildSurvival,
    ["Movement & Physics"] = buildMovement,
    ["Visuals & ESP"] = buildVisuals,
    ["Teleports & Map"] = buildTeleports,
    ["World & Interactions"] = buildWorld,
    ["Player & Session"] = buildPlayerSession,
    ["Runtime Safety"] = buildRuntime,
    ["Settings & Configs"] = buildSettings,
}

function UI:Initialize(rayfieldLibrary)
    self.Rayfield = rayfieldLibrary

    self.Window = rayfieldLibrary:CreateWindow({
        Name = "Forest Core",
        Icon = 0,
        LoadingTitle = "Forest Core",
        LoadingSubtitle = "Structural Runtime",
        ShowText = "Forest Core",
        Theme = "Default",
        ToggleUIKeybind = "K",

        DisableRayfieldPrompts = true,
        DisableBuildWarnings = false,

        -- External ConfigManager owns persistence.
        ConfigurationSaving = {
            Enabled = false,
            FolderName = nil,
            FileName = "ForestCore",
        },

        Discord = {
            Enabled = false,
            Invite = "",
            RememberJoins = false,
        },

        KeySystem = false,
    })

    for _, definition in ipairs(TabDefinitions) do
        local tab = self.Window:CreateTab(definition.Name, definition.Icon)
        self.Tabs[definition.Name] = tab

        -- Register builder only. Do not instantiate content here.
        LazyTabs:Register(definition.Name, tab, Builders[definition.Name])
    end

    self.Ready = true
    return true
end

Framework.UI = UI

-- =========================================================
-- PART 26: CLEANUP MANAGER
-- =========================================================

local CleanupManager = {}
CleanupManager.__index = CleanupManager

function CleanupManager.new()
    local self = setmetatable({}, CleanupManager)
    self._running = false
    return self
end

function CleanupManager:PanicShutdown()
    if self._running then
        return
    end

    self._running = true

    Features:DisableAll()
    Actions:Clear()
    Jobs:StopAllJobs()
    Jobs:Stop()
    Threads:CancelAll()
    Connections:DisconnectAll()
    Instances:DestroyAll()

    Movement:Destroy()
    ESP:Destroy()
    Targets:Clear()
    Index:Clear()
    Locks:Reset()

    State:Set("Runtime.CurrentTask", nil)
    State:Set("Runtime.CurrentTargetId", nil)
    State:Set("Runtime.Status", "Stopped")

    self._running = false
end

function CleanupManager:FullUnload()
    self:PanicShutdown()

    Features:DestroyAll()
    LazyTabs:Destroy()
    Adapter:Destroy()

    if UI.Rayfield and type(UI.Rayfield.Destroy) == "function" then
        pcall(function()
            UI.Rayfield:Destroy()
        end)
    end

    Framework.Destroyed = true
    State:Set("Runtime.Status", "Destroyed")

end

local Cleanup = CleanupManager.new()
Framework.CleanupManager = Cleanup

function Framework:PanicShutdown()
    Cleanup:PanicShutdown()
end

function Framework:Destroy()
    Cleanup:FullUnload()
end

-- =========================================================
-- PART 27: INITIALIZATION
-- =========================================================

function Framework:Start()
    if self.Destroyed then
        return false, "framework already destroyed"
    end

    local initOk, initResult = pcall(function()
        return Adapter:Initialize()
    end)

    if not initOk then
        return false, tostring(initResult)
    end

    if type(initResult) ~= "table" then
        return false, "Adapter:Initialize returned an invalid result."
    end

    if not initResult.Ok then
        return false, initResult.Message
    end

    Movement:CaptureOriginalCharacterState()
    Jobs:Start()

    State:Set("Runtime.Status", "Running")
    return true
end

-- =========================================================
-- PART 28: DIRECT BOOTSTRAP
-- =========================================================
--
-- Production-safe bootstrap for an owned Roblox experience:
-- place a Rayfield-compatible ModuleScript named "Rayfield" in ReplicatedStorage.
-- The module must return the Rayfield library table.

local function resolveRayfieldLibrary()
    local module = ReplicatedStorage:FindFirstChild("Rayfield")

    if not module then
        return nil, "ReplicatedStorage.Rayfield ModuleScript was not found."
    end

    if not module:IsA("ModuleScript") then
        return nil, "ReplicatedStorage.Rayfield must be a ModuleScript."
    end

    local ok, library = pcall(require, module)

    if not ok then
        return nil, "Rayfield module failed to load: " .. tostring(library)
    end

    if type(library) ~= "table" then
        return nil, "Rayfield module returned an invalid value."
    end

    return library, nil
end

local Rayfield, rayfieldError = resolveRayfieldLibrary()

if not Rayfield then
    error(rayfieldError)
end

local uiOk, uiResult = pcall(function()
    return UI:Initialize(Rayfield)
end)

if not uiOk then
    error("UI initialization failed: " .. tostring(uiResult))
end

if uiResult ~= true then
    error("UI initialization returned a non-success result.")
end

local started, startError = Framework:Start()

if not started then
    error("Framework failed to start: " .. tostring(startError))
end

local lazyOk, lazyError = LazyTabs:NotifySelected("Main Farm")

if lazyOk == false then
    error("Main Farm tab failed to initialize: " .. tostring(lazyError))
end

return Framework
