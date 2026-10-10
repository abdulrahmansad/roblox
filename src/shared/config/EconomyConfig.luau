-- Public economy constants. Values that affect progression are server-validated.

return table.freeze({
    STARTING_SCRAP = 50,
    MAX_SCRAP = 2_000_000_000,
    INCOME_INTERVAL_SECONDS = 10,
    AUTOSAVE_INTERVAL_SECONDS = 120,
    SESSION_LOCK_TTL_SECONDS = 300,
    STORE_MAX_ATTEMPTS = 3,
    CREATURE_SALE_VALUE = 60,
    SLOT_3_PRICE = 350,
    SLOT_4_PRICE = 1_200,
    MAX_SLOT_CAPACITY = 4,
    KIOSK_RANGE_STUDS = 12,
    STARTER_SPECIES_ID = "Mossling",
    STARTER_SLOT_CAPACITY = 2,
})
