-- Mobile-first, presentation-only onboarding and contextual action controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared").network.Protocol)
local EconomyConfig = require(ReplicatedStorage.Shared.config.EconomyConfig)
local CapsuleConfig = require(ReplicatedStorage.Shared.config.CapsuleConfig)
local MutationConfig = require(ReplicatedStorage.Shared.config.MutationConfig)
local RaidConfig = require(ReplicatedStorage.Shared.config.RaidConfig)
local MutationDefinitions = require(ReplicatedStorage.Shared.definitions.MutationDefinitions)
local CodexModel = require(script.Parent.CodexModel)
local AudioEffectsController = require(script.Parent.AudioEffectsController)
local CreaturePresentationController = require(script.Parent.CreaturePresentationController)
local HudModel = require(script.Parent.HudModel)
local RaidPresentationController = require(script.Parent.RaidPresentationController)

local controller = {}
local THEMES = { "Ember", "Prism", "Moss" }
local THEME_COLORS = {
    Ember = Color3.fromRGB(208, 105, 66),
    Prism = Color3.fromRGB(143, 104, 190),
    Moss = Color3.fromRGB(91, 150, 98),
}
local RARITY_COLORS = {
    Common = Color3.fromRGB(116, 156, 103),
    Uncommon = Color3.fromRGB(74, 139, 191),
    Rare = Color3.fromRGB(151, 92, 185),
    Mythic = Color3.fromRGB(199, 153, 58),
    Neutral = Color3.fromRGB(72, 91, 112),
}
local THEME_CATALYSTS = {
    Ember = "emberSeed",
    Prism = "prismDust",
    Moss = "mossSpore",
}
local PROFILE_ACTIONS = {
    PurchaseCapsule = true,
    SellCreature = true,
    PurchaseSlot = true,
    PurchaseCatalyst = true,
    CompleteTutorialMutation = true,
    StartMutation = true,
    ResolveMutation = true,
}

local started = false
local connections = {}
local player: Player? = nil
local activeSessionId: string? = nil
local screenGui: ScreenGui? = nil
local requestRemote: RemoteEvent? = nil
local resultRemote: RemoteEvent? = nil
local domainEvent: RemoteEvent? = nil
local rootFrame: Frame? = nil
local introCard: Frame? = nil
local introButtons = {}
local goalCard: Frame? = nil
local goalLabel: TextLabel? = nil
local contextButton: TextButton? = nil
local contextProgress: Frame? = nil
local holdProgressSegments = {}
local holdProgressFilledCount = -1
local menuPanel: Frame? = nil
local menuTitle: TextLabel? = nil
local menuBody: Frame? = nil
local effectsButton: TextButton? = nil
local toastPanel: Frame? = nil
local toastLabel: TextLabel? = nil

local snapshot: any = nil
local menuKind: string? = nil
local menuTab = "Grow"
local selectedTheme = "Ember"
local tutorialTheme: string? = nil
local guidanceSkipped = false
local selectedCreatureId: string? = nil
local pendingMutation: any = nil
local currentContext: any = nil
local localAttemptId: string? = nil
local localAttemptState: string? = nil
local droppedAttempt: any = nil
local dropMarker: Part? = nil
local actionPending = {}
local actionBusy = {}
local snapshotRequestPending = false
local lastSnapshotRequestAt = -math.huge
local snapshotRefreshScheduled = false
local channelStartedAt = {}
local bankStartedAt = {}
local recoveryStartedAt = {}
local leaderstatsScrap: IntValue? = nil
local leaderstatsIncome: NumberValue? = nil
local contextHold: any = nil
local toastRevision = 0
local scanAccumulator = 0
local blockout: Instance? = nil
local commonsKiosk: BasePart? = nil
local mutationStation: BasePart? = nil
local stands = {}

local renderHud: (() -> ())? = nil
local renderMenu: (() -> ())? = nil
local renderContext: (() -> ())? = nil
local openMenu: ((string) -> ())? = nil
local closeMenu: (() -> ())? = nil
local performContext: (() -> ())? = nil
local beginContextHold: ((InputObject?) -> ())? = nil
local endContextHold: (() -> ())? = nil
local sendAction: ((string, any, ((any, any) -> ())?) -> boolean)? = nil
local requestSnapshot: (() -> ())? = nil
local scheduleSnapshotRefresh: () -> () = function() end
local announce: ((string, number?) -> ())? = nil

local function addConnection(connection: any)
    table.insert(connections, connection)
end

local function colorForTheme(themeId: string): Color3
    return THEME_COLORS[themeId] or RARITY_COLORS.Neutral
end

local function makeCorner(parent: Instance, radius: number)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function makeStroke(parent: Instance, color: Color3, transparency: number?)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Transparency = transparency or 0.25
    stroke.Thickness = 1
    stroke.Parent = parent
end

local function makeLabel(
    parent: Instance,
    name: string,
    text: string,
    position: UDim2,
    size: UDim2,
    textSize: number,
    align: Enum.TextXAlignment?
): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Position = position
    label.Size = size
    label.Font = Enum.Font.GothamMedium
    label.Text = text
    label.TextColor3 = Color3.fromRGB(247, 249, 255)
    label.TextSize = textSize
    label.TextWrapped = true
    label.TextXAlignment = align or Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Selectable = false
    label.ZIndex = 32
    label.Parent = parent
    return label
end

