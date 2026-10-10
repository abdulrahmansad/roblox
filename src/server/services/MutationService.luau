-- Owns server-selected mutation rolls and one transient revealed offer per player.

local MutationDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.MutationDefinitions)
    else require("../../shared/definitions/MutationDefinitions")
local MutationConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.MutationConfig)
    else require("../../shared/config/MutationConfig")
local CreatureService = if game ~= nil
    then require(game:GetService("ServerScriptService").Server.services.CreatureService)
    else require("./CreatureService")

local MutationService = {}
MutationService.__index = MutationService

local ECONOMY_PHASES = { PEACE = true, WARNING = true, COOLDOWN = true }
local FORBIDDEN_PHASES = { RAID = true, RESOLUTION = true }

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

local function makeOddsSnapshot(mutationRareMissCount: number): any
    local normalOdds = MutationConfig.ODDS_PER_1000
    local guaranteeActive = mutationRareMissCount >= MutationConfig.RARE_PITY_LIMIT
    return {
        unit = "per-thousand",
        normal = {
            common = normalOdds.common,
            uncommon = normalOdds.uncommon,
            rare = normalOdds.rare,
            mythic = normalOdds.mythic,
        },
        rareGuaranteeActive = guaranteeActive,
        nextRoll = if guaranteeActive
            then { rare = 999, mythic = 1 }
            else {
                common = normalOdds.common,
                uncommon = normalOdds.uncommon,
                rare = normalOdds.rare,
                mythic = normalOdds.mythic,
            },
        mutationRareMissCount = mutationRareMissCount,
    }
end

function MutationService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.playerDataService) == "table", "playerDataService is required")
    assert(type(options.playerDataService.transact) == "function", "transact is required")
    assert(type(options.playerDataService.getSnapshot) == "function", "getSnapshot is required")
    assert(type(options.creatureService) == "table", "creatureService is required")
    assert(
        type(options.generateTransactionId) == "function",
        "transaction ID generator is required"
    )

    return setmetatable({
        _playerDataService = options.playerDataService,
        _creatureService = options.creatureService,
        _generateTransactionId = options.generateTransactionId,
        _randomInteger = options.randomInteger or math.random,
        _emitEvent = options.emitEvent,
        _pending = {},
    }, MutationService)
end

function MutationService._random(self: any, minimum: number, maximum: number): number?
    local ok, value = pcall(self._randomInteger, minimum, maximum)
    if
        not ok
        or type(value) ~= "number"
        or value % 1 ~= 0
        or value < minimum
        or value > maximum
    then
        return nil
    end
    return value
end

function MutationService._newTransactionId(self: any): string?
    local ok, transactionId = pcall(self._generateTransactionId)
    if not ok or type(transactionId) ~= "string" or #transactionId < 1 or #transactionId > 128 then
        return nil
    end
    return transactionId
end

