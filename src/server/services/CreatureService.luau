-- Owns creature identity checks and transient reservations for future gameplay.

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")

local CreatureService = {}
CreatureService.__index = CreatureService

local function cloneCreature(creature: any): any
    local copy = { id = creature.id, speciesId = creature.speciesId }
    if creature.mutationFormId ~= nil then
        copy.mutationFormId = creature.mutationFormId
    end
    return copy
end

function CreatureService.new(options: any?)
    options = options or {}
    return setmetatable({
        _playerDataService = options.playerDataService,
        _baseService = options.baseService,
        _reservations = {},
        _mutationLocks = {},
    }, CreatureService)
end

function CreatureService.isProtectedFromTheft(_self: any, profile: any, creatureId: string): boolean
    if type(profile) ~= "table" or type(creatureId) ~= "string" then
        return false
    end
    return profile.starterCreatureId == creatureId
        or (profile.welcomeCreatureId == creatureId and profile.hasCompletedFirstRaid == false)
end

function CreatureService.syncPlayer(self: any, userId: number): (boolean, string?)
    if self._baseService == nil then
        return true, nil
    end
    if self._playerDataService == nil then
        return false, "Unavailable"
    end
    local profile = self._playerDataService:getSnapshot(userId)
    if profile == nil then
        return false, "ProfileNotLoaded"
    end
    local synced = self._baseService:setCollection(userId, profile.creatures, profile.slotCapacity)
    if not synced then
        return false, "BaseCollectionUnavailable"
    end
    return true, nil
end

function CreatureService.findInProfile(
    _self: any,
    profile: any,
    creatureId: string
): (any?, number?)
    if type(profile) ~= "table" or type(profile.creatures) ~= "table" then
        return nil, nil
    end
    for index, creature in profile.creatures do
        if creature.id == creatureId then
            return creature, index
        end
    end
    return nil, nil
end

function CreatureService.addToProfile(_self: any, profile: any, creature: any): (any?, string?)
    if
        type(profile) ~= "table"
        or type(creature) ~= "table"
        or type(creature.id) ~= "string"
        or #creature.id == 0
        or not CreatureDefinitions.isSpeciesId(creature.speciesId)
    then
        return nil, "InvalidCreature"
    end
    if #profile.creatures >= profile.slotCapacity then
        return nil, "CapacityFull"
    end
    if CreatureService.findInProfile(nil, profile, creature.id) ~= nil then
        return nil, "Conflict"
    end
    local owned = cloneCreature(creature)
    table.insert(profile.creatures, owned)
    profile.discoveredSpeciesIds[owned.speciesId] = true
    if owned.mutationFormId ~= nil then
        profile.discoveredMutationFormIds[owned.mutationFormId] = true
    end
    return cloneCreature(owned), nil
end

function CreatureService.isRestricted(self: any, userId: number, creatureId: string): boolean
    return (self._reservations[userId] ~= nil and self._reservations[userId][creatureId] ~= nil)
        or (self._mutationLocks[userId] ~= nil and self._mutationLocks[userId][creatureId] == true)
end

function CreatureService.removeFromProfile(
    self: any,
    userId: number,
    profile: any,
    creatureId: string
): (any?, string?)
    if type(creatureId) ~= "string" or #creatureId == 0 then
        return nil, "InvalidCreatureId"
    end
    if creatureId == profile.starterCreatureId then
        return nil, "StarterProtected"
    end
    if self:isRestricted(userId, creatureId) then
        return nil, "Locked"
    end
    local creature, index = CreatureService.findInProfile(self, profile, creatureId)
    if creature == nil or index == nil then
        return nil, "NotOwner"
    end
    table.remove(profile.creatures, index)
    return cloneCreature(creature), nil
end

function CreatureService.reserve(
    self: any,
    userId: number,
    creatureId: string,
    attemptId: string
): boolean
    if type(attemptId) ~= "string" or #attemptId == 0 then
        return false
    end
    local creatures = if self._playerDataService ~= nil
        then self._playerDataService:getCreatures(userId)
        else nil
    local found = false
    if creatures ~= nil then
        for _, creature in creatures do
            if creature.id == creatureId then
                found = true
                break
            end
        end
    end
    if not found or self:isRestricted(userId, creatureId) then
        return false
    end
    self._reservations[userId] = self._reservations[userId] or {}
    self._reservations[userId][creatureId] = attemptId
    return true
end

function CreatureService.releaseReservation(
    self: any,
    userId: number,
    creatureId: string,
    attemptId: string
): boolean
    local reservations = self._reservations[userId]
    if reservations == nil or reservations[creatureId] ~= attemptId then
        return false
    end
    reservations[creatureId] = nil
    if next(reservations) == nil then
        self._reservations[userId] = nil
    end
    return true
end

function CreatureService.setMutationLock(
    self: any,
    userId: number,
    creatureId: string,
    locked: boolean
): boolean
    if type(locked) ~= "boolean" then
        return false
    end
    self._mutationLocks[userId] = self._mutationLocks[userId] or {}
    if locked then
        if self:isRestricted(userId, creatureId) then
            return false
        end
        self._mutationLocks[userId][creatureId] = true
    else
        self._mutationLocks[userId][creatureId] = nil
        if next(self._mutationLocks[userId]) == nil then
            self._mutationLocks[userId] = nil
        end
    end
    return true
end

function CreatureService.cleanupUser(self: any, userId: number)
    self._reservations[userId] = nil
    self._mutationLocks[userId] = nil
end

return table.freeze(CreatureService)
