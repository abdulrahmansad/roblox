local SessionService = {}
SessionService.__index = SessionService

local function defaultIsPlayer(player: any): boolean
    return typeof(player) == "Instance" and player:IsA("Player")
end

local function defaultSchedule(callback: () -> ())
    task.spawn(callback)
end

local function defaultSpawnCharacter(_player: any, character: any, base: any): boolean
    local root = character:WaitForChild("HumanoidRootPart", 10)
    if root == nil then
        return false
    end

    character:PivotTo(CFrame.new(base.spawn.x, base.spawn.y, base.spawn.z))
    return true
end

local function defaultLoadProfile(_player: any): boolean
    -- M1 has no persisted profile yet; M2 supplies PlayerDataService here.
    return true
end

local function disconnectAll(connections: { any })
    for _, connection in connections do
        if connection ~= nil and type(connection.Disconnect) == "function" then
            connection:Disconnect()
        end
    end
    table.clear(connections)
end

local function setAttribute(player: any, name: string, value: any)
    if type(player.SetAttribute) == "function" then
        player:SetAttribute(name, value)
    end
end

function SessionService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.baseService) == "table", "baseService is required")
    assert(type(options.raidService) == "table", "raidService is required")
    assert(type(options.baseService.assign) == "function", "baseService.assign is required")
    assert(
        type(options.raidService.getSnapshot) == "function",
        "raidService.getSnapshot is required"
    )

    return setmetatable({
        _baseService = options.baseService,
        _raidService = options.raidService,
        _loadProfile = options.loadProfile or defaultLoadProfile,
        _saveProfile = options.saveProfile,
        _isPlayer = options.isPlayer or defaultIsPlayer,
        _schedule = options.schedule or defaultSchedule,
        _spawnCharacter = options.spawnCharacter or defaultSpawnCharacter,
        _onRejected = options.onRejected,
        _onSessionReady = options.onSessionReady,
        _onSessionEnded = options.onSessionEnded,
        _generateSessionId = options.generateSessionId or function(_player, token)
            return "session-" .. tostring(token)
        end,
        _onOperationalChanged = options.onOperationalChanged,
        _sessions = {},
        _pending = {},
        _connections = {},
        _started = false,
        _players = nil,
        _nextToken = 0,
    }, SessionService)
end

function SessionService._getUserId(self: any, player: any): number?
    if not self._isPlayer(player) then
        return nil
    end
    local userId = player.UserId
    if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
        return nil
    end
    return userId
end

function SessionService._applyPhase(session: any, phase: string)
    session.phase = phase
    setAttribute(session.player, "OddlingsRaidPhase", phase)
end

function SessionService.start(self: any, players: any): (boolean, string?)
    if self._started then
        return false, "AlreadyStarted"
    end
    if players == nil or type(players.GetPlayers) ~= "function" then
        return false, "InvalidPlayersService"
    end

    self._players = players
    self._started = true
    table.insert(
        self._connections,
        players.PlayerAdded:Connect(function(player)
            SessionService.onPlayerAdded(self, player)
        end)
    )
    table.insert(
        self._connections,
        players.PlayerRemoving:Connect(function(player)
            SessionService.onPlayerRemoving(self, player)
        end)
    )
    if self._raidService.Changed ~= nil then
        table.insert(
            self._connections,
            self._raidService.Changed:Connect(function(snapshot)
                SessionService.onPhaseChanged(self, snapshot)
            end)
        )
    end

    for _, player in players:GetPlayers() do
        SessionService.onPlayerAdded(self, player)
    end
    return true, nil
end

function SessionService.onPlayerAdded(self: any, player: any): (boolean, string?)
    local userId = SessionService._getUserId(self, player)
    if userId == nil then
        return false, "InvalidPlayer"
    end
    if self._sessions[userId] ~= nil then
        return true, nil
    end
    if self._pending[userId] ~= nil then
        return true, nil
    end

    self._nextToken += 1
    local token = self._nextToken
    self._pending[userId] = token

    local loadCallOk, profileReady, profileError = pcall(self._loadProfile, player)
    if self._pending[userId] ~= token then
        if loadCallOk and profileReady == true and self._saveProfile ~= nil then
            pcall(self._saveProfile, player)
        end
        return false, "SessionCancelled"
    end
    self._pending[userId] = nil
    if not loadCallOk then
        if self._onRejected ~= nil then
            self._onRejected(player, "ProfileLoadFailed")
        end
        return false, "ProfileLoadFailed"
    end
    if profileReady ~= true then
        local rejectReason = if type(profileError) == "string"
            then profileError
            else "ProfileUnavailable"
        if self._onRejected ~= nil then
            self._onRejected(player, rejectReason)
        end
        return false, rejectReason
    end

    local base, baseError = self._baseService:assign(player)
    if base == nil then
        if self._saveProfile ~= nil then
            pcall(self._saveProfile, player)
        end
        if self._onRejected ~= nil then
            self._onRejected(player, baseError or "ServerFull")
        end
        return false, baseError or "ServerFull"
    end

    local phaseSnapshot = self._raidService:getSnapshot()
    local sessionId = self._generateSessionId(player, token)
    if type(sessionId) ~= "string" or #sessionId < 8 or #sessionId > 128 then
        self._baseService:release(player)
        if self._saveProfile ~= nil then
            pcall(self._saveProfile, player)
        end
        if self._onRejected ~= nil then
            self._onRejected(player, "SessionInitializationFailed")
        end
        return false, "SessionInitializationFailed"
    end
    local session = {
        player = player,
        userId = userId,
        sessionId = sessionId,
        baseId = base.id,
        base = base,
        phase = phaseSnapshot.phase,
        operational = false,
        token = token,
        connections = {},
    }
    self._sessions[userId] = session

    setAttribute(player, "OddlingsBaseId", base.id)
    setAttribute(player, "OddlingsSessionId", sessionId)
    setAttribute(player, "OddlingsOperational", false)
    SessionService._applyPhase(session, phaseSnapshot.phase)

    if self._onSessionReady ~= nil then
        local readyOk, readyResult = pcall(self._onSessionReady, player)
        if not readyOk or readyResult == false then
            self._baseService:release(player)
            self._sessions[userId] = nil
            setAttribute(player, "OddlingsBaseId", nil)
            setAttribute(player, "OddlingsSessionId", nil)
            setAttribute(player, "OddlingsRaidPhase", nil)
            if self._onSessionEnded ~= nil then
                pcall(self._onSessionEnded, player)
            end
            if self._saveProfile ~= nil then
                pcall(self._saveProfile, player)
            end
            if self._onRejected ~= nil then
                self._onRejected(player, "SessionInitializationFailed")
            end
            return false, "SessionInitializationFailed"
        end
    end

    if player.CharacterAdded ~= nil then
        table.insert(
            session.connections,
            player.CharacterAdded:Connect(function(character)
                SessionService.onCharacterAdded(self, player, character)
            end)
        )
    end
    if player.CharacterRemoving ~= nil then
        table.insert(
            session.connections,
            player.CharacterRemoving:Connect(function(character)
                SessionService.onCharacterRemoving(self, player, character)
            end)
        )
    end

    if player.Character ~= nil then
        SessionService.onCharacterAdded(self, player, player.Character)
    end
    return true, nil
