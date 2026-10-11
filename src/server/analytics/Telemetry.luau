-- Server-owned, low-cardinality events. Serialized output never includes UserIds.

local Telemetry = {}
Telemetry.__index = Telemetry

local RARITIES = { Common = true, Uncommon = true, Rare = true }
local MUTATION_TIERS = { Common = true, Uncommon = true, Rare = true, Mythic = true }
local THEMES = { Ember = true, Prism = true, Moss = true }
local EVENT_SCHEMAS = {
    session_started = { newPlayer = "boolean" },
    capsule_purchased = { kind = { Welcome = true, Standard = true }, rarity = RARITIES },
    first_capsule = { kind = { Welcome = true, Standard = true }, rarity = RARITIES },
    tutorial_mutation_completed = { theme = THEMES },
    first_mutation = {},
    mutation_rolled = { tier = MUTATION_TIERS, rarePityActive = "boolean" },
    scrap_earned = { source = { income = true, sale = true }, amount = "number" },
    scrap_spent = {
        sink = { capsule = true, catalyst = true, mutation = true, slot = true },
        amount = "number",
    },
    slot_upgraded = { capacity = { [3] = true, [4] = true } },
    slot3_purchased = {},
    first_raid_participated = {
        reason = { raid_start = true, arrival_grace_expired = true },
    },
    first_raid_completed = {},
    arrival_grace_started = {},
    arrival_grace_expired = { eligible = "boolean" },
    theft_protection_check = {
        role = { actor = true, target = true },
        starterProtected = "boolean",
        welcomeProtected = "boolean",
        ownerArrivalGrace = "boolean",
        thiefArrivalGrace = "boolean",
    },
    creature_lost = { rarity = RARITIES, hasMutation = "boolean", ownedSeconds = "number?" },
    theft_banked = { rarity = RARITIES, hasMutation = "boolean" },
    tag_succeeded = { outcome = { Cancelled = true, Dropped = true } },
    creature_recovered = { rarity = RARITIES },
    creature_auto_returned = { rarity = RARITIES },
    session_ended = {
        durationSeconds = "number",
        lossToExitSeconds = "number?",
        lossRarity = "rarity?",
    },
}

local function finiteNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validSessionId(value: any): boolean
    return type(value) == "string" and #value >= 8 and #value <= 128
end

local function validProperties(schema: any, properties: any): boolean
    if type(properties) ~= "table" then
        return false
    end
    for key, value in properties do
        local rule = schema[key]
        if rule == nil then
            return false
        elseif type(rule) == "table" then
            if rule[value] ~= true then
                return false
            end
        elseif rule == "boolean" then
            if type(value) ~= "boolean" then
                return false
            end
        elseif rule == "number" or rule == "number?" then
            if not finiteNumber(value) or value < 0 or value > 86_400 then
                return false
            end
        elseif rule == "rarity?" then
            if RARITIES[value] ~= true then
                return false
            end
        else
            return false
        end
    end
    for key in schema do
        local rule = schema[key]
        if rule ~= "number?" and rule ~= "rarity?" and properties[key] == nil then
            return false
        end
    end
    return true
end

function Telemetry.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.write) == "function", "write is required")
    return setmetatable({
        _clock = options.clock or os.clock,
        _write = options.write,
        _sessions = {},
    }, Telemetry)
end

function Telemetry._emit(self: any, session: any, eventName: string, properties: any): boolean
    local event = {
        event = eventName,
        sessionId = session.sessionId,
        elapsedSeconds = math.floor(math.max(0, self._clock() - session.startedAt)),
        properties = properties,
    }
    local ok = pcall(self._write, event)
    return ok
end

