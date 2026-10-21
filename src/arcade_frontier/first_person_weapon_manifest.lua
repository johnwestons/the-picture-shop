local Manifest={}

local ROOT="assets/generated/frontier-arcade/assets/sprites/weapons/first-person/"
local DEFAULT_ADS_ANCHOR={x=.5,y=.35,calibrated=false}

-- ADS action sheet aim points use each weapon's calibrated sight anchor;
-- weapons with a separately measured firing-sheet point override it here.
local ADS_ACTION_ANCHORS={
    ["frontier-45-1911"]={x=.53,y=.26,calibrated=true},
    ["vintage-bolt-action-rifle"]={x=.5,y=.20,calibrated=true},
    ["frontier-sr22-pistol"]={x=.5,y=.20,calibrated=true},
    ["frontier-compact-9mm"]={x=.5,y=.18,calibrated=true},
    ["frontier-380-pocket-pistol"]={x=.5,y=.26,calibrated=true},
    ["frontier-pearl-pocket-pistol"]={x=.5,y=.27,calibrated=true},
    ["frontier-22-target-pistol"]={x=.5,y=.28,calibrated=true},
    ["heavy-frontier-pistol"]={x=.5,y=.27,calibrated=true},
    ["frontier-long-barrel-revolver"]={x=.5,y=.25,calibrated=true},
    ["frontier-lever-rifle"]={x=.5,y=.24,calibrated=true},
    ["wood-stock-survival-carbine"]={x=.53,y=.29,calibrated=true},
    ["frontier-lever-carbine"]={x=.5,y=.27,calibrated=true},
    ["rugged-submachine-gun"]={x=.5,y=.19,calibrated=true},
    ["sawed-off-shotgun"]={x=.515,y=.323,calibrated=true},
    ["machine-pistol"]={x=.5,y=.33,calibrated=true},
    ["frontier-9mm-service-pistol"]={x=.5,y=.15,calibrated=true},
    ["frontier-9mm-glock"]={x=.5,y=.13,calibrated=true},
    ["frontier-762-carbine"]={x=.5,y=.26,calibrated=true},
    ["patched-22-survival-rifle"]={x=.5,y=.20,calibrated=true},
    ["compact-carbine"]={x=.5,y=.25,calibrated=true},
    ["improvised-556-rifle"]={x=.5,y=.22,calibrated=true},
    ["improvised-service-rifle"]={x=.5,y=.24,calibrated=true},
}
local ADS_ACTION_FRAME_ANCHORS={
    -- The generated flash cell sits slightly left of the ready pose. Pin its
    -- iron-sight/bore line to the same reticle point during the shot.
    ["frontier-45-1911"]={[2]={x=.47,y=.26,calibrated=true}},
    ["sawed-off-shotgun"]={[2]={x=.498,y=.323,calibrated=true}},
}

local AUTOMATIC_WEAPONS={
    ["compact-carbine"]=true,
    ["frontier-556-carbine"]=true,
    ["frontier-9mm-smg"]=true,
    ["frontier-ak-compact"]=true,
    ["improvised-556-rifle"]=true,
    ["improvised-service-rifle"]=true,
    ["machine-pistol"]=true,
    ["rugged-submachine-gun"]=true,
}

local RELOAD_DURATIONS={
    magazine=1.15,
    revolver=1.65,
    lever=1.35,
    tubeLever=5.24,
    pumpTube=1.55,
    sksStripperClip=1.55,
    bolt=1.28,
    pump=1.50,
    breakAction=1.42,
    singleShot=1.32,
}

-- The inner tube is pulled out, its full available load goes in one round at a time,
-- then the tube is reseated and locked: .35 + 12*.38 + .33 = 5.24 seconds.
local TUBE_LEVER_RELOAD_TIMING={startSeconds=.35,roundSeconds=.38,finishSeconds=.33}

local function reloadStyleFor(id)
    if id=="frontier-762-carbine" then return "sksStripperClip" end
    if id=="frontier-12g-pump-shotgun" then return "pumpTube" end
    if id=="frontier-22-lever-rifle" then return "tubeLever" end
    if id:find("revolver",1,true) then return "revolver" end
    if id=="scrap-pistol" then return "singleShot" end
    if id=="sawed-off-shotgun" then return "breakAction" end
    if id:find("pump-shotgun",1,true) then return "pump" end
    if id:find("lever",1,true) then return "lever" end
    if id:find("bolt-action",1,true) then return "bolt" end
    if id:find("single-shot",1,true) then return "singleShot" end
    return "magazine"
