-- Central action remote: server identity, phase, rate, proximity, and replay checks.

local Protocol = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.network.Protocol)
    else require("../../shared/network/Protocol")
local EconomyConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.EconomyConfig)
    else require("../../shared/config/EconomyConfig")
local MutationDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.MutationDefinitions)
    else require("../../shared/definitions/MutationDefinitions")

local ActionService = {}
ActionService.__index = ActionService

local ECONOMY_PHASES = { PEACE = true, WARNING = true, COOLDOWN = true }
local MUTATING_ACTIONS = {
    PurchaseCapsule = true,
    SellCreature = true,
    PurchaseSlot = true,
    PurchaseCatalyst = true,
    CompleteTutorialMutation = true,
    StartMutation = true,
    ResolveMutation = true,
    BeginTheft = true,
    CancelTheft = true,
    BankTheft = true,
    Tag = true,
    RecoverDroppedCreature = true,
}
local RAID_ACTIONS = {
    BeginTheft = true,
    CancelTheft = true,
    BankTheft = true,
    Tag = true,
    RecoverDroppedCreature = true,
}
local ACTION_RATE = {
    PurchaseCapsule = { capacity = 2, refillPerSecond = 2 },
    SellCreature = { capacity = 2, refillPerSecond = 2 },
    PurchaseSlot = { capacity = 2, refillPerSecond = 2 },
    PurchaseCatalyst = { capacity = 2, refillPerSecond = 2 },
    CompleteTutorialMutation = { capacity = 1, refillPerSecond = 1 },
    StartMutation = { capacity = 1, refillPerSecond = 1 / 3 },
    ResolveMutation = { capacity = 2, refillPerSecond = 2 },
    GetSnapshot = { capacity = 1, refillPerSecond = 0.5 },
    BeginTheft = { capacity = 1, refillPerSecond = 1 },
    CancelTheft = { capacity = 2, refillPerSecond = 2 },
    BankTheft = { capacity = 2, refillPerSecond = 2 },
    Tag = { capacity = 2, refillPerSecond = 2 },
    RecoverDroppedCreature = { capacity = 2, refillPerSecond = 2 },
}
local MAX_CACHED_REQUESTS = 2_048
local STABLE_ERROR_CODES = {
    InvalidRequest = true,
    RateLimited = true,
    WrongPhase = true,
    OutOfRange = true,
    NotOwner = true,
    InsufficientScrap = true,
    InsufficientCatalyst = true,
    CapacityFull = true,
    Locked = true,
    AlreadyClaimed = true,
    Expired = true,
    Unavailable = true,
    Conflict = true,
    ServiceUnavailable = true,
}

