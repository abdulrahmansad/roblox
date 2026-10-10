local Protocol = require("../src/shared/network/Protocol")
local BaseService = require("../src/server/services/BaseService")
local DevPingService = require("../src/server/services/DevPingService")
local RaidService = require("../src/server/services/RaidService")
local RequestGuard = require("../src/server/security/RequestGuard")
local SessionService = require("../src/server/services/SessionService")

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

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
    error(string.format("%d test(s) failed", failed))
end
