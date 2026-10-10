local RaidConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.RaidConfig)
    else require("../../shared/config/RaidConfig")

local RaidService = {}
RaidService.__index = RaidService

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

function Signal:Fire(value: any)
    for _, record in self._listeners do
        if record.connected then
            local ok, failure = pcall(record.callback, value)
            if not ok then
                warn(string.format("[RaidService] Phase listener failed: %s", tostring(failure)))
            end
        end
    end
end

local function isFiniteNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isUserId(value: any): boolean
    return type(value) == "number" and value > 0 and value % 1 == 0
end

local function isValidRaidId(value: any): boolean
    return type(value) == "string" and #value > 0 and #value <= 128
end

local function copyGrace(record: any, nowUnix: number): any
    return {
        raidId = record.raidId,
        startedAtUnix = record.startedAtUnix,
        expiresAtUnix = record.expiresAtUnix,
        active = nowUnix < record.expiresAtUnix,
    }
end

local function phaseSnapshot(self: any, serverTimeUnix: number): any
    return {
        phase = self._phase,
        phaseStartedAtUnix = self._phaseStartedAtUnix,
        phaseEndsAtUnix = self._phaseEndsAtUnix,
        raidId = self._raidId,
        revision = self._phaseRevision,
        serverTimeUnix = serverTimeUnix,
    }
end

local function generateRaidId(self: any): string?
    self._raidSequence += 1
    local callOk, value = pcall(self._generateRaidId, self._raidSequence)
    if not callOk or not isValidRaidId(value) then
        self._raidSequence -= 1
        return nil
    end
    return value
end

local function advanceTo(self: any, phase: string, startedAtUnix: number, serverTimeUnix: number)
    if NEXT_PHASE[self._phase] ~= phase or startedAtUnix ~= self._phaseEndsAtUnix then
        return false, "InvalidTransition"
    end

    if phase == "RAID" then
        local nextRaidId = generateRaidId(self)
        if nextRaidId == nil then
            return false, "RaidIdUnavailable"
        end
        self._raidId = nextRaidId
        table.clear(self._arrivalGraceByUserId)
    end

    self._phase = phase
    self._phaseStartedAtUnix = startedAtUnix
    self._phaseEndsAtUnix = startedAtUnix + self._phaseDurations[phase]
    self._phaseRevision += 1
    self.Changed:Fire(phaseSnapshot(self, serverTimeUnix))
    return true, nil
end