local function cloneValue(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in value do
        copy[key] = cloneValue(child)
    end
    return copy
end

local function valuesEqual(left: any, right: any): boolean
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in left do
        if not valuesEqual(value, right[key]) then
            return false
        end
    end
    for key in right do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function consumeToken(
    buckets: any,
    key: any,
    now: number,
    capacity: number,
    refill: number
): boolean
    local bucket = buckets[key]
    if bucket == nil then
        bucket = { tokens = capacity, updatedAt = now }
        buckets[key] = bucket
    end
    local elapsed = math.max(0, now - bucket.updatedAt)
    bucket.tokens = math.min(capacity, bucket.tokens + elapsed * refill)
    bucket.updatedAt = now
    if bucket.tokens < 1 then
        return false
    end
    bucket.tokens -= 1
    return true
end

local function defaultCanInteract(player: any, kioskPart: any, range: number): boolean
    if kioskPart == nil or typeof(player) ~= "Instance" or not player:IsA("Player") then
        return false
    end
    local character = player.Character
    if character == nil then
        return false
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root == nil then
        return false
    end
    return (root.Position - kioskPart.Position).Magnitude <= range
end

function ActionService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.sessionService) == "table", "sessionService is required")
    assert(type(options.raidService) == "table", "raidService is required")
    assert(type(options.playerDataService) == "table", "playerDataService is required")
    assert(type(options.economyService) == "table", "economyService is required")
    assert(type(options.capsuleService) == "table", "capsuleService is required")
    assert(type(options.mutationService) == "table", "mutationService is required")
    assert(type(options.theftService) == "table", "theftService is required")
    assert(type(options.baseService) == "table", "baseService is required")
    assert(
        type(options.baseService.isOperational) == "function",
        "baseService.isOperational is required"
    )
    assert(options.requestEvent ~= nil, "requestEvent is required")
    assert(options.resultEvent ~= nil, "resultEvent is required")
    assert(options.domainEvent ~= nil, "domainEvent is required")

    local maxCachedRequests = options.maxCachedRequests or MAX_CACHED_REQUESTS
    assert(
        type(maxCachedRequests) == "number" and maxCachedRequests > 0 and maxCachedRequests % 1 == 0,
        "maxCachedRequests must be a positive integer"
    )

    return setmetatable({
        _sessionService = options.sessionService,
        _raidService = options.raidService,
        _playerDataService = options.playerDataService,
        _economyService = options.economyService,
        _capsuleService = options.capsuleService,
        _mutationService = options.mutationService,
        _theftService = options.theftService,
        _tagService = options.tagService or options.theftService,
        _baseService = options.baseService,
        _requestEvent = options.requestEvent,
        _resultEvent = options.resultEvent,
        _domainEvent = options.domainEvent,
        _kioskPart = options.kioskPart,
        _mutationStationPart = options.mutationStationPart,
        _clock = options.clock or os.clock,
        _unixClock = options.unixClock or os.time,
        _canInteract = options.canInteract,
        _isOperationalCheck = options.isOperational,
        _transportBuckets = {},
        _actionBuckets = {},
        _idempotency = {},
        _connections = {},
        _started = false,
        _maxCachedRequests = maxCachedRequests,
        _kioskRange = options.kioskRange or EconomyConfig.KIOSK_RANGE_STUDS,
    }, ActionService)
end

function ActionService.start(self: any): (boolean, string?)
    if self._started then
        return false, "AlreadyStarted"
    end
    if
        self._requestEvent.OnServerEvent == nil
        or type(self._requestEvent.OnServerEvent.Connect) ~= "function"
    then
        return false, "InvalidRequestEvent"
    end
    local connection = self._requestEvent.OnServerEvent:Connect(function(player, request)
        local response = ActionService.handle(self, player, request)
        if response ~= nil then
            pcall(function()
                self._resultEvent:FireClient(player, response)
            end)
        end
    end)
    table.insert(self._connections, connection)
    self._started = true
    return true, nil
end

function ActionService._session(self: any, player: any): any?
    return self._sessionService:getSession(player)
end

function ActionService._response(
    _self: any,
    session: any,
    requestId: string,
    ok: boolean,
    code: string?,
    data: any?,
    profileRevision: number?
): any
    return {
        sessionId = session.sessionId,
        requestId = requestId,
        ok = ok,
        code = code,
        data = data,
        profileRevision = profileRevision,
    }
end

function ActionService._cacheFor(self: any, userId: number, sessionId: string): any
    local entry = self._idempotency[userId]
    if entry == nil or entry.sessionId ~= sessionId then
        entry = { sessionId = sessionId, responses = {}, count = 0, exhausted = false }
        self._idempotency[userId] = entry
    end
    return entry
end

function ActionService._cacheResponse(
    self: any,
    cache: any,
    requestId: string,
    request: any,
    response: any
)
    if cache.count >= self._maxCachedRequests then
        cache.exhausted = true
        return
    end
    cache.responses[requestId] = {
        request = { action = request.action, payload = cloneValue(request.payload) },
        response = cloneValue(response),
    }
    cache.count += 1
    if cache.count >= self._maxCachedRequests then
        cache.exhausted = true
    end
end

function ActionService._isOperational(self: any, player: any): boolean
    if self._isOperationalCheck ~= nil then
        return self._isOperationalCheck(player) == true
    end
    return self._baseService ~= nil and self._baseService:isOperational(player)
end

