-- Short, free-to-use Creator Store sound cues used by the client presenter.

local assets = {
    uiClick = 113397864512278,
    chime = 158050602,
    sparkle = 9125644410,
    reactorAlert = 5306089604,
    swoosh = 12222200,
    bass = 12221944,
}

local function cue(assetId: number, volume: number, playbackSpeed: number)
    return table.freeze({
        assetId = assetId,
        volume = volume,
        playbackSpeed = playbackSpeed,
    })
end

return table.freeze({
    INCOME_CUE_MIN_INTERVAL_SECONDS = 30,
    CUES = table.freeze({
        CapsuleReveal = cue(assets.chime, 0.34, 1),
        MutationStart = cue(assets.uiClick, 0.2, 0.9),
        MutationReveal = cue(assets.sparkle, 0.32, 1),
        RarePlus = cue(assets.sparkle, 0.46, 0.82),
        RaidWarning = cue(assets.reactorAlert, 0.34, 0.92),
        RaidStart = cue(assets.bass, 0.32, 0.86),
        RaidEnd = cue(assets.chime, 0.28, 0.78),
        TheftInTransit = cue(assets.swoosh, 0.2, 1.08),
        TagDrop = cue(assets.swoosh, 0.3, 0.82),
        Recovery = cue(assets.chime, 0.36, 1.15),
        SuccessfulBank = cue(assets.chime, 0.4, 1.02),
        Escape = cue(assets.uiClick, 0.3, 0.68),
        IncomeTick = cue(assets.uiClick, 0.1, 0.82),
    }),
})
