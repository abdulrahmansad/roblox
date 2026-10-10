-- Public form IDs and balance facts. Mutation transactions arrive in M6.

local definitions = {}

local function addBranch(forms: { any })
    for _, form in forms do
        definitions[form[1]] = table.freeze({ tier = form[2], multiplier = form[3] })
    end
end

addBranch({
    { "Cinder", "Common", 1.25 },
    { "Sparkcap", "Common", 1.25 },
    { "Coalcoat", "Common", 1.25 },
    { "Toastbite", "Common", 1.25 },
    { "Flarefin", "Uncommon", 1.5 },
    { "Hearthhorn", "Uncommon", 1.5 },
    { "Sunheart", "Rare", 2 },
    { "Starforge", "Mythic", 4 },
})

addBranch({
    { "Glint", "Common", 1.25 },
    { "Opalcoat", "Common", 1.25 },
    { "Shardtail", "Common", 1.25 },
    { "Splitlight", "Common", 1.25 },
    { "Aurora", "Uncommon", 1.5 },
    { "Mirrorflash", "Uncommon", 1.5 },
    { "Spectrum", "Rare", 2 },
    { "Paragon", "Mythic", 4 },
})

addBranch({
    { "Sprout", "Common", 1.25 },
    { "Puffcap", "Common", 1.25 },
    { "Lichen", "Common", 1.25 },
    { "Vinewrap", "Common", 1.25 },
    { "Bloomguard", "Uncommon", 1.5 },
    { "Boglight", "Uncommon", 1.5 },
    { "Worldroot", "Rare", 2 },
    { "VerdantCrown", "Mythic", 4 },
})

function definitions.isFormId(formId: any): boolean
    local definition = if type(formId) == "string" then definitions[formId] else nil
    return type(definition) == "table" and type(definition.multiplier) == "number"
end

return table.freeze(definitions)