function ActionService._isNearStation(self: any, player: any, action: string): boolean
    local stationName = if action == "StartMutation"
            or action == "ResolveMutation"
            or action == "CompleteTutorialMutation"
        then "mutation"
        else "commons"
    local stationPart = if stationName == "mutation"
        then self._mutationStationPart
        else self._kioskPart
    if self._canInteract ~= nil then
        return self._canInteract(player, stationName) == true
    end
    return defaultCanInteract(player, stationPart, self._kioskRange)
end

function ActionService._isTransportLimited(self: any, userId: number): boolean
    local now = self._clock()
    local transport = self._transportBuckets[userId]
    if transport == nil then
        transport = {}
        self._transportBuckets[userId] = transport
    end
    if not consumeToken(transport, "all", now, 20, 10) then
        return true
    end
    return false
end

function ActionService._isActionRateLimited(self: any, userId: number, action: string): boolean
    local now = self._clock()
    local limits = ACTION_RATE[action]
    if limits == nil then
        return false
    end
    local perAction = self._actionBuckets[userId]
    if perAction == nil then
        perAction = {}
        self._actionBuckets[userId] = perAction
    end
    return not consumeToken(perAction, action, now, limits.capacity, limits.refillPerSecond)
end

function ActionService._emit(self: any, player: any, event: string, data: any, revision: number)
    self._domainEvent:FireClient(player, {
        event = event,
        revision = revision,
        serverTimeUnix = self._unixClock(),
        data = data,
    })
end

function ActionService._dispatch(
    self: any,
    player: any,
    request: any,
    session: any
): (boolean, any?, string?)
    local raidSnapshot = self._raidService:getSnapshot(session.userId)
    local phase = raidSnapshot.phase
    if RAID_ACTIONS[request.action] == true and phase ~= "RAID" then
        return false, nil, "WrongPhase"
    end
    if
        request.action ~= "GetSnapshot"
        and RAID_ACTIONS[request.action] ~= true
        and ECONOMY_PHASES[phase] ~= true
    then
        return false, nil, "WrongPhase"
    end

    if request.action == "GetSnapshot" then
        local profile = self._playerDataService:getSnapshot(session.userId)
        if profile == nil then
            return false, nil, "Unavailable"
        end
        return true,
            {
                phase = phase,
                raid = {
                    phase = raidSnapshot.phase,
                    phaseStartedAtUnix = raidSnapshot.phaseStartedAtUnix,
                    phaseEndsAtUnix = raidSnapshot.phaseEndsAtUnix,
                    raidId = raidSnapshot.raidId,
                    revision = raidSnapshot.revision,
                    serverTimeUnix = raidSnapshot.serverTimeUnix,
                },
                arrivalGrace = raidSnapshot.arrivalGrace,
                scrap = profile.scrap,
                creatures = profile.creatures,
                slotCapacity = profile.slotCapacity,
                catalysts = profile.catalysts,
                pity = {
                    standardCapsule = profile.standardCapsulePity,
                    mutationRareMissCount = profile.mutationRareMissCount,
                },
                mutationOdds = self._mutationService:getOddsSnapshot(profile.mutationRareMissCount),
                pendingMutation = self._mutationService:getPending(session.userId),
                codex = {
                    speciesIds = profile.discoveredSpeciesIds,
                    mutationFormIds = profile.discoveredMutationFormIds,
                },
                welcomeAvailable = profile.welcomeCreatureId == nil,
                tutorialCompleted = profile.tutorialCompleted,
                hasCompletedFirstRaid = profile.hasCompletedFirstRaid,
            },
            nil
    end

    if not self:_isOperational(player) then
        return false, nil, "Unavailable"
    end
    if RAID_ACTIONS[request.action] ~= true and not self:_isNearStation(player, request.action) then
        return false, nil, "OutOfRange"
    end

    local data, errorCode
    if request.action == "PurchaseCapsule" then
        data, errorCode = self._capsuleService:purchase(session.userId, request.payload.kind, phase)
    elseif request.action == "SellCreature" then
        data, errorCode =
            self._economyService:sellCreature(session.userId, request.payload.creatureId, phase)
    elseif request.action == "PurchaseSlot" then
        data, errorCode =
            self._economyService:purchaseSlot(session.userId, request.payload.targetCapacity, phase)
    elseif request.action == "PurchaseCatalyst" then
        data, errorCode =
            self._economyService:purchaseCatalyst(session.userId, request.payload.themeId, phase)
    elseif request.action == "CompleteTutorialMutation" then
        data, errorCode = self._mutationService:completeTutorialMutation(
            session.userId,
            request.payload.creatureId,
            request.payload.themeId,
            phase
        )
    elseif request.action == "StartMutation" then
        data, errorCode = self._mutationService:startMutation(
            session.userId,
            request.payload.creatureId,
            request.payload.themeId,
            phase
        )
    elseif request.action == "ResolveMutation" then
        data, errorCode = self._mutationService:resolveMutation(
            session.userId,
            request.payload.transactionId,
            request.payload.choice,
            phase
        )
    elseif request.action == "BeginTheft" then
        data, errorCode =
            self._theftService:beginTheft(session.userId, request.payload.targetCreatureId)
    elseif request.action == "CancelTheft" then
        data, errorCode = self._theftService:cancelTheft(session.userId, request.payload.attemptId)
    elseif request.action == "BankTheft" then
        if request.payload.stage == "Begin" then
            data, errorCode =
                self._theftService:beginBank(session.userId, request.payload.attemptId)
        else
            data, errorCode = self._theftService:completeBank(
                session.userId,
                request.payload.attemptId,
                request.payload.catalystThemeId
            )
        end
    elseif request.action == "Tag" then
        data, errorCode = self._tagService:tag(session.userId, request.payload.targetUserId)
    elseif request.action == "RecoverDroppedCreature" then
        data, errorCode =
            self._theftService:beginRecovery(session.userId, request.payload.attemptId)
    else
        return false, nil, "InvalidRequest"
    end

    if data == nil then
        return false, nil, errorCode or "Unavailable"
    end
    return true, data, nil
