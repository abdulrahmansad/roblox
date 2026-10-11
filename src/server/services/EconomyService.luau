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
local MutationConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.MutationConfig)
    else require("../../shared/config/MutationConfig")

local EconomyService = {}
EconomyService.__index = EconomyService

local function defaultWait(seconds: number)
    task.wait(seconds)
end

local function defaultSchedule(callback: () -> ())
    task.spawn(callback)
end

local function defaultResolveUserId(player: any): number?
    if type(player) == "table" or typeof(player) == "Instance" then
        return player.UserId
    end
    return nil
end

local function resolveUserId(self: any, player: any): number?
    if type(player) ~= "table" and typeof(player) ~= "Instance" then
        return nil
    end
    local ok, userId = pcall(self._resolveUserId, player)
    if not ok or type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
        return nil
    end
    return userId
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
    assert(
        type(options.playerDataService.transact) == "function",
        "profile transaction is required"
    )

    return setmetatable({
        _playerDataService = options.playerDataService,
        _creatureService = options.creatureService,
        _resolveUserId = options.resolveUserId or defaultResolveUserId,
        _wait = options.wait or defaultWait,
        _schedule = options.schedule or defaultSchedule,
        _publish = options.publish or publishLeaderboard,
        _emitIncomeEvent = options.emitIncomeEvent,
        _interval = options.intervalSeconds or EconomyConfig.INCOME_INTERVAL_SECONDS,
        _active = {},
        _fractionalScrap = {},
    }, EconomyService)
end

local ECONOMY_PHASES = { PEACE = true, WARNING = true, COOLDOWN = true }

function EconomyService.purchaseCatalyst(
    self: any,
    userId: number,
    themeId: string,
    phase: string
): (any?, string?)
    if ECONOMY_PHASES[phase] ~= true then
        return nil, "WrongPhase"
    end
    local catalystId = MutationConfig.CATALYSTS_BY_THEME[themeId]
    if catalystId == nil then
        return nil, "InvalidRequest"
    end

    local success, data, errorCode = self._playerDataService:transact(userId, function(profile)
        if profile.scrap < MutationConfig.CATALYST_PRICE then
            return nil, "InsufficientScrap"
        end
        if profile.catalysts[catalystId] >= MutationConfig.MAX_CATALYST_COUNT then
            return nil, "Unavailable"
        end
        profile.scrap -= MutationConfig.CATALYST_PRICE
        profile.catalysts[catalystId] += 1
        return {
            themeId = themeId,
            count = profile.catalysts[catalystId],
            scrapBalance = profile.scrap,
        },
            nil
    end)
    if not success then
        return nil, errorCode or "Unavailable"
    end
    EconomyService.refreshPlayer(self, userId)
    return data, nil
end

function EconomyService.sellCreature(
    self: any,
    userId: number,
    creatureId: string,
    phase: string
): (any?, string?)
    if ECONOMY_PHASES[phase] ~= true then
        return nil, "WrongPhase"
    end
    if self._creatureService == nil then
        return nil, "Unavailable"
    end

    local success, data, errorCode = self._playerDataService:transact(userId, function(profile)
        if profile.scrap > EconomyConfig.MAX_SCRAP - EconomyConfig.CREATURE_SALE_VALUE then
            return nil, "Unavailable"
        end
        local creature, removeError =
            self._creatureService:removeFromProfile(userId, profile, creatureId)
        if creature == nil then
            return nil, if removeError == "StarterProtected" then "Locked" else removeError
        end
        profile.scrap += EconomyConfig.CREATURE_SALE_VALUE
        return {
            creatureId = creature.id,
            refund = EconomyConfig.CREATURE_SALE_VALUE,
            scrapBalance = profile.scrap,
        },
            nil
    end)
    if not success then
        return nil, errorCode or "Unavailable"
    end
    local synced, syncError = self._creatureService:syncPlayer(userId)
    if not synced then
        warn(string.format("[Base] Could not sync collection after sale: %s", tostring(syncError)))
    end
    EconomyService.refreshPlayer(self, userId)
    return data, nil
end

function EconomyService.purchaseSlot(
    self: any,
    userId: number,
    targetCapacity: number,
    phase: string
): (any?, string?)
    if ECONOMY_PHASES[phase] ~= true then
        return nil, "WrongPhase"
    end
    if targetCapacity ~= 3 and targetCapacity ~= 4 then
        return nil, "InvalidRequest"
    end

    local success, data, errorCode = self._playerDataService:transact(userId, function(profile)
        local price
        local slot3Capacity = EconomyConfig.STARTER_SLOT_CAPACITY + 1
        if
            profile.slotCapacity == EconomyConfig.STARTER_SLOT_CAPACITY
            and targetCapacity == slot3Capacity
        then
            if #profile.creatures < EconomyConfig.STARTER_SLOT_CAPACITY then
                return nil, "Unavailable"
            end
            price = EconomyConfig.SLOT_3_PRICE
        elseif
            profile.slotCapacity == slot3Capacity
            and targetCapacity == EconomyConfig.MAX_SLOT_CAPACITY
        then
            if not profile.hasCompletedFirstRaid or #profile.creatures < slot3Capacity then
                return nil, "Unavailable"
            end
            price = EconomyConfig.SLOT_4_PRICE
        else
            return nil, "Conflict"
        end
        if profile.scrap < price then
            return nil, "InsufficientScrap"
        end

        profile.scrap -= price
        profile.slotCapacity = targetCapacity
        return { slotCapacity = targetCapacity, scrapBalance = profile.scrap }, nil
    end)
    if not success then
        return nil, errorCode or "Unavailable"
    end
    if self._creatureService ~= nil then
        local synced, syncError = self._creatureService:syncPlayer(userId)
        if not synced then
            warn(
                string.format(
                    "[Base] Could not sync capacity after slot purchase: %s",
                    tostring(syncError)
                )
            )
        end
    end
    EconomyService.refreshPlayer(self, userId)
    return data, nil
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

function EconomyService.refreshPlayer(self: any, userId: number): boolean
    local active = self._active[userId]
    if active == nil then
        return false
    end
    self:_publishCurrent(active.player, userId)
    return true
end

function EconomyService.startPlayer(self: any, player: any): (boolean, string?)
    local userId = resolveUserId(self, player)
    if userId == nil then
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
    local userId = resolveUserId(self, player)
    if userId == nil then
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
    if amount > 0 and type(self._emitIncomeEvent) == "function" then
        -- Presentation notifications must never interfere with a committed payout.
        pcall(self._emitIncomeEvent, active.player, userId, amount, balance)
    end
    self:_publishCurrent(active.player, userId)
    return true, amount, balance, nil
end

function EconomyService.getFractionalRemainder(self: any, userId: number): number
    return self._fractionalScrap[userId] or 0
end

return table.freeze(EconomyService)
