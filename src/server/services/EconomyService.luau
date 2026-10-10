-- Credits server-owned creature income only while a loaded player is online.

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")
local MutationDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.MutationDefinitions)
    else require("../../shared/definitions/MutationDefinitions")
local EconomyConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.EconomyConfig)
    else require("../../shared/config/EconomyConfig")

local EconomyService = {}
EconomyService.__index = EconomyService

local function defaultWait(seconds: number)
    task.wait(seconds)
end

local function defaultSchedule(callback: () -> ())
    task.spawn(callback)
end

local function setValue(parent: any, name: string, className: string, value: number): any
    local child = parent:FindFirstChild(name)
    if child == nil then
        child = Instance.new(className)
        child.Name = name
        child.Parent = parent
    elseif not child:IsA(className) then
        child:Destroy()
        child = Instance.new(className)
        child.Name = name
        child.Parent = parent
    end
    child.Value = value
    return child
end

local function publishLeaderboard(player: any, scrap: number, incomePerMinute: number)
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return
    end
    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats == nil then
        leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"
        leaderstats.Parent = player
    elseif not leaderstats:IsA("Folder") then
        leaderstats:Destroy()
        leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"
        leaderstats.Parent = player
    end
    setValue(leaderstats, "Scrap", "IntValue", scrap)
    setValue(leaderstats, "IncomePerMinute", "NumberValue", incomePerMinute)
end

function EconomyService.new(options: any)
    assert(type(options) == "table", "options are required")
    assert(type(options.playerDataService) == "table", "playerDataService is required")
    assert(type(options.playerDataService.getSnapshot) == "function", "getSnapshot is required")
    assert(type(options.playerDataService.creditScrap) == "function", "creditScrap is required")

    return setmetatable({
        _playerDataService = options.playerDataService,
        _wait = options.wait or defaultWait,
        _schedule = options.schedule or defaultSchedule,
        _publish = options.publish or publishLeaderboard,
        _interval = options.intervalSeconds or EconomyConfig.INCOME_INTERVAL_SECONDS,
        _active = {},
        _fractionalScrap = {},
    }, EconomyService)
end

function EconomyService.getIncomePerMinute(profile: any): number
    if type(profile) ~= "table" or type(profile.creatures) ~= "table" then
        return 0
    end
    local total = 0
    for _, creature in profile.creatures do
        local species = CreatureDefinitions[creature.speciesId]
        if species ~= nil then
            local multiplier = 1
            if creature.mutationFormId ~= nil then
                local form = MutationDefinitions[creature.mutationFormId]
                if form ~= nil then
                    multiplier = form.multiplier
                end
            end
            total += species.scrapPerMinute * multiplier
        end
    end
    return total
end

function EconomyService._publishCurrent(self: any, player: any, userId: number)
    local profile = self._playerDataService:getSnapshot(userId)
    if profile ~= nil then
        self._publish(player, profile.scrap, EconomyService.getIncomePerMinute(profile))
    end
end

function EconomyService.startPlayer(self: any, player: any): (boolean, string?)
    local userId = if type(player) == "table" or typeof(player) == "Instance"
        then player.UserId
        else nil
    if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
        return false, "InvalidPlayer"
    end
    if self._playerDataService:getSnapshot(userId) == nil then
        return false, "ProfileNotLoaded"
    end
    if self._active[userId] ~= nil then
        return true, nil
    end

    local token = {}
    self._active[userId] = { token = token, player = player }
    self._fractionalScrap[userId] = 0
    self:_publishCurrent(player, userId)
    self._schedule(function()
        while self._active[userId] ~= nil and self._active[userId].token == token do
            self._wait(self._interval)
            if self._active[userId] ~= nil and self._active[userId].token == token then
                EconomyService.accrue(self, userId, self._interval)
            end
        end
    end)
    return true, nil
end

function EconomyService.stopPlayer(self: any, player: any): boolean
    local userId = if type(player) == "table" or typeof(player) == "Instance"
        then player.UserId
        else nil
    if type(userId) ~= "number" then
        return false
    end
    local active = self._active[userId]
    if active == nil or active.player ~= player then
        return false
    end
    self._active[userId] = nil
    self._fractionalScrap[userId] = nil
    return true
end

function EconomyService.accrue(
    self: any,
    userId: number,
    elapsedSeconds: number
): (boolean, number, number?, string?)
    local active = self._active[userId]
    if active == nil then
        return false, 0, nil, "PlayerOffline"
    end
    if
        type(elapsedSeconds) ~= "number"
        or elapsedSeconds <= 0
        or elapsedSeconds ~= elapsedSeconds
    then
        return false, 0, nil, "InvalidElapsedTime"
    end
    local profile = self._playerDataService:getSnapshot(userId)
    if profile == nil then
        return false, 0, nil, "ProfileNotLoaded"
    end

    local ratePerMinute = EconomyService.getIncomePerMinute(profile)
    local exact = self._fractionalScrap[userId] + ratePerMinute * elapsedSeconds / 60
    local wholeScrap = math.floor(exact + 1e-9)
    self._fractionalScrap[userId] = exact - wholeScrap
    local credited, amount, balance, creditError =
        self._playerDataService:creditScrap(userId, wholeScrap)
    if not credited then
        return false, 0, balance, creditError
    end
    self:_publishCurrent(active.player, userId)
    return true, amount, balance, nil
end

function EconomyService.getFractionalRemainder(self: any, userId: number): number
    return self._fractionalScrap[userId] or 0
end

return table.freeze(EconomyService)
