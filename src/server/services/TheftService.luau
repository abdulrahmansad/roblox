-- Owns Raid theft, carry, Tag, drop, recovery, and journaled bank decisions.

local RaidConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.RaidConfig)
    else require("../../shared/config/RaidConfig")
local Protocol = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.network.Protocol)
    else require("../../shared/network/Protocol")
local MutationConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.MutationConfig)
    else require("../../shared/config/MutationConfig")
local PLAYER_ATTRIBUTES = Protocol.PlayerAttributeNames

local TheftService = {}
TheftService.__index = TheftService

local function coordinates(position: any): (number?, number?, number?)
    if position == nil then
        return nil, nil, nil
    end
    local ok, x, y, z = pcall(function()
        return position.X or position.x, position.Y or position.y, position.Z or position.z
    end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil, nil, nil
    end
    return x, y, z
end

local function distance(left: any, right: any): number?
    local lx, ly, lz = coordinates(left)
    local rx, ry, rz = coordinates(right)
    if lx == nil or ly == nil or lz == nil or rx == nil or ry == nil or rz == nil then
        return nil
    end
    local dx, dy, dz = lx - rx, ly - ry, lz - rz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function copyPosition(position: any): any?
    local x, y, z = coordinates(position)
    if x == nil or y == nil or z == nil then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getCharacter(player: any): any?
    return if player ~= nil then player.Character else nil
end

local function defaultGetPosition(player: any): any?
    local character = getCharacter(player)
    if character == nil then
        return nil
    end
    local root = if type(character.FindFirstChild) == "function"
        then character:FindFirstChild("HumanoidRootPart")
        else character.HumanoidRootPart
    return if root ~= nil then root.Position else nil
end

local function defaultGetHumanoid(player: any): any?
    local character = getCharacter(player)
    if character == nil then
        return nil
    end
    if type(character.FindFirstChildOfClass) == "function" then
        return character:FindFirstChildOfClass("Humanoid")
    end
    return character.Humanoid
end

local function getAttemptForUser(self: any, userId: number): any?
    local attemptId = self._activeAttemptByThief[userId]
    return if attemptId ~= nil then self._attempts[attemptId] else nil
end

function TheftService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.raidService) == "table", "raidService is required")
    assert(type(options.playerDataService) == "table", "playerDataService is required")
    assert(type(options.creatureService) == "table", "creatureService is required")
    assert(type(options.baseService) == "table", "baseService is required")
    assert(type(options.transferJournalStore) == "table", "transferJournalStore is required")
    assert(type(options.getPlayer) == "function", "getPlayer is required")
    assert(type(options.generateAttemptId) == "function", "generateAttemptId is required")

    return setmetatable({
        _raidService = options.raidService,
        _playerDataService = options.playerDataService,
        _creatureService = options.creatureService,
        _baseService = options.baseService,
        _transferJournalStore = options.transferJournalStore,
        _getPlayer = options.getPlayer,
        _getPlayerPosition = options.getPlayerPosition or defaultGetPosition,
        _getHumanoid = options.getHumanoid or defaultGetHumanoid,
        _isOperational = options.isOperational,
        _generateAttemptId = options.generateAttemptId,
        _isStaggered = options.isStaggered,
        _clock = options.clock or os.clock,
        _unixClock = options.unixClock or os.time,
        _schedule = options.schedule or function(callback)
            task.spawn(callback)
        end,
        _emitToUser = options.emitToUser,
        _attempts = {},
        _activeAttemptByThief = {},
        _activeOwnerLocks = {},
        _activeCreatureLocks = {},
        _raidStateByThief = {},
        _raidOwnerLosses = {},
        _connections = {},
        _raidId = nil,
        _inFlightCommits = 0,
        _closing = false,
        _started = false,
    }, TheftService)
end

function TheftService._emit(self: any, userId: number, event: string, data: any)
    if self._emitToUser ~= nil then
        pcall(self._emitToUser, userId, event, data)
    end
end

function TheftService._emitState(self: any, attempt: any)
    local data = {
        attemptId = attempt.id,
        state = attempt.state,
        thiefUserId = attempt.thiefUserId,
        ownerUserId = attempt.ownerUserId,
        creatureId = attempt.creature.id,
        serverTimeUnix = self._unixClock(),
    }
    self:_emit(attempt.thiefUserId, Protocol.DomainEventNames.TheftStateChanged, data)
    self:_emit(attempt.ownerUserId, Protocol.DomainEventNames.TheftStateChanged, data)
end

function TheftService._getPosition(self: any, userId: number): any?
    local player = self._getPlayer(userId)
    if player == nil then
        return nil
    end
    local ok, position = pcall(self._getPlayerPosition, player, userId)
    return if ok then position else nil
