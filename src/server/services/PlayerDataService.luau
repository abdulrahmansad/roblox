-- Owns validated in-memory player profiles and narrow server mutations.

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")
local MutationDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.MutationDefinitions)
    else require("../../shared/definitions/MutationDefinitions")
local EconomyConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.EconomyConfig)
    else require("../../shared/config/EconomyConfig")
local MutationConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.MutationConfig)
    else require("../../shared/config/MutationConfig")

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

local PROFILE_FIELDS = {
    schemaVersion = true,
    scrap = true,
    creatures = true,
    starterCreatureId = true,
    slotCapacity = true,
    catalysts = true,
    standardCapsulePity = true,
    mutationRareMissCount = true,
    discoveredSpeciesIds = true,
    discoveredMutationFormIds = true,
    tutorialCompleted = true,
    welcomeCreatureId = true,
    hasCompletedFirstRaid = true,
    firstRaidParticipation = true,
}
local CATALYST_IDS = { emberSeed = true, prismDust = true, mossSpore = true }

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

local function isIntegerBetween(value: any, minimum: number, maximum: number): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value % 1 == 0
        and value >= minimum
        and value <= maximum
end

local function validateExactKeys(value: any, allowed: { [string]: boolean }): boolean
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

local function validateSet(value: any, isAllowed: (any) -> boolean, maximum: number): boolean
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key, present in value do
        if type(key) ~= "string" or present ~= true or not isAllowed(key) then
            return false
        end
        count += 1
        if count > maximum then
            return false
        end
    end
    return true
end

local function validRaidId(value: any): boolean
    return type(value) == "string" and #value >= 1 and #value <= 128
end

function PlayerDataService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.profileStore) == "table", "profileStore is required")
    assert(type(options.profileStore.load) == "function", "profileStore.load is required")
    assert(type(options.profileStore.save) == "function", "profileStore.save is required")
    assert(type(options.clock) == "function", "clock is required")
    assert(type(options.generateCreatureId) == "function", "creature ID generator is required")

    return setmetatable({
        _profileStore = options.profileStore,
        _transferJournalStore = options.transferJournalStore,
        _clock = options.clock,
        _generateCreatureId = options.generateCreatureId,
        _wait = options.wait or function(seconds)
            task.wait(seconds)
        end,
        _schedule = options.schedule or function(callback)
            task.spawn(callback)
        end,
        _autoSaveEnabled = options.autoSaveEnabled == true,
        _autoSaveInterval = options.autoSaveIntervalSeconds
            or EconomyConfig.AUTOSAVE_INTERVAL_SECONDS,
        _random = options.random or math.random,
        _profiles = {},
        _dirty = {},
        _revision = {},
        _closing = {},
        _transacting = {},
        _saving = {},
        _transferLocks = {},
        _autoSaveTokens = {},
        _stopped = false,
    }, PlayerDataService)
end

function PlayerDataService.createDefaultProfile(generateCreatureId: () -> string): any
    assert(type(generateCreatureId) == "function", "creature ID generator is required")
    local starterId = generateCreatureId()
    return {
        schemaVersion = 1,
        scrap = EconomyConfig.STARTING_SCRAP,
        creatures = {
            { id = starterId, speciesId = EconomyConfig.STARTER_SPECIES_ID },
        },
        starterCreatureId = starterId,
        slotCapacity = EconomyConfig.STARTER_SLOT_CAPACITY,
        catalysts = { emberSeed = 0, prismDust = 0, mossSpore = 0 },
        standardCapsulePity = { belowUncommon = 0, belowRare = 0 },
        mutationRareMissCount = 0,
        discoveredSpeciesIds = { [EconomyConfig.STARTER_SPECIES_ID] = true },
        discoveredMutationFormIds = {},
        tutorialCompleted = false,
        hasCompletedFirstRaid = false,
    }
end