function RaidService.new(options: any?)
    options = options or {}
    local config = options.config or RaidConfig
    assert(type(config) == "table", "config must be a table")
    assert(type(config.PHASE_ORDER) == "table", "config phase order is required")
    assert(type(config.PHASE_DURATIONS_SECONDS) == "table", "phase durations are required")
    assert(
        isFiniteNumber(config.ARRIVAL_GRACE_SECONDS)
            and config.ARRIVAL_GRACE_SECONDS > 0
            and config.ARRIVAL_GRACE_SECONDS % 1 == 0,
        "arrival grace must be a positive integer"
    )

    local phaseOrder = {}
    local phaseDurations = {}
    for index, phase in config.PHASE_ORDER do
        assert(type(phase) == "string" and NEXT_PHASE[phase] ~= nil, "config has an invalid phase")
        assert(phaseOrder[index - 1] ~= phase, "config has a repeated phase")
        local duration = config.PHASE_DURATIONS_SECONDS[phase]
        assert(
            isFiniteNumber(duration) and duration > 0 and duration % 1 == 0,
            "each phase needs a positive integer duration"
        )
        phaseOrder[index] = phase
        phaseDurations[phase] = duration
    end
    assert(#phaseOrder == 5, "Raid cycle must define exactly five phases")
    for index, phase in phaseOrder do
        local nextPhase = phaseOrder[index % #phaseOrder + 1]
        assert(NEXT_PHASE[phase] == nextPhase, "config phase order does not match the locked cycle")
    end

    local clock = options.clock or os.time
    assert(type(clock) == "function", "clock must be a function")
    local nowUnix = options.initialPhaseStartedAtUnix or clock()
    assert(isFiniteNumber(nowUnix), "initial phase timestamp must be finite")
    local initialPhase = options.initialPhase or "PEACE"
    assert(phaseDurations[initialPhase] ~= nil, "initialPhase is invalid")
    local generator = options.generateRaidId
    if generator ~= nil then
        assert(type(generator) == "function", "generateRaidId must be a function")
    else
        generator = function(sequence: number)
            return string.format("raid-%d-%d", math.floor(nowUnix), sequence)
        end
    end

    local self = setmetatable({
        _phase = initialPhase,
        _phaseStartedAtUnix = nowUnix,
        _phaseEndsAtUnix = nowUnix + phaseDurations[initialPhase],
        _raidId = options.raidId,
        _raidSequence = 0,
        _phaseRevision = 0,
        _phaseOrder = phaseOrder,
        _phaseDurations = phaseDurations,
        _arrivalGraceSeconds = config.ARRIVAL_GRACE_SECONDS,
        _arrivalGraceByUserId = {},
        _clock = clock,
        _generateRaidId = generator,
        _heartbeatConnection = nil,
        _started = false,
        Changed = Signal.new(),
    }, RaidService)

    if self._raidId == nil then
        self._raidId = generateRaidId(self)
    end
    assert(isValidRaidId(self._raidId), "initial raid ID is invalid")
    return self
end

function RaidService.getSnapshot(self: any, userId: number?): any
    local now = self._clock()
    self:step(now)
    local snapshot = phaseSnapshot(self, now)
    if isUserId(userId) and self._phase == "RAID" then
        local record = self._arrivalGraceByUserId[userId]
        if record ~= nil and record.raidId == self._raidId then
            snapshot.arrivalGrace = copyGrace(record, now)
        end
    end
    return snapshot
end

function RaidService.step(self: any, nowUnix: number?): (boolean, number?, string?)
    local now = if nowUnix ~= nil then nowUnix else self._clock()
    if not isFiniteNumber(now) or now < self._phaseStartedAtUnix then
        return false, nil, "InvalidTimestamp"
    end

    local transitions = 0
    while self._phaseEndsAtUnix ~= nil and now >= self._phaseEndsAtUnix do
        local nextPhase = NEXT_PHASE[self._phase]
        local boundary = self._phaseEndsAtUnix
        local advanced, failure = advanceTo(self, nextPhase, boundary, now)
        if not advanced then
            return false, transitions, failure
        end
        transitions += 1
    end
    return true, transitions, nil
end

function RaidService.start(self: any, heartbeat: any): (boolean, string?)
    if self._started then
        return false, "AlreadyStarted"
    end
    if heartbeat == nil or type(heartbeat.Connect) ~= "function" then
        return false, "InvalidHeartbeat"
    end
    local stepped, _, failure = self:step()
    if not stepped then
        return false, failure
    end
    self._heartbeatConnection = heartbeat:Connect(function()
        local ok, _, stepError = self:step()
        if not ok and stepError ~= nil then
            warn(string.format("[RaidService] Clock step failed: %s", stepError))
        end
    end)
    self._started = true
    return true, nil
end

function RaidService.stop(self: any)
    if self._heartbeatConnection ~= nil then
        self._heartbeatConnection:Disconnect()
        self._heartbeatConnection = nil
    end
    self._started = false
end

function RaidService.onOperationalChanged(
    self: any,
    userId: number,
    isOperational: boolean,
    joinedDuringRaidId: string?
): (any?, string?)
    if not isUserId(userId) or type(isOperational) ~= "boolean" then
        return nil, "InvalidPlayer"
    end
    if not isOperational then
        return nil, nil
    end

    local now = self._clock()
    local stepped, _, stepError = self:step(now)
    if not stepped then
        return nil, stepError
    end
    if self._phase ~= "RAID" or joinedDuringRaidId ~= self._raidId then
        return nil, "Unavailable"
    end

    local current = self._arrivalGraceByUserId[userId]
    if current ~= nil and current.raidId == self._raidId then
        return copyGrace(current, now), nil
    end

    local record = {
        raidId = self._raidId,
        startedAtUnix = now,
        expiresAtUnix = now + self._arrivalGraceSeconds,
    }
    self._arrivalGraceByUserId[userId] = record
    return copyGrace(record, now), nil
end

function RaidService.getArrivalGrace(self: any, userId: number): any?
    if not isUserId(userId) then
        return nil
    end
    local now = self._clock()
    local stepped = self:step(now)
    if not stepped or self._phase ~= "RAID" then
        return nil
    end
    local record = self._arrivalGraceByUserId[userId]
    if record == nil or record.raidId ~= self._raidId then
        return nil
    end
    return copyGrace(record, now)
end

function RaidService.isArrivalGraceActive(self: any, userId: number): boolean
    local grace = self:getArrivalGrace(userId)
    return grace ~= nil and grace.active
end

return table.freeze(RaidService)
