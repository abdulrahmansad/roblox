-- Durable write-ahead journal for cross-profile creature ownership transfers.

local TransferJournalStore = {}
TransferJournalStore.__index = TransferJournalStore

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")
local MutationDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.MutationDefinitions)
    else require("../../shared/definitions/MutationDefinitions")

local JOURNAL_KEY = "OddlingsTransfersV1"
local MAX_RECORDS = 64
local DEFAULT_MAX_ATTEMPTS = 3
local MAX_SAFE_USER_ID = 9_007_199_254_740_991
local THEMES = { Ember = true, Prism = true, Moss = true }

local function defaultWait(seconds: number)
    task.wait(seconds)
end

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

local function isUserId(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value % 1 == 0
        and value >= 1
        and value <= MAX_SAFE_USER_ID
end

local function hasExactKeys(value: any, allowed: { [string]: boolean }): boolean
    if type(value) ~= "table" then
        return false
    end
    for key in value do
        if type(key) ~= "string" or allowed[key] ~= true then
            return false
        end
    end
    return true
end

local function validCreature(creature: any): boolean
    if
        type(creature) ~= "table"
        or type(creature.id) ~= "string"
        or #creature.id < 1
        or #creature.id > 128
        or not CreatureDefinitions.isSpeciesId(creature.speciesId)
    then
        return false
    end
    for key, value in creature do
        if key ~= "id" and key ~= "speciesId" and key ~= "mutationFormId" then
            return false
        end
        if key == "mutationFormId" and not MutationDefinitions.isFormId(value) then
            return false
        end
    end
    return true
end

local function validRecord(record: any): boolean
    if
        type(record) ~= "table"
        or not hasExactKeys(record, {
            transferId = true,
            state = true,
            fromUserId = true,
            toUserId = true,
            raidId = true,
            creature = true,
            catalystThemeId = true,
            createdAtUnix = true,
            fromApplied = true,
            toApplied = true,
        })
        or type(record.transferId) ~= "string"
        or #record.transferId < 1
        or #record.transferId > 128
        or (record.state ~= "PREPARED" and record.state ~= "COMMITTED")
        or not isUserId(record.fromUserId)
        or not isUserId(record.toUserId)
        or record.fromUserId == record.toUserId
        or type(record.raidId) ~= "string"
        or #record.raidId < 1
        or #record.raidId > 128
        or not validCreature(record.creature)
        or not THEMES[record.catalystThemeId]
        or type(record.createdAtUnix) ~= "number"
        or record.createdAtUnix ~= record.createdAtUnix
        or record.createdAtUnix == math.huge
        or record.createdAtUnix == -math.huge
        or record.createdAtUnix % 1 ~= 0
        or record.createdAtUnix < 0
        or record.createdAtUnix > 4_102_444_800
        or type(record.fromApplied) ~= "boolean"
        or type(record.toApplied) ~= "boolean"
    then
        return false
    end
    return true
end

local function validIndex(index: any): boolean
    if
        not hasExactKeys(index, { version = true, records = true })
        or index.version ~= 1
        or type(index.records) ~= "table"
    then
        return false
    end
    local count = 0
    for key, record in index.records do
        if
            type(key) ~= "string"
            or type(record) ~= "table"
            or key ~= record.transferId
            or not validRecord(record)
        then
            return false
        end
        count += 1
        if count > MAX_RECORDS then
            return false
        end
    end
    return true
end

local function sameTransfer(left: any, right: any): boolean
    if
        left.transferId ~= right.transferId
        or left.fromUserId ~= right.fromUserId
        or left.toUserId ~= right.toUserId
        or left.raidId ~= right.raidId
        or left.catalystThemeId ~= right.catalystThemeId
        or left.creature.id ~= right.creature.id
        or left.creature.speciesId ~= right.creature.speciesId
        or left.creature.mutationFormId ~= right.creature.mutationFormId
    then
        return false
    end
    return true
end

function TransferJournalStore.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.store) == "table", "store is required")
    assert(type(options.store.UpdateAsync) == "function", "store.UpdateAsync is required")
    assert(type(options.store.GetAsync) == "function", "store.GetAsync is required")
    local maxAttempts = options.maxAttempts or DEFAULT_MAX_ATTEMPTS
    assert(
        type(maxAttempts) == "number" and maxAttempts > 0 and maxAttempts % 1 == 0,
        "maxAttempts must be a positive integer"
    )
    return setmetatable({
        _store = options.store,
        _maxAttempts = maxAttempts,
        _wait = options.wait or defaultWait,
    }, TransferJournalStore)
end

function TransferJournalStore._updateWithRetry(self: any, update: () -> any): (boolean, any)
    local lastError = "DataStoreUnavailable"
    for attempt = 1, self._maxAttempts do
        local ok, value = pcall(update)
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

