local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local HudModel = require(script.Parent.HudModel)
local PLAYER_ATTRIBUTES = Protocol.PlayerAttributeNames

local PHASES = {
    PEACE = true,
    WARNING = true,
    RAID = true,
    RESOLUTION = true,
    COOLDOWN = true,
}

local controller = {}
local state: any = nil
local localSyncTime = 0
local connections = {}
local screenGui: ScreenGui? = nil
local phaseLabel: TextLabel? = nil
local graceLabel: TextLabel? = nil
local scrapLabel: TextLabel? = nil
local incomeLabel: TextLabel? = nil
local slotsLabel: TextLabel? = nil
local started = false
local renderLoopGeneration = 0
local RENDER_INTERVAL_SECONDS = 0.25

local function isFiniteNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function createLabel(parent: Instance, name: string, position: UDim2, size: UDim2): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.Position = position
    label.Size = size
    label.TextColor3 = Color3.fromRGB(247, 249, 255)
    label.TextSize = 18
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = parent
    return label
end

local function ensureGui(playerGui: PlayerGui)
    local existing = playerGui:FindFirstChild("OddlingsRaidPresentation")
    if existing ~= nil and existing:IsA("ScreenGui") then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "OddlingsRaidPresentation"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 20
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "PhasePanel"
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, 0, 0, 12)
    frame.Size = UDim2.new(1, -24, 0, 104)
    frame.BackgroundColor3 = Color3.fromRGB(21, 28, 40)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MaxSize = Vector2.new(480, 104)
    sizeConstraint.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(113, 151, 194)
    stroke.Transparency = 0.35
    stroke.Thickness = 1
    stroke.Parent = frame

    phaseLabel =
        createLabel(frame, "PhaseAndTimer", UDim2.fromOffset(8, 3), UDim2.new(1, -16, 0, 30))
    phaseLabel.Text = "CONNECTING TO RAID CLOCK"
    phaseLabel.TextSize = 18

    graceLabel =
        createLabel(frame, "ArrivalGrace", UDim2.fromOffset(8, 32), UDim2.new(1, -16, 0, 18))
    graceLabel.Text = ""
    graceLabel.TextColor3 = Color3.fromRGB(170, 229, 255)
    graceLabel.TextSize = 12

    scrapLabel =
        createLabel(frame, "ScrapStatus", UDim2.fromOffset(8, 57), UDim2.new(1 / 3, -8, 0, 36))
    incomeLabel =
        createLabel(frame, "IncomeStatus", UDim2.new(1 / 3, 0, 0, 57), UDim2.new(1 / 3, 0, 0, 36))
    slotsLabel =
        createLabel(frame, "SlotsStatus", UDim2.new(2 / 3, 0, 0, 57), UDim2.new(1 / 3, -8, 0, 36))
    for _, label in { scrapLabel, incomeLabel, slotsLabel } do
        label.TextSize = 13
        label.TextWrapped = true
    end
    scrapLabel.Text = "SCRAP —"
    incomeLabel.Text = "SCRAP/MIN —"
    slotsLabel.Text = "SLOTS —"

    screenGui = gui
end

local function setState(snapshot: any, serverTimeUnix: any)
    if
        type(snapshot) ~= "table"
        or PHASES[snapshot.phase] ~= true
        or not isFiniteNumber(snapshot.phaseStartedAtUnix)
        or not isFiniteNumber(snapshot.phaseEndsAtUnix)
        or snapshot.phaseEndsAtUnix < snapshot.phaseStartedAtUnix
        or type(snapshot.raidId) ~= "string"
        or #snapshot.raidId < 1
        or #snapshot.raidId > 128
        or not isFiniteNumber(serverTimeUnix)
    then
        return
    end

    state = {
        phase = snapshot.phase,
        phaseStartedAtUnix = snapshot.phaseStartedAtUnix,
        phaseEndsAtUnix = snapshot.phaseEndsAtUnix,
        raidId = snapshot.raidId,
        revision = snapshot.revision,
        serverTimeUnix = serverTimeUnix,
    }
    localSyncTime = os.clock()
end

local function readAttributes(player: Player)
    local phase = player:GetAttribute(PLAYER_ATTRIBUTES.RaidPhase)
    local phaseStartedAtUnix = player:GetAttribute(PLAYER_ATTRIBUTES.RaidPhaseStartedAtUnix)
    local phaseEndsAtUnix = player:GetAttribute(PLAYER_ATTRIBUTES.RaidPhaseEndsAtUnix)
    local raidId = player:GetAttribute(PLAYER_ATTRIBUTES.RaidId)
    local revision = player:GetAttribute(PLAYER_ATTRIBUTES.RaidRevision)
    local serverTimeUnix = player:GetAttribute(PLAYER_ATTRIBUTES.RaidServerTimeUnix)
    local nextState = {
        phase = phase,
        phaseStartedAtUnix = phaseStartedAtUnix,
        phaseEndsAtUnix = phaseEndsAtUnix,
        raidId = raidId,
        revision = revision,
        serverTimeUnix = serverTimeUnix,
    }
    if HudModel.isSameRaidPresentationState(state, nextState) then
        return
    end
    setState(nextState, serverTimeUnix)
