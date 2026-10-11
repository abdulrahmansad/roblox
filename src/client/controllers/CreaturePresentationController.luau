-- Builds local, non-colliding creature models from the fixed shared visual recipes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CreatureDefinitions = require(ReplicatedStorage.Shared.definitions.CreatureDefinitions)
local MutationDefinitions = require(ReplicatedStorage.Shared.definitions.MutationDefinitions)
local VisualDefinitions = require(ReplicatedStorage.Shared.definitions.CreatureVisualDefinitions)
local HudModel = require(script.Parent.HudModel)

local controller = {}
local BODY_SIZES = {
    Round = Vector3.new(2.1, 1.85, 1.85),
    Winged = Vector3.new(1.95, 1.5, 1.55),
    Aquatic = Vector3.new(2.25, 1.5, 1.7),
    Tall = Vector3.new(2.1, 1.75, 1.6),
}
local RARITY_COLORS = {
    Common = Color3.fromRGB(146, 194, 128),
    Uncommon = Color3.fromRGB(101, 177, 224),
    Rare = Color3.fromRGB(192, 126, 231),
    Mythic = Color3.fromRGB(255, 212, 105),
}

local started = false
local reducedEffects = false
local connections = {}
local records = {}
local localFolder: Folder? = nil

local function colorFrom(rgb: { number }): Color3
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function materialFrom(name: string): Enum.Material
    return Enum.Material[name] or Enum.Material.SmoothPlastic
end

local function addPart(
    model: Model,
    name: string,
    className: string,
    shapeName: string?,
    size: Vector3,
    center: Vector3,
    offset: Vector3,
    color: Color3,
    material: Enum.Material?,
    transparency: number?,
    rotation: Vector3?
): BasePart
    local part = Instance.new(className)
    part.Name = name
    if part:IsA("Part") and shapeName ~= nil then
        part.Shape = Enum.PartType[shapeName]
    end
    part.Size = size
    part.CFrame = CFrame.new(center + offset)
        * CFrame.Angles(
            if rotation ~= nil then rotation.X else 0,
            if rotation ~= nil then rotation.Y else 0,
            if rotation ~= nil then rotation.Z else 0
        )
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Transparency = transparency or 0
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Parent = model
    return part
end

