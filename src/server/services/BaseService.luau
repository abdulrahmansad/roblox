local BaseService = {}
BaseService.__index = BaseService

local CreatureDefinitions = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.definitions.CreatureDefinitions)
    else require("../../shared/definitions/CreatureDefinitions")
local EconomyConfig = if game ~= nil
    then require(game:GetService("ReplicatedStorage").Shared.config.EconomyConfig)
    else require("../../shared/config/EconomyConfig")

local DEFAULT_BASE_COUNT = 8
local DEFAULT_SLOT_CAPACITY = EconomyConfig.STARTER_SLOT_CAPACITY
local MAX_SLOT_CAPACITY = EconomyConfig.MAX_SLOT_CAPACITY
local STAND_OFFSETS = {
    { x = -6, z = -4 },
    { x = 6, z = -4 },
    { x = -6, z = 4 },
    { x = 6, z = 4 },
}
local STAND_COLORS = {
    locked = Color3 and Color3.fromRGB(84, 88, 92) or nil,
    empty = Color3 and Color3.fromRGB(151, 128, 98) or nil,
    Common = Color3 and Color3.fromRGB(143, 190, 125) or nil,
    Uncommon = Color3 and Color3.fromRGB(91, 159, 215) or nil,
    Rare = Color3 and Color3.fromRGB(178, 113, 207) or nil,
}

local function getUserId(player: any): number?
    if type(player) ~= "table" then
        if typeof == nil or typeof(player) ~= "Instance" then
            return nil
        end
    end

    local userId = player.UserId
    if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
        return nil
    end

    return userId
end

local function makePosition(index: number, count: number): { x: number, y: number, z: number }
    local angle = ((index - 1) * (2 * math.pi / count)) - (math.pi / 2)
    local radius = 67

    return {
        x = math.floor(math.cos(angle) * radius + 0.5),
        y = 5,
        z = math.floor(math.sin(angle) * radius + 0.5),
    }
end

local function cloneBase(base: any): any
    local creatures = {}
    for _, creature in base.creatures do
        local copy = { id = creature.id, speciesId = creature.speciesId }
        if creature.mutationFormId ~= nil then
            copy.mutationFormId = creature.mutationFormId
        end
        table.insert(creatures, copy)
    end
    return {
        id = base.id,
        ownerUserId = base.ownerUserId,
        operational = base.operational,
        slotCapacity = base.slotCapacity,
        creatures = creatures,
        spawn = {
            x = base.spawn.x,
            y = base.spawn.y,
            z = base.spawn.z,
        },
    }
end

function BaseService.new(options: any?)
    options = options or {}
    local baseCount = options.baseCount or DEFAULT_BASE_COUNT
    assert(
        type(baseCount) == "number" and baseCount > 0 and baseCount % 1 == 0,
        "baseCount must be a positive integer"
    )

    local self = setmetatable({
        _bases = {},
        _userIdToBaseIndex = {},
        _onOwnershipChanged = options.onOwnershipChanged,
        _plotParts = {},
        _standParts = {},
    }, BaseService)

    for index = 1, baseCount do
        table.insert(self._bases, {
            id = string.format("Base%02d", index),
            ownerUserId = nil,
            operational = false,
            slotCapacity = DEFAULT_SLOT_CAPACITY,
            creatures = {},
            spawn = makePosition(index, baseCount),
        })
    end

    if options.world ~= nil then
        self:_ensureBlockoutWorld(options.world)
    end

    return self
end

function BaseService._ensurePart(parent: any, name: string, className: string): any
    local instance = parent:FindFirstChild(name)
    if instance ~= nil then
        assert(instance:IsA(className), string.format("%s must be a %s", name, className))
        return instance
    end

    instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

