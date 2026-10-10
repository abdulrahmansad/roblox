-- Presentation-only helpers for the compact HUD and onboarding goal.

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")
local MutationDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.MutationDefinitions)
    else require("../../shared/definitions/MutationDefinitions")
local EconomyConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.EconomyConfig)
    else require("../../shared/config/EconomyConfig")
local CapsuleConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.CapsuleConfig)
    else require("../../shared/config/CapsuleConfig")

local HudModel = {}
HudModel.MIN_TOUCH_TARGET_PX = 56

local RARITIES = {
    Common = { icon = "●", color = "Common" },
    Uncommon = { icon = "◆", color = "Uncommon" },
    Rare = { icon = "✦", color = "Rare" },
    Mythic = { icon = "✧", color = "Mythic" },
}

function HudModel.formatNumber(value: number): string
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return "0"
    end
    if value % 1 == 0 then
        return string.format("%d", value)
    end
    return string.format("%.1f", value)
end

function HudModel.getIncomePerMinute(creatures: any): number
    if type(creatures) ~= "table" then
        return 0
    end
    local total = 0
    for _, creature in creatures do
        if type(creature) == "table" then
            local species = CreatureDefinitions[creature.speciesId]
            if species ~= nil then
                local multiplier = 1
                if creature.mutationFormId ~= nil then
                    local form = MutationDefinitions[creature.mutationFormId]
                    if form ~= nil then
                        multiplier = form.multiplier
                    end
                end
                total += species.scrapPerMinute * multiplier
            end
        end
    end
    return total
end

function HudModel.getGoal(snapshot: any, guidanceSkipped: boolean?): string
    if type(snapshot) ~= "table" then
        return "Connecting to your oddlings..."
    end
    if snapshot.tutorialCompleted ~= true and guidanceSkipped ~= true then
        return "Choose a theme for your free Common mutation."
    end
    if snapshot.welcomeAvailable == true then
        return string.format(
            "Visit the Commons for your guaranteed Uncommon capsule · %s Scrap.",
            HudModel.formatNumber(CapsuleConfig.PRICE)
        )
    end

    local creatures = if type(snapshot.creatures) == "table" then snapshot.creatures else {}
    local capacity = if type(snapshot.slotCapacity) == "number" then snapshot.slotCapacity else 2
    if capacity == EconomyConfig.STARTER_SLOT_CAPACITY and #creatures < capacity then
        return "Add an oddling at the Commons to fill your next stand."
    end
    if capacity == EconomyConfig.STARTER_SLOT_CAPACITY then
        return "Choose your next goal: improve a mutation or save for Slot 3."
    end
    if capacity < EconomyConfig.MAX_SLOT_CAPACITY then
        local targetCapacity = capacity + 1
        if targetCapacity == 4 and snapshot.hasCompletedFirstRaid ~= true then
            return "Complete your first Raid to unlock Slot 4."
        end
        local price = if targetCapacity == 3
            then EconomyConfig.SLOT_3_PRICE
            else EconomyConfig.SLOT_4_PRICE
        return string.format(
            "Save %s Scrap for Slot %d.",
            HudModel.formatNumber(price),
            targetCapacity
        )
    end
    return "Choose an oddling to improve before the next Raid."
end

function HudModel.getRarityPresentation(rarity: any): any
    local presentation = if type(rarity) == "string" then RARITIES[rarity] else nil
    if presentation == nil then
        return { icon = "○", label = "UNKNOWN", color = "Neutral" }
    end
    return { icon = presentation.icon, label = string.upper(rarity), color = presentation.color }
end

function HudModel.formatOdds(odds: any): string
    if type(odds) ~= "table" or type(odds.nextRoll) ~= "table" then
        return "Odds are unavailable until the server snapshot arrives."
    end
    local nextRoll = odds.nextRoll
    if odds.rareGuaranteeActive == true then
        return string.format(
            "Next roll: Rare %.1f%% · Mythic %.1f%% (Rare guarantee)",
            (nextRoll.rare or 0) / 10,
            (nextRoll.mythic or 0) / 10
        )
    end
    return string.format(
        "Next roll: Common %.0f%% · Uncommon %.0f%% · Rare %.1f%% · Mythic %.1f%%",
        (nextRoll.common or 0) / 10,
        (nextRoll.uncommon or 0) / 10,
        (nextRoll.rare or 0) / 10,
        (nextRoll.mythic or 0) / 10
    )
end

function HudModel.getCreatureLabel(creature: any): (string, string)
    if type(creature) ~= "table" then
        return "No oddling selected", "Common"
    end
    local speciesId = creature.speciesId
    local species = CreatureDefinitions[speciesId]
    if species == nil then
        return "Unknown oddling", "Common"
    end
    local rarity = species.rarity
    local label = speciesId
    if creature.mutationFormId ~= nil then
        local form = MutationDefinitions[creature.mutationFormId]
        if form ~= nil then
            rarity = form.tier
            label ..= " · " .. form.displayName
        end
    end
    return label, rarity
end

function HudModel.getErrorCopy(code: any): string
    local messages = {
        OutOfRange = "Move closer to the station or creature.",
        InsufficientScrap = "You need more Scrap for that.",
        InsufficientCatalyst = "Buy that theme's catalyst at the Commons.",
        CapacityFull = "Your stands are full. Open a slot first.",
        WrongPhase = "That action is paused during this Raid phase.",
        RateLimited = "Give it a moment, then try again.",
        AlreadyClaimed = "That one-time reward was already claimed.",
        Locked = "That action is not available right now.",
        NotOwner = "That oddling is no longer available.",
        Expired = "That interaction has expired.",
        Conflict = "Your game state changed. Try again.",
        Unavailable = "That action is temporarily unavailable.",
        ServiceUnavailable = "That action is temporarily unavailable.",
        InvalidRequest = "That action could not be understood.",
    }
    return if type(code) == "string"
        then messages[code] or "Please try again."
        else "Please try again."
end

return table.freeze(HudModel)