local function addSpeciesSilhouette(
    model: Model,
    center: Vector3,
    detail: string,
    accent: Color3,
    bodySize: Vector3
): BasePart?
    local function part(
        name: string,
        className: string,
        shape: string?,
        size: Vector3,
        offset: Vector3,
        rotation: Vector3?
    ): BasePart
        return addPart(
            model,
            name,
            className,
            shape,
            size,
            center,
            offset,
            accent,
            Enum.Material.SmoothPlastic,
            nil,
            rotation
        )
    end

    if detail == "LeafNubs" then
        part(
            "LeafNubLeft",
            "Part",
            "Ball",
            Vector3.new(0.5, 0.82, 0.22),
            Vector3.new(-0.38, 1.04, 0)
        )
        return part(
            "LeafNubRight",
            "Part",
            "Ball",
            Vector3.new(0.5, 0.82, 0.22),
            Vector3.new(0.38, 1.04, 0)
        )
    elseif detail == "KettleBack" then
        return part(
            "KettleBack",
            "Part",
            "Ball",
            Vector3.new(1.24, 0.8, 1.1),
            Vector3.new(0, 0.55, 0.35)
        )
    elseif detail == "FloppyEars" then
        part(
            "DropEarLeft",
            "Part",
            "Ball",
            Vector3.new(0.42, 0.92, 0.38),
            Vector3.new(-1.02, 0.24, 0.12),
            Vector3.new(0, 0, math.rad(24))
        )
        return part(
            "DropEarRight",
            "Part",
            "Ball",
            Vector3.new(0.42, 0.92, 0.38),
            Vector3.new(1.02, 0.24, 0.12),
            Vector3.new(0, 0, math.rad(-24))
        )
    elseif detail == "ButtonWings" then
        part(
            "BatWingLeft",
            "WedgePart",
            nil,
            Vector3.new(1.25, 0.18, 1.05),
            Vector3.new(-1.15, 0.1, 0.36),
            Vector3.new(0, 0, math.rad(25))
        )
        return part(
            "BatWingRight",
            "WedgePart",
            nil,
            Vector3.new(1.25, 0.18, 1.05),
            Vector3.new(1.15, 0.1, 0.36),
            Vector3.new(0, 0, math.rad(-25))
        )
    elseif detail == "RibbonTail" then
        part(
            "RibbonTailRoot",
            "Part",
            "Block",
            Vector3.new(0.34, 0.18, 0.8),
            Vector3.new(0, -0.12, 1.0)
        )
        return part(
            "RibbonTailTip",
            "Part",
            "Block",
            Vector3.new(0.18, 0.14, 0.75),
            Vector3.new(0.18, -0.18, 1.62),
            Vector3.new(0, 0, math.rad(18))
        )
    elseif detail == "StoneBack" then
        return part(
            "StoneBackPlate",
            "WedgePart",
            nil,
            Vector3.new(1.65, 0.9, 1.3),
            Vector3.new(0, 0.55, 0.2)
        )
    elseif detail == "CupShell" then
        part(
            "CupShell",
            "Part",
            "Cylinder",
            Vector3.new(1.45, 0.9, 1.45),
            Vector3.new(0, 0.78, 0),
            Vector3.new(0, 0, math.pi / 2)
        )
        return part(
            "CupRim",
            "Part",
            "Cylinder",
            Vector3.new(1.55, 0.14, 1.55),
            Vector3.new(0, 1.16, 0),
            Vector3.new(0, 0, math.pi / 2)
        )
    elseif detail == "ZigzagPlume" then
        part(
            "PlumeRoot",
            "WedgePart",
            nil,
            Vector3.new(0.38, 0.42, 0.5),
            Vector3.new(0, 0.82, 0.62)
        )
        return part(
            "PlumeTip",
            "WedgePart",
            nil,
            Vector3.new(0.32, 0.44, 0.46),
            Vector3.new(0.12, 1.14, 0.83),
            Vector3.new(0, 0, math.rad(25))
        )
    elseif detail == "OversizedEars" then
        part(
            "GremlinEarLeft",
            "Part",
            "Ball",
            Vector3.new(0.78, 1.05, 0.36),
            Vector3.new(-1, 0.62, 0)
        )
        return part(
            "GremlinEarRight",
            "Part",
            "Ball",
            Vector3.new(0.78, 1.05, 0.36),
            Vector3.new(1, 0.62, 0)
        )
    elseif detail == "SquareFins" then
        part(
            "CarpFinLeft",
            "Part",
            "Block",
            Vector3.new(0.84, 0.2, 0.78),
            Vector3.new(-1.12, 0.22, 0.2)
        )
        return part(
            "CarpFinRight",
            "Part",
            "Block",
            Vector3.new(0.84, 0.2, 0.78),
            Vector3.new(1.12, 0.22, 0.2)
        )
    elseif detail == "LanternHorns" then
        part(
            "YakHornLeft",
            "WedgePart",
            nil,
            Vector3.new(0.5, 0.84, 0.48),
            Vector3.new(-0.78, 0.92, 0),
            Vector3.new(0, 0, math.rad(-24))
        )
        part(
            "YakChestLantern",
            "Part",
            "Ball",
            Vector3.new(0.72, 0.82, 0.42),
            Vector3.new(0, -0.04, -0.78)
        )
        return part(
            "YakHornRight",
            "WedgePart",
            nil,
            Vector3.new(0.5, 0.84, 0.48),
            Vector3.new(0.78, 0.92, 0),
            Vector3.new(0, 0, math.rad(24))
        )
    elseif detail == "ThreeHeads" then
        part(
            "HydraNeckLeft",
            "Part",
            "Cylinder",
            Vector3.new(0.46, 0.82, 0.46),
            Vector3.new(-0.65, 0.7, 0),
            Vector3.new(0, 0, math.pi / 2)
        )
        part(
            "HydraNeckRight",
            "Part",
            "Cylinder",
            Vector3.new(0.46, 0.82, 0.46),
            Vector3.new(0.65, 0.7, 0),
            Vector3.new(0, 0, math.pi / 2)
        )
        part(
            "HydraHeadLeft",
            "Part",
            "Ball",
            Vector3.new(0.7, 0.68, 0.68),
            Vector3.new(-0.68, 1.24, 0)
        )
        part(
            "HydraHeadRight",
            "Part",
            "Ball",
            Vector3.new(0.7, 0.68, 0.68),
            Vector3.new(0.68, 1.24, 0)
        )
        return part(
            "HydraHeadCenter",
            "Part",
            "Ball",
            Vector3.new(0.74, 0.72, 0.7),
            Vector3.new(0, 1.48, -0.06)
        )
    end

    return part(
        "RigAccent",
        "Part",
        "Ball",
        Vector3.new(0.3, 0.3, 0.3),
        Vector3.new(0, bodySize.Y / 2, 0)
    )
