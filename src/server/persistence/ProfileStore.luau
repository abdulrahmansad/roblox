-- DataStore adapter with a metadata-backed per-player session lease.

local ProfileStore = {}
ProfileStore.__index = ProfileStore

local OWNER_KEY = "oddSessionOwner"
local TOKEN_KEY = "oddSessionToken"
local EXPIRES_KEY = "oddSessionExpiresAt"
local SAVE_REVISION_KEY = "oddSaveRevision"
local BACKUP_PREFIX = "Backup_Player_"
local QUARANTINE_PREFIX = "Quarantine_"
local MAX_SAFE_USER_ID = 9_007_199_254_740_991

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

local function sameValue(left: any, right: any): boolean
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end
    for key, value in left do
        if not sameValue(value, right[key]) then
            return false
        end
    end
    for key in right do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function validInteger(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value % 1 == 0
        and value >= 0
        and value <= 2_147_483_647
end

local function isValidUserId(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value % 1 == 0
        and value >= 1
        and value <= MAX_SAFE_USER_ID
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
        options.store ~= nil
            and type(options.store.UpdateAsync) == "function"
            and type(options.store.GetAsync) == "function",
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
        _saveRevisions = {},
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

function ProfileStore._backupKeyForUserId(_self: any, userId: number): string
    return BACKUP_PREFIX .. tostring(userId)
end

function ProfileStore._quarantineKeyForUserId(_self: any, userId: number, token: string): string
    local safeToken = string.gsub(token, "[^%w_-]", "")
    return QUARANTINE_PREFIX .. tostring(userId) .. "_" .. string.sub(safeToken, 1, 20)
end

function ProfileStore._getWithRetry(self: any, key: string): (boolean, any)
    local lastError = "DataStoreUnavailable"
    for attempt = 1, self._maxAttempts do
        local ok, value = pcall(self._store.GetAsync, self._store, key)
        if ok then
            return true, value
        end
        lastError = tostring(value)
        if attempt < self._maxAttempts then
            self._wait(math.min(2 ^ (attempt - 1), 4))
        end
    end
    return false, lastError
end

function ProfileStore._readBackup(self: any, userId: number): (any?, string?)
    local ok, value = self:_getWithRetry(self:_backupKeyForUserId(userId))
    if not ok then
        return nil, "BackupUnavailable: " .. tostring(value)
    end
    if value == nil then
        return nil, "BackupMissing"
    end
    if
        type(value) ~= "table"
        or value.version ~= 1
        or not validInteger(value.saveRevision)
        or type(value.profile) ~= "table"
    then
        return nil, "InvalidProfileBackup"
    end
    for key in value do
        if key ~= "version" and key ~= "saveRevision" and key ~= "profile" then
            return nil, "InvalidProfileBackup"
        end
    end
    local valid, validationError = self._validate(value.profile)
    if valid ~= true then
        return nil, validationError or "InvalidProfileBackup"
    end
    return value, nil
end

function ProfileStore._writeBackup(
    self: any,
    userId: number,
    profile: any,
    saveRevision: number
): (boolean, string?)
    local envelope = {
        version = 1,
        saveRevision = saveRevision,
        profile = cloneValue(profile),
    }
    local valid, validationError = self._validate(envelope.profile)
    if not valid then
        return false, validationError or "InvalidProfileBackup"
    end
    local result = { saved = false, reason = nil }
    local ok, value = self:_updateWithRetry(function()
        result.saved = false
        result.reason = nil
        return self._store:UpdateAsync(self:_backupKeyForUserId(userId), function(current)
            if current ~= nil then
                local currentBackup = current
                if
                    type(currentBackup) == "table"
                    and currentBackup.version == 1
                    and validInteger(currentBackup.saveRevision)
                    and type(currentBackup.profile) == "table"
                then
                    local exactBackupKeys = true
                    for key in currentBackup do
                        if key ~= "version" and key ~= "saveRevision" and key ~= "profile" then
                            exactBackupKeys = false
                            break
                        end
                    end
                    local currentValid = self._validate(currentBackup.profile)
                    if exactBackupKeys and currentValid == true then
                        if currentBackup.saveRevision > saveRevision then
                            result.saved = true
                            return currentBackup, { userId }, {}
                        elseif currentBackup.saveRevision == saveRevision then
                            if sameValue(currentBackup.profile, envelope.profile) then
                                result.saved = true
                                return currentBackup, { userId }, {}
                            end
                            result.reason = "ProfileBackupConflict"
                            return nil
                        end
                    end
                end
            end
            result.saved = true
            return envelope, { userId }, {}
        end)
    end)
    if not ok then
        return false, "DataStoreUnavailable: " .. tostring(value)
    end
    if not result.saved or type(value) ~= "table" then
        return false, result.reason or "ProfileBackupUnavailable"
    end
    local currentBackup = value
    if
        currentBackup.version ~= 1
        or not validInteger(currentBackup.saveRevision)
        or type(currentBackup.profile) ~= "table"
        or currentBackup.saveRevision < saveRevision
    then
        return false, "ProfileBackupUnavailable"
    end
    local backupValid = self._validate(currentBackup.profile)
    if backupValid ~= true then
        return false, "InvalidProfileBackup"
    end
    return true, nil
end

function ProfileStore._quarantineCorrupt(
    self: any,
    userId: number,
    token: string,
    value: any,
    metadata: any,
    userIds: any,
    reason: string
): (boolean, string?)
    local record = {
        version = 1,
        reason = reason,
        quarantinedAtUnix = self._clock(),
        value = cloneValue(value),
        metadata = cloneValue(metadata),
        userIds = cloneValue(userIds),
    }
    local result = { saved = false }
    local ok, stored = self:_updateWithRetry(function()
        result.saved = false
        return self._store:UpdateAsync(
            self:_quarantineKeyForUserId(userId, token),
            function(existing)
                if existing ~= nil and not sameValue(existing, record) then
                    return nil
                end
                result.saved = true
                return record, { userId }, {}
            end
        )
    end)
    if not ok then
        return false, "DataStoreUnavailable: " .. tostring(stored)
    end
    if not result.saved or not sameValue(stored, record) then
        return false, "QuarantineUnavailable"
    end
    return true, nil
end

function ProfileStore._restoreBackup(
    self: any,
    userId: number,
    token: string,
    observedValue: any,
    observedUserIds: any,
    backup: any
): (any?, string?)
    local result = { acquired = false, reason = nil }
    local function update()
        result.acquired = false
        result.reason = nil
        local value = self._store:UpdateAsync(
            self:_keyForUserId(userId),
            function(current, currentInfo)
                if not sameValue(current, observedValue) then
                    result.reason = "ProfileChangedDuringRecovery"
                    return nil
                end
                local metadata = getMetadata(currentInfo)
                local lockToken = metadata[TOKEN_KEY]
                local lockExpiry = metadata[EXPIRES_KEY]
                if lockToken ~= nil and (type(lockToken) ~= "string" or lockToken == "") then
                    result.reason = "InvalidSessionLock"
                    return nil
                elseif type(lockToken) == "string" and lockToken ~= token then
                    if not validInteger(lockExpiry) then
                        result.reason = "InvalidSessionLock"
                        return nil
                    elseif lockExpiry > self._clock() then
                        result.reason = "SessionLocked"
                        return nil
                    end
                end
                local revision = metadata[SAVE_REVISION_KEY]
                if not validInteger(revision) or revision ~= backup.saveRevision then
                    result.reason = "ProfileRevisionChangedDuringRecovery"
                    return nil
                end
                metadata[OWNER_KEY] = self._serverId
                metadata[TOKEN_KEY] = token
                metadata[EXPIRES_KEY] = self._clock() + self._lockTtl
                metadata[SAVE_REVISION_KEY] = revision
                result.acquired = true
                return cloneValue(backup.profile), observedUserIds, metadata
            end
        )
        return value
    end

    local ok, value = self:_updateWithRetry(update)
    if not ok then
        return nil, "DataStoreUnavailable: " .. tostring(value)
    end
    if not result.acquired or type(value) ~= "table" then
        return nil, result.reason or "ProfileRecoveryCancelled"
    end
    return cloneValue(value), nil
end

function ProfileStore.load(self: any, userId: number, defaultProfile: any): (any?, string?)
    if not isValidUserId(userId) then
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
    if
        type(token) ~= "string"
        or #token < 8
        or #token > 128
        or string.find(token, "[^%w_-]") ~= nil
    then
        return nil, "InvalidSessionToken"
    end

    local result = { acquired = false, reason = nil, observedValue = nil }
    local function update()
        result.acquired = false
        result.reason = nil
        result.observedValue = nil
        result.observedMetadata = nil
        result.observedUserIds = nil
        result.saveRevision = nil
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
                    result.observedValue = cloneValue(current)
                    result.observedMetadata = metadata
                    result.observedUserIds = getUserIds(currentInfo, userId)
                    return nil
                end
                local valid, validationError = self._validate(candidate)
                if valid ~= true then
                    result.reason = validationError or "CorruptProfile"
                    if result.reason ~= "UnknownSchemaVersion" then
                        result.observedValue = cloneValue(current)
                        result.observedMetadata = metadata
                        result.observedUserIds = getUserIds(currentInfo, userId)
                    end
                    return nil
                end

                local saveRevision = metadata[SAVE_REVISION_KEY]
                if saveRevision ~= nil and not validInteger(saveRevision) then
                    result.reason = "InvalidSaveRevision"
                    return nil
                end

                metadata[OWNER_KEY] = self._serverId
                metadata[TOKEN_KEY] = token
                metadata[EXPIRES_KEY] = self._clock() + self._lockTtl
                result.acquired = true
                result.saveRevision = saveRevision or 0
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
        local reason = result.reason or "LoadCancelled"
        if result.observedValue == nil then
            return nil, reason
        end
        local backup, backupError = self:_readBackup(userId)
        local quarantineOk, quarantineError = self:_quarantineCorrupt(
            userId,
            token,
            result.observedValue,
            result.observedMetadata or {},
            result.observedUserIds or { userId },
            reason
        )
        if not quarantineOk then
            return nil, "CorruptProfileQuarantineFailed: " .. tostring(quarantineError)
        end
        if backup == nil then
            return nil, "CorruptProfileQuarantined: " .. tostring(backupError)
        end
        local observedRevision = (result.observedMetadata or {})[SAVE_REVISION_KEY]
        if not validInteger(observedRevision) or backup.saveRevision ~= observedRevision then
            return nil, "CorruptProfileQuarantined: StaleProfileBackup"
        end
        local recovered, recoveryError = self:_restoreBackup(
            userId,
            token,
            result.observedValue,
            result.observedUserIds or { userId },
            backup
        )
        if recovered == nil then
            return nil, "CorruptProfileRecoveryFailed: " .. tostring(recoveryError)
        end
        self._sessions[userId] = token
        self._saveRevisions[userId] = backup.saveRevision
        return cloneValue(recovered), nil
    end

    self._sessions[userId] = token
    self._saveRevisions[userId] = result.saveRevision or 0
    return cloneValue(value), nil
end

function ProfileStore.save(
    self: any,
    userId: number,
    profile: any,
    release: boolean?
): (boolean, string?)
    if not isValidUserId(userId) then
        return false, "InvalidUserId"
    end
    local token = self._sessions[userId]
    if token == nil then
        return false, "SessionNotLoaded"
    end
    local valid, validationError = self._validate(profile)
    if valid ~= true then
        return false, validationError or "InvalidProfile"
    end

    local result = { saved = false, reason = nil, saveRevision = nil }
    local function update()
        result.saved = false
        result.reason = nil
        result.saveRevision = nil
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

                local currentRevision = metadata[SAVE_REVISION_KEY]
                if currentRevision == nil then
                    currentRevision = self._saveRevisions[userId] or 0
                elseif not validInteger(currentRevision) then
                    result.reason = "InvalidSaveRevision"
                    return nil
                end
                if currentRevision >= 2_147_483_647 then
                    result.reason = "SaveRevisionExhausted"
                    return nil
                end
                local nextRevision = currentRevision + 1

                if release == true then
                    metadata[OWNER_KEY] = nil
                    metadata[TOKEN_KEY] = nil
                    metadata[EXPIRES_KEY] = nil
                else
                    metadata[OWNER_KEY] = self._serverId
                    metadata[EXPIRES_KEY] = self._clock() + self._lockTtl
                end
                metadata[SAVE_REVISION_KEY] = nextRevision
                result.saved = true
                result.saveRevision = nextRevision
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

    self._saveRevisions[userId] = result.saveRevision
    local backupSaved, backupError = self:_writeBackup(userId, profile, result.saveRevision)
    if not backupSaved then
        warn(string.format("[ProfileStore] Backup checkpoint failed: %s", tostring(backupError)))
    end
    if release == true then
        self._sessions[userId] = nil
        self._saveRevisions[userId] = nil
    end
    return true, nil
end

function ProfileStore.release(self: any, userId: number): (boolean, string?)
    if not isValidUserId(userId) then
        return false, "InvalidUserId"
    end
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
    self._saveRevisions[userId] = nil
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