function BaseService._ensureBlockoutWorld(self: any, world: any)
    local folder = world:FindFirstChild("OddlingsBlockout")
    if folder == nil then
        folder = Instance.new("Folder")
        folder.Name = "OddlingsBlockout"
        folder.Parent = world
    else
        assert(folder:IsA("Folder"), "Workspace.OddlingsBlockout must be a Folder")
    end

    local ground = BaseService._ensurePart(folder, "Ground", "Part")
    ground.Anchored = true
    ground.Size = Vector3.new(180, 1, 180)
    ground.CFrame = CFrame.new(0, -0.5, 0)
    ground.Material = Enum.Material.Grass
    ground.Color = Color3.fromRGB(103, 139, 94)

    local kiosk = BaseService._ensurePart(folder, "CommonsKiosk", "Part")
    kiosk.Anchored = true
    kiosk.Size = Vector3.new(12, 4, 8)
    kiosk.CFrame = CFrame.new(0, 2, 0)
    kiosk.Material = Enum.Material.WoodPlanks
    kiosk.Color = Color3.fromRGB(174, 133, 91)
    kiosk:SetAttribute("InteractionRangeStuds", 12)

    local mutationStation = BaseService._ensurePart(folder, "MutationStation", "Part")
    mutationStation.Anchored = true
    mutationStation.Size = Vector3.new(8, 3, 8)
    mutationStation.CFrame = CFrame.new(0, 1.5, 16)
    mutationStation.Material = Enum.Material.Neon
    mutationStation.Color = Color3.fromRGB(112, 151, 173)
    mutationStation:SetAttribute("InteractionRangeStuds", EconomyConfig.KIOSK_RANGE_STUDS)

    for _, base in self._bases do
        local plot = folder:FindFirstChild(base.id)
        if plot == nil then
            plot = Instance.new("Folder")
            plot.Name = base.id
            plot.Parent = folder
        else
            assert(plot:IsA("Folder"), string.format("%s must be a Folder", base.id))
        end

        local pad = BaseService._ensurePart(plot, "Pad", "Part")
        pad.Anchored = true
        pad.Size = Vector3.new(22, 1, 18)
        pad.CFrame = CFrame.new(base.spawn.x, 0.5, base.spawn.z)
        pad.Material = Enum.Material.SmoothPlastic
        pad.Color = Color3.fromRGB(125, 176, 132)
        pad:SetAttribute("BaseId", base.id)
        self._plotParts[base.id] = pad

        local stands = {}
        for slotIndex, offset in STAND_OFFSETS do
            local stand =
                BaseService._ensurePart(plot, string.format("Stand%02d", slotIndex), "Part")
            stand.Anchored = true
            stand.CanCollide = false
            stand.Size = Vector3.new(4, 1, 4)
            stand.CFrame = CFrame.new(base.spawn.x + offset.x, 1.5, base.spawn.z + offset.z)
            stand.Material = Enum.Material.SmoothPlastic
            stand:SetAttribute("BaseId", base.id)
            stand:SetAttribute("SlotIndex", slotIndex)

            local display = BaseService._ensurePart(
                plot,
                string.format("CreatureDisplay%02d", slotIndex),
                "Part"
            )
            display.Anchored = true
            display.CanCollide = false
            display.Shape = Enum.PartType.Ball
            display.Size = Vector3.new(2, 2, 2)
            display.CFrame = CFrame.new(base.spawn.x + offset.x, 3, base.spawn.z + offset.z)
            display.Material = Enum.Material.SmoothPlastic
            display:SetAttribute("BaseId", base.id)
            display:SetAttribute("SlotIndex", slotIndex)
            table.insert(stands, { stand = stand, display = display })
        end
        self._standParts[base.id] = stands
        BaseService._renderStands(self, base)
    end
end