end

local function addMutationDetail(
    model: Model,
    center: Vector3,
    formId: string,
    recipe: any,
    bodySize: Vector3
): BasePart
    local accent = colorFrom(recipe.accent)
    local material = materialFrom(recipe.material)
    local detail = recipe.silhouette
    local function part(
        name: string,
        className: string,
        shape: string?,
        size: Vector3,
        offset: Vector3,
        detailMaterial: Enum.Material?,
        transparency: number?,
        rotation: Vector3?
    ): BasePart
        return addPart(
            model,
            name,
            className,
            shape,
            size,
            center,
            offset,
            accent,
            detailMaterial or material,
            transparency,
            rotation
        )
    end

    if detail == "Fissures" then
        part(
            "FissureLeft",
            "Part",
            "Block",
            Vector3.new(0.08, 0.72, 0.06),
            Vector3.new(-0.34, 0.05, -bodySize.Z / 2),
            Enum.Material.Neon
        )
        return part(
            "FissureRight",
            "Part",
            "Block",
            Vector3.new(0.08, 0.56, 0.06),
            Vector3.new(0.34, -0.08, -bodySize.Z / 2),
            Enum.Material.Neon
        )
    elseif
        detail == "Cap"
        or detail == "MushroomCap"
        or detail == "FacetedCrown"
        or detail == "LeafCrown"
    then
        local size = if detail == "Cap"
            then Vector3.new(1.45, 0.54, 1.2)
            else Vector3.new(1.6, 0.62, 1.35)
        part("FormCrown", "Part", "Ball", size, Vector3.new(0, bodySize.Y / 2 + 0.2, 0), material)
        if detail == "FacetedCrown" or detail == "LeafCrown" then
            part(
                "CrownPointLeft",
                "WedgePart",
                nil,
                Vector3.new(0.44, 0.84, 0.42),
                Vector3.new(-0.44, bodySize.Y / 2 + 0.68, 0)
            )
            return part(
                "CrownPointRight",
                "WedgePart",
                nil,
                Vector3.new(0.44, 0.84, 0.42),
                Vector3.new(0.44, bodySize.Y / 2 + 0.68, 0)
            )
        end
        return part(
            "FormCrownHighlight",
            "Part",
            "Ball",
            Vector3.new(0.28, 0.1, 0.28),
            Vector3.new(0, bodySize.Y / 2 + 0.38, -0.44),
            Enum.Material.Neon
        )
    elseif
        detail == "Mantle"
        or detail == "ForgePlates"
        or detail == "OpalPanels"
        or detail == "MirrorPlate"
    then
        return part(
            "FormMantle",
            "Part",
            "Ball",
            Vector3.new(bodySize.X * 0.78, bodySize.Y * 0.62, 0.42),
            Vector3.new(0, 0.08, bodySize.Z / 2 - 0.14),
            material
        )
    elseif
        detail == "ToastPatch"
        or detail == "LichenPatches"
        or detail == "PinHighlights"
        or detail == "CyanSpots"
    then
        part(
            "FormPatchLeft",
            "Part",
            "Ball",
            Vector3.new(0.32, 0.3, 0.12),
            Vector3.new(-0.56, 0.15, -bodySize.Z / 2),
            if detail == "CyanSpots" then Enum.Material.Neon else material
        )
        return part(
            "FormPatchRight",
            "Part",
            "Ball",
            Vector3.new(0.32, 0.3, 0.12),
            Vector3.new(0.56, -0.08, -bodySize.Z / 2),
            if detail == "CyanSpots" then Enum.Material.Neon else material
        )
    elseif detail == "FlameFin" or detail == "CrystalTail" or detail == "SpectrumEdge" then
        return part(
            "FormFin",
            "WedgePart",
            nil,
            Vector3.new(0.82, 0.9, 0.62),
            Vector3.new(0, 0.08, bodySize.Z / 2 + 0.34),
            material
        )
    elseif detail == "EmberHorns" then
        part(
            "FormHornLeft",
            "WedgePart",
            nil,
            Vector3.new(0.44, 0.78, 0.42),
            Vector3.new(-0.64, bodySize.Y / 2 + 0.3, 0),
            material,
            nil,
            Vector3.new(0, 0, math.rad(-28))
        )
        return part(
            "FormHornRight",
            "WedgePart",
            nil,
            Vector3.new(0.44, 0.78, 0.42),
            Vector3.new(0.64, bodySize.Y / 2 + 0.3, 0),
            material,
            nil,
            Vector3.new(0, 0, math.rad(28))
        )
    elseif detail == "ChestCore" then
        return part(
            "FormChestCore",
            "Part",
            "Ball",
            Vector3.new(0.72, 0.78, 0.34),
            Vector3.new(0, -0.06, -bodySize.Z / 2),
            Enum.Material.Neon
        )
    elseif detail == "RootCuffs" then
        local cuffSize = Vector3.new(0.56, 0.68, 0.62)
        part(
            "RootCuffLeft",
            "Part",
            "Ball",
            cuffSize,
            Vector3.new(-bodySize.X / 2 + 0.08, -0.5, 0.08),
            material
        )
        part(
            "RootBranchLeft",
            "WedgePart",
            nil,
            Vector3.new(0.3, 0.66, 0.34),
            Vector3.new(-bodySize.X / 2 - 0.18, -0.33, 0.32),
            material,
            nil,
            Vector3.new(0, 0, math.rad(24))
        )
        part(
            "RootCuffRight",
            "Part",
            "Ball",
            cuffSize,
            Vector3.new(bodySize.X / 2 - 0.08, -0.5, 0.08),
            material
        )
        return part(
            "RootBranchRight",
            "WedgePart",
            nil,
            Vector3.new(0.3, 0.66, 0.34),
            Vector3.new(bodySize.X / 2 + 0.18, -0.33, 0.32),
            material,
            nil,
            Vector3.new(0, 0, math.rad(-24))
        )
    elseif detail == "SplitPalette" or detail == "VineBand" then
        local size = Vector3.new(bodySize.X * 0.92, 0.18, bodySize.Z * 0.9)
        return part(
            "FormBand",
            "Part",
            "Cylinder",
            size,
            Vector3.new(0, 0, -0.04),
            material,
            nil,
            Vector3.new(0, 0, math.pi / 2)
        )
    elseif detail == "AuroraRibbon" then
        return part(
            "FormRibbon",
            "Part",
            "Block",
            Vector3.new(0.18, 1.5, 1.7),
            Vector3.new(0, 0.28, bodySize.Z / 2 + 0.12),
            material,
            0.28
        )
    elseif detail == "FlowerShield" then
        return part(
            "FormShield",
            "Part",
            "Ball",
            Vector3.new(0.74, 0.9, 0.34),
            Vector3.new(bodySize.X / 2 + 0.12, 0.12, 0),
            material
        )
    elseif detail == "SunRing" or detail == "PrismHalo" or detail == "RootHalo" then
        return part(
            "FormHalo",
            "Part",
            "Cylinder",
            Vector3.new(2.4, 0.1, 2.4),
            Vector3.new(0, bodySize.Y / 2 + 0.72, 0),
            Enum.Material.Neon,
            0.42,
            Vector3.new(0, 0, math.pi / 2)
        )
    end

    return part(
        "FormDetail_" .. formId,
        "Part",
        "Ball",
        Vector3.new(0.72, 0.7, 0.4),
        Vector3.new(0, bodySize.Y / 2 + 0.2, 0),
        material
    )
