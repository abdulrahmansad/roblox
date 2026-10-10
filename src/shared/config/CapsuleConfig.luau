return table.freeze({
    PRICE = 120,
    STANDARD_ODDS_PER_1000 = table.freeze({ common = 700, uncommon = 250, rare = 50 }),
    FORCE_UNCOMMON_AFTER_COMMON_COUNT = 3,
    FORCE_RARE_AFTER_BELOW_RARE_COUNT = 8,
})