end

-- Keep an entry uncalibrated until its production PNG has been checked against
-- the in-game reticle. The renderer can use the safe default without presenting
-- that default as weapon-specific sight data.

local function path(file)
    return ROOT..file
end

local function pair(id,anchor)
    local reloadStyle=reloadStyleFor(id)
    local modes={"safe","single"}
    if AUTOMATIC_WEAPONS[id] then modes[#modes+1]="auto" end
    local rapid=AUTOMATIC_WEAPONS[id]
    return {
        kind="firearm",
        views={
            hip=path(id.."-hip.png"),
            sights=path(id.."-sights.png"),
        },
        actionAtlas=ROOT.."actions/"..id.."-actions.png",
        adsActionAtlas=ROOT.."actions/"..id.."-ads-fire.png",
        adsAnchor=anchor,
        adsActionAnchor=ADS_ACTION_ANCHORS[id] or anchor,
        adsActionFrameAnchors=ADS_ACTION_FRAME_ANCHORS[id],
        fireModes=modes,
        fireCooldown=rapid and .18 or .27,
        autoCooldown=rapid and (id:find("smg",1,true) or id:find("submachine",1,true)
            or id=="machine-pistol") and .10 or .12,
        reloadStyle=reloadStyle,
        reloadSeconds=RELOAD_DURATIONS[reloadStyle],
    }
end

local function special(id,states,hipState,sightsState,anchor,shotSequence)
    local views={}
    for state,file in pairs(states) do views[state]=path(file) end
    views.hip=assert(views[hipState],id.." requires a hip state")
    views.sights=assert(views[sightsState],id.." requires an aimed state")
    return {kind="special",views=views,adsAnchor=anchor,shotSequence=shotSequence}
end

Manifest.weapons={
    ["frontier-22-lever-rifle"]=pair("frontier-22-lever-rifle",{x=.498455,y=.159358,calibrated=true}),
    ["frontier-sr22-pistol"]=pair("frontier-sr22-pistol",{x=.500000,y=.127592,calibrated=true}),
    ["frontier-22-pocket-pistol"]=pair("frontier-22-pocket-pistol",{x=.500000,y=.251196,calibrated=true}),
    ["frontier-compact-9mm"]=pair("frontier-compact-9mm",{x=.500000,y=.114833,calibrated=true}),
    ["frontier-silver-22-revolver"]=pair("frontier-silver-22-revolver",{x=.500000,y=.106771,calibrated=true}),
    ["frontier-32-pocket-pistol"]=pair("frontier-32-pocket-pistol",{x=.500000,y=.188995,calibrated=true}),
    ["frontier-380-pocket-pistol"]=pair("frontier-380-pocket-pistol",{x=.499554,y=.202423,calibrated=true}),
    ["frontier-pearl-pocket-pistol"]=pair("frontier-pearl-pocket-pistol",{x=.500000,y=.139323,calibrated=true}),
    ["frontier-silver-compact-pistol"]=pair("frontier-silver-compact-pistol",{x=.500000,y=.230463,calibrated=true}),
    ["frontier-compact-9mm-pistol"]=pair("frontier-compact-9mm-pistol",{x=.500000,y=.259968,calibrated=true}),
    ["frontier-45-1911"]=pair("frontier-45-1911",{x=.500000,y=.126953,calibrated=true}),
    ["frontier-9mm-service-pistol"]=pair("frontier-9mm-service-pistol",{x=.500000,y=.114833,calibrated=true}),
    ["frontier-9mm-glock"]=pair("frontier-9mm-glock",{x=.500000,y=.083732,calibrated=true}),
    ["frontier-22-target-pistol"]=pair("frontier-22-target-pistol",{x=.500000,y=.074960,calibrated=true}),
    ["frontier-380-revolver"]=pair("frontier-380-revolver",{x=.500000,y=.261719,calibrated=true}),
    ["long-barrel-22-pistol"]=pair("long-barrel-22-pistol",{x=.500000,y=.238260,calibrated=true}),
    ["heavy-frontier-pistol"]=pair("heavy-frontier-pistol",{x=.499023,y=.113932,calibrated=true}),
    ["frontier-long-barrel-revolver"]=pair("frontier-long-barrel-revolver",{x=.498047,y=.138672,calibrated=true}),
    ["frontier-long-22-target-pistol"]=pair("frontier-long-22-target-pistol",{x=.500000,y=.214844,calibrated=true}),
    ["frontier-lever-rifle"]=pair("frontier-lever-rifle",{x=.494141,y=.183594,calibrated=true}),
    ["wood-stock-survival-carbine"]=pair("wood-stock-survival-carbine",{x=.499023,y=.173828,calibrated=true}),
    ["vintage-bolt-action-rifle"]=pair("vintage-bolt-action-rifle",{x=.490741,y=.283508,calibrated=true}),
    ["frontier-12g-pump-shotgun"]=pair("frontier-12g-pump-shotgun",{x=.500977,y=.141276,calibrated=true}),
    ["frontier-762-carbine"]=pair("frontier-762-carbine",{x=.500000,y=.223958,calibrated=true}),
    ["weathered-lever-rifle"]=pair("weathered-lever-rifle",{x=.499023,y=.211589,calibrated=true}),
    ["patched-22-survival-rifle"]=pair("patched-22-survival-rifle",{x=.497069,y=.168655,calibrated=true}),
    ["frontier-lever-carbine"]=pair("frontier-lever-carbine",{x=.495117,y=.214193,calibrated=true}),
    ["compact-carbine"]=pair("compact-carbine",{x=.496395,y=.196296,calibrated=true}),
    ["frontier-556-carbine"]=pair("frontier-556-carbine",{x=.497070,y=.145182,calibrated=true}),
    ["improvised-556-rifle"]=pair("improvised-556-rifle",{x=.500000,y=.142230,calibrated=true}),
    ["improvised-service-rifle"]=pair("improvised-service-rifle",{x=.499511,y=.210150,calibrated=true}),
    ["frontier-9mm-smg"]=pair("frontier-9mm-smg",{x=.499436,y=.143179,calibrated=true}),
    ["frontier-ak-compact"]=pair("frontier-ak-compact",{x=.500000,y=.138672,calibrated=true}),
    ["frontier-single-shot-hunter"]=pair("frontier-single-shot-hunter",{x=.500000,y=.186198,calibrated=true}),
    ["scrap-pistol"]=pair("scrap-pistol",{x=.500000,y=.162679,calibrated=true}),
    ["compact-scrap-pistol"]=pair("compact-scrap-pistol",{x=.500000,y=.231260,calibrated=true}),
    ["sawed-off-shotgun"]=pair("sawed-off-shotgun",{x=.500000,y=.091,calibrated=true}),
    ["machine-pistol"]=pair("machine-pistol",{x=.500000,y=.092504,calibrated=true}),
    ["rugged-submachine-gun"]=pair("rugged-submachine-gun",{x=.500424,y=.101949,calibrated=true}),

    -- The user-approved full-draw master is the only production bow view for
    -- now. Earlier low-ready, nocked, partial-draw, and release attempts were
    -- explicitly rejected, so both runtime poses intentionally share it until
    -- matching states are derived from that master.
    ["hunting-bow"]=special("hunting-bow",{
        fullDraw="hunting-bow-full-draw-aim.png",
    },"fullDraw","fullDraw",{x=.490431,y=.456938,calibrated=true}),
    ["critter-crossbow"]=special("critter-crossbow",{
        lowReady="critter-crossbow-low-ready.png",
        uncocked="critter-crossbow-uncocked.png",
        cocked="critter-crossbow-cocked.png",
        loadedAim="critter-crossbow-bolt-loaded-aim.png",
        release="critter-crossbow-release.png",
    },"lowReady","loadedAim",{x=.500000,y=.155212,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="uncocked",placement="hip"},
        },
    }),
    ["trail-slingshot"]=special("trail-slingshot",{
        lowReady="trail-slingshot-low-ready.png",
        loaded="trail-slingshot-loaded.png",
        fullDraw="trail-slingshot-full-draw-aim.png",
        release="trail-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.326954,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["wrist-braced-slingshot"]=special("wrist-braced-slingshot",{
        lowReady="wrist-braced-slingshot-low-ready.png",
        loaded="wrist-braced-slingshot-loaded.png",
        fullDraw="wrist-braced-slingshot-full-draw-aim.png",
        release="wrist-braced-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.199362,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["metal-scrap-slingshot"]=special("metal-scrap-slingshot",{
        lowReady="metal-scrap-slingshot-low-ready.png",
        loaded="metal-scrap-slingshot-loaded.png",
        fullDraw="metal-scrap-slingshot-full-draw-aim.png",
        release="metal-scrap-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.223285,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["long-hunting-slingshot"]=special("long-hunting-slingshot",{
        lowReady="long-hunting-slingshot-low-ready.png",
        loaded="long-hunting-slingshot-loaded.png",
        fullDraw="long-hunting-slingshot-full-draw-aim.png",
        release="long-hunting-slingshot-release-band-return.png",
    },"loaded","fullDraw",{x=.500000,y=.117188,calibrated=true},{
        steps={
            {state="release",duration=.12,placement="hip"},
            {state="lowReady",placement="hip"},
        },
    }),
    ["scrap-boomerang"]=special("scrap-boomerang",{
        ready="scrap-boomerang-ready-throw.png",
        flight="scrap-boomerang-flight-spin.png",
        returning="scrap-boomerang-return-approach.png",
    },"ready","ready",nil,{
        steps={
            {state="flight",duration=.28,placement="hip"},
            {state="returning",duration=.34,placement="hip"},
            {state="ready",duration=.08,placement="hip"},
        },
        restoresLoaded=true,
    }),
}

