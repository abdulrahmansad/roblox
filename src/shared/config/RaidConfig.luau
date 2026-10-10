-- Public, immutable timing for the shared Raid cycle.

return table.freeze({
    PHASE_ORDER = table.freeze({ "PEACE", "WARNING", "RAID", "RESOLUTION", "COOLDOWN" }),
    PHASE_DURATIONS_SECONDS = table.freeze({
        PEACE = 300,
        WARNING = 30,
        RAID = 90,
        RESOLUTION = 30,
        COOLDOWN = 30,
    }),
    ARRIVAL_GRACE_SECONDS = 15,
})
