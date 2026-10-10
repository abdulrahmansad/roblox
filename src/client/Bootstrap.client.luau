local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local networkFolder = ReplicatedStorage:WaitForChild("Network")
local pingRemote = networkFolder:WaitForChild(Protocol.RemoteNames.DevPing)

local response = pingRemote:InvokeServer({ requestId = "client-smoke" })
if response.accepted then
    print("[Foundation] Server accepted the validated development smoke request.")
else
    warn(
        "[Foundation] Server rejected the development smoke request: " .. tostring(response.reason)
    )
end
