-- Public species facts shared by server systems and future presentation code.

local definitions = {
    Mossling = { rarity = "Common", scrapPerMinute = 40 },
    TiffinToad = { rarity = "Common", scrapPerMinute = 36 },
    PuddlePup = { rarity = "Common", scrapPerMinute = 38 },
    ButtonBat = { rarity = "Common", scrapPerMinute = 42 },
    NoodleFinch = { rarity = "Common", scrapPerMinute = 44 },
    PebbleImp = { rarity = "Common", scrapPerMinute = 46 },
    TeacupCrab = { rarity = "Uncommon", scrapPerMinute = 70 },
    StaticFinch = { rarity = "Uncommon", scrapPerMinute = 74 },
    VelvetGremlin = { rarity = "Uncommon", scrapPerMinute = 78 },
    ClockworkCarp = { rarity = "Uncommon", scrapPerMinute = 82 },
    LanternYak = { rarity = "Rare", scrapPerMinute = 110 },
    PocketHydra = { rarity = "Rare", scrapPerMinute = 120 },
}

function definitions.isSpeciesId(speciesId: any): boolean
    local definition = if type(speciesId) == "string" then definitions[speciesId] else nil
    return type(definition) == "table" and type(definition.scrapPerMinute) == "number"
end

return table.freeze(definitions)
