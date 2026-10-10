return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Protocol = require(ReplicatedStorage.Shared.network.Protocol)

    describe("shared request protocol", function()
        it("accepts a well-formed development ping", function()
            expect(Protocol.isValidDevPingRequest({ requestId = "testez" })).to.equal(true)
        end)

        it("rejects client-supplied authority fields", function()
            expect(Protocol.isValidDevPingRequest({ requestId = "testez", currency = 100 })).to.equal(
                false
            )
        end)
    end)
end