function BaseService._renderStands(self: any, base: any)
    local stands = self._standParts[base.id]
    if stands == nil then
        return
    end

    for slotIndex, parts in stands do
        local creature = base.creatures[slotIndex]
        local species = if creature ~= nil then CreatureDefinitions[creature.speciesId] else nil
        local unlocked = slotIndex <= base.slotCapacity
        local color = if not unlocked then STAND_COLORS.locked else STAND_COLORS.empty
        if species ~= nil then
            color = STAND_COLORS[species.rarity] or color
        end

        parts.stand:SetAttribute("OwnerUserId", base.ownerUserId)
        parts.stand:SetAttribute("Unlocked", unlocked)
        parts.stand:SetAttribute("CreatureId", if creature ~= nil then creature.id else nil)
        parts.stand:SetAttribute("SpeciesId", if creature ~= nil then creature.speciesId else nil)
        parts.stand:SetAttribute("BaseRarity", if species ~= nil then species.rarity else nil)
        parts.stand:SetAttribute(
            "MutationFormId",
            if creature ~= nil then creature.mutationFormId else nil
        )
        parts.stand.Color = color

        parts.display:SetAttribute("OwnerUserId", base.ownerUserId)
        parts.display:SetAttribute("CreatureId", if creature ~= nil then creature.id else nil)
        parts.display:SetAttribute("SpeciesId", if creature ~= nil then creature.speciesId else nil)
        parts.display:SetAttribute("BaseRarity", if species ~= nil then species.rarity else nil)
        parts.display:SetAttribute(
            "MutationFormId",
            if creature ~= nil then creature.mutationFormId else nil
        )
        parts.display.Transparency = if creature ~= nil then 0 else 1
        parts.display.Color = color
    end
end

function BaseService.assign(self: any, player: any): (any?, string?)
    local userId = getUserId(player)
    if userId == nil then
        return nil, "InvalidPlayer"
    end

    local existingIndex = self._userIdToBaseIndex[userId]
    if existingIndex ~= nil then
        return cloneBase(self._bases[existingIndex]), nil
    end

    for index, base in self._bases do
        if base.ownerUserId == nil then
            base.ownerUserId = userId
            base.operational = false
            self._userIdToBaseIndex[userId] = index
            local pad = self._plotParts[base.id]
            if pad ~= nil then
                pad:SetAttribute("OwnerUserId", userId)
            end
            BaseService._renderStands(self, base)
            if self._onOwnershipChanged ~= nil then
                self._onOwnershipChanged(base.id, userId)
            end
            return cloneBase(base), nil
        end
    end

    return nil, "ServerFull"
end

function BaseService.release(self: any, player: any): boolean
    local userId = getUserId(player)
    if userId == nil then
        return false
    end

    local index = self._userIdToBaseIndex[userId]
    if index == nil then
        return false
    end

    local base = self._bases[index]
    if base.ownerUserId ~= userId then
        return false
    end

    base.ownerUserId = nil
    base.operational = false
    base.slotCapacity = DEFAULT_SLOT_CAPACITY
    base.creatures = {}
    self._userIdToBaseIndex[userId] = nil
    local pad = self._plotParts[base.id]
    if pad ~= nil then
        pad:SetAttribute("OwnerUserId", nil)
    end
    BaseService._renderStands(self, base)
    if self._onOwnershipChanged ~= nil then
        self._onOwnershipChanged(base.id, nil)
    end
    return true
end

function BaseService.getForPlayer(self: any, player: any): any?
    local userId = getUserId(player)
    if userId == nil then
        return nil
    end

    local index = self._userIdToBaseIndex[userId]
    if index == nil then
        return nil
    end
    return cloneBase(self._bases[index])
end

function BaseService.getForUserId(self: any, userId: number): any?
    if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
        return nil
    end
    local index = self._userIdToBaseIndex[userId]
    if index == nil then
        return nil
    end
    return cloneBase(self._bases[index])
end