local function validAnchor(anchor)
    return type(anchor)=="table" and type(anchor.x)=="number" and type(anchor.y)=="number"
        and anchor.x>=0 and anchor.x<=1 and anchor.y>=0 and anchor.y<=1
        and type(anchor.calibrated)=="boolean"
end

function Manifest.anchorFor(name)
    local entry=Manifest.weapons[name]
    local anchor=entry and entry.adsAnchor
    if validAnchor(anchor) then return {x=anchor.x,y=anchor.y},anchor.calibrated==true end
    return {x=DEFAULT_ADS_ANCHOR.x,y=DEFAULT_ADS_ANCHOR.y},false
end

function Manifest.calibrationSummary()
    local result={calibrated=0,provisional=0,withoutAnchor=0}
    for _,entry in pairs(Manifest.weapons) do
        local anchor=entry.adsAnchor
        if validAnchor(anchor) then
            if anchor.calibrated then result.calibrated=result.calibrated+1
            else result.provisional=result.provisional+1 end
        else
            result.withoutAnchor=result.withoutAnchor+1
        end
    end
    return result
end

function Manifest.shotSequenceFor(name)
    local entry=Manifest.weapons[name]
    return entry and entry.shotSequence or nil
end

function Manifest.actionAtlasFor(name)
    local entry=Manifest.weapons[name]
    return entry and entry.actionAtlas or nil