end

function TheftService._getHumanoidForUser(self: any, userId: number): any?
    local player = self._getPlayer(userId)
    if player == nil then
        return nil
    end
    local ok, humanoid = pcall(self._getHumanoid, player, userId)
    return if ok then humanoid else nil
end

function TheftService._isOperationalForUser(self: any, userId: number): boolean
    local player = self._getPlayer(userId)
    if player == nil then
        return false
    end
    if self._isOperational ~= nil then
        return self._isOperational(player, userId) == true
    end
    return self._baseService:isOperational(player) == true and self:_getPosition(userId) ~= nil
end

function TheftService._isPresentWithBase(self: any, userId: number): boolean
    local player = self._getPlayer(userId)
    local base = self._baseService:getForUserId(userId)
    return player ~= nil and base ~= nil and base.ownerUserId == userId
end

function TheftService._currentRaid(self: any): any
    return self._raidService:getSnapshot()
end

function TheftService._newRaidState(self: any, userId: number, raidId: string): any
    local state = self._raidStateByThief[userId]
    if state == nil or state.raidId ~= raidId then
        state = {
            raidId = raidId,
            attempts = 0,
            attemptedCreatureIds = {},
            banked = false,
            catalystGranted = false,
        }
        self._raidStateByThief[userId] = state
    end
    return state
end

function TheftService._checkPhase(self: any): (any?, string?)
    if self._closing then
        return nil, "Unavailable"
    end
    local raid = self:_currentRaid()
    if raid.phase ~= "RAID" then
        return nil, "WrongPhase"
    end
    return raid, nil
end

function TheftService._isNearPosition(
    self: any,
    userId: number,
    targetPosition: any,
    range: number
): boolean
    local current = self:_getPosition(userId)
    local separation = distance(current, targetPosition)
    return separation ~= nil and separation <= range
end

function TheftService._isGraceProtected(self: any, userId: number): boolean
    return self._raidService:isArrivalGraceActive(userId)
end

function TheftService._attemptStationary(self: any, userId: number, anchor: any): boolean
    local separation = distance(self:_getPosition(userId), anchor)
    return separation ~= nil and separation <= RaidConfig.STATIONARY_TOLERANCE_STUDS
end

function TheftService._setCarryMovement(self: any, attempt: any, enabled: boolean)
    local userId = attempt.thiefUserId
    local player = self._getPlayer(userId)
    local humanoid = self:_getHumanoidForUser(userId)
    if enabled then
        if player ~= nil and type(player.SetAttribute) == "function" then
            player:SetAttribute(PLAYER_ATTRIBUTES.CarryingAttemptId, attempt.id)
            player:SetAttribute(PLAYER_ATTRIBUTES.CarriedCreatureId, attempt.creature.id)
        end
        if humanoid ~= nil and attempt.movementState == nil then
            attempt.movementState = {
                humanoid = humanoid,
                walkSpeed = humanoid.WalkSpeed,
                jumpPower = humanoid.JumpPower,
                jumpHeight = humanoid.JumpHeight,
                useJumpPower = humanoid.UseJumpPower,
            }
            humanoid.WalkSpeed *= RaidConfig.CARRY_WALK_SPEED_MULTIPLIER
            humanoid.JumpPower = 0
            humanoid.JumpHeight = 0
            pcall(function()
                humanoid:UnequipTools()
            end)
        end
    elseif player ~= nil and type(player.SetAttribute) == "function" then
        player:SetAttribute(PLAYER_ATTRIBUTES.CarryingAttemptId, nil)
        player:SetAttribute(PLAYER_ATTRIBUTES.CarriedCreatureId, nil)
    end
    if not enabled and attempt.movementState ~= nil then
        local movement = attempt.movementState
        attempt.movementState = nil
        if movement.humanoid == self:_getHumanoidForUser(userId) then
            movement.humanoid.WalkSpeed = movement.walkSpeed
            movement.humanoid.JumpPower = movement.jumpPower
            movement.humanoid.JumpHeight = movement.jumpHeight
            movement.humanoid.UseJumpPower = movement.useJumpPower
        end
    end
end

function TheftService._unequipTools(self: any, userId: number)
    local humanoid = self:_getHumanoidForUser(userId)
    if humanoid ~= nil then
        pcall(function()
            humanoid:UnequipTools()
        end)
    end
end

