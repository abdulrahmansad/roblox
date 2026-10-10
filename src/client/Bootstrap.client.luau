local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local RaidPresentationController = require(script.Parent.controllers.RaidPresentationController)
local OnboardingController = require(script.Parent.controllers.OnboardingController)
local networkFolder = ReplicatedStorage:WaitForChild("Network")
local pingRemote = networkFolder:WaitForChild(Protocol.RemoteNames.DevPing)

assert(RaidPresentationController.start(), "RaidPresentationController failed to start")
assert(OnboardingController.start(), "OnboardingController failed to start")
script.Destroying:Connect(function()
    OnboardingController.stop()
    RaidPresentationController.stop()
end)

local response = pingRemote:InvokeServer({ requestId = "client-smoke" })
if response.accepted then
    print("[Foundation] Server accepted the validated development smoke request.")
else
    warn(
        "[Foundation] Server rejected the development smoke request: " .. tostring(response.reason)
    )
end
