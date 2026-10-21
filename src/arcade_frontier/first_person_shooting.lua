local Preferences=require("src.arcade_frontier.local_preferences")
local WeaponViews=require("src.arcade_frontier.first_person_weapon_views")
local WeaponActions=require("src.arcade_frontier.first_person_weapon_actions")
local WeaponManifest=require("src.arcade_frontier.first_person_weapon_manifest")
local MobileAim=require("src.arcade_frontier.mobile_weapon_aim")
local Items=require("src.arcade_frontier.item_instances")

local Shooting={}
local viewCache
local SoundProfiles=require("src.arcade_frontier.weapon_sound_profiles")
local sounds={}

local NON_FIREARM_AMMO={
    arrows=true,
    rocks=true,
    ["ball-bearings"]=true,
}

local function firearmStats(name,Catalog)
    local stats=name and Catalog.weaponCombat and Catalog.weaponCombat[name]
    if not stats or stats.kind~="ranged" or not stats.ammo or NON_FIREARM_AMMO[stats.ammo] then return nil end
    return stats
end

function Shooting.playerWeapon(data,Catalog)
    data=data or {}
    local fallback
    for _,entry in ipairs(Items.weapons(data,Catalog)) do
        local stats=firearmStats(entry.name,Catalog)
        if stats and entry.durability>0 then
            fallback=fallback or entry
            if math.max(0,tonumber(data.ammo and data.ammo[stats.ammo]) or 0)>0 then return entry.name,entry.id end
        end
    end
    if fallback then return fallback.name,fallback.id end
end

function Shooting.hasUsableFirearm(data,Catalog)
    local name=Shooting.playerWeapon(data,Catalog)
    local stats=firearmStats(name,Catalog)
    return stats and math.max(0,tonumber(data.ammo and data.ammo[stats.ammo]) or 0)>0 or false
end

local function totalRounds(state,data,quest)
    if state.borrowed then return math.max(0,math.floor(tonumber(quest.loanAmmo) or 0)) end
    return math.max(0,math.floor(tonumber(data.ammo and data.ammo[state.ammoType]) or 0))
end

local function stagedTubeReload(profile)
    return profile and (profile.style=="tubeLever" or profile.style=="pumpTube")
end

local function configure(state,name,stats,borrowed,data,quest,itemId)
    state.weapon=name
    state.itemId=itemId
    state.ammoType=stats and stats.ammo or "22lr"
    state.capacity=math.max(1,math.floor(tonumber(stats and stats.capacity) or 1))
    state.borrowed=borrowed==true
    state.magazine=math.min(state.capacity,totalRounds(state,data,quest))
    state.reloadTimer=0
    state.cooldown=0
    if not WeaponManifest.fireModeValid(name,state.fireMode) then state.fireMode="single" end
    WeaponActions.finish(state)
end

function Shooting.new(data,Catalog,quest,width,height)
    local saved=quest.weaponSession
    if type(saved)=="table" and firearmStats(saved.weapon,Catalog) then
        local owned=saved.borrowed and quest.loanActive
        if not saved.borrowed then
            local selector=Items.enabled(data) and saved.itemId or saved.weapon
            local entry=Items.selection(data,selector,Catalog)
            owned=entry and entry.name==saved.weapon
        end
        local durability=saved.borrowed and 100 or Items.condition(data,saved.itemId or saved.weapon)
        if owned and durability>0 then
            saved.capacity=Catalog.weaponCombat[saved.weapon].capacity or 1
            saved.ammoType=Catalog.weaponCombat[saved.weapon].ammo
            saved.magazine=math.max(0,math.min(tonumber(saved.magazine) or 0,saved.capacity,totalRounds(saved,data,quest)))
            saved.ads=false
            saved.touchAim=nil
            saved.fireHeld=false
            saved.fireHeldSources={}
            if not WeaponManifest.fireModeValid(saved.weapon,saved.fireMode) then saved.fireMode="single" end
            return saved
        end
    end
    local state={
        aimX=(width or 960)/2,
        aimY=(height or 720)/2,
        weaponX=(width or 960)*.68,
        weaponY=(height or 720)*.70,
        ads=false,
        cooldown=0,
        reloadTimer=0,
    }
    local name,itemId=Shooting.playerWeapon(data,Catalog)
    local stats=firearmStats(name,Catalog)
    local rounds=stats and math.max(0,tonumber(data.ammo and data.ammo[stats.ammo]) or 0) or 0
    if stats and rounds>0 then
        configure(state,name,stats,false,data,quest,itemId)
    elseif quest.loanActive and math.max(0,tonumber(quest.loanAmmo) or 0)>0 then
        local loanStats=assert(firearmStats("frontier-22-lever-rifle",Catalog))
        configure(state,"frontier-22-lever-rifle",loanStats,true,data,quest)
    elseif stats then
        configure(state,name,stats,false,data,quest,itemId)
    end
    quest.weaponSession=state
    return state
