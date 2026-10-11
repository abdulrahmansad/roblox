--!strict

local StudioMemoryDataStoreService = {}
StudioMemoryDataStoreService.__index = StudioMemoryDataStoreService

type StoredRecord = {
    value: any,
    userIds: { number },
    metadata: { [string]: any },
}

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

local function makeKeyInfo(record: StoredRecord?): any
    if record == nil then
        return nil
    end

    return {
        GetMetadata = function()
            return cloneValue(record.metadata)
        end,
        GetUserIds = function()
            return cloneValue(record.userIds)
        end,
    }
end

local function makeDataStore(): any
    local records: { [string]: StoredRecord } = {}
    local store = {}

    function store:GetAsync(key: string): any
        local record = records[key]
        return if record ~= nil then cloneValue(record.value) else nil
    end

    function store:UpdateAsync(key: string, transform: any): (any, any)
        assert(type(key) == "string" and key ~= "", "DataStore key must be a non-empty string")
        assert(type(transform) == "function", "UpdateAsync transform is required")

        local existing = records[key]
        local newValue, userIds, metadata = transform(
            if existing ~= nil then cloneValue(existing.value) else nil,
            makeKeyInfo(existing)
        )
        if newValue == nil then
            return nil, makeKeyInfo(existing)
        end

        local updated: StoredRecord = {
            value = cloneValue(newValue),
            userIds = cloneValue(userIds or if existing ~= nil then existing.userIds else {}),
            metadata = cloneValue(metadata or if existing ~= nil then existing.metadata else {}),
        }
        records[key] = updated
        return cloneValue(updated.value), makeKeyInfo(updated)
    end

    return store
end

function StudioMemoryDataStoreService.new()
    return setmetatable({ _stores = {} }, StudioMemoryDataStoreService)
end

function StudioMemoryDataStoreService.isUnpublishedStudioSession(
    isStudio: boolean,
    placeId: number,
    gameId: number
): boolean
    return isStudio and placeId == 0 and gameId == 0
end

function StudioMemoryDataStoreService:GetDataStore(name: string): any
    assert(type(name) == "string" and name ~= "", "DataStore name must be a non-empty string")

    local store = self._stores[name]
    if store == nil then
        store = makeDataStore()
        self._stores[name] = store
    end
    return store
end

return StudioMemoryDataStoreService
