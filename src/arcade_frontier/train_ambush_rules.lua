-- Serializable encounter state. Rendering and input never own rewards or costs.
local Shooting=require("src.arcade_frontier.first_person_shooting")
local Rules={version=2,bribe=5,hideFood=2,hideWater=2,reward=5}

Rules.vehicleDefs={
    pickup={id="pickup",title="Bandit Pickup",art="pickup-damage.png",cellW=543,cellH=340,sourceY=200,
        hull=18,crewHealth=3,crewCount=2,protection=24,damageScale=1,distance="near"},
    wagon={id="wagon",title="Scrap Wagon",art="bandit-wagon-damage.png",cellW=768,cellH=512,sourceY=0,
        hull=14,crewHealth=2,crewCount=2,protection=14,damageScale=.85,distance="far"},
    cargo={id="cargo",title="Cargo War Rig",art="bandit-cargo-truck-damage.png",cellW=768,cellH=512,sourceY=0,
        hull=26,crewHealth=2,crewCount=2,protection=18,damageScale=1.1,distance="far"},
}
Rules.pickup=Rules.vehicleDefs.pickup

local durations={peek=.35,aim=1.4,fire=.18,duck=.3,hit=.32,hidden=2.3}
local nextPhase={hidden="peek",peek="aim",aim="fire",fire="duck",duck="hidden",hit="hidden"}
local damageByAmmo={['22lr']=1,['32-acp']=1.15,['380-acp']=1.3,['9mm']=1.55,
    ['45-cal']=1.8,['30-carbine']=2.05,['556']=2.25,['762x39']=2.55,['8mm']=2.75,['12-gauge']=3}

function Rules.canFight(data,catalog)
    return Shooting.hasUsableFirearm(data,catalog) and (tonumber(data.health) or 0)>1
end

function Rules.wear(data,amount)
    data.maintenance=data.maintenance or {}
    local m=data.maintenance
    local before=tonumber(m.condition) or 72
    m.condition=math.max(0,before-amount)
    m.totalWear=(tonumber(m.totalWear) or 0)+(before-m.condition)
    return before-m.condition
end

function Rules.hide(data)
    data.resources=data.resources or {}
    local food=math.min(Rules.hideFood,data.resources.food or 0)
    local water=math.min(Rules.hideWater,data.resources.water or 0)
    data.resources.food=(data.resources.food or 0)-food
    data.resources.water=(data.resources.water or 0)-water
    local wear=Rules.wear(data,(Rules.hideFood-food+Rules.hideWater-water)*4)
    return string.format("The pickup passes. Spent %d food and %d water. Train condition lost: %d.",food,water,wear)
end

local function crewFor(def,firstTimer)
    local crew={}
    for i=1,def.crewCount do
        crew[i]={hp=def.crewHealth,phase="hidden",timer=(firstTimer or .8)+(i-1)*1.35}
    end
    return crew
end

local function vehicleFor(def,old)
    old=old or {}
    local motion=old.motion or {}
    local queued=def.distance=="far" and old.active==false
    return {id=def.id,title=def.title,art=def.art,cellW=def.cellW,cellH=def.cellH,sourceY=def.sourceY,
        distance=def.distance,damageScale=def.damageScale,hull=tonumber(old.hull) or def.hull,maxHull=def.hull,
        protection=tonumber(old.protection) or def.protection,maxProtection=def.protection,
        hullHits=tonumber(old.hullHits) or 0,crewHits=tonumber(old.crewHits) or 0,
        crew=old.crew or crewFor(def),disabled=(tonumber(old.hull) or def.hull)<=0,
        active=old.active~=false and not queued,
        motion={phase=motion.phase or (queued and "queued" or "approach"),clock=tonumber(motion.clock) or 0,
            matchClock=tonumber(motion.matchClock) or 0}}
end