function BaseService.getCreatureDisplayPosition(self: any, userId: number, creatureId: string): any?
    local baseIndex = self._userIdToBaseIndex[userId]
    local base = if baseIndex ~= nil then self._bases[baseIndex] else nil
    if base == nil or base.ownerUserId ~= userId or type(creatureId) ~= "string" then
        return nil
    end
    local slotIndex = nil
    for index, creature in base.creatures do
        if creature.id == creatureId then
            slotIndex = index
            break
        end
    end
    if slotIndex == nil then
        return nil
    end
    local standParts = self._standParts[base.id]
    local parts = if standParts ~= nil then standParts[slotIndex] else nil
    if parts ~= nil and parts.display ~= nil then
        return parts.display.Position
    end
    local offset = STAND_OFFSETS[slotIndex]
    if offset == nil then
        return nil
    end
    return {
        x = base.spawn.x + offset.x,
        y = 3,
        z = base.spawn.z + offset.z,
    }
end

function BaseService.getHomePadPosition(self: any, userId: number): any?
    local baseIndex = self._userIdToBaseIndex[userId]
    local base = if baseIndex ~= nil then self._bases[baseIndex] else nil
    if base == nil or base.ownerUserId ~= userId then
        return nil
    end
    local pad = self._plotParts[base.id]
    if pad ~= nil then
        return pad.Position
    end
    return { x = base.spawn.x, y = 1, z = base.spawn.z }
end

function BaseService.setCollection(
    self: any,
    userId: number,
    creatures: any,
    slotCapacity: number
): boolean
    if
        type(userId) ~= "number"
        or userId <= 0
        or userId % 1 ~= 0
        or type(creatures) ~= "table"
        or type(slotCapacity) ~= "number"
        or slotCapacity % 1 ~= 0
        or slotCapacity < DEFAULT_SLOT_CAPACITY
        or slotCapacity > MAX_SLOT_CAPACITY
    then
        return false
    end

    local baseIndex = self._userIdToBaseIndex[userId]
    local base = if baseIndex ~= nil then self._bases[baseIndex] else nil
    if base == nil or base.ownerUserId ~= userId or #creatures > slotCapacity then
        return false
    end

    local itemCount = 0
    for key in creatures do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #creatures then
            return false
        end
        itemCount += 1
    end
    if itemCount ~= #creatures then
        return false
    end

    local copied = {}
    local seenIds = {}
    for index = 1, #creatures do
        local creature = creatures[index]
        if
            type(creature) ~= "table"
            or type(creature.id) ~= "string"
            or #creature.id == 0
            or #creature.id > 128
            or not CreatureDefinitions.isSpeciesId(creature.speciesId)
            or seenIds[creature.id] == true
        then
            return false
        end
        seenIds[creature.id] = true
        local copy = { id = creature.id, speciesId = creature.speciesId }
        if creature.mutationFormId ~= nil then
            if type(creature.mutationFormId) ~= "string" then
                return false
            end
            copy.mutationFormId = creature.mutationFormId
        end
        copied[index] = copy
    end

    base.slotCapacity = slotCapacity
    base.creatures = copied
    BaseService._renderStands(self, base)
    return true
end

function BaseService.setOperational(self: any, player: any, isOperational: boolean): boolean
    local userId = getUserId(player)
    if userId == nil or type(isOperational) ~= "boolean" then
        return false
    end

    local index = self._userIdToBaseIndex[userId]
    if index == nil then
        return false
    end

    local base = self._bases[index]
    if base.ownerUserId ~= userId then
        return false
    end
    base.operational = isOperational
    return true
end

function BaseService.isOperational(self: any, player: any): boolean
    local base = BaseService.getForPlayer(self, player)
    return base ~= nil and base.operational
end

function BaseService.getAvailableCount(self: any): number
    local count = 0
    for _, base in self._bases do
        if base.ownerUserId == nil then
            count += 1
        end
    end
    return count
end

function BaseService.getAll(self: any): { any }
    local bases = {}
    for _, base in self._bases do
        table.insert(bases, cloneBase(base))
    end
    return bases
end

return table.freeze(BaseService)