function PlayerDataService.validateProfile(profile: any): (boolean, string?)
    if type(profile) ~= "table" or not validateExactKeys(profile, PROFILE_FIELDS) then
        return false, "InvalidProfileShape"
    end
    if profile.schemaVersion ~= 1 then
        if type(profile.schemaVersion) == "number" and profile.schemaVersion > 1 then
            return false, "UnknownSchemaVersion"
        end
        return false, "InvalidSchemaVersion"
    end
    if not isIntegerBetween(profile.scrap, 0, EconomyConfig.MAX_SCRAP) then
        return false, "InvalidScrap"
    end
    if type(profile.creatures) ~= "table" or #profile.creatures > 4 then
        return false, "InvalidCreatures"
    end
    local seenCreatureIds = {}
    local creatureCount = 0
    for key, creature in profile.creatures do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #profile.creatures then
            return false, "InvalidCreatures"
        end
        creatureCount += 1
        if type(creature) ~= "table" then
            return false, "InvalidCreature"
        end
        local allowedCreatureFields = { id = true, speciesId = true, mutationFormId = true }
        if not validateExactKeys(creature, allowedCreatureFields) then
            return false, "InvalidCreature"
        end
        if type(creature.id) ~= "string" or #creature.id < 1 or #creature.id > 128 then
            return false, "InvalidCreatureId"
        end
        if seenCreatureIds[creature.id] then
            return false, "DuplicateCreatureId"
        end
        seenCreatureIds[creature.id] = true
        if not CreatureDefinitions.isSpeciesId(creature.speciesId) then
            return false, "InvalidSpeciesId"
        end
        if
            creature.mutationFormId ~= nil
            and not MutationDefinitions.isFormId(creature.mutationFormId)
        then
            return false, "InvalidMutationFormId"
        end
    end
    if creatureCount ~= #profile.creatures or creatureCount < 1 then
        return false, "InvalidCreatures"
    end
    if
        type(profile.starterCreatureId) ~= "string"
        or not seenCreatureIds[profile.starterCreatureId]
    then
        return false, "InvalidStarterCreatureId"
    end
    for _, creature in profile.creatures do
        if creature.id == profile.starterCreatureId and creature.speciesId ~= "Mossling" then
            return false, "InvalidStarterSpecies"
        end
    end
    if
        not isIntegerBetween(
            profile.slotCapacity,
            EconomyConfig.STARTER_SLOT_CAPACITY,
            EconomyConfig.MAX_SLOT_CAPACITY
        )
    then
        return false, "InvalidSlotCapacity"
    end
    if profile.slotCapacity < creatureCount then
        return false, "SlotCapacityBelowOwnedCount"
    end

    if not validateExactKeys(profile.catalysts, CATALYST_IDS) then
        return false, "InvalidCatalysts"
    end
    for catalystId in CATALYST_IDS do
        if not isIntegerBetween(profile.catalysts[catalystId], 0, 1_000_000) then
            return false, "InvalidCatalystCount"
        end
    end

    if
        not validateExactKeys(
            profile.standardCapsulePity,
            { belowUncommon = true, belowRare = true }
        )
    then
        return false, "InvalidCapsulePity"
    end
    if
        not isIntegerBetween(profile.standardCapsulePity.belowUncommon, 0, 3)
        or not isIntegerBetween(profile.standardCapsulePity.belowRare, 0, 8)
    then
        return false, "InvalidCapsulePity"
    end
    if not isIntegerBetween(profile.mutationRareMissCount, 0, 8) then
        return false, "InvalidMutationPity"
    end

    if not validateSet(profile.discoveredSpeciesIds, CreatureDefinitions.isSpeciesId, 12) then
        return false, "InvalidDiscoveredSpecies"
    end
    if profile.discoveredSpeciesIds.Mossling ~= true then
        return false, "StarterSpeciesNotDiscovered"
    end
    for _, creature in profile.creatures do
        if profile.discoveredSpeciesIds[creature.speciesId] ~= true then
            return false, "OwnedSpeciesNotDiscovered"
        end
    end
    if not validateSet(profile.discoveredMutationFormIds, MutationDefinitions.isFormId, 24) then
        return false, "InvalidDiscoveredMutationForms"
    end
    for _, creature in profile.creatures do
        if
            creature.mutationFormId ~= nil
            and profile.discoveredMutationFormIds[creature.mutationFormId] ~= true
        then
            return false, "EquippedMutationNotDiscovered"
        end
    end

    if type(profile.tutorialCompleted) ~= "boolean" then
        return false, "InvalidTutorialState"
    end
    if
        profile.welcomeCreatureId ~= nil
        and (
            type(profile.welcomeCreatureId) ~= "string"
            or #profile.welcomeCreatureId < 1
            or #profile.welcomeCreatureId > 128
        )
    then
        return false, "InvalidWelcomeCreatureId"
    end
    if type(profile.hasCompletedFirstRaid) ~= "boolean" then
        return false, "InvalidFirstRaidState"
    end
    if profile.firstRaidParticipation ~= nil then
        if
            not validateExactKeys(
                profile.firstRaidParticipation,
                { raidId = true, completesAtUnix = true }
            )
            or not validRaidId(profile.firstRaidParticipation.raidId)
            or not isIntegerBetween(
                profile.firstRaidParticipation.completesAtUnix,
                1,
                9_999_999_999
            )
            or profile.hasCompletedFirstRaid
        then
            return false, "InvalidFirstRaidParticipation"
        end
    end
    return true, nil
