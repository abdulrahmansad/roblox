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
        _saving = {},
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
    if profile.slotCapacity ~= 2 and profile.slotCapacity ~= 3 and profile.slotCapacity ~= 4 then
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

    local changed = PlayerDataService._normalizeFirstRaid(profile, self._clock())
    if changed then
        local saved, saveError = self._profileStore:save(userId, profile, false)
        if not saved then
            if type(self._profileStore.release) == "function" then
                pcall(self._profileStore.release, self._profileStore, userId)
            end
            return false, saveError or "ProfileNormalizationSaveFailed"
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
    while self._saving[userId] do
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
