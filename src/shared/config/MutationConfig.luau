-- Central balance and catalyst mapping for mutation actions.

return table.freeze({
    NORMAL_PRICE = 100,
    CATALYST_PRICE = 60,
    MAX_CATALYST_COUNT = 1_000_000,
    RARE_PITY_LIMIT = 8,
    ODDS_PER_1000 = table.freeze({ common = 600, uncommon = 300, rare = 99, mythic = 1 }),
    CATALYSTS_BY_THEME = table.freeze({
        Ember = "emberSeed",
        Prism = "prismDust",
        Moss = "mossSpore",
    }),
})
