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
})

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