end

function Manifest.adsActionAtlasFor(name)
    local entry=Manifest.weapons[name]
    return entry and entry.adsActionAtlas or nil
end

function Manifest.adsActionAnchorFor(name,frame)
    local entry=Manifest.weapons[name]
    local frameAnchor=entry and entry.adsActionFrameAnchors and entry.adsActionFrameAnchors[frame]
    local anchor=frameAnchor or (entry and entry.adsActionAnchor)
    if validAnchor(anchor) then return {x=anchor.x,y=anchor.y},anchor.calibrated==true end
    return Manifest.anchorFor(name)
end

function Manifest.fireModesFor(name)
    local entry=Manifest.weapons[name]
    local result={}
    for index,mode in ipairs(entry and entry.fireModes or {}) do result[index]=mode end
    return result
end

function Manifest.fireModeValid(name,mode)
    for _,candidate in ipairs(Manifest.fireModesFor(name)) do
        if candidate==mode then return true end
    end
    return false
end

function Manifest.fireCooldownFor(name,mode)
    local entry=Manifest.weapons[name]
    if not entry then return .27 end
    return mode=="auto" and (entry.autoCooldown or entry.fireCooldown or .27)
        or (entry.fireCooldown or .27)
end

function Manifest.reloadProfileFor(name)
    local entry=Manifest.weapons[name]
    if not entry or entry.kind~="firearm" then return nil end
    local profile={style=entry.reloadStyle,duration=entry.reloadSeconds}
    if entry.reloadStyle=="tubeLever" then
        profile.startSeconds=TUBE_LEVER_RELOAD_TIMING.startSeconds
        profile.roundSeconds=TUBE_LEVER_RELOAD_TIMING.roundSeconds
        profile.finishSeconds=TUBE_LEVER_RELOAD_TIMING.finishSeconds
    end
    return profile
