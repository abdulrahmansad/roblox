local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local Constants = require(ReplicatedStorage.Shared.config.Constants)
local DevPingService = require(ServerScriptService.Server.services.DevPingService)
local BaseService = require(ServerScriptService.Server.services.BaseService)
local RaidService = require(ServerScriptService.Server.services.RaidService)
local SessionService = require(ServerScriptService.Server.services.SessionService)
local PlayerDataService = require(ServerScriptService.Server.services.PlayerDataService)
local EconomyService = require(ServerScriptService.Server.services.EconomyService)
local ProfileStore = require(ServerScriptService.Server.persistence.ProfileStore)
local EconomyConfig = require(ReplicatedStorage.Shared.config.EconomyConfig)
local RequestGuard = require(ServerScriptService.Server.security.RequestGuard)

assert(Constants.BASE_COUNT == Constants.MAX_PLAYERS, "base count must match server capacity")
local raidService = RaidService.new()
local baseService = BaseService.new({
    baseCount = Constants.BASE_COUNT,
    world = Workspace,
})
local profileStore = ProfileStore.new({
    store = DataStoreService:GetDataStore("OddlingsPlayerData"),
    validate = PlayerDataService.validateProfile,
    clock = os.time,
    generateToken = function()
        return HttpService:GenerateGUID(false)
    end,
    serverId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false),
    lockTtlSeconds = EconomyConfig.SESSION_LOCK_TTL_SECONDS,
    maxAttempts = EconomyConfig.STORE_MAX_ATTEMPTS,
})
local playerDataService = PlayerDataService.new({
    profileStore = profileStore,
    clock = os.time,
    generateCreatureId = function()
        return HttpService:GenerateGUID(false)
    end,
    autoSaveEnabled = true,
    autoSaveIntervalSeconds = EconomyConfig.AUTOSAVE_INTERVAL_SECONDS,
})
local economyService = EconomyService.new({ playerDataService = playerDataService })
local sessionService = SessionService.new({
    baseService = baseService,
    raidService = raidService,
    loadProfile = function(player)
        local loaded, reason = playerDataService:load(player.UserId)
        if not loaded then
            warn(string.format("[PlayerData] Load rejected: %s", tostring(reason)))
        end
        return loaded, reason
    end,
    saveProfile = function(player)
        local saved, reason = playerDataService:unload(player.UserId)
        if not saved then
            warn(string.format("[PlayerData] Unload deferred: %s", tostring(reason)))
        end
        return saved, reason
    end,
    onSessionReady = function(player)
        return economyService:startPlayer(player)
    end,
    onSessionEnded = function(player)
        economyService:stopPlayer(player)
    end,
    onRejected = function(player, reason)
        warn(string.format("[Session] Rejecting player: %s", reason))
        if reason == "ServerFull" then
            player:Kick("This server has reached its player limit. Please join another server.")
        else
            player:Kick("Your player data could not be loaded safely. Please try joining again.")
        end
    end,
})
assert(sessionService:start(Players), "SessionService failed to start")
game:BindToClose(function()
    for _, player in Players:GetPlayers() do
        economyService:stopPlayer(player)
    end
    local saved, failureCount = playerDataService:saveAllAndRelease(25)
    if not saved then
        warn(string.format("[PlayerData] Shutdown saves incomplete (%d profiles)", failureCount))
    end
    sessionService:stop()
end)

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
