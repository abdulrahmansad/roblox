-- Central place for the names and shapes of client/server messages.
-- Client supplied values remain untrusted even when they match this protocol.

export type DevPingRequest = {
    requestId: string,
}

export type DevPingResponse = {
    accepted: boolean,
    requestId: string?,
    reason: string?,
}

export type RaidPhase = "PEACE" | "WARNING" | "RAID" | "RESOLUTION" | "COOLDOWN"

export type ArrivalGraceSnapshot = {
    raidId: string,
    startedAtUnix: number,
    expiresAtUnix: number,
    active: boolean,
}

export type RaidSnapshot = {
    phase: RaidPhase,
    phaseStartedAtUnix: number,
    phaseEndsAtUnix: number,
    raidId: string,
    revision: number,
    serverTimeUnix: number,
    arrivalGrace: ArrivalGraceSnapshot?,
}

export type RaidPhaseChangedData = {
    phase: RaidPhase,
    phaseStartedAtUnix: number,
    phaseEndsAtUnix: number,
    raidId: string,
    revision: number,
}

export type TheftAttemptState =
    "CHANNELING"
    | "CARRIED"
    | "BANKING"
    | "DROPPED"
    | "RETURNED"
    | "BANKED"

export type TheftStateChangedData = {
    attemptId: string,
    state: TheftAttemptState,
    thiefUserId: number,
    ownerUserId: number,
    creatureId: string,
    serverTimeUnix: number,
}

local Protocol = {}
local MUTATION_THEMES = { Ember = true, Prism = true, Moss = true }
local MUTATION_CHOICES = { KeepCurrent = true, Replace = true, Decline = true }

Protocol.RemoteNames = table.freeze({
    DevPing = "DevPing",
    ActionRequest = "ActionRequest",
    ActionResult = "ActionResult",
    DomainEvent = "DomainEvent",
})

Protocol.DomainEventNames = table.freeze({
    RaidPhaseChanged = "RaidPhaseChanged",
    CreatureChanged = "CreatureChanged",
    CatalystChanged = "CatalystChanged",
    TheftStateChanged = "TheftStateChanged",
    TheftBanked = "TheftBanked",
    TagResolved = "TagResolved",
})

Protocol.PlayerAttributeNames = table.freeze({
    RaidPhase = "OddlingsRaidPhase",
    RaidPhaseStartedAtUnix = "OddlingsRaidPhaseStartedAtUnix",
    RaidPhaseEndsAtUnix = "OddlingsRaidPhaseEndsAtUnix",
    RaidId = "OddlingsRaidId",
    RaidRevision = "OddlingsRaidRevision",
    RaidServerTimeUnix = "OddlingsRaidServerTimeUnix",
    ArrivalGraceRaidId = "OddlingsArrivalGraceRaidId",
    ArrivalGraceStartedAtUnix = "OddlingsArrivalGraceStartedAtUnix",
    ArrivalGraceEndsAtUnix = "OddlingsArrivalGraceEndsAtUnix",
    CarryingAttemptId = "OddlingsCarryingAttemptId",
    CarriedCreatureId = "OddlingsCarriedCreatureId",
})

local function hasExactKeys(value: any, allowedKeys: { [string]: boolean }): boolean
    if typeof(value) ~= "table" then
        return false
    end
    for key in value do
        if type(key) ~= "string" or allowedKeys[key] ~= true then
            return false
        end
    end
    return true
end

local function isValidPayload(action: string, payload: any): boolean
    if typeof(payload) ~= "table" then
        return false
    end
    if action == "PurchaseCapsule" then
        return hasExactKeys(payload, { kind = true })
            and (payload.kind == "Welcome" or payload.kind == "Standard")
    elseif action == "SellCreature" then
        return hasExactKeys(payload, { creatureId = true })
            and type(payload.creatureId) == "string"
            and #payload.creatureId > 0
            and #payload.creatureId <= 128
    elseif action == "PurchaseSlot" then
        return hasExactKeys(payload, { targetCapacity = true })
            and (payload.targetCapacity == 3 or payload.targetCapacity == 4)
    elseif action == "PurchaseCatalyst" then
        return hasExactKeys(payload, { themeId = true })
            and MUTATION_THEMES[payload.themeId] == true
    elseif action == "CompleteTutorialMutation" then
        return hasExactKeys(payload, { creatureId = true, themeId = true })
            and type(payload.creatureId) == "string"
            and #payload.creatureId > 0
            and #payload.creatureId <= 128
            and MUTATION_THEMES[payload.themeId] == true
    elseif action == "StartMutation" then
        return hasExactKeys(payload, { creatureId = true, themeId = true })
            and type(payload.creatureId) == "string"
            and #payload.creatureId > 0
            and #payload.creatureId <= 128
            and MUTATION_THEMES[payload.themeId] == true
    elseif action == "ResolveMutation" then
        return hasExactKeys(payload, { transactionId = true, choice = true })
            and type(payload.transactionId) == "string"
            and #payload.transactionId > 0
            and #payload.transactionId <= 128
            and MUTATION_CHOICES[payload.choice] == true
    elseif action == "GetSnapshot" then
        return hasExactKeys(payload, {})
    elseif action == "BeginTheft" then
        return hasExactKeys(payload, { targetCreatureId = true })
            and type(payload.targetCreatureId) == "string"
            and #payload.targetCreatureId > 0
            and #payload.targetCreatureId <= 128
    elseif action == "CancelTheft" then
        return hasExactKeys(payload, { attemptId = true })
            and type(payload.attemptId) == "string"
            and #payload.attemptId > 0
            and #payload.attemptId <= 128
    elseif action == "BankTheft" then
        if payload.stage == "Begin" then
            return hasExactKeys(payload, { attemptId = true, stage = true })
                and type(payload.attemptId) == "string"
                and #payload.attemptId > 0
                and #payload.attemptId <= 128
        elseif payload.stage == "Complete" then
            return hasExactKeys(payload, { attemptId = true, stage = true, catalystThemeId = true })
                and type(payload.attemptId) == "string"
                and #payload.attemptId > 0
                and #payload.attemptId <= 128
                and MUTATION_THEMES[payload.catalystThemeId] == true
        end
        return false
    elseif action == "Tag" then
        return hasExactKeys(payload, { targetUserId = true })
            and type(payload.targetUserId) == "number"
            and payload.targetUserId > 0
            and payload.targetUserId % 1 == 0
    elseif action == "RecoverDroppedCreature" then
        return hasExactKeys(payload, { attemptId = true })
            and type(payload.attemptId) == "string"
            and #payload.attemptId > 0
            and #payload.attemptId <= 128
    end
    return false
end

function Protocol.isValidActionRequest(value: any): boolean
    if
        not hasExactKeys(value, {
            sessionId = true,
            requestId = true,
            action = true,
            payload = true,
        })
    then
        return false
    end
    if
        type(value.sessionId) ~= "string"
        or #value.sessionId < 1
        or #value.sessionId > 128
        or type(value.requestId) ~= "string"
        or #value.requestId < 1
        or #value.requestId > 64
        or type(value.action) ~= "string"
    then
        return false
    end
    return isValidPayload(value.action, value.payload)
end

function Protocol.isValidDevPingRequest(value: any): boolean
    if typeof(value) ~= "table" then
        return false
    end

    if typeof(value.requestId) ~= "string" or #value.requestId < 1 or #value.requestId > 64 then
        return false
    end

    for key in value do
        if key ~= "requestId" then
            return false
        end
    end

    return true
end

return table.freeze(Protocol)