function Telemetry.startSession(
    self: any,
    userId: number,
    sessionId: string,
    joinedAt: number,
    profile: any
): boolean
    if
        type(userId) ~= "number"
        or userId <= 0
        or userId % 1 ~= 0
        or not validSessionId(sessionId)
        or not finiteNumber(joinedAt)
        or type(profile) ~= "table"
        or type(profile.creatures) ~= "table"
    then
        return false
    end
    local now = self._clock()
    if not finiteNumber(now) or now < joinedAt then
        return false
    end
    local acquiredAt = {}
    for _, creature in profile.creatures do
        if type(creature) == "table" and type(creature.id) == "string" then
            acquiredAt[creature.id] = now
        end
    end
    local session = {
        sessionId = sessionId,
        startedAt = joinedAt,
        acquiredAt = acquiredAt,
        firstCapsule = #profile.creatures <= 1 and profile.welcomeCreatureId == nil,
        firstMutation = profile.tutorialCompleted == false,
        firstRaid = profile.hasCompletedFirstRaid == false
            and profile.firstRaidParticipation == nil,
        raidParticipated = type(profile.firstRaidParticipation) == "table",
        slot3 = profile.slotCapacity == 2,
        lastLossAt = nil,
        lastLossRarity = nil,
        ended = false,
    }
    self._sessions[userId] = session
    self:_emit(session, "session_started", { newPlayer = session.firstCapsule })
    return true
end

function Telemetry.record(
    self: any,
    userId: number,
    eventName: string,
    properties: any?,
    creatureId: string?
): boolean
    local session = self._sessions[userId]
    if session == nil or session.ended then
        return false
    end
    if eventName == "creature_acquired" then
        if type(creatureId) ~= "string" or #creatureId < 1 or #creatureId > 128 then
            return false
        end
        session.acquiredAt[creatureId] = self._clock()
        return true
    end

    local schema = EVENT_SCHEMAS[eventName]
    local fields = properties or {}
    if schema == nil or not validProperties(schema, fields) then
        return false
    end
    if eventName == "capsule_purchased" then
        if type(creatureId) == "string" then
            session.acquiredAt[creatureId] = self._clock()
        end
        self:_emit(session, eventName, fields)
        if session.firstCapsule then
            session.firstCapsule = false
            self:_emit(session, "first_capsule", fields)
        end
        return true
    elseif eventName == "tutorial_mutation_completed" then
        self:_emit(session, eventName, fields)
        if session.firstMutation then
            session.firstMutation = false
            self:_emit(session, "first_mutation", {})
        end
        return true
    elseif eventName == "slot_upgraded" then
        self:_emit(session, eventName, fields)
        if fields.capacity == 3 and session.slot3 then
            session.slot3 = false
            self:_emit(session, "slot3_purchased", {})
        end
        return true
    elseif eventName == "first_raid_participated" then
        if not session.firstRaid then
            return false
        end
        session.firstRaid = false
        session.raidParticipated = true
    elseif eventName == "first_raid_completed" then
        if not session.raidParticipated then
            return false
        end
        session.raidParticipated = false
    elseif eventName == "creature_lost" then
        local acquiredAt = if type(creatureId) == "string"
            then session.acquiredAt[creatureId]
            else nil
        if acquiredAt == nil then
            return false
        end
        local ownedSeconds = math.floor(math.clamp(self._clock() - acquiredAt, 0, 86_400))
        fields = {
            rarity = fields.rarity,
            hasMutation = fields.hasMutation,
            ownedSeconds = ownedSeconds,
        }
        if not validProperties(schema, fields) then
            return false
        end
        session.acquiredAt[creatureId] = nil
        session.lastLossAt = self._clock()
        session.lastLossRarity = fields.rarity
    elseif eventName == "theft_banked" then
        if type(creatureId) == "string" then
            session.acquiredAt[creatureId] = self._clock()
        end
    elseif eventName == "creature_recovered" or eventName == "creature_auto_returned" then
        if type(creatureId) == "string" and session.acquiredAt[creatureId] == nil then
            session.acquiredAt[creatureId] = self._clock()
        end
    end
    return self:_emit(session, eventName, fields)
end

function Telemetry.endSession(self: any, userId: number): boolean
    local session = self._sessions[userId]
    if session == nil or session.ended then
        return false
    end
    session.ended = true
    local now = self._clock()
    local properties = { durationSeconds = math.floor(math.max(0, now - session.startedAt)) }
    if session.lastLossAt ~= nil then
        properties.lossToExitSeconds = math.floor(math.max(0, now - session.lastLossAt))
        properties.lossRarity = session.lastLossRarity
    end
    self:_emit(session, "session_ended", properties)
    self._sessions[userId] = nil
    return true
end

return table.freeze(Telemetry)