end

function ActionService.handle(self: any, player: any, request: any): any?
    local session = self:_session(player)
    if session == nil then
        return nil
    end
    local requestId = if type(request) == "table" and type(request.requestId) == "string"
        then request.requestId
        else nil
    if requestId == nil or #requestId < 1 or #requestId > 64 then
        return nil
    end

    if self:_isTransportLimited(session.userId) then
        return self:_response(session, requestId, false, "RateLimited", nil, nil)
    end
    if not Protocol.isValidActionRequest(request) then
        return self:_response(session, requestId, false, "InvalidRequest", nil, nil)
    end
    if request.sessionId ~= session.sessionId then
        return self:_response(session, requestId, false, "Conflict", nil, nil)
    end

    local cache = self:_cacheFor(session.userId, session.sessionId)
    local cached = cache.responses[requestId]
    if cached ~= nil then
        local requestKey = { action = request.action, payload = request.payload }
        if not valuesEqual(cached.request, requestKey) then
            return self:_response(session, requestId, false, "Conflict", nil, nil)
        end
        return cloneValue(cached.response)
    end
    if cache.exhausted then
        return self:_response(session, requestId, false, "Unavailable", nil, nil)
    end
    if self:_isActionRateLimited(session.userId, request.action) then
        return self:_response(session, requestId, false, "RateLimited", nil, nil)
    end

    local ok, data, errorCode = self:_dispatch(player, request, session)
    if errorCode ~= nil and STABLE_ERROR_CODES[errorCode] ~= true then
        errorCode = "Unavailable"
    end
    if
        ok
        and (
            request.action == "PurchaseCapsule"
            or request.action == "PurchaseCatalyst"
            or request.action == "StartMutation"
            or request.action == "CompleteTutorialMutation"
            or (request.action == "ResolveMutation" and data.outcome == "Replaced")
        )
    then
        pcall(function()
            self._economyService:refreshPlayer(session.userId)
        end)
    end
    local revision = self._playerDataService:getRevision(session.userId)
    local response =
        self:_response(session, requestId, ok, if ok then nil else errorCode, data, revision)
    self:_cacheResponse(cache, requestId, request, response)

    if ok and MUTATING_ACTIONS[request.action] then
        pcall(function()
            if request.action == "PurchaseCapsule" then
                self:_emit(player, "CreatureAdded", { creature = data.creature }, revision or 0)
                self:_emit(player, "ScrapChanged", { scrap = data.scrapBalance }, revision or 0)
            elseif request.action == "SellCreature" then
                self:_emit(
                    player,
                    "CreatureRemoved",
                    { creatureId = data.creatureId },
                    revision or 0
                )
                self:_emit(player, "ScrapChanged", { scrap = data.scrapBalance }, revision or 0)
            elseif request.action == "PurchaseSlot" then
                self:_emit(
                    player,
                    "CapacityChanged",
                    { slotCapacity = data.slotCapacity },
                    revision or 0
                )
                self:_emit(player, "ScrapChanged", { scrap = data.scrapBalance }, revision or 0)
            elseif request.action == "PurchaseCatalyst" then
                self:_emit(
                    player,
                    "CatalystChanged",
                    { themeId = data.themeId, count = data.count },
                    revision or 0
                )
                self:_emit(player, "ScrapChanged", { scrap = data.scrapBalance }, revision or 0)
            elseif request.action == "CompleteTutorialMutation" then
                self:_emit(
                    player,
                    "MutationApplied",
                    { creatureId = data.creatureId, formId = data.formId, outcome = "Tutorial" },
                    revision or 0
                )
                self:_emit(
                    player,
                    "TutorialCompleted",
                    { themeId = data.themeId, formId = data.formId },
                    revision or 0
                )
                self:_emit(player, "CodexChanged", { mutationFormId = data.formId }, revision or 0)
            elseif request.action == "StartMutation" then
                self:_emit(player, "MutationRevealed", {
                    transactionId = data.transactionId,
                    revealedFormId = data.revealedFormId,
                    tier = data.tier,
                    oddsSnapshot = data.oddsSnapshot,
                }, revision or 0)
                self:_emit(
                    player,
                    "CatalystChanged",
                    { themeId = data.themeId, count = data.catalystCount },
                    revision or 0
                )
                self:_emit(player, "ScrapChanged", { scrap = data.scrapBalance }, revision or 0)
            elseif request.action == "ResolveMutation" and data.outcome == "Replaced" then
                self:_emit(
                    player,
                    "MutationApplied",
                    { activeFormId = data.activeFormId, outcome = data.outcome },
                    revision or 0
                )
                if data.codexFormAdded then
                    self:_emit(
                        player,
                        "CodexChanged",
                        { mutationFormId = data.activeFormId },
                        revision or 0
                    )
                end
            end
        end)
    end

    if
        ok
        and request.action == "ResolveMutation"
        and data.outcome == "Replaced"
        and type(data.activeFormId) == "string"
    then
        local form = MutationDefinitions[data.activeFormId]
        if form ~= nil and form.tier == "Mythic" then
            pcall(function()
                if type(self._domainEvent.FireAllClients) ~= "function" then
                    return
                end
                local displayName = player.DisplayName
                if type(displayName) ~= "string" or #displayName == 0 then
                    displayName = player.Name
                end
                if type(displayName) ~= "string" or #displayName == 0 then
                    displayName = "A player"
                end
                self._domainEvent:FireAllClients({
                    event = Protocol.DomainEventNames.MythicEquipped,
                    revision = revision or 0,
                    serverTimeUnix = self._unixClock(),
                    data = {
                        playerDisplayName = string.sub(displayName, 1, 32),
                        formId = data.activeFormId,
                    },
                })
            end)
        end
    end

    return response
end

function ActionService.stop(self: any)
    for _, connection in self._connections do
        if connection ~= nil then
            connection:Disconnect()
        end
    end
    table.clear(self._connections)
    self._started = false
end

function ActionService.clearUser(self: any, userId: number)
    self._transportBuckets[userId] = nil
    self._actionBuckets[userId] = nil
    self._idempotency[userId] = nil
end

return table.freeze(ActionService)