function MutationService._chooseForm(self: any, themeId: string, tier: string): string?
    local themeForms = MutationDefinitions.FormIdsByThemeAndTier[themeId]
    local forms = if themeForms ~= nil then themeForms[tier] else nil
    if type(forms) ~= "table" or #forms == 0 then
        return nil
    end
    local index = self:_random(1, #forms)
    return if index ~= nil then forms[index] else nil
end

function MutationService._rollTier(self: any, mutationRareMissCount: number): string?
    local roll = self:_random(1, 1_000)
    if roll == nil then
        return nil
    end
    if mutationRareMissCount >= MutationConfig.RARE_PITY_LIMIT then
        return if roll == 1 then "Mythic" else "Rare"
    end

    local odds = MutationConfig.ODDS_PER_1000
    if roll <= odds.common then
        return "Common"
    elseif roll <= odds.common + odds.uncommon then
        return "Uncommon"
    elseif roll <= odds.common + odds.uncommon + odds.rare then
        return "Rare"
    end
    return "Mythic"
end

function MutationService.getOddsSnapshot(_self: any, mutationRareMissCount: number): any?
    if
        type(mutationRareMissCount) ~= "number"
        or mutationRareMissCount % 1 ~= 0
        or mutationRareMissCount < 0
        or mutationRareMissCount > MutationConfig.RARE_PITY_LIMIT
    then
        return nil
    end
    return makeOddsSnapshot(mutationRareMissCount)
end

function MutationService._isOwnedAndOnStand(
    self: any,
    userId: number,
    creatureId: string
): (any?, string?)
    local profile = self._playerDataService:getSnapshot(userId)
    if profile == nil then
        return nil, "Unavailable"
    end
    local creature = CreatureService.findInProfile(nil, profile, creatureId)
    if creature == nil then
        return nil, "NotOwner"
    end
    if
        self._creatureService:isRestricted(userId, creatureId)
        or not self._creatureService:isOnStand(userId, creatureId)
    then
        return nil, "Locked"
    end
    return creature, nil
end

function MutationService.completeTutorialMutation(
    self: any,
    userId: number,
    creatureId: string,
    themeId: string,
    phase: string
): (any?, string?)
    if not ECONOMY_PHASES[phase] then
        return nil, "WrongPhase"
    end
    if not MutationDefinitions.isThemeId(themeId) then
        return nil, "InvalidRequest"
    end
    if self._pending[userId] ~= nil then
        return nil, "Conflict"
    end

    local profile = self._playerDataService:getSnapshot(userId)
    if profile == nil then
        return nil, "Unavailable"
    end
    if profile.tutorialCompleted then
        return nil, "AlreadyClaimed"
    end
    if creatureId ~= profile.starterCreatureId then
        return nil, "Locked"
    end
    local _, ownershipError = self:_isOwnedAndOnStand(userId, creatureId)
    if ownershipError ~= nil then
        return nil, ownershipError
    end
    local formId = self:_chooseForm(themeId, "Common")
    if formId == nil then
        return nil, "Unavailable"
    end

    local success, data, errorCode = self._playerDataService:transact(userId, function(draft)
        if draft.tutorialCompleted then
            return nil, "AlreadyClaimed"
        end
        if draft.starterCreatureId ~= creatureId then
            return nil, "Locked"
        end
        local creature = CreatureService.findInProfile(nil, draft, creatureId)
        if creature == nil then
            return nil, "NotOwner"
        end
        if creature.mutationFormId ~= nil then
            return nil, "Conflict"
        end

        creature.mutationFormId = formId
        draft.discoveredMutationFormIds[formId] = true
        draft.tutorialCompleted = true
        return {
            themeId = themeId,
            formId = formId,
            tutorialCompleted = true,
            creatureId = creatureId,
        },
            nil
    end)
    if not success then
        return nil, errorCode or "Unavailable"
    end

    local synced, syncError = self._creatureService:syncPlayer(userId)
    if not synced then
        warn(string.format("[Base] Could not sync tutorial mutation: %s", tostring(syncError)))
    end
    return data, nil
end

function MutationService.startMutation(
    self: any,
    userId: number,
    creatureId: string,
    themeId: string,
    phase: string
): (any?, string?)
    if not ECONOMY_PHASES[phase] then
        return nil, "WrongPhase"
    end
    if not MutationDefinitions.isThemeId(themeId) then
        return nil, "InvalidRequest"
    end
    if self._pending[userId] ~= nil then
        return nil, "Conflict"
    end
    local ownedCreature, ownershipError = self:_isOwnedAndOnStand(userId, creatureId)
    if ownedCreature == nil then
        return nil, ownershipError
    end
    local profile = self._playerDataService:getSnapshot(userId)
    if profile == nil then
        return nil, "Unavailable"
    end
    if not profile.tutorialCompleted then
        return nil, "Locked"
    end

    local transactionId = self:_newTransactionId()
    if transactionId == nil then
        return nil, "Unavailable"
    end
    if not self._creatureService:setMutationLock(userId, creatureId, true) then
        return nil, "Locked"
    end

    local success, data, errorCode = self._playerDataService:transact(userId, function(draft)
        if not draft.tutorialCompleted then
            return nil, "Locked"
        end
        local creature = CreatureService.findInProfile(nil, draft, creatureId)
        if creature == nil then
            return nil, "NotOwner"
        end
        local catalystId = MutationConfig.CATALYSTS_BY_THEME[themeId]
        if draft.catalysts[catalystId] <= 0 then
            return nil, "InsufficientCatalyst"
        end
        if draft.scrap < MutationConfig.NORMAL_PRICE then
            return nil, "InsufficientScrap"
        end

        local oddsSnapshot = makeOddsSnapshot(draft.mutationRareMissCount)
        local tier = self:_rollTier(draft.mutationRareMissCount)
        if tier == nil then
            return nil, "Unavailable"
        end
        local revealedFormId = self:_chooseForm(themeId, tier)
        if revealedFormId == nil then
            return nil, "Unavailable"
        end

        draft.scrap -= MutationConfig.NORMAL_PRICE
        draft.catalysts[catalystId] -= 1
        if tier == "Rare" or tier == "Mythic" then
            draft.mutationRareMissCount = 0
        else
            draft.mutationRareMissCount =
                math.min(draft.mutationRareMissCount + 1, MutationConfig.RARE_PITY_LIMIT)
        end
        return {
            transactionId = transactionId,
            creatureId = creatureId,
            themeId = themeId,
            revealedFormId = revealedFormId,
            tier = tier,
            oddsSnapshot = oddsSnapshot,
            pityCount = draft.mutationRareMissCount,
            scrapBalance = draft.scrap,
            catalystCount = draft.catalysts[catalystId],
            catalystId = catalystId,
            previousFormId = creature.mutationFormId,
        },
            nil
    end)
    if not success then
        self._creatureService:setMutationLock(userId, creatureId, false)
        return nil, errorCode or "Unavailable"
    end

    self._pending[userId] = {
        transactionId = data.transactionId,
        creatureId = data.creatureId,
        themeId = data.themeId,
        revealedFormId = data.revealedFormId,
        tier = data.tier,
        oddsSnapshot = cloneValue(data.oddsSnapshot),
        previousFormId = data.previousFormId,
    }
    return {
        transactionId = data.transactionId,
        themeId = data.themeId,
        revealedFormId = data.revealedFormId,
        tier = data.tier,
        oddsSnapshot = cloneValue(data.oddsSnapshot),
        pityCount = data.pityCount,
        scrapBalance = data.scrapBalance,
        catalystCount = data.catalystCount,
        catalystId = data.catalystId,
    },
        nil
end

function MutationService._clearPending(self: any, userId: number, reason: string?): any?
    local pending = self._pending[userId]
    if pending == nil then
        return nil
    end
    self._pending[userId] = nil
    self._creatureService:setMutationLock(userId, pending.creatureId, false)
    if reason ~= nil and self._emitEvent ~= nil then
        local revision = self._playerDataService:getRevision(userId) or 0
        pcall(self._emitEvent, userId, "MutationDiscarded", {
            transactionId = pending.transactionId,
            reason = reason,
        }, revision)
    end
    return pending
end

function MutationService.resolveMutation(
    self: any,
    userId: number,
    transactionId: string,
    choice: string,
    phase: string
): (any?, string?)
    if not ECONOMY_PHASES[phase] then
        return nil, "WrongPhase"
    end
    local pending = self._pending[userId]
    if pending == nil or pending.transactionId ~= transactionId then
        return nil, "Expired"
    end
    if choice ~= "KeepCurrent" and choice ~= "Replace" and choice ~= "Decline" then
        return nil, "InvalidRequest"
    end

    local profile = self._playerDataService:getSnapshot(userId)
    if profile == nil then
        self:_clearPending(userId)
        return nil, "Unavailable"
    end
    local current = CreatureService.findInProfile(nil, profile, pending.creatureId)
    if current == nil then
        self:_clearPending(userId)
        return nil, "NotOwner"
    end

    local outcome = if choice == "Decline" then "Declined" else "KeptCurrent"
    local codexFormAdded = false
    local equippedFormId = current.mutationFormId
    if choice == "Replace" and current.mutationFormId == pending.revealedFormId then
        outcome = "Duplicate"
    elseif choice == "Replace" then
        local success, data, errorCode = self._playerDataService:transact(userId, function(draft)
            local creature = CreatureService.findInProfile(nil, draft, pending.creatureId)
            if creature == nil then
                return nil, "NotOwner"
            end
            if creature.mutationFormId ~= pending.previousFormId then
                return nil, "Conflict"
            end
            local alreadyDiscovered = draft.discoveredMutationFormIds[pending.revealedFormId]
                == true
            creature.mutationFormId = pending.revealedFormId
            draft.discoveredMutationFormIds[pending.revealedFormId] = true
            return {
                activeFormId = pending.revealedFormId,
                codexFormAdded = not alreadyDiscovered,
            },
                nil
        end)
        if not success then
            self:_clearPending(userId)
            return nil, errorCode or "Unavailable"
        end
        outcome = "Replaced"
        equippedFormId = data.activeFormId
        codexFormAdded = data.codexFormAdded
        local synced, syncError = self._creatureService:syncPlayer(userId)
        if not synced then
            warn(
                string.format("[Base] Could not sync mutation replacement: %s", tostring(syncError))
            )
        end
    end

    self:_clearPending(userId)
    local result = { outcome = outcome, codexFormAdded = codexFormAdded }
    if equippedFormId ~= nil then
        result.activeFormId = equippedFormId
    end
    return result, nil
end

function MutationService.getPending(self: any, userId: number): any?
    return cloneValue(self._pending[userId])
end

function MutationService.onPhaseChanged(self: any, snapshot: any): number
    local phase = if type(snapshot) == "table" then snapshot.phase else snapshot
    if type(phase) ~= "string" or not FORBIDDEN_PHASES[phase] then
        return 0
    end
    local userIds = {}
    for userId in self._pending do
        table.insert(userIds, userId)
    end
    for _, userId in userIds do
        self:_clearPending(userId, "PhaseEnded")
    end
    return #userIds
end

function MutationService.clearUser(self: any, userId: number)
    self:_clearPending(userId)
end

return table.freeze(MutationService)