end

local function getMutationIncome(speciesId: string, formId: string?): number
    local species = CreatureDefinitions[speciesId]
    if species == nil then
        return 0
    end
    local form = if formId ~= nil then MutationDefinitions[formId] else nil
    return species.scrapPerMinute * (if form ~= nil then form.multiplier else 1)
end

local function addInspectionLabel(body: BasePart, speciesId: string, formId: string?)
    local species = CreatureDefinitions[speciesId]
    local form = if formId ~= nil then MutationDefinitions[formId] else nil
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "CreatureInspection"
    billboard.Adornee = body
    billboard.Size = UDim2.fromOffset(176, if form ~= nil then 58 else 42)
    billboard.StudsOffset = Vector3.new(0, 1.7, 0)
    billboard.MaxDistance = 44
    billboard.AlwaysOnTop = false
    billboard.Parent = body

    local label = Instance.new("TextLabel")
    label.Name = "Details"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundColor3 = Color3.fromRGB(26, 37, 42)
    label.BackgroundTransparency = 0.22
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(246, 250, 240)
    label.TextSize = 12
    label.TextWrapped = true
    local firstLine = string.format("%s SPECIES · %s", string.upper(species.rarity), speciesId)
    local secondLine = if form ~= nil
        then string.format("%s MUTATION · %s", string.upper(form.tier), form.displayName)
        else "NO ACTIVE MUTATION"
    label.Text = firstLine
        .. "\n"
        .. secondLine
        .. "\n"
        .. HudModel.formatNumber(getMutationIncome(speciesId, formId))
        .. " SCRAP/MIN"
    if form ~= nil then
        label.TextColor3 = RARITY_COLORS[form.tier] or label.TextColor3
    end
    label.Parent = billboard
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = label
end

