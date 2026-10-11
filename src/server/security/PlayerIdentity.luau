-- Maps Roblox players to server-side profile keys.
-- Studio local clients use negative UserIds; those are only mapped when the
-- unpublished-place volatile datastore adapter is active.
local PlayerIdentity = {}

local MAX_PROFILE_USER_ID = 2_147_483_647
local MAX_STUDIO_TEST_CLIENTS = 8

local function isPlayerCandidate(player: any): boolean
    if type(player) == "table" then
        return true
    end
    if typeof == nil or typeof(player) ~= "Instance" then
        return false
    end
    return player:IsA("Player")
end

function PlayerIdentity.resolve(player: any, allowStudioTestUsers: boolean?): number?
    if not isPlayerCandidate(player) then
        return nil
    end

    local userId = player.UserId
    if type(userId) ~= "number" or userId % 1 ~= 0 or userId > MAX_PROFILE_USER_ID then
        return nil
    end

    if userId > 0 then
        return userId
    end

    if allowStudioTestUsers ~= true or userId < -MAX_STUDIO_TEST_CLIENTS or userId == 0 then
        return nil
    end

    -- Keep the mapping inside the profile schema's valid range. It is only used
    -- with the process-local Studio datastore and is never published or saved.
    return MAX_PROFILE_USER_ID + userId + 1
end

return table.freeze(PlayerIdentity)
