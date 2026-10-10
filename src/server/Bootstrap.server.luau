local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
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
local CreatureService = require(ServerScriptService.Server.services.CreatureService)
local CapsuleService = require(ServerScriptService.Server.services.CapsuleService)
local MutationService = require(ServerScriptService.Server.services.MutationService)
local ActionService = require(ServerScriptService.Server.services.ActionService)
local ProfileStore = require(ServerScriptService.Server.persistence.ProfileStore)
local EconomyConfig = require(ReplicatedStorage.Shared.config.EconomyConfig)
local RequestGuard = require(ServerScriptService.Server.security.RequestGuard)

assert(Constants.BASE_COUNT == Constants.MAX_PLAYERS, "base count must match server capacity")
local raidService = RaidService.new({
    clock = os.time,
    generateRaidId = function()
        return HttpService:GenerateGUID(false)
    end,
})
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
local creatureService = CreatureService.new({
    playerDataService = playerDataService,
    baseService = baseService,
})
local economyService = EconomyService.new({
    playerDataService = playerDataService,
    creatureService = creatureService,
})
local capsuleService = CapsuleService.new({
    playerDataService = playerDataService,
    creatureService = creatureService,
    generateCreatureId = function()
        return HttpService:GenerateGUID(false)
    end,
})

local networkFolder = ReplicatedStorage:FindFirstChild("Network")
if networkFolder == nil then
    networkFolder = Instance.new("Folder")
    networkFolder.Name = "Network"
    networkFolder.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name: string): any
    local remote = networkFolder:FindFirstChild(name)
    if remote == nil then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = networkFolder
    end
    assert(remote:IsA("RemoteEvent"), string.format("%s must be a RemoteEvent", name))
    return remote
end

local actionRequest = ensureRemoteEvent(Protocol.RemoteNames.ActionRequest)
local actionResult = ensureRemoteEvent(Protocol.RemoteNames.ActionResult)
local domainEvent = ensureRemoteEvent(Protocol.RemoteNames.DomainEvent)
local blockout = Workspace:WaitForChild("OddlingsBlockout")
local kioskPart = blockout:WaitForChild("CommonsKiosk")
local mutationStationPart = blockout:WaitForChild("MutationStation")
local mutationService = MutationService.new({
    playerDataService = playerDataService,
    creatureService = creatureService,
    generateTransactionId = function()
        return HttpService:GenerateGUID(false)
    end,
    emitEvent = function(userId, event, data, revision)
        local player = Players:GetPlayerByUserId(userId)
        if player ~= nil then
            pcall(function()
                domainEvent:FireClient(player, {
                    event = event,
                    revision = revision,
                    serverTimeUnix = os.time(),
                    data = data,
                })
            end)
        end
    end,
})
local actionService: any = nil
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
        local synced, syncError = creatureService:syncPlayer(player.UserId)
        if not synced then
            warn(string.format("[Base] Could not sync collection: %s", tostring(syncError)))
            return false
        end
        return economyService:startPlayer(player)
    end,
    onSessionEnded = function(player)
        economyService:stopPlayer(player)
        mutationService:clearUser(player.UserId)
        creatureService:cleanupUser(player.UserId)
        if actionService ~= nil then
            actionService:clearUser(player.UserId)
        end
    end,
    onOperationalChanged = function(player, isOperational, _base, joinedDuringRaidId)
        local grace =
            raidService:onOperationalChanged(player.UserId, isOperational, joinedDuringRaidId)
        if grace ~= nil then
            player:SetAttribute(Protocol.PlayerAttributeNames.ArrivalGraceRaidId, grace.raidId)
            player:SetAttribute(
                Protocol.PlayerAttributeNames.ArrivalGraceStartedAtUnix,
                grace.startedAtUnix
            )
            player:SetAttribute(
                Protocol.PlayerAttributeNames.ArrivalGraceEndsAtUnix,
                grace.expiresAtUnix
            )
        end
    end,
    generateSessionId = function()
        return HttpService:GenerateGUID(false)
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
raidService.Changed:Connect(function(snapshot)
    mutationService:onPhaseChanged(snapshot)
    pcall(function()
        domainEvent:FireAllClients({
            event = Protocol.DomainEventNames.RaidPhaseChanged,
            revision = snapshot.revision,
            serverTimeUnix = snapshot.serverTimeUnix,
            data = {
                phase = snapshot.phase,
                phaseStartedAtUnix = snapshot.phaseStartedAtUnix,
                phaseEndsAtUnix = snapshot.phaseEndsAtUnix,
                raidId = snapshot.raidId,
                revision = snapshot.revision,
            },
        })
    end)
end)
actionService = ActionService.new({
    sessionService = sessionService,
    raidService = raidService,
    playerDataService = playerDataService,
    economyService = economyService,
    capsuleService = capsuleService,
    mutationService = mutationService,
    baseService = baseService,
    requestEvent = actionRequest,
    resultEvent = actionResult,
    domainEvent = domainEvent,
    kioskPart = kioskPart,
    mutationStationPart = mutationStationPart,
})
assert(actionService:start(), "ActionService failed to start")
assert(raidService:start(RunService.Heartbeat), "RaidService failed to start")
assert(sessionService:start(Players), "SessionService failed to start")
game:BindToClose(function()
    actionService:stop()
    raidService:stop()
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