end

function PlayerDataService._normalizeFirstRaid(profile: any, nowUnix: number): boolean
    local marker = profile.firstRaidParticipation
    if marker ~= nil and marker.completesAtUnix <= nowUnix then
        profile.firstRaidParticipation = nil
        profile.hasCompletedFirstRaid = true
        return true
    end
    return false
end

local function reconcileTransferRecord(
    profile: any,
    userId: number,
    record: any
): (boolean, string?)
    if
        type(record) ~= "table"
        or (record.state ~= "PREPARED" and record.state ~= "COMMITTED")
        or not isIntegerBetween(record.fromUserId, 1, 2_147_483_647)
        or not isIntegerBetween(record.toUserId, 1, 2_147_483_647)
        or record.fromUserId == record.toUserId
        or type(record.transferId) ~= "string"
        or type(record.raidId) ~= "string"
        or type(record.creature) ~= "table"
        or type(record.creature.id) ~= "string"
        or not CreatureDefinitions.isSpeciesId(record.creature.speciesId)
        or (record.creature.mutationFormId ~= nil and not MutationDefinitions.isFormId(
            record.creature.mutationFormId
        ))
        or MutationConfig.CATALYSTS_BY_THEME[record.catalystThemeId] == nil
    then
        return false, "InvalidTransferJournalRecord"
    end

    local shouldOwn = (record.state == "PREPARED" and userId == record.fromUserId)
        or (record.state == "COMMITTED" and userId == record.toUserId)
    local shouldNotOwn = (record.state == "PREPARED" and userId == record.toUserId)
        or (record.state == "COMMITTED" and userId == record.fromUserId)
    if not shouldOwn and not shouldNotOwn then
        return true, nil
    end

    local foundIndex = nil
    for index, creature in profile.creatures do
        if creature.id == record.creature.id then
            foundIndex = index
            break
        end
    end
    if shouldNotOwn then
        if foundIndex ~= nil then
            table.remove(profile.creatures, foundIndex)
            return true, nil
        end
        return true, nil
    end

    if foundIndex ~= nil then
        return true, nil
    end
    if #profile.creatures >= profile.slotCapacity then
        return false, "TransferRecoveryCapacityConflict"
    end
    local creature = {
        id = record.creature.id,
        speciesId = record.creature.speciesId,
    }
    if record.creature.mutationFormId ~= nil then
        creature.mutationFormId = record.creature.mutationFormId
    end
    table.insert(profile.creatures, creature)
    profile.discoveredSpeciesIds[creature.speciesId] = true
    if creature.mutationFormId ~= nil then
        profile.discoveredMutationFormIds[creature.mutationFormId] = true
    end
    if record.state == "COMMITTED" then
        local catalystId = MutationConfig.CATALYSTS_BY_THEME[record.catalystThemeId]
        if profile.catalysts[catalystId] >= MutationConfig.MAX_CATALYST_COUNT then
            return false, "TransferRecoveryCatalystConflict"
        end
        profile.catalysts[catalystId] += 1
    end
    return true, nil
end