function TheftService._releaseLocks(self: any, attempt: any)
    if self._activeAttemptByThief[attempt.thiefUserId] == attempt.id then
        self._activeAttemptByThief[attempt.thiefUserId] = nil
    end
    if self._activeOwnerLocks[attempt.ownerUserId] == attempt.id then
        self._activeOwnerLocks[attempt.ownerUserId] = nil
    end
    local creatureKey = tostring(attempt.ownerUserId) .. ":" .. attempt.creature.id
    if self._activeCreatureLocks[creatureKey] == attempt.id then
        self._activeCreatureLocks[creatureKey] = nil
    end
    self._creatureService:releaseReservation(attempt.ownerUserId, attempt.creature.id, attempt.id)
end

function TheftService._returnAttempt(self: any, attempt: any, reason: string)
    if attempt.state == "RETURNED" or attempt.state == "BANKED" then
        return false
    end
    self:_setCarryMovement(attempt, false)
    if attempt.state == "COMMITTING" then
        return false
    end
    attempt.state = "RETURNED"
    attempt.bankHold = nil
    attempt.recoveryHold = nil
    attempt.terminalReason = reason
    attempt.terminalAt = self._clock()
    self:_releaseLocks(attempt)
    self:_emitState(attempt)
    return true
end

function TheftService._cancelBankHold(self: any, attempt: any)
    if attempt.state == "BANKING" then
        attempt.state = "CARRIED"
        attempt.bankHold = nil
        self:_emitState(attempt)
    end
end

function TheftService._targetEligible(
    self: any,
    thiefUserId: number,
    ownerUserId: number,
    targetCreatureId: string,
    raid: any
): (any?, any?, string?)
    if thiefUserId == ownerUserId then
        return nil, nil, "InvalidRequest"
    end
    if
        not self:_isOperationalForUser(thiefUserId) or not self:_isOperationalForUser(ownerUserId)
    then
        return nil, nil, "Unavailable"
    end
    if self:_isGraceProtected(thiefUserId) or self:_isGraceProtected(ownerUserId) then
        return nil, nil, "Locked"
    end
    if self._activeOwnerLocks[ownerUserId] ~= nil then
        return nil, nil, "Locked"
    end
    if self._raidOwnerLosses[ownerUserId] == raid.raidId then
        return nil, nil, "Locked"
    end
    local profile = self._playerDataService:getSnapshot(ownerUserId)
    if profile == nil then
        return nil, nil, "Unavailable"
    end
    if
        self._creatureService:isProtectedFromTheft(profile, targetCreatureId, raid.serverTimeUnix)
    then
        return nil, nil, "Locked"
    end
    local creature = self._creatureService:findInProfile(profile, targetCreatureId)
    if creature == nil then
        return nil, nil, "NotOwner"
    end
    if not self._creatureService:isOnStand(ownerUserId, targetCreatureId) then
        return nil, nil, "Unavailable"
    end
    local position = self._baseService:getCreatureDisplayPosition(ownerUserId, targetCreatureId)
    if
        position == nil
        or not self:_isNearPosition(thiefUserId, position, RaidConfig.THEFT_RANGE_STUDS)
    then
        return nil, nil, "OutOfRange"
    end
    return profile, creature, nil
end