local function stopRecordEffects(record: any)
    if record.tween ~= nil then
        record.tween:Cancel()
        record.tween = nil
    end
end

local function applyRecordEffects(record: any)
    if record.highlight ~= nil then
        record.highlight.Enabled = not reducedEffects
    end
    stopRecordEffects(record)
    if reducedEffects or record.animatedPart == nil then
        return
    end
    local origin = record.animatedPart.Position
    record.tween = TweenService:Create(
        record.animatedPart,
        TweenInfo.new(
            record.effectDuration or 1.6,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            -1,
            true
        ),
        { Position = origin + Vector3.new(0, record.effectHeight or 0.12, 0) }
    )
    record.tween:Play()
end

local function destroyModel(record: any)
    stopRecordEffects(record)
    if record.model ~= nil then
        record.model:Destroy()
        record.model = nil
    end
    record.highlight = nil
    record.animatedPart = nil
    record.effectHeight = nil
    record.effectDuration = nil
end

local function buildModel(record: any, speciesId: string, formId: string?): Model?
    local species = CreatureDefinitions[speciesId]
    local speciesVisual = VisualDefinitions.Species[speciesId]
    if species == nil or speciesVisual == nil then
        return nil
    end
    local form = if formId ~= nil then MutationDefinitions[formId] else nil
    local recipe = if formId ~= nil then VisualDefinitions.Mutations[formId] else nil
    if formId ~= nil and (form == nil or recipe == nil) then
        return nil
    end

    local model = Instance.new("Model")
    model.Name = "CreatureDisplay_" .. speciesId
    model:SetAttribute("PresentationOnly", true)
    model:SetAttribute("SpeciesId", speciesId)
    model:SetAttribute("MutationFormId", formId)
    local center = record.display.Position + Vector3.new(0, 0.16, 0)
    local bodySize = BODY_SIZES[speciesVisual.rigFamily] or BODY_SIZES.Round
    local bodyColor = if recipe ~= nil
        then colorFrom(recipe.body)
        else colorFrom(speciesVisual.body)
    local accentColor = if recipe ~= nil
        then colorFrom(recipe.accent)
        else colorFrom(speciesVisual.accent)
    local bodyMaterial = if recipe ~= nil
        then materialFrom(recipe.material)
        else Enum.Material.SmoothPlastic
    local body = addPart(
        model,
        "Body",
        "Part",
        "Ball",
        bodySize,
        center,
        Vector3.zero,
        bodyColor,
        bodyMaterial
    )
    model.PrimaryPart = body

    local eyeZ = -bodySize.Z / 2 - 0.045
    for _, eyeX in { -0.38, 0.38 } do
        addPart(
            model,
            "Eye",
            "Part",
            "Ball",
            Vector3.new(0.25, 0.3, 0.14),
            center,
            Vector3.new(eyeX, 0.18, eyeZ),
            Color3.fromRGB(249, 247, 230)
        )
        addPart(
            model,
            "Pupil",
            "Part",
            "Ball",
            Vector3.new(0.1, 0.14, 0.08),
            center,
            Vector3.new(eyeX, 0.16, eyeZ - 0.095),
            Color3.fromRGB(36, 44, 52)
        )
    end

    addPart(
        model,
        "FootLeft",
        "Part",
        "Ball",
        Vector3.new(0.58, 0.28, 0.68),
        center,
        Vector3.new(-0.52, -bodySize.Y / 2 + 0.03, -0.1),
        accentColor
    )
    addPart(
        model,
        "FootRight",
        "Part",
        "Ball",
        Vector3.new(0.58, 0.28, 0.68),
        center,
        Vector3.new(0.52, -bodySize.Y / 2 + 0.03, -0.1),
        accentColor
    )

    local silhouettePart =
        addSpeciesSilhouette(model, center, speciesVisual.silhouette, accentColor, bodySize)
    local focusPart = silhouettePart or body
    if recipe ~= nil and formId ~= nil and form ~= nil then
        model:SetAttribute("EffectRecipe", recipe.effect)
        focusPart = addMutationDetail(model, center, formId, recipe, bodySize)
        local effect = VisualDefinitions.Effects[recipe.effect]
        if form.tier == "Uncommon" then
            record.animatedPart = focusPart
            if effect ~= nil then
                record.effectHeight = effect.bobHeight
                record.effectDuration = effect.bobDuration
            end
        elseif form.tier == "Rare" or form.tier == "Mythic" then
            local highlight = Instance.new("Highlight")
            highlight.Name = "MutationAura"
            highlight.Adornee = model
            highlight.FillColor = accentColor
            highlight.OutlineColor = accentColor
            highlight.FillTransparency = if form.tier == "Mythic"
                then (if effect ~= nil then effect.mythicFillTransparency else nil) or 0.84
                else (if effect ~= nil then effect.rareFillTransparency else nil) or 0.93
            highlight.OutlineTransparency = if form.tier == "Mythic"
                then (if effect ~= nil then effect.mythicOutlineTransparency else nil) or 0.12
                else (if effect ~= nil then effect.rareOutlineTransparency else nil) or 0.46
            highlight.DepthMode = Enum.HighlightDepthMode.Occluded
            highlight.Parent = model
            record.highlight = highlight
        end
    end

    addInspectionLabel(body, speciesId, formId)
    model.Parent = localFolder
    record.model = model
    applyRecordEffects(record)
    return model