function PlayerDataService.beginFirstRaidParticipation(
    self: any,
    userId: number,
    raidId: string,
    completesAtUnix: number
): (boolean, any?, string?)
    if
        type(userId) ~= "number"
        or userId <= 0
        or userId % 1 ~= 0
        or not validRaidId(raidId)
        or not isIntegerBetween(completesAtUnix, 0, 4_102_444_800)
    then
        return false, nil, "InvalidFirstRaidParticipation"
    end
    local profile = self._profiles[userId]
    if profile == nil then
        return false, nil, "ProfileNotLoaded"
    end
    if profile.hasCompletedFirstRaid then
        if self._dirty[userId] then
            local saved, saveError = self:save(userId, false)
            if not saved then
                return false, nil, saveError or "SaveFailed"
            end
        end
        return true, nil, nil
    end
    if profile.firstRaidParticipation ~= nil then
        local marker = cloneValue(profile.firstRaidParticipation)
        if self._dirty[userId] then
            local saved, saveError = self:save(userId, false)
            if not saved then
                return false, marker, saveError or "SaveFailed"
            end
        end
        return true, marker, nil
    end

    local transacted, result, transactionError = self:transact(userId, function(draft)
        if draft.hasCompletedFirstRaid then
            return { changed = false }
        end
        if draft.firstRaidParticipation ~= nil then
            return { changed = false, marker = draft.firstRaidParticipation }
        end
        draft.firstRaidParticipation = {
            raidId = raidId,
            completesAtUnix = completesAtUnix,
        }
        return { changed = true, marker = draft.firstRaidParticipation }
    end)
    if not transacted or result == nil then
        return false, nil, transactionError or "Unavailable"
    end
    local marker = cloneValue(result.marker)
    if result.changed or self._dirty[userId] then
        local saved, saveError = self:save(userId, false)
        if not saved then
            return false, marker, saveError or "SaveFailed"
        end
    end
    return true, marker, nil
end

function PlayerDataService.finalizeFirstRaidParticipation(
    self: any,
    userId: number,
    raidId: string,
    completesAtUnix: number,
    nowUnix: number?
): (boolean, boolean, string?)
    local now = if nowUnix ~= nil then nowUnix else self._clock()
    if
        type(userId) ~= "number"
        or userId <= 0
        or userId % 1 ~= 0
        or not validRaidId(raidId)
        or not isIntegerBetween(completesAtUnix, 0, 4_102_444_800)
        or type(now) ~= "number"
        or now ~= now
        or now == math.huge
        or now == -math.huge
    then
        return false, false, "InvalidFirstRaidParticipation"
    end
    local profile = self._profiles[userId]
    if profile == nil then
        return false, false, "ProfileNotLoaded"
    end
    if profile.hasCompletedFirstRaid then
        if self._dirty[userId] then
            local saved, saveError = self:save(userId, false)
            if not saved then
                return false, false, saveError or "SaveFailed"
            end
        end
        return true, false, nil
    end
    local marker = profile.firstRaidParticipation
    if marker == nil or marker.raidId ~= raidId or marker.completesAtUnix ~= completesAtUnix then
        return true, false, nil
    end
    if now < completesAtUnix then
        return false, false, "NotExpired"
    end

    local transacted, result, transactionError = self:transact(userId, function(draft)
        local current = draft.firstRaidParticipation
        if
            current == nil
            or current.raidId ~= raidId
            or current.completesAtUnix ~= completesAtUnix
        then
            return { changed = false }
        end
        if now < current.completesAtUnix then
            return nil, "NotExpired"
        end
        draft.firstRaidParticipation = nil
        draft.hasCompletedFirstRaid = true
        return { changed = true }
    end)
    if not transacted or result == nil then
        return false, false, transactionError or "Unavailable"
    end
    if result.changed or self._dirty[userId] then
        local saved, saveError = self:save(userId, false)
        if not saved then
            return false, result.changed, saveError or "SaveFailed"
        end
    end
    return true, result.changed, nil
end

function PlayerDataService.lockTransfer(
    self: any,
    transferId: string,
    fromUserId: number,
    toUserId: number,
    creatureId: string,
    catalystThemeId: string
): (any?, string?)
    local catalystId = MutationConfig.CATALYSTS_BY_THEME[catalystThemeId]
    if
        type(transferId) ~= "string"
        or #transferId < 1
        or #transferId > 128
        or not isIntegerBetween(fromUserId, 1, 2_147_483_647)
        or not isIntegerBetween(toUserId, 1, 2_147_483_647)
        or fromUserId == toUserId
        or type(creatureId) ~= "string"
        or #creatureId < 1
        or #creatureId > 128
        or catalystId == nil
    then
        return nil, "InvalidTransfer"
    end

    local ownerProfile = self._profiles[fromUserId]
    local thiefProfile = self._profiles[toUserId]
    if ownerProfile == nil or thiefProfile == nil then
        return nil, "ProfileNotLoaded"
    end
    if
        self._closing[fromUserId]
        or self._closing[toUserId]
        or self._transferLocks[fromUserId] ~= nil
        or self._transferLocks[toUserId] ~= nil
        or self._transacting[fromUserId]
        or self._transacting[toUserId]
    then
        return nil, "Locked"
    end

    local creature = nil
    for _, ownedCreature in ownerProfile.creatures do
        if ownedCreature.id == creatureId then
            creature = ownedCreature
            break
        end
    end
    if creature == nil then
        return nil, "NotOwner"
    end
    if creatureId == ownerProfile.starterCreatureId then
        return nil, "Locked"
    end
    if #thiefProfile.creatures >= thiefProfile.slotCapacity then
        return nil, "CapacityFull"
    end
    for _, ownedCreature in thiefProfile.creatures do
        if ownedCreature.id == creatureId then
            return nil, "Conflict"
        end
    end
    if thiefProfile.catalysts[catalystId] >= MutationConfig.MAX_CATALYST_COUNT then
        return nil, "CapacityFull"
    end

    self._transferLocks[fromUserId] = transferId
    self._transferLocks[toUserId] = transferId
    return cloneValue(creature), nil
