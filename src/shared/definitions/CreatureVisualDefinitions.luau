-- Reusable creature silhouettes and palette metadata for the client presenter.

local function rgb(red: number, green: number, blue: number)
    return table.freeze({ red, green, blue })
end

local families = table.freeze({ "Round", "Winged", "Aquatic", "Tall" })

local species = {
    Mossling = {
        rigFamily = "Round",
        silhouette = "LeafNubs",
        body = rgb(116, 166, 113),
        accent = rgb(74, 114, 77),
    },
    TiffinToad = {
        rigFamily = "Round",
        silhouette = "KettleBack",
        body = rgb(86, 142, 120),
        accent = rgb(194, 151, 98),
    },
    PuddlePup = {
        rigFamily = "Aquatic",
        silhouette = "FloppyEars",
        body = rgb(111, 164, 197),
        accent = rgb(186, 222, 232),
    },
    ButtonBat = {
        rigFamily = "Winged",
        silhouette = "ButtonWings",
        body = rgb(101, 92, 140),
        accent = rgb(236, 227, 197),
    },
    NoodleFinch = {
        rigFamily = "Winged",
        silhouette = "RibbonTail",
        body = rgb(211, 160, 90),
        accent = rgb(243, 218, 137),
    },
    PebbleImp = {
        rigFamily = "Round",
        silhouette = "StoneBack",
        body = rgb(118, 119, 127),
        accent = rgb(82, 85, 94),
    },
    TeacupCrab = {
        rigFamily = "Aquatic",
        silhouette = "CupShell",
        body = rgb(210, 129, 106),
        accent = rgb(239, 206, 152),
    },
    StaticFinch = {
        rigFamily = "Winged",
        silhouette = "ZigzagPlume",
        body = rgb(105, 143, 181),
        accent = rgb(227, 239, 250),
    },
    VelvetGremlin = {
        rigFamily = "Round",
        silhouette = "OversizedEars",
        body = rgb(147, 99, 131),
        accent = rgb(222, 170, 199),
    },
    ClockworkCarp = {
        rigFamily = "Aquatic",
        silhouette = "SquareFins",
        body = rgb(194, 151, 79),
        accent = rgb(235, 204, 119),
    },
    LanternYak = {
        rigFamily = "Tall",
        silhouette = "LanternHorns",
        body = rgb(133, 101, 75),
        accent = rgb(249, 191, 86),
    },
    PocketHydra = {
        rigFamily = "Tall",
        silhouette = "ThreeHeads",
        body = rgb(88, 145, 145),
        accent = rgb(164, 219, 196),
    },
}

local function recipe(
    body: { number },
    accent: { number },
    material: string,
    silhouette: string,
    effect: string
)
    return table.freeze({
        body = rgb(body[1], body[2], body[3]),
        accent = rgb(accent[1], accent[2], accent[3]),
        material = material,
        silhouette = silhouette,
        effect = effect,
    })
end

local function effect(
    bobHeight: number?,
    bobDuration: number?,
    rareFillTransparency: number?,
    rareOutlineTransparency: number?,
    mythicFillTransparency: number?,
    mythicOutlineTransparency: number?
)
    return table.freeze({
        bobHeight = bobHeight,
        bobDuration = bobDuration,
        rareFillTransparency = rareFillTransparency,
        rareOutlineTransparency = rareOutlineTransparency,
        mythicFillTransparency = mythicFillTransparency,
        mythicOutlineTransparency = mythicOutlineTransparency,
    })
end

local effects = table.freeze({
    EmberGlow = effect(0.08, 1.8),
    Glimmer = effect(nil, nil),
    WarmPulse = effect(nil, nil),
    EmberTrail = effect(0.14, 1.2),
    SunRing = effect(nil, nil, 0.91, 0.38),
    OrbitStar = effect(nil, nil, nil, nil, 0.81, 0.12),
    ColorSweep = effect(nil, nil),
    SlowRibbon = effect(0.08, 2.4),
    ShortGlint = effect(0.06, 0.9),
    PrismAura = effect(nil, nil, 0.91, 0.34),
    PrismHalo = effect(nil, nil, nil, nil, 0.83, 0.1),
    SoftPollen = effect(nil, nil),
    PetalDrift = effect(0.13, 1.5),
    BogGlow = effect(0.05, 1.2),
    RootAura = effect(nil, nil, 0.92, 0.4),
    RootHalo = effect(nil, nil, nil, nil, 0.82, 0.14),
})

