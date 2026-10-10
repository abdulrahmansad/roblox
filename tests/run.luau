local Protocol = require("../src/shared/network/Protocol")
local DevPingService = require("../src/server/services/DevPingService")
local RequestGuard = require("../src/server/security/RequestGuard")

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

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
    error(string.format("%d test(s) failed", failed))
end
