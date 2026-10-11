-- Plays local-only, presentation-only audio cues with reduced-volume support.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local AudioCueConfig = require(game:GetService("ReplicatedStorage").Shared.config.AudioCueConfig)

local controller = {}
local started = false
local reducedEffects = false
local activeSounds = {}
local warnedCueErrors = {}
local lastIncomeCueAt = -math.huge

function controller.start(): boolean
    if started then
        return true
    end
    started = true
    return true
end

function controller.isReducedEffectsEnabled(): boolean
    return reducedEffects
end

function controller.setReducedEffects(enabled: boolean)
    if type(enabled) ~= "boolean" then
        return
    end
    reducedEffects = enabled
    for sound, baseVolume in activeSounds do
        if sound.Parent ~= nil then
            sound.Volume = baseVolume * if reducedEffects then 0.45 else 1
        end
    end
end

function controller.playCue(cueId: string): boolean
    if not started then
        return false
    end
    local specification = AudioCueConfig.CUES[cueId]
    if specification == nil then
        return false
    end
    if cueId == "IncomeTick" then
        local now = os.clock()
        if now - lastIncomeCueAt < AudioCueConfig.INCOME_CUE_MIN_INTERVAL_SECONDS then
            return false
        end
        lastIncomeCueAt = now
    end

    local sound = Instance.new("Sound")
    sound.Name = "OddlingsCue_" .. cueId
    sound.SoundId = "rbxassetid://" .. tostring(specification.assetId)
    sound.Volume = specification.volume * if reducedEffects then 0.45 else 1
    sound.PlaybackSpeed = specification.playbackSpeed
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.Parent = SoundService
    activeSounds[sound] = specification.volume
    sound.Ended:Connect(function()
        activeSounds[sound] = nil
        sound:Destroy()
    end)
    Debris:AddItem(sound, 8)

    local ok, errorMessage = pcall(function()
        sound:Play()
    end)
    if not ok then
        activeSounds[sound] = nil
        sound:Destroy()
        if not warnedCueErrors[cueId] then
            warnedCueErrors[cueId] = true
            warn(string.format("[Audio] Cue %s could not play: %s", cueId, tostring(errorMessage)))
        end
        return false
    end
    return true
end

function controller.stop()
    for sound in activeSounds do
        activeSounds[sound] = nil
        sound:Stop()
        sound:Destroy()
    end
    table.clear(activeSounds)
    started = false
end

return table.freeze(controller)