function TheftService.beginTheft(
    self: any,
    thiefUserId: number,
    targetCreatureId: string
): (any?, string?)
    local raid, phaseError = self:_checkPhase()
    if raid == nil then
        return nil, phaseError
    end
    if
        type(thiefUserId) ~= "number"
        or thiefUserId <= 0
        or thiefUserId % 1 ~= 0
        or type(targetCreatureId) ~= "string"
        or #targetCreatureId < 1
        or #targetCreatureId > 128
    then
        return nil, "InvalidRequest"
    end
    if not self:_isOperationalForUser(thiefUserId) then
        return nil, "Unavailable"
    end
    if self._isStaggered ~= nil and self._isStaggered(thiefUserId, raid.raidId) == true then
        return nil, "Locked"
    end
    if self:_isGraceProtected(thiefUserId) then
        return nil, "Locked"
    end
    if self._activeAttemptByThief[thiefUserId] ~= nil then
        return nil, "Locked"
    end
    local raidState = self:_newRaidState(thiefUserId, raid.raidId)
    if raidState.banked or raidState.attempts >= 2 then
        return nil, "Locked"
    end
    if raidState.attemptedCreatureIds[targetCreatureId] then
        return nil, "Locked"
    end
    local targetOwnerId = nil
    for _, base in self._baseService:getAll() do
        if base.ownerUserId ~= nil then
            for _, creature in base.creatures do
                if creature.id == targetCreatureId then
                    targetOwnerId = base.ownerUserId
                    break
                end
            end
        end
        if targetOwnerId ~= nil then
            break
        end
    end
    if targetOwnerId == nil then
        return nil, "NotOwner"
    end
    local profile, creature, eligibilityError =
        self:_targetEligible(thiefUserId, targetOwnerId, targetCreatureId, raid)
    if profile == nil or creature == nil then
        return nil, eligibilityError or "Unavailable"
    end
    local thiefProfile = self._playerDataService:getSnapshot(thiefUserId)
    if thiefProfile == nil then
        return nil, "Unavailable"
    end
    local reserved = 0
    for userId, attemptId in self._activeAttemptByThief do
        local active = self._attempts[attemptId]
        if
            userId == thiefUserId
            and active ~= nil
            and active.state ~= "RETURNED"
            and active.state ~= "BANKED"
        then
            reserved += 1
        end
    end
    if #thiefProfile.creatures + reserved >= thiefProfile.slotCapacity then
        return nil, "CapacityFull"
    end
    if self._activeCreatureLocks[tostring(targetOwnerId) .. ":" .. targetCreatureId] ~= nil then
        return nil, "Locked"
    end
    local attemptId = self._generateAttemptId()
    if
        type(attemptId) ~= "string"
        or #attemptId < 1
        or #attemptId > 128
        or self._attempts[attemptId] ~= nil
    then
        return nil, "Unavailable"
    end
    if not self._creatureService:reserve(targetOwnerId, targetCreatureId, attemptId) then
        return nil, "Locked"
    end
    local startedAt = self._clock()
    local thiefPosition = copyPosition(self:_getPosition(thiefUserId))
    if thiefPosition == nil then
        self._creatureService:releaseReservation(targetOwnerId, targetCreatureId, attemptId)
        return nil, "Unavailable"
    end
    local attempt = {
        id = attemptId,
        raidId = raid.raidId,
        raidEndsAtUnix = raid.phaseEndsAtUnix,
        thiefUserId = thiefUserId,
        ownerUserId = targetOwnerId,
        creature = creature,
        state = "CHANNELING",
        channelStartedAt = startedAt,
        channelAnchor = thiefPosition,
        bankHold = nil,
        recoveryHold = nil,
    }
    self._attempts[attemptId] = attempt
    self._activeAttemptByThief[thiefUserId] = attemptId
    self._activeOwnerLocks[targetOwnerId] = attemptId
    self._activeCreatureLocks[tostring(targetOwnerId) .. ":" .. targetCreatureId] = attemptId
    raidState.attempts += 1
    raidState.attemptedCreatureIds[targetCreatureId] = true
    self:_emitState(attempt)
    return {
        attemptId = attemptId,
        targetUserId = targetOwnerId,
        channelEndsAt = self._unixClock() + RaidConfig.THEFT_CHANNEL_SECONDS,
    },
        nil
end

function TheftService.cancelTheft(
    self: any,
    thiefUserId: number,
    attemptId: string
): (any?, string?)
    local attempt = self._attempts[attemptId]
    if attempt == nil or attempt.thiefUserId ~= thiefUserId then
        return nil, "NotOwner"
    end
    if attempt.state == "RETURNED" then
        return { attemptId = attemptId, state = "Returned" }, nil
    end
    if attempt.state ~= "CHANNELING" then
        return nil, "Locked"
    end
    self:_returnAttempt(attempt, "Cancelled")
    return { attemptId = attemptId, state = "Returned" }, nil
end

function TheftService.beginBank(self: any, thiefUserId: number, attemptId: string): (any?, string?)
    local raid, phaseError = self:_checkPhase()
    if raid == nil then
        return nil, phaseError
    end
    local attempt = self._attempts[attemptId]
    if attempt == nil or attempt.thiefUserId ~= thiefUserId then
        return nil, "NotOwner"
    end
    if attempt.state ~= "CARRIED" and attempt.state ~= "BANKING" then
        return nil, "Locked"
    end
    if not self:_isOperationalForUser(thiefUserId) then
        return nil, "Unavailable"
    end
    local homePad = self._baseService:getHomePadPosition(thiefUserId)
    if
        homePad == nil
        or not self:_isNearPosition(thiefUserId, homePad, RaidConfig.BANK_RANGE_STUDS)
    then
        return nil, "OutOfRange"
    end
    if attempt.state == "BANKING" then
        return { attemptId = attempt.id, holdStartedAt = attempt.bankHold.startedAtUnix }, nil
    end
    attempt.state = "BANKING"
    attempt.bankHold = {
        startedAt = self._clock(),
        startedAtUnix = self._unixClock(),
        anchor = copyPosition(self:_getPosition(thiefUserId)),
    }
    self:_emitState(attempt)
    return { attemptId = attempt.id, holdStartedAt = attempt.bankHold.startedAtUnix }, nil
end