end

function PlayerDataService.finishTransfer(self: any, record: any): (boolean, string?)
    if
        type(record) ~= "table"
        or type(record.transferId) ~= "string"
        or record.state ~= "COMMITTED"
        or not isIntegerBetween(record.fromUserId, 1, 2_147_483_647)
        or not isIntegerBetween(record.toUserId, 1, 2_147_483_647)
    then
        return false, "InvalidTransfer"
    end
    local fromUserId = record.fromUserId
    local toUserId = record.toUserId
    if
        self._transferLocks[fromUserId] ~= record.transferId
        or self._transferLocks[toUserId] ~= record.transferId
    then
        return false, "TransferLockMissing"
    end

    local ownerProfile = self._profiles[fromUserId]
    local thiefProfile = self._profiles[toUserId]
    if ownerProfile == nil or thiefProfile == nil then
        return false, "ProfileNotLoaded"
    end
    local ownerDraft = cloneValue(ownerProfile)
    local thiefDraft = cloneValue(thiefProfile)
    local ownerApplied, ownerError = reconcileTransferRecord(ownerDraft, fromUserId, record)
    local thiefApplied, thiefError = reconcileTransferRecord(thiefDraft, toUserId, record)
    if not ownerApplied or not thiefApplied then
        return false, ownerError or thiefError or "TransferConflict"
    end
    local ownerValid, ownerValidationError = PlayerDataService.validateProfile(ownerDraft)
    local thiefValid, thiefValidationError = PlayerDataService.validateProfile(thiefDraft)
    if not ownerValid or not thiefValid then
        return false, ownerValidationError or thiefValidationError or "TransferProfileInvalid"
    end

    self._profiles[fromUserId] = ownerDraft
    self._profiles[toUserId] = thiefDraft
    self._dirty[fromUserId] = true
    self._dirty[toUserId] = true
    self._revision[fromUserId] += 1
    self._revision[toUserId] += 1
    self._transferLocks[fromUserId] = nil
    self._transferLocks[toUserId] = nil
    return true, nil
end

function PlayerDataService.abortTransferLock(
    self: any,
    transferId: string,
    fromUserId: number,
    toUserId: number
): boolean
    if type(transferId) ~= "string" then
        return false
    end
    local released = false
    if self._transferLocks[fromUserId] == transferId then
        self._transferLocks[fromUserId] = nil
        released = true
    end
    if self._transferLocks[toUserId] == transferId then
        self._transferLocks[toUserId] = nil
        released = true
    end
    return released
end

function PlayerDataService._startAutoSave(self: any, userId: number)
    if not self._autoSaveEnabled then
        return
    end
    local token = {}
    self._autoSaveTokens[userId] = token
    self._schedule(function()
        local offset = math.floor(self._random() * self._autoSaveInterval)
        if offset > 0 then
            self._wait(offset)
        end
        while
            not self._stopped
            and self._profiles[userId] ~= nil
            and self._autoSaveTokens[userId] == token
        do
            self._wait(self._autoSaveInterval)
            if self._profiles[userId] ~= nil and self._autoSaveTokens[userId] == token then
                local ok, reason =
                    PlayerDataService.save(self, userId, self._closing[userId] == true)
                if not ok then
                    warn(string.format("[PlayerData] Autosave failed: %s", tostring(reason)))
                end
            end
        end
    end)
end

