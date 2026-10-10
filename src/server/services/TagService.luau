-- Validates Tag range and timing, then asks TheftService to cancel or drop its attempt.

local RaidConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.RaidConfig)
    else require("../../shared/config/RaidConfig")
local Protocol = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.network.Protocol)
    else require("../../shared/network/Protocol")

local TagService = {}
TagService.__index = TagService

local function isFinite(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function coordinates(position: any): (number?, number?, number?)
    if position == nil then
        return nil, nil, nil
    end
    local ok, x, y, z = pcall(function()
        return position.X or position.x, position.Y or position.y, position.Z or position.z
    end)
    if not ok or not isFinite(x) or not isFinite(y) or not isFinite(z) then
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

local function defaultGetPosition(player: any): any?
    local character = if player ~= nil then player.Character else nil
    if character == nil then
        return nil
    end
    local root = if type(character.FindFirstChild) == "function"
        then character:FindFirstChild("HumanoidRootPart")
        else character.HumanoidRootPart
    return if root ~= nil then root.Position else nil
end

local function defaultGetHumanoid(player: any): any?
    local character = if player ~= nil then player.Character else nil
    if character == nil then
        return nil
    end
    if type(character.FindFirstChildOfClass) == "function" then
        return character:FindFirstChildOfClass("Humanoid")
    end
    return character.Humanoid
end

function TagService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.raidService) == "table", "raidService is required")
    assert(type(options.theftService) == "table", "theftService is required")
    assert(type(options.getPlayer) == "function", "getPlayer is required")
    assert(type(options.isOperational) == "function", "isOperational is required")
    return setmetatable({
        _raidService = options.raidService,
        _theftService = options.theftService,
        _getPlayer = options.getPlayer,
        _getPlayerPosition = options.getPlayerPosition or defaultGetPosition,
        _getHumanoid = options.getHumanoid or defaultGetHumanoid,
        _isOperational = options.isOperational,
        _clock = options.clock or os.clock,
        _emitToUser = options.emitToUser,
        _tagCooldowns = {},
        _tagImmunity = {},
        _staggers = {},
        _connections = {},
        _started = false,
    }, TagService)
end

function TagService._getPosition(self: any, userId: number): any?
    local player = self._getPlayer(userId)
    if player == nil then
        return nil
    end
    local ok, position = pcall(self._getPlayerPosition, player, userId)
    return if ok then position else nil
end

function TagService._getHumanoidForUser(self: any, userId: number): any?
    local player = self._getPlayer(userId)
    if player == nil then
        return nil
    end
    local ok, humanoid = pcall(self._getHumanoid, player, userId)
    return if ok then humanoid else nil
end

function TagService._isOperationalForUser(self: any, userId: number): boolean
    local player = self._getPlayer(userId)
    return player ~= nil and self._isOperational(player, userId) == true
end

function TagService._emit(self: any, userId: number, data: any)
    if self._emitToUser ~= nil then
        pcall(self._emitToUser, userId, Protocol.DomainEventNames.TagResolved, data)
    end
end

function TagService.isStaggered(self: any, userId: number, raidId: string?): boolean
    local stagger = self._staggers[userId]
    return type(stagger) == "table"
        and (raidId == nil or stagger.raidId == raidId)
        and stagger.endsAt > self._clock()
end

function TagService._applyStagger(self: any, userId: number, raidId: string, endsAt: number)
    local humanoid = self:_getHumanoidForUser(userId)
    if humanoid == nil then
        self._staggers[userId] = { raidId = raidId, endsAt = endsAt, movement = nil }
        return
    end
    local movement = {
        humanoid = humanoid,
        walkSpeed = humanoid.WalkSpeed,
        jumpPower = humanoid.JumpPower,
        jumpHeight = humanoid.JumpHeight,
        useJumpPower = humanoid.UseJumpPower,
    }
    self._staggers[userId] = { raidId = raidId, endsAt = endsAt, movement = movement }
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0
end