function TheftService._saveCommittedProfiles(self: any, record: any)
    for _, userId in { record.fromUserId, record.toUserId } do
        if self._playerDataService:getSnapshot(userId) ~= nil then
            local saved = self._playerDataService:save(userId, false)
            if saved then
                local marked, markError =
                    self._transferJournalStore:markApplied(record.transferId, userId)
                if not marked then
                    warn(
                        string.format(
                            "[Theft] Transfer receipt remains pending: %s",
                            tostring(markError)
                        )
                    )
                end
            end
        end
    end
end

function TheftService._finishBankCommit(
    self: any,
    attempt: any,
    record: any,
    raidState: any
): boolean
    local applied, applyError = self._playerDataService:finishTransfer(record)
    if not applied then
        warn(
            string.format(
                "[Theft] Committed transfer needs profile replay: %s",
                tostring(applyError)
            )
        )
        return false
    end

    attempt.state = "BANKED"
    attempt.terminalReason = "Banked"
    attempt.terminalAt = self._clock()
    attempt.bankResult = {
        attemptId = attempt.id,
        creatureId = attempt.creature.id,
        catalystThemeId = record.catalystThemeId,
    }
    attempt.bankHold = nil
    self:_setCarryMovement(attempt, false)
    self:_releaseLocks(attempt)
    raidState.banked = true
    raidState.catalystGranted = true
    self._raidOwnerLosses[attempt.ownerUserId] = attempt.raidId
    self._inFlightCommits = math.max(0, self._inFlightCommits - 1)
    pcall(self._creatureService.syncPlayer, self._creatureService, attempt.ownerUserId)
    pcall(self._creatureService.syncPlayer, self._creatureService, attempt.thiefUserId)
    local thiefProfile = self._playerDataService:getSnapshot(attempt.thiefUserId)
    local catalystId = MutationConfig.CATALYSTS_BY_THEME[record.catalystThemeId]
    self:_emit(attempt.ownerUserId, Protocol.DomainEventNames.CreatureChanged, {
        creatureId = attempt.creature.id,
        change = "Removed",
    })
    self:_emit(attempt.thiefUserId, Protocol.DomainEventNames.CreatureChanged, {
        creature = attempt.creature,
        change = "Added",
    })
    if thiefProfile ~= nil and catalystId ~= nil then
        self:_emit(attempt.thiefUserId, Protocol.DomainEventNames.CatalystChanged, {
            themeId = record.catalystThemeId,
            count = thiefProfile.catalysts[catalystId],
        })
    end
    local scheduleOk, scheduleError = pcall(self._schedule, function()
        self:_saveCommittedProfiles(record)
    end)
    if not scheduleOk then
        warn(
            string.format(
                "[Theft] Could not schedule transfer checkpoint: %s",
                tostring(scheduleError)
            )
        )
    end
    self:_emitState(attempt)
    self:_emit(attempt.thiefUserId, Protocol.DomainEventNames.TheftBanked, attempt.bankResult)
    return true
end

function TheftService._resolveAmbiguousCommit(self: any, attempt: any, record: any, raidState: any)
    local scheduled, scheduleError = pcall(self._schedule, function()
        while attempt.state == "COMMITTING" do
            local records, readError = self._transferJournalStore:getForUser(record.fromUserId)
            local found = nil
            if type(records) == "table" then
                for _, candidate in records do
                    if candidate.transferId == record.transferId then
                        found = candidate
                        break
                    end
                end
            end
            if found ~= nil and found.state == "COMMITTED" then
                if not self:_finishBankCommit(attempt, found, raidState) then
                    task.wait(1)
                end
            else
                if found == nil then
                    local prepared = self._transferJournalStore:prepare(record)
                    if not prepared then
                        task.wait(1)
                        continue
                    end
                end
                local committed = self._transferJournalStore:commit(record.transferId)
                if committed then
                    local committedRecord = table.clone(record)
                    committedRecord.state = "COMMITTED"
                    if not self:_finishBankCommit(attempt, committedRecord, raidState) then
                        task.wait(1)
                    end
                else
                    warn(
                        string.format(
                            "[Theft] Transfer decision still pending: %s",
                            tostring(
                                if type(records) == "table" then "journal retry" else readError
                            )
                        )
                    )
                    task.wait(1)
                end
            end
        end
    end)
    if not scheduled then
        warn(
            string.format(
                "[Theft] Could not schedule journal recovery: %s",
                tostring(scheduleError)
            )
        )
    end
end