local function migrateLegacy(state)
    local def=Rules.vehicleDefs.pickup
    local old={hull=state.hull,hullHits=state.hullHits,protection=state.protection,crew=state.crew}
    local pickup=vehicleFor(def,old)
    pickup.maxHull=state.maxHull or pickup.maxHull
    pickup.maxProtection=state.maxProtection or pickup.maxProtection
    state.vehicles={pickup}
    state.bulletHoles=state.bulletHoles or {}
    state.version=Rules.version
end

function Rules.start(data)
    local current=data.trainAmbush
    if current and current.active then
        if not current.vehicles then migrateLegacy(current) end
        return current
    end
    local pickup=vehicleFor(Rules.vehicleDefs.pickup,{},true)
    local wagon=vehicleFor(Rules.vehicleDefs.wagon,{},true)
    local cargo=vehicleFor(Rules.vehicleDefs.cargo,{active=false},false)
    wagon.crew=crewFor(Rules.vehicleDefs.wagon,1.25)
    cargo.crew=crewFor(Rules.vehicleDefs.cargo,1.8)
    local state={version=Rules.version,active=true,location=data.location,phase="approach",phaseClock=0,clock=0,
        vehicles={cargo,wagon,pickup},hull=pickup.hull,maxHull=pickup.maxHull,protection=pickup.protection,
        maxProtection=pickup.maxProtection,cover=false,coverProgress=0,shots=0,crewHits=0,hullHits=0,
        trainDamage=0,playerDamage=0,bulletHoles={},activeFar="wagon"}
    data.trainAmbush=state
    return state
end

function Rules.vehicle(state,id)
    if not state or not state.vehicles then return nil end
    for _,vehicle in ipairs(state.vehicles) do if vehicle.id==id then return vehicle end end
end

function Rules.aliveCrew(vehicle)
    local count=0
    for _,member in ipairs(vehicle.crew or {}) do if member.hp>0 then count=count+1 end end
    return count
end

function Rules.hullTotal(state)
    local total,max=0,0
    for _,vehicle in ipairs(state.vehicles or {}) do total=total+math.max(0,vehicle.hull); max=max+(vehicle.maxHull or vehicle.hull) end
    return total,max
end

function Rules.crewTotal(state)
    local count=0
    for _,vehicle in ipairs(state.vehicles or {}) do count=count+Rules.aliveCrew(vehicle) end
    return count
end

local function ease(t)
    t=math.max(0,math.min(1,t))
    return t*t*(3-2*t)
end

function Rules.motionOffset(vehicle)
    local motion=vehicle and vehicle.motion
    if not motion then return 0 end
    if motion.phase=="queued" or motion.phase=="gone" then return 1.05 end
    if motion.phase=="approach" then return 1.05*(1-ease(motion.clock/1.5)) end
    if motion.phase=="departLeft" then return -1.05*ease(motion.clock/1.5) end
    if motion.phase=="departRight" then return 1.05*ease(motion.clock/1.5) end
    return 0
end

local function beginDeparture(state,vehicle,left)
    if not vehicle or not vehicle.motion or vehicle.motion.phase=="gone" then return end
    if vehicle.motion.phase=="departLeft" or vehicle.motion.phase=="departRight" then return end
    vehicle.motion.phase=left and "departLeft" or "departRight"
    vehicle.motion.clock=0
    vehicle.motion.matchClock=0
    vehicle.active=true
end

local function nextFarVehicle(state)
    for _,vehicle in ipairs(state.vehicles or {}) do
        if vehicle.distance=="far" and vehicle.motion and vehicle.motion.phase=="queued" and vehicle.hull>0 then
            return vehicle
        end
    end
end

local function completeDeparture(state,vehicle)
    vehicle.active=false
    vehicle.motion.phase="gone"
    vehicle.motion.clock=0
    if vehicle.distance=="far" and state.activeFar==vehicle.id then
        local next=nextFarVehicle(state)
        if next then
            next.active=true
            next.motion.phase="approach"
            next.motion.clock=0
            next.motion.matchClock=0
            state.activeFar=next.id
        else
            state.activeFar=nil
        end
    end