local function setHoldProgress(progress: number)
    if contextProgress == nil then
        return
    end
    local filledCount = math.floor(math.clamp(progress, 0, 1) * #holdProgressSegments + 0.001)
    if filledCount == holdProgressFilledCount then
        return
    end
    holdProgressFilledCount = filledCount
    for index, segment in holdProgressSegments do
        segment.BackgroundTransparency = if index <= filledCount then 0 else 0.68
    end
end

local function makePanel(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = position
    frame.Size = size
    frame.BackgroundColor3 = Color3.fromRGB(24, 31, 44)
    frame.BackgroundTransparency = 0.04
    frame.BorderSizePixel = 0
    frame.ZIndex = 30
    frame.Parent = parent
    makeCorner(frame, 14)
    makeStroke(frame, Color3.fromRGB(112, 143, 181), 0.28)
    local constraint = Instance.new("UISizeConstraint")
    constraint.MaxSize = Vector2.new(440, 360)
    constraint.Parent = frame
    return frame
end

local function makeButton(
    parent: Instance,
    name: string,
    text: string,
    position: UDim2,
    size: UDim2,
    color: Color3,
    onActivated: (() -> ())?,
    enabled: boolean?
): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.Position = position
    button.Size = size
    button.BackgroundColor3 = color
    button.BackgroundTransparency = if enabled == false then 0.48 else 0.06
    button.BorderSizePixel = 0
    button.AutoButtonColor = enabled ~= false
    button.Active = enabled ~= false
    button.Selectable = enabled ~= false
    button.Font = Enum.Font.GothamBold
    button.Text = text
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 15
    button.TextWrapped = true
    button.ZIndex = 33
    button.Parent = parent
    makeCorner(button, 12)
    makeStroke(button, Color3.fromRGB(234, 241, 255), 0.62)
    if onActivated ~= nil then
        button.Activated:Connect(onActivated)
    end
    return button
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
    button.Active = enabled
    button.Selectable = enabled
    button.AutoButtonColor = enabled
    button.BackgroundTransparency = if enabled then 0.06 else 0.48
end

local function getServerNow(): number
    return Workspace:GetServerTimeNow()
end

local function getCharacterRoot(targetPlayer: Player?): BasePart?
    if targetPlayer == nil or targetPlayer.Character == nil then
        return nil
    end
    local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function distance(left: Vector3?, right: Vector3?): number?
    if left == nil or right == nil then
        return nil
    end
    return (left - right).Magnitude
end

local function countCreatures(): number
    return if type(snapshot) == "table" and type(snapshot.creatures) == "table"
        then #snapshot.creatures
        else 0
end

local function getCreature(creatureId: string?): any?
    if creatureId == nil or type(snapshot) ~= "table" or type(snapshot.creatures) ~= "table" then
        return nil
    end
    for _, creature in snapshot.creatures do
        if creature.id == creatureId then
            return creature
        end
    end
    return nil
end

local function getStarterCreatureId(): string?
    if player == nil or blockout == nil then
        return nil
    end
    local baseId = player:GetAttribute("OddlingsBaseId")
    if type(baseId) ~= "string" then
        return nil
    end
    local base = blockout:FindFirstChild(baseId)
    local starterStand = if base ~= nil then base:FindFirstChild("Stand01") else nil
    local creatureId = if starterStand ~= nil then starterStand:GetAttribute("CreatureId") else nil
    return if type(creatureId) == "string" then creatureId else nil
end

local function getSelectedCreature(): any?
    local creature = getCreature(selectedCreatureId)
    if creature ~= nil then
        return creature
    end
    if type(snapshot) == "table" and type(snapshot.creatures) == "table" then
        local first = snapshot.creatures[1]
        if first ~= nil then
            selectedCreatureId = first.id
            return first
        end
    end
    return nil
end

local function getSellableCreatures(): { any }
    local candidates = {}
    local starterId = getStarterCreatureId()
    if type(snapshot) == "table" and type(snapshot.creatures) == "table" then
        for _, creature in snapshot.creatures do
            if creature.id ~= starterId then
                table.insert(candidates, creature)
            end
        end
    end
    return candidates
end

local function changeSelectedCreature(delta: number, sellOnly: boolean)
    local creatures = if sellOnly
        then getSellableCreatures()
        else snapshot and snapshot.creatures or {}
    if #creatures == 0 then
        selectedCreatureId = nil
        if renderMenu ~= nil then
            renderMenu()
        end
        return
    end
    local currentIndex = 0
    for index, creature in creatures do
        if creature.id == selectedCreatureId then
            currentIndex = index
            break
        end
    end
    local nextIndex = ((currentIndex - 1 + delta) % #creatures) + 1
    selectedCreatureId = creatures[nextIndex].id
    if renderMenu ~= nil then
        renderMenu()
    end
end

local function setScrapInSnapshot(value: any)
    if type(snapshot) == "table" and type(value) == "number" then
        snapshot.scrap = value
    end
end

local function canAfford(price: number): boolean
    local scrap = if leaderstatsScrap ~= nil
        then leaderstatsScrap.Value
        else snapshot and snapshot.scrap
    return type(scrap) == "number" and scrap >= price
end

local function updateStatusLabels()
    local scrap = if leaderstatsScrap ~= nil
        then leaderstatsScrap.Value
        else snapshot and snapshot.scrap
    local income = if leaderstatsIncome ~= nil
        then leaderstatsIncome.Value
        else HudModel.getIncomePerMinute(snapshot and snapshot.creatures)
    RaidPresentationController.setEconomyStatus(
        scrap,
        income,
        countCreatures(),
        snapshot and snapshot.slotCapacity
    )
end

local function refreshOpenMenu()
    if menuKind ~= nil and renderMenu ~= nil then
        renderMenu()
    end
end

local function removeDropMarker()
    if dropMarker ~= nil then
        dropMarker:Destroy()
        dropMarker = nil
    end
end

local function createDropMarker(position: any)
    removeDropMarker()
    if
        type(position) ~= "table"
        or type(position.x) ~= "number"
        or type(position.y) ~= "number"
        or type(position.z) ~= "number"
        or position.x ~= position.x
        or position.y ~= position.y
        or position.z ~= position.z
        or math.abs(position.x) == math.huge
        or math.abs(position.y) == math.huge
        or math.abs(position.z) == math.huge
    then
        return
    end
    local marker = Instance.new("Part")
    marker.Name = "LocalOddlingRecoveryMarker"
    marker.Anchored = true
    marker.CanCollide = false
    marker.CanTouch = false
    marker.CanQuery = false
    marker.Transparency = 1
    marker.Size = Vector3.new(1, 1, 1)
    marker.Position = Vector3.new(position.x, position.y + 2, position.z)
    marker.Parent = Workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "RecoveryCaption"
    billboard.Adornee = marker
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 180
    billboard.Size = UDim2.fromOffset(190, 58)
    billboard.Parent = marker

    local caption = Instance.new("TextLabel")
    caption.Name = "Caption"
    caption.Size = UDim2.fromScale(1, 1)
    caption.BackgroundColor3 = Color3.fromRGB(31, 50, 52)
    caption.BackgroundTransparency = 0.08
    caption.BorderSizePixel = 0
    caption.Font = Enum.Font.GothamBold
    caption.Text = "DROPPED ODDLING\nRECOVER HERE"
    caption.TextColor3 = Color3.fromRGB(255, 255, 255)
    caption.TextSize = 15
    caption.TextWrapped = true
    caption.Parent = billboard
    makeCorner(caption, 10)
    makeStroke(caption, Color3.fromRGB(146, 219, 169), 0.15)
    dropMarker = marker
end

local function positionToast()
    if toastPanel == nil then
        return
    end
    toastPanel.Position =
        UDim2.new(0.5, 0, 0, HudModel.getToastOffsetY(introCard ~= nil and introCard.Visible))
end

announce = function(message: string, duration: number?)
    if toastPanel == nil or toastLabel == nil then
        return
    end
    toastRevision += 1
    local revision = toastRevision
    positionToast()
    toastLabel.Text = message
    toastLabel.TextColor3 = Color3.fromRGB(247, 249, 255)
    toastPanel.Visible = true
    task.delay(duration or 3, function()
        if started and revision == toastRevision and toastPanel ~= nil then
            toastPanel.Visible = false
        end
    end)
end

local function announceRarity(rarityName: string, message: string, duration: number?)
    if announce ~= nil then
        announce(message, duration)
    end
    if toastLabel ~= nil then
        toastLabel.TextColor3 = RARITY_COLORS[rarityName] or RARITY_COLORS.Neutral
    end
end

local function buildUi(parentGui: ScreenGui)
    local root = Instance.new("Frame")
    root.Name = "OddlingsOnboardingUI"
    root.BackgroundTransparency = 1
    root.BorderSizePixel = 0
    root.Size = UDim2.fromScale(1, 1)
    root.ZIndex = 30
    root.Parent = parentGui
    rootFrame = root

    introCard =
        makePanel(root, "FirstSessionChoice", UDim2.new(0.5, 0, 0, 124), UDim2.new(1, -24, 0, 176))
    introCard.Visible = false
    makeLabel(
        introCard,
        "LoopExplanation",
        "Mutate your oddling, add more, and when the siren hits, steal one and bring it home.",
        UDim2.fromOffset(12, 6),
        UDim2.new(1, -24, 0, 40),
        14
    )
    local themeRow = Instance.new("Frame")
    themeRow.Name = "ThemeChoices"
    themeRow.BackgroundTransparency = 1
    themeRow.Position = UDim2.fromOffset(8, 50)
    themeRow.Size = UDim2.new(1, -16, 0, HudModel.MIN_TOUCH_TARGET_PX)
    themeRow.ZIndex = 32
    themeRow.Parent = introCard
    for index, themeId in THEMES do
        local button = makeButton(
            themeRow,
            "Choose" .. themeId,
            themeId .. "\nFREE",
            UDim2.new((index - 1) / 3, 3, 0, 0),
            UDim2.new(1 / 3, -6, 1, 0),
            colorForTheme(themeId),
            function()
                selectedTheme = themeId
                tutorialTheme = themeId
                guidanceSkipped = false
                if announce ~= nil then
                    announce(
                        themeId
                            .. " chosen · visit the glowing station for your free Common mutation.",
                        4
                    )
                end
                if renderHud ~= nil then
                    renderHud()
                end
            end
        )
        introButtons[themeId] = button
    end
    makeButton(
        introCard,
        "SkipGuidance",
        "SKIP GUIDE · FREE MUTATION STAYS AVAILABLE",
        UDim2.fromOffset(12, 112),
        UDim2.new(1, -24, 0, HudModel.MIN_TOUCH_TARGET_PX),
        RARITY_COLORS.Neutral,
        function()
            guidanceSkipped = true
            tutorialTheme = nil
            if renderHud ~= nil then
                renderHud()
            end
            if announce ~= nil then
                announce(
                    "Guidance hidden · the free Common mutation remains at the glowing station.",
                    4
                )
            end
        end
    )

    goalCard = makePanel(root, "NextGoal", UDim2.new(0.5, 0, 0, 124), UDim2.new(1, -24, 0, 58))
    goalCard.Visible = false
    goalLabel = makeLabel(
        goalCard,
        "GoalText",
        "Connecting to your oddlings...",
        UDim2.fromOffset(12, 4),
        UDim2.new(1, -24, 1, -8),
        15
    )

    toastPanel =
        makePanel(root, "VisualCaption", UDim2.new(0.5, 0, 0, 190), UDim2.new(1, -24, 0, 50))
    toastPanel.Visible = false
    toastLabel = makeLabel(
        toastPanel,
        "CaptionText",
        "",
        UDim2.fromOffset(10, 2),
        UDim2.new(1, -20, 1, -4),
        15
    )

    contextButton = makeButton(
        root,
        "ContextAction",
        "",
        UDim2.new(0.5, 0, 1, -176),
        UDim2.new(1, -24, 0, 64),
        Color3.fromRGB(65, 116, 150),
        function()
            if performContext ~= nil then
                performContext()
            end
        end
    )
    contextButton.AnchorPoint = Vector2.new(0.5, 1)
    contextButton.Visible = false
    local contextConstraint = Instance.new("UISizeConstraint")
    contextConstraint.MaxSize = Vector2.new(360, 64)
    contextConstraint.Parent = contextButton
    contextButton.TextXAlignment = Enum.TextXAlignment.Left
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 44)
    padding.Parent = contextButton
    contextProgress = Instance.new("Frame")
    contextProgress.Name = "Progress"
    contextProgress.AnchorPoint = Vector2.new(1, 0.5)
    contextProgress.Position = UDim2.new(1, -10, 0.5, 0)
    contextProgress.Size = UDim2.fromOffset(34, 34)
    contextProgress.BackgroundTransparency = 1
    contextProgress.BorderSizePixel = 0
    contextProgress.Active = false
    contextProgress.ZIndex = 35
    contextProgress.Parent = contextButton
    table.clear(holdProgressSegments)
    holdProgressFilledCount = -1
    for index = 1, 12 do
        local angle = -math.pi / 2 + (index - 1) * math.pi / 6
        local segment = Instance.new("Frame")
        segment.Name = "Segment"
        segment.AnchorPoint = Vector2.new(0.5, 0.5)
        segment.Position = UDim2.new(0.5, math.cos(angle) * 10, 0.5, math.sin(angle) * 10)
        segment.Size = UDim2.fromOffset(4, 9)
        segment.Rotation = math.deg(angle) + 90
        segment.BackgroundColor3 = Color3.fromRGB(255, 216, 109)
        segment.BackgroundTransparency = 0.68
        segment.BorderSizePixel = 0
        segment.Active = false
        segment.ZIndex = 36
        segment.Parent = contextProgress
        makeCorner(segment, 3)
        table.insert(holdProgressSegments, segment)
    end
    contextButton.InputBegan:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            if beginContextHold ~= nil then
                beginContextHold(input)
            end
        end
    end)
    contextButton.InputEnded:Connect(function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            if endContextHold ~= nil then
                endContextHold()
            end
        end
    end)

    menuPanel =
        makePanel(root, "InteractionPanel", UDim2.new(0.5, 0, 1, -168), UDim2.new(1, -24, 0, 332))
    menuPanel.AnchorPoint = Vector2.new(0.5, 1)
    menuPanel.Visible = false
    menuTitle = makeLabel(
        menuPanel,
        "PanelTitle",
        "",
        UDim2.fromOffset(12, 5),
        UDim2.new(1, -144, 0, 48),
        16,
        Enum.TextXAlignment.Left
    )
    effectsButton = makeButton(
        menuPanel,
        "ReducedEffects",
        if AudioEffectsController.isReducedEffectsEnabled() then "FX\nLOW" else "FX\nFULL",
        UDim2.new(1, -122, 0, 4),
        UDim2.fromOffset(56, HudModel.MIN_TOUCH_TARGET_PX),
        Color3.fromRGB(74, 103, 111),
        function()
            local enabled = not AudioEffectsController.isReducedEffectsEnabled()
            AudioEffectsController.setReducedEffects(enabled)
            CreaturePresentationController.setReducedEffects(enabled)
            if effectsButton ~= nil then
                effectsButton.Text = if enabled then "FX\nLOW" else "FX\nFULL"
                effectsButton.BackgroundColor3 = if enabled
                    then Color3.fromRGB(74, 103, 111)
                    else Color3.fromRGB(83, 91, 106)
            end
            if announce ~= nil then
                announce(
                    if enabled
                        then "Reduced visual effects enabled."
                        else "Full visual effects enabled.",
                    3
                )
            end
        end
    )
    effectsButton.TextSize = 11
    local closeButton = makeButton(
        menuPanel,
        "ClosePanel",
        "CLOSE",
        UDim2.new(1, -62, 0, 4),
        UDim2.fromOffset(56, HudModel.MIN_TOUCH_TARGET_PX),
        Color3.fromRGB(76, 88, 106),
        function()
            if closeMenu ~= nil then
                closeMenu()
            end
        end
    )
    closeButton.TextSize = 12

    menuBody = Instance.new("Frame")
    menuBody.Name = "PanelContent"
    menuBody.BackgroundTransparency = 1
    menuBody.Position = UDim2.fromOffset(12, 58)
    menuBody.Size = UDim2.new(1, -24, 1, -68)
    menuBody.ZIndex = 32
    menuBody.Parent = menuPanel
end

local function bodyButton(
    name: string,
    text: string,
    xScale: number,
    xOffset: number,
    y: number,
    widthScale: number,
    widthOffset: number,
    color: Color3,
    enabled: boolean,
    callback: (() -> ())?
): TextButton
    return makeButton(
        menuBody :: Frame,
        name,
        text,
        UDim2.new(xScale, xOffset, 0, y),
        UDim2.new(widthScale, widthOffset, 0, HudModel.MIN_TOUCH_TARGET_PX),
        color,
        callback,
        enabled
    )
end

local function bodyLabel(
    name: string,
    text: string,
    y: number,
    height: number,
    textSize: number
): TextLabel
    return makeLabel(
        menuBody :: Frame,
        name,
        text,
        UDim2.fromOffset(2, y),
        UDim2.new(1, -4, 0, height),
        textSize
    )
end

local function themeCount(themeId: string): number
    local catalystId = THEME_CATALYSTS[themeId]
    local catalysts = if type(snapshot) == "table" then snapshot.catalysts else nil
    local count = if type(catalysts) == "table" then catalysts[catalystId] else 0
    return if type(count) == "number" then count else 0
end

local function selectedCreatureText(creature: any): (string, string)
    local label, rarity = HudModel.getCreatureLabel(creature)
    local presentation = HudModel.getRarityPresentation(rarity)
    return presentation.icon .. " " .. presentation.label .. "\n" .. label, rarity
end

local function getPendingOffer(): any?
    if pendingMutation ~= nil then
        return pendingMutation
    end
    return if type(snapshot) == "table" then snapshot.pendingMutation else nil
end

renderMenu = function()
    if menuPanel == nil or menuTitle == nil or menuBody == nil or menuKind == nil then
        return
    end
    for _, child in menuBody:GetChildren() do
        child:Destroy()
    end

    if menuKind == "Commons" then
        menuTitle.Text = "COMMONS"
        local tabs = { "Grow", "Sell", "Catalyst", "Codex" }
        for index, tab in tabs do
            local button = bodyButton(
                "Tab" .. tab,
                string.upper(tab),
                (index - 1) / #tabs,
                3,
                0,
                1 / #tabs,
                -6,
                if menuTab == tab then Color3.fromRGB(63, 115, 143) else Color3.fromRGB(58, 68, 84),
                true,
                function()
                    menuTab = tab
                    if renderMenu ~= nil then
                        renderMenu()
                    end
                end
            )
            button.TextSize = 13
        end

        if menuTab == "Grow" then
            local hasRoom = countCreatures() < (snapshot and snapshot.slotCapacity or 0)
            bodyButton(
                "WelcomeCapsule",
                if snapshot ~= nil and snapshot.welcomeAvailable == true
                    then "WELCOME\n" .. HudModel.formatNumber(CapsuleConfig.PRICE) .. " SCRAP"
                    else "WELCOME\nALREADY CLAIMED",
                0,
                3,
                62,
                0.5,
                -6,
                Color3.fromRGB(176, 123, 77),
                hasRoom
                    and snapshot ~= nil
                    and snapshot.welcomeAvailable == true
                    and canAfford(CapsuleConfig.PRICE),
                function()
                    sendAction("PurchaseCapsule", { kind = "Welcome" }, function(data)
                        if snapshot ~= nil then
                            snapshot.welcomeAvailable = false
                        end
                        setScrapInSnapshot(data.scrapBalance)
                        if type(data.creature) == "table" then
                            local exists = getCreature(data.creature.id) ~= nil
                            if not exists then
                                table.insert(snapshot.creatures, data.creature)
                            end
                            local label, rarity = HudModel.getCreatureLabel(data.creature)
                            local shown = HudModel.getRarityPresentation(data.rarity or rarity)
                            announceRarity(
                                shown.label,
                                shown.icon .. " " .. shown.label .. " revealed: " .. label .. ".",
                                4
                            )
                        end
                        if renderHud ~= nil then
                            renderHud()
                        end
                        if renderMenu ~= nil then
                            renderMenu()
                        end
                    end)
                end
            )
            bodyButton(
                "StandardCapsule",
                "STANDARD\n" .. HudModel.formatNumber(CapsuleConfig.PRICE) .. " SCRAP",
                0.5,
                3,
                62,
                0.5,
                -6,
                Color3.fromRGB(75, 118, 153),
                hasRoom and snapshot ~= nil and canAfford(CapsuleConfig.PRICE),
                function()
                    sendAction("PurchaseCapsule", { kind = "Standard" }, function(data)
                        setScrapInSnapshot(data.scrapBalance)
                        if type(data.creature) == "table" then
                            if getCreature(data.creature.id) == nil then
                                table.insert(snapshot.creatures, data.creature)
                            end
                            local label, rarity = HudModel.getCreatureLabel(data.creature)
                            local shown = HudModel.getRarityPresentation(data.rarity or rarity)
                            announceRarity(
                                shown.label,
                                shown.icon .. " " .. shown.label .. " revealed: " .. label .. ".",
                                4
                            )
                        end
                        if renderHud ~= nil then
                            renderHud()
                        end
                        if renderMenu ~= nil then
                            renderMenu()
                        end
                    end)
                end
            )
            local capacity = if snapshot ~= nil then snapshot.slotCapacity else 0
            local targetCapacity = capacity + 1
            local slotEnabled = false
            local slotText = "All stands unlocked"
            if capacity == EconomyConfig.STARTER_SLOT_CAPACITY then
                slotText = string.format(
                    "SLOT 3\n%s SCRAP",
                    HudModel.formatNumber(EconomyConfig.SLOT_3_PRICE)
                )
                slotEnabled = countCreatures() >= EconomyConfig.STARTER_SLOT_CAPACITY
            elseif capacity == 3 and snapshot ~= nil and snapshot.hasCompletedFirstRaid == true then
                targetCapacity = 4
                slotText = string.format(
                    "SLOT 4\n%s SCRAP",
                    HudModel.formatNumber(EconomyConfig.SLOT_4_PRICE)
                )
                slotEnabled = true
            elseif capacity == 3 then
                slotText = "SLOT 4\nUNLOCKS AFTER RAID"
            end
            local slotPrice = if targetCapacity == 3
                then EconomyConfig.SLOT_3_PRICE
                elseif targetCapacity == 4 then EconomyConfig.SLOT_4_PRICE
                else math.huge
            slotEnabled = slotEnabled and canAfford(slotPrice)
            bodyButton(
                "PurchaseNextSlot",
                slotText,
                0,
                3,
                122,
                1,
                -6,
                Color3.fromRGB(94, 112, 77),
                slotEnabled,
                function()
                    sendAction("PurchaseSlot", { targetCapacity = targetCapacity }, function(data)
                        if snapshot ~= nil then
                            snapshot.slotCapacity = data.slotCapacity
                        end
                        setScrapInSnapshot(data.scrapBalance)
                        announce("Slot " .. tostring(data.slotCapacity) .. " unlocked.")
                        if renderHud ~= nil then
                            renderHud()
                        end
                        if renderMenu ~= nil then
                            renderMenu()
                        end
                    end)
                end
            )
        elseif menuTab == "Sell" then
            local sellable = getSellableCreatures()
            local selected = nil
            for _, creature in sellable do
                if creature.id == selectedCreatureId then
                    selected = creature
                    break
                end
            end
            if selected == nil and sellable[1] ~= nil then
                selected = sellable[1]
                selectedCreatureId = selected.id
            end
            bodyButton(
                "PreviousSaleCreature",
                "◀",
                0,
                3,
                62,
                0,
                56,
                Color3.fromRGB(67, 81, 102),
                #sellable > 1,
                function()
                    changeSelectedCreature(-1, true)
                end
            )
            local creatureText, creatureRarity
            if selected ~= nil then
                creatureText, creatureRarity = selectedCreatureText(selected)
            else
                creatureText, creatureRarity =
                    "No creature can be sold\nMossling is protected", "Common"
            end
            local saleSelection = bodyLabel("SaleSelection", creatureText, 62, 56, 14)
            saleSelection.Position = UDim2.fromOffset(62, 62)
            saleSelection.Size = UDim2.new(1, -124, 0, 56)
            saleSelection.TextColor3 = RARITY_COLORS[creatureRarity] or RARITY_COLORS.Neutral
            bodyButton(
                "NextSaleCreature",
                "▶",
                1,
                -59,
                62,
                0,
                56,
                Color3.fromRGB(67, 81, 102),
                #sellable > 1,
                function()
                    changeSelectedCreature(1, true)
                end
            )
            bodyButton(
                "SellSelected",
                string.format(
                    "SELL SELECTED · +%s SCRAP",
                    HudModel.formatNumber(EconomyConfig.CREATURE_SALE_VALUE)
                ),
                0,
                3,
                122,
                1,
                -6,
                Color3.fromRGB(134, 82, 71),
                selected ~= nil,
                function()
                    if selected ~= nil then
                        sendAction("SellCreature", { creatureId = selected.id }, function(data)
                            if type(snapshot) == "table" then
                                for index, creature in snapshot.creatures do
                                    if creature.id == data.creatureId then
                                        table.remove(snapshot.creatures, index)
                                        break
                                    end
                                end
                            end
                            setScrapInSnapshot(data.scrapBalance)
                            selectedCreatureId = nil
                            announce(
                                "Creature sold · " .. tostring(data.refund) .. " Scrap added."
                            )
                            if renderHud ~= nil then
                                renderHud()
                            end
                            if renderMenu ~= nil then
                                renderMenu()
                            end
                        end)
                    end
                end
            )
        elseif menuTab == "Codex" then
            menuTitle.Text = "CODEX"
            local codex = if snapshot ~= nil then snapshot.codex else nil
            bodyLabel("CodexSummary", CodexModel.getSummary(codex), 60, 28, 12)
            local entries = CodexModel.getEntries(codex)
            local scroll = Instance.new("ScrollingFrame")
            scroll.Name = "CodexEntries"
            scroll.Position = UDim2.fromOffset(2, 92)
            scroll.Size = UDim2.new(1, -4, 1, -94)
            scroll.BackgroundTransparency = 1
            scroll.BorderSizePixel = 0
            scroll.ScrollBarThickness = 6
            scroll.ScrollingDirection = Enum.ScrollingDirection.Y
            scroll.CanvasSize = UDim2.fromOffset(0, #entries * 44)
            scroll.ZIndex = 32
            scroll.Parent = menuBody
            for index, entry in entries do
                local rarity = HudModel.getRarityPresentation(entry.rarity)
                local row = Instance.new("TextLabel")
                row.Name = "CodexEntry_" .. entry.kind .. "_" .. entry.id
                row.Position = UDim2.fromOffset(0, (index - 1) * 44)
                row.Size = UDim2.new(1, -8, 0, 40)
                row.BackgroundColor3 = if entry.discovered
                    then Color3.fromRGB(42, 55, 62)
                    else Color3.fromRGB(31, 40, 47)
                row.BackgroundTransparency = 0.05
                row.BorderSizePixel = 0
                row.Font = Enum.Font.GothamMedium
                row.Text = string.format(
                    "%s %s · %s · %s",
                    rarity.icon,
                    rarity.label,
                    if entry.kind == "Species"
                        then "SPECIES"
                        else string.upper(entry.themeId) .. " FORM",
                    entry.label
                )
                row.TextColor3 = if entry.discovered
                    then RARITY_COLORS[entry.rarity] or RARITY_COLORS.Neutral
                    else Color3.fromRGB(147, 157, 166)
                row.TextSize = 12
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.TextTruncate = Enum.TextTruncate.AtEnd
                row.ZIndex = 33
                row.Parent = scroll
                makeCorner(row, 8)
            end
        else
            bodyLabel(
                "CatalystHint",
                "Choose a theme to buy one matching catalyst · "
                    .. HudModel.formatNumber(MutationConfig.CATALYST_PRICE)
                    .. " Scrap",
                62,
                48,
                14
            )
            for index, themeId in THEMES do
                local catalystCount = themeCount(themeId)
                local button = bodyButton(
                    "Buy" .. themeId .. "Catalyst",
                    string.format("%s\nx%d", string.upper(themeId), catalystCount),
                    (index - 1) / 3,
                    3,
                    114,
                    1 / 3,
                    -7,
                    colorForTheme(themeId),
                    snapshot ~= nil and canAfford(MutationConfig.CATALYST_PRICE),
                    function()
                        selectedTheme = themeId
                        sendAction("PurchaseCatalyst", { themeId = themeId }, function(data)
                            if snapshot ~= nil then
                                snapshot.catalysts[THEME_CATALYSTS[themeId]] = data.count
                            end
                            setScrapInSnapshot(data.scrapBalance)
                            announce(themeId .. " catalyst ready.")
                            if renderHud ~= nil then
                                renderHud()
                            end
                            if renderMenu ~= nil then
                                renderMenu()
                            end
                        end)
                    end
                )
                button.TextSize = 14
            end
        end
    else
        local offer = getPendingOffer()
        menuTitle.Text = if snapshot ~= nil and snapshot.tutorialCompleted ~= true
            then "YOUR FIRST MUTATION"
            else "MUTATION STATION"
        if offer ~= nil then
            local form = MutationDefinitions[offer.revealedFormId]
            local tier = offer.tier or (form and form.tier) or "Common"
            local rarity = HudModel.getRarityPresentation(tier)
            local formName = if form ~= nil
                then form.displayName
                else tostring(offer.revealedFormId)
            local revealLabel = bodyLabel(
                "MutationReveal",
                rarity.icon .. " " .. rarity.label .. " REVEAL\n" .. formName,
                0,
                58,
                16
            )
            revealLabel.TextColor3 = RARITY_COLORS[tier] or RARITY_COLORS.Neutral
            local choices = {
                { "KeepCurrent", "KEEP", Color3.fromRGB(72, 119, 92) },
                { "Replace", "REPLACE", colorForTheme(offer.themeId or selectedTheme) },
                { "Decline", "DECLINE", Color3.fromRGB(77, 88, 104) },
            }
            for index, choice in choices do
                local button = bodyButton(
                    "Resolve" .. choice[1],
                    choice[2],
                    (index - 1) / 3,
                    3,
                    62,
                    1 / 3,
                    -7,
                    choice[3],
                    true,
                    function()
                        local activeOffer = getPendingOffer()
                        if activeOffer == nil then
                            return
                        end
                        sendAction(
                            "ResolveMutation",
                            { transactionId = activeOffer.transactionId, choice = choice[1] },
                            function(data)
                                if data.outcome == "Replaced" and activeOffer.creatureId ~= nil then
                                    local creature = getCreature(activeOffer.creatureId)
                                    if creature ~= nil then
                                        creature.mutationFormId = data.activeFormId
                                    end
                                end
                                pendingMutation = nil
                                if snapshot ~= nil then
                                    snapshot.pendingMutation = nil
                                end
                                announce("Mutation " .. string.lower(data.outcome) .. ".")
                                if renderHud ~= nil then
                                    renderHud()
                                end
                                if renderMenu ~= nil then
                                    renderMenu()
                                end
                            end
                        )
                    end
                )
                button.TextSize = 13
            end
            local oddsText =
                HudModel.formatOdds(offer.oddsSnapshot or (snapshot and snapshot.mutationOdds))
            bodyLabel("RevealOdds", oddsText, 122, 54, 12)
        elseif snapshot ~= nil and snapshot.tutorialCompleted ~= true then
            bodyLabel(
                "TutorialHint",
                "Choose one theme. The free result is always Common.",
                0,
                52,
                14
            )
            for index, themeId in THEMES do
                local button = bodyButton(
                    "Tutorial" .. themeId,
                    string.upper(themeId) .. "\nFREE",
                    (index - 1) / 3,
                    3,
                    54,
                    1 / 3,
                    -7,
                    colorForTheme(themeId),
                    true,
                    function()
                        selectedTheme = themeId
                        tutorialTheme = themeId
                        guidanceSkipped = false
                        if renderMenu ~= nil then
                            renderMenu()
                        end
                    end
                )
                button.TextSize = 14
            end
            bodyButton(
                "ApplyTutorialMutation",
                "APPLY FREE COMMON MUTATION",
                0,
                3,
                114,
                1,
                -6,
                colorForTheme(tutorialTheme or selectedTheme),
                tutorialTheme ~= nil or selectedTheme ~= nil,
                function()
                    if tutorialTheme ~= nil or selectedTheme ~= nil then
                        selectedTheme = tutorialTheme or selectedTheme
                        local starterId = getStarterCreatureId()
                        if starterId == nil then
                            if announce ~= nil then
                                announce("Your starter stand is still loading.")
                            end
                            return
                        end
                        sendAction(
                            "CompleteTutorialMutation",
                            { creatureId = starterId, themeId = selectedTheme },
                            function(data)
                                tutorialTheme = nil
                                guidanceSkipped = false
                                if snapshot ~= nil then
                                    snapshot.tutorialCompleted = true
                                    for _, creature in snapshot.creatures do
                                        if creature.id == data.creatureId then
                                            creature.mutationFormId = data.formId
                                        end
                                    end
                                end
                                menuKind = nil
                                if menuPanel ~= nil then
                                    menuPanel.Visible = false
                                end
                                local form = MutationDefinitions[data.formId]
                                local rarity = HudModel.getRarityPresentation("Common")
                                announceRarity(
                                    rarity.label,
                                    "Free mutation · "
                                        .. rarity.icon
                                        .. " "
                                        .. rarity.label
                                        .. " · "
                                        .. (form and form.displayName or tostring(data.formId))
                                        .. ".",
                                    4
                                )
                                if renderHud ~= nil then
                                    renderHud()
                                end
                                scheduleSnapshotRefresh()
                            end
                        )
                    end
                end
            )
        else
            local selected = getSelectedCreature()
            local creatureLabel, selectedRarity = selectedCreatureText(selected)
            bodyButton(
                "PreviousCreature",
                "◀",
                0,
                3,
                0,
                0,
                56,
                Color3.fromRGB(67, 81, 102),
                snapshot ~= nil and countCreatures() > 1,
                function()
                    changeSelectedCreature(-1, false)
                end
            )
            local selectionLabel = bodyLabel("SelectedCreature", creatureLabel, 0, 56, 13)
            selectionLabel.TextColor3 = RARITY_COLORS[selectedRarity] or RARITY_COLORS.Neutral
            selectionLabel.Position = UDim2.fromOffset(62, 0)
            selectionLabel.Size = UDim2.new(1, -124, 0, 56)
            bodyButton(
                "NextCreature",
                "▶",
                1,
                -59,
                0,
                0,
                56,
                Color3.fromRGB(67, 81, 102),
                snapshot ~= nil and countCreatures() > 1,
                function()
                    changeSelectedCreature(1, false)
                end
            )
            for index, themeId in THEMES do
                local count = themeCount(themeId)
                local button = bodyButton(
                    "MutationTheme" .. themeId,
                    string.upper(themeId) .. "\nx" .. tostring(count),
                    (index - 1) / 3,
                    3,
                    58,
                    1 / 3,
                    -7,
                    colorForTheme(themeId),
                    true,
                    function()
                        selectedTheme = themeId
                        if renderMenu ~= nil then
                            renderMenu()
                        end
                    end
                )
                button.TextSize = 13
            end
            bodyLabel(
                "MutationOdds",
                HudModel.formatOdds(snapshot and snapshot.mutationOdds),
                116,
                40,
                12
            )
            bodyButton(
                "StartMutation",
                string.format(
                    "ROLL · %s SCRAP + 1 %s CATALYST",
                    HudModel.formatNumber(MutationConfig.NORMAL_PRICE),
                    string.upper(selectedTheme)
                ),
                0,
                3,
                160,
                1,
                -6,
                colorForTheme(selectedTheme),
                selected ~= nil
                    and snapshot ~= nil
                    and themeCount(selectedTheme) > 0
                    and canAfford(MutationConfig.NORMAL_PRICE),
                function()
                    if selected ~= nil then
                        AudioEffectsController.playCue("MutationStart")
                        sendAction(
                            "StartMutation",
                            { creatureId = selected.id, themeId = selectedTheme },
                            function(data)
                                pendingMutation = data
                                if snapshot ~= nil then
                                    snapshot.pendingMutation = data
                                    snapshot.scrap = data.scrapBalance
                                    local mutationTheme = data.themeId or selectedTheme
                                    snapshot.catalysts[THEME_CATALYSTS[mutationTheme]] =
                                        data.catalystCount
                                end
                                local form = MutationDefinitions[data.revealedFormId]
                                local rarity = HudModel.getRarityPresentation(data.tier)
                                announceRarity(
                                    rarity.label,
                                    rarity.icon
                                        .. " "
                                        .. rarity.label
                                        .. " reveal · "
                                        .. (form and form.displayName or data.revealedFormId),
                                    5
                                )
                                if renderMenu ~= nil then
                                    renderMenu()
                                end
                                if renderHud ~= nil then
                                    renderHud()
                                end
                            end
                        )
                    end
                end
            )
        end
    end
end

closeMenu = function()
    menuKind = nil
    if menuPanel ~= nil then
        menuPanel.Visible = false
    end
    if renderHud ~= nil then
        renderHud()
    end
    if renderContext ~= nil then
        renderContext()
    end
end

openMenu = function(kind: string)
    if menuPanel == nil then
        return
    end
    menuKind = kind
    menuTab = "Grow"
    menuPanel.Visible = true
    if contextButton ~= nil then
        contextButton.Visible = false
    end
    if introCard ~= nil then
        introCard.Visible = false
    end
    if goalCard ~= nil then
        goalCard.Visible = false
    end
    if renderMenu ~= nil then
        renderMenu()
    end
end

local function updateSnapshot(data: any)
    if type(data) ~= "table" or type(data.creatures) ~= "table" then
        return
    end
    snapshot = data
    pendingMutation = data.pendingMutation
    if selectedCreatureId ~= nil and getCreature(selectedCreatureId) == nil then
        selectedCreatureId = nil
    end
    getSelectedCreature()
    updateStatusLabels()
    if renderHud ~= nil then
        renderHud()
    end
    if renderMenu ~= nil and menuKind ~= nil then
        renderMenu()
    end
end

local function addSnapshotCreature(creature: any)
    if
        type(snapshot) ~= "table"
        or type(snapshot.creatures) ~= "table"
        or type(creature) ~= "table"
        or type(creature.id) ~= "string"
    then
        return
    end
    if getCreature(creature.id) == nil then
        table.insert(snapshot.creatures, creature)
    end
    if
        type(creature.speciesId) == "string"
        and type(snapshot.codex) == "table"
        and type(snapshot.codex.speciesIds) == "table"
    then
        snapshot.codex.speciesIds[creature.speciesId] = true
    end
    if
        type(creature.mutationFormId) == "string"
        and type(snapshot.codex) == "table"
        and type(snapshot.codex.mutationFormIds) == "table"
    then
        snapshot.codex.mutationFormIds[creature.mutationFormId] = true
    end
end

local function applyActionResult(action: string, data: any)
    if type(data) ~= "table" then
        return
    end
    if action == "PurchaseCapsule" then
        addSnapshotCreature(data.creature)
        setScrapInSnapshot(data.scrapBalance)
        AudioEffectsController.playCue("CapsuleReveal")
        if data.rarity == "Rare" then
            AudioEffectsController.playCue("RarePlus")
        end
        if data.kind == "Welcome" and snapshot ~= nil then
            snapshot.welcomeAvailable = false
        end
    elseif action == "SellCreature" then
        if snapshot ~= nil and type(snapshot.creatures) == "table" then
            for index, creature in snapshot.creatures do
                if creature.id == data.creatureId then
                    table.remove(snapshot.creatures, index)
                    break
                end
            end
        end
        setScrapInSnapshot(data.scrapBalance)
        selectedCreatureId = nil
    elseif action == "PurchaseSlot" then
        if snapshot ~= nil then
            snapshot.slotCapacity = data.slotCapacity
        end
        setScrapInSnapshot(data.scrapBalance)
    elseif action == "PurchaseCatalyst" then
        if snapshot ~= nil then
            snapshot.catalysts[THEME_CATALYSTS[data.themeId]] = data.count
        end
        setScrapInSnapshot(data.scrapBalance)
    elseif action == "CompleteTutorialMutation" then
        AudioEffectsController.playCue("MutationReveal")
        if snapshot ~= nil then
            snapshot.tutorialCompleted = true
            for _, creature in snapshot.creatures do
                if creature.id == data.creatureId then
                    creature.mutationFormId = data.formId
                end
            end
        end
    elseif action == "StartMutation" then
        AudioEffectsController.playCue("MutationReveal")
        if data.tier == "Rare" or data.tier == "Mythic" then
            AudioEffectsController.playCue("RarePlus")
        end
        pendingMutation = data
        if snapshot ~= nil then
            snapshot.pendingMutation = data
            snapshot.scrap = data.scrapBalance
            snapshot.catalysts[THEME_CATALYSTS[data.themeId or selectedTheme]] = data.catalystCount
        end
    elseif action == "ResolveMutation" then
        local offer = getPendingOffer()
        if data.outcome == "Replaced" and offer ~= nil and offer.creatureId ~= nil then
            local creature = getCreature(offer.creatureId)
            if creature ~= nil then
                creature.mutationFormId = data.activeFormId
            end
        end
        pendingMutation = nil
        if snapshot ~= nil then
            snapshot.pendingMutation = nil
        end
    end
    updateStatusLabels()
    if renderHud ~= nil then
        renderHud()
    end
    if renderMenu ~= nil and menuKind ~= nil then
        renderMenu()
    end
end

scheduleSnapshotRefresh = function()
    if snapshotRefreshScheduled or not started then
        return
    end
    snapshotRefreshScheduled = true
    task.delay(2.1, function()
        snapshotRefreshScheduled = false
        if started and requestSnapshot ~= nil then
            requestSnapshot()
        end
    end)
end

sendAction = function(action: string, payload: any, onSuccess: ((any, any) -> ())?): boolean
    if player == nil or requestRemote == nil or resultRemote == nil then
        return false
    end
    if action ~= "GetSnapshot" and actionBusy[action] == true then
        return false
    end
    local sessionId = player:GetAttribute("OddlingsSessionId")
    if type(sessionId) ~= "string" then
        if announce ~= nil and action ~= "GetSnapshot" then
            announce("Connecting to your player data. Try again in a moment.")
        end
        return false
    end
    local requestId = HttpService:GenerateGUID(false)
    actionPending[requestId] = {
        action = action,
        sessionId = sessionId,
        onSuccess = onSuccess,
    }
    if action == "GetSnapshot" then
        snapshotRequestPending = true
        lastSnapshotRequestAt = os.clock()
    else
        actionBusy[action] = true
    end
    local sent = pcall(function()
        requestRemote:FireServer({
            sessionId = sessionId,
            requestId = requestId,
            action = action,
            payload = payload,
        })
    end)
    if not sent then
        actionPending[requestId] = nil
        actionBusy[action] = nil
        if action == "GetSnapshot" then
            snapshotRequestPending = false
        end
        return false
    end
    return true
end

requestSnapshot = function()
    if not started or snapshotRequestPending or sendAction == nil then
        return
    end
    local elapsed = os.clock() - lastSnapshotRequestAt
    if elapsed < 2.1 then
        task.delay(2.1 - elapsed, function()
            if started and not snapshotRequestPending and requestSnapshot ~= nil then
                requestSnapshot()
            end
        end)
        return
    end
    sendAction("GetSnapshot", {}, function(data)
        updateSnapshot(data)
    end)
end

local function onActionResult(response: any)
    if type(response) ~= "table" or type(response.requestId) ~= "string" then
        return
    end
    local pending = actionPending[response.requestId]
    if pending == nil or response.sessionId ~= pending.sessionId then
        return
    end
    if player == nil or player:GetAttribute("OddlingsSessionId") ~= pending.sessionId then
        actionPending[response.requestId] = nil
        if pending.action == "GetSnapshot" then
            snapshotRequestPending = false
        else
            actionBusy[pending.action] = nil
        end
        return
    end
    actionPending[response.requestId] = nil
    if pending.action == "GetSnapshot" then
        snapshotRequestPending = false
    else
        actionBusy[pending.action] = nil
    end
    if response.ok == true then
        if pending.action ~= "GetSnapshot" then
            applyActionResult(pending.action, response.data)
            if PROFILE_ACTIONS[pending.action] == true then
                scheduleSnapshotRefresh()
            end
        end
        if pending.onSuccess ~= nil then
            local ok, errorMessage = pcall(pending.onSuccess, response.data, response)
            if not ok and announce ~= nil then
                announce("That interaction did not finish. Please try again.")
                warn(
                    "[Onboarding] Action response could not be presented: "
                        .. tostring(errorMessage)
                )
            end
        end
    elseif pending.action == "GetSnapshot" then
        task.delay(2.2, function()
            if started and requestSnapshot ~= nil then
                requestSnapshot()
            end
        end)
    elseif pending.action ~= "CancelTheft" or response.code ~= "Locked" then
        if
            pending.action == "BeginTheft"
            or pending.action == "BankTheft"
            or pending.action == "RecoverDroppedCreature"
        then
            contextHold = nil
            setHoldProgress(0)
            if renderContext ~= nil then
                renderContext()
            end
        end
        if announce ~= nil then
            announce(HudModel.getErrorCopy(response.code))
        end
    end
end

local function applyDomainEvent(event: any)
    if type(event) ~= "table" or type(event.event) ~= "string" then
        return
    end
    local data = if type(event.data) == "table" then event.data else {}
    if event.event == Protocol.DomainEventNames.MythicEquipped then
        local displayName = if type(data.playerDisplayName) == "string"
            then data.playerDisplayName
            else "A player"
        local form = if type(data.formId) == "string" then MutationDefinitions[data.formId] else nil
        announce(
            "MYTHIC · "
                .. displayName
                .. " equipped "
                .. (if form ~= nil then form.displayName else "a Mythic form")
                .. ".",
            7
        )
        AudioEffectsController.playCue("RarePlus")
    elseif event.event == Protocol.DomainEventNames.IncomeCredited then
        if type(data.scrap) == "number" and type(data.amount) == "number" and data.amount > 0 then
            setScrapInSnapshot(data.scrap)
            AudioEffectsController.playCue("IncomeTick")
            updateStatusLabels()
            refreshOpenMenu()
        end
    elseif event.event == Protocol.DomainEventNames.RaidPhaseChanged then
        local phase = data.phase
        if phase == "WARNING" then
            announce("RAID WARNING · 30 seconds to prepare.", 5)
            AudioEffectsController.playCue("RaidWarning")
        elseif phase == "RAID" then
            announce("RAID START · Tag a nearby carrier or bring a theft home.", 5)
            AudioEffectsController.playCue("RaidStart")
        elseif phase == "RESOLUTION" then
            announce("RAID END · unfinished carries return.", 4)
            AudioEffectsController.playCue("RaidEnd")
            if closeMenu ~= nil then
                closeMenu()
            end
        elseif phase == "COOLDOWN" then
            announce("Raid result saved · Peace begins soon.", 4)
            if requestSnapshot ~= nil then
                scheduleSnapshotRefresh()
            end
        elseif phase == "PEACE" then
            announce("PEACE · improve or grow your collection.", 3)
        end
        if phase == "RAID" and closeMenu ~= nil then
            closeMenu()
        end
    elseif event.event == "ScrapChanged" and type(data.scrap) == "number" then
        setScrapInSnapshot(data.scrap)
        updateStatusLabels()
        refreshOpenMenu()
    elseif event.event == "CreatureAdded" then
        addSnapshotCreature(data.creature)
        updateStatusLabels()
        refreshOpenMenu()
    elseif event.event == Protocol.DomainEventNames.CreatureChanged then
        if data.change == "Added" and type(data.creature) == "table" then
            addSnapshotCreature(data.creature)
        elseif data.change == "Removed" and type(data.creatureId) == "string" then
            if snapshot ~= nil and type(snapshot.creatures) == "table" then
                for index, creature in snapshot.creatures do
                    if creature.id == data.creatureId then
                        table.remove(snapshot.creatures, index)
                        break
                    end
                end
            end
            if selectedCreatureId == data.creatureId then
                selectedCreatureId = nil
            end
        end
        updateStatusLabels()
        if renderHud ~= nil then
            renderHud()
        end
        refreshOpenMenu()
    elseif event.event == "CreatureRemoved" and type(data.creatureId) == "string" then
        if snapshot ~= nil then
            for index, creature in snapshot.creatures do
                if creature.id == data.creatureId then
                    table.remove(snapshot.creatures, index)
                    break
                end
            end
        end
        updateStatusLabels()
    elseif event.event == "CapacityChanged" and type(data.slotCapacity) == "number" then
        if snapshot ~= nil then
            snapshot.slotCapacity = data.slotCapacity
        end
        updateStatusLabels()
    elseif event.event == "CatalystChanged" and snapshot ~= nil then
        local catalystId = THEME_CATALYSTS[data.themeId]
        if catalystId ~= nil and type(data.count) == "number" then
            snapshot.catalysts[catalystId] = data.count
        end
    elseif event.event == "TutorialCompleted" then
        if snapshot ~= nil then
            snapshot.tutorialCompleted = true
        end
        tutorialTheme = nil
        guidanceSkipped = false
        if renderHud ~= nil then
            renderHud()
        end
    elseif event.event == "CodexChanged" then
        if snapshot ~= nil and type(snapshot.codex) == "table" then
            if type(data.speciesId) == "string" and type(snapshot.codex.speciesIds) == "table" then
                snapshot.codex.speciesIds[data.speciesId] = true
            end
            if
                type(data.mutationFormId) == "string"
                and type(snapshot.codex.mutationFormIds) == "table"
            then
                snapshot.codex.mutationFormIds[data.mutationFormId] = true
            end
        end
        refreshOpenMenu()
    elseif event.event == "TagResolved" then
        AudioEffectsController.playCue("TagDrop")
        announce(
            if data.result == "Dropped"
                then "TAG · creature dropped. Recover it now."
                else "TAG · channel interrupted.",
            4
        )
    elseif event.event == Protocol.DomainEventNames.TheftStateChanged then
        local localUserId = if player ~= nil then player.UserId else 0
        if data.thiefUserId == localUserId then
            localAttemptId = data.attemptId
            localAttemptState = data.state
        end
        if data.state == "CHANNELING" then
            if data.thiefUserId == localUserId or data.ownerUserId == localUserId then
                AudioEffectsController.playCue("TheftInTransit")
            end
            if data.thiefUserId == localUserId then
                channelStartedAt[data.attemptId] = channelStartedAt[data.attemptId] or os.clock()
                if contextHold ~= nil and contextHold.mode == "STEAL" then
                    contextHold.attemptId = data.attemptId
                end
            elseif data.ownerUserId == localUserId then
                announce("Someone is stealing from your base · Tag them to interrupt.", 4)
            end
        elseif data.state == "BANKING" then
            bankStartedAt[data.attemptId] = bankStartedAt[data.attemptId] or os.clock()
        end
        if data.state == "DROPPED" then
            if data.ownerUserId == localUserId then
                droppedAttempt = {
                    attemptId = data.attemptId,
                    ownerUserId = data.ownerUserId,
                    position = data.dropPosition,
                    startedAt = getServerNow(),
                }
                createDropMarker(data.dropPosition)
                announce("Your oddling was dropped · follow the marker to recover it.", 5)
            elseif data.thiefUserId == localUserId then
                createDropMarker(data.dropPosition)
                announce("The carried oddling was dropped. The owner can recover it.", 4)
            end
        elseif data.state == "BANKED" or data.state == "RETURNED" then
            if droppedAttempt ~= nil and droppedAttempt.attemptId == data.attemptId then
                droppedAttempt = nil
                removeDropMarker()
            end
            if localAttemptId == data.attemptId then
                localAttemptId = nil
                localAttemptState = nil
                channelStartedAt[data.attemptId] = nil
                bankStartedAt[data.attemptId] = nil
            end
            if contextHold ~= nil and contextHold.attemptId == data.attemptId then
                contextHold = nil
                setHoldProgress(0)
            end
            if data.state == "BANKED" then
                if data.ownerUserId == localUserId then
                    AudioEffectsController.playCue("SuccessfulBank")
                    announce("A player banked an oddling from your base.", 4)
                elseif data.thiefUserId == localUserId then
                    AudioEffectsController.playCue("Escape")
                    announce("Oddling banked · it is now in your collection.", 4)
                end
            elseif data.ownerUserId == localUserId then
                if data.terminalReason == "Recovered" then
                    AudioEffectsController.playCue("Recovery")
                    announce("Oddling recovered safely.", 4)
                else
                    announce("Oddling returned safely.", 4)
                end
            end
        elseif data.state == "CARRIED" then
            channelStartedAt[data.attemptId] = nil
            if
                contextHold ~= nil
                and contextHold.mode == "BANK"
                and contextHold.attemptId == data.attemptId
            then
                contextHold = nil
                bankStartedAt[data.attemptId] = nil
            end
            if
                contextHold ~= nil
                and contextHold.mode == "STEAL"
                and contextHold.attemptId == data.attemptId
            then
                contextHold = nil
                setHoldProgress(0)
            end
            if data.thiefUserId == localUserId then
                announce("You have the oddling · return to your base to bank it.", 4)
            end
        end
        if renderContext ~= nil then
            renderContext()
        end
    end
    if renderHud ~= nil then
        renderHud()
    end
    if renderMenu ~= nil and menuKind ~= nil then
        renderMenu()
    end
end

local function findNearbyCarrier(localPosition: Vector3): Player?
    local target: Player? = nil
    local nearest = math.huge
    for _, otherPlayer in Players:GetPlayers() do
        if
            otherPlayer ~= player
            and type(otherPlayer:GetAttribute(Protocol.PlayerAttributeNames.CarryingAttemptId))
                == "string"
        then
            local root = getCharacterRoot(otherPlayer)
            local separation = if root ~= nil then distance(localPosition, root.Position) else nil
            if
                separation ~= nil
                and separation <= RaidConfig.TAG_RANGE_STUDS
                and separation < nearest
            then
                target = otherPlayer
                nearest = separation
            end
        end
    end
    return target
end

local function findNearbyCreature(localPosition: Vector3): any?
    local best = nil
    local nearest = math.huge
    local localUserId = if player ~= nil then player.UserId else 0
    for _, entry in stands do
        local ownerUserId = entry.stand:GetAttribute("OwnerUserId")
        local creatureId = entry.stand:GetAttribute("CreatureId")
        local slotIndex = entry.stand:GetAttribute("SlotIndex")
        if
            type(ownerUserId) == "number"
            and ownerUserId ~= localUserId
            and type(creatureId) == "string"
            and slotIndex ~= 1
        then
            local owner = Players:GetPlayerByUserId(ownerUserId)
            local display = entry.display
            local separation = distance(localPosition, display.Position)
            if
                owner ~= nil
                and owner:GetAttribute("OddlingsOperational") == true
                and separation ~= nil
                and separation <= RaidConfig.THEFT_RANGE_STUDS
                and separation < nearest
            then
                nearest = separation
                best = {
                    mode = "STEAL",
                    creatureId = creatureId,
                    ownerUserId = ownerUserId,
                    speciesId = entry.stand:GetAttribute("SpeciesId"),
                    rarity = entry.stand:GetAttribute("BaseRarity"),
                }
            end
        end
    end
    return best
end

local function getBasePad(): BasePart?
    if player == nil or blockout == nil then
        return nil
    end
    local baseId = player:GetAttribute("OddlingsBaseId")
    if type(baseId) ~= "string" then
        return nil
    end
    local base = blockout:FindFirstChild(baseId)
    local pad = if base ~= nil then base:FindFirstChild("Pad") else nil
    return if pad ~= nil and pad:IsA("BasePart") then pad else nil
end

local function findContext(): any?
    if player == nil or player:GetAttribute("OddlingsOperational") ~= true then
        return nil
    end
    local root = getCharacterRoot(player)
    if root == nil then
        return nil
    end
    local localPosition = root.Position
    local phase = player:GetAttribute(Protocol.PlayerAttributeNames.RaidPhase)
    local now = getServerNow()
    local graceUntil = player:GetAttribute(Protocol.PlayerAttributeNames.ArrivalGraceEndsAtUnix)
    local graceActive = type(graceUntil) == "number" and graceUntil > now

    if phase == "RAID" then
        if localAttemptId ~= nil and localAttemptState == "CHANNELING" then
            return { mode = "STEALING", attemptId = localAttemptId }
        end
        local carryingAttemptId =
            player:GetAttribute(Protocol.PlayerAttributeNames.CarryingAttemptId)
        if type(carryingAttemptId) == "string" then
            local pad = getBasePad()
            local separation = if pad ~= nil then distance(localPosition, pad.Position) else nil
            if separation ~= nil and separation <= RaidConfig.BANK_RANGE_STUDS then
                return { mode = "BANK", attemptId = carryingAttemptId }
            end
            return { mode = "CARRY_HOME", attemptId = carryingAttemptId }
        end

        if droppedAttempt ~= nil and droppedAttempt.ownerUserId == player.UserId then
            local position = droppedAttempt.position
            if type(position) == "table" then
                local dropVector = Vector3.new(position.x, position.y, position.z)
                local remaining = droppedAttempt.startedAt
                    + RaidConfig.RECOVERY_WINDOW_SECONDS
                    - now
                local separation = distance(localPosition, dropVector)
                if remaining > 0 and separation ~= nil then
                    if separation <= RaidConfig.RECOVERY_RANGE_STUDS then
                        return {
                            mode = "RECOVER",
                            attemptId = droppedAttempt.attemptId,
                            remaining = remaining,
                        }
                    end
                    return { mode = "FIND_DROP", remaining = remaining }
                end
            end
        end

        local carrier = findNearbyCarrier(localPosition)
        if carrier ~= nil then
            return { mode = "TAG", targetUserId = carrier.UserId, targetName = carrier.DisplayName }
        end
        if not graceActive then
            return findNearbyCreature(localPosition)
        end
        return nil
    end

    if phase == "PEACE" or phase == "WARNING" or phase == "COOLDOWN" then
        local commonsDistance = if commonsKiosk ~= nil
            then distance(localPosition, commonsKiosk.Position)
            else nil
        local commonsRange = if commonsKiosk ~= nil
            then commonsKiosk:GetAttribute("InteractionRangeStuds")
            else EconomyConfig.KIOSK_RANGE_STUDS
        local mutationDistance = if mutationStation ~= nil
            then distance(localPosition, mutationStation.Position)
            else nil
        local mutationRange = if mutationStation ~= nil
            then mutationStation:GetAttribute("InteractionRangeStuds")
            else EconomyConfig.KIOSK_RANGE_STUDS
        if
            mutationDistance ~= nil
            and type(mutationRange) == "number"
            and mutationDistance <= mutationRange
        then
            return {
                mode = if snapshot ~= nil and snapshot.tutorialCompleted ~= true
                    then "MUTATION_TUTORIAL"
                    else "MUTATION",
            }
        end
        if
            commonsDistance ~= nil
            and type(commonsRange) == "number"
            and commonsDistance <= commonsRange
        then
            return { mode = "COMMONS" }
        end
    end
    return nil
end

renderHud = function()
    if snapshot == nil or introCard == nil or goalCard == nil or goalLabel == nil then
        return
    end
    local tutorialComplete = snapshot.tutorialCompleted == true
    local needsThemeChoice = not tutorialComplete and tutorialTheme == nil and not guidanceSkipped
    introCard.Visible = needsThemeChoice and menuKind == nil
    if toastPanel ~= nil and toastPanel.Visible then
        positionToast()
    end
    goalCard.Visible = not needsThemeChoice and menuKind == nil
    if tutorialComplete then
        local phase = player and player:GetAttribute(Protocol.PlayerAttributeNames.RaidPhase)
        if phase == "WARNING" then
            goalLabel.Text = "RAID WARNING · prepare your route and protect your oddlings."
        elseif phase == "RAID" then
            goalLabel.Text = "RAID · Tag a carrier, steal one creature, or watch and learn."
        elseif phase == "RESOLUTION" then
            goalLabel.Text = "RAID END · unfinished carries return automatically."
        else
            goalLabel.Text = HudModel.getGoal(snapshot)
        end
    elseif tutorialTheme ~= nil then
        goalLabel.Text = "Take your free "
            .. tutorialTheme
            .. " Common mutation at the glowing station."
    elseif guidanceSkipped then
        goalLabel.Text = HudModel.getGoal(snapshot, true)
    end
    updateStatusLabels()
end

local function describeContext(context: any): string
    if context.mode == "COMMONS" then
        return "OPEN COMMONS"
    elseif context.mode == "MUTATION_TUTORIAL" then
        return if tutorialTheme ~= nil then "APPLY FREE MUTATION" else "CHOOSE FREE MUTATION"
    elseif context.mode == "MUTATION" then
        return if getPendingOffer() ~= nil then "RESOLVE MUTATION" else "OPEN MUTATION STATION"
    elseif context.mode == "TAG" then
        return "TAG CARRIER · Q"
    elseif context.mode == "STEAL" then
        local label = tostring(context.speciesId or "ODDLING")
        local rarity = HudModel.getRarityPresentation(context.rarity)
        return "HOLD TO STEAL · " .. rarity.label .. " " .. label .. " · 2.5s"
    elseif context.mode == "BANK" then
        return "HOLD TO BANK · 1 SECOND"
    elseif context.mode == "RECOVER" then
        return "HOLD TO RECOVER · 1 SECOND"
    elseif context.mode == "FIND_DROP" then
        return "FOLLOW THE MARKER · RECOVER"
    elseif context.mode == "CARRY_HOME" then
        return "CARRYING · RETURN TO YOUR BASE"
    elseif context.mode == "STEALING" then
        return "STEALING · KEEP STILL"
    end
    return ""
end

renderContext = function()
    if contextButton == nil then
        return
    end
    currentContext = findContext()
    if contextHold ~= nil and contextHold.mode == "BANK" then
        if currentContext == nil or currentContext.mode ~= "BANK" then
            bankStartedAt[contextHold.attemptId] = nil
            contextHold = nil
        end
    elseif contextHold ~= nil and contextHold.mode == "RECOVER" then
        if currentContext == nil or currentContext.mode ~= "RECOVER" then
            recoveryStartedAt[contextHold.attemptId] = nil
            contextHold = nil
        end
    end
    local introVisible = introCard ~= nil and introCard.Visible
    if
        not HudModel.shouldDisplayContextAction(
            currentContext ~= nil,
            menuKind ~= nil,
            introVisible
        )
    then
        contextButton.Visible = false
        if currentContext == nil then
            contextButton.Text = ""
            setHoldProgress(0)
        end
        return
    end
    contextButton.Visible = true
    if contextProgress ~= nil then
        contextProgress.Visible = HudModel.shouldShowHoldProgress(
            currentContext.mode,
            if contextHold ~= nil then contextHold.mode else nil
        )
    end
    if contextHold == nil then
        contextButton.Text = describeContext(currentContext)
    end
    if contextHold == nil then
        setHoldProgress(0)
    end
    local color = if currentContext.mode == "TAG"
        then Color3.fromRGB(177, 87, 76)
        elseif currentContext.mode == "STEAL" then Color3.fromRGB(176, 111, 68)
        elseif currentContext.mode == "RECOVER" then Color3.fromRGB(71, 137, 93)
        elseif currentContext.mode == "BANK" then Color3.fromRGB(70, 127, 96)
        else Color3.fromRGB(65, 116, 150)
    contextButton.BackgroundColor3 = color
    setButtonEnabled(
        contextButton,
        currentContext.mode ~= "FIND_DROP"
            and currentContext.mode ~= "CARRY_HOME"
            and currentContext.mode ~= "STEALING"
    )
end

performContext = function()
    if currentContext == nil then
        return
    end
    local context = currentContext
    if context.mode == "COMMONS" then
        if openMenu ~= nil then
            openMenu("Commons")
        end
    elseif context.mode == "MUTATION" then
        if openMenu ~= nil then
            openMenu("Mutation")
        end
    elseif context.mode == "MUTATION_TUTORIAL" then
        if tutorialTheme ~= nil then
            local starterId = getStarterCreatureId()
            if starterId == nil then
                if announce ~= nil then
                    announce("Your starter stand is still loading.")
                end
                return
            end
            sendAction(
                "CompleteTutorialMutation",
                { creatureId = starterId, themeId = tutorialTheme },
                function(data)
                    applyActionResult("CompleteTutorialMutation", data)
                    tutorialTheme = nil
                    guidanceSkipped = false
                    menuKind = nil
                    if menuPanel ~= nil then
                        menuPanel.Visible = false
                    end
                    local form = MutationDefinitions[data.formId]
                    local rarity = HudModel.getRarityPresentation("Common")
                    announceRarity(
                        rarity.label,
                        "Free mutation · "
                            .. rarity.icon
                            .. " "
                            .. rarity.label
                            .. " · "
                            .. (form and form.displayName or tostring(data.formId))
                            .. ".",
                        4
                    )
                    if renderHud ~= nil then
                        renderHud()
                    end
                    scheduleSnapshotRefresh()
                end
            )
        elseif openMenu ~= nil then
            openMenu("Mutation")
        end
    elseif context.mode == "TAG" then
        sendAction("Tag", { targetUserId = context.targetUserId }, function(data)
            if data.success ~= true then
                announce("Tag missed · get within 7 studs of the carrier.")
            end
        end)
    end
end

local function cancelTheftAttempt(attemptId: string)
    sendAction("CancelTheft", { attemptId = attemptId }, function()
        localAttemptId = nil
        localAttemptState = nil
    end)
end

local function completeBankHold(hold: any)
    if hold.completeSent or hold.attemptId == nil then
        return
    end
    hold.completeSent = true
    local sent = sendAction(
        "BankTheft",
        { attemptId = hold.attemptId, stage = "Complete", catalystThemeId = selectedTheme },
        function(data)
            bankStartedAt[hold.attemptId] = nil
            contextHold = nil
            announce(
                "Bank complete · " .. tostring(data.catalystThemeId) .. " catalyst earned.",
                4
            )
            if renderContext ~= nil then
                renderContext()
            end
        end
    )
    if not sent and contextHold == hold then
        contextHold = nil
        bankStartedAt[hold.attemptId] = nil
        if renderContext ~= nil then
            renderContext()
        end
    end
end

beginContextHold = function(input: InputObject?)
    if contextHold ~= nil or currentContext == nil then
        return
    end
    local mode = currentContext.mode
    if mode ~= "STEAL" and mode ~= "BANK" and mode ~= "RECOVER" then
        return
    end
    local hold = {
        mode = mode,
        pressed = true,
        beganAt = os.clock(),
        anchorPosition = if player ~= nil and getCharacterRoot(player) ~= nil
            then (getCharacterRoot(player) :: BasePart).Position
            else nil,
        inputType = if input ~= nil then input.UserInputType else nil,
        attemptId = currentContext.attemptId,
        context = currentContext,
    }
    contextHold = hold
    if mode == "STEAL" then
        local sent = sendAction(
            "BeginTheft",
            { targetCreatureId = hold.context.creatureId },
            function(data)
                hold.attemptId = data.attemptId
                localAttemptId = data.attemptId
                localAttemptState = "CHANNELING"
                channelStartedAt[data.attemptId] = os.clock()
                if
                    not hold.pressed
                    and os.clock() - hold.beganAt < RaidConfig.THEFT_CHANNEL_SECONDS
                then
                    cancelTheftAttempt(data.attemptId)
                    if contextHold == hold then
                        contextHold = nil
                    end
                end
            end
        )
        if not sent and contextHold == hold then
            contextHold = nil
        end
    elseif mode == "BANK" then
        local sent = sendAction(
            "BankTheft",
            { attemptId = hold.attemptId, stage = "Begin" },
            function()
                if contextHold ~= hold then
                    return
                end
                bankStartedAt[hold.attemptId] = os.clock()
                hold.startedAtLocal = bankStartedAt[hold.attemptId]
                if not hold.pressed and contextHold == hold then
                    hold.waitingForStationaryHold = true
                end
            end
        )
        if not sent and contextHold == hold then
            contextHold = nil
        end
    elseif mode == "RECOVER" then
        local sent = sendAction(
            "RecoverDroppedCreature",
            { attemptId = hold.attemptId },
            function(data)
                if contextHold ~= hold then
                    return
                end
                recoveryStartedAt[hold.attemptId] = os.clock()
                hold.startedAtLocal = recoveryStartedAt[hold.attemptId]
                if data.recovered == true then
                    droppedAttempt = nil
                    removeDropMarker()
                    contextHold = nil
                    announce("Oddling recovered safely.", 4)
                end
            end
        )
        if not sent and contextHold == hold then
            contextHold = nil
        end
    end
    if contextButton ~= nil then
        contextButton.Text = describeContext(currentContext)
    end
end

endContextHold = function()
    local hold = contextHold
    if hold == nil or not hold.pressed then
        return
    end
    hold.pressed = false
    if hold.mode == "STEAL" then
        if os.clock() - hold.beganAt < RaidConfig.THEFT_CHANNEL_SECONDS then
            if hold.attemptId ~= nil then
                cancelTheftAttempt(hold.attemptId)
            else
                hold.cancelAfterStart = true
            end
        end
        if contextHold == hold then
            contextHold = nil
        end
    elseif hold.mode == "BANK" or hold.mode == "RECOVER" then
        -- The server completes these stationary holds while the player remains in range.
        hold.pressed = false
    elseif contextHold == hold then
        contextHold = nil
    end
    if hold.mode == "STEAL" then
        setHoldProgress(0)
    end
    if renderContext ~= nil then
        renderContext()
    end
end

local function updateHoldProgress()
    local hold = contextHold
    if
        hold == nil
        or (not hold.pressed and hold.mode == "STEAL")
        or contextProgress == nil
        or contextButton == nil
    then
        return
    end
    local now = os.clock()
    local start = hold.startedAtLocal
    local duration = 1
    if hold.mode == "STEAL" then
        duration = RaidConfig.THEFT_CHANNEL_SECONDS
        start = if hold.attemptId ~= nil then channelStartedAt[hold.attemptId] else hold.beganAt
    elseif hold.mode == "BANK" then
        duration = RaidConfig.BANK_HOLD_SECONDS
        start = if hold.attemptId ~= nil then bankStartedAt[hold.attemptId] else nil
    elseif hold.mode == "RECOVER" then
        duration = RaidConfig.RECOVERY_HOLD_SECONDS
        start = if hold.attemptId ~= nil then recoveryStartedAt[hold.attemptId] else nil
    end
    if hold.mode == "BANK" or hold.mode == "RECOVER" then
        local root = getCharacterRoot(player)
        local movedDistance = if root ~= nil and hold.anchorPosition ~= nil
            then (root.Position - hold.anchorPosition).Magnitude
            else math.huge
        if movedDistance > RaidConfig.STATIONARY_TOLERANCE_STUDS then
            if hold.attemptId ~= nil then
                if hold.mode == "BANK" then
                    bankStartedAt[hold.attemptId] = nil
                else
                    recoveryStartedAt[hold.attemptId] = nil
                end
            end
            contextHold = nil
            setHoldProgress(0)
            if renderContext ~= nil then
                renderContext()
            end
            return
        end
    end
    local progress = math.clamp(((start or now) and (now - (start or now)) or 0) / duration, 0, 1)
    setHoldProgress(progress)
    contextButton.Text = describeContext(hold.context)
        .. " · "
        .. string.format("%d%%", math.floor(progress * 100))
    if hold.mode == "BANK" and progress >= 1 then
        completeBankHold(hold)
    end
end

local function installWorldReferences()
    blockout = Workspace:WaitForChild("OddlingsBlockout", 30)
    if blockout == nil then
        return false
    end
    commonsKiosk = blockout:FindFirstChild("CommonsKiosk") :: BasePart?
    mutationStation = blockout:FindFirstChild("MutationStation") :: BasePart?
    table.clear(stands)
    for _, base in blockout:GetChildren() do
        if string.match(base.Name, "^Base%d%d$") ~= nil then
            for slotIndex = 1, EconomyConfig.MAX_SLOT_CAPACITY do
                local stand = base:FindFirstChild(string.format("Stand%02d", slotIndex))
                local display = base:FindFirstChild(string.format("CreatureDisplay%02d", slotIndex))
                if
                    stand ~= nil
                    and stand:IsA("BasePart")
                    and display ~= nil
                    and display:IsA("BasePart")
                then
                    table.insert(stands, { stand = stand, display = display })
                end
            end
        end
    end
    return true
end

local function bindLeaderstats()
    if player == nil then
        return
    end
    local function attach()
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats == nil then
            return
        end
        local scrapValue = leaderstats:FindFirstChild("Scrap")
        local incomeValue = leaderstats:FindFirstChild("IncomePerMinute")
        if scrapValue ~= nil and scrapValue:IsA("IntValue") then
            leaderstatsScrap = scrapValue
            addConnection(scrapValue:GetPropertyChangedSignal("Value"):Connect(function()
                updateStatusLabels()
                refreshOpenMenu()
            end))
        end
        if incomeValue ~= nil and incomeValue:IsA("NumberValue") then
            leaderstatsIncome = incomeValue
            addConnection(incomeValue:GetPropertyChangedSignal("Value"):Connect(updateStatusLabels))
        end
        updateStatusLabels()
    end
    attach()
    addConnection(player.ChildAdded:Connect(function(child)
        if child.Name == "leaderstats" then
            attach()
        end
    end))
end

local function bindKeyboardActions()
    ContextActionService:BindAction("OddlingsContextAction", function(_, inputState)
        if UserInputService:GetFocusedTextBox() ~= nil then
            return Enum.ContextActionResult.Pass
        end
        if inputState == Enum.UserInputState.Begin then
            if
                currentContext ~= nil
                and (
                    currentContext.mode == "STEAL"
                    or currentContext.mode == "BANK"
                    or currentContext.mode == "RECOVER"
                )
            then
                if beginContextHold ~= nil then
                    beginContextHold(nil)
                end
            elseif performContext ~= nil then
                performContext()
            end
            return Enum.ContextActionResult.Sink
        elseif inputState == Enum.UserInputState.End then
            if endContextHold ~= nil then
                endContextHold()
            end
            return Enum.ContextActionResult.Sink
        end
        return Enum.ContextActionResult.Pass
    end, false, Enum.KeyCode.E)
    ContextActionService:BindAction("OddlingsTagAction", function(_, inputState)
        if
            inputState == Enum.UserInputState.Begin
            and UserInputService:GetFocusedTextBox() == nil
        then
            if currentContext ~= nil and currentContext.mode == "TAG" and performContext ~= nil then
                performContext()
                return Enum.ContextActionResult.Sink
            end
        end
        return Enum.ContextActionResult.Pass
    end, false, Enum.KeyCode.Q)
end

local function connectActionRemotes()
    if screenGui == nil or player == nil then
        return false
    end
    local network = ReplicatedStorage:WaitForChild("Network")
    requestRemote = network:WaitForChild(Protocol.RemoteNames.ActionRequest) :: RemoteEvent
    resultRemote = network:WaitForChild(Protocol.RemoteNames.ActionResult) :: RemoteEvent
    domainEvent = network:WaitForChild(Protocol.RemoteNames.DomainEvent) :: RemoteEvent
    if
        not requestRemote:IsA("RemoteEvent")
        or not resultRemote:IsA("RemoteEvent")
        or not domainEvent:IsA("RemoteEvent")
    then
        return false
    end
    addConnection(resultRemote.OnClientEvent:Connect(onActionResult))
    addConnection(domainEvent.OnClientEvent:Connect(applyDomainEvent))
    return true
end

function controller.start(): boolean
    if started then
        return true
    end
    player = Players.LocalPlayer
    if player == nil then
        return false
    end
    screenGui = RaidPresentationController.getGui()
    if screenGui == nil then
        return false
    end
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    buildUi(screenGui)
    if not connectActionRemotes() then
        if rootFrame ~= nil then
            rootFrame:Destroy()
        end
        rootFrame = nil
        return false
    end
    installWorldReferences()
    bindLeaderstats()
    bindKeyboardActions()
    started = true
    task.spawn(function()
        task.wait(1)
        for _ = 1, 10 do
            if not started then
                return
            end
            local success = pcall(function()
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
            end)
            if success then
                return
            end
            task.wait(0.1)
        end
        warn("[Oddlings] Could not disable the default Roblox player list.")
    end)

    addConnection(UserInputService.InputEnded:Connect(function(input)
        if contextHold ~= nil and contextHold.inputType == input.UserInputType then
            if endContextHold ~= nil then
                endContextHold()
            end
        end
    end))
    addConnection(RunService.Heartbeat:Connect(function(deltaTime)
        scanAccumulator += deltaTime
        if scanAccumulator >= 0.15 then
            scanAccumulator %= 0.15
            if
                droppedAttempt ~= nil
                and getServerNow()
                    >= droppedAttempt.startedAt + RaidConfig.RECOVERY_WINDOW_SECONDS
            then
                droppedAttempt = nil
                removeDropMarker()
            end
            if renderContext ~= nil then
                renderContext()
            end
        end
        updateHoldProgress()
    end))
    addConnection(player:GetAttributeChangedSignal("OddlingsSessionId"):Connect(function()
        local nextSessionId = player:GetAttribute("OddlingsSessionId")
        if nextSessionId ~= activeSessionId then
            if activeSessionId ~= nil then
                actionPending = {}
                actionBusy = {}
                snapshotRequestPending = false
                snapshot = nil
                pendingMutation = nil
                selectedCreatureId = nil
                localAttemptId = nil
                localAttemptState = nil
                droppedAttempt = nil
                contextHold = nil
                channelStartedAt = {}
                bankStartedAt = {}
                recoveryStartedAt = {}
                removeDropMarker()
                updateStatusLabels()
                if renderHud ~= nil then
                    renderHud()
                end
            end
            activeSessionId = if type(nextSessionId) == "string" then nextSessionId else nil
        end
        if requestSnapshot ~= nil then
            requestSnapshot()
        end
    end))
    local sessionId = player:GetAttribute("OddlingsSessionId")
    if type(sessionId) == "string" then
        requestSnapshot()
    end
    if renderHud ~= nil then
        renderHud()
    end
    if renderContext ~= nil then
        renderContext()
    end
    return true
end

function controller.stop()
    ContextActionService:UnbindAction("OddlingsContextAction")
    ContextActionService:UnbindAction("OddlingsTagAction")
    for _, connection in connections do
        if connection ~= nil then
            connection:Disconnect()
        end
    end
    table.clear(connections)
    removeDropMarker()
    if rootFrame ~= nil then
        rootFrame:Destroy()
    end
    rootFrame = nil
    introCard = nil
    table.clear(introButtons)
    goalCard = nil
    goalLabel = nil
    contextButton = nil
    contextProgress = nil
    table.clear(holdProgressSegments)
    holdProgressFilledCount = -1
    menuPanel = nil
    menuTitle = nil
    menuBody = nil
    toastPanel = nil
    toastLabel = nil
    snapshot = nil
    menuKind = nil
    selectedTheme = "Ember"
    tutorialTheme = nil
    guidanceSkipped = false
    selectedCreatureId = nil
    pendingMutation = nil
    currentContext = nil
    localAttemptId = nil
    localAttemptState = nil
    droppedAttempt = nil
    actionPending = {}
    actionBusy = {}
    snapshotRequestPending = false
    snapshotRefreshScheduled = false
    leaderstatsScrap = nil
    leaderstatsIncome = nil
    contextHold = nil
    blockout = nil
    commonsKiosk = nil
    mutationStation = nil
    stands = {}
    requestRemote = nil
    resultRemote = nil
    domainEvent = nil
    screenGui = nil
    player = nil
    activeSessionId = nil
    started = false
end

return table.freeze(controller)