end

function Shooting.useLoan(state,data,Catalog,quest)
    return Shooting.chooseWeapon(state,{name="frontier-22-lever-rifle",borrowed=true},data,Catalog,quest)
end

function Shooting.weaponOptions(data,Catalog)
    local result={}
    for _,entry in ipairs(Items.weapons(data,Catalog)) do
        if firearmStats(entry.name,Catalog) and entry.durability>0 then
            result[#result+1]={name=entry.name,itemId=entry.id,ref=entry.ref,borrowed=false}
        end
    end
    table.sort(result,function(a,b) return a.name==b.name and (a.itemId or "")<(b.itemId or "") or a.name<b.name end)
    result[#result+1]={name="frontier-22-lever-rifle",borrowed=true}
    return result
end

function Shooting.chooseWeapon(state,option,data,Catalog,quest)
    local allowed=false
    for _,entry in ipairs(Shooting.weaponOptions(data,Catalog)) do
        if entry.name==option.name and entry.borrowed==option.borrowed and entry.itemId==option.itemId then allowed=true end
    end
    if not allowed then return state end
    quest.weaponSessions=quest.weaponSessions or {}
    if state.weapon then quest.weaponSessions[state.borrowed and "loan" or state.itemId or state.weapon]=state end
    local key=option.borrowed and "loan" or option.itemId or option.name
    local selected=quest.weaponSessions[key]
    local supplied=false
    if option.borrowed and (quest.loanAmmo or 0)<=0 then
        quest.loanAmmo=quest.loanActive and 12 or 48
        supplied=true
    end
    if option.borrowed then quest.loanActive=true end
    if not selected then
        selected={aimX=state.aimX,aimY=state.aimY,weaponX=state.weaponX,weaponY=state.weaponY,ads=false}
        configure(selected,option.name,firearmStats(option.name,Catalog),option.borrowed,data,quest,option.itemId)
        quest.weaponSessions[key]=selected
    end
    selected.aimX,selected.aimY=state.aimX,state.aimY
    selected.ads=state.ads
    selected.touchAim=state.touchAim
    MobileAim.refresh(selected,selected.weapon,selected.ads and "sights" or "hip")
    if supplied then selected.magazine=math.min(selected.capacity,totalRounds(selected,data,quest)) end
    selected.magazine=math.min(selected.magazine,totalRounds(selected,data,quest))
    quest.weaponSession=selected
    return selected
end

function Shooting.playReport(name,Catalog,data,distant)
    if not love.audio then return end
    local profile=SoundProfiles.forWeapon(name,Catalog)
    if sounds[profile.path]==nil then
        local path=profile.path
        if love.filesystem and not love.filesystem.getInfo(path) then
            local stem=path:gsub("%.[^./]+$","")
            for _,extension in ipairs({".ogg",".mp3",".wav",".flac"}) do
                local candidate=stem..extension
                if love.filesystem.getInfo(candidate) then path=candidate; break end
            end
        end
        local ok,source=pcall(love.audio.newSource,path,"static")
        sounds[profile.path]=ok and source or false
    end
    local source=sounds[profile.path]
    if source then
        source:stop()
        source:setPitch(profile.pitch*(distant and .92 or 1))
        local volume=tonumber(data and Preferences.audio(data) and Preferences.audio(data).sfxVolume) or .55
        source:setVolume((profile.volume or .8)*volume*(distant and .22 or 1))
        source:play()
    end
end

function Shooting.release()
    if viewCache then viewCache:release(); viewCache=nil end
    for _,source in pairs(sounds) do
        if source then
            pcall(source.stop,source)
            pcall(source.release,source)
        end
    end
    sounds={}
end

function Shooting.rounds(state,data,quest)
    if not state or not state.weapon then return 0 end
    return totalRounds(state,data,quest)
end

function Shooting.needsSupply(state,data,quest)
    return not state.weapon or (state.magazine<=0 and totalRounds(state,data,quest)<=0)
end

function Shooting.setAim(state,x,y)
    state.touchAim=nil
    if type(x)=="number" then state.aimX=x end
    if type(y)=="number" then state.aimY=y end
end

function Shooting.setTouchAim(state,x,y,width,height)
    MobileAim.set(state,x,y,state.weapon,state.ads and "sights" or "hip",width,height)
end

function Shooting.setADS(state,value)
    state.ads=value==true
    MobileAim.refresh(state,state.weapon,state.ads and "sights" or "hip")
end

function Shooting.fireModes(name)
    return WeaponManifest.fireModesFor(name)
end

function Shooting.cycleFireMode(state,direction)
    if not state or not state.weapon then return nil end
    local modes=WeaponManifest.fireModesFor(state.weapon)
    if #modes<2 then return nil end
    local selected=1
    for index,mode in ipairs(modes) do if mode==state.fireMode then selected=index; break end end
    selected=((selected-1+(direction or 1))%#modes)+1
    state.fireMode=modes[selected]
    state.fireHeld=false
    state.fireHeldSources={}
    return state.fireMode
end

function Shooting.reload(state,data,quest)
    if not state.borrowed and Items.enabled(data) then
        local item=Items.owned(data,state.itemId)
        if not item or item.name~=state.weapon then return false end
    end
    if not state.borrowed and Items.condition(data,state.itemId or state.weapon)<=0 then return false end
    if not state.weapon or state.reloadTimer>0 or totalRounds(state,data,quest)<=0 then return false end
    local profile=WeaponManifest.reloadProfileFor(state.weapon)
    local rounds
    if stagedTubeReload(profile) then
        local target=math.min(state.capacity,totalRounds(state,data,quest))
        if profile.style=="pumpTube" then
            rounds=target-math.max(0,tonumber(state.magazine) or 0)
            if rounds<=0 then return false end
        else
            if target<=(tonumber(state.magazine) or 0) then return false end
            rounds=target
        end
    end
    state.reloadTimer=WeaponActions.reloadDuration(state,rounds)
    WeaponActions.beginReload(state,rounds)
    if profile and profile.style=="tubeLever" and rounds then state.magazine=0 end
    return true
end

function Shooting.fire(state,data,quest)
    if state.fireMode=="safe" then return false,"safe" end
    if not state.weapon or state.reloadTimer>0 or state.cooldown>0 then return false,"busy" end
    if not state.borrowed and Items.enabled(data) then
        local item=Items.owned(data,state.itemId)
        if not item or item.name~=state.weapon then return false,"ownership" end
    end
    if not state.borrowed and Items.condition(data,state.itemId or state.weapon)<=0 then return false,"broken" end
    if totalRounds(state,data,quest)<=0 then return false,"empty" end
    if state.magazine<=0 then return false,totalRounds(state,data,quest)>0 and "reload" or "empty" end
    state.magazine=state.magazine-1
    if state.borrowed then
        quest.loanAmmo=math.max(0,(tonumber(quest.loanAmmo) or 0)-1)
    else
        data.ammo=data.ammo or {}
        data.ammo[state.ammoType]=math.max(0,(tonumber(data.ammo[state.ammoType]) or 0)-1)
    end
    state.cooldown=WeaponManifest.fireCooldownFor(state.weapon,state.fireMode)
    WeaponActions.beginFire(state)
    return true
end

function Shooting.update(state,dt,data,quest,width,height)
    WeaponActions.update(state,dt)
    state.cooldown=math.max(0,(state.cooldown or 0)-dt)
    if state.reloadTimer and state.reloadTimer>0 then
        local tubeReload=state.tubeReloadTotalRounds~=nil
        if tubeReload then
            local inserted=WeaponActions.consumeTubeRounds(state)
            for _=1,inserted do
                local target=math.min(state.capacity,totalRounds(state,data,quest))
                if state.magazine<target then state.magazine=state.magazine+1 end
            end
        end
        state.reloadTimer=math.max(0,state.reloadTimer-dt)
        if state.reloadTimer==0 then
            if not tubeReload then
                state.magazine=math.min(state.capacity,totalRounds(state,data,quest))
            end
            WeaponActions.finish(state)
        end
    end
end

local function ensureViews()
    if viewCache then return viewCache end
    viewCache=WeaponViews.new(
        function(file)
            local ok,image=pcall(love.graphics.newImage,file)
            return ok and image or nil
        end,
        function(file) return love.filesystem.getInfo(file)~=nil end,
        function(...) return love.graphics.newQuad(...) end
    )
    return viewCache
end

local function fallbackWeapon(state)
    love.graphics.setColor(.16,.12,.09,.95)
    love.graphics.polygon("fill",
        state.weaponX-120,state.weaponY+35,
        state.weaponX+85,state.weaponY-25,
        state.weaponX+150,state.weaponY+5,
        state.weaponX-105,state.weaponY+70)
    love.graphics.setColor(.72,.49,.24,1)
    love.graphics.rectangle("fill",state.weaponX-75,state.weaponY+48,80,42,8,8)
end

function Shooting.draw(state,width,height)
    if not state or not state.weapon then return end
    love.graphics.push("all")
    local views=ensureViews()
    local image=views:get(state.weapon,state.ads and "sights" or "hip")
    if not image then fallbackWeapon(state); love.graphics.pop(); return end
    local iw,ih=image:getDimensions()
    local maxWidth=state.ads and width*1.03 or width*.80
    local maxHeight=state.ads and height*.94 or height*.84
    local scale=math.min(maxWidth/iw,maxHeight/ih)
    local actionImage,actionQuad,actionWidth,actionHeight,adsFrame
    if state.ads and state.weaponAction~="reload" then
        adsFrame=WeaponActions.adsFrameIndex(state)
        actionImage,actionQuad,actionWidth,actionHeight=views:adsActionFrame(state.weapon,adsFrame)
    else
        local frame=WeaponActions.frameIndex(state)
        actionImage,actionQuad,actionWidth,actionHeight=views:actionFrame(state.weapon,frame)
    end
    love.graphics.setColor(1,1,1,1)
    if actionImage then
        if state.ads and state.weaponAction~="reload" then
            local place=MobileAim.adsActionPlacement(state.weapon,state.aimX,state.aimY,width,height,
                actionWidth,actionHeight,width*1.03,height*.94,adsFrame)
            if place then love.graphics.draw(actionImage,actionQuad,place.x,place.y,0,place.scale,place.scale) end
        else
            local place=MobileAim.placement(state.weapon,"hip","hip",state.aimX,state.aimY,width,height)
            local actionScale=place.height/actionHeight
            love.graphics.draw(actionImage,actionQuad,
                place.gripX-place.gripAnchor.x*actionWidth*actionScale,
                place.gripY-place.gripAnchor.y*actionHeight*actionScale,0,actionScale,actionScale)
        end
    elseif state.ads then
        if state.touchAim then
            local place=MobileAim.placement(state.weapon,"sights","sights",state.aimX,state.aimY,width,height)
            love.graphics.draw(image,place.x,place.y,0,place.width/iw,place.height/ih)
        else
            local anchor=views:anchor(state.weapon)
            local x=state.aimX-iw*scale*anchor.x
            local y=state.aimY-ih*scale*anchor.y
            love.graphics.draw(image,x,y,0,scale,scale)
        end
    else
        local mode=state.ads and "sights" or "hip"
        local place=MobileAim.placement(state.weapon,mode,mode,state.aimX,state.aimY,width,height)
        love.graphics.draw(image,place.x,place.y,0,place.width/iw,place.height/ih)
    end
    love.graphics.pop()
end

return Shooting
