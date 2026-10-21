local Profiles={}

local gunshots={
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/385811__morganpurkis__single-pistol-gunshot-3.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/391328__morganpurkis__single-pistol-gunshot-4.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/391846__morganpurkis__single-pistol-gunshot-42.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/392229__morganpurkis__single-pistol-gunshot-33.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/427594__michorvath__22-magnum-pistol-shot.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/718174__tb0y298__pistol-shot-1.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/718965__tb0y298__pistol-shot-2.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/147901__tcawte__gunshot.mp3",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/171236__alukahn__gunshot2.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/569174__coolabc__makarov-shoot.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/773867__mrgungus__gunshot-4.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/427598__michorvath__ar15-pistol-shot.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/gunshot/615028__zreimbach__designed-gunshot.wav",
}

local releases={
    "assets/generated/frontier-arcade/sounds/soundEffects/bow/179996__calvarychurchatlanta__arrow-release-and-hit.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/bow/394179__saturdaysoundguy__longbow-release-2.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/bow/536068__eminyildirim__bow-release-hit.wav",
    "assets/generated/frontier-arcade/sounds/soundEffects/bow/649335__sonofxaudio__arrow_loose01.wav",
}

-- Stable ordering gives every current ranged weapon a repeatable recording and
-- tone. New weapons still receive a deterministic fallback below.
local rangedOrder={
    "scrap-boomerang","hunting-bow","trail-slingshot","critter-crossbow",
    "scrap-pistol","sawed-off-shotgun","frontier-lever-rifle","compact-scrap-pistol",
    "long-barrel-22-pistol","heavy-frontier-pistol","machine-pistol","weathered-lever-rifle",
    "improvised-service-rifle","compact-carbine","rugged-submachine-gun","wrist-braced-slingshot",
    "metal-scrap-slingshot","long-hunting-slingshot","patched-22-survival-rifle","improvised-556-rifle",
    "frontier-long-barrel-revolver","frontier-22-lever-rifle","frontier-45-1911","frontier-380-revolver",
    "frontier-long-22-target-pistol","wood-stock-survival-carbine","vintage-bolt-action-rifle","frontier-556-carbine",
    "frontier-9mm-smg","frontier-22-target-pistol","frontier-380-pocket-pistol","frontier-12g-pump-shotgun",
    "frontier-762-carbine","frontier-sr22-pistol","frontier-9mm-service-pistol","frontier-compact-9mm",
    "frontier-32-pocket-pistol","frontier-22-pocket-pistol","frontier-silver-22-revolver","frontier-ak-compact",
    "frontier-9mm-glock","frontier-pearl-pocket-pistol","frontier-silver-compact-pistol","frontier-compact-9mm-pistol",
    "frontier-single-shot-hunter","frontier-lever-carbine",
}

local order={}
for index,name in ipairs(rangedOrder) do order[name]=index end

local overrides={
    ["frontier-22-target-pistol"]={path=gunshots[5],pitch=1.12,volume=.78,label="Crisp .22 pistol"},
    ["frontier-22-lever-rifle"]={path=gunshots[5],pitch=.96,volume=.86,label="Long .22 rifle"},
}

local function hash(value)
    local result=7
    for index=1,#(value or "") do result=(result*31+value:byte(index))%104729 end
    return result
end

local function projectileRelease(name,combat)
    local lower=(name or ""):lower()
    return lower:find("bow",1,true) or lower:find("slingshot",1,true) or lower:find("boomerang",1,true)
        or (combat and combat.ammo=="arrows")
end

function Profiles.forWeapon(name,catalog)
    if overrides[name] then return overrides[name] end
    local combat=catalog and catalog.weaponCombat and catalog.weaponCombat[name]
    local index=order[name] or (hash(name)%97+1)
    local pool=projectileRelease(name,combat) and releases or gunshots
    local source=pool[((index-1)%#pool)+1]
    local pitch=.86+(((index-1)%29)*.01)
    local volume=.72+(((index-1)%7)*.025)
    return {path=source,pitch=pitch,volume=volume,label="Assigned weapon report"}
end

function Profiles.audit(catalog)
    local assigned,missing=0,{}
    for name,combat in pairs(catalog.weaponCombat or {}) do
        if combat.kind=="ranged" then
            local profile=Profiles.forWeapon(name,catalog)
            if profile and profile.path and profile.pitch then assigned=assigned+1 else missing[#missing+1]=name end
        end
    end
    table.sort(missing)
    return {assigned=assigned,missing=missing,prototypePistol=Profiles.forWeapon("frontier-22-target-pistol",catalog),prototypeRifle=Profiles.forWeapon("frontier-22-lever-rifle",catalog)}
end

return Profiles
