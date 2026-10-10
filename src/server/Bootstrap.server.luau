local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local DevPingService = require(ServerScriptService.Server.services.DevPingService)
local RequestGuard = require(ServerScriptService.Server.security.RequestGuard)
local pingService = DevPingService.new(Protocol, RequestGuard)

local networkFolder = ReplicatedStorage:FindFirstChild("Network")
if networkFolder == nil then
    networkFolder = Instance.new("Folder")
    networkFolder.Name = "Network"
    networkFolder.Parent = ReplicatedStorage
end

local pingRemote = networkFolder:FindFirstChild(Protocol.RemoteNames.DevPing)
if pingRemote == nil then
    pingRemote = Instance.new("RemoteFunction")
    pingRemote.Name = Protocol.RemoteNames.DevPing
    pingRemote.Parent = networkFolder
end

assert(pingRemote:IsA("RemoteFunction"), "DevPing must be a RemoteFunction")
pingRemote.OnServerInvoke = function(_player, payload)
    return pingService:handle(payload)
end

print("[Foundation] Server initialized; DevPing request validation is ready.")