function TheftService.completeBank(
    self: any,
    thiefUserId: number,
    attemptId: string,
    catalystThemeId: string
): (any?, string?)
    local raid, phaseError = self:_checkPhase()
    if raid == nil then
        return nil, phaseError
    end
    local attempt = self._attempts[attemptId]
    if attempt == nil or attempt.thiefUserId ~= thiefUserId then
        return nil, "NotOwner"
    end
    if attempt.state == "BANKED" then
        return attempt.bankResult, nil
    end
    if attempt.state ~= "BANKING" or attempt.bankHold == nil then
        return nil, "Locked"
    end
    local raidState = self:_newRaidState(thiefUserId, raid.raidId)
    if raidState.banked then
        return nil, "Locked"
    end
    if
        raid.phaseEndsAtUnix ~= attempt.raidEndsAtUnix
        or self._unixClock() >= attempt.raidEndsAtUnix
    then
        return nil, "Expired"
    end
    if
        not self:_isOperationalForUser(thiefUserId)
        or not self:_isPresentWithBase(attempt.ownerUserId)
    then
        return nil, "Unavailable"
    end
    local homePad = self._baseService:getHomePadPosition(thiefUserId)
    if
        homePad == nil
        or not self:_isNearPosition(thiefUserId, homePad, RaidConfig.BANK_RANGE_STUDS)
        or not self:_attemptStationary(thiefUserId, attempt.bankHold.anchor)
    then
        self:_cancelBankHold(attempt)
        return nil, "OutOfRange"
    end
    if self._clock() - attempt.bankHold.startedAt < RaidConfig.BANK_HOLD_SECONDS then
        return nil, "Locked"
    end
    if self:_isGraceProtected(thiefUserId) or self:_isGraceProtected(attempt.ownerUserId) then
        return nil, "Locked"
    end
    if raidState.catalystGranted then
        return nil, "Locked"
    end

    attempt.state = "COMMITTING"
    attempt.bankCommitAtUnix = self._unixClock()
    self._inFlightCommits += 1
    local record = {
        transferId = attempt.id,
        raidId = attempt.raidId,
        fromUserId = attempt.ownerUserId,
        toUserId = attempt.thiefUserId,
        creature = attempt.creature,
        catalystThemeId = catalystThemeId,
        createdAtUnix = attempt.bankCommitAtUnix,
    }
    local creature, lockError = self._playerDataService:lockTransfer(
        record.transferId,
        record.fromUserId,
        record.toUserId,
        attempt.creature.id,
        catalystThemeId
    )
    if creature == nil then
        attempt.state = "CARRIED"
        self._inFlightCommits -= 1
        return nil, lockError or "Conflict"
    end
    record.creature = creature
    local prepared, prepareError = self._transferJournalStore:prepare(record)
    if not prepared then
        warn(
            string.format(
                "[Theft] Transfer intent could not be prepared: %s",
                tostring(prepareError)
            )
        )
        local aborted, abortError = self._transferJournalStore:abort(record.transferId)
        if not aborted then
            warn(
                string.format(
                    "[Theft] Prepared intent cleanup remains pending: %s",
                    tostring(abortError)
                )
            )
        end
        self._playerDataService:abortTransferLock(
            record.transferId,
            record.fromUserId,
            record.toUserId
        )
        attempt.state = "CARRIED"
        self._inFlightCommits -= 1
        return nil, "ServiceUnavailable"
    end
    local committed, commitError = self._transferJournalStore:commit(record.transferId)
    if not committed then
        local aborted, abortError = self._transferJournalStore:abort(record.transferId)
        if aborted then
            self._playerDataService:abortTransferLock(
                record.transferId,
                record.fromUserId,
                record.toUserId
            )
            attempt.state = "CARRIED"
            self._inFlightCommits -= 1
            return nil, "ServiceUnavailable"
        else
            warn(
                string.format(
                    "[Theft] Transfer decision needs journal replay: %s / %s",
                    tostring(commitError),
                    tostring(abortError)
                )
            )
        end
        self:_resolveAmbiguousCommit(attempt, record, raidState)
        return nil, "ServiceUnavailable"
    end
    record.state = "COMMITTED"
    if not self:_finishBankCommit(attempt, record, raidState) then
        self:_resolveAmbiguousCommit(attempt, record, raidState)
        return nil, "ServiceUnavailable"
    end
    return attempt.bankResult, nil
end

function TheftService.getTagTargetInfo(self: any, targetUserId: number): any?
    local attempt = getAttemptForUser(self, targetUserId)
    if
        attempt == nil
        or (
            attempt.state ~= "CHANNELING"
            and attempt.state ~= "CARRIED"
            and attempt.state ~= "BANKING"
        )
    then
        return nil
    end
    return { attemptId = attempt.id, state = attempt.state }
end

