-- Public mutation forms and deterministic theme/tier catalogs.

local definitions = {}
local mutableFormIdsByTheme = {}
local mutableFormIdsByThemeAndTier = {}

local forms = {
    { "Cinder", "Cinder", "Ember", "Common", 1.25 },
    { "Sparkcap", "Sparkcap", "Ember", "Common", 1.25 },
    { "Coalcoat", "Coalcoat", "Ember", "Common", 1.25 },
    { "Toastbite", "Toastbite", "Ember", "Common", 1.25 },
    { "Flarefin", "Flarefin", "Ember", "Uncommon", 1.5 },
    { "Hearthhorn", "Hearthhorn", "Ember", "Uncommon", 1.5 },
    { "Sunheart", "Sunheart", "Ember", "Rare", 2 },
    { "Starforge", "Starforge", "Ember", "Mythic", 4 },
    { "Glint", "Glint", "Prism", "Common", 1.25 },
    { "Opalcoat", "Opalcoat", "Prism", "Common", 1.25 },
    { "Shardtail", "Shardtail", "Prism", "Common", 1.25 },
    { "Splitlight", "Splitlight", "Prism", "Common", 1.25 },
    { "Aurora", "Aurora", "Prism", "Uncommon", 1.5 },
    { "Mirrorflash", "Mirrorflash", "Prism", "Uncommon", 1.5 },
    { "Spectrum", "Spectrum", "Prism", "Rare", 2 },
    { "Paragon", "Paragon", "Prism", "Mythic", 4 },
    { "Sprout", "Sprout", "Moss", "Common", 1.25 },
    { "Puffcap", "Puffcap", "Moss", "Common", 1.25 },
    { "Lichen", "Lichen", "Moss", "Common", 1.25 },
    { "Vinewrap", "Vinewrap", "Moss", "Common", 1.25 },
    { "Bloomguard", "Bloomguard", "Moss", "Uncommon", 1.5 },
    { "Boglight", "Boglight", "Moss", "Uncommon", 1.5 },
    { "Worldroot", "Worldroot", "Moss", "Rare", 2 },
    { "VerdantCrown", "Verdant Crown", "Moss", "Mythic", 4 },
}

for _, form in forms do
    local formId, displayName, themeId, tier, multiplier = table.unpack(form)
    definitions[formId] = table.freeze({
        displayName = displayName,
        themeId = themeId,
        tier = tier,
        multiplier = multiplier,
    })

    mutableFormIdsByTheme[themeId] = mutableFormIdsByTheme[themeId] or {}
    table.insert(mutableFormIdsByTheme[themeId], formId)
    mutableFormIdsByThemeAndTier[themeId] = mutableFormIdsByThemeAndTier[themeId] or {}
    mutableFormIdsByThemeAndTier[themeId][tier] = mutableFormIdsByThemeAndTier[themeId][tier] or {}
    table.insert(mutableFormIdsByThemeAndTier[themeId][tier], formId)
end

local formIdsByTheme = {}
for themeId, themeForms in mutableFormIdsByTheme do
    formIdsByTheme[themeId] = table.freeze(themeForms)
end

local formIdsByThemeAndTier = {}
for themeId, tierMap in mutableFormIdsByThemeAndTier do
    local frozenTierMap = {}
    for tier, tierForms in tierMap do
        frozenTierMap[tier] = table.freeze(tierForms)
    end
    formIdsByThemeAndTier[themeId] = table.freeze(frozenTierMap)
end

definitions.FormIdsByTheme = table.freeze(formIdsByTheme)
definitions.FormIdsByThemeAndTier = table.freeze(formIdsByThemeAndTier)

function definitions.isFormId(formId: any): boolean
    local definition = if type(formId) == "string" then definitions[formId] else nil
    return type(definition) == "table" and type(definition.multiplier) == "number"
end

function definitions.isThemeId(themeId: any): boolean
    return type(themeId) == "string" and formIdsByTheme[themeId] ~= nil
end

return table.freeze(definitions)