function PlayerDataService.load(self: any, userId: number): (boolean, string?)
    if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
        return false, "InvalidUserId"
    end
    if self._profiles[userId] ~= nil then
        return true, nil
    end
    local defaultProfile = PlayerDataService.createDefaultProfile(self._generateCreatureId)
    local profile, loadError = self._profileStore:load(userId, defaultProfile)
    if profile == nil then
        return false, loadError or "ProfileUnavailable"
    end
    local valid, validationError = PlayerDataService.validateProfile(profile)
    if not valid then
        if type(self._profileStore.release) == "function" then
            pcall(self._profileStore.release, self._profileStore, userId)
        end
        return false, validationError or "CorruptProfile"
    end

    local journalRecords = {}
    local journalChanged = false
    if self._transferJournalStore ~= nil then
        local readOk, records, journalError =
            pcall(self._transferJournalStore.getForUser, self._transferJournalStore, userId)
        if not readOk or type(records) ~= "table" then
            if type(self._profileStore.release) == "function" then
                pcall(self._profileStore.release, self._profileStore, userId)
            end
            return false,
                if readOk then journalError or "TransferJournalUnavailable" else tostring(records)
        end
        journalRecords = records
        for _, record in journalRecords do
            local beforeCount = #profile.creatures
            local creatureFoundBefore = false
            for _, creature in profile.creatures do
                if creature.id == record.creature.id then
                    creatureFoundBefore = true
                    break
                end
            end
            local applied, applyError = reconcileTransferRecord(profile, userId, record)
            if not applied then
                if type(self._profileStore.release) == "function" then
                    pcall(self._profileStore.release, self._profileStore, userId)
                end
                return false, applyError or "TransferJournalConflict"
            end
            local creatureFoundAfter = false
            for _, creature in profile.creatures do
                if creature.id == record.creature.id then
                    creatureFoundAfter = true
                    break
                end
            end
            journalChanged = journalChanged
                or #profile.creatures ~= beforeCount
                or creatureFoundBefore ~= creatureFoundAfter
        end
        local journalProfileValid, journalValidationError =
            PlayerDataService.validateProfile(profile)
        if not journalProfileValid then
            if type(self._profileStore.release) == "function" then
                pcall(self._profileStore.release, self._profileStore, userId)
            end
            return false, journalValidationError or "TransferJournalConflict"
        end
    end

    local changed = journalChanged or PlayerDataService._normalizeFirstRaid(profile, self._clock())
    if changed then
        local saved, saveError = self._profileStore:save(userId, profile, false)
        if not saved then
            if type(self._profileStore.release) == "function" then
                pcall(self._profileStore.release, self._profileStore, userId)
            end
            return false, saveError or "ProfileNormalizationSaveFailed"
        end
    end

    if self._transferJournalStore ~= nil then
        for _, record in journalRecords do
            local marked, markError = pcall(
                self._transferJournalStore.markApplied,
                self._transferJournalStore,
                record.transferId,
                userId
            )
            if not marked or markError == false then
                warn(
                    string.format(
                        "[PlayerData] Transfer journal receipt pending: %s",
                        tostring(markError)
                    )
                )
            end
        end
    end

    self._profiles[userId] = cloneValue(profile)
    self._dirty[userId] = false
    self._revision[userId] = 0
    self._closing[userId] = nil
    self:_startAutoSave(userId)
    return true, nil
end

function PlayerDataService.isProfileValid(profile: any): boolean
    local valid = PlayerDataService.validateProfile(profile)
    return valid
end

function PlayerDataService.getSnapshot(self: any, userId: number): any?
    local profile = self._profiles[userId]
    if profile == nil then
        return nil
    end
    return cloneValue(profile)
end

function PlayerDataService.getCreatures(self: any, userId: number): { any }?
    local profile = self._profiles[userId]
    if profile == nil then
        return nil
    end
    return cloneValue(profile.creatures)
end

function PlayerDataService.getRevision(self: any, userId: number): number?
    if self._profiles[userId] == nil then
        return nil
    end
    return self._revision[userId]
end

