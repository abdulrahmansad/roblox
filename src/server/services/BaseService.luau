local BaseService = {}
BaseService.__index = BaseService

local DEFAULT_BASE_COUNT = 8

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
    return {
        id = base.id,
        ownerUserId = base.ownerUserId,
        operational = base.operational,
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
    }, BaseService)

    for index = 1, baseCount do
        table.insert(self._bases, {
            id = string.format("Base%02d", index),
            ownerUserId = nil,
            operational = false,
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
    self._userIdToBaseIndex[userId] = nil
    local pad = self._plotParts[base.id]
    if pad ~= nil then
        pad:SetAttribute("OwnerUserId", nil)
    end
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