end

function SessionService.onCharacterAdded(self: any, player: any, character: any): boolean
    local userId = SessionService._getUserId(self, player)
    local session = if userId ~= nil then self._sessions[userId] else nil
    if session == nil or character == nil then
        return false
    end

    session.operational = false
    session.character = character
    self._baseService:setOperational(player, false)
    setAttribute(player, "OddlingsOperational", false)
    local token = session.token

    self._schedule(function()
        if
            self._sessions[userId] ~= session
            or session.token ~= token
            or session.character ~= character
            or player.Character ~= character
        then
            return
        end
        local ok, spawnResult = pcall(self._spawnCharacter, player, character, session.base)
        if not ok or spawnResult ~= true then
            return
        end
        if
            self._sessions[userId] ~= session
            or session.token ~= token
            or session.character ~= character
            or player.Character ~= character
        then
            return
        end

        session.operational = true
        self._baseService:setOperational(player, true)
        setAttribute(player, "OddlingsOperational", true)
        if self._onOperationalChanged ~= nil then
            self._onOperationalChanged(player, true, session.base)
        end
    end)
    return true
end

function SessionService.onCharacterRemoving(self: any, player: any, _character: any): boolean
    local userId = SessionService._getUserId(self, player)
    local session = if userId ~= nil then self._sessions[userId] else nil
    if session == nil then
        return false
    end
    if session.character ~= _character then
        return false
    end
    session.character = nil
    session.operational = false
    self._baseService:setOperational(player, false)
    setAttribute(player, "OddlingsOperational", false)
    if self._onOperationalChanged ~= nil then
        self._onOperationalChanged(player, false, session.base)
    end
    return true
end

function SessionService.onPhaseChanged(self: any, snapshot: any): boolean
    if type(snapshot) ~= "table" or type(snapshot.phase) ~= "string" then
        return false
    end
    for _, session in self._sessions do
        SessionService._applyPhase(session, snapshot.phase)
    end
    return true
end

function SessionService.onPlayerRemoving(self: any, player: any): boolean
    local userId = SessionService._getUserId(self, player)
    if userId == nil then
        return false
    end

    local session = self._sessions[userId]
    if session == nil then
        self._pending[userId] = nil
        return false
    end

    session.operational = false
    self._baseService:setOperational(player, false)
    if self._onSessionEnded ~= nil then
        pcall(self._onSessionEnded, player)
    end
    if self._saveProfile ~= nil then
        local saveOk, saved, saveError = pcall(self._saveProfile, player)
        if not saveOk or saved == false then
            warn(
                string.format("[Session] Profile unload deferred: %s", tostring(saveError or saved))
            )
        end
    end
    disconnectAll(session.connections)
    self._baseService:release(player)
    self._sessions[userId] = nil
    setAttribute(player, "OddlingsBaseId", nil)
    setAttribute(player, "OddlingsSessionId", nil)
    setAttribute(player, "OddlingsOperational", false)
    setAttribute(player, "OddlingsRaidPhase", nil)
    return true
end

function SessionService.getSession(self: any, player: any): any?
    local userId = SessionService._getUserId(self, player)
    local session = if userId ~= nil then self._sessions[userId] else nil
    if session == nil then
        return nil
    end
    return {
        userId = session.userId,
        sessionId = session.sessionId,
        baseId = session.baseId,
        phase = session.phase,
        operational = session.operational,
    }
end

function SessionService.stop(self: any)
    disconnectAll(self._connections)
    if self._players ~= nil then
        for _, player in self._players:GetPlayers() do
            SessionService.onPlayerRemoving(self, player)
        end
    end
    self._started = false
    self._players = nil
    table.clear(self._pending)
end

return table.freeze(SessionService)
