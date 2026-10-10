local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local Constants = require(ReplicatedStorage.Shared.config.Constants)
local DevPingService = require(ServerScriptService.Server.services.DevPingService)
local BaseService = require(ServerScriptService.Server.services.BaseService)
local RaidService = require(ServerScriptService.Server.services.RaidService)
local SessionService = require(ServerScriptService.Server.services.SessionService)
local RequestGuard = require(ServerScriptService.Server.security.RequestGuard)

assert(Constants.BASE_COUNT == Constants.MAX_PLAYERS, "base count must match server capacity")
local raidService = RaidService.new()
local baseService = BaseService.new({
    baseCount = Constants.BASE_COUNT,
    world = Workspace,
})
local sessionService = SessionService.new({
    baseService = baseService,
    raidService = raidService,
    onRejected = function(player, reason)
        warn(string.format("[Session] Rejecting player: %s", reason))
        player:Kick("This server has reached its player limit. Please join another server.")
    end,
})
assert(sessionService:start(Players), "SessionService failed to start")

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
