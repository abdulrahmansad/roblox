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

local function participantUserIds(self: any): { number }
    if self._getPlayerUserIds == nil then
        return {}
    end
    local ok, userIds = pcall(self._getPlayerUserIds)
    if not ok or type(userIds) ~= "table" then
        warn("[RaidService] Could not read players at Raid start.")
        return {}
    end
    return userIds
end

local function defaultSchedule(callback: () -> ())
    callback()
end

local function finalizeParticipation(self: any, userId: number, marker: any, nowUnix: number)
    if self._finalizeFirstRaidParticipation == nil then
        return false
    end
    local ok, finalized, changed, failure = pcall(
        self._finalizeFirstRaidParticipation,
        userId,
        marker.raidId,
        marker.completesAtUnix,
        nowUnix
    )
    if not ok or not finalized then
        self._pendingFirstRaidParticipation[userId] = marker
        self._participationRetryAt[userId] = nowUnix + 5
        warn(
            string.format(
                "[RaidService] First-Raid completion pending for user %d: %s",
                userId,
                tostring(if ok then failure else finalized)
            )
        )
        return false
    end
    self._pendingFirstRaidParticipation[userId] = nil
    self._participationRetryAt[userId] = nil
    if changed == true and type(self._emitAnalytics) == "function" then
        pcall(self._emitAnalytics, userId, "first_raid_completed", {})
    end
    return changed == true
end

local function beginParticipation(
    self: any,
    userId: number,
    raidId: string,
    completesAtUnix: number,
    forceRetry: boolean?,
    participationReason: string?
)
    if self._beginFirstRaidParticipation == nil then
        return false
    end
    local nowUnix = self._clock()
    local pending = self._pendingFirstRaidParticipation[userId]
    if
        forceRetry ~= true
        and pending ~= nil
        and pending.raidId == raidId
        and pending.completesAtUnix == completesAtUnix
        and (self._participationRetryAt[userId] or 0) > nowUnix
    then
        return false
    end
    local marker = { raidId = raidId, completesAtUnix = completesAtUnix }
    local ok, began, existingOrError, failure, created =
        pcall(self._beginFirstRaidParticipation, userId, raidId, completesAtUnix)
    if created == true and type(self._emitAnalytics) == "function" then
        local reason = participationReason
            or self._pendingFirstRaidParticipationReason[userId]
            or "raid_start"
        pcall(self._emitAnalytics, userId, "first_raid_participated", { reason = reason })
    end
    if not ok or not began then
        self._pendingFirstRaidParticipation[userId] = marker
        self._participationRetryAt[userId] = nowUnix + 5
        if not ok or failure ~= nil then
            warn(
                string.format(
                    "[RaidService] First-Raid participation pending for user %d: %s",
                    userId,
                    tostring(if ok then failure or existingOrError else began)
                )
            )
        end
        return false
    end
    self._pendingFirstRaidParticipation[userId] = nil
    self._participationRetryAt[userId] = nil
    self._pendingFirstRaidParticipationReason[userId] = nil
    local persistedMarker = if type(existingOrError) == "table" then existingOrError else marker
    if persistedMarker ~= nil and nowUnix >= persistedMarker.completesAtUnix then
        finalizeParticipation(self, userId, persistedMarker, nowUnix)
    end
    return true
end

local function scheduleParticipation(
    self: any,
    userId: number,
    raidId: string,
    completesAtUnix: number,
    participationReason: string?
)
    local nowUnix = self._clock()
    local pending = self._pendingFirstRaidParticipation[userId]
    if
        pending ~= nil
        and pending.raidId == raidId
        and pending.completesAtUnix == completesAtUnix
        and (self._participationRetryAt[userId] or 0) > nowUnix
    then
        return false
    end
    if self._participationInFlight[userId] == true then
        return false
    end
    self._pendingFirstRaidParticipation[userId] = {
        raidId = raidId,
        completesAtUnix = completesAtUnix,
    }
    if participationReason ~= nil then
        self._pendingFirstRaidParticipationReason[userId] = participationReason
    end
    self._participationRetryAt[userId] = nowUnix + 5
    self._participationInFlight[userId] = true
    local ok, failure = pcall(self._schedule, function()
        beginParticipation(
            self,
            userId,
            raidId,
            completesAtUnix,
            true,
            self._pendingFirstRaidParticipationReason[userId]
        )
        self._participationInFlight[userId] = nil
    end)
    if not ok then
        self._participationInFlight[userId] = nil
        warn(
            string.format("[RaidService] Could not queue participation save: %s", tostring(failure))
        )
        return false
    end
    return true