function TheftService.resolveTag(
    self: any,
    targetUserId: number,
    expectedAttemptId: string
): (string?, string?)
    local attempt = getAttemptForUser(self, targetUserId)
    if
        attempt == nil
        or attempt.id ~= expectedAttemptId
        or (
            attempt.state ~= "CHANNELING"
            and attempt.state ~= "CARRIED"
            and attempt.state ~= "BANKING"
        )
    then
        return nil, "Conflict"
    end
    if attempt.state == "CHANNELING" then
        self:_returnAttempt(attempt, "Tagged")
        return "Cancelled", nil
    end
    local thiefPosition = copyPosition(self:_getPosition(targetUserId))
    if thiefPosition == nil then
        return nil, "Unavailable"
    end
    self:_setCarryMovement(attempt, false)
    attempt.state = "DROPPED"
    attempt.dropPosition = thiefPosition
    attempt.dropStartedAt = self._clock()
    attempt.recoveryHold = nil
    attempt.bankHold = nil
    self._activeAttemptByThief[targetUserId] = nil
    self:_emitState(attempt)
    return "Dropped", nil
end

function TheftService.beginRecovery(
    self: any,
    ownerUserId: number,
    attemptId: string
): (any?, string?)
    local raid, phaseError = self:_checkPhase()
    if raid == nil then
        return nil, phaseError
    end
    local attempt = self._attempts[attemptId]
    if attempt == nil or attempt.ownerUserId ~= ownerUserId then
        return nil, "NotOwner"
    end
    if attempt.state ~= "DROPPED" then
        return nil, "Expired"
    end
    if self._clock() - attempt.dropStartedAt >= RaidConfig.RECOVERY_WINDOW_SECONDS then
        self:_returnAttempt(attempt, "RecoveryExpired")
        return { attemptId = attemptId, recovered = false }, nil
    end
    if not self:_isOperationalForUser(ownerUserId) then
        return nil, "Unavailable"
    end
    if
        not self:_isNearPosition(ownerUserId, attempt.dropPosition, RaidConfig.RECOVERY_RANGE_STUDS)
    then
        return nil, "OutOfRange"
    end
    if attempt.recoveryHold == nil then
        attempt.recoveryHold = {
            startedAt = self._clock(),
            anchor = copyPosition(self:_getPosition(ownerUserId)),
        }
        return { attemptId = attemptId, recovered = false, holdStarted = true }, nil
    end
    return { attemptId = attemptId, recovered = false, holdStarted = false }, nil
end

function TheftService._validHold(
    self: any,
    userId: number,
    hold: any,
    range: number,
    targetPosition: any
): boolean
    return hold ~= nil
        and self:_isNearPosition(userId, targetPosition, range)
        and self:_attemptStationary(userId, hold.anchor)
end

function TheftService.step(self: any, now: number?): (boolean, string?)
    local timestamp = if now ~= nil then now else self._clock()
    if not isFinite(timestamp) then
        return false, "InvalidTimestamp"
    end
    local raid = self:_currentRaid()
    for attemptId, attempt in self._attempts do
        if attempt.state == "CHANNELING" then
            if raid.phase ~= "RAID" or raid.raidId ~= attempt.raidId then
                self:_returnAttempt(attempt, "RaidEnded")
            elseif
                not self:_isOperationalForUser(attempt.thiefUserId)
                or not self:_isOperationalForUser(attempt.ownerUserId)
                or self:_isGraceProtected(attempt.thiefUserId)
                or self:_isGraceProtected(attempt.ownerUserId)
            then
                self:_returnAttempt(attempt, "PlayerUnavailable")
            else
                local targetPosition = self._baseService:getCreatureDisplayPosition(
                    attempt.ownerUserId,
                    attempt.creature.id
                )
                if
                    targetPosition == nil
                    or not self:_validHold(
                        attempt.thiefUserId,
                        { anchor = attempt.channelAnchor },
                        RaidConfig.THEFT_RANGE_STUDS,
                        targetPosition
                    )
                then
                    self:_returnAttempt(attempt, "ChannelInterrupted")
                elseif timestamp - attempt.channelStartedAt >= RaidConfig.THEFT_CHANNEL_SECONDS then
                    attempt.state = "CARRIED"
                    attempt.carriedAt = timestamp
                    self:_setCarryMovement(attempt, true)
                    self:_emitState(attempt)
                end
            end
        elseif attempt.state == "CARRIED" or attempt.state == "BANKING" then
            self:_unequipTools(attempt.thiefUserId)
            if
                raid.phase ~= "RAID"
                or raid.raidId ~= attempt.raidId
                or raid.phaseEndsAtUnix ~= attempt.raidEndsAtUnix
                or not self:_isOperationalForUser(attempt.thiefUserId)
                or not self:_isPresentWithBase(attempt.ownerUserId)
            then
                self:_returnAttempt(attempt, "RaidOrPlayerEnded")
            elseif attempt.state == "BANKING" then
                local homePad = self._baseService:getHomePadPosition(attempt.thiefUserId)
                if
                    not self:_validHold(
                        attempt.thiefUserId,
                        attempt.bankHold,
                        RaidConfig.BANK_RANGE_STUDS,
                        homePad
                    )
                then
                    self:_cancelBankHold(attempt)
                end
            end
        elseif attempt.state == "DROPPED" then
            if raid.phase ~= "RAID" or raid.raidId ~= attempt.raidId then
                self:_returnAttempt(attempt, "RaidEnded")
            elseif
                not self:_isOperationalForUser(attempt.ownerUserId)
                or not self:_isOperationalForUser(attempt.thiefUserId)
            then
                self:_returnAttempt(attempt, "PlayerUnavailable")
            elseif timestamp - attempt.dropStartedAt >= RaidConfig.RECOVERY_WINDOW_SECONDS then
                self:_returnAttempt(attempt, "RecoveryExpired")
            elseif attempt.recoveryHold ~= nil then
                if
                    not self:_validHold(
                        attempt.ownerUserId,
                        attempt.recoveryHold,
                        RaidConfig.RECOVERY_RANGE_STUDS,
                        attempt.dropPosition
                    )
                then
                    attempt.recoveryHold = nil
                elseif
                    timestamp - attempt.recoveryHold.startedAt >= RaidConfig.RECOVERY_HOLD_SECONDS
                then
                    self:_returnAttempt(attempt, "Recovered")
                end
            end
        end
        if
            (attempt.state == "BANKED" or attempt.state == "RETURNED")
            and timestamp - (attempt.terminalAt or timestamp) >= 120
        then
            self._attempts[attemptId] = nil
        end
    end
    return true, nil