end

local function clearRecord(record: any)
    destroyModel(record)
    if record.display.Parent ~= nil then
        record.display.LocalTransparencyModifier = 0
    end
end

local function refreshRecord(record: any)
    local creatureId = record.display:GetAttribute("CreatureId")
    local speciesId = record.display:GetAttribute("SpeciesId")
    local formId = record.display:GetAttribute("MutationFormId")
    local signature =
        table.concat({ tostring(creatureId), tostring(speciesId), tostring(formId) }, "|")
    if record.signature == signature then
        return
    end
    destroyModel(record)
    record.signature = signature
    if type(creatureId) ~= "string" or type(speciesId) ~= "string" then
        record.display.LocalTransparencyModifier = 0
        return
    end
    record.display.LocalTransparencyModifier = 1
    if buildModel(record, speciesId, if type(formId) == "string" then formId else nil) == nil then
        record.display.LocalTransparencyModifier = 0
    end
end

local function unwatchDisplay(display: BasePart)
    local record = records[display]
    if record == nil then
        return
    end
    for _, connection in record.connections do
        connection:Disconnect()
    end
    clearRecord(record)
    records[display] = nil
end

local function watchDisplay(display: BasePart)
    if records[display] ~= nil then
        return
    end
    local record = { display = display, connections = {}, model = nil, signature = nil }
    records[display] = record
    for _, attributeName in { "CreatureId", "SpeciesId", "MutationFormId" } do
        table.insert(
            record.connections,
            display:GetAttributeChangedSignal(attributeName):Connect(function()
                refreshRecord(record)
            end)
        )
    end
    table.insert(
        record.connections,
        display.Destroying:Connect(function()
            unwatchDisplay(display)
        end)
    )
    refreshRecord(record)
end

local function isCreatureDisplay(instance: Instance): boolean
    return instance:IsA("BasePart") and string.match(instance.Name, "^CreatureDisplay%d%d$") ~= nil
end

function controller.setReducedEffects(enabled: boolean)
    if type(enabled) ~= "boolean" then
        return
    end
    reducedEffects = enabled
    for _, record in records do
        applyRecordEffects(record)
    end
end

function controller.start(): boolean
    if started then
        return true
    end
    local blockout = Workspace:WaitForChild("OddlingsBlockout", 30)
    if blockout == nil then
        return false
    end
    local folder = Instance.new("Folder")
    folder.Name = "OddlingsLocalCreaturePresentation"
    folder.Parent = Workspace
    localFolder = folder
    started = true

    for _, descendant in blockout:GetDescendants() do
        if isCreatureDisplay(descendant) then
            watchDisplay(descendant :: BasePart)
        end
    end
    table.insert(
        connections,
        blockout.DescendantAdded:Connect(function(descendant)
            if isCreatureDisplay(descendant) then
                watchDisplay(descendant :: BasePart)
            end
        end)
    )
    return true
end

function controller.stop()
    for _, connection in connections do
        connection:Disconnect()
    end
    table.clear(connections)
    for display in records do
        unwatchDisplay(display)
    end
    if localFolder ~= nil then
        localFolder:Destroy()
        localFolder = nil
    end
    started = false
end

return table.freeze(controller)