end

local function scheduleFinalization(self: any, userId: number, marker: any, nowUnix: number)
    if self._participationInFlight[userId] == true then
        return false
    end
    self._pendingFirstRaidParticipation[userId] = marker
    self._participationRetryAt[userId] = nowUnix + 5
    self._participationInFlight[userId] = true
    local ok, failure = pcall(self._schedule, function()
        finalizeParticipation(self, userId, marker, nowUnix)
        self._participationInFlight[userId] = nil
    end)
    if not ok then
        self._participationInFlight[userId] = nil
        warn(string.format("[RaidService] Could not queue completion save: %s", tostring(failure)))
        return false
    end
    return true
end

local function handlePhaseBoundary(self: any, phase: string, phaseStartedAtUnix: number)
    if phase == "RAID" then
        local completesAtUnix = self._phaseEndsAtUnix + self._phaseDurations.RESOLUTION
        for _, userId in participantUserIds(self) do
            if isUserId(userId) then
                scheduleParticipation(self, userId, self._raidId, completesAtUnix, "raid_start")
            end
        end
    elseif phase == "COOLDOWN" then
        for _, userId in participantUserIds(self) do
            if
                isUserId(userId)
                and self._finalizeFirstRaidParticipation ~= nil
                and self._getParticipationMarker ~= nil
            then
                local ok, profile = pcall(self._getParticipationMarker, userId)
                if ok and type(profile) == "table" and profile ~= nil then
                    scheduleFinalization(self, userId, profile, phaseStartedAtUnix)
                end
            end
        end
    end
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
    handlePhaseBoundary(self, phase, startedAtUnix)
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
        _getPlayerUserIds = options.getPlayerUserIds,
        _beginFirstRaidParticipation = options.beginFirstRaidParticipation,
        _finalizeFirstRaidParticipation = options.finalizeFirstRaidParticipation,
        _getParticipationMarker = options.getParticipationMarker,
        _emitAnalytics = options.emitAnalytics,
        _schedule = options.schedule or defaultSchedule,
        _pendingFirstRaidParticipation = {},
        _pendingFirstRaidParticipationReason = {},
        _participationRetryAt = {},
        _participationInFlight = {},
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

    for userId, grace in self._arrivalGraceByUserId do
        if not grace.expiryLogged and grace.expiresAtUnix <= now then
            grace.expiryLogged = true
            local eligible = grace.expiresAtUnix < grace.raidEndsAtUnix
            if type(self._emitAnalytics) == "function" then
                pcall(self._emitAnalytics, userId, "arrival_grace_expired", { eligible = eligible })
            end
            if eligible and self._phase == "RAID" and grace.raidId == self._raidId then
                scheduleParticipation(
                    self,
                    userId,
                    grace.raidId,
                    grace.raidEndsAtUnix + self._phaseDurations.RESOLUTION,
                    "arrival_grace_expired"
                )
            end
        end
    end
    for userId, marker in self._pendingFirstRaidParticipation do
        if (self._participationRetryAt[userId] or 0) <= now then
            scheduleParticipation(
                self,
                userId,
                marker.raidId,
                marker.completesAtUnix,
                self._pendingFirstRaidParticipationReason[userId]
            )
        end
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
        raidEndsAtUnix = self._phaseEndsAtUnix,
        expiryLogged = false,
    }
    self._arrivalGraceByUserId[userId] = record
    if type(self._emitAnalytics) == "function" then
        pcall(self._emitAnalytics, userId, "arrival_grace_started", {})
    end
    return copyGrace(record, now), nil
end

function RaidService.onProfileReady(self: any, userId: number): (boolean, string?)
    if not isUserId(userId) then
        return false, "InvalidPlayer"
    end
    local marker = self._pendingFirstRaidParticipation[userId]
    if marker ~= nil then
        self._participationRetryAt[userId] = nil
        local began = beginParticipation(
            self,
            userId,
            marker.raidId,
            marker.completesAtUnix,
            true,
            self._pendingFirstRaidParticipationReason[userId]
        )
        if not began then
            return false, "ParticipationSavePending"
        end
        if self._clock() >= marker.completesAtUnix then
            local finalized = finalizeParticipation(self, userId, marker, self._clock())
            if not finalized then
                return false, "ParticipationFinalizePending"
            end
        end
    end
    return true, nil
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