end

local function render(player: Player)
    if state == nil or phaseLabel == nil or graceLabel == nil then
        return
    end
    local serverNow = state.serverTimeUnix + math.max(0, os.clock() - localSyncTime)
    local phaseText = string.format(
        "%s  ·  %s",
        state.phase,
        HudModel.formatDuration(state.phaseEndsAtUnix - serverNow)
    )
    if phaseLabel.Text ~= phaseText then
        phaseLabel.Text = phaseText
    end

    local graceRaidId = player:GetAttribute(PLAYER_ATTRIBUTES.ArrivalGraceRaidId)
    local graceEndsAtUnix = player:GetAttribute(PLAYER_ATTRIBUTES.ArrivalGraceEndsAtUnix)
    local graceText = ""
    if
        state.phase == "RAID"
        and graceRaidId == state.raidId
        and isFiniteNumber(graceEndsAtUnix)
        and graceEndsAtUnix > serverNow
    then
        graceText = "ARRIVAL GRACE  " .. HudModel.formatDuration(graceEndsAtUnix - serverNow)
    end
    if graceLabel.Text ~= graceText then
        graceLabel.Text = graceText
    end
end

local function onDomainEvent(event: any)
    if type(event) ~= "table" or event.event ~= Protocol.DomainEventNames.RaidPhaseChanged then
        return
    end
    setState(event.data, event.serverTimeUnix)
end

function controller.start(): boolean
    if started then
        return true
    end
    local player = Players.LocalPlayer
    if player == nil then
        return false
    end
    local networkFolder = ReplicatedStorage:WaitForChild("Network")
    local domainEvent = networkFolder:WaitForChild(Protocol.RemoteNames.DomainEvent)
    if not domainEvent:IsA("RemoteEvent") then
        return false
    end
    local playerGui = player:WaitForChild("PlayerGui")
    if not playerGui:IsA("PlayerGui") then
        return false
    end
    ensureGui(playerGui)

    local attributeNames = {
        PLAYER_ATTRIBUTES.RaidPhase,
        PLAYER_ATTRIBUTES.RaidPhaseStartedAtUnix,
        PLAYER_ATTRIBUTES.RaidPhaseEndsAtUnix,
        PLAYER_ATTRIBUTES.RaidId,
        PLAYER_ATTRIBUTES.RaidRevision,
        PLAYER_ATTRIBUTES.RaidServerTimeUnix,
        PLAYER_ATTRIBUTES.ArrivalGraceRaidId,
        PLAYER_ATTRIBUTES.ArrivalGraceEndsAtUnix,
    }
    for _, attributeName in attributeNames do
        table.insert(
            connections,
            player:GetAttributeChangedSignal(attributeName):Connect(function()
                readAttributes(player)
            end)
        )
    end

    table.insert(connections, domainEvent.OnClientEvent:Connect(onDomainEvent))
    readAttributes(player)
    started = true
    renderLoopGeneration += 1
    local generation = renderLoopGeneration
    task.spawn(function()
        while started and renderLoopGeneration == generation do
            render(player)
            task.wait(RENDER_INTERVAL_SECONDS)
        end
    end)
    return true
end

function controller.getGui(): ScreenGui?
    return screenGui
end

function controller.setEconomyStatus(scrap: any, incomePerMinute: any, occupied: any, capacity: any)
    if scrapLabel == nil or incomeLabel == nil or slotsLabel == nil then
        return
    end
    local function displayNumber(value: any): string
        if
            type(value) ~= "number"
            or value ~= value
            or value == math.huge
            or value == -math.huge
        then
            return "—"
        end
        return if value % 1 == 0 then string.format("%d", value) else string.format("%.1f", value)
    end
    scrapLabel.Text = "SCRAP  " .. displayNumber(scrap)
    incomeLabel.Text = "SCRAP/MIN  " .. displayNumber(incomePerMinute)
    slotsLabel.Text = "SLOTS  " .. displayNumber(occupied) .. "/" .. displayNumber(capacity)
end

function controller.stop()
    started = false
    renderLoopGeneration += 1
    for _, connection in connections do
        connection:Disconnect()
    end
    table.clear(connections)
    if screenGui ~= nil then
        screenGui:Destroy()
        screenGui = nil
    end
    phaseLabel = nil
    graceLabel = nil
    scrapLabel = nil
    incomeLabel = nil
    slotsLabel = nil
    state = nil
end

return table.freeze(controller)
