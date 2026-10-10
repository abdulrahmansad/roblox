local RaidService = {}
RaidService.__index = RaidService

local PHASES = { "PEACE", "WARNING", "RAID", "RESOLUTION", "COOLDOWN" }
local NEXT_PHASE = {
    PEACE = "WARNING",
    WARNING = "RAID",
    RAID = "RESOLUTION",
    RESOLUTION = "COOLDOWN",
    COOLDOWN = "PEACE",
}

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(callback: (...any) -> ()): any
    assert(type(callback) == "function", "callback must be a function")
    local record = { callback = callback, connected = true }
    table.insert(self._listeners, record)
    return {
        Disconnect = function()
            record.connected = false
        end,
    }
end

function Signal:Fire(...)
    for _, record in self._listeners do
        if record.connected then
            record.callback(...)
        end
    end
end

local function isValidPhase(phase: any): boolean
    for _, validPhase in PHASES do
        if phase == validPhase then
            return true
        end
    end
    return false
end

local function isFiniteNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function RaidService.new(options: any?)
    options = options or {}
    local phase = options.initialPhase or "PEACE"
    assert(isValidPhase(phase), "initialPhase is invalid")

    local clock = options.clock or os.time
    assert(type(clock) == "function", "clock must be a function")

    return setmetatable({
        _phase = phase,
        _phaseStartedAtUnix = clock(),
        _phaseEndsAtUnix = nil,
        _raidId = options.raidId or "initial",
        _phaseRevision = 0,
        _clock = clock,
        Changed = Signal.new(),
    }, RaidService)
end

function RaidService.getSnapshot(self: any): any
    return {
        phase = self._phase,
        phaseStartedAtUnix = self._phaseStartedAtUnix,
        phaseEndsAtUnix = self._phaseEndsAtUnix,
        raidId = self._raidId,
        revision = self._phaseRevision,
    }
end

function RaidService.transitionTo(
    self: any,
    phase: string,
    startedAtUnix: number?,
    endsAtUnix: number?
): (boolean, string?)
    if not isValidPhase(phase) then
        return false, "InvalidPhase"
    end
    if NEXT_PHASE[self._phase] ~= phase then
        return false, "InvalidTransition"
    end

    local phaseStartedAtUnix = startedAtUnix or self._clock()
    if not isFiniteNumber(phaseStartedAtUnix) or phaseStartedAtUnix < self._phaseStartedAtUnix then
        return false, "InvalidTimestamp"
    end
    if
        endsAtUnix ~= nil and (not isFiniteNumber(endsAtUnix) or endsAtUnix < phaseStartedAtUnix)
    then
        return false, "InvalidTimestamp"
    end

    self._phase = phase
    self._phaseStartedAtUnix = phaseStartedAtUnix
    self._phaseEndsAtUnix = endsAtUnix
    self._phaseRevision += 1
    self.Changed:Fire(RaidService.getSnapshot(self))
    return true, nil
end

return table.freeze(RaidService)