end

local function validateShotSequence(name,entry,issues)
    local sequence=entry.shotSequence
    if sequence==nil then return end
    if type(sequence)~="table" or type(sequence.steps)~="table" or #sequence.steps==0 then
        issues[#issues+1]=name.." has an invalid shot sequence"
        return
    end
    if sequence.restoresLoaded~=nil and type(sequence.restoresLoaded)~="boolean" then
        issues[#issues+1]=name.." has an invalid restoresLoaded flag"
    end
    for index,step in ipairs(sequence.steps) do
        if type(step)~="table" or type(step.state)~="string" or not entry.views[step.state] then
            issues[#issues+1]=name.." shot sequence step "..index.." has no matching view"
        elseif step.placement~="hip" and step.placement~="sights" then
            issues[#issues+1]=name.." shot sequence step "..index.." has an invalid placement"
        elseif step.duration~=nil and (type(step.duration)~="number" or step.duration<=0) then
            issues[#issues+1]=name.." shot sequence step "..index.." has an invalid duration"
        elseif index<#sequence.steps and step.duration==nil then
            issues[#issues+1]=name.." shot sequence step "..index.." cannot hold before the final step"
        end
    end
end

function Manifest.validate()
    local issues={}
    for name,entry in pairs(Manifest.weapons) do
        if type(name)~="string" or name=="" then issues[#issues+1]="invalid weapon id"
        elseif type(entry)~="table" or type(entry.views)~="table" then issues[#issues+1]=name.." has no views"
        else
            for _,state in ipairs({"hip","sights"}) do
                if type(entry.views[state])~="string" or entry.views[state]=="" then
                    issues[#issues+1]=name.." has no "..state.." view"
                end
            end
            for state,file in pairs(entry.views) do
                if type(state)~="string" or type(file)~="string" or not file:match("%.png$") then
                    issues[#issues+1]=name.." has an invalid view entry"
                end
            end
            if entry.adsAnchor~=nil and not validAnchor(entry.adsAnchor) then
                issues[#issues+1]=name.." has an invalid ADS anchor"
            end
            if entry.kind=="firearm" then
                if type(entry.actionAtlas)~="string" or not entry.actionAtlas:match("%-actions%.png$") then
                    issues[#issues+1]=name.." has no action sprite atlas"
                end
                if type(entry.adsActionAtlas)~="string" or not entry.adsActionAtlas:match("%-ads%-fire%.png$") then
                    issues[#issues+1]=name.." has no ADS firing sprite atlas"
                end
                if entry.adsActionAnchor~=nil and not validAnchor(entry.adsActionAnchor) then
                    issues[#issues+1]=name.." has an invalid ADS firing anchor"
                end
                for frame,anchor in pairs(entry.adsActionFrameAnchors or {}) do
                    if type(frame)~="number" or frame<1 or frame>4 or frame%1~=0 or not validAnchor(anchor) then
                        issues[#issues+1]=name.." has an invalid ADS firing frame anchor"
                    end
                end
                if type(entry.fireModes)~="table" or entry.fireModes[1]~="safe" or entry.fireModes[2]~="single"
                    or (#entry.fireModes>2 and entry.fireModes[3]~="auto") or #entry.fireModes>3 then
                    issues[#issues+1]=name.." has invalid fire selector modes"
                end
                if type(entry.reloadStyle)~="string" or type(entry.reloadSeconds)~="number" or entry.reloadSeconds<=0 then
                    issues[#issues+1]=name.." has an invalid reload sprite profile"
                end
            end
            validateShotSequence(name,entry,issues)
        end
    end
    return #issues==0,issues
end

return Manifest
