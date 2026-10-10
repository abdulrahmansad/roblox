-- Server-selected capsule purchases, pity, and persisted collection changes.

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")
local CapsuleConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.CapsuleConfig)
    else require("../../shared/config/CapsuleConfig")

local CapsuleService = {}
CapsuleService.__index = CapsuleService

local ECONOMY_PHASES = { PEACE = true, WARNING = true, COOLDOWN = true }

function CapsuleService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.playerDataService) == "table", "playerDataService is required")
    assert(
        type(options.playerDataService.transact) == "function",
        "profile transaction is required"
    )
    assert(type(options.creatureService) == "table", "creatureService is required")
    assert(type(options.generateCreatureId) == "function", "creature ID generator is required")

    return setmetatable({
        _playerDataService = options.playerDataService,
        _creatureService = options.creatureService,
        _generateCreatureId = options.generateCreatureId,
        _randomInteger = options.randomInteger or math.random,
    }, CapsuleService)
end

function CapsuleService._random(self: any, minimum: number, maximum: number): number?
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

function CapsuleService._rollTier(self: any, profile: any): string?
    local pity = profile.standardCapsulePity
    if pity.belowRare >= CapsuleConfig.FORCE_RARE_AFTER_BELOW_RARE_COUNT then
        return "Rare"
    end
    if pity.belowUncommon >= CapsuleConfig.FORCE_UNCOMMON_AFTER_COMMON_COUNT then
        local roll = self:_random(1, 6)
        if roll == nil then
            return nil
        end
        return if roll <= 5 then "Uncommon" else "Rare"
    end

    local roll = self:_random(1, 1_000)
    if roll == nil then
        return nil
    elseif roll <= CapsuleConfig.STANDARD_ODDS_PER_1000.common then
        return "Common"
    elseif
        roll
        <= CapsuleConfig.STANDARD_ODDS_PER_1000.common
            + CapsuleConfig.STANDARD_ODDS_PER_1000.uncommon
    then
        return "Uncommon"
    end
    return "Rare"
end

function CapsuleService._chooseSpecies(self: any, rarity: string): string?
    local speciesIds = CreatureDefinitions.SpeciesIdsByRarity[rarity]
    if type(speciesIds) ~= "table" or #speciesIds == 0 then
        return nil
    end
    local roll = self:_random(1, #speciesIds)
    if roll == nil then
        return nil
    end
    return speciesIds[roll]
end

function CapsuleService.purchase(
    self: any,
    userId: number,
    kind: string,
    phase: string
): (any?, string?)
    if kind ~= "Welcome" and kind ~= "Standard" then
        return nil, "InvalidRequest"
    end
    if ECONOMY_PHASES[phase] ~= true then
        return nil, "WrongPhase"
    end

    local success, data, errorCode = self._playerDataService:transact(userId, function(profile)
        if kind == "Welcome" and profile.welcomeCreatureId ~= nil then
            return nil, "AlreadyClaimed"
        end
        if #profile.creatures >= profile.slotCapacity then
            return nil, "CapacityFull"
        end
        if profile.scrap < CapsuleConfig.PRICE then
            return nil, "InsufficientScrap"
        end

        local rarity = if kind == "Welcome" then "Uncommon" else self:_rollTier(profile)
        if rarity == nil then
            return nil, "Unavailable"
        end
        local speciesId = self:_chooseSpecies(rarity)
        if speciesId == nil then
            return nil, "Unavailable"
        end
        local creature = {
            id = self._generateCreatureId(),
            speciesId = speciesId,
        }
        local owned, addError = self._creatureService:addToProfile(profile, creature)
        if owned == nil then
            return nil, addError or "Unavailable"
        end

        profile.scrap -= CapsuleConfig.PRICE
        if kind == "Welcome" then
            profile.welcomeCreatureId = owned.id
        else
            if rarity == "Common" then
                profile.standardCapsulePity.belowUncommon = math.min(
                    profile.standardCapsulePity.belowUncommon + 1,
                    CapsuleConfig.FORCE_UNCOMMON_AFTER_COMMON_COUNT
                )
            else
                profile.standardCapsulePity.belowUncommon = 0
            end
            if rarity == "Rare" then
                profile.standardCapsulePity.belowRare = 0
            else
                profile.standardCapsulePity.belowRare = math.min(
                    profile.standardCapsulePity.belowRare + 1,
                    CapsuleConfig.FORCE_RARE_AFTER_BELOW_RARE_COUNT
                )
            end
        end

        return {
            kind = kind,
            creature = owned,
            rarity = rarity,
            scrapBalance = profile.scrap,
            pity = {
                belowUncommon = profile.standardCapsulePity.belowUncommon,
                belowRare = profile.standardCapsulePity.belowRare,
            },
        },
            nil
    end)

    if not success then
        return nil, errorCode or "Unavailable"
    end
    local synced, syncError = self._creatureService:syncPlayer(userId)
    if not synced then
        warn(
            string.format("[Base] Could not sync collection after capsule: %s", tostring(syncError))
        )
    end
    return data, nil
end

return table.freeze(CapsuleService)