local mutations = {
    Cinder = recipe({ 61, 52, 52 }, { 239, 111, 53 }, "Slate", "Fissures", "EmberGlow"),
    Sparkcap = recipe({ 185, 91, 47 }, { 255, 197, 83 }, "SmoothPlastic", "Cap", "Glimmer"),
    Coalcoat = recipe({ 48, 48, 55 }, { 222, 115, 54 }, "Slate", "Mantle", "EmberGlow"),
    Toastbite = recipe(
        { 171, 117, 76 },
        { 242, 197, 120 },
        "SmoothPlastic",
        "ToastPatch",
        "WarmPulse"
    ),
    Flarefin = recipe({ 206, 98, 44 }, { 255, 177, 65 }, "SmoothPlastic", "FlameFin", "EmberTrail"),
    Hearthhorn = recipe({ 119, 65, 51 }, { 248, 147, 77 }, "Slate", "EmberHorns", "EmberGlow"),
    Sunheart = recipe({ 163, 119, 58 }, { 255, 226, 130 }, "Metal", "ChestCore", "SunRing"),
    Starforge = recipe({ 38, 42, 56 }, { 252, 195, 83 }, "Metal", "ForgePlates", "OrbitStar"),

    Glint = recipe(
        { 104, 151, 194 },
        { 239, 251, 255 },
        "SmoothPlastic",
        "PinHighlights",
        "Glimmer"
    ),
    Opalcoat = recipe(
        { 135, 116, 188 },
        { 205, 202, 245 },
        "SmoothPlastic",
        "OpalPanels",
        "ColorSweep"
    ),
    Shardtail = recipe({ 105, 140, 191 }, { 191, 231, 255 }, "Glass", "CrystalTail", "Glimmer"),
    Splitlight = recipe(
        { 114, 150, 190 },
        { 237, 186, 236 },
        "SmoothPlastic",
        "SplitPalette",
        "ColorSweep"
    ),
    Aurora = recipe({ 91, 146, 179 }, { 164, 228, 216 }, "Glass", "AuroraRibbon", "SlowRibbon"),
    Mirrorflash = recipe(
        { 113, 132, 179 },
        { 227, 246, 255 },
        "Metal",
        "MirrorPlate",
        "ShortGlint"
    ),
    Spectrum = recipe({ 117, 113, 171 }, { 246, 207, 248 }, "Neon", "SpectrumEdge", "PrismAura"),
    Paragon = recipe({ 95, 101, 175 }, { 232, 220, 255 }, "Glass", "FacetedCrown", "PrismHalo"),

    Sprout = recipe(
        { 97, 151, 94 },
        { 175, 219, 117 },
        "SmoothPlastic",
        "LeafSprouts",
        "SoftPollen"
    ),
    Puffcap = recipe(
        { 134, 171, 105 },
        { 229, 179, 183 },
        "SmoothPlastic",
        "MushroomCap",
        "SoftPollen"
    ),
    Lichen = recipe({ 111, 148, 87 }, { 170, 188, 112 }, "Slate", "LichenPatches", "SoftPollen"),
    Vinewrap = recipe(
        { 85, 142, 84 },
        { 164, 200, 108 },
        "SmoothPlastic",
        "VineBand",
        "SoftPollen"
    ),
    Bloomguard = recipe(
        { 104, 161, 105 },
        { 239, 190, 138 },
        "SmoothPlastic",
        "FlowerShield",
        "PetalDrift"
    ),
    Boglight = recipe({ 72, 145, 137 }, { 139, 235, 220 }, "Neon", "CyanSpots", "BogGlow"),
    Worldroot = recipe({ 92, 126, 74 }, { 168, 188, 116 }, "Slate", "RootCuffs", "RootAura"),
    VerdantCrown = recipe(
        { 68, 124, 72 },
        { 190, 236, 135 },
        "SmoothPlastic",
        "LeafCrown",
        "RootHalo"
    ),
}

for _, value in species do
    table.freeze(value)
end

return table.freeze({
    RigFamilies = families,
    Species = table.freeze(species),
    Mutations = table.freeze(mutations),
    Effects = effects,
})