end

local function updateMotion(state,vehicle,dt)
    local motion=vehicle.motion
    if not motion or motion.phase=="queued" or motion.phase=="gone" then return false end
    motion.clock=motion.clock+dt
    if motion.phase=="approach" and motion.clock>=1.5 then
        motion.phase="matched"
        motion.clock=0
        motion.matchClock=0
        return true
    elseif (motion.phase=="departLeft" or motion.phase=="departRight") and motion.clock>=1.5 then
        completeDeparture(state,vehicle)
        return true
    end
    return false
end

local function allHullDown(state)
    local any=false
    for _,vehicle in ipairs(state.vehicles or {}) do any=true; if vehicle.hull>0 then return false end end
    return any
end

local function allCrewDown(state)
    local any=false
    for _,vehicle in ipairs(state.vehicles or {}) do any=true; if Rules.aliveCrew(vehicle)>0 then return false end end
    return any
end

local function allVehiclesCleared(state)
    for _,vehicle in ipairs(state.vehicles or {}) do
        if vehicle.motion and vehicle.motion.phase~="gone" and vehicle.motion.phase~="queued" then return false end
        if vehicle.motion and vehicle.motion.phase=="queued" and vehicle.hull>0 then return false end
    end
    return true
end

function Rules.finish(data,state,outcome)
    if state.outcome then return false end
    state.outcome=outcome
    state.phase="depart"
    state.phaseClock=0
    state.cover=true
    state.reward=0
    for _,vehicle in ipairs(state.vehicles or {}) do
        if vehicle.active and vehicle.motion and vehicle.motion.phase=="matched" then
            beginDeparture(state,vehicle,outcome=="escaped")
        end
    end
    if outcome=="disabled" or outcome=="crew" then
        state.reward=Rules.reward
        data.scrap=(data.scrap or 0)+state.reward
    end
    local receipt=data.events and data.events[tostring(state.location)]
    if receipt and receipt.id=="rail-bandits" then
        receipt.outcome=outcome; receipt.reward=state.reward; receipt.resolved=true
    end
    return true
end

function Rules.withdraw(data,state)
    if state.outcome then return false end
    local lost=Rules.wear(data,6)
    state.trainDamage=state.trainDamage+lost
    return Rules.finish(data,state,"withdrawn")
end

function Rules.vehicleStage(vehicle)
    if vehicle.hull<=0 then return 4 end
    if vehicle.hull<=vehicle.maxHull/3 then return 3 end
    if vehicle.hull<=vehicle.maxHull*2/3 then return 2 end
    return 1
end

function Rules.damageStage(state)
    return Rules.vehicleStage(Rules.vehicle(state,"pickup") or {hull=state.hull,maxHull=state.maxHull})
end

function Rules.exposed(crew)
    return crew.hp>0 and (crew.phase=="peek" or crew.phase=="aim" or crew.phase=="fire" or crew.phase=="hit")
end

