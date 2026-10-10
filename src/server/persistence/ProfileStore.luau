-- DataStore adapter with a metadata-backed per-player session lease.

local ProfileStore = {}
ProfileStore.__index = ProfileStore

local OWNER_KEY = "oddSessionOwner"
local TOKEN_KEY = "oddSessionToken"
local EXPIRES_KEY = "oddSessionExpiresAt"

local function cloneValue(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in value do
        copy[key] = cloneValue(child)
    end
    return copy
end

local function getMetadata(keyInfo: any): { [string]: any }
    if keyInfo == nil or type(keyInfo.GetMetadata) ~= "function" then
        return {}
    end
    local metadata = keyInfo:GetMetadata()
    if type(metadata) ~= "table" then
        return {}
    end
    return cloneValue(metadata)
end

local function getUserIds(keyInfo: any, userId: number): { number }
    if keyInfo ~= nil and type(keyInfo.GetUserIds) == "function" then
        local userIds = keyInfo:GetUserIds()
        if type(userIds) == "table" then
            return userIds
        end
    end
    return { userId }
end

local function defaultWait(seconds: number)
    task.wait(seconds)
end

function ProfileStore.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(
        options.store ~= nil and type(options.store.UpdateAsync) == "function",
        "DataStore is required"
    )
    assert(type(options.validate) == "function", "profile validator is required")
    assert(type(options.clock) == "function", "clock is required")
    assert(type(options.generateToken) == "function", "token generator is required")
    local lockTtl = options.lockTtlSeconds or 300
    local maxAttempts = options.maxAttempts or 3
    assert(
        type(lockTtl) == "number" and lockTtl > 0 and lockTtl % 1 == 0,
        "lock TTL must be a positive integer"
    )
    assert(
        type(maxAttempts) == "number" and maxAttempts > 0 and maxAttempts % 1 == 0,
        "maxAttempts must be a positive integer"
    )

    return setmetatable({
        _store = options.store,
        _validate = options.validate,
        _clock = options.clock,
        _generateToken = options.generateToken,
        _wait = options.wait or defaultWait,
        _serverId = options.serverId or "server",
        _lockTtl = lockTtl,
        _maxAttempts = maxAttempts,
        _sessions = {},
    }, ProfileStore)
end

function ProfileStore._updateWithRetry(self: any, update: () -> (any, any)): (boolean, any, any)
    local lastError = "DataStoreUnavailable"
    for attempt = 1, self._maxAttempts do
        local ok, value, keyInfo = pcall(update)
        if ok then
            return true, value, keyInfo
        end
        lastError = tostring(value)
        if attempt < self._maxAttempts then
            self._wait(math.min(2 ^ (attempt - 1), 4))
        end
    end
    return false, lastError, nil
end

function ProfileStore._keyForUserId(_self: any, userId: number): string
    return "Player_" .. tostring(userId)
end

function ProfileStore.load(self: any, userId: number, defaultProfile: any): (any?, string?)
    if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
        return nil, "InvalidUserId"
    end
    if self._sessions[userId] ~= nil then
        return nil, "AlreadyLoaded"
    end
    local isValidDefault = self._validate(defaultProfile)
    if isValidDefault ~= true then
        return nil, "InvalidDefaultProfile"
    end

    local token = self._generateToken()
    if type(token) ~= "string" or #token < 8 or #token > 128 then
        return nil, "InvalidSessionToken"
    end

    local result = { acquired = false, reason = nil }
    local function update()
        result.acquired = false
        result.reason = nil
        local value, keyInfo = self._store:UpdateAsync(
            self:_keyForUserId(userId),
            function(current, currentInfo)
                local metadata = getMetadata(currentInfo)
                local lockToken = metadata[TOKEN_KEY]
                local lockExpiry = metadata[EXPIRES_KEY]
                if lockToken ~= nil and (type(lockToken) ~= "string" or lockToken == "") then
                    result.reason = "InvalidSessionLock"
                    return nil
                elseif type(lockToken) == "string" and lockToken ~= token then
                    if
                        type(lockExpiry) ~= "number"
                        or lockExpiry ~= lockExpiry
                        or lockExpiry == math.huge
                        or lockExpiry == -math.huge
                    then
                        result.reason = "InvalidSessionLock"
                        return nil
                    elseif lockExpiry > self._clock() then
                        result.reason = "SessionLocked"
                        return nil
                    end
                end

                local candidate = if current == nil then cloneValue(defaultProfile) else current
                if type(candidate) ~= "table" then
                    result.reason = "CorruptProfile"
                    return nil
                end
                local valid, validationError = self._validate(candidate)
                if valid ~= true then
                    result.reason = validationError or "CorruptProfile"
                    return nil
                end

                metadata[OWNER_KEY] = self._serverId
                metadata[TOKEN_KEY] = token
                metadata[EXPIRES_KEY] = self._clock() + self._lockTtl
                result.acquired = true
                return cloneValue(candidate), getUserIds(currentInfo, userId), metadata
            end
        )
        return value, keyInfo
    end

    local ok, value = self:_updateWithRetry(update)
    if not ok then
        return nil, "DataStoreUnavailable: " .. tostring(value)
    end
    if not result.acquired or type(value) ~= "table" then
        return nil, result.reason or "LoadCancelled"
    end

    self._sessions[userId] = token
    return cloneValue(value), nil
end

function ProfileStore.save(
    self: any,
    userId: number,
    profile: any,
    release: boolean?
): (boolean, string?)
    local token = self._sessions[userId]
    if token == nil then
        return false, "SessionNotLoaded"
    end
    local valid, validationError = self._validate(profile)
    if valid ~= true then
        return false, validationError or "InvalidProfile"
    end

    local result = { saved = false, reason = nil }
    local function update()
        result.saved = false
        result.reason = nil
        local value, keyInfo = self._store:UpdateAsync(
            self:_keyForUserId(userId),
            function(current, currentInfo)
                local metadata = getMetadata(currentInfo)
                if current == nil or metadata[TOKEN_KEY] ~= token then
                    result.reason = "SessionLost"
                    return nil
                end
                local currentValid, currentError = self._validate(current)
                if currentValid ~= true then
                    result.reason = currentError or "CorruptProfile"
                    return nil
                end

                if release == true then
                    metadata[OWNER_KEY] = nil
                    metadata[TOKEN_KEY] = nil
                    metadata[EXPIRES_KEY] = nil
                else
                    metadata[OWNER_KEY] = self._serverId
                    metadata[EXPIRES_KEY] = self._clock() + self._lockTtl
                end
                result.saved = true
                return cloneValue(profile), getUserIds(currentInfo, userId), metadata
            end
        )
        return value, keyInfo
    end

    local ok, value = self:_updateWithRetry(update)
    if not ok then
        return false, "DataStoreUnavailable: " .. tostring(value)
    end
    if not result.saved or type(value) ~= "table" then
        return false, result.reason or "SaveCancelled"
    end
    if release == true then
        self._sessions[userId] = nil
    end
    return true, nil
end

function ProfileStore.release(self: any, userId: number): (boolean, string?)
    local token = self._sessions[userId]
    if token == nil then
        return true, nil
    end

    local result = { released = false, reason = nil }
    local function update()
        result.released = false
        result.reason = nil
        local value, keyInfo = self._store:UpdateAsync(
            self:_keyForUserId(userId),
            function(current, currentInfo)
                local metadata = getMetadata(currentInfo)
                if current == nil or metadata[TOKEN_KEY] ~= token then
                    result.reason = "SessionLost"
                    return nil
                end
                metadata[OWNER_KEY] = nil
                metadata[TOKEN_KEY] = nil
                metadata[EXPIRES_KEY] = nil
                result.released = true
                return current, getUserIds(currentInfo, userId), metadata
            end
        )
        return value, keyInfo
    end

    local ok, value = self:_updateWithRetry(update)
    if not ok then
        return false, "DataStoreUnavailable: " .. tostring(value)
    end
    if not result.released or value == nil then
        return false, result.reason or "ReleaseCancelled"
    end
    self._sessions[userId] = nil
    return true, nil
end

function ProfileStore.getLoadedCount(self: any): number
    local count = 0
    for _ in self._sessions do
        count += 1
    end
    return count
end

return table.freeze(ProfileStore)
