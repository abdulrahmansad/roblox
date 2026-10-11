-- Locked compact-map dimensions and route layout, shared by server world setup and tests.

local WorldConfig = {
    MAP_FOOTPRINT_STUDS = 180,
    BASE_COUNT = 8,
    BASE_RING_RADIUS = 67,
    CHASE_LOOP_RADIUS = 44,
    CHASE_LOOP_WIDTH = 8,
    COMMONS_RADIUS = 21,
    BASE_PAD_SIZE_X = 22,
    BASE_PAD_SIZE_Z = 18,
    CHASE_SEGMENT_COUNT = 8,
    COMMONS_SPOKE_COUNT = 4,
    ZONES = { "BaseRing", "Commons", "ChaseLoop" },
}

function WorldConfig.getBaseSpawn(
    index: number,
    count: number
): { x: number, y: number, z: number }?
    if
        type(index) ~= "number"
        or index % 1 ~= 0
        or type(count) ~= "number"
        or count % 1 ~= 0
        or count < 1
        or index < 1
        or index > count
    then
        return nil
    end
    local angle = ((index - 1) * (2 * math.pi / count)) - (math.pi / 2)
    return {
        x = math.floor(math.cos(angle) * WorldConfig.BASE_RING_RADIUS + 0.5),
        y = 5,
        z = math.floor(math.sin(angle) * WorldConfig.BASE_RING_RADIUS + 0.5),
    }
end

table.freeze(WorldConfig.ZONES)
return table.freeze(WorldConfig)