local function addBulletHole(state,target,vehicle)
    if not target or target.x==nil or target.y==nil then return end
    state.bulletHoles=state.bulletHoles or {}
    state.bulletHoles[#state.bulletHoles+1]={vehicle=vehicle.id,x=target.x,y=target.y,variant=((vehicle.hullHits-1)%4)+1}
    if #state.bulletHoles>48 then table.remove(state.bulletHoles,1) end
end

function Rules.hit(data,state,target,gun)
    if state.phase~="combat" or state.coverProgress>0 or state.cover then return false end
    local damage=(damageByAmmo[gun.ammoType] or 1)
    local kind,vehicle,index
    if type(target)=="number" then kind="crew"; vehicle=Rules.vehicle(state,"pickup"); index=target
    elseif target=="hull" then kind="hull"; vehicle=Rules.vehicle(state,"pickup")
    elseif type(target)=="table" then kind=target.kind; vehicle=Rules.vehicle(state,target.vehicle or "pickup"); index=target.index end
    if not vehicle then return false end
    if vehicle.active==false or not vehicle.motion or vehicle.motion.phase=="queued" or vehicle.motion.phase=="gone" then return false end
    if kind=="crew" then
        local crew=vehicle.crew[index]
        if not crew or not Rules.exposed(crew) then return false end
        crew.hp=math.max(0,crew.hp-damage)
        crew.phase=crew.hp>0 and "hit" or "down"
        crew.timer=durations.hit
        vehicle.crewHits=(vehicle.crewHits or 0)+1
        state.crewHits=state.crewHits+1
        if Rules.aliveCrew(vehicle)==0 then beginDeparture(state,vehicle,false) end
        if allCrewDown(state) then Rules.finish(data,state,"crew") end
        return true
    elseif kind=="hull" then
        damage=damage*(vehicle.damageScale or 1)
        vehicle.hull=math.max(0,vehicle.hull-damage)
        vehicle.hullHits=(vehicle.hullHits or 0)+1
        vehicle.disabled=vehicle.hull<=0
        state.hullHits=state.hullHits+1
        addBulletHole(state,target,vehicle)
        if vehicle.id=="pickup" then state.hull=vehicle.hull end
        if vehicle.hull<=vehicle.maxHull/3 then beginDeparture(state,vehicle,true) end
        if allHullDown(state) then Rules.finish(data,state,"disabled")
        elseif allCrewDown(state) then Rules.finish(data,state,"crew") end
        return true
    end
    return false
end

function Rules.update(data,state,dt,onEnemyFire)
    state.clock=state.clock+dt
    state.phaseClock=state.phaseClock+dt
    local step=dt/.16
    state.coverProgress=state.cover and math.min(1,state.coverProgress+step) or math.max(0,state.coverProgress-step)
    local motionChanged=false
    for _,vehicle in ipairs(state.vehicles or {}) do
        if vehicle.active and updateMotion(state,vehicle,dt) then motionChanged=true end
    end
    if state.phase=="approach" then
        if state.phaseClock>=1.5 then state.phase="combat"; state.phaseClock=0; return true end
        return motionChanged
    elseif state.phase=="depart" then
        if state.phaseClock>=2 then state.phase="result"; state.phaseClock=0; return true end
    elseif state.phase=="combat" then
        local changed=motionChanged
        for _,vehicle in ipairs(state.vehicles or {}) do
            if vehicle.active and vehicle.hull>0 and vehicle.motion and vehicle.motion.phase=="matched" then
                if vehicle.distance=="far" then
                    vehicle.motion.matchClock=vehicle.motion.matchClock+dt
                    if vehicle.motion.matchClock>=4.5 then
                        beginDeparture(state,vehicle,false)
                        changed=true
                    end
                end
                for index,crew in ipairs(vehicle.crew or {}) do
                    if crew.hp>0 then
                        crew.timer=crew.timer-dt
                        if crew.timer<=0 then
                            crew.phase=nextPhase[crew.phase] or "hidden"
                            crew.timer=durations[crew.phase]
                            changed=true
                            if crew.phase=="fire" then
                                vehicle.protection=math.max(0,vehicle.protection-2)
                                state.protection=math.max(0,state.protection-2)
                                state.trainDamage=state.trainDamage+Rules.wear(data,1)
                                local handled=onEnemyFire and onEnemyFire(vehicle.id,index)
                                if not handled and state.coverProgress<1 then
                                    local before=data.health or 20
                                    data.health=math.max(1,before-2)
                                    state.playerDamage=state.playerDamage+before-data.health
                                end

                                if (data.health or 20)<=1 or state.protection<=0 then
                                    Rules.finish(data,state,"overrun")
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
        if allHullDown(state) then Rules.finish(data,state,"disabled")
        elseif allCrewDown(state) then Rules.finish(data,state,"crew")
        elseif allVehiclesCleared(state) then Rules.finish(data,state,"escaped") end
        return changed
    end
    return false
end

return Rules
