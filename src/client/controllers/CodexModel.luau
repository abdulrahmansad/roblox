-- Builds the fixed 12-species and 24-form Codex view from a safe profile snapshot.

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")
local MutationDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.MutationDefinitions)
    else require("../../shared/definitions/MutationDefinitions")

local CodexModel = {}
local RARITY_ORDER = { "Common", "Uncommon", "Rare" }
local THEME_ORDER = { "Ember", "Prism", "Moss" }
local TIER_ORDER = { "Common", "Uncommon", "Rare", "Mythic" }

local function isDiscovered(map: any, id: string): boolean
    return type(map) == "table" and map[id] == true
end

function CodexModel.getEntries(codex: any): { any }
    local speciesMap = if type(codex) == "table" then codex.speciesIds else nil
    local mutationMap = if type(codex) == "table" then codex.mutationFormIds else nil
    local entries = {}

    for _, rarity in RARITY_ORDER do
        for _, speciesId in CreatureDefinitions.SpeciesIdsByRarity[rarity] do
            local discovered = isDiscovered(speciesMap, speciesId)
            table.insert(entries, {
                id = speciesId,
                kind = "Species",
                rarity = rarity,
                discovered = discovered,
                label = if discovered then speciesId else "Unknown species",
            })
        end
    end

    for _, themeId in THEME_ORDER do
        local formsByTier = MutationDefinitions.FormIdsByThemeAndTier[themeId]
        for _, tier in TIER_ORDER do
            for _, formId in formsByTier[tier] or {} do
                local definition = MutationDefinitions[formId]
                local discovered = isDiscovered(mutationMap, formId)
                table.insert(entries, {
                    id = formId,
                    kind = "Form",
                    themeId = themeId,
                    rarity = tier,
                    discovered = discovered,
                    label = if discovered
                        then definition.displayName
                        else "Unknown " .. themeId .. " form",
                })
            end
        end
    end

    return entries
end

function CodexModel.getSummary(codex: any): string
    local entries = CodexModel.getEntries(codex)
    local speciesCount = 0
    local formCount = 0
    for _, entry in entries do
        if entry.discovered then
            if entry.kind == "Species" then
                speciesCount += 1
            else
                formCount += 1
            end
        end
    end
    return string.format("CODEX · %d/12 SPECIES · %d/24 FORMS", speciesCount, formCount)
end

return table.freeze(CodexModel)
