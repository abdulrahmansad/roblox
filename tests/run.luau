local Protocol = require("../src/shared/network/Protocol")
local BaseService = require("../src/server/services/BaseService")
local DevPingService = require("../src/server/services/DevPingService")
local RaidService = require("../src/server/services/RaidService")
local RequestGuard = require("../src/server/security/RequestGuard")
local SessionService = require("../src/server/services/SessionService")
local ProfileStore = require("../src/server/persistence/ProfileStore")
local PlayerDataService = require("../src/server/services/PlayerDataService")
local EconomyService = require("../src/server/services/EconomyService")
local CreatureService = require("../src/server/services/CreatureService")
local CapsuleService = require("../src/server/services/CapsuleService")
local ActionService = require("../src/server/services/ActionService")
local EconomyConfig = require("../src/shared/config/EconomyConfig")
local CreatureDefinitions = require("../src/shared/definitions/CreatureDefinitions")

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
        return cloneTable(updated.value), keyInfoFor(updated)
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

test("shared protocol accepts a well-formed request", function()
    assert(
        Protocol.isValidDevPingRequest({ requestId = "test-1" }),
        "valid ping should pass protocol validation"
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

test("Raid phase skeleton publishes only valid sequential transitions", function()
    local service = RaidService.new({
        clock = function()
            return 100
        end,
    })
    local changed = nil
    service.Changed:Connect(function(snapshot)
        changed = snapshot
    end)

    local skipped = service:transitionTo("RAID", 101, 191)
    assert(not skipped, "phase skeleton must reject skipped phases")
    local invalidTime = service:transitionTo("WARNING", 99, 129)
    assert(not invalidTime, "phase start time cannot move backward")
    local notFinite = service:transitionTo("WARNING", math.huge, math.huge)
    assert(not notFinite, "phase timestamps must be finite")
    local advanced = service:transitionTo("WARNING", 101, 131)
    assert(advanced, "PEACE may transition to WARNING")
    assert(changed.phase == "WARNING", "phase update should be published")
    assert(changed.phaseStartedAtUnix == 101, "phase start time should be server-owned")
end)

test("session inherits phase, spawns at its base, and cleans up on leave", function()
    local baseService = BaseService.new({ baseCount = 8 })
    local raidService = RaidService.new({
        initialPhase = "WARNING",
        clock = function()
            return 500
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

    local transitioned = raidService:transitionTo("RAID", 510, 600)
    assert(transitioned, "phase skeleton should advance to RAID")
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
    local economyService = EconomyService.new({
        playerDataService = dataService,
        schedule = function(callback)
            table.insert(scheduled, callback)
        end,
        wait = function() end,
        publish = function(_player, scrap, rate)
            table.insert(published, { scrap = scrap, rate = rate })
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

    assert(economyService:stopPlayer(player), "leaving should stop the income loop")
    local offline, _, _, offlineReason = economyService:accrue(701, 600)
    assert(
        not offline and offlineReason == "PlayerOffline",
        "offline time must never accrue income"
    )
    assert(dataService:getSnapshot(701).scrap == 90, "offline interval must not change Scrap")
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

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
    error(string.format("%d test(s) failed", failed))
end
