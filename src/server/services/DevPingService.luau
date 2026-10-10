local DevPingService = {}
DevPingService.__index = DevPingService

function DevPingService.new(protocol: any, requestGuard: any)
    assert(typeof(protocol) == "table", "protocol dependency is required")
    assert(typeof(protocol.isValidDevPingRequest) == "function", "protocol validator is required")
    assert(typeof(requestGuard) == "table", "request guard dependency is required")
    assert(
        typeof(requestGuard.validateDevPing) == "function",
        "request guard validator is required"
    )

    return setmetatable({
        _protocol = protocol,
        _requestGuard = requestGuard,
        _initialized = true,
    }, DevPingService)
end

function DevPingService.handle(self, payload: any)
    if not self._initialized then
        return { accepted = false, reason = "ServiceUnavailable" }
    end

    local valid, reason = self._requestGuard.validateDevPing(self._protocol, payload)
    if not valid then
        return { accepted = false, reason = reason }
    end

    return {
        accepted = true,
        requestId = payload.requestId,
    }
end

return table.freeze(DevPingService)
