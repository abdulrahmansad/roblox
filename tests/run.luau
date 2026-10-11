local Protocol = require("../src/shared/network/Protocol")
local BaseService = require("../src/server/services/BaseService")
local DevPingService = require("../src/server/services/DevPingService")
local RaidService = require("../src/server/services/RaidService")
local RequestGuard = require("../src/server/security/RequestGuard")
local SessionService = require("../src/server/services/SessionService")
local ProfileStore = require("../src/server/persistence/ProfileStore")
local TransferJournalStore = require("../src/server/persistence/TransferJournalStore")
local PlayerDataService = require("../src/server/services/PlayerDataService")
local EconomyService = require("../src/server/services/EconomyService")
local CreatureService = require("../src/server/services/CreatureService")
local CapsuleService = require("../src/server/services/CapsuleService")
local MutationService = require("../src/server/services/MutationService")
local ActionService = require("../src/server/services/ActionService")
local TheftService = require("../src/server/services/TheftService")
local TagService = require("../src/server/services/TagService")
local HudModel = require("../src/client/controllers/HudModel")
local CodexModel = require("../src/client/controllers/CodexModel")
local EconomyConfig = require("../src/shared/config/EconomyConfig")
local RaidConfig = require("../src/shared/config/RaidConfig")
local WorldConfig = require("../src/shared/config/WorldConfig")
local AudioCueConfig = require("../src/shared/config/AudioCueConfig")
local CreatureDefinitions = require("../src/shared/definitions/CreatureDefinitions")
local CreatureVisualDefinitions = require("../src/shared/definitions/CreatureVisualDefinitions")
local MutationDefinitions = require("../src/shared/definitions/MutationDefinitions")
local Telemetry = require("../src/server/analytics/Telemetry")
local StudioMemoryDataStoreService =
    require("../src/server/persistence/StudioMemoryDataStoreService")

local passed = 0
local failed = 0

local function test(name: string, callback: () -> ())
    local ok, result = pcall(callback)
    if ok then
        passed += 1
        print("PASS " .. name)
    else
        failed += 1
        warn("FAIL " .. name .. ": " .. tostring(result))
    end
end

local function expect(condition: any, message: string?)
    if not condition then
        error(message or "expectation failed", 2)
    end
    return condition
end

