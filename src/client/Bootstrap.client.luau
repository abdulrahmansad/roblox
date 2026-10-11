local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local RaidPresentationController = require(script.Parent.controllers.RaidPresentationController)
local AudioEffectsController = require(script.Parent.controllers.AudioEffectsController)
local CreaturePresentationController =
    require(script.Parent.controllers.CreaturePresentationController)
local OnboardingController = require(script.Parent.controllers.OnboardingController)
local networkFolder = ReplicatedStorage:WaitForChild("Network")
local pingRemote = networkFolder:WaitForChild(Protocol.RemoteNames.DevPing)

assert(AudioEffectsController.start(), "AudioEffectsController failed to start")
assert(CreaturePresentationController.start(), "CreaturePresentationController failed to start")
assert(RaidPresentationController.start(), "RaidPresentationController failed to start")
assert(OnboardingController.start(), "OnboardingController failed to start")
script.Destroying:Connect(function()
    OnboardingController.stop()
    CreaturePresentationController.stop()
    AudioEffectsController.stop()
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