function TransferJournalStore._getWithRetry(self: any, key: string): (boolean, any)
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

function TransferJournalStore.prepare(self: any, record: any): (boolean, string?)
    if type(record) ~= "table" then
        return false, "InvalidTransferRecord"
    end
    local prepared = cloneValue(record)
    prepared.state = "PREPARED"
    prepared.fromApplied = false
    prepared.toApplied = false
    if not validRecord(prepared) then
        return false, "InvalidTransferRecord"
    end

    local updateOk, updated = self:_updateWithRetry(function()
        return self._store:UpdateAsync(JOURNAL_KEY, function(existing)
            local index = if existing == nil then { version = 1, records = {} } else existing
            if not validIndex(index) then
                return nil
            end
            local current = index.records[prepared.transferId]
            if current ~= nil then
                return if sameTransfer(current, prepared) then index else nil
            end
            local count = 0
            for _ in index.records do
                count += 1
            end
            if count >= MAX_RECORDS then
                return nil
            end
            index.records[prepared.transferId] = prepared
            return index
        end)
    end)
    if not updateOk then
        return false, tostring(updated)
    end
    if not validIndex(updated) or updated.records[prepared.transferId] == nil then
        return false, "TransferJournalUnavailable"
    end
    if not sameTransfer(updated.records[prepared.transferId], prepared) then
        return false, "TransferJournalConflict"
    end
    return true, nil
end

function TransferJournalStore.commit(self: any, transferId: string): (boolean, string?)
    if type(transferId) ~= "string" or #transferId < 1 or #transferId > 128 then
        return false, "InvalidTransferId"
    end
    local updateOk, updated = self:_updateWithRetry(function()
        return self._store:UpdateAsync(JOURNAL_KEY, function(existing)
            if not validIndex(existing) then
                return nil
            end
            local record = existing.records[transferId]
            if record == nil then
                return nil
            end
            record.state = "COMMITTED"
            return existing
        end)
    end)
    if not updateOk then
        return false, tostring(updated)
    end
    if not validIndex(updated) or updated.records[transferId] == nil then
        return false, "TransferJournalUnavailable"
    end
    if updated.records[transferId].state ~= "COMMITTED" then
        return false, "TransferJournalUnavailable"
    end
    return true, nil
end

function TransferJournalStore.abort(self: any, transferId: string): (boolean, string?)
    if type(transferId) ~= "string" or #transferId < 1 or #transferId > 128 then
        return false, "InvalidTransferId"
    end
    local updateOk, updated = self:_updateWithRetry(function()
        return self._store:UpdateAsync(JOURNAL_KEY, function(existing)
            if existing == nil then
                return { version = 1, records = {} }
            end
            if not validIndex(existing) then
                return nil
            end
            local record = existing.records[transferId]
            if record == nil then
                return existing
            end
            if record.state ~= "PREPARED" then
                return nil
            end
            existing.records[transferId] = nil
            return existing
        end)
    end)
    if not updateOk then
        return false, tostring(updated)
    end
    if not validIndex(updated) then
        return false, "TransferJournalUnavailable"
    end
    if updated.records[transferId] ~= nil then
        return false, "TransferAlreadyCommitted"
    end
    return true, nil
end

function TransferJournalStore.getForUser(self: any, userId: number): ({ any }?, string?)
    if not isUserId(userId) then
        return nil, "InvalidUserId"
    end
    local readOk, index = self:_getWithRetry(JOURNAL_KEY)
    if not readOk then
        return nil, tostring(index)
    end
    if index == nil then
        return {}, nil
    end
    if not validIndex(index) then
        return nil, "InvalidTransferJournal"
    end
    local records = {}
    for _, record in index.records do
        if record.fromUserId == userId or record.toUserId == userId then
            table.insert(records, cloneValue(record))
        end
    end
    return records, nil
end

function TransferJournalStore.markApplied(
    self: any,
    transferId: string,
    userId: number
): (boolean, string?)
    if
        type(transferId) ~= "string"
        or #transferId < 1
        or #transferId > 128
        or not isUserId(userId)
    then
        return false, "InvalidTransferReceipt"
    end
    local updateOk, updated = self:_updateWithRetry(function()
        return self._store:UpdateAsync(JOURNAL_KEY, function(existing)
            if not validIndex(existing) then
                return nil
            end
            local record = existing.records[transferId]
            if record == nil then
                return existing
            end
            if record.fromUserId == userId then
                record.fromApplied = true
            elseif record.toUserId == userId then
                record.toApplied = true
            else
                return nil
            end
            if record.fromApplied and record.toApplied then
                existing.records[transferId] = nil
            end
            return existing
        end)
    end)
    if not updateOk then
        return false, tostring(updated)
    end
    if not validIndex(updated) then
        return false, "TransferJournalUnavailable"
    end
    return true, nil
end

return table.freeze(TransferJournalStore)
