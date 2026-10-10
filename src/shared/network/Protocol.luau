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

local Protocol = {}

Protocol.RemoteNames = table.freeze({
    DevPing = "DevPing",
    ActionRequest = "ActionRequest",
    ActionResult = "ActionResult",
    DomainEvent = "DomainEvent",
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
    elseif action == "GetSnapshot" then
        return hasExactKeys(payload, {})
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
