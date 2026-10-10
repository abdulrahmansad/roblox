-- Shared server-side request boundary. Extend with identity, ownership, phase,
-- proximity, cooldown, replay, and rate checks when real gameplay requests exist.

local RequestGuard = {}

function RequestGuard.validateDevPing(protocol: any, payload: any): (boolean, string?)
    if not protocol.isValidDevPingRequest(payload) then
        return false, "MalformedRequest"
    end

    return true, nil
end

return table.freeze(RequestGuard)