function PlayerDataService.transact(
    self: any,
    userId: number,
    operation: (any) -> (any, string?)
): (boolean, any?, string?)
    local current = self._profiles[userId]
    if current == nil then
        return false, nil, "ProfileNotLoaded"
    end
    if self._closing[userId] then
        return false, nil, "ProfileClosing"
    end
    if self._transferLocks[userId] ~= nil then
        return false, nil, "Locked"
    end
    if self._transacting[userId] then
        return false, nil, "Conflict"
    end
    if type(operation) ~= "function" then
        return false, nil, "InvalidOperation"
    end

    self._transacting[userId] = true
    local draft = cloneValue(current)
    local callOk, result, operationError = pcall(operation, draft)
    self._transacting[userId] = nil
    if not callOk then
        return false, nil, "Unavailable"
    end
    if operationError ~= nil then
        return false, nil, operationError
    end
    if result == nil then
        return false, nil, "Conflict"
    end
    local valid, validationError = PlayerDataService.validateProfile(draft)
    if not valid then
        return false, nil, validationError or "InvalidProfile"
    end

    self._profiles[userId] = draft
    self._dirty[userId] = true
    self._revision[userId] += 1
    return true, cloneValue(result), nil
end

function PlayerDataService.creditScrap(
    self: any,
    userId: number,
    amount: number
): (boolean, number, number?, string?)
    local profile = self._profiles[userId]
    if profile == nil then
        return false, 0, nil, "ProfileNotLoaded"
    end
    if self._closing[userId] then
        return false, 0, profile.scrap, "ProfileClosing"
    end
    if self._transacting[userId] then
        return false, 0, profile.scrap, "Conflict"
    end
    if not isIntegerBetween(amount, 0, EconomyConfig.MAX_SCRAP) then
        return false, 0, profile.scrap, "InvalidAmount"
    end
    local credited = math.min(amount, EconomyConfig.MAX_SCRAP - profile.scrap)
    if credited > 0 then
        profile.scrap += credited
        self._dirty[userId] = true
        self._revision[userId] += 1
    end
    return true, credited, profile.scrap, nil
end

function PlayerDataService.save(self: any, userId: number, release: boolean?): (boolean, string?)
    if release == true then
        self._closing[userId] = true
    end
    local profile = self._profiles[userId]
    if profile == nil then
        if release == true then
            return true, nil
        end
        return false, "ProfileNotLoaded"
    end
    local deadline = os.clock() + 10
    while self._saving[userId] or self._transferLocks[userId] ~= nil do
        if os.clock() >= deadline then
            return false, "SaveInProgress"
        end
        self._wait(0.05)
    end
    profile = self._profiles[userId]
    if profile == nil then
        if release == true then
            return true, nil
        end
        return false, "ProfileNotLoaded"
    end

    self._saving[userId] = true
    local revision = self._revision[userId]
    local callOk, saved, saveError = pcall(
        self._profileStore.save,
        self._profileStore,
        userId,
        cloneValue(profile),
        release == true
    )
    self._saving[userId] = nil
    if not callOk or not saved then
        if not callOk then
            return false, tostring(saved)
        end
        return false, saveError or "SaveFailed"
    end

    self._dirty[userId] = self._revision[userId] ~= revision
    if release == true then
        self._profiles[userId] = nil
        self._dirty[userId] = nil
        self._revision[userId] = nil
        self._closing[userId] = nil
        self._autoSaveTokens[userId] = nil
    end
    return true, nil
end

function PlayerDataService.unload(self: any, userId: number): (boolean, string?)
    if self._profiles[userId] == nil then
        return true, nil
    end
    self._closing[userId] = true
    local saved, saveError = PlayerDataService.save(self, userId, true)
    if not saved then
        return false, saveError
    end
    return true, nil
end

function PlayerDataService.saveAllAndRelease(self: any, timeoutSeconds: number?): (boolean, number)
    self._stopped = true
    local pending = {}
    for userId in self._profiles do
        table.insert(pending, userId)
        self._closing[userId] = true
    end
    if #pending == 0 then
        return true, 0
    end

    local remaining = #pending
    local failures = 0
    for _, userId in pending do
        local scheduled, scheduleError = pcall(function()
            self._schedule(function()
                local callOk, saved = pcall(PlayerDataService.save, self, userId, true)
                if not callOk or not saved then
                    failures += 1
                end
                remaining -= 1
            end)
        end)
        if not scheduled then
            warn(
                string.format(
                    "[PlayerData] Shutdown save could not start: %s",
                    tostring(scheduleError)
                )
            )
            failures += 1
            remaining -= 1
        end
    end

    local deadline = os.clock() + (timeoutSeconds or 25)
    while remaining > 0 and os.clock() < deadline do
        self._wait(0.05)
    end
    return remaining == 0 and failures == 0, failures + remaining
end

return table.freeze(PlayerDataService)