end

function TheftService.onPhaseChanged(self: any, snapshot: any)
    if snapshot.phase == "RAID" and snapshot.raidId ~= self._raidId then
        self._raidId = snapshot.raidId
        table.clear(self._raidOwnerLosses)
        for userId in self._raidStateByThief do
            self._raidStateByThief[userId] = nil
        end
    end
    if snapshot.phase ~= "RAID" then
        for _, attempt in self._attempts do
            if attempt.state ~= "COMMITTING" then
                self:_returnAttempt(attempt, "RaidEnded")
            end
        end
    end
end

function TheftService.onPlayerRemoving(self: any, userId: number)
    for _, attempt in self._attempts do
        if
            attempt.state ~= "COMMITTING"
            and (attempt.thiefUserId == userId or attempt.ownerUserId == userId)
        then
            self:_returnAttempt(attempt, "PlayerLeft")
        end
    end
end

function TheftService.onOperationalChanged(self: any, userId: number, isOperational: boolean)
    if isOperational then
        return
    end
    for _, attempt in self._attempts do
        if
            attempt.state ~= "COMMITTING"
            and (
                attempt.thiefUserId == userId
                or (
                    attempt.ownerUserId == userId
                    and (attempt.state == "CHANNELING" or attempt.state == "DROPPED")
                )
            )
        then
            self:_returnAttempt(attempt, "CharacterReset")
        end
    end
end

function TheftService.start(self: any, heartbeat: any): (boolean, string?)
    if self._started then
        return false, "AlreadyStarted"
    end
    if heartbeat == nil or type(heartbeat.Connect) ~= "function" then
        return false, "InvalidHeartbeat"
    end
    table.insert(
        self._connections,
        heartbeat:Connect(function()
            local ok, failure = self:step()
            if not ok then
                warn(string.format("[Theft] Step failed: %s", tostring(failure)))
            end
        end)
    )
    if self._raidService.Changed ~= nil then
        table.insert(
            self._connections,
            self._raidService.Changed:Connect(function(snapshot)
                self:onPhaseChanged(snapshot)
            end)
        )
    end
    self._started = true
    return true, nil
end

function TheftService.stop(self: any)
    self._closing = true
    for _, connection in self._connections do
        if connection ~= nil then
            connection:Disconnect()
        end
    end
    table.clear(self._connections)
    for _, attempt in self._attempts do
        if attempt.state ~= "COMMITTING" then
            self:_returnAttempt(attempt, "ServerShutdown")
        end
    end
    self._started = false
end

function TheftService.shutdown(self: any, timeoutSeconds: number?)
    TheftService.stop(self)
    local deadline = os.clock() + (timeoutSeconds or 20)
    while self._inFlightCommits > 0 and os.clock() < deadline do
        task.wait(0.05)
    end
    return self._inFlightCommits == 0
end

return table.freeze(TheftService)