function TagService.tag(self: any, defenderUserId: number, targetUserId: number): (any?, string?)
    if
        type(defenderUserId) ~= "number"
        or defenderUserId <= 0
        or defenderUserId % 1 ~= 0
        or type(targetUserId) ~= "number"
        or targetUserId <= 0
        or targetUserId % 1 ~= 0
    then
        return nil, "InvalidRequest"
    end
    local raid = self._raidService:getSnapshot()
    if raid.phase ~= "RAID" then
        return nil, "WrongPhase"
    end
    if defenderUserId == targetUserId then
        return { success = false, result = "Miss" }, nil
    end
    local now = self._clock()
    local cooldown = self._tagCooldowns[defenderUserId]
    if cooldown ~= nil and cooldown.raidId == raid.raidId and now < cooldown.endsAt then
        return nil, "RateLimited"
    end
    if self:isStaggered(defenderUserId, raid.raidId) then
        return nil, "Locked"
    end
    local targetInfo = self._theftService:getTagTargetInfo(targetUserId)
    if
        targetInfo == nil
        or not self:_isOperationalForUser(defenderUserId)
        or not self:_isOperationalForUser(targetUserId)
    then
        return { success = false, result = "Miss" }, nil
    end
    local separation = distance(self:_getPosition(defenderUserId), self:_getPosition(targetUserId))
    if separation == nil or separation > RaidConfig.TAG_RANGE_STUDS then
        return { success = false, result = "Miss" }, nil
    end
    local immunity = self._tagImmunity[targetUserId]
    if immunity ~= nil and immunity.raidId == raid.raidId and now < immunity.endsAt then
        return { success = false, result = "Miss" }, nil
    end
    local result, resolveError = self._theftService:resolveTag(targetUserId, targetInfo.attemptId)
    if result == nil then
        return nil, resolveError or "Conflict"
    end
    self._tagCooldowns[defenderUserId] = {
        raidId = raid.raidId,
        endsAt = now + RaidConfig.TAG_COOLDOWN_SECONDS,
    }
    self._tagImmunity[targetUserId] = {
        raidId = raid.raidId,
        endsAt = now + RaidConfig.TAG_IMMUNITY_SECONDS,
    }
    self:_applyStagger(targetUserId, raid.raidId, now + RaidConfig.TAG_STAGGER_SECONDS)
    local response = { success = true, result = result }
    local eventData = { targetUserId = targetUserId, result = result }
    self:_emit(defenderUserId, eventData)
    self:_emit(targetUserId, eventData)
    return response, nil
end

function TagService.step(self: any, now: number?): (boolean, string?)
    local timestamp = if now ~= nil then now else self._clock()
    if
        type(timestamp) ~= "number"
        or timestamp ~= timestamp
        or timestamp == math.huge
        or timestamp == -math.huge
    then
        return false, "InvalidTimestamp"
    end
    for userId, stagger in self._staggers do
        if timestamp >= stagger.endsAt then
            local movement = stagger.movement
            if movement ~= nil and movement.humanoid == self:_getHumanoidForUser(userId) then
                movement.humanoid.WalkSpeed = movement.walkSpeed
                movement.humanoid.JumpPower = movement.jumpPower
                movement.humanoid.JumpHeight = movement.jumpHeight
                movement.humanoid.UseJumpPower = movement.useJumpPower
            end
            self._staggers[userId] = nil
        end
    end
    return true, nil
end

function TagService.onPlayerRemoving(self: any, userId: number)
    self._tagCooldowns[userId] = nil
    self._tagImmunity[userId] = nil
    local stagger = self._staggers[userId]
    if stagger ~= nil and stagger.movement ~= nil then
        local movement = stagger.movement
        if movement.humanoid == self:_getHumanoidForUser(userId) then
            movement.humanoid.WalkSpeed = movement.walkSpeed
            movement.humanoid.JumpPower = movement.jumpPower
            movement.humanoid.JumpHeight = movement.jumpHeight
            movement.humanoid.UseJumpPower = movement.useJumpPower
        end
    end
    self._staggers[userId] = nil
end

function TagService.start(self: any, heartbeat: any): (boolean, string?)
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
                warn(string.format("[Tag] Step failed: %s", tostring(failure)))
            end
        end)
    )
    self._started = true
    return true, nil
end

function TagService.stop(self: any)
    for _, connection in self._connections do
        if connection ~= nil then
            connection:Disconnect()
        end
    end
    table.clear(self._connections)
    for userId in self._staggers do
        self:onPlayerRemoving(userId)
    end
    self._started = false
end

return table.freeze(TagService)