local function cloneTable(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in value do
        copy[key] = cloneTable(child)
    end
    return copy
end

local function makeFakeDataStore()
    local store = { records = {}, calls = 0, failuresRemaining = 0 }
    function store:UpdateAsync(key, transform)
        self.calls += 1
        if self.failuresRemaining > 0 then
            self.failuresRemaining -= 1
            error("temporary DataStore failure")
        end
        if self.failOnCall == self.calls then
            error("injected one-shot DataStore failure")
        end
        if self.failOnCalls ~= nil and self.failOnCalls[self.calls] then
            error("injected DataStore failure")
        end
        local existing = self.records[key]
        local function keyInfoFor(record)
            if record == nil then
                return nil
            end
            return {
                GetMetadata = function()
                    return cloneTable(record.metadata)
                end,
                GetUserIds = function()
                    return cloneTable(record.userIds)
                end,
            }
        end

        local newValue, userIds, metadata = transform(
            if existing ~= nil then cloneTable(existing.value) else nil,
            keyInfoFor(existing)
        )
        if newValue == nil then
            return nil, keyInfoFor(existing)
        end
        local updated = {
            value = cloneTable(newValue),
            userIds = cloneTable(userIds or if existing ~= nil then existing.userIds else {}),
            metadata = cloneTable(metadata or if existing ~= nil then existing.metadata else {}),
        }
        self.records[key] = updated
        if self.failAfterWriteOnCall == self.calls then
            error("injected ambiguous DataStore response")
        end
        return cloneTable(updated.value), keyInfoFor(updated)
    end
    function store:GetAsync(key)
        if self.getFailuresRemaining ~= nil and self.getFailuresRemaining > 0 then
            self.getFailuresRemaining -= 1
            error("temporary DataStore read failure")
        end
        local existing = self.records[key]
        return if existing ~= nil then cloneTable(existing.value) else nil
    end
    return store
end

local function makeProfileStore(fakeStore: any, now: { value: number }?, tokens: { number }?)
    now = now or { value = 1_000 }
    tokens = tokens or { value = 0 }
    return ProfileStore.new({
        store = fakeStore,
        validate = PlayerDataService.validateProfile,
        clock = function()
            return now.value
        end,
        generateToken = function()
            tokens.value += 1
            return "session-token-" .. tostring(tokens.value)
        end,
        wait = function() end,
        serverId = "test-server",
    })
end

local function makeLoadedDataService(userId: number, idPrefix: string?)
    local dataStore = makeFakeDataStore()
    local profileStore = makeProfileStore(dataStore)
    local nextId = 0
    local dataService = PlayerDataService.new({
        profileStore = profileStore,
        clock = function()
            return 1_000
        end,
        generateCreatureId = function()
            nextId += 1
            return (idPrefix or "creature-") .. tostring(nextId)
        end,
        autoSaveEnabled = false,
        wait = function() end,
    })
    assert(dataService:load(userId), "test profile should load")
    return dataService, dataStore
end

local function makeMutationContext(
    userId: number,
    randomInteger: ((number, number) -> number)?,
    emitEvent: ((number, string, any, number) -> ())?
)
    local dataService = makeLoadedDataService(userId, "mutation-" .. tostring(userId) .. "-")
    local baseService = BaseService.new({ baseCount = 1 })
    local player = { UserId = userId }
    assert(baseService:assign(player), "mutation test player should receive a base")
    local creatureService = CreatureService.new({
        playerDataService = dataService,
        baseService = baseService,
    })
    assert(creatureService:syncPlayer(userId), "starter should project to its stand")
    local nextTransaction = 0
    local mutationService = MutationService.new({
        playerDataService = dataService,
        creatureService = creatureService,
        generateTransactionId = function()
            nextTransaction += 1
            return "mutation-transaction-" .. tostring(nextTransaction)
        end,
        randomInteger = randomInteger,
        emitEvent = emitEvent,
    })
    local economyService = EconomyService.new({
        playerDataService = dataService,
        creatureService = creatureService,
        schedule = function() end,
        wait = function() end,
        publish = function() end,
    })
    return {
        dataService = dataService,
        baseService = baseService,
        player = player,
        creatureService = creatureService,
        mutationService = mutationService,
        economyService = economyService,
    }
end

local function makeTheftContext(options: any?)
    options = options or {}
    local userIds = options.userIds or { 1_201, 1_202 }
    local unixNow = { value = options.unixNow or 1_000 }
    local monotonicNow = { value = options.monotonicNow or 10 }
    local players = {}
    local positions = {}
    local humanoids = {}
    local dataServices = {}
    local nextCreatureId = 0
    local attemptSequence = 0
    local profileDataStore = makeFakeDataStore()
    local dataService = PlayerDataService.new({
        profileStore = makeProfileStore(profileDataStore),
        clock = function()
            return unixNow.value
        end,
        generateCreatureId = function()
            nextCreatureId += 1
            return "theft-starter-" .. tostring(nextCreatureId)
        end,
        autoSaveEnabled = false,
        schedule = function(callback)
            callback()
        end,
        wait = function() end,
    })
    local baseService = BaseService.new({ baseCount = #userIds })
    for _, userId in userIds do
        local player = { UserId = userId, attributes = {} }
        function player:SetAttribute(name, value)
            self.attributes[name] = value
        end
        players[userId] = player
        local assigned = baseService:assign(player)
        assert(assigned ~= nil, "theft test player should receive a base")
        assert(baseService:setOperational(player, true), "theft test player should be operational")
        assert(dataService:load(userId), "theft test profile should load")
        dataServices[userId] = dataService
        humanoids[userId] = {
            WalkSpeed = 16,
            JumpPower = 50,
            JumpHeight = 7.2,
            UseJumpPower = true,
            toolsEquipped = false,
            UnequipTools = function(self)
                self.toolsEquipped = false
            end,
        }
    end
    local ownerUserId = userIds[1]
    local thiefUserId = userIds[2]
    local ownerData = dataServices[ownerUserId]
    local targetId = options.targetId or "theft-target"
    local targetSpecies = CreatureDefinitions.SpeciesIdsByRarity.Common[2]
    local targetCreature = { id = targetId, speciesId = targetSpecies }
    local added, _, addError = ownerData:transact(ownerUserId, function(profile)
        if options.ownerCapacity ~= nil then
            profile.slotCapacity = options.ownerCapacity
        end
        profile.creatures[#profile.creatures + 1] = cloneTable(targetCreature)
        profile.discoveredSpeciesIds[targetSpecies] = true
        if options.welcomeTarget then
            profile.welcomeCreatureId = targetId
        end
        if options.participationMarker ~= nil then
            profile.firstRaidParticipation = cloneTable(options.participationMarker)
        end
        return { changed = true }
    end)
    assert(added and addError == nil, "test owner should receive the target creature")
    if options.extraOwnerTargets then
        for index = 1, options.extraOwnerTargets do
            local extraId = "theft-extra-" .. tostring(index)
            local speciesId = CreatureDefinitions.SpeciesIdsByRarity.Common[(index % 5) + 2]
            local changed = ownerData:transact(ownerUserId, function(profile)
                profile.creatures[#profile.creatures + 1] = { id = extraId, speciesId = speciesId }
                profile.discoveredSpeciesIds[speciesId] = true
                return { changed = true }
            end)
            assert(changed, "test owner should receive extra target")
        end
    end
    if options.fillThief then
        local thiefData = dataServices[thiefUserId]
        local speciesId = CreatureDefinitions.SpeciesIdsByRarity.Common[2]
        local filled = thiefData:transact(thiefUserId, function(profile)
            profile.creatures[#profile.creatures + 1] =
                { id = "thief-filler", speciesId = speciesId }
            profile.discoveredSpeciesIds[speciesId] = true
            return { changed = true }
        end)
        assert(filled, "test thief should be filled")
    end
    for _, userId in userIds do
        assert(
            CreatureService.new({
                playerDataService = dataServices[userId],
                baseService = baseService,
            }):syncPlayer(userId),
            "test creatures should project to their stands"
        )
    end
    local raidService = RaidService.new({
        initialPhase = options.phase or "RAID",
        initialPhaseStartedAtUnix = unixNow.value,
        clock = function()
            return unixNow.value
        end,
        generateRaidId = function(sequence)
            return "theft-raid-" .. tostring(sequence)
        end,
    })
    local tagService = nil
    if options.graceUserId ~= nil then
        local raidId = raidService:getSnapshot().raidId
        raidService:onOperationalChanged(options.graceUserId, true, raidId)
    end
    local journalDataStore = makeFakeDataStore()
    local journalStore = TransferJournalStore.new({
        store = journalDataStore,
        wait = function() end,
    })
    local creatureService = CreatureService.new({
        playerDataService = ownerData,
        baseService = baseService,
    })
    local theftService = TheftService.new({
        raidService = raidService,
        playerDataService = dataService,
        creatureService = creatureService,
        baseService = baseService,
        transferJournalStore = journalStore,
        getPlayer = function(userId)
            return players[userId]
        end,
        getPlayerPosition = function(player)
            return positions[player.UserId]
        end,
        getHumanoid = function(player)
            return humanoids[player.UserId]
        end,
        isOperational = function(player)
            return baseService:isOperational(player)
        end,
        generateAttemptId = function()
            if options.attemptId ~= nil then
                return options.attemptId
            end
            attemptSequence += 1
            return "theft-attempt-" .. tostring(attemptSequence)
        end,
        isStaggered = function(userId, raidId)
            return tagService ~= nil and tagService:isStaggered(userId, raidId)
        end,
        clock = function()
            return monotonicNow.value
        end,
        unixClock = function()
            return unixNow.value
        end,
        emitToUser = options.emitToUser,
        emitAnalytics = options.emitAnalytics,
        schedule = function(callback)
            if options.runScheduled ~= false then
                callback()
            end
        end,
    })
    tagService = TagService.new({
        raidService = raidService,
        theftService = theftService,
        getPlayer = function(userId)
            return players[userId]
        end,
        getPlayerPosition = function(player)
            return positions[player.UserId]
        end,
        getHumanoid = function(player)
            return humanoids[player.UserId]
        end,
        isOperational = function(player)
            return baseService:isOperational(player)
        end,
        clock = function()
            return monotonicNow.value
        end,
        emitToUser = options.emitToUser,
        emitAnalytics = options.emitAnalytics,
    })
    local targetPosition = baseService:getCreatureDisplayPosition(ownerUserId, targetId)
    positions[ownerUserId] = baseService:getHomePadPosition(ownerUserId)
    positions[thiefUserId] = targetPosition
    return {
        ownerUserId = ownerUserId,
        thiefUserId = thiefUserId,
        targetId = targetId,
        targetCreature = targetCreature,
        players = players,
        positions = positions,
        humanoids = humanoids,
        dataServices = dataServices,
        dataService = dataService,
        baseService = baseService,
        creatureService = creatureService,
        raidService = raidService,
        theftService = theftService,
        tagService = tagService,
        journalStore = journalStore,
        journalDataStore = journalDataStore,
        profileDataStore = profileDataStore,
        unixNow = unixNow,
        monotonicNow = monotonicNow,
    }
end

local function beginAndCarryTheft(context: any, targetId: string?): string
    local result, errorCode =
        context.theftService:beginTheft(context.thiefUserId, targetId or context.targetId)
    assert(result ~= nil and errorCode == nil, "valid theft should begin")
    context.monotonicNow.value += RaidConfig.THEFT_CHANNEL_SECONDS
    assert(context.theftService:step(context.monotonicNow.value), "theft state should step")
    local attempt = context.theftService._attempts[result.attemptId]
    assert(attempt ~= nil and attempt.state == "CARRIED", "completed channel should carry the item")
    context.positions[context.thiefUserId] =
        context.baseService:getHomePadPosition(context.thiefUserId)
    return result.attemptId
end

local function completeMutationTutorial(context: any, themeId: string): any
    local profile = context.dataService:getSnapshot(context.player.UserId)
    local result, errorCode = context.mutationService:completeTutorialMutation(
        context.player.UserId,
        profile.starterCreatureId,
        themeId,
        "PEACE"
    )
    assert(result ~= nil and errorCode == nil, "tutorial mutation should complete")
    return result
end

test("shared protocol accepts a well-formed request", function()
    assert(
        Protocol.isValidDevPingRequest({ requestId = "test-1" }),
        "valid ping should pass protocol validation"
    )
    assert(
        Protocol.DomainEventNames.RaidPhaseChanged == "RaidPhaseChanged",
        "Raid phase events must use the centralized network contract"
    )
    assert(
        Protocol.PlayerAttributeNames.RaidPhaseEndsAtUnix == "OddlingsRaidPhaseEndsAtUnix",
        "replicated Raid state names must use the centralized contract"
    )
end)

test("shared protocol rejects malformed and unexpected fields", function()
    assert(not Protocol.isValidDevPingRequest("test-1"), "non-table payload should be rejected")
    assert(
        not Protocol.isValidDevPingRequest({ requestId = "" }),
        "empty request id should be rejected"
    )
    assert(
        not Protocol.isValidDevPingRequest({ requestId = string.rep("x", 65) }),
        "oversized request id should be rejected"
    )
    assert(
        not Protocol.isValidDevPingRequest({ requestId = "test-1", currency = 999999 }),
        "unexpected client authority fields should be rejected"
    )
end)

test("central action protocol rejects unknown fields and client authority values", function()
    local request = {
        sessionId = "session-123456",
        requestId = "request-1",
        action = "PurchaseCapsule",
        payload = { kind = "Welcome" },
    }
    assert(Protocol.isValidActionRequest(request), "valid capsule request should pass")
    assert(not Protocol.isValidActionRequest({
        sessionId = request.sessionId,
        requestId = request.requestId,
        action = request.action,
        payload = { kind = "Welcome", speciesId = "PocketHydra" },
    }), "client must not choose capsule result")
    assert(not Protocol.isValidActionRequest({
        sessionId = request.sessionId,
        requestId = request.requestId,
        action = request.action,
        payload = request.payload,
        scrap = 1_000_000,
    }), "action envelope must reject extra authority fields")
    assert(not Protocol.isValidActionRequest({
        sessionId = request.sessionId,
        requestId = "phase-request",
        action = "SetRaidPhase",
        payload = { phase = "RAID" },
    }), "clients cannot request a Raid phase transition")
end)

test("Raid action protocol accepts only server-measured interaction requests", function()
    local shared = { sessionId = "raid-session-123", requestId = "raid-action-1" }
    local cases = {
        { action = "BeginTheft", payload = { targetCreatureId = "creature-a" } },
        { action = "CancelTheft", payload = { attemptId = "attempt-a" } },
        { action = "BankTheft", payload = { stage = "Begin", attemptId = "attempt-a" } },
        {
            action = "BankTheft",
            payload = { stage = "Complete", attemptId = "attempt-a", catalystThemeId = "Ember" },
        },
        { action = "Tag", payload = { targetUserId = 1_302 } },
        { action = "RecoverDroppedCreature", payload = { attemptId = "attempt-a" } },
    }
    for index, testCase in cases do
        local request = cloneTable(shared)
        request.requestId = "raid-action-" .. tostring(index)
        request.action = testCase.action
        request.payload = testCase.payload
        assert(
            Protocol.isValidActionRequest(request),
            testCase.action .. " payload should be valid"
        )
        local claimedTime = cloneTable(request)
        claimedTime.payload = cloneTable(testCase.payload)
        claimedTime.payload.clientTimestamp = 1_000
        assert(not Protocol.isValidActionRequest(claimedTime), "clients cannot submit server time")
    end
    local malformed = cloneTable(shared)
    malformed.action = "BeginTheft"
    malformed.payload = { targetCreatureId = "creature-a", ownerUserId = 1_301 }
    assert(not Protocol.isValidActionRequest(malformed), "client cannot claim target ownership")
end)

test("server service initializes and accepts a valid request", function()
    local service = DevPingService.new(Protocol, RequestGuard)
    local response = service:handle({ requestId = "server-test" })
    assert(response.accepted == true, "service should accept valid request")
    assert(response.requestId == "server-test", "service should preserve valid request id")
end)

test("server service rejects invalid client-style input", function()
    local service = DevPingService.new(Protocol, RequestGuard)
    local response = service:handle({ requestId = "invalid", ownedCreature = "client-claimed" })
    assert(response.accepted == false, "service should reject invalid request")
    assert(response.reason == "MalformedRequest", "service should return validation reason")
end)

local function newSignal()
    local listeners = {}
    return {
        Connect = function(_, callback)
            local listener = { callback = callback, connected = true }
            table.insert(listeners, listener)
            return {
                Disconnect = function()
                    listener.connected = false
                end,
            }
        end,
        Fire = function(_, ...)
            local args = { ... }
            for _, listener in listeners do
                if listener.connected then
                    listener.callback(table.unpack(args))
                end
            end
        end,
    }
end

local function newPlayer(userId, character)
    return {
        UserId = userId,
        Character = character,
        CharacterAdded = newSignal(),
        CharacterRemoving = newSignal(),
        attributes = {},
        SetAttribute = function(self, name, value)
            self.attributes[name] = value
        end,
        Kick = function(self, reason)
            self.kicked = reason
        end,
    }
end

local function newPlayers(initialPlayers)
    local members = initialPlayers or {}
    local service = {
        PlayerAdded = newSignal(),
        PlayerRemoving = newSignal(),
    }
    function service:GetPlayers()
        return members
    end
    function service:Add(player)
        table.insert(members, player)
        self.PlayerAdded:Fire(player)
    end
    function service:Remove(player)
        for index, member in members do
            if member == player then
                table.remove(members, index)
                break
            end
        end
        self.PlayerRemoving:Fire(player)
    end
    return service
end

test("base assignment is unique and rejects a ninth player", function()
    local service = BaseService.new({ baseCount = 8 })
    local baseIds = {}
    for userId = 1, 8 do
        local base, reason = service:assign(newPlayer(userId))
        assert(base ~= nil, "each of eight players should receive a base")
        assert(reason == nil, "successful assignment should have no error")
        assert(baseIds[base.id] == nil, "two players must not own the same base")
        baseIds[base.id] = userId
    end

    local ninthBase, reason = service:assign(newPlayer(9))
    assert(ninthBase == nil, "ninth player must not receive a base")
    assert(reason == "ServerFull", "server capacity should be explicit")
    assert(service:getAvailableCount() == 0, "all eight bases should be occupied")
end)

test("released base is reused deterministically and stale release is safe", function()
    local service = BaseService.new({ baseCount = 8 })
    local firstPlayer = newPlayer(101)
    local secondPlayer = newPlayer(202)
    local firstBase = service:assign(firstPlayer)
    local secondBase = service:assign(secondPlayer)

    assert(firstBase.id == "Base01", "allocation should start at the first base")
    assert(secondBase.id == "Base02", "next player should receive the next free base")
    assert(service:release(firstPlayer), "owner should release its base")
    assert(not service:release(firstPlayer), "duplicate release should be harmless")

    local rejoinedBase = service:assign(firstPlayer)
    assert(rejoinedBase.id == "Base01", "freed base should be reused deterministically")
    assert(service:setOperational(firstPlayer, true), "assigned owner can become operational")
    assert(service:isOperational(firstPlayer), "operational state should be observable")
    assert(service:release(firstPlayer), "rejoined owner should release normally")
    assert(not service:isOperational(firstPlayer), "release clears operational state")
end)

test("base collections map stable creatures to bounded stands and reset on release", function()
    local baseService = BaseService.new()
    local firstPlayer = { UserId = 315 }
    local assigned = baseService:assign(firstPlayer)
    assert(assigned ~= nil, "first player should get a base")
    assert(
        assigned.slotCapacity == 2 and #assigned.creatures == 0,
        "base starts at two empty slots"
    )

    local creatures = {
        { id = "starter-315", speciesId = "Mossling" },
        { id = "welcome-315", speciesId = "TeacupCrab" },
    }
    assert(
        baseService:setCollection(firstPlayer.UserId, creatures, 2),
        "valid two-creature collection should map to the base"
    )
    local snapshot = baseService:getForPlayer(firstPlayer)
    assert(#snapshot.creatures == 2, "both occupied stands should appear in the snapshot")
    assert(
        snapshot.creatures[2].id == "welcome-315"
            and snapshot.creatures[2].speciesId == "TeacupCrab",
        "stand mapping should preserve stable IDs and species"
    )
    creatures[2].speciesId = "InvalidSpecies"
    assert(
        snapshot.creatures[2].speciesId == "TeacupCrab",
        "base snapshots must not expose mutable collection references"
    )

    local threeCreatures = {
        { id = "starter-315", speciesId = "Mossling" },
        { id = "welcome-315", speciesId = "TeacupCrab" },
        { id = "third-315", speciesId = "ButtonBat" },
    }
    assert(
        baseService:setCollection(firstPlayer.UserId, threeCreatures, 3),
        "purchased Slot 3 should map its third stand"
    )
    assert(
        not baseService:setCollection(firstPlayer.UserId, threeCreatures, 5),
        "capacity cannot exceed four slots"
    )
    assert(not baseService:setCollection(firstPlayer.UserId, {
        { id = "duplicate", speciesId = "Mossling" },
        { id = "duplicate", speciesId = "ButtonBat" },
    }, 3), "stand mappings require unique creature IDs")
    assert(baseService:release(firstPlayer), "leaving should release the base")

    local secondPlayer = { UserId = 316 }
    local reused = baseService:assign(secondPlayer)
    assert(reused.id == assigned.id, "the released base should be reused deterministically")
    assert(
        reused.slotCapacity == 2 and #reused.creatures == 0,
        "a reused base must not retain its previous collection or upgrades"
    )
end)

test("Raid config matches the exact locked eight-minute cycle", function()
    local durations = RaidConfig.PHASE_DURATIONS_SECONDS
    expect(table.concat(RaidConfig.PHASE_ORDER, ",") == "PEACE,WARNING,RAID,RESOLUTION,COOLDOWN")
    expect(durations.PEACE == 300 and durations.WARNING == 30)
    expect(durations.RAID == 90 and durations.RESOLUTION == 30 and durations.COOLDOWN == 30)
    expect(
        durations.PEACE
                + durations.WARNING
                + durations.RAID
                + durations.RESOLUTION
                + durations.COOLDOWN
            == 480,
        "the shared Raid cycle must total eight minutes"
    )
    expect(RaidConfig.ARRIVAL_GRACE_SECONDS == 15)
end)

test("Raid clock advances at exact boundaries without accumulating drift", function()
    local now = { value = 100 }
    local service = RaidService.new({
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "test-raid-" .. tostring(sequence)
        end,
    })
    local changed = {}
    service.Changed:Connect(function(snapshot)
        table.insert(changed, snapshot)
    end)

    local first = service:getSnapshot()
    expect(first.phase == "PEACE" and first.phaseStartedAtUnix == 100)
    expect(first.phaseEndsAtUnix == 400 and first.raidId == "test-raid-1")
    local boundaries = {
        { phase = "WARNING", start = 400, finish = 430 },
        { phase = "RAID", start = 430, finish = 520 },
        { phase = "RESOLUTION", start = 520, finish = 550 },
        { phase = "COOLDOWN", start = 550, finish = 580 },
        { phase = "PEACE", start = 580, finish = 880 },
    }
    for _, expected in boundaries do
        now.value = expected.start - 1
        local earlyOk, earlyTransitions = service:step()
        expect(earlyOk and earlyTransitions == 0, "a phase must not advance before its deadline")
        now.value = expected.start
        local advanced, count = service:step()
        expect(advanced and count == 1, "the exact boundary must advance one phase")
        local snapshot = service:getSnapshot()
        expect(snapshot.phase == expected.phase)
        expect(snapshot.phaseStartedAtUnix == expected.start)
        expect(snapshot.phaseEndsAtUnix == expected.finish)
        expect(changed[#changed].phase == expected.phase, "each boundary must publish its phase")
    end
    expect(changed[2].raidId == "test-raid-2", "entering RAID creates a distinct server Raid ID")
    local backwardOk, _, backwardError = service:step(579)
    expect(not backwardOk and backwardError == "InvalidTimestamp")
end)

test("Raid clock catches up through delayed ticks using scheduled boundaries", function()
    local now = { value = 1_000 }
    local service = RaidService.new({
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "catchup-" .. tostring(sequence)
        end,
    })
    local eventCount = 0
    service.Changed:Connect(function()
        eventCount += 1
    end)

    now.value = 1_000 + 3 * 480
    local stepped, transitions = service:step()
    local snapshot = service:getSnapshot()
    expect(stepped and transitions == 15 and eventCount == 15)
    expect(snapshot.phase == "PEACE" and snapshot.phaseStartedAtUnix == now.value)
    expect(snapshot.phaseEndsAtUnix == now.value + 300)
end)

test("Raid clock binds one server heartbeat and stops cleanly", function()
    local now = { value = 1_500 }
    local service = RaidService.new({
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "heartbeat-" .. tostring(sequence)
        end,
    })
    local heartbeat = newSignal()
    local eventCount = 0
    service.Changed:Connect(function()
        eventCount += 1
    end)
    local started = service:start(heartbeat)
    expect(started)
    local duplicateStart, duplicateError = service:start(heartbeat)
    expect(not duplicateStart and duplicateError == "AlreadyStarted")

    now.value = 1_800
    heartbeat:Fire()
    expect(service:getSnapshot().phase == "WARNING")
    now.value = 1_830
    heartbeat:Fire()
    expect(service:getSnapshot().phase == "RAID")
    service:stop()

    now.value = 1_920
    heartbeat:Fire()
    expect(eventCount == 2, "stopped RaidService must disconnect from server Heartbeat")
    expect(service:getSnapshot().phase == "RESOLUTION")
    local invalidStart, invalidError = service:start(nil)
    expect(not invalidStart and invalidError == "InvalidHeartbeat")
end)

test("arrival grace starts at operational readiness and never refreshes", function()
    local now = { value = 500 }
    local service = RaidService.new({
        initialPhase = "RAID",
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "grace-" .. tostring(sequence)
        end,
    })
    local raidId = service:getSnapshot().raidId
    local notJoinedDuringRaid = service:onOperationalChanged(700, true, nil)
    expect(notJoinedDuringRaid == nil, "a pre-existing player does not receive arrival grace")

    local grace = service:onOperationalChanged(701, true, raidId)
    expect(grace ~= nil and grace.startedAtUnix == 500 and grace.expiresAtUnix == 515)
    expect(service:isArrivalGraceActive(701), "active grace blocks the user's Raid interactions")

    now.value = 510
    service:onOperationalChanged(701, false, raidId)
    local afterRespawn = service:onOperationalChanged(701, true, raidId)
    expect(afterRespawn.startedAtUnix == 500 and afterRespawn.expiresAtUnix == 515)
    expect(service:isArrivalGraceActive(701), "respawn preserves, but does not restart, grace")

    now.value = 515
    expect(not service:isArrivalGraceActive(701), "grace expires at its exact timestamp")
    local afterExpiry = service:onOperationalChanged(701, true, raidId)
    expect(afterExpiry.startedAtUnix == 500 and afterExpiry.expiresAtUnix == 515)
    expect(not afterExpiry.active, "a repeated readiness event cannot create new grace")

    now.value = 580
    local lateGrace = service:onOperationalChanged(702, true, raidId)
    expect(lateGrace.expiresAtUnix == 595)
    now.value = 590
    expect(service:getSnapshot().phase == "RESOLUTION")
    expect(not service:isArrivalGraceActive(702), "arrival grace never continues beyond RAID")
end)

test("session phase snapshots and arrival grace distinguish joins from resets", function()
    for _, phase in RaidConfig.PHASE_ORDER do
        local now = { value = 1_000 }
        local raidService = RaidService.new({
            initialPhase = phase,
            clock = function()
                return now.value
            end,
            generateRaidId = function(sequence)
                return phase .. "-raid-" .. tostring(sequence)
            end,
        })
        local baseService = BaseService.new({ baseCount = 1 })
        local callbackGrace = nil
        local sessionService = SessionService.new({
            baseService = baseService,
            raidService = raidService,
            isPlayer = function(player)
                return type(player) == "table" and type(player.UserId) == "number"
            end,
            schedule = function(callback)
                callback()
            end,
            spawnCharacter = function()
                return true
            end,
            onOperationalChanged = function(player, isOperational, _base, joinedDuringRaidId)
                callbackGrace = raidService:onOperationalChanged(
                    player.UserId,
                    isOperational,
                    joinedDuringRaidId
                )
                if callbackGrace ~= nil then
                    player:SetAttribute("OddlingsArrivalGraceRaidId", callbackGrace.raidId)
                    player:SetAttribute(
                        "OddlingsArrivalGraceStartedAtUnix",
                        callbackGrace.startedAtUnix
                    )
                    player:SetAttribute(
                        "OddlingsArrivalGraceEndsAtUnix",
                        callbackGrace.expiresAtUnix
                    )
                end
            end,
        })
        local player = newPlayer(400 + #phase, {})
        local added = sessionService:onPlayerAdded(player)
        local session = sessionService:getSession(player)
        expect(added and session.phase == phase)
        expect(player.attributes.OddlingsRaidPhase == phase)
        expect(
            player.attributes.OddlingsRaidPhaseEndsAtUnix
                == 1_000 + RaidConfig.PHASE_DURATIONS_SECONDS[phase]
        )
        if phase == "RAID" then
            expect(session.joinedDuringRaidId == session.raidId)
            expect(callbackGrace ~= nil and callbackGrace.active)
            expect(player.attributes.OddlingsArrivalGraceEndsAtUnix == 1_015)
            local originalEnd = callbackGrace.expiresAtUnix
            now.value = 1_005
            local oldCharacter = player.Character
            player.CharacterRemoving:Fire(oldCharacter)
            player.Character = {}
            player.CharacterAdded:Fire(player.Character)
            expect(callbackGrace.expiresAtUnix == originalEnd)
            sessionService:onPlayerRemoving(player)
            now.value = 1_008
            local rejoined = sessionService:onPlayerAdded(player)
            expect(rejoined)
            expect(
                callbackGrace.startedAtUnix == 1_000 and callbackGrace.expiresAtUnix == originalEnd,
                "rejoining the same Raid must reuse the original grace window"
            )
        else
            expect(session.joinedDuringRaidId == nil)
            expect(callbackGrace == nil, "non-RAID joins never receive Raid arrival grace")
        end
        sessionService:stop()
    end
end)

test("GetSnapshot returns authoritative Raid timing and private arrival grace", function()
    local userId = 441
    local now = { value = 2_000 }
    local dataService = makeLoadedDataService(userId, "raid-snapshot-")
    local raidService = RaidService.new({
        initialPhase = "RAID",
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "snapshot-raid-" .. tostring(sequence)
        end,
    })
    local raidSnapshot = raidService:getSnapshot()
    raidService:onOperationalChanged(userId, true, raidSnapshot.raidId)
    local player = newPlayer(userId)
    local actionService = ActionService.new({
        sessionService = {
            getSession = function()
                return { userId = userId, sessionId = "raid-snapshot-session" }
            end,
        },
        raidService = raidService,
        playerDataService = dataService,
        economyService = {},
        capsuleService = {},
        mutationService = {
            getOddsSnapshot = function()
                return { normal = true }
            end,
            getPending = function()
                return nil
            end,
        },
        theftService = {},
        baseService = BaseService.new({ baseCount = 1 }),
        requestEvent = { OnServerEvent = newSignal() },
        resultEvent = { FireClient = function() end },
        domainEvent = { FireClient = function() end },
        clock = function()
            return now.value
        end,
        unixClock = function()
            return now.value
        end,
    })
    local response = actionService:handle(player, {
        sessionId = "raid-snapshot-session",
        requestId = "raid-snapshot-request",
        action = "GetSnapshot",
        payload = {},
    })
    expect(response.ok and response.data.phase == "RAID")
    expect(response.data.raid.raidId == raidSnapshot.raidId)
    expect(response.data.raid.phaseStartedAtUnix == 2_000)
    expect(response.data.raid.phaseEndsAtUnix == 2_090)
    expect(response.data.raid.serverTimeUnix == 2_000)
    expect(response.data.arrivalGrace.active)
    expect(response.data.arrivalGrace.expiresAtUnix == 2_015)
    expect(response.data.welcomeAvailable == true)
end)

test("a pre-existing player does not gain Raid grace from a reset after Raid starts", function()
    local now = { value = 1_000 }
    local raidService = RaidService.new({
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "existing-player-raid-" .. tostring(sequence)
        end,
    })
    local player = newPlayer(442, {})
    local sessionService = SessionService.new({
        baseService = BaseService.new({ baseCount = 1 }),
        raidService = raidService,
        isPlayer = function(candidate)
            return candidate == player
        end,
        schedule = function(callback)
            callback()
        end,
        spawnCharacter = function()
            return true
        end,
        onOperationalChanged = function(candidate, isOperational, _base, joinedDuringRaidId)
            raidService:onOperationalChanged(candidate.UserId, isOperational, joinedDuringRaidId)
        end,
    })
    local added = sessionService:onPlayerAdded(player)
    expect(added and sessionService:getSession(player).joinedDuringRaidId == nil)
    expect(not raidService:isArrivalGraceActive(player.UserId))

    now.value = 1_330
    local stepped = raidService:step()
    expect(stepped and raidService:getSnapshot().phase == "RAID")
    local oldCharacter = player.Character
    player.CharacterRemoving:Fire(oldCharacter)
    player.Character = {}
    player.CharacterAdded:Fire(player.Character)
    expect(not raidService:isArrivalGraceActive(player.UserId))
end)

test("session inherits phase, spawns at its base, and cleans up on leave", function()
    local baseService = BaseService.new({ baseCount = 8 })
    local now = { value = 500 }
    local raidService = RaidService.new({
        initialPhase = "WARNING",
        clock = function()
            return now.value
        end,
    })
    local sessionService = SessionService.new({
        baseService = baseService,
        raidService = raidService,
        isPlayer = function(player)
            return type(player) == "table" and type(player.UserId) == "number"
        end,
        schedule = function(callback)
            callback()
        end,
        spawnCharacter = function(_player, character, base)
            character.spawnedAtBaseId = base.id
            return true
        end,
    })
    local character = {}
    local player = newPlayer(303, character)
    local players = newPlayers({ player })

    local started = sessionService:start(players)
    assert(started, "session service should start")
    local session = sessionService:getSession(player)
    assert(session ~= nil, "existing player should receive a session")
    assert(session.baseId == "Base01", "session should own its assigned base")
    assert(session.phase == "WARNING", "join should inherit the current phase")
    assert(session.operational, "player with a ready character should become operational")
    assert(character.spawnedAtBaseId == "Base01", "character should spawn at its assigned base")
    assert(
        player.attributes.OddlingsBaseId == "Base01",
        "base assignment should be replicated as an attribute"
    )
    assert(player.attributes.OddlingsRaidPhase == "WARNING", "phase snapshot should be replicated")
    assert(baseService:getAvailableCount() == 7, "one session should occupy one base")

    local nextCharacter = {}
    player.CharacterRemoving:Fire(character)
    assert(not baseService:isOperational(player), "character removal clears operational readiness")
    player.Character = nextCharacter
    player.CharacterAdded:Fire(nextCharacter)
    assert(
        baseService:isOperational(player),
        "respawn should restore readiness without changing base"
    )
    assert(
        sessionService:getSession(player).baseId == "Base01",
        "respawn must not reassign the base"
    )

    now.value = 530
    local transitioned = raidService:step()
    assert(transitioned, "Raid clock should advance at the configured boundary")
    assert(
        player.attributes.OddlingsRaidPhase == "RAID",
        "existing session should receive phase updates"
    )

    players.PlayerAdded:Fire(player)
    assert(
        baseService:getAvailableCount() == 7,
        "duplicate add event must not allocate another base"
    )
    players:Remove(player)
    assert(sessionService:getSession(player) == nil, "leave should end the session")
    assert(baseService:getAvailableCount() == 8, "leave should release the base")
    assert(player.attributes.OddlingsBaseId == nil, "leave clears the replicated base assignment")

    players:Add(player)
    assert(
        sessionService:getSession(player).baseId == "Base01",
        "rejoin should deterministically reuse a freed base"
    )
    sessionService:stop()
    assert(baseService:getAvailableCount() == 8, "stop should clean up all active sessions")
end)

test("session boundary rejects malformed player lifecycle input", function()
    local service = SessionService.new({
        baseService = BaseService.new({ baseCount = 8 }),
        raidService = RaidService.new(),
        isPlayer = function(player)
            return type(player) == "table" and type(player.UserId) == "number"
        end,
    })
    local accepted, reason = service:onPlayerAdded({ UserId = -1 })
    assert(not accepted, "invalid user identity must be rejected")
    assert(reason == "InvalidPlayer", "invalid lifecycle input returns a stable error")
    assert(service._baseService:getAvailableCount() == 8, "invalid input must not reserve a base")
end)

test("failed profile readiness rejects the player before base assignment", function()
    local baseService = BaseService.new({ baseCount = 8 })
    local rejectedReason = nil
    local sessionService = SessionService.new({
        baseService = baseService,
        raidService = RaidService.new(),
        isPlayer = function(player)
            return type(player) == "table" and type(player.UserId) == "number"
        end,
        loadProfile = function()
            return false
        end,
        onRejected = function(_player, reason)
            rejectedReason = reason
        end,
    })
    local player = newPlayer(350)
    local accepted, reason = sessionService:onPlayerAdded(player)
    assert(not accepted, "player with unavailable profile must not enter the session")
    assert(reason == "ProfileUnavailable", "profile readiness failure should be explicit")
    assert(
        rejectedReason == "ProfileUnavailable",
        "rejected player should be surfaced to the bootstrap"
    )
    assert(baseService:getAvailableCount() == 8, "failed profile must not reserve a base")
    assert(sessionService:getSession(player) == nil, "failed profile must not expose a session")
end)

test("failed session initialization clears all replicated Raid state", function()
    local attributes = Protocol.PlayerAttributeNames
    local sessionService = SessionService.new({
        baseService = BaseService.new({ baseCount = 1 }),
        raidService = RaidService.new({ initialPhase = "RAID" }),
        isPlayer = function(player)
            return type(player) == "table" and type(player.UserId) == "number"
        end,
        onSessionReady = function()
            return false
        end,
    })
    local player = newPlayer(351, {})
    local added = sessionService:onPlayerAdded(player)
    expect(not added, "session startup failure rejects the player")
    for _, name in
        {
            attributes.RaidPhase,
            attributes.RaidPhaseStartedAtUnix,
            attributes.RaidPhaseEndsAtUnix,
            attributes.RaidId,
            attributes.RaidRevision,
            attributes.RaidServerTimeUnix,
            attributes.ArrivalGraceRaidId,
            attributes.ArrivalGraceStartedAtUnix,
            attributes.ArrivalGraceEndsAtUnix,
        }
    do
        expect(player.attributes[name] == nil, "failed sessions must clear stale Raid attributes")
    end
end)

test("session waits for profile readiness and saves after stopping online systems", function()
    local order = {}
    local player = newPlayer(375)
    local sessionService = SessionService.new({
        baseService = BaseService.new({ baseCount = 8 }),
        raidService = RaidService.new(),
        isPlayer = function(candidate)
            return type(candidate) == "table" and type(candidate.UserId) == "number"
        end,
        loadProfile = function()
            table.insert(order, "profile-loaded")
            return true
        end,
        onSessionReady = function()
            assert(
                order[1] == "profile-loaded",
                "online systems must start only after profile load"
            )
            table.insert(order, "online-started")
            return true
        end,
        onSessionEnded = function()
            table.insert(order, "online-stopped")
        end,
        saveProfile = function()
            table.insert(order, "profile-saved")
            return true
        end,
    })
    local accepted = sessionService:onPlayerAdded(player)
    assert(accepted, "loaded profile should create a session")
    assert(order[2] == "online-started", "online systems should start after load")
    assert(sessionService:onPlayerRemoving(player), "player removal should complete")
    assert(order[3] == "online-stopped", "online income should stop before save")
    assert(order[4] == "profile-saved", "profile should save after gameplay stops")
end)

test("queued character spawn is ignored after the session has ended", function()
    local baseService = BaseService.new({ baseCount = 8 })
    local scheduled = {}
    local spawnCalls = 0
    local sessionService = SessionService.new({
        baseService = baseService,
        raidService = RaidService.new(),
        isPlayer = function(player)
            return type(player) == "table" and type(player.UserId) == "number"
        end,
        schedule = function(callback)
            table.insert(scheduled, callback)
        end,
        spawnCharacter = function()
            spawnCalls += 1
            return true
        end,
    })
    local player = newPlayer(404, {})
    local players = newPlayers({ player })

    assert(sessionService:start(players), "session should start")
    assert(#scheduled == 1, "character spawn should be scheduled")
    players:Remove(player)
    scheduled[1]()
    assert(spawnCalls == 0, "stale work must not spawn a character after leave")
    assert(baseService:getAvailableCount() == 8, "stale work must not reclaim a released base")
end)

test("profile defaults contain the protected starter and exact starting economy", function()
    local profile = PlayerDataService.createDefaultProfile(function()
        return "starter-id"
    end)
    assert(
        PlayerDataService.validateProfile(profile),
        "fresh defaults should pass the profile schema"
    )
    assert(profile.schemaVersion == 1, "fresh profile must use schema version one")
    assert(profile.scrap == 50, "fresh profile must start with 50 Scrap")
    assert(profile.slotCapacity == 2, "fresh profile must start with two slots")
    assert(#profile.creatures == 1, "fresh profile must contain exactly one creature")
    assert(profile.creatures[1].id == profile.starterCreatureId, "starter identity must be stable")
    assert(profile.creatures[1].speciesId == "Mossling", "Mossling must be the only starter")
    assert(profile.catalysts.emberSeed == 0, "fresh profile must not grant an unchosen catalyst")
    assert(profile.standardCapsulePity.belowRare == 0, "fresh profile must start with zero pity")
    assert(profile.discoveredSpeciesIds.Mossling, "starter species must be discovered")
    assert(profile.hasCompletedFirstRaid == false, "fresh profile has not completed a Raid")
end)

test("M8 HUD summarizes income, first-session goals, rarity labels, and action feedback", function()
    local profile = PlayerDataService.createDefaultProfile(function()
        return "hud-starter"
    end)
    local income = HudModel.getIncomePerMinute(profile.creatures)
    expect(income == 40 and HudModel.formatNumber(income) == "40")
    expect(
        string.find(HudModel.getGoal({ tutorialCompleted = false }), "free Common mutation") ~= nil
    )

    profile.creatures[1].mutationFormId = "Cinder"
    expect(HudModel.getIncomePerMinute(profile.creatures) == 50)
    expect(HudModel.formatNumber(126.5) == "126.5")
    local welcomeGoal = HudModel.getGoal({
        tutorialCompleted = true,
        welcomeAvailable = true,
    })
    expect(string.find(welcomeGoal, "120 Scrap") ~= nil)
    local skippedGuideGoal = HudModel.getGoal({
        tutorialCompleted = false,
        welcomeAvailable = true,
    }, true)
    expect(string.find(skippedGuideGoal, "120 Scrap") ~= nil)

    local choiceGoal = HudModel.getGoal({
        tutorialCompleted = true,
        welcomeAvailable = false,
        creatures = { {}, {} },
        slotCapacity = 2,
    })
    expect(string.find(choiceGoal, "Slot 3") ~= nil and string.find(choiceGoal, "mutation") ~= nil)
    local slotGoal = HudModel.getGoal({
        tutorialCompleted = true,
        welcomeAvailable = false,
        creatures = { {}, {}, {} },
        slotCapacity = 3,
        hasCompletedFirstRaid = false,
    })
    expect(string.find(slotGoal, "first Raid") ~= nil)

    local rarity = HudModel.getRarityPresentation("Rare")
    expect(rarity.icon == "✦" and rarity.label == "RARE" and rarity.color == "Rare")
    expect(HudModel.MIN_TOUCH_TARGET_PX >= 52)
    local odds = HudModel.formatOdds({
        rareGuaranteeActive = true,
        nextRoll = { rare = 999, mythic = 1 },
    })
    expect(
        string.find(odds, "Rare 99.9%", 1, true) ~= nil
            and string.find(odds, "Mythic 0.1%", 1, true) ~= nil
    )
    local creatureLabel, creatureRarity = HudModel.getCreatureLabel(profile.creatures[1])
    expect(creatureLabel == "Mossling · Cinder" and creatureRarity == "Common")
    expect(string.find(HudModel.getErrorCopy("InsufficientCatalyst"), "Commons") ~= nil)
end)

test("M9 visual catalogs, map zones, Codex, and audio cues match locked V1 scope", function()
    local distinctRigFamilies = {}
    local speciesVisualCount = 0
    for _, speciesId in CreatureDefinitions.SpeciesIdsByRarity.Common do
        local visual = CreatureVisualDefinitions.Species[speciesId]
        expect(visual ~= nil and visual.rigFamily ~= nil and visual.silhouette ~= nil)
        distinctRigFamilies[visual.rigFamily] = true
        speciesVisualCount += 1
    end
    for rarity, speciesIds in CreatureDefinitions.SpeciesIdsByRarity do
        if rarity ~= "Common" then
            for _, speciesId in speciesIds do
                local visual = CreatureVisualDefinitions.Species[speciesId]
                expect(visual ~= nil and visual.rigFamily ~= nil and visual.silhouette ~= nil)
                distinctRigFamilies[visual.rigFamily] = true
                speciesVisualCount += 1
            end
        end
    end
    local familyCount = 0
    for _ in distinctRigFamilies do
        familyCount += 1
    end
    expect(speciesVisualCount == 12 and familyCount == 4)
    expect(#CreatureVisualDefinitions.RigFamilies == 4)

    local mutationVisualCount = 0
    for formId in MutationDefinitions.FormIdsByTheme do
        for _, themeFormId in MutationDefinitions.FormIdsByTheme[formId] do
            local recipe = CreatureVisualDefinitions.Mutations[themeFormId]
            expect(
                recipe ~= nil
                    and type(recipe.body) == "table"
                    and type(recipe.accent) == "table"
                    and type(recipe.material) == "string"
                    and type(recipe.silhouette) == "string"
                    and type(recipe.effect) == "string"
                    and CreatureVisualDefinitions.Effects[recipe.effect] ~= nil
            )
            mutationVisualCount += 1
        end
    end
    expect(mutationVisualCount == 24)

    local entries = CodexModel.getEntries({ speciesIds = {}, mutationFormIds = {} })
    expect(#entries == 36)
    expect(
        CodexModel.getSummary({ speciesIds = {}, mutationFormIds = {} })
            == "CODEX · 0/12 SPECIES · 0/24 FORMS"
    )
    local discoveredSpecies = {}
    local discoveredForms = {}
    for _, raritySpecies in CreatureDefinitions.SpeciesIdsByRarity do
        for _, speciesId in raritySpecies do
            discoveredSpecies[speciesId] = true
        end
    end
    for _, themeForms in MutationDefinitions.FormIdsByTheme do
        for _, formId in themeForms do
            discoveredForms[formId] = true
        end
    end
    expect(
        CodexModel.getSummary({ speciesIds = discoveredSpecies, mutationFormIds = discoveredForms })
            == "CODEX · 12/12 SPECIES · 24/24 FORMS"
    )

    expect(WorldConfig.MAP_FOOTPRINT_STUDS == 180 and WorldConfig.BASE_COUNT == 8)
    expect(WorldConfig.CHASE_SEGMENT_COUNT == 8)
    expect(#WorldConfig.ZONES == 3)
    expect(WorldConfig.ZONES[1] == "BaseRing")
    expect(WorldConfig.ZONES[2] == "Commons")
    expect(WorldConfig.ZONES[3] == "ChaseLoop")

    local cueCount = 0
    for cueId, cue in AudioCueConfig.CUES do
        expect(type(cueId) == "string" and type(cue.assetId) == "number" and cue.assetId > 0)
        expect(cue.volume > 0 and cue.volume <= 1 and cue.playbackSpeed > 0)
        cueCount += 1
    end
    expect(cueCount == 13)
    expect(AudioCueConfig.INCOME_CUE_MIN_INTERVAL_SECONDS >= 30)

    local visualIdCount = 0
    for _ in CreatureVisualDefinitions.Species do
        visualIdCount += 1
    end
    for _ in CreatureVisualDefinitions.Mutations do
        visualIdCount += 1
    end
    expect(visualIdCount == 36, "visual catalog cannot contain missing or extra IDs")

    local furthestBaseExtent = WorldConfig.BASE_RING_RADIUS
        + math.max(WorldConfig.BASE_PAD_SIZE_X, WorldConfig.BASE_PAD_SIZE_Z) / 2
    expect(furthestBaseExtent < WorldConfig.MAP_FOOTPRINT_STUDS / 2)
    for index = 1, WorldConfig.BASE_COUNT do
        local spawn = WorldConfig.getBaseSpawn(index, WorldConfig.BASE_COUNT)
        expect(spawn ~= nil and spawn.y == 5)
        local radius = math.sqrt(spawn.x * spawn.x + spawn.z * spawn.z)
        expect(math.abs(radius - WorldConfig.BASE_RING_RADIUS) <= 1)
    end
    expect(WorldConfig.getBaseSpawn(0, WorldConfig.BASE_COUNT) == nil)
    expect(WorldConfig.getBaseSpawn(WorldConfig.BASE_COUNT + 1, WorldConfig.BASE_COUNT) == nil)
end)

test("only an equipped Mythic mutation is announced server-wide", function()
    local player = {
        UserId = 81_001,
        Name = "TestPlayer",
        DisplayName = "OddlingFan",
        sessionId = "mythic-session-1",
        nearMutation = true,
    }
    local personalEvents = {}
    local globalEvents = {}
    local now = 100
    local actionService = ActionService.new({
        sessionService = {
            getSession = function(_self, candidate)
                if candidate == player then
                    return { userId = player.UserId, sessionId = player.sessionId }
                end
                return nil
            end,
        },
        raidService = {
            getSnapshot = function()
                return { phase = "PEACE" }
            end,
        },
        playerDataService = {
            getRevision = function()
                return 12
            end,
        },
        economyService = {
            refreshPlayer = function()
                return true
            end,
        },
        capsuleService = {},
        mutationService = {
            resolveMutation = function(_self, _userId, transactionId)
                if transactionId == "mythic-offer" then
                    return {
                        outcome = "Replaced",
                        activeFormId = "Starforge",
                        codexFormAdded = true,
                    }
                elseif transactionId == "common-offer" then
                    return {
                        outcome = "Replaced",
                        activeFormId = "Cinder",
                        codexFormAdded = false,
                    }
                end
                return { outcome = "KeptCurrent", activeFormId = "Cinder" }
            end,
        },
        theftService = {},
        baseService = {
            isOperational = function()
                return true
            end,
        },
        requestEvent = {},
        resultEvent = {},
        domainEvent = {
            FireClient = function(_self, _player, event)
                table.insert(personalEvents, event)
            end,
            FireAllClients = function(_self, event)
                table.insert(globalEvents, event)
            end,
        },
        clock = function()
            return now
        end,
        unixClock = function()
            return 1_000
        end,
        canInteract = function(candidate, station)
            return candidate.nearMutation and station == "mutation"
        end,
    })

    local function resolve(requestId, transactionId, choice)
        return actionService:handle(player, {
            sessionId = player.sessionId,
            requestId = requestId,
            action = "ResolveMutation",
            payload = { transactionId = transactionId, choice = choice },
        })
    end

    local mythic = resolve("mythic-resolve", "mythic-offer", "Replace")
    expect(mythic.ok and mythic.data.outcome == "Replaced")
    expect(#globalEvents == 1)
    local announcement = globalEvents[1]
    expect(announcement.event == Protocol.DomainEventNames.MythicEquipped)
    expect(announcement.data.playerDisplayName == "OddlingFan")
    expect(announcement.data.formId == "Starforge")
    expect(announcement.data.baseId == nil and announcement.data.position == nil)
    expect(announcement.revision == 12 and announcement.serverTimeUnix == 1_000)

    local personalCount = #personalEvents
    local replay = resolve("mythic-resolve", "mythic-offer", "Replace")
    expect(replay.ok and #globalEvents == 1 and #personalEvents == personalCount)
    expect(resolve("common-resolve", "common-offer", "Replace").ok)
    now += 1
    expect(resolve("kept-resolve", "kept-offer", "KeepCurrent").ok)
    expect(#globalEvents == 1, "common and kept mutations are not announced")
end)

test("profile validation rejects corrupt fields and unknown schema versions", function()
    local profile = PlayerDataService.createDefaultProfile(function()
        return "starter-id"
    end)
    local future = cloneTable(profile)
    future.schemaVersion = 99
    local validFuture, futureError = PlayerDataService.validateProfile(future)
    assert(
        not validFuture and futureError == "UnknownSchemaVersion",
        "future schema must not be overwritten"
    )

    local badBalance = cloneTable(profile)
    badBalance.scrap = -1
    assert(not PlayerDataService.validateProfile(badBalance), "negative Scrap must be rejected")

    local duplicateId = cloneTable(profile)
    duplicateId.creatures[2] = { id = "starter-id", speciesId = "Mossling" }
    duplicateId.discoveredSpeciesIds.Mossling = true
    duplicateId.slotCapacity = 2
    assert(
        not PlayerDataService.validateProfile(duplicateId),
        "duplicate creature IDs must be rejected"
    )
end)

test(
    "unpublished Studio selects volatile stores and preserves their scoped data contract",
    function()
        expect(
            StudioMemoryDataStoreService.isUnpublishedStudioSession(true, 0, 0),
            "unpublished Studio should use volatile stores"
        )
        expect(
            not StudioMemoryDataStoreService.isUnpublishedStudioSession(false, 0, 0),
            "live servers must never use volatile stores"
        )
        expect(
            not StudioMemoryDataStoreService.isUnpublishedStudioSession(true, 1, 0),
            "published places must use Roblox DataStores"
        )
        expect(
            not StudioMemoryDataStoreService.isUnpublishedStudioSession(true, 0, 1),
            "universe identity must also be absent for volatile stores"
        )

        local service = StudioMemoryDataStoreService.new()
        local profileStore = service:GetDataStore("OddlingsPlayerData")
        expect(
            profileStore == service:GetDataStore("OddlingsPlayerData"),
            "repeated store lookup should retain the same session-local store"
        )

        local stored, keyInfo = profileStore:UpdateAsync("Player_501", function(current)
            expect(current == nil, "the first write should receive an empty key")
            return { scrap = 50 }, { 501 }, { revision = 1 }
        end)
        expect(stored.scrap == 50, "UpdateAsync should store and return a cloned value")
        expect(keyInfo:GetMetadata().revision == 1, "key metadata should be retained")
        expect(keyInfo:GetUserIds()[1] == 501, "key user IDs should be retained")

        stored.scrap = 1
        expect(profileStore:GetAsync("Player_501").scrap == 50, "reads must not mutate stored data")

        local cancelled = profileStore:UpdateAsync("Player_501", function()
            return nil
        end)
        expect(cancelled == nil, "a nil transform result should cancel the update")
        expect(
            profileStore:GetAsync("Player_501").scrap == 50,
            "a cancelled update must keep the old value"
        )
        expect(
            service:GetDataStore("OddlingsTransferJournal"):GetAsync("Player_501") == nil,
            "different logical stores must have isolated records"
        )
    end
)

test("profile store atomically locks, saves, releases, and reloads one profile", function()
    local dataStore = makeFakeDataStore()
    local now = { value = 1_000 }
    local firstStore = makeProfileStore(dataStore, now, { value = 0 })
    local secondStore = makeProfileStore(dataStore, now, { value = 10 })
    local starterProfile = PlayerDataService.createDefaultProfile(function()
        return "stable-starter"
    end)
    local loaded, loadError = firstStore:load(501, starterProfile)
    assert(loadError == nil and loaded ~= nil, "first server should acquire the player profile")
    assert(
        dataStore.records.Player_501.metadata.oddSessionToken ~= nil,
        "lock should be written atomically"
    )

    local rejected, lockError = secondStore:load(501, starterProfile)
    assert(rejected == nil and lockError == "SessionLocked", "second writer must be rejected")
    assert(
        dataStore.records.Player_501.value.starterCreatureId == "stable-starter",
        "lock rejection must not alter data"
    )

    loaded.scrap = 175
    local saved, saveError = firstStore:save(501, loaded, false)
    assert(saved and saveError == nil, "checkpoint save should succeed")
    assert(
        dataStore.records.Player_501.metadata.oddSessionToken ~= nil,
        "checkpoint must renew the lock"
    )
    local released, releaseError = firstStore:save(501, loaded, true)
    assert(released and releaseError == nil, "final save should release the lock")
    assert(
        dataStore.records.Player_501.metadata.oddSaveRevision == 2,
        "profile saves should advance their stored revision"
    )
    assert(
        dataStore.records.Backup_Player_501.value.saveRevision == 2
            and dataStore.records.Backup_Player_501.value.profile.scrap == 175,
        "every confirmed save should leave a revisioned, validated backup"
    )
    assert(
        dataStore.records.Player_501.metadata.oddSessionToken == nil,
        "released profile should not retain its token"
    )

    local resumed, resumeError = secondStore:load(501, starterProfile)
    assert(resumeError == nil and resumed.scrap == 175, "rejoin should restore committed balance")
    assert(resumed.starterCreatureId == "stable-starter", "rejoin must not duplicate the starter")
end)

test("profile store preserves corrupt and future-version records", function()
    local dataStore = makeFakeDataStore()
    dataStore.records.Player_502 = {
        value = { schemaVersion = 99, scrap = 999 },
        userIds = { 502 },
        metadata = {},
    }
    local profileStore = makeProfileStore(dataStore)
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "unused-default"
    end)
    local profile, reason = profileStore:load(502, defaults)
    assert(profile == nil and reason == "UnknownSchemaVersion", "unknown versions must fail closed")
    assert(
        dataStore.records.Player_502.value.schemaVersion == 99,
        "unknown record must remain unchanged"
    )
    assert(
        dataStore.records.Player_502.metadata.oddSessionToken == nil,
        "corrupt record must not acquire a lock"
    )
end)

test("profile store quarantines corrupt data and restores a verified backup", function()
    local dataStore = makeFakeDataStore()
    local now = { value = 1_000 }
    local tokens = { value = 0 }
    local profileStore = makeProfileStore(dataStore, now, tokens)
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "backup-starter"
    end)
    local profile = profileStore:load(507, defaults)
    expect(profile ~= nil)
    profile.scrap = 777
    expect(profileStore:save(507, profile, true))
    dataStore.records.Player_507.value = { schemaVersion = 1, scrap = -1 }

    local recovered, recoveryError = profileStore:load(507, defaults)
    expect(recovered ~= nil and recoveryError == nil)
    expect(recovered.scrap == 777 and recovered.starterCreatureId == "backup-starter")
    expect(dataStore.records.Player_507.value.scrap == 777)
    expect(dataStore.records.Player_507.metadata.oddSessionToken ~= nil)
    local quarantine = nil
    for key, record in dataStore.records do
        if string.sub(key, 1, #"Quarantine_507_") == "Quarantine_507_" then
            quarantine = record.value
            break
        end
    end
    expect(quarantine ~= nil and quarantine.value.scrap == -1)
    expect(profileStore:save(507, recovered, true))
end)

test("profile store refuses to restore a backup older than the primary save revision", function()
    local dataStore = makeFakeDataStore()
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "stale-backup-starter"
    end)
    local profileStore = makeProfileStore(dataStore)
    local profile = profileStore:load(512, defaults)
    expect(profile ~= nil)
    expect(profileStore:save(512, profile, true))
    dataStore.records.Player_512.value = { schemaVersion = 1, scrap = -1 }
    dataStore.records.Player_512.metadata.oddSaveRevision += 1

    local recovered, reason = profileStore:load(512, defaults)
    expect(recovered == nil and string.find(reason, "StaleProfileBackup") ~= nil)
    expect(dataStore.records.Player_512.value.scrap == -1)
    expect(dataStore.records.Player_512.metadata.oddSessionToken == nil)
end)

test("profile store quarantines corruption but never trusts an invalid backup", function()
    local dataStore = makeFakeDataStore()
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "bad-backup-starter"
    end)
    dataStore.records.Player_508 = {
        value = { schemaVersion = 1, scrap = -5 },
        userIds = { 508 },
        metadata = {},
    }
    dataStore.records.Backup_Player_508 = {
        value = {
            version = 1,
            saveRevision = 1,
            profile = { schemaVersion = 1, scrap = -10 },
        },
        userIds = { 508 },
        metadata = {},
    }
    local profileStore = makeProfileStore(dataStore)
    local recovered, reason = profileStore:load(508, defaults)
    expect(recovered == nil and string.find(reason, "InvalidScrap") ~= nil)
    expect(dataStore.records.Player_508.value.scrap == -5)
    local quarantineExists = false
    for key in dataStore.records do
        quarantineExists = quarantineExists
            or string.sub(key, 1, #"Quarantine_508_") == "Quarantine_508_"
    end
    expect(quarantineExists, "the original corrupt value remains preserved in quarantine")
end)

test("profile store leaves quarantined corruption unavailable when no backup exists", function()
    local dataStore = makeFakeDataStore()
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "missing-backup-starter"
    end)
    dataStore.records.Player_510 = {
        value = { schemaVersion = 1, scrap = "broken" },
        userIds = { 510 },
        metadata = {},
    }
    local profileStore = makeProfileStore(dataStore)
    local recovered, reason = profileStore:load(510, defaults)
    expect(recovered == nil and string.find(reason, "BackupMissing") ~= nil)
    expect(dataStore.records.Player_510.value.scrap == "broken")
    local quarantined = false
    for key in dataStore.records do
        quarantined = quarantined or string.sub(key, 1, #"Quarantine_510_") == "Quarantine_510_"
    end
    expect(quarantined, "corrupt data is preserved without falling back to a fresh profile")
end)

test("schema-one legacy fixture keeps stable ownership without a fabricated migration", function()
    local dataStore = makeFakeDataStore()
    local legacy = PlayerDataService.createDefaultProfile(function()
        return "legacy-v1-starter"
    end)
    legacy.welcomeCreatureId = nil
    legacy.firstRaidParticipation = nil
    dataStore.records.Player_511 = {
        value = cloneTable(legacy),
        userIds = { 511 },
        metadata = {},
    }
    local profileStore = makeProfileStore(dataStore)
    local loaded, loadError = profileStore:load(511, legacy)
    expect(loaded ~= nil and loadError == nil)
    expect(loaded.schemaVersion == 1 and loaded.starterCreatureId == "legacy-v1-starter")
    expect(PlayerDataService.validateProfile(loaded))
    expect(profileStore:save(511, loaded, true))
end)

test("profile save exhaustion reports failure and keeps the session available for retry", function()
    local dataStore = makeFakeDataStore()
    local profileStore = makeProfileStore(dataStore)
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "retry-save-starter"
    end)
    local profile = profileStore:load(509, defaults)
    expect(profile ~= nil)
    profile.scrap = 250
    dataStore.failuresRemaining = 3
    local saved, saveError = profileStore:save(509, profile, false)
    expect(not saved and string.find(saveError, "DataStoreUnavailable") ~= nil)
    expect(dataStore.records.Player_509.value.scrap == 50)
    expect(dataStore.records.Player_509.metadata.oddSessionToken ~= nil)
    expect(profileStore:getLoadedCount() == 1)

    dataStore.failuresRemaining = 0
    expect(profileStore:save(509, profile, true))
    expect(dataStore.records.Player_509.value.scrap == 250)
    expect(dataStore.records.Backup_Player_509.value.profile.scrap == 250)
end)

test("expired session lease can be taken over and stale server cannot save", function()
    local dataStore = makeFakeDataStore()
    local now = { value = 1_000 }
    local firstStore = makeProfileStore(dataStore, now, { value = 0 })
    local secondStore = makeProfileStore(dataStore, now, { value = 20 })
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "lease-starter"
    end)
    local firstProfile = firstStore:load(505, defaults)
    assert(firstProfile ~= nil, "first server should acquire a lease")
    now.value += EconomyConfig.SESSION_LOCK_TTL_SECONDS + 1
    local secondProfile, secondError = secondStore:load(505, defaults)
    assert(secondProfile ~= nil and secondError == nil, "expired lease should permit takeover")

    firstProfile.scrap = 900
    local staleSaved, staleError = firstStore:save(505, firstProfile, false)
    assert(
        not staleSaved and staleError == "SessionLost",
        "old server must not overwrite the new owner"
    )
    assert(
        dataStore.records.Player_505.value.scrap == 50,
        "failed stale save must preserve stored progress"
    )
end)

test("malformed session metadata fails closed without overwriting the profile", function()
    local dataStore = makeFakeDataStore()
    local profile = PlayerDataService.createDefaultProfile(function()
        return "invalid-lock-starter"
    end)
    dataStore.records.Player_506 = {
        value = profile,
        userIds = { 506 },
        metadata = { oddSessionToken = "another-server-token" },
    }
    local profileStore = makeProfileStore(dataStore)
    local loaded, reason = profileStore:load(506, profile)
    assert(
        loaded == nil and reason == "InvalidSessionLock",
        "missing lock expiry must not allow takeover"
    )
    assert(
        dataStore.records.Player_506.value.scrap == 50,
        "invalid lock metadata must not replace profile data"
    )
    assert(
        dataStore.records.Player_506.metadata.oddSessionToken == "another-server-token",
        "failed acquisition must not clear existing lock metadata"
    )
end)

test("profile store retries transient failures with a bounded attempt count", function()
    local dataStore = makeFakeDataStore()
    dataStore.failuresRemaining = 2
    local waits = 0
    local profileStore = ProfileStore.new({
        store = dataStore,
        validate = PlayerDataService.validateProfile,
        clock = function()
            return 1_000
        end,
        generateToken = function()
            return "retry-session-token"
        end,
        wait = function()
            waits += 1
        end,
        maxAttempts = 3,
    })
    local defaults = PlayerDataService.createDefaultProfile(function()
        return "retry-starter"
    end)
    local profile, reason = profileStore:load(503, defaults)
    assert(profile ~= nil and reason == nil, "retry should recover on the final allowed attempt")
    assert(dataStore.calls == 3, "retry count must stay within the configured limit")
    assert(waits == 2, "backoff should happen only between attempts")

    local failingStore = makeFakeDataStore()
    failingStore.failuresRemaining = 8
    local failingProfileStore = makeProfileStore(failingStore)
    local unavailable, failureReason = failingProfileStore:load(504, defaults)
    assert(
        unavailable == nil and string.find(failureReason, "DataStoreUnavailable") ~= nil,
        "exhausted retries must fail closed"
    )
    assert(failingStore.calls == 3, "exhausted retries must not loop forever")
end)

test("player data saves balance and restores the same starter on rejoin", function()
    local dataStore = makeFakeDataStore()
    local profileStore = makeProfileStore(dataStore)
    local idSequence = 0
    local function makeDataService()
        return PlayerDataService.new({
            profileStore = profileStore,
            clock = function()
                return 1_000
            end,
            generateCreatureId = function()
                idSequence += 1
                return "starter-" .. tostring(idSequence)
            end,
            autoSaveEnabled = false,
            wait = function() end,
        })
    end

    local firstSession = makeDataService()
    assert(firstSession:load(601), "first profile load should succeed")
    local original = firstSession:getSnapshot(601)
    local credited, amount, newBalance = firstSession:creditScrap(601, 75)
    assert(
        credited and amount == 75 and newBalance == 125,
        "server credit should update the loaded profile"
    )
    assert(firstSession:unload(601), "player leave should save and release the profile")

    local nextSession = makeDataService()
    assert(nextSession:load(601), "rejoin should load committed profile")
    local restored = nextSession:getSnapshot(601)
    assert(restored.scrap == 125, "saved balance should be restored")
    assert(
        restored.starterCreatureId == original.starterCreatureId,
        "starter ID should remain stable across sessions"
    )
    assert(#restored.creatures == 1, "rejoin must not duplicate the starter")
end)

test("shutdown saves profiles in parallel and releases session leases", function()
    local dataStore = makeFakeDataStore()
    local profileStore = makeProfileStore(dataStore)
    local dataService = PlayerDataService.new({
        profileStore = profileStore,
        clock = function()
            return 1_000
        end,
        generateCreatureId = function()
            return "shutdown-starter"
        end,
        autoSaveEnabled = false,
        schedule = function(callback)
            callback()
        end,
        wait = function() end,
    })
    assert(dataService:load(650), "shutdown profile should load")
    local saved, failures = dataService:saveAllAndRelease(1)
    assert(saved and failures == 0, "shutdown save should finish within the bounded wait")
    assert(dataService:getSnapshot(650) == nil, "saved profile should leave memory on shutdown")
    assert(
        dataStore.records.Player_650.metadata.oddSessionToken == nil,
        "shutdown save should release its lock"
    )
    expect(
        #dataStore.records.Player_650.value.creatures == 1
            and dataStore.records.Player_650.value.creatures[1].id == "shutdown-starter",
        "shutdown should persist normal ownership without duplication"
    )
end)

test("shutdown during carry returns the creature before either profile is saved", function()
    local context = makeTheftContext()
    local attemptId = beginAndCarryTheft(context)
    expect(context.theftService:shutdown(1))
    expect(context.theftService._attempts[attemptId].state == "RETURNED")

    local ownerData = context.dataServices[context.ownerUserId]
    local thiefData = context.dataServices[context.thiefUserId]
    expect(ownerData:saveAllAndRelease(1))
    expect(thiefData:saveAllAndRelease(1))
    local ownerProfile =
        context.profileDataStore.records["Player_" .. tostring(context.ownerUserId)].value
    local thiefProfile =
        context.profileDataStore.records["Player_" .. tostring(context.thiefUserId)].value
    expect(CreatureService.findInProfile(nil, ownerProfile, context.targetId) ~= nil)
    expect(CreatureService.findInProfile(nil, thiefProfile, context.targetId) == nil)
end)

test(
    "shutdown waits for an ambiguous bank decision and committed replay saves one owner",
    function()
        local context = makeTheftContext()
        local deferred = {}
        context.theftService._schedule = function(callback)
            table.insert(deferred, callback)
        end
        local attemptId = beginAndCarryTheft(context)
        expect(context.theftService:beginBank(context.thiefUserId, attemptId))
        context.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
        context.journalDataStore.failOnCalls = {
            [2] = true,
            [3] = true,
            [4] = true,
            [5] = true,
            [6] = true,
            [7] = true,
        }
        local pending, failure =
            context.theftService:completeBank(context.thiefUserId, attemptId, "Moss")
        expect(pending == nil and failure == "ServiceUnavailable")
        expect(context.theftService._attempts[attemptId].state == "COMMITTING")
        expect(not context.theftService:shutdown(0), "shutdown must report an unresolved bank")

        context.journalDataStore.failOnCalls = nil
        local resolve = table.remove(deferred, 1)
        expect(type(resolve) == "function")
        resolve()
        expect(context.theftService._attempts[attemptId].state == "BANKED")
        expect(context.theftService:shutdown(1))

        local ownerData = context.dataServices[context.ownerUserId]
        local thiefData = context.dataServices[context.thiefUserId]
        expect(ownerData:saveAllAndRelease(1))
        expect(thiefData:saveAllAndRelease(1))
        local ownerProfile =
            context.profileDataStore.records["Player_" .. tostring(context.ownerUserId)].value
        local thiefProfile =
            context.profileDataStore.records["Player_" .. tostring(context.thiefUserId)].value
        expect(CreatureService.findInProfile(nil, ownerProfile, context.targetId) == nil)
        expect(CreatureService.findInProfile(nil, thiefProfile, context.targetId) ~= nil)
        expect(thiefProfile.catalysts.mossSpore == 1)
    end
)

test(
    "transfer journal records intent, commits, and clears only after both profiles apply",
    function()
        local fakeStore = makeFakeDataStore()
        local journal = TransferJournalStore.new({ store = fakeStore, wait = function() end })
        local record = {
            transferId = "transfer-1",
            fromUserId = 701,
            toUserId = 702,
            raidId = "raid-1",
            creature = { id = "creature-1", speciesId = "PocketHydra" },
            catalystThemeId = "Prism",
            createdAtUnix = 1_000,
        }
        local prepared = journal:prepare(record)
        expect(prepared)
        expect(journal:prepare(record), "replaying the same journal intent is idempotent")
        local ownerRecords = journal:getForUser(701)
        expect(#ownerRecords == 1 and ownerRecords[1].state == "PREPARED")
        expect(#journal:getForUser(702) == 1)

        local conflict = cloneTable(record)
        conflict.toUserId = 703
        local conflictingPrepare = journal:prepare(conflict)
        expect(not conflictingPrepare, "a transfer ID cannot be reused for another recipient")
        expect(journal:commit("transfer-1"))
        expect(journal:getForUser(701)[1].state == "COMMITTED")

        expect(journal:markApplied("transfer-1", 701))
        expect(#journal:getForUser(701) == 1, "one applied profile cannot clear the other receipt")
        expect(journal:markApplied("transfer-1", 702))
        expect(#journal:getForUser(701) == 0 and #journal:getForUser(702) == 0)
    end
)

test("profile load rolls PREPARED transfers back and COMMITTED transfers forward", function()
    local function loadPair(state: string, ownerHasCreature: boolean, thiefHasCreature: boolean)
        local fakeStore = makeFakeDataStore()
        local ownerProfile = PlayerDataService.createDefaultProfile(function()
            return "owner-starter"
        end)
        local thiefProfile = PlayerDataService.createDefaultProfile(function()
            return "thief-starter"
        end)
        ownerProfile.slotCapacity = 3
        thiefProfile.slotCapacity = 3
        local creature = { id = "journal-creature", speciesId = "PocketHydra" }
        if ownerHasCreature then
            table.insert(ownerProfile.creatures, cloneTable(creature))
            ownerProfile.discoveredSpeciesIds.PocketHydra = true
        end
        if thiefHasCreature then
            table.insert(thiefProfile.creatures, cloneTable(creature))
            thiefProfile.discoveredSpeciesIds.PocketHydra = true
            thiefProfile.catalysts.prismDust = 1
        end
        fakeStore.records.Player_711 = {
            value = cloneTable(ownerProfile),
            userIds = { 711 },
            metadata = {},
        }
        fakeStore.records.Player_712 = {
            value = cloneTable(thiefProfile),
            userIds = { 712 },
            metadata = {},
        }

        local journal = TransferJournalStore.new({ store = fakeStore, wait = function() end })
        local transfer = {
            transferId = "journal-transfer",
            fromUserId = 711,
            toUserId = 712,
            raidId = "journal-raid",
            creature = creature,
            catalystThemeId = "Prism",
            createdAtUnix = 1_000,
        }
        assert(journal:prepare(transfer), "journal intent should be prepared")
        if state == "COMMITTED" then
            assert(journal:commit(transfer.transferId), "transfer should commit")
        end

        local nextCreatureId = 0
        local dataService = PlayerDataService.new({
            profileStore = makeProfileStore(fakeStore),
            transferJournalStore = journal,
            clock = function()
                return 1_000
            end,
            generateCreatureId = function()
                nextCreatureId += 1
                return "journal-default-" .. tostring(nextCreatureId)
            end,
            autoSaveEnabled = false,
            wait = function() end,
        })
        local ownerLoaded, ownerError = dataService:load(711)
        assert(
            ownerLoaded,
            "owner profile should recover before gameplay: " .. tostring(ownerError)
        )
        local thiefLoaded, thiefError = dataService:load(712)
        assert(
            thiefLoaded,
            "thief profile should recover before gameplay: " .. tostring(thiefError)
        )
        return dataService, fakeStore, journal
    end

    local rollback, rollbackStore, rollbackJournal = loadPair("PREPARED", false, true)
    local restoredOwner = rollback:getSnapshot(711)
    local restoredThief = rollback:getSnapshot(712)
    expect(#restoredOwner.creatures == 2)
    expect(restoredOwner.creatures[2].id == "journal-creature")
    expect(
        #restoredThief.creatures == 1 and restoredThief.catalysts.prismDust == 1,
        "rollback must not remove a catalyst the profile already owned"
    )
    expect(#rollbackJournal:getForUser(711) == 0)
    expect(rollbackStore.records.Player_711.value.creatures[2].id == "journal-creature")

    local commit, commitStore, commitJournal = loadPair("COMMITTED", false, false)
    local committedOwner = commit:getSnapshot(711)
    local committedThief = commit:getSnapshot(712)
    expect(#committedOwner.creatures == 1)
    expect(#committedThief.creatures == 2)
    expect(committedThief.creatures[2].id == "journal-creature")
    expect(committedThief.catalysts.prismDust == 1)
    expect(#commitJournal:getForUser(712) == 0)
    expect(commitStore.records.Player_712.value.creatures[2].id == "journal-creature")
end)

test("transfer journal retries storage errors and stays bounded and schema-strict", function()
    local retryStore = makeFakeDataStore()
    retryStore.failuresRemaining = 2
    local waits = 0
    local journal = TransferJournalStore.new({
        store = retryStore,
        wait = function()
            waits += 1
        end,
    })
    local record = {
        transferId = "retry-journal",
        fromUserId = 901,
        toUserId = 902,
        raidId = "retry-raid",
        creature = { id = "retry-creature", speciesId = "PocketHydra" },
        catalystThemeId = "Ember",
        createdAtUnix = 1_000,
    }
    expect(journal:prepare(record), "prepared writes retry within the configured limit")
    expect(retryStore.calls == 3 and waits == 2)
    retryStore.failAfterWriteOnCall = 4
    expect(journal:commit(record.transferId), "an ambiguous committed write is idempotent")
    retryStore.getFailuresRemaining = 2
    local recoveredRecords = journal:getForUser(record.toUserId)
    expect(#recoveredRecords == 1 and recoveredRecords[1].state == "COMMITTED")
    expect(waits == 5, "read and write retries use bounded backoff")

    local strictStore = makeFakeDataStore()
    local strictJournal = TransferJournalStore.new({ store = strictStore, wait = function() end })
    expect(strictJournal:prepare(record))
    strictStore.records.OddlingsTransfersV1.value.records[record.transferId].unexpected = true
    local corruptRecords, corruptError = strictJournal:getForUser(record.fromUserId)
    expect(corruptRecords == nil and corruptError == "InvalidTransferJournal")

    local boundedStore = makeFakeDataStore()
    local boundedJournal = TransferJournalStore.new({ store = boundedStore, wait = function() end })
    for index = 1, 64 do
        local boundedRecord = {
            transferId = "bounded-" .. tostring(index),
            fromUserId = 10_000 + index,
            toUserId = 20_000 + index,
            raidId = "bounded-raid",
            creature = { id = "bounded-creature-" .. tostring(index), speciesId = "PocketHydra" },
            catalystThemeId = "Prism",
            createdAtUnix = 1_000,
        }
        expect(boundedJournal:prepare(boundedRecord))
    end
    local overflow, overflowError = boundedJournal:prepare({
        transferId = "bounded-overflow",
        fromUserId = 30_001,
        toUserId = 30_002,
        raidId = "bounded-raid",
        creature = { id = "bounded-overflow-creature", speciesId = "PocketHydra" },
        catalystThemeId = "Moss",
        createdAtUnix = 1_000,
    })
    expect(not overflow and overflowError == "TransferJournalUnavailable")
    local count = 0
    for _ in boundedStore.records.OddlingsTransfersV1.value.records do
        count += 1
    end
    expect(count == 64, "journal overflow fails closed without evicting transfers")
end)

test("failed transfer intent preparation preserves the original owner and can retry", function()
    local context = makeTheftContext()
    local attemptId = beginAndCarryTheft(context)
    expect(context.theftService:beginBank(context.thiefUserId, attemptId))
    context.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
    context.journalDataStore.failuresRemaining = 3
    local bankFailed, failure =
        context.theftService:completeBank(context.thiefUserId, attemptId, "Prism")
    expect(bankFailed == nil and failure == "ServiceUnavailable")
    expect(context.theftService._attempts[attemptId].state == "CARRIED")
    expect(
        CreatureService.findInProfile(
            nil,
            context.dataService:getSnapshot(context.ownerUserId),
            context.targetId
        )
    )
    expect(
        CreatureService.findInProfile(
            nil,
            context.dataService:getSnapshot(context.thiefUserId),
            context.targetId
        ) == nil
    )
    local emptyJournal = context.journalDataStore.records.OddlingsTransfersV1.value
    expect(next(emptyJournal.records) == nil)

    expect(context.theftService:beginBank(context.thiefUserId, attemptId))
    context.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
    expect(context.theftService:completeBank(context.thiefUserId, attemptId, "Prism"))
    expect(
        CreatureService.findInProfile(
            nil,
            context.dataService:getSnapshot(context.thiefUserId),
            context.targetId
        )
    )
end)

test("elapsed first-Raid marker is normalized before profile exposure", function()
    local dataStore = makeFakeDataStore()
    local profile = PlayerDataService.createDefaultProfile(function()
        return "marker-starter"
    end)
    profile.firstRaidParticipation = { raidId = "raid-1", completesAtUnix = 999 }
    dataStore.records.Player_606 = { value = profile, userIds = { 606 }, metadata = {} }
    local service = PlayerDataService.new({
        profileStore = makeProfileStore(dataStore),
        clock = function()
            return 1_000
        end,
        generateCreatureId = function()
            return "unused-marker-starter"
        end,
        autoSaveEnabled = false,
    })
    assert(service:load(606), "profile should load and normalize")
    local normalized = service:getSnapshot(606)
    assert(
        normalized.hasCompletedFirstRaid,
        "elapsed first Raid must finalize before gameplay access"
    )
    assert(normalized.firstRaidParticipation == nil, "finalized marker must be cleared")
    assert(
        dataStore.records.Player_606.value.hasCompletedFirstRaid,
        "normalization must be durably saved before ready"
    )
    assert(
        dataStore.records.Player_606.value.firstRaidParticipation == nil,
        "durable marker must also be cleared"
    )
end)

test("first-Raid participation markers save immediately and never get replaced", function()
    local dataService, dataStore = makeLoadedDataService(607, "first-raid-")
    local started, marker = dataService:beginFirstRaidParticipation(607, "first-raid-a", 2_000)
    expect(started and marker.raidId == "first-raid-a")
    expect(marker.completesAtUnix == 2_000)
    expect(
        dataStore.records.Player_607.value.firstRaidParticipation.raidId == "first-raid-a",
        "participation must be durably saved before returning"
    )
    local repeated, existing = dataService:beginFirstRaidParticipation(607, "later-raid", 3_000)
    expect(repeated and existing.raidId == "first-raid-a")
    expect(existing.completesAtUnix == 2_000, "a prior marker must never be replaced")

    local early, _, earlyError =
        dataService:finalizeFirstRaidParticipation(607, "first-raid-a", 2_000, 1_999)
    expect(not early and earlyError == "NotExpired")
    local finalized, changed =
        dataService:finalizeFirstRaidParticipation(607, "first-raid-a", 2_000, 2_000)
    expect(finalized and changed, "the exact completion timestamp expires protection")
    local profile = dataService:getSnapshot(607)
    expect(profile.hasCompletedFirstRaid and profile.firstRaidParticipation == nil)
    expect(dataStore.records.Player_607.value.hasCompletedFirstRaid)
end)

test("Raid start marks present players and finalizes them at Resolution end", function()
    local now = { value = 1_000 }
    local onlineUsers = { 610, 611 }
    local markers = {}
    local completed = {}
    local analyticsEvents = {}
    local service = RaidService.new({
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "welcome-raid-" .. tostring(sequence)
        end,
        getPlayerUserIds = function()
            return onlineUsers
        end,
        beginFirstRaidParticipation = function(userId, raidId, completesAtUnix)
            local created = markers[userId] == nil
            if markers[userId] == nil then
                markers[userId] = { raidId = raidId, completesAtUnix = completesAtUnix }
            end
            return true, markers[userId], nil, created
        end,
        emitAnalytics = function(userId, event, properties)
            table.insert(analyticsEvents, {
                userId = userId,
                event = event,
                properties = cloneTable(properties),
            })
        end,
        getParticipationMarker = function(userId)
            return markers[userId]
        end,
        finalizeFirstRaidParticipation = function(userId, raidId, completesAtUnix, timestamp)
            local marker = markers[userId]
            if
                marker ~= nil
                and marker.raidId == raidId
                and marker.completesAtUnix == completesAtUnix
                and timestamp >= completesAtUnix
            then
                markers[userId] = nil
                completed[userId] = true
                return true, true
            end
            return true, false
        end,
    })

    now.value = 1_300
    expect(service:step())
    now.value = 1_330
    expect(service:step())
    local raidId = service:getSnapshot().raidId
    for _, userId in onlineUsers do
        expect(markers[userId] ~= nil, "players present at Raid start participate immediately")
        expect(markers[userId].raidId == raidId)
        expect(markers[userId].completesAtUnix == 1_450)
    end
    expect(#analyticsEvents == 2, "only newly created participation markers are tracked")
    for _, event in analyticsEvents do
        expect(event.event == "first_raid_participated")
        expect(event.properties.reason == "raid_start")
    end

    now.value = 1_420
    expect(service:step())
    expect(not completed[610], "first-Raid protection remains through RESOLUTION")
    now.value = 1_450
    expect(service:step())
    expect(completed[610] and completed[611], "completion expires protection at COOLDOWN")
    expect(markers[610] == nil and markers[611] == nil)
    local completionCount = 0
    for _, event in analyticsEvents do
        if event.event == "first_raid_completed" then
            completionCount += 1
        end
    end
    expect(completionCount == 2, "first-Raid completion events should match persisted transitions")
end)

test("late arrival grace participates only when expiry is strictly before Raid end", function()
    local now = { value = 0 }
    local markers = {}
    local analyticsEvents = {}
    local service = RaidService.new({
        initialPhase = "RAID",
        clock = function()
            return now.value
        end,
        generateRaidId = function(sequence)
            return "late-welcome-" .. tostring(sequence)
        end,
        beginFirstRaidParticipation = function(userId, raidId, completesAtUnix)
            local created = markers[userId] == nil
            markers[userId] = markers[userId]
                or {
                    raidId = raidId,
                    completesAtUnix = completesAtUnix,
                }
            return true, markers[userId], nil, created
        end,
        emitAnalytics = function(userId, event, properties)
            table.insert(analyticsEvents, {
                userId = userId,
                event = event,
                properties = cloneTable(properties),
            })
        end,
    })
    local raidId = service:getSnapshot().raidId
    now.value = 70
    expect(service:onOperationalChanged(621, true, raidId))
    now.value = 75
    expect(service:onOperationalChanged(620, true, raidId))
    now.value = 80
    expect(service:onOperationalChanged(622, true, raidId))
    expect(#analyticsEvents == 3, "each ready mid-Raid join should log grace once")
    now.value = 85
    expect(service:step())
    expect(markers[621] ~= nil, "grace expiring at 85 begins first-Raid participation")
    expect(markers[621].completesAtUnix == 120)
    local participationReason = nil
    for _, event in analyticsEvents do
        if event.event == "first_raid_participated" then
            participationReason = event.properties.reason
        end
    end
    expect(
        participationReason == "arrival_grace_expired",
        "eligible late join should record its server-determined participation reason"
    )
    local eligibleExpiry = false
    for _, event in analyticsEvents do
        if event.event == "arrival_grace_expired" then
            eligibleExpiry = event.properties.eligible == true
        end
    end
    expect(eligibleExpiry, "grace expiry before Raid end should be tracked as eligible")
    expect(markers[620] == nil, "grace expiring exactly at Raid end is ineligible")
    now.value = 90
    expect(service:step())
    expect(markers[620] == nil, "exact-boundary expiry must not consume protection")
    local exactExpiry = false
    for _, event in analyticsEvents do
        if event.event == "arrival_grace_expired" and event.userId == 620 then
            exactExpiry = event.properties.eligible == false
        end
    end
    expect(exactExpiry, "grace expiry at Raid end should be recorded as ineligible")
    now.value = 95
    expect(service:step())
    local lateExpiry = false
    for _, event in analyticsEvents do
        if event.event == "arrival_grace_expired" and event.userId == 622 then
            lateExpiry = event.properties.eligible == false
        end
    end
    expect(lateExpiry, "grace expiry after Raid end should not consume first-Raid protection")
end)

test("theft channels server-side, carries one item, and commits a journaled bank", function()
    local bankEvents = {}
    local analyticsEvents = {}
    local context = makeTheftContext({
        emitToUser = function(userId, event, data)
            table.insert(bankEvents, {
                userId = userId,
                event = event,
                data = cloneTable(data),
            })
        end,
        emitAnalytics = function(userId, event, properties)
            table.insert(analyticsEvents, {
                userId = userId,
                event = event,
                properties = cloneTable(properties),
            })
        end,
    })
    local ownerBefore = context.dataService:getSnapshot(context.ownerUserId)
    local thiefBefore = context.dataService:getSnapshot(context.thiefUserId)
    local started, startError =
        context.theftService:beginTheft(context.thiefUserId, context.targetId)
    expect(started ~= nil and startError == nil)
    expect(started.targetUserId == context.ownerUserId)
    expect(context.theftService._attempts[started.attemptId].state == "CHANNELING")
    expect(context.dataService:getSnapshot(context.ownerUserId).creatures[2].id == context.targetId)
    expect(
        #context.dataService:getSnapshot(context.thiefUserId).creatures == #thiefBefore.creatures
    )

    context.monotonicNow.value += RaidConfig.THEFT_CHANNEL_SECONDS
    expect(context.theftService:step(context.monotonicNow.value))
    local attempt = context.theftService._attempts[started.attemptId]
    expect(attempt.state == "CARRIED")
    expect(
        context.players[context.thiefUserId].attributes.OddlingsCarriedCreatureId
            == context.targetId
    )
    expect(context.humanoids[context.thiefUserId].WalkSpeed == 16 * 0.8)
    context.humanoids[context.thiefUserId].toolsEquipped = true
    expect(context.theftService:step(context.monotonicNow.value))
    expect(
        context.humanoids[context.thiefUserId].toolsEquipped == false,
        "re-equipped tools are removed while carrying"
    )
    expect(context.humanoids[context.thiefUserId].JumpPower == 0)
    expect(context.dataService:getSnapshot(context.ownerUserId).creatures[2].id == context.targetId)

    context.positions[context.thiefUserId] =
        context.baseService:getHomePadPosition(context.thiefUserId)
    local bank, bankError = context.theftService:beginBank(context.thiefUserId, started.attemptId)
    expect(bank ~= nil and bankError == nil)
    context.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
    local result, resultError =
        context.theftService:completeBank(context.thiefUserId, started.attemptId, "Ember")
    expect(result ~= nil and resultError == nil)
    expect(result.creatureId == context.targetId and result.catalystThemeId == "Ember")
    local ownerAfter = context.dataService:getSnapshot(context.ownerUserId)
    local thiefAfter = context.dataService:getSnapshot(context.thiefUserId)
    expect(CreatureService.findInProfile(nil, ownerAfter, context.targetId) == nil)
    expect(CreatureService.findInProfile(nil, thiefAfter, context.targetId) ~= nil)
    expect(thiefAfter.catalysts.emberSeed == 1, "one chosen theft catalyst is granted after bank")
    expect(
        #ownerAfter.creatures + #thiefAfter.creatures
            == #ownerBefore.creatures + #thiefBefore.creatures
    )
    expect(context.players[context.thiefUserId].attributes.OddlingsCarriedCreatureId == nil)
    expect(context.humanoids[context.thiefUserId].WalkSpeed == 16)
    expect(context.humanoids[context.thiefUserId].JumpPower == 50)
    local ownerRemoved = false
    local thiefAdded = false
    for _, message in bankEvents do
        if message.event == Protocol.DomainEventNames.CreatureChanged then
            ownerRemoved = ownerRemoved
                or (message.userId == context.ownerUserId and message.data.change == "Removed")
            thiefAdded = thiefAdded
                or (
                    message.userId == context.thiefUserId
                    and message.data.change == "Added"
                    and message.data.creature.id == context.targetId
                )
        end
    end
    expect(ownerRemoved and thiefAdded, "bank emits the committed ownership change to both players")
    local lostTracked = false
    local bankTracked = false
    for _, event in analyticsEvents do
        lostTracked = lostTracked
            or (event.userId == context.ownerUserId and event.event == "creature_lost")
        bankTracked = bankTracked
            or (event.userId == context.thiefUserId and event.event == "theft_banked")
    end
    expect(lostTracked and bankTracked, "only the committed bank records loss and theft analytics")
end)

test("a cancellation at the completed channel boundary cannot undo a valid theft", function()
    local context = makeTheftContext()
    local begun, beginError = context.theftService:beginTheft(context.thiefUserId, context.targetId)
    expect(begun ~= nil and beginError == nil)

    context.monotonicNow.value += RaidConfig.THEFT_CHANNEL_SECONDS
    local cancelled, cancelError =
        context.theftService:cancelTheft(context.thiefUserId, begun.attemptId)
    expect(cancelled == nil and cancelError == "Locked")
    expect(
        context.theftService._attempts[begun.attemptId].state == "CARRIED",
        "the server must complete a valid elapsed channel before accepting cancellation"
    )
end)

test(
    "theft locks same-owner races, protects starter and Welcome, and rejects full thief capacity",
    function()
        local contested = makeTheftContext({
            userIds = { 1_211, 1_212, 1_213 },
            ownerCapacity = 4,
            extraOwnerTargets = 2,
        })
        local first, firstError =
            contested.theftService:beginTheft(contested.thiefUserId, contested.targetId)
        expect(first ~= nil and firstError == nil)
        contested.positions[1_213] =
            contested.baseService:getCreatureDisplayPosition(contested.ownerUserId, "theft-extra-1")
        local sameOwner, sameOwnerError = contested.theftService:beginTheft(1_213, "theft-extra-1")
        expect(
            sameOwner == nil and sameOwnerError == "Locked",
            "one channel locks the whole owner base"
        )
        local sameCreature, sameCreatureError =
            contested.theftService:beginTheft(1_213, contested.targetId)
        expect(
            sameCreature == nil and sameCreatureError == "Locked",
            "only one thief gets the target lock"
        )

        local protectionEvents = {}
        local protected = makeTheftContext({
            welcomeTarget = true,
            emitAnalytics = function(userId, event, properties)
                table.insert(protectionEvents, {
                    userId = userId,
                    event = event,
                    properties = cloneTable(properties),
                })
            end,
        })
        local welcome, welcomeError =
            protected.theftService:beginTheft(protected.thiefUserId, protected.targetId)
        expect(
            welcome == nil and welcomeError == "Locked",
            "unexpired Welcome creature stays protected"
        )
        local welcomeProtectionTracked = false
        for _, event in protectionEvents do
            welcomeProtectionTracked = welcomeProtectionTracked
                or (
                    event.event == "theft_protection_check"
                    and event.properties.role == "actor"
                    and event.properties.welcomeProtected
                )
        end
        expect(
            welcomeProtectionTracked,
            "server should record Welcome protection at a valid attempt"
        )
        local starterId = protected.dataService:getSnapshot(protected.ownerUserId).starterCreatureId
        protected.positions[protected.thiefUserId] =
            protected.baseService:getCreatureDisplayPosition(protected.ownerUserId, starterId)
        local starter, starterError =
            protected.theftService:beginTheft(protected.thiefUserId, starterId)
        expect(
            starter == nil and starterError == "Locked",
            "starter Mossling stays permanently protected"
        )

        local full = makeTheftContext({ fillThief = true })
        local fullResult, fullError = full.theftService:beginTheft(full.thiefUserId, full.targetId)
        expect(
            fullResult == nil and fullError == "CapacityFull",
            "a full thief cannot reserve a slot"
        )

        local completedWelcome = makeTheftContext({
            welcomeTarget = true,
            participationMarker = { raidId = "previous-raid", completesAtUnix = 990 },
        })
        local expiredProtection = completedWelcome.theftService:beginTheft(
            completedWelcome.thiefUserId,
            completedWelcome.targetId
        )
        expect(
            expiredProtection ~= nil,
            "an elapsed participation marker expires Welcome protection"
        )

        local thiefGraceEvents = {}
        local thiefGrace = makeTheftContext({
            graceUserId = 1_202,
            emitAnalytics = function(userId, event, properties)
                table.insert(
                    thiefGraceEvents,
                    { userId = userId, event = event, properties = properties }
                )
            end,
        })
        local graceAttempt, graceError =
            thiefGrace.theftService:beginTheft(thiefGrace.thiefUserId, thiefGrace.targetId)
        expect(
            graceAttempt == nil and graceError == "Locked",
            "arrival grace blocks theft initiation"
        )
        expect(
            thiefGraceEvents[1].properties.thiefArrivalGrace,
            "server should record outgoing arrival-grace protection"
        )
        local ownerGraceEvents = {}
        local ownerGrace = makeTheftContext({
            graceUserId = 1_201,
            emitAnalytics = function(userId, event, properties)
                table.insert(
                    ownerGraceEvents,
                    { userId = userId, event = event, properties = properties }
                )
            end,
        })
        local protectedBase, protectedBaseError =
            ownerGrace.theftService:beginTheft(ownerGrace.thiefUserId, ownerGrace.targetId)
        expect(
            protectedBase == nil and protectedBaseError == "Locked",
            "arrival grace protects the new owner's base"
        )
        local ownerGraceTracked = false
        for _, event in ownerGraceEvents do
            ownerGraceTracked = ownerGraceTracked
                or (event.event == "theft_protection_check" and event.properties.ownerArrivalGrace)
        end
        expect(ownerGraceTracked, "server should record incoming arrival-grace protection")
    end
)

test("creature attempts and theft limits remain fixed for each Raid", function()
    local context = makeTheftContext({ ownerCapacity = 4, extraOwnerTargets = 2 })
    local first, firstError = context.theftService:beginTheft(context.thiefUserId, context.targetId)
    expect(first ~= nil and firstError == nil)
    expect(context.theftService:cancelTheft(context.thiefUserId, first.attemptId))
    local repeated, repeatedError =
        context.theftService:beginTheft(context.thiefUserId, context.targetId)
    expect(
        repeated == nil and repeatedError == "Locked",
        "the same creature is closed for this Raid"
    )

    context.positions[context.thiefUserId] =
        context.baseService:getCreatureDisplayPosition(context.ownerUserId, "theft-extra-1")
    local second, secondError =
        context.theftService:beginTheft(context.thiefUserId, "theft-extra-1")
    expect(second ~= nil and secondError == nil)
    expect(context.theftService:cancelTheft(context.thiefUserId, second.attemptId))
    context.positions[context.thiefUserId] =
        context.baseService:getCreatureDisplayPosition(context.ownerUserId, "theft-extra-2")
    local third, thirdError = context.theftService:beginTheft(context.thiefUserId, "theft-extra-2")
    expect(third == nil and thirdError == "Locked", "attempt three is rejected")

    local banked = makeTheftContext({
        userIds = { 1_221, 1_222, 1_223 },
        ownerCapacity = 3,
        extraOwnerTargets = 1,
    })
    local attemptId = beginAndCarryTheft(banked)
    banked.positions[banked.thiefUserId] = banked.baseService:getHomePadPosition(banked.thiefUserId)
    expect(banked.theftService:beginBank(banked.thiefUserId, attemptId))
    banked.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
    expect(banked.theftService:completeBank(banked.thiefUserId, attemptId, "Prism"))
    banked.positions[1_223] =
        banked.baseService:getCreatureDisplayPosition(banked.ownerUserId, "theft-extra-1")
    local secondBankAttempt, secondBankError =
        banked.theftService:beginTheft(banked.thiefUserId, "theft-extra-1")
    expect(secondBankAttempt == nil and secondBankError == "Locked", "a thief cannot bank twice")
    local otherThief, otherThiefError = banked.theftService:beginTheft(1_223, "theft-extra-1")
    expect(
        otherThief == nil and otherThiefError == "Locked",
        "an owner cannot lose twice in one Raid"
    )
    expect(banked.theftService._raidOwnerLosses[banked.ownerUserId] == "theft-raid-1")
end)

test(
    "Tag cancels channels, drops carries, enforces cooldown, and recovery returns ownership",
    function()
        local tagAnalytics = {}
        local context = makeTheftContext({
            emitAnalytics = function(userId, event, properties)
                table.insert(tagAnalytics, {
                    userId = userId,
                    event = event,
                    properties = cloneTable(properties),
                })
            end,
        })
        local begun = context.theftService:beginTheft(context.thiefUserId, context.targetId)
        expect(begun ~= nil)
        context.positions[context.ownerUserId] = context.positions[context.thiefUserId]
        local tagged, tagError = context.tagService:tag(context.ownerUserId, context.thiefUserId)
        expect(tagged ~= nil and tagError == nil and tagged.success)
        expect(tagged.result == "Cancelled")
        local successfulTagCount = 0
        for _, event in tagAnalytics do
            if event.event == "tag_succeeded" and event.properties.outcome == "Cancelled" then
                successfulTagCount += 1
            end
        end
        expect(
            successfulTagCount == 1,
            "only a successful Tag should be included in playtest analytics"
        )
        expect(context.theftService._attempts[begun.attemptId].state == "RETURNED")
        expect(
            context.humanoids[context.thiefUserId].WalkSpeed == 0,
            "Tag applies a one-second stagger"
        )
        local repeated, repeatedError =
            context.tagService:tag(context.ownerUserId, context.thiefUserId)
        expect(
            repeated == nil and repeatedError == "RateLimited",
            "successful Tag starts defender cooldown"
        )
        context.monotonicNow.value += RaidConfig.TAG_STAGGER_SECONDS
        expect(context.tagService:step(context.monotonicNow.value))
        expect(context.humanoids[context.thiefUserId].WalkSpeed == 16)

        local recoveryEvents = {}
        local carried = makeTheftContext({
            userIds = { 1_221, 1_222, 1_223 },
            emitToUser = function(userId, event, data)
                table.insert(recoveryEvents, {
                    userId = userId,
                    event = event,
                    data = cloneTable(data),
                })
            end,
        })
        local attemptId = beginAndCarryTheft(carried)
        carried.positions[carried.ownerUserId] = carried.positions[carried.thiefUserId]
        local dropped, dropError = carried.tagService:tag(carried.ownerUserId, carried.thiefUserId)
        expect(dropped ~= nil and dropError == nil and dropped.result == "Dropped")
        local attempt = carried.theftService._attempts[attemptId]
        expect(attempt.state == "DROPPED")
        expect(carried.dataService:getSnapshot(carried.thiefUserId).catalysts.emberSeed == 0)
        local recovery, recoveryError =
            carried.theftService:beginRecovery(carried.ownerUserId, attemptId)
        expect(recovery ~= nil and recoveryError == nil and recovery.holdStarted)
        carried.monotonicNow.value += RaidConfig.RECOVERY_HOLD_SECONDS
        expect(carried.theftService:step(carried.monotonicNow.value))
        expect(
            attempt.state == "RETURNED",
            "valid one-second recovery returns the original creature"
        )
        local recoveredFor = {}
        for _, message in recoveryEvents do
            if
                message.event == Protocol.DomainEventNames.TheftStateChanged
                and message.data.state == "RETURNED"
                and message.data.terminalReason == "Recovered"
            then
                recoveredFor[message.userId] = true
            end
        end
        expect(recoveredFor[carried.ownerUserId] and recoveredFor[carried.thiefUserId])
        expect(not recoveredFor[1_223], "recovery details stay limited to both participants")
        expect(
            CreatureService.findInProfile(
                nil,
                carried.dataService:getSnapshot(carried.ownerUserId),
                carried.targetId
            )
        )

        local immune = makeTheftContext({ userIds = { 1_231, 1_232, 1_233 } })
        local firstAttempt = immune.theftService:beginTheft(immune.thiefUserId, immune.targetId)
        immune.positions[immune.ownerUserId] = immune.positions[immune.thiefUserId]
        expect(immune.tagService:tag(immune.ownerUserId, immune.thiefUserId))
        immune.monotonicNow.value += RaidConfig.TAG_STAGGER_SECONDS
        expect(immune.tagService:step(immune.monotonicNow.value))
        local thirdTargetId = "third-owner-target"
        local thirdSpecies = CreatureDefinitions.SpeciesIdsByRarity.Common[3]
        local thirdAdded = immune.dataServices[1_233]:transact(1_233, function(profile)
            profile.creatures[#profile.creatures + 1] =
                { id = thirdTargetId, speciesId = thirdSpecies }
            profile.discoveredSpeciesIds[thirdSpecies] = true
            return { changed = true }
        end)
        expect(thirdAdded)
        expect(immune.creatureService:syncPlayer(1_233))
        immune.positions[immune.thiefUserId] =
            immune.baseService:getCreatureDisplayPosition(1_233, thirdTargetId)
        immune.positions[1_233] = immune.positions[immune.thiefUserId]
        local secondAttempt = immune.theftService:beginTheft(immune.thiefUserId, thirdTargetId)
        expect(secondAttempt ~= nil and secondAttempt.attemptId ~= firstAttempt.attemptId)
        local immuneTag = immune.tagService:tag(1_233, immune.thiefUserId)
        expect(immuneTag ~= nil and not immuneTag.success and immuneTag.result == "Miss")
        expect(immune.theftService._attempts[secondAttempt.attemptId].state == "CHANNELING")
    end
)

test("Tag rejects non-finite server-observed positions", function()
    local context = makeTheftContext()
    local attempt = context.theftService:beginTheft(context.thiefUserId, context.targetId)
    expect(attempt ~= nil)
    context.positions[context.ownerUserId] = { X = math.huge, Y = 0, Z = 0 }
    local result, tagError = context.tagService:tag(context.ownerUserId, context.thiefUserId)
    expect(result ~= nil and tagError == nil and not result.success and result.result == "Miss")
    expect(context.theftService._attempts[attempt.attemptId].state == "CHANNELING")
end)

test("dropped-creature events send the recovery target only to the involved players", function()
    local delivered = {}
    local context = makeTheftContext({
        userIds = { 1_301, 1_302, 1_303 },
        emitToUser = function(userId, event, data)
            table.insert(delivered, { userId = userId, event = event, data = cloneTable(data) })
        end,
    })
    local attemptId = beginAndCarryTheft(context)
    local expected = context.positions[context.thiefUserId]
    context.positions[context.ownerUserId] = expected
    expect(context.tagService:tag(context.ownerUserId, context.thiefUserId))

    local targetByUser = {}
    for _, message in delivered do
        if
            message.event == Protocol.DomainEventNames.TheftStateChanged
            and message.data.state == "DROPPED"
        then
            targetByUser[message.userId] = message.data.dropPosition
        end
    end
    for _, userId in { context.ownerUserId, context.thiefUserId } do
        local dropPosition = targetByUser[userId]
        expect(dropPosition ~= nil, "both involved clients need a recovery marker")
        local expectedX = expected.X or expected.x
        local expectedY = expected.Y or expected.y
        local expectedZ = expected.Z or expected.z
        expect(
            dropPosition.x == expectedX
                and dropPosition.y == expectedY
                and dropPosition.z == expectedZ
        )
    end
    for _, message in delivered do
        expect(message.userId ~= 1_303, "drop location must never be sent to uninvolved players")
    end
    expect(context.theftService._attempts[attemptId].state == "DROPPED")
end)

test("dropped creatures auto-return and disconnect or reset cancels active theft", function()
    local context = makeTheftContext()
    local attemptId = beginAndCarryTheft(context)
    context.positions[context.ownerUserId] = context.positions[context.thiefUserId]
    expect(context.tagService:tag(context.ownerUserId, context.thiefUserId))
    local attempt = context.theftService._attempts[attemptId]
    context.monotonicNow.value += RaidConfig.RECOVERY_WINDOW_SECONDS
    expect(context.theftService:step(context.monotonicNow.value))
    expect(attempt.state == "RETURNED", "an unrecovered drop automatically returns at five seconds")

    local channeling = makeTheftContext()
    local started = channeling.theftService:beginTheft(channeling.thiefUserId, channeling.targetId)
    channeling.theftService:onPlayerRemoving(channeling.ownerUserId)
    expect(channeling.theftService._attempts[started.attemptId].state == "RETURNED")
    local reset = makeTheftContext()
    local resetStarted = reset.theftService:beginTheft(reset.thiefUserId, reset.targetId)
    reset.theftService:onOperationalChanged(reset.thiefUserId, false)
    expect(reset.theftService._attempts[resetStarted.attemptId].state == "RETURNED")

    local carrierReset = makeTheftContext()
    local carriedId = beginAndCarryTheft(carrierReset)
    carrierReset.theftService:onOperationalChanged(carrierReset.thiefUserId, false)
    expect(carrierReset.theftService._attempts[carriedId].state == "RETURNED")

    local ownerReset = makeTheftContext()
    local protectedRunId = beginAndCarryTheft(ownerReset)
    ownerReset.baseService:setOperational(ownerReset.players[ownerReset.ownerUserId], false)
    ownerReset.theftService:onOperationalChanged(ownerReset.ownerUserId, false)
    expect(
        ownerReset.theftService._attempts[protectedRunId].state == "CARRIED",
        "an owner's reset while an item is carried does not grant theft protection"
    )

    local ownerChannelReset = makeTheftContext()
    local ownerChannelAttempt = ownerChannelReset.theftService:beginTheft(
        ownerChannelReset.thiefUserId,
        ownerChannelReset.targetId
    )
    ownerChannelReset.theftService:onOperationalChanged(ownerChannelReset.ownerUserId, false)
    expect(
        ownerChannelReset.theftService._attempts[ownerChannelAttempt.attemptId].state == "RETURNED"
    )

    local ownerCarryLeave = makeTheftContext()
    local ownerCarryAttempt = beginAndCarryTheft(ownerCarryLeave)
    ownerCarryLeave.theftService:onPlayerRemoving(ownerCarryLeave.ownerUserId)
    expect(ownerCarryLeave.theftService._attempts[ownerCarryAttempt].state == "RETURNED")

    local thiefCarryLeave = makeTheftContext()
    local thiefCarryAttempt = beginAndCarryTheft(thiefCarryLeave)
    thiefCarryLeave.theftService:onPlayerRemoving(thiefCarryLeave.thiefUserId)
    expect(thiefCarryLeave.theftService._attempts[thiefCarryAttempt].state == "RETURNED")
end)

test("bank requires a full hold and completes strictly before the Raid boundary", function()
    local tooEarly = makeTheftContext()
    local earlyAttempt = beginAndCarryTheft(tooEarly)
    local earlyBegin = tooEarly.theftService:beginBank(tooEarly.thiefUserId, earlyAttempt)
    expect(earlyBegin ~= nil)
    tooEarly.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS - 0.01
    local incomplete, incompleteError =
        tooEarly.theftService:completeBank(tooEarly.thiefUserId, earlyAttempt, "Prism")
    expect(
        incomplete == nil and incompleteError == "Locked",
        "bank cannot complete before one second"
    )
    expect(
        CreatureService.findInProfile(
            nil,
            tooEarly.dataService:getSnapshot(tooEarly.ownerUserId),
            tooEarly.targetId
        )
    )

    local exact = makeTheftContext()
    local exactAttempt = beginAndCarryTheft(exact)
    expect(exact.theftService:beginBank(exact.thiefUserId, exactAttempt))
    exact.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
    exact.unixNow.value = 1_090
    local exactResult = exact.theftService:completeBank(exact.thiefUserId, exactAttempt, "Moss")
    expect(exactResult == nil, "bank at the exact Raid end boundary must fail")
    expect(
        CreatureService.findInProfile(
            nil,
            exact.dataService:getSnapshot(exact.ownerUserId),
            exact.targetId
        )
    )

    local before = makeTheftContext()
    local beforeAttempt = beginAndCarryTheft(before)
    expect(before.theftService:beginBank(before.thiefUserId, beforeAttempt))
    before.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
    before.unixNow.value = 1_089
    local success = before.theftService:completeBank(before.thiefUserId, beforeAttempt, "Moss")
    expect(success ~= nil, "bank just before the Raid end boundary is allowed")
    expect(before.dataService:getSnapshot(before.thiefUserId).catalysts.mossSpore == 1)
end)

test(
    "journal retries transient commit failures and resolves an ambiguous write exactly once",
    function()
        local ambiguous = makeTheftContext()
        local ambiguousAttempt = beginAndCarryTheft(ambiguous)
        expect(ambiguous.theftService:beginBank(ambiguous.thiefUserId, ambiguousAttempt))
        ambiguous.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
        ambiguous.journalDataStore.failAfterWriteOnCall = 2
        local ambiguousResult, ambiguousError =
            ambiguous.theftService:completeBank(ambiguous.thiefUserId, ambiguousAttempt, "Ember")
        expect(ambiguousResult ~= nil and ambiguousError == nil)
        expect(ambiguous.theftService._attempts[ambiguousAttempt].state == "BANKED")
        expect(
            CreatureService.findInProfile(
                nil,
                ambiguous.dataService:getSnapshot(ambiguous.ownerUserId),
                ambiguous.targetId
            ) == nil
        )
        expect(
            CreatureService.findInProfile(
                nil,
                ambiguous.dataService:getSnapshot(ambiguous.thiefUserId),
                ambiguous.targetId
            )
        )
        expect(ambiguous.dataService:getSnapshot(ambiguous.thiefUserId).catalysts.emberSeed == 1)

        local context = makeTheftContext()
        local attemptId = beginAndCarryTheft(context)
        expect(context.theftService:beginBank(context.thiefUserId, attemptId))
        context.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
        context.journalDataStore.failOnCalls = { [2] = true, [3] = true, [4] = true }
        local bankFailureResult, failure =
            context.theftService:completeBank(context.thiefUserId, attemptId, "Ember")
        expect(bankFailureResult == nil and failure == "ServiceUnavailable")
        expect(context.theftService._attempts[attemptId].state == "CARRIED")
        expect(
            CreatureService.findInProfile(
                nil,
                context.dataService:getSnapshot(context.ownerUserId),
                context.targetId
            )
        )
        expect(
            CreatureService.findInProfile(
                nil,
                context.dataService:getSnapshot(context.thiefUserId),
                context.targetId
            ) == nil
        )
        local journalIndex = context.journalDataStore.records.OddlingsTransfersV1.value
        expect(next(journalIndex.records) == nil, "failed prepared intent is removed before retry")

        expect(context.theftService:beginBank(context.thiefUserId, attemptId))
        context.monotonicNow.value += RaidConfig.BANK_HOLD_SECONDS
        local retried = context.theftService:completeBank(context.thiefUserId, attemptId, "Ember")
        expect(retried ~= nil, "a fresh journal decision may safely retry the bank")
        expect(
            CreatureService.findInProfile(
                nil,
                context.dataService:getSnapshot(context.thiefUserId),
                context.targetId
            )
        )
    end
)

test(
    "ActionService routes Raid requests with phase checks and request replay protection",
    function()
        local context = makeTheftContext()
        local player = context.players[context.thiefUserId]
        player.sessionId = "theft-action-session"
        local actionService = ActionService.new({
            sessionService = {
                getSession = function(_self, candidate)
                    if candidate == player then
                        return { userId = player.UserId, sessionId = player.sessionId }
                    end
                    return nil
                end,
            },
            raidService = context.raidService,
            playerDataService = context.dataService,
            economyService = {},
            capsuleService = {},
            mutationService = {
                getOddsSnapshot = function()
                    return nil
                end,
                getPending = function()
                    return nil
                end,
            },
            theftService = context.theftService,
            tagService = context.tagService,
            baseService = context.baseService,
            requestEvent = {},
            resultEvent = {},
            domainEvent = { FireClient = function() end },
            clock = function()
                return context.monotonicNow.value
            end,
            unixClock = function()
                return context.unixNow.value
            end,
            isOperational = function()
                return true
            end,
        })
        local request = {
            sessionId = player.sessionId,
            requestId = "begin-theft-action",
            action = "BeginTheft",
            payload = { targetCreatureId = context.targetId },
        }
        local first = actionService:handle(player, request)
        expect(first.ok and first.data.attemptId ~= nil)
        local replay = actionService:handle(player, request)
        expect(replay.ok and replay.data.attemptId == first.data.attemptId)
        local altered = cloneTable(request)
        altered.payload.targetCreatureId = "different-creature"
        local conflict = actionService:handle(player, altered)
        expect(not conflict.ok and conflict.code == "Conflict")
        local tagMiss = actionService:handle(player, {
            sessionId = player.sessionId,
            requestId = "tag-action",
            action = "Tag",
            payload = { targetUserId = context.ownerUserId },
        })
        expect(tagMiss.ok and not tagMiss.data.success and tagMiss.data.result == "Miss")

        local peace = makeTheftContext({ phase = "PEACE" })
        local peacePlayer = peace.players[peace.thiefUserId]
        peacePlayer.sessionId = "peace-action-session"
        local phaseService = ActionService.new({
            sessionService = {
                getSession = function()
                    return { userId = peace.thiefUserId, sessionId = peacePlayer.sessionId }
                end,
            },
            raidService = peace.raidService,
            playerDataService = peace.dataService,
            economyService = {},
            capsuleService = {},
            mutationService = { getOddsSnapshot = function() end, getPending = function() end },
            theftService = peace.theftService,
            tagService = peace.tagService,
            baseService = peace.baseService,
            requestEvent = {},
            resultEvent = {},
            domainEvent = { FireClient = function() end },
            isOperational = function()
                return true
            end,
        })
        local wrongPhase = phaseService:handle(peacePlayer, {
            sessionId = peacePlayer.sessionId,
            requestId = "theft-outside-raid",
            action = "BeginTheft",
            payload = { targetCreatureId = peace.targetId },
        })
        expect(not wrongPhase.ok and wrongPhase.code == "WrongPhase")
    end
)

test("Scrap credit is bounded and mutation inputs cannot exceed the profile cap", function()
    local dataStore = makeFakeDataStore()
    local nearCap = PlayerDataService.createDefaultProfile(function()
        return "cap-starter"
    end)
    nearCap.scrap = EconomyConfig.MAX_SCRAP - 2
    dataStore.records.Player_602 = { value = nearCap, userIds = { 602 }, metadata = {} }
    local dataService = PlayerDataService.new({
        profileStore = makeProfileStore(dataStore),
        clock = function()
            return 1_000
        end,
        generateCreatureId = function()
            return "unused-cap-starter"
        end,
        autoSaveEnabled = false,
    })
    assert(dataService:load(602), "valid near-cap profile should load")
    local credited, amount, balance = dataService:creditScrap(602, 10)
    assert(
        credited and amount == 2 and balance == EconomyConfig.MAX_SCRAP,
        "credit must clamp to the configured cap"
    )
    local capped, zeroAmount, cappedBalance = dataService:creditScrap(602, 1)
    assert(
        capped and zeroAmount == 0 and cappedBalance == EconomyConfig.MAX_SCRAP,
        "balance must never exceed cap"
    )
end)

test("online income carries fractional Scrap and stops accruing when offline", function()
    local dataStore = makeFakeDataStore()
    local dataService = PlayerDataService.new({
        profileStore = makeProfileStore(dataStore),
        clock = function()
            return 1_000
        end,
        generateCreatureId = function()
            return "income-starter"
        end,
        autoSaveEnabled = false,
    })
    assert(dataService:load(701), "income test profile should load")
    local published = {}
    local scheduled = {}
    local incomeEvents = {}
    local failIncomeNotification = false
    local economyService = EconomyService.new({
        playerDataService = dataService,
        schedule = function(callback)
            table.insert(scheduled, callback)
        end,
        wait = function() end,
        publish = function(_player, scrap, rate)
            table.insert(published, { scrap = scrap, rate = rate })
        end,
        emitIncomeEvent = function(_player, userId, amount, balance)
            table.insert(incomeEvents, {
                userId = userId,
                amount = amount,
                scrap = balance,
            })
            if failIncomeNotification then
                error("injected presentation delivery failure")
            end
        end,
    })
    local player = { UserId = 701 }
    assert(
        EconomyService.getIncomePerMinute(dataService:getSnapshot(701)) == 40,
        "Mossling base rate must be exactly 40/minute"
    )
    assert(economyService:startPlayer(player), "loaded player should start online income")
    assert(#scheduled == 1, "one online payout loop should be scheduled")
    for _ = 1, 6 do
        assert(economyService:accrue(701, 10), "online payout tick should succeed")
    end
    assert(
        dataService:getSnapshot(701).scrap == 90,
        "six ten-second ticks should credit exactly 40 Scrap"
    )
    assert(
        math.abs(economyService:getFractionalRemainder(701)) < 1e-8,
        "fractional carry should total zero after one minute"
    )
    assert(
        published[#published].rate == 40,
        "visible leaderboard should show the exact income rate"
    )
    local totalAnnouncedIncome = 0
    for _, event in incomeEvents do
        assert(event.userId == 701 and event.amount > 0, "income events are positive and private")
        totalAnnouncedIncome += event.amount
    end
    assert(
        #incomeEvents == 6 and totalAnnouncedIncome == 40,
        "income event totals must match the credited online income"
    )

    failIncomeNotification = true
    local payout, creditedAmount = economyService:accrue(701, 10)
    assert(payout and creditedAmount > 0, "presentation failure must not roll back a payout")
    assert(
        dataService:getSnapshot(701).scrap == 90 + creditedAmount,
        "committed income survives a failed presentation event"
    )

    assert(economyService:stopPlayer(player), "leaving should stop the income loop")
    local offline, _, _, offlineReason = economyService:accrue(701, 600)
    assert(
        not offline and offlineReason == "PlayerOffline",
        "offline time must never accrue income"
    )
    assert(
        dataService:getSnapshot(701).scrap == 90 + creditedAmount,
        "offline interval must not change Scrap"
    )
end)

test("Welcome Capsule is one-time, guaranteed Uncommon, and does not change pity", function()
    local dataService = makeLoadedDataService(801, "welcome-")
    assert(dataService:creditScrap(801, 100), "test player should have enough for Welcome")
    local creatureService = CreatureService.new({ playerDataService = dataService })
    local capsuleService = CapsuleService.new({
        playerDataService = dataService,
        creatureService = creatureService,
        generateCreatureId = function()
            return "welcome-award"
        end,
        randomInteger = function()
            return 1
        end,
    })

    local result, errorCode = capsuleService:purchase(801, "Welcome", "PEACE")
    assert(result ~= nil and errorCode == nil, "first Welcome purchase should succeed")
    assert(result.rarity == "Uncommon", "Welcome must guarantee Uncommon")
    assert(
        result.creature.speciesId == "TeacupCrab",
        "server should select from the Uncommon catalog"
    )
    assert(result.scrapBalance == 30, "Welcome must cost exactly 120 Scrap")
    assert(
        result.pity.belowUncommon == 0 and result.pity.belowRare == 0,
        "Welcome must not alter standard pity"
    )
    assert(
        dataService:getSnapshot(801).welcomeCreatureId == "welcome-award",
        "Welcome creature ID must persist"
    )

    local duplicate, duplicateError = capsuleService:purchase(801, "Welcome", "PEACE")
    assert(
        duplicate == nil and duplicateError == "AlreadyClaimed",
        "Welcome can be claimed only once"
    )
    assert(
        dataService:getSnapshot(801).scrap == 30,
        "duplicate Welcome request must not charge again"
    )
end)

test("creature catalog contains exactly twelve species in their approved rarity groups", function()
    local seen = {}
    local total = 0
    local expectedCounts = { Common = 6, Uncommon = 4, Rare = 2 }
    for rarity, speciesIds in CreatureDefinitions.SpeciesIdsByRarity do
        assert(
            #speciesIds == expectedCounts[rarity],
            rarity .. " species count should match the design"
        )
        for _, speciesId in speciesIds do
            assert(not seen[speciesId], "species IDs must be unique across rarity groups")
            seen[speciesId] = true
            local definition = CreatureDefinitions[speciesId]
            assert(
                definition ~= nil and definition.rarity == rarity,
                "species rarity must match its pool"
            )
            total += 1
        end
    end
    assert(total == 12, "V1 must contain exactly twelve species")
end)

test(
    "Welcome Capsule species selection covers each Uncommon uniformly addressable entry",
    function()
        local randomIndex = 0
        local capsuleService = CapsuleService.new({
            playerDataService = { transact = function() end },
            creatureService = {},
            generateCreatureId = function()
                return "unused"
            end,
            randomInteger = function(minimum, maximum)
                randomIndex += 1
                assert(
                    minimum == 1 and maximum == 4,
                    "Welcome selection must use a four-entry uniform range"
                )
                return randomIndex
            end,
        })
        local expected = CreatureDefinitions.SpeciesIdsByRarity.Uncommon
        for index = 1, #expected do
            assert(
                capsuleService:_chooseSpecies("Uncommon") == expected[index],
                "each Uncommon species must map to one equally sized RNG index"
            )
        end
    end
)

test("capsule purchases reject insufficient Scrap and full capacity before rolling", function()
    local dataService = makeLoadedDataService(806, "capsule-reject-")
    local randomCalls = 0
    local idCalls = 0
    local creatureService = CreatureService.new({ playerDataService = dataService })
    local capsuleService = CapsuleService.new({
        playerDataService = dataService,
        creatureService = creatureService,
        generateCreatureId = function()
            idCalls += 1
            return "should-not-be-created-" .. tostring(idCalls)
        end,
        randomInteger = function()
            randomCalls += 1
            return 1
        end,
    })

    local insufficient, insufficientError = capsuleService:purchase(806, "Welcome", "PEACE")
    assert(
        insufficient == nil and insufficientError == "InsufficientScrap",
        "50 Scrap cannot buy Welcome"
    )
    assert(randomCalls == 0 and idCalls == 0, "rejected purchases must not roll or allocate IDs")
    assert(
        dataService:getSnapshot(806).scrap == EconomyConfig.STARTING_SCRAP,
        "insufficient funds must not change the balance"
    )

    assert(
        dataService:creditScrap(806, 1_000),
        "test player should have funds before capacity rejection"
    )
    assert(
        dataService:transact(806, function(profile)
            return creatureService:addToProfile(
                profile,
                { id = "second-806", speciesId = "ButtonBat" }
            )
        end),
        "test should fill the second starting stand"
    )
    local full, fullError = capsuleService:purchase(806, "Standard", "PEACE")
    assert(full == nil and fullError == "CapacityFull", "a full base must reject Standard capsules")
    local welcomeFull, welcomeFullError = capsuleService:purchase(806, "Welcome", "PEACE")
    assert(
        welcomeFull == nil and welcomeFullError == "CapacityFull",
        "a full base must reject the Welcome Capsule"
    )
    assert(
        randomCalls == 0 and idCalls == 0,
        "full-capacity rejection must happen before RNG and ID work"
    )
    assert(
        dataService:getSnapshot(806).scrap == 1_050 and #dataService:getSnapshot(806).creatures == 2,
        "capacity rejection must not charge Scrap or grant a creature"
    )
end)

test("theft protection applies only to the starter and exact Welcome creature", function()
    local creatureService = CreatureService.new()
    local profile = {
        starterCreatureId = "starter-id",
        welcomeCreatureId = "welcome-id",
        hasCompletedFirstRaid = false,
    }
    assert(
        creatureService:isProtectedFromTheft(profile, "starter-id"),
        "the starting Mossling remains permanently protected"
    )
    assert(
        creatureService:isProtectedFromTheft(profile, "welcome-id"),
        "the specific Welcome creature is protected before first-Raid completion"
    )
    assert(
        not creatureService:isProtectedFromTheft(profile, "later-creature-id"),
        "other creatures receive no Welcome protection"
    )
    profile.hasCompletedFirstRaid = true
    assert(
        not creatureService:isProtectedFromTheft(profile, "welcome-id"),
        "Welcome protection expires after first-Raid completion"
    )
    assert(
        creatureService:isProtectedFromTheft(profile, "starter-id"),
        "first-Raid completion never removes starter protection"
    )
end)

test("capsule, slot, and sale mutations keep the base stand projection synchronized", function()
    local userId = 807
    local player = { UserId = userId }
    local dataService = makeLoadedDataService(userId, "stand-sync-")
    assert(dataService:creditScrap(userId, 1_000), "test player should afford the M3 actions")
    local baseService = BaseService.new()
    assert(baseService:assign(player) ~= nil, "test player should receive a base")
    local published = {}
    local creatureService = CreatureService.new({
        playerDataService = dataService,
        baseService = baseService,
    })
    local capsuleService = CapsuleService.new({
        playerDataService = dataService,
        creatureService = creatureService,
        generateCreatureId = function()
            return "welcome-stand-807"
        end,
        randomInteger = function()
            return 1
        end,
    })
    local economyService = EconomyService.new({
        playerDataService = dataService,
        creatureService = creatureService,
        schedule = function() end,
        wait = function() end,
        publish = function(_candidate, scrap, incomePerMinute)
            table.insert(published, { scrap = scrap, incomePerMinute = incomePerMinute })
        end,
    })
    assert(economyService:startPlayer(player), "loaded player should publish initial economy state")

    assert(
        capsuleService:purchase(userId, "Welcome", "PEACE") ~= nil,
        "Welcome purchase should succeed"
    )
    local afterCapsule = baseService:getForPlayer(player)
    assert(
        afterCapsule.slotCapacity == 2
            and #afterCapsule.creatures == 2
            and afterCapsule.creatures[2].id == "welcome-stand-807",
        "capsule purchase should map the new creature into its stand"
    )

    assert(economyService:purchaseSlot(userId, 3, "PEACE") ~= nil, "Slot 3 purchase should succeed")
    assert(
        baseService:getForPlayer(player).slotCapacity == 3,
        "slot purchase should unlock the matching stand projection"
    )
    assert(
        published[#published].scrap == 580,
        "slot purchase should immediately publish its balance"
    )
    assert(
        economyService:sellCreature(userId, "welcome-stand-807", "PEACE") ~= nil,
        "non-starter Welcome creature can be sold under the fixed sale rule"
    )
    local afterSale = baseService:getForPlayer(player)
    assert(
        afterSale.slotCapacity == 3 and #afterSale.creatures == 1,
        "sale should clear the occupied stand without reducing permanent capacity"
    )
    assert(published[#published].scrap == 640, "sale should immediately publish its balance")
    economyService:stopPlayer(player)
end)

test(
    "standard capsule odds respect exact bucket boundaries, duplicates, and pity floors",
    function()
        local dataService = makeLoadedDataService(802, "standard-")
        assert(dataService:creditScrap(802, 1_000), "test player should have enough capsule funds")
        assert(
            dataService:transact(802, function(profile)
                profile.slotCapacity = 4
                return true
            end),
            "test profile should have four slots"
        )
        local values = { 700, 1, 950, 1, 951, 2 }
        local randomIndex = 0
        local nextCreatureId = 0
        local creatureService = CreatureService.new({ playerDataService = dataService })
        local capsuleService = CapsuleService.new({
            playerDataService = dataService,
            creatureService = creatureService,
            generateCreatureId = function()
                nextCreatureId += 1
                return "standard-drop-" .. tostring(nextCreatureId)
            end,
            randomInteger = function(minimum, maximum)
                randomIndex += 1
                local value = values[randomIndex]
                assert(
                    value >= minimum and value <= maximum,
                    "test random value should fit selected range"
                )
                return value
            end,
        })

        local boundaryValues = { 700, 701, 950, 951 }
        local boundaryIndex = 0
        local boundaryService = CapsuleService.new({
            playerDataService = { transact = function() end },
            creatureService = {},
            generateCreatureId = function()
                return "unused-boundary"
            end,
            randomInteger = function(minimum, maximum)
                boundaryIndex += 1
                local value = boundaryValues[boundaryIndex]
                assert(
                    minimum == 1 and maximum == 1_000,
                    "normal tier roll must use 1 through 1,000"
                )
                return value
            end,
        })
        local boundaryProfile = { standardCapsulePity = { belowUncommon = 0, belowRare = 0 } }
        for index, expectedRarity in { "Common", "Uncommon", "Uncommon", "Rare" } do
            assert(
                boundaryService:_rollTier(boundaryProfile) == expectedRarity,
                string.format(
                    "standard odds boundary %d should select %s",
                    boundaryValues[index],
                    expectedRarity
                )
            )
        end

        local common, commonError = capsuleService:purchase(802, "Standard", "PEACE")
        assert(common ~= nil, "Common purchase failed: " .. tostring(commonError))
        local uncommon, uncommonError = capsuleService:purchase(802, "Standard", "PEACE")
        assert(uncommon ~= nil, "Uncommon purchase failed: " .. tostring(uncommonError))
        local rare, rareError = capsuleService:purchase(802, "Standard", "PEACE")
        assert(rare ~= nil, "Rare purchase failed: " .. tostring(rareError))
        assert(common.rarity == "Common", "roll 700 belongs to the 70% Common bucket")
        assert(
            common.creature.speciesId == "Mossling",
            "duplicates are allowed, including a later Mossling"
        )
        assert(uncommon.rarity == "Uncommon", "roll 950 belongs to the Uncommon bucket")
        assert(rare.rarity == "Rare", "roll 951 belongs to the Rare bucket")
        assert(
            rare.pity.belowUncommon == 0 and rare.pity.belowRare == 0,
            "Rare should reset both counters"
        )
        assert(
            dataService:getSnapshot(802).creatures[1].id ~= common.creature.id,
            "duplicate species use a distinct creature ID"
        )
    end
)

test("standard capsule pity forces Uncommon and then Rare at their floors", function()
    local dataService = makeLoadedDataService(803, "pity-")
    assert(dataService:creditScrap(803, 500), "test player should have enough capsule funds")
    assert(
        dataService:transact(803, function(profile)
            profile.slotCapacity = 4
            profile.standardCapsulePity.belowUncommon = 3
            profile.standardCapsulePity.belowRare = 3
            return true
        end),
        "test should seed the Uncommon pity floor"
    )
    local values = { 5, 1, 2 }
    local randomIndex = 0
    local nextCreatureId = 0
    local capsuleService = CapsuleService.new({
        playerDataService = dataService,
        creatureService = CreatureService.new({ playerDataService = dataService }),
        generateCreatureId = function()
            nextCreatureId += 1
            return "pity-drop-" .. tostring(nextCreatureId)
        end,
        randomInteger = function(minimum, maximum)
            randomIndex += 1
            local value = values[randomIndex]
            assert(
                value >= minimum and value <= maximum,
                "pity RNG value should fit requested range"
            )
            return value
        end,
    })

    local guaranteedUncommon, uncommonError = capsuleService:purchase(803, "Standard", "PEACE")
    assert(guaranteedUncommon ~= nil, "Uncommon pity purchase failed: " .. tostring(uncommonError))
    assert(
        guaranteedUncommon.rarity == "Uncommon",
        "three Common results must exclude the Common tier"
    )
    assert(
        guaranteedUncommon.pity.belowUncommon == 0,
        "Uncommon-or-better resets the first counter"
    )

    assert(
        dataService:transact(803, function(profile)
            profile.standardCapsulePity.belowUncommon = 2
            profile.standardCapsulePity.belowRare = 8
            return true
        end),
        "test should seed the Rare pity floor"
    )
    local guaranteedRare, rareError = capsuleService:purchase(803, "Standard", "PEACE")
    assert(guaranteedRare ~= nil, "Rare pity purchase failed: " .. tostring(rareError))
    assert(guaranteedRare.rarity == "Rare", "eight below-Rare results must force Rare")
    assert(
        guaranteedRare.pity.belowUncommon == 0 and guaranteedRare.pity.belowRare == 0,
        "Rare clears both counters"
    )
end)

test(
    "slot purchases and creature sales enforce costs, prerequisites, and starter protection",
    function()
        local dataService = makeLoadedDataService(804, "commerce-")
        assert(dataService:creditScrap(804, 1_500), "test player should have upgrade funds")
        local creatureService = CreatureService.new({ playerDataService = dataService })
        local added, addResult, addError = dataService:transact(804, function(profile)
            return creatureService:addToProfile(
                profile,
                { id = "owned-2", speciesId = "TiffinToad" }
            )
        end)
        assert(added and addResult ~= nil and addError == nil, "second creature should be granted")
        local economyService = EconomyService.new({
            playerDataService = dataService,
            creatureService = creatureService,
            schedule = function() end,
            wait = function() end,
        })

        local slot3 = economyService:purchaseSlot(804, 3, "PEACE")
        assert(slot3.slotCapacity == 3 and slot3.scrapBalance == 1_200, "Slot 3 costs exactly 350")
        local earlySlot4, earlyError = economyService:purchaseSlot(804, 4, "PEACE")
        assert(
            earlySlot4 == nil and earlyError == "Unavailable",
            "Slot 4 requires three creatures and completed Raid"
        )

        local third, thirdResult, thirdError = dataService:transact(804, function(profile)
            profile.hasCompletedFirstRaid = true
            return creatureService:addToProfile(
                profile,
                { id = "owned-3", speciesId = "PuddlePup" }
            )
        end)
        assert(
            third and thirdResult ~= nil and thirdError == nil,
            "third creature should be granted"
        )
        assert(dataService:creditScrap(804, 1_200), "test player should afford Slot 4")
        local slot4 = economyService:purchaseSlot(804, 4, "COOLDOWN")
        assert(
            slot4.slotCapacity == 4 and slot4.scrapBalance == 1_200,
            "Slot 4 costs exactly 1,200"
        )
        local fourth, fourthResult, fourthError = dataService:transact(804, function(profile)
            return creatureService:addToProfile(
                profile,
                { id = "owned-4", speciesId = "PebbleImp" }
            )
        end)
        assert(
            fourth and fourthResult ~= nil and fourthError == nil,
            "the fourth purchased slot should accept one more creature"
        )
        local fifth, fifthResult, fifthError = dataService:transact(804, function(profile)
            return creatureService:addToProfile(
                profile,
                { id = "owned-5", speciesId = "PebbleImp" }
            )
        end)
        assert(
            not fifth and fifthResult == nil and fifthError == "CapacityFull",
            "a four-slot profile cannot add a fifth creature"
        )

        local snapshot = dataService:getSnapshot(804)
        local starterId = snapshot.starterCreatureId
        local protected, protectError = economyService:sellCreature(804, starterId, "PEACE")
        assert(protected == nil and protectError == "Locked", "starter cannot be sold")

        assert(
            creatureService:reserve(804, "owned-2", "attempt-1"),
            "owned creature can be reserved"
        )
        local reserved, reservedError = economyService:sellCreature(804, "owned-2", "PEACE")
        assert(reserved == nil and reservedError == "Locked", "reserved creature cannot be sold")
        assert(
            creatureService:releaseReservation(804, "owned-2", "attempt-1"),
            "reservation should release"
        )
        local sale, saleError = economyService:sellCreature(804, "owned-2", "PEACE")
        assert(sale ~= nil and saleError == nil, "ordinary owned creature can be sold")
        assert(sale.refund == 60 and sale.scrapBalance == 1_260, "sale refunds exactly 60 Scrap")
        assert(
            dataService:getSnapshot(804).slotCapacity == 4,
            "selling does not remove purchased capacity"
        )
    end
)

test("mutation catalog contains the approved 24 forms, themes, tiers, and multipliers", function()
    local expected = {
        Ember = { Common = 4, Uncommon = 2, Rare = 1, Mythic = 1 },
        Prism = { Common = 4, Uncommon = 2, Rare = 1, Mythic = 1 },
        Moss = { Common = 4, Uncommon = 2, Rare = 1, Mythic = 1 },
    }
    local total = 0
    for themeId, tierCounts in expected do
        local themeForms = MutationDefinitions.FormIdsByThemeAndTier[themeId]
        expect(themeForms ~= nil, "each approved theme should have a form catalog")
        for tier, count in tierCounts do
            expect(#themeForms[tier] == count, "theme tier count should match the design")
            for _, formId in themeForms[tier] do
                local form = MutationDefinitions[formId]
                expect(form.themeId == themeId, "catalog form must match its theme")
                expect(form.tier == tier, "catalog form must match its tier")
                expect(
                    form.multiplier
                        == ({ Common = 1.25, Uncommon = 1.5, Rare = 2, Mythic = 4 })[tier],
                    "catalog form multiplier should match its tier"
                )
                total += 1
            end
        end
    end
    expect(total == 24, "the V1 catalog should contain exactly 24 forms")
    expect(MutationDefinitions.VerdantCrown.displayName == "Verdant Crown")
end)

test("profile validation requires every equipped mutation to be in the Codex", function()
    local profile = PlayerDataService.createDefaultProfile(function()
        return "profile-mutation-starter"
    end)
    profile.creatures[1].mutationFormId = "Cinder"
    local invalid, invalidError = PlayerDataService.validateProfile(profile)
    expect(not invalid and invalidError == "EquippedMutationNotDiscovered")

    profile.discoveredMutationFormIds.Cinder = true
    local valid, validError = PlayerDataService.validateProfile(profile)
    expect(valid and validError == nil)
end)

test("catalyst purchases bind theme, cost exactly 60 Scrap, and reject invalid states", function()
    local context = makeMutationContext(901, nil)
    local userId = context.player.UserId
    expect(context.dataService:creditScrap(userId, 60), "test player should afford a catalyst")

    local purchase, purchaseError =
        context.economyService:purchaseCatalyst(userId, "Prism", "PEACE")
    expect(purchase ~= nil and purchaseError == nil, "Prism catalyst should be purchasable")
    expect(purchase.themeId == "Prism" and purchase.count == 1)
    local profile = context.dataService:getSnapshot(userId)
    expect(profile.catalysts.prismDust == 1, "Prism must grant only its bound catalyst")
    expect(profile.catalysts.emberSeed == 0 and profile.catalysts.mossSpore == 0)
    expect(profile.scrap == 50, "catalyst purchase should cost exactly 60")

    local unavailable, fundsError =
        context.economyService:purchaseCatalyst(userId, "Ember", "PEACE")
    expect(unavailable == nil and fundsError == "InsufficientScrap")
    local invalid, invalidError =
        context.economyService:purchaseCatalyst(userId, "Starlight", "PEACE")
    expect(invalid == nil and invalidError == "InvalidRequest")
    local wrongPhase, phaseError = context.economyService:purchaseCatalyst(userId, "Ember", "RAID")
    expect(wrongPhase == nil and phaseError == "WrongPhase")
    expect(context.dataService:getSnapshot(userId).scrap == 50)
end)

test("tutorial mutation is one-time, free, theme-bound, and selects every Common form", function()
    local themes = { "Ember", "Prism", "Moss" }
    local userId = 910
    for _, themeId in themes do
        for index = 1, 4 do
            local chosenIndex = index
            local context = makeMutationContext(userId, function(_minimum, maximum)
                return if maximum == 4 then chosenIndex else 1
            end)
            local result = completeMutationTutorial(context, themeId)
            local expectedForm = MutationDefinitions.FormIdsByThemeAndTier[themeId].Common[index]
            expect(result.formId == expectedForm, "tutorial should select from the chosen branch")
            local form = MutationDefinitions[result.formId]
            expect(form.themeId == themeId and form.tier == "Common")
            local profile = context.dataService:getSnapshot(userId)
            expect(profile.tutorialCompleted, "tutorial completion should persist")
            expect(profile.creatures[1].mutationFormId == result.formId)
            expect(
                profile.discoveredMutationFormIds[result.formId],
                "equipped tutorial form enters Codex"
            )
            expect(profile.scrap == 50, "tutorial must not charge Scrap")
            expect(profile.catalysts.emberSeed == 0)
            expect(profile.catalysts.prismDust == 0)
            expect(profile.catalysts.mossSpore == 0)
            expect(profile.mutationRareMissCount == 0, "tutorial does not affect mutation pity")
            local repeated, repeatedError = context.mutationService:completeTutorialMutation(
                userId,
                profile.starterCreatureId,
                themeId,
                "PEACE"
            )
            expect(repeated == nil and repeatedError == "AlreadyClaimed")
        end
        userId += 1
    end

    local wrongTarget = makeMutationContext(920, function()
        return 1
    end)
    local rejected, targetError = wrongTarget.mutationService:completeTutorialMutation(
        920,
        "not-the-starter",
        "Ember",
        "PEACE"
    )
    expect(rejected == nil and targetError == "Locked", "tutorial must target the exact starter ID")
end)

test(
    "normal mutation odds use exact tier boundaries and keep Mythic at one per thousand",
    function()
        local cases = {
            { 600, "Common" },
            { 601, "Uncommon" },
            { 900, "Uncommon" },
            { 901, "Rare" },
            { 999, "Rare" },
            { 1_000, "Mythic" },
        }
        for index, case in cases do
            local calls = 0
            local context = makeMutationContext(930 + index, function(minimum, _maximum)
                calls += 1
                if calls == 1 then
                    return 1
                elseif calls == 2 then
                    return case[1]
                end
                return minimum
            end)
            local userId = context.player.UserId
            expect(context.dataService:creditScrap(userId, 1_000))
            completeMutationTutorial(context, "Ember")
            expect(context.dataService:transact(userId, function(profile)
                profile.catalysts.emberSeed = 1
                return true, nil
            end))
            local profile = context.dataService:getSnapshot(userId)
            local result, errorCode = context.mutationService:startMutation(
                userId,
                profile.starterCreatureId,
                "Ember",
                "PEACE"
            )
            expect(result ~= nil and errorCode == nil)
            expect(result.tier == case[2], "normal roll should match exact thousand-roll bucket")
            expect(result.oddsSnapshot.unit == "per-thousand")
            expect(result.oddsSnapshot.normal.mythic == 1)
            expect(not result.oddsSnapshot.rareGuaranteeActive)
            expect(result.oddsSnapshot.nextRoll.mythic == 1)
            expect(MutationDefinitions[result.revealedFormId].themeId == "Ember")
        end
    end
)

test("eight sub-Rare mutation misses activate 999-to-1 pity without Mythic pity", function()
    local normalRollCount = 0
    local forcedRoll = nil
    local context = makeMutationContext(940, function(minimum, maximum)
        if maximum == 1_000 then
            normalRollCount += 1
            if normalRollCount <= 8 then
                return 600
            end
            return forcedRoll or 2
        end
        return minimum
    end)
    local userId = context.player.UserId
    expect(context.dataService:creditScrap(userId, 5_000))
    completeMutationTutorial(context, "Ember")
    expect(context.dataService:transact(userId, function(profile)
        profile.catalysts.emberSeed = 9
        return true, nil
    end))

    for _ = 1, 8 do
        local profile = context.dataService:getSnapshot(userId)
        local result = context.mutationService:startMutation(
            userId,
            profile.starterCreatureId,
            "Ember",
            "PEACE"
        )
        expect(result ~= nil and result.tier == "Common")
        expect(
            context.mutationService:resolveMutation(
                userId,
                result.transactionId,
                "Decline",
                "PEACE"
            )
        )
    end
    local profile = context.dataService:getSnapshot(userId)
    expect(profile.mutationRareMissCount == 8)
    expect(profile.mythicMissCount == nil, "profile has no Mythic miss counter")

    forcedRoll = 2
    local guaranteedRare =
        context.mutationService:startMutation(userId, profile.starterCreatureId, "Ember", "PEACE")
    expect(guaranteedRare.tier == "Rare")
    expect(guaranteedRare.oddsSnapshot.rareGuaranteeActive)
    expect(guaranteedRare.oddsSnapshot.nextRoll.rare == 999)
    expect(guaranteedRare.oddsSnapshot.nextRoll.mythic == 1)
    expect(context.dataService:getSnapshot(userId).mutationRareMissCount == 0)

    local mythicContext = makeMutationContext(941, function(_minimum, maximum)
        return if maximum == 1_000 then 1 else 1
    end)
    expect(mythicContext.dataService:creditScrap(941, 1_000))
    completeMutationTutorial(mythicContext, "Prism")
    expect(mythicContext.dataService:transact(941, function(draft)
        draft.catalysts.prismDust = 1
        draft.mutationRareMissCount = 8
        return true, nil
    end))
    local mythicProfile = mythicContext.dataService:getSnapshot(941)
    local guaranteedMythic = mythicContext.mutationService:startMutation(
        941,
        mythicProfile.starterCreatureId,
        "Prism",
        "PEACE"
    )
    expect(guaranteedMythic.tier == "Mythic", "pity-active roll one still has its 0.1% Mythic")
    expect(guaranteedMythic.oddsSnapshot.nextRoll.mythic == 1)
    expect(mythicContext.dataService:getSnapshot(941).mutationRareMissCount == 0)

    local longRun = makeMutationContext(942, function(minimum, maximum)
        return if maximum == 1_000 then 600 else minimum
    end)
    expect(longRun.dataService:creditScrap(942, 5_000))
    completeMutationTutorial(longRun, "Moss")
    expect(longRun.dataService:transact(942, function(draft)
        draft.catalysts.mossSpore = 25
        return true, nil
    end))
    for _ = 1, 25 do
        local rollProfile = longRun.dataService:getSnapshot(942)
        local result = longRun.mutationService:startMutation(
            942,
            rollProfile.starterCreatureId,
            "Moss",
            "PEACE"
        )
        expect(result.tier ~= "Mythic", "this deterministic 25-roll sequence has no Mythic")
        expect(
            longRun.mutationService:resolveMutation(942, result.transactionId, "Decline", "PEACE")
        )
    end
    local finalProfile = longRun.dataService:getSnapshot(942)
    local finalOdds = longRun.mutationService:getOddsSnapshot(finalProfile.mutationRareMissCount)
    expect(finalProfile.mythicMissCount == nil, "Mythic misses do not persist a pity counter")
    expect(finalOdds.normal.mythic == 1 and finalOdds.nextRoll.mythic == 1)
end)

test(
    "mutation choices preserve, equip, or decline forms without refunds or premature Codex entries",
    function()
        local current = nil
        local queued = {
            { tier = 601, form = 1 },
            { tier = 601, form = 2 },
            { tier = 601, form = 1 },
        }
        local context = makeMutationContext(950, function(minimum, maximum)
            if maximum == 1_000 then
                current = (current or 0) + 1
                return queued[current].tier
            elseif maximum == 2 then
                return queued[current].form
            end
            return minimum
        end)
        local userId = context.player.UserId
        expect(context.dataService:creditScrap(userId, 1_000))
        completeMutationTutorial(context, "Ember")
        expect(context.dataService:transact(userId, function(profile)
            profile.catalysts.emberSeed = 3
            return true, nil
        end))
        local profile = context.dataService:getSnapshot(userId)
        local starterId = profile.starterCreatureId
        local tutorialForm = profile.creatures[1].mutationFormId

        local keepOffer = context.mutationService:startMutation(userId, starterId, "Ember", "PEACE")
        expect(keepOffer.revealedFormId == "Flarefin")
        expect(
            context.mutationService:resolveMutation(
                userId,
                keepOffer.transactionId,
                "KeepCurrent",
                "PEACE"
            )
        )
        profile = context.dataService:getSnapshot(userId)
        expect(profile.creatures[1].mutationFormId == tutorialForm)
        expect(not profile.discoveredMutationFormIds.Flarefin, "kept result must not enter Codex")

        local replaceOffer =
            context.mutationService:startMutation(userId, starterId, "Ember", "PEACE")
        expect(replaceOffer.revealedFormId == "Hearthhorn")
        local replaced, replaceError = context.mutationService:resolveMutation(
            userId,
            replaceOffer.transactionId,
            "Replace",
            "PEACE"
        )
        expect(replaced ~= nil and replaced.outcome == "Replaced" and replaced.codexFormAdded)
        profile = context.dataService:getSnapshot(userId)
        expect(profile.creatures[1].mutationFormId == "Hearthhorn")
        expect(profile.discoveredMutationFormIds.Hearthhorn)

        local declineOffer =
            context.mutationService:startMutation(userId, starterId, "Ember", "PEACE")
        expect(declineOffer.revealedFormId == "Flarefin")
        local declined = context.mutationService:resolveMutation(
            userId,
            declineOffer.transactionId,
            "Decline",
            "PEACE"
        )
        expect(declined.outcome == "Declined")
        profile = context.dataService:getSnapshot(userId)
        expect(profile.creatures[1].mutationFormId == "Hearthhorn")
        expect(not profile.discoveredMutationFormIds.Flarefin)
        expect(profile.scrap == 750, "keep, replace, and decline each retain the 100 Scrap cost")
        expect(profile.catalysts.emberSeed == 0)
        expect(profile.mutationRareMissCount == 3)
        expect(replaceError == nil)
    end
)

test("duplicate mutation results keep the active form while preserving cost and pity", function()
    local context = makeMutationContext(951, function(minimum, maximum)
        if maximum == 1_000 then
            return 1
        end
        return minimum
    end)
    local userId = context.player.UserId
    expect(context.dataService:creditScrap(userId, 500))
    local tutorial = completeMutationTutorial(context, "Ember")
    expect(tutorial.formId == "Cinder")
    expect(context.dataService:transact(userId, function(profile)
        profile.catalysts.emberSeed = 1
        return true, nil
    end))
    local profile = context.dataService:getSnapshot(userId)
    local offer =
        context.mutationService:startMutation(userId, profile.starterCreatureId, "Ember", "PEACE")
    expect(offer.revealedFormId == "Cinder")
    local result =
        context.mutationService:resolveMutation(userId, offer.transactionId, "Replace", "PEACE")
    expect(result.outcome == "Duplicate")
    profile = context.dataService:getSnapshot(userId)
    expect(profile.creatures[1].mutationFormId == "Cinder")
    expect(profile.scrap == 450 and profile.catalysts.emberSeed == 0)
    expect(profile.mutationRareMissCount == 1)
    expect(profile.discoveredMutationFormIds.Cinder)
end)

test("pending mutation locks the creature and phase or disconnect clears only the offer", function()
    local discardedEvents = {}
    local context = makeMutationContext(952, function(minimum, maximum)
        return if maximum == 1_000 then 1 else minimum
    end, function(_userId, event, data)
        table.insert(discardedEvents, { event = event, data = data })
    end)
    local userId = context.player.UserId
    expect(context.dataService:creditScrap(userId, 500))
    completeMutationTutorial(context, "Ember")
    expect(context.dataService:transact(userId, function(profile)
        table.insert(profile.creatures, { id = "mutation-extra", speciesId = "PebbleImp" })
        profile.discoveredSpeciesIds.PebbleImp = true
        return true, nil
    end))
    expect(context.creatureService:syncPlayer(userId))
    expect(context.dataService:transact(userId, function(profile)
        profile.catalysts.emberSeed = 2
        return true, nil
    end))
    local creatureId = "mutation-extra"
    expect(context.baseService:setCollection(userId, {}, 2))
    local offStand, offStandError =
        context.mutationService:startMutation(userId, creatureId, "Ember", "PEACE")
    expect(
        offStand == nil and offStandError == "Locked",
        "creature must still be projected to a stand"
    )
    expect(context.creatureService:syncPlayer(userId))
    expect(context.creatureService:reserve(userId, creatureId, "raid-attempt"))
    local reserved, reservedError =
        context.mutationService:startMutation(userId, creatureId, "Ember", "PEACE")
    expect(reserved == nil and reservedError == "Locked", "reserved creature cannot mutate")
    expect(context.creatureService:releaseReservation(userId, creatureId, "raid-attempt"))
    local offer = context.mutationService:startMutation(userId, creatureId, "Ember", "PEACE")
    expect(offer ~= nil)
    local balanceAfterRoll = context.dataService:getSnapshot(userId).scrap
    expect(context.creatureService:isRestricted(userId, creatureId))
    expect(not context.creatureService:reserve(userId, creatureId, "raid-attempt"))
    local sale, saleError = context.economyService:sellCreature(userId, creatureId, "PEACE")
    expect(sale == nil and saleError == "Locked")
    local duplicateStart, duplicateError =
        context.mutationService:startMutation(userId, creatureId, "Ember", "PEACE")
    expect(duplicateStart == nil and duplicateError == "Conflict")
    expect(context.dataService:getSnapshot(userId).scrap == balanceAfterRoll)

    expect(context.mutationService:onPhaseChanged({ phase = "RAID" }) == 1)
    expect(context.mutationService:getPending(userId) == nil)
    expect(not context.creatureService:isRestricted(userId, creatureId))
    expect(discardedEvents[1].event == "MutationDiscarded")
    expect(discardedEvents[1].data.transactionId == offer.transactionId)
    local expired, expiredError =
        context.mutationService:resolveMutation(userId, offer.transactionId, "Replace", "PEACE")
    expect(expired == nil and expiredError == "Expired")
    expect(context.dataService:getSnapshot(userId).scrap == balanceAfterRoll)

    local secondOffer = context.mutationService:startMutation(userId, creatureId, "Ember", "PEACE")
    expect(secondOffer ~= nil)
    context.mutationService:clearUser(userId)
    expect(context.mutationService:getPending(userId) == nil)
    expect(not context.creatureService:isRestricted(userId, creatureId))
end)

test("mutation action protocol accepts only the approved payloads", function()
    local function request(action, payload)
        return {
            sessionId = "session-mutation-123",
            requestId = "mutation-action-1",
            action = action,
            payload = payload,
        }
    end
    expect(Protocol.isValidActionRequest(request("PurchaseCatalyst", { themeId = "Moss" })))
    expect(Protocol.isValidActionRequest(request("CompleteTutorialMutation", {
        creatureId = "creature-id",
        themeId = "Ember",
    })))
    expect(Protocol.isValidActionRequest(request("StartMutation", {
        creatureId = "creature-id",
        themeId = "Prism",
    })))
    expect(Protocol.isValidActionRequest(request("ResolveMutation", {
        transactionId = "transaction-id",
        choice = "Replace",
    })))
    expect(not Protocol.isValidActionRequest(request("PurchaseCatalyst", {
        themeId = "Moss",
        catalystId = "emberSeed",
    })))
    expect(not Protocol.isValidActionRequest(request("StartMutation", {
        creatureId = "creature-id",
        themeId = "Prism",
        rarity = "Mythic",
    })))
    expect(not Protocol.isValidActionRequest(request("ResolveMutation", {
        transactionId = "transaction-id",
        choice = "GrantMythic",
    })))
end)

test("ActionService routes mutation requests through station and transaction guards", function()
    local userId = 953
    local calls = 0
    local context = makeMutationContext(userId, function(minimum, maximum)
        calls += 1
        if calls == 1 then
            return 1
        elseif maximum == 1_000 then
            return 601
        end
        return minimum
    end)
    expect(context.dataService:creditScrap(userId, 1_000))
    local profile = context.dataService:getSnapshot(userId)
    local capsuleService = CapsuleService.new({
        playerDataService = context.dataService,
        creatureService = context.creatureService,
        generateCreatureId = function()
            return "unused-capsule"
        end,
        randomInteger = function()
            return 1
        end,
    })
    local player = {
        UserId = userId,
        sessionId = "mutation-session-953",
        nearCommons = true,
        nearMutation = true,
    }
    local now = 0
    local phase = "PEACE"
    local events = {}
    local actionService = ActionService.new({
        sessionService = {
            getSession = function(_self, candidate)
                if candidate == player then
                    return { userId = userId, sessionId = player.sessionId }
                end
                return nil
            end,
        },
        raidService = {
            getSnapshot = function()
                return { phase = phase }
            end,
        },
        playerDataService = context.dataService,
        economyService = context.economyService,
        capsuleService = capsuleService,
        mutationService = context.mutationService,
        theftService = {},
        baseService = {
            isOperational = function()
                return true
            end,
        },
        requestEvent = {},
        resultEvent = {},
        domainEvent = {
            FireClient = function(_self, _player, event)
                table.insert(events, event)
            end,
        },
        clock = function()
            return now
        end,
        canInteract = function(_candidate, station)
            return if station == "mutation" then player.nearMutation else player.nearCommons
        end,
    })
    local initialSnapshot = actionService:handle(player, {
        sessionId = player.sessionId,
        requestId = "mutation-initial-snapshot",
        action = "GetSnapshot",
        payload = {},
    })
    expect(initialSnapshot.ok)
    expect(initialSnapshot.data.mutationOdds.normal.mythic == 1)
    expect(initialSnapshot.data.mutationOdds.nextRoll.mythic == 1)
    now = 2
    local tutorialRequest = {
        sessionId = player.sessionId,
        requestId = "tutorial-mutation",
        action = "CompleteTutorialMutation",
        payload = { creatureId = profile.starterCreatureId, themeId = "Ember" },
    }
    local tutorial = actionService:handle(player, tutorialRequest)
    expect(tutorial.ok and tutorial.data.tutorialCompleted)
    expect(events[1].event == "MutationApplied")
    expect(events[2].event == "TutorialCompleted")

    local buy = actionService:handle(player, {
        sessionId = player.sessionId,
        requestId = "buy-catalyst",
        action = "PurchaseCatalyst",
        payload = { themeId = "Ember" },
    })
    expect(buy.ok and buy.data.count == 1 and buy.data.scrapBalance == 990)
    expect(events[#events - 1].event == "CatalystChanged")
    expect(events[#events].event == "ScrapChanged")

    local startRequest = {
        sessionId = player.sessionId,
        requestId = "start-mutation",
        action = "StartMutation",
        payload = { creatureId = profile.starterCreatureId, themeId = "Ember" },
    }
    local start = actionService:handle(player, startRequest)
    expect(start.ok and start.data.transactionId ~= nil)
    local afterStart = context.dataService:getSnapshot(userId)
    local replay = actionService:handle(player, startRequest)
    expect(replay.ok and replay.data.transactionId == start.data.transactionId)
    expect(context.dataService:getSnapshot(userId).scrap == afterStart.scrap)
    expect(events[#events - 2].event == "MutationRevealed")
    local pendingSnapshot = actionService:handle(player, {
        sessionId = player.sessionId,
        requestId = "mutation-pending-snapshot",
        action = "GetSnapshot",
        payload = {},
    })
    expect(
        pendingSnapshot.ok
            and pendingSnapshot.data.pendingMutation.transactionId == start.data.transactionId,
        "snapshot should restore the server-owned transient reveal"
    )

    now = 4
    local resolveRequest = {
        sessionId = player.sessionId,
        requestId = "resolve-mutation",
        action = "ResolveMutation",
        payload = { transactionId = start.data.transactionId, choice = "Replace" },
    }
    local resolved = actionService:handle(player, resolveRequest)
    expect(resolved.ok and resolved.data.outcome == "Replaced")
    expect(events[#events - 1].event == "MutationApplied")
    expect(events[#events].event == "CodexChanged")
    local eventCountAfterResolve = #events
    local resolvedReplay = actionService:handle(player, resolveRequest)
    expect(resolvedReplay.ok and resolvedReplay.data.outcome == "Replaced")
    expect(#events == eventCountAfterResolve, "resolution replay cannot equip or publish twice")
    expect(EconomyService.getIncomePerMinute(context.dataService:getSnapshot(userId)) > 50)

    player.nearMutation = false
    now = 8
    local outOfRange = actionService:handle(player, {
        sessionId = player.sessionId,
        requestId = "mutation-out-of-range",
        action = "StartMutation",
        payload = { creatureId = profile.starterCreatureId, themeId = "Ember" },
    })
    expect(not outOfRange.ok and outOfRange.code == "OutOfRange")
    phase = "RAID"
    player.nearMutation = true
    now = 12
    local wrongPhase = actionService:handle(player, {
        sessionId = player.sessionId,
        requestId = "mutation-wrong-phase",
        action = "StartMutation",
        payload = { creatureId = profile.starterCreatureId, themeId = "Ember" },
    })
    expect(not wrongPhase.ok and wrongPhase.code == "WrongPhase")
end)

test(
    "ActionService checks session, phase, kiosk, and replays request IDs without duplicate effects",
    function()
        local userId = 805
        local dataService = makeLoadedDataService(userId, "action-")
        assert(dataService:creditScrap(userId, 200), "action test player should afford Welcome")
        local creatureService = CreatureService.new({ playerDataService = dataService })
        local capsuleService = CapsuleService.new({
            playerDataService = dataService,
            creatureService = creatureService,
            generateCreatureId = function()
                return "action-welcome"
            end,
            randomInteger = function()
                return 1
            end,
        })
        local published = {}
        local economyService = EconomyService.new({
            playerDataService = dataService,
            creatureService = creatureService,
            schedule = function() end,
            wait = function() end,
            publish = function(_candidate, scrap, rate)
                table.insert(published, { scrap = scrap, rate = rate })
            end,
        })
        local phase = "PEACE"
        local now = 0
        local player = { UserId = userId, sessionId = "session-current-123", nearKiosk = true }
        local telemetryEvents = {}
        local telemetry = Telemetry.new({
            clock = function()
                return now
            end,
            write = function(event)
                table.insert(telemetryEvents, cloneTable(event))
            end,
        })
        assert(
            telemetry:startSession(userId, player.sessionId, now, dataService:getSnapshot(userId)),
            "test session should start telemetry"
        )
        assert(
            economyService:startPlayer(player),
            "action player should publish initial economy state"
        )
        local domainEvents = {}
        local actionService = ActionService.new({
            sessionService = {
                getSession = function(_self, candidate)
                    if candidate == player then
                        return { userId = userId, sessionId = player.sessionId }
                    end
                    return nil
                end,
            },
            raidService = {
                getSnapshot = function()
                    return { phase = phase }
                end,
            },
            playerDataService = dataService,
            economyService = economyService,
            capsuleService = capsuleService,
            mutationService = {
                getOddsSnapshot = function()
                    return nil
                end,
                getPending = function()
                    return nil
                end,
            },
            theftService = {},
            baseService = {
                isOperational = function()
                    return true
                end,
            },
            requestEvent = {},
            resultEvent = {},
            domainEvent = {
                FireClient = function(_self, _player, event)
                    table.insert(domainEvents, event)
                end,
            },
            emitAnalytics = function(user, event, properties, creatureId)
                return telemetry:record(user, event, properties, creatureId)
            end,
            clock = function()
                return now
            end,
            unixClock = function()
                return 1_000
            end,
            canInteract = function(candidate)
                return candidate.nearKiosk
            end,
            isOperational = function()
                return true
            end,
        })
        local welcomeRequest = {
            sessionId = player.sessionId,
            requestId = "welcome-request-1",
            action = "PurchaseCapsule",
            payload = { kind = "Welcome" },
        }
        local first = actionService:handle(player, welcomeRequest)
        assert(
            first.ok and first.data.scrapBalance == 130,
            "valid request should charge and award once"
        )
        assert(#domainEvents == 2, "successful purchase should emit creature and Scrap events")
        local firstCapsuleCount = 0
        local capsulePurchaseCount = 0
        for _, event in telemetryEvents do
            if event.event == "first_capsule" then
                firstCapsuleCount += 1
            elseif event.event == "capsule_purchased" then
                capsulePurchaseCount += 1
            end
        end
        assert(
            firstCapsuleCount == 1 and capsulePurchaseCount == 1,
            "successful server purchase should produce one telemetry event and one first-capsule event"
        )
        assert(
            published[#published].scrap == 130,
            "capsule purchase should immediately publish its balance"
        )
        local duplicate = actionService:handle(player, welcomeRequest)
        assert(
            duplicate.ok and duplicate.data.creature.id == first.data.creature.id,
            "replay should return cached result"
        )
        assert(#domainEvents == 2, "replay must not emit duplicate domain events")
        firstCapsuleCount = 0
        capsulePurchaseCount = 0
        for _, event in telemetryEvents do
            if event.event == "first_capsule" then
                firstCapsuleCount += 1
            elseif event.event == "capsule_purchased" then
                capsulePurchaseCount += 1
            end
        end
        assert(
            firstCapsuleCount == 1 and capsulePurchaseCount == 1,
            "request replay must not duplicate telemetry"
        )
        assert(dataService:getSnapshot(userId).scrap == 130, "replay must not charge twice")
        assert(
            #dataService:getSnapshot(userId).creatures == 2,
            "replay must not add a second creature"
        )

        local changedPayload = table.clone(welcomeRequest)
        changedPayload.payload = { kind = "Standard" }
        local changedResult = actionService:handle(player, changedPayload)
        assert(
            not changedResult.ok and changedResult.code == "Conflict",
            "a request ID cannot be reused with a different action payload"
        )

        local missingSession = table.clone(welcomeRequest)
        missingSession.sessionId = nil
        local missingSessionResult = actionService:handle(player, missingSession)
        assert(
            not missingSessionResult.ok and missingSessionResult.code == "InvalidRequest",
            "a cached request ID cannot bypass a missing session ID"
        )

        for _ = 1, 16 do
            assert(
                actionService:handle(player, welcomeRequest).ok,
                "cached replay should remain stable"
            )
        end
        local replayFlood = actionService:handle(player, welcomeRequest)
        assert(
            not replayFlood.ok and replayFlood.code == "RateLimited",
            "transport throttling must also cover cached-result replay floods"
        )
        now = 0.1
        local retryAfterLimit = actionService:handle(player, welcomeRequest)
        assert(
            retryAfterLimit.ok and retryAfterLimit.data.creature.id == first.data.creature.id,
            "a transport-limited response must not poison a later retry"
        )
        now = 1.2

        local stale = table.clone(welcomeRequest)
        stale.requestId = "stale-session-request"
        stale.sessionId = "session-old-1234"
        local staleResult = actionService:handle(player, stale)
        assert(
            not staleResult.ok and staleResult.code == "Conflict",
            "old session request should be rejected"
        )

        phase = "RAID"
        local phaseResult = actionService:handle(player, {
            sessionId = player.sessionId,
            requestId = "wrong-phase-request",
            action = "PurchaseCapsule",
            payload = { kind = "Standard" },
        })
        assert(
            not phaseResult.ok and phaseResult.code == "WrongPhase",
            "purchases are blocked during Raid"
        )
        now = 10
        local snapshotResult = actionService:handle(player, {
            sessionId = player.sessionId,
            requestId = "snapshot-request",
            action = "GetSnapshot",
            payload = {},
        })
        assert(
            snapshotResult.ok and snapshotResult.data.phase == "RAID",
            "snapshot remains available in any phase"
        )
        local rateLimitedSnapshot = actionService:handle(player, {
            sessionId = player.sessionId,
            requestId = "snapshot-rate-limited",
            action = "GetSnapshot",
            payload = {},
        })
        assert(
            not rateLimitedSnapshot.ok and rateLimitedSnapshot.code == "RateLimited",
            "GetSnapshot should have an action-specific token bucket"
        )
        now = 12
        local snapshotRetry = actionService:handle(player, {
            sessionId = player.sessionId,
            requestId = "snapshot-rate-limited",
            action = "GetSnapshot",
            payload = {},
        })
        assert(snapshotRetry.ok, "an action-limited request must remain retryable with the same ID")

        phase = "PEACE"
        player.nearKiosk = false
        local outOfRange = actionService:handle(player, {
            sessionId = player.sessionId,
            requestId = "out-of-range-request",
            action = "PurchaseSlot",
            payload = { targetCapacity = 3 },
        })
        assert(
            not outOfRange.ok and outOfRange.code == "OutOfRange",
            "server kiosk distance check should reject the request"
        )
        economyService:stopPlayer(player)
    end
)

test("ActionService contains a client response send error after disconnect", function()
    local userId = 808
    local player = { UserId = userId }
    local dataService = makeLoadedDataService(userId, "response-send-")
    local requestHandler = nil
    local disconnected = false
    local requestEvent = { OnServerEvent = {} }
    requestEvent.OnServerEvent.Connect = function(_signal, callback)
        requestHandler = callback
        return {
            Disconnect = function()
                disconnected = true
            end,
        }
    end
    local service = ActionService.new({
        sessionService = {
            getSession = function()
                return { userId = userId, sessionId = "session-response-123" }
            end,
        },
        raidService = {
            getSnapshot = function()
                return { phase = "PEACE" }
            end,
        },
        playerDataService = dataService,
        economyService = {},
        capsuleService = {},
        mutationService = {
            getOddsSnapshot = function()
                return nil
            end,
            getPending = function()
                return nil
            end,
        },
        theftService = {},
        baseService = {
            isOperational = function()
                return true
            end,
        },
        requestEvent = requestEvent,
        resultEvent = {
            FireClient = function()
                error("player disconnected before response")
            end,
        },
        domainEvent = { FireClient = function() end },
    })
    assert(service:start(), "ActionService should bind its request listener")
    assert(type(requestHandler) == "function", "request listener should be captured")
    local sent, sendError = pcall(requestHandler, player, {
        sessionId = "session-response-123",
        requestId = "snapshot-after-leave",
        action = "GetSnapshot",
        payload = {},
    })
    assert(
        sent,
        "a failed FireClient must not escape the server event handler: " .. tostring(sendError)
    )
    service:stop()
    assert(disconnected, "stopping ActionService should disconnect its event listener")
end)

test(
    "playtest telemetry records bounded progression and loss outcomes without player IDs",
    function()
        local now = 10
        local events = {}
        local telemetry = Telemetry.new({
            clock = function()
                return now
            end,
            write = function(event)
                table.insert(events, cloneTable(event))
            end,
        })
        local profile = {
            creatures = { { id = "starter-id" } },
            welcomeCreatureId = nil,
            tutorialCompleted = false,
            hasCompletedFirstRaid = false,
            firstRaidParticipation = nil,
            slotCapacity = 2,
        }
        assert(telemetry:startSession(9001, "session-anonymous-01", now, profile))
        now = 20
        assert(
            telemetry:record(
                9001,
                "capsule_purchased",
                { kind = "Welcome", rarity = "Uncommon" },
                "welcome-id"
            )
        )
        local eventCountBeforeRejectedPayload = #events
        assert(not telemetry:record(9001, "capsule_purchased", {
            kind = "Standard",
            rarity = "Rare",
            playerUserId = 9001,
        }), "event schema must reject account IDs and arbitrary properties")
        assert(
            #events == eventCountBeforeRejectedPayload,
            "rejected event payloads must not reach the writer"
        )
        assert(telemetry:record(9001, "tutorial_mutation_completed", { theme = "Moss" }))
        assert(telemetry:record(9001, "slot_upgraded", { capacity = 3 }))
        assert(telemetry:record(9001, "first_raid_participated", { reason = "raid_start" }))
        assert(telemetry:record(9001, "first_raid_completed", {}))
        now = 50
        assert(
            telemetry:record(
                9001,
                "creature_lost",
                { rarity = "Rare", hasMutation = true },
                "welcome-id"
            )
        )
        now = 95
        assert(telemetry:endSession(9001))
        assert(not telemetry:endSession(9001), "ending a session twice must be idempotent")
        local eventIndex = {}
        for _, event in events do
            assert(
                event.sessionId == "session-anonymous-01",
                "events should use the anonymous session token"
            )
            assert(event.elapsedSeconds >= 0, "elapsed time should be non-negative")
            assert(
                event.userId == nil and event.playerUserId == nil,
                "events must omit account IDs"
            )
            eventIndex[event.event] = event
        end
        assert(
            eventIndex.first_capsule.elapsedSeconds == 10,
            "first capsule timing should be recorded"
        )
        assert(
            eventIndex.first_mutation.elapsedSeconds == 10,
            "first mutation timing should be recorded"
        )
        assert(eventIndex.slot3_purchased.elapsedSeconds == 10, "Slot 3 timing should be recorded")
        assert(
            eventIndex.first_raid_participated.elapsedSeconds == 10,
            "first Raid timing should be recorded"
        )
        assert(
            eventIndex.creature_lost.properties.ownedSeconds == 30,
            "owned time should be measured"
        )
        assert(
            eventIndex.session_ended.properties.durationSeconds == 85,
            "session duration should be recorded"
        )
        assert(
            eventIndex.session_ended.properties.lossToExitSeconds == 45,
            "loss exit time should be recorded"
        )
        assert(
            eventIndex.session_ended.properties.lossRarity == "Rare",
            "loss rarity should be recorded"
        )
    end
)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
    error(string.format("%d test(s) failed", failed))
end
