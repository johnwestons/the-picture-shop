-- Durable health rules. Entity records are independent of player rendering so
-- the same rules can later be applied to NPCs without enrolling them now.
local Medical={CRITICAL=10,EXPOSURE_HOURS=.5,RECOVERY_HOURS=12,FAINT_SECONDS=5,HOSPITAL_SECONDS=9}
local function finite(n,hi)return type(n)=='number' and n==n and n>=0 and n<=(hi or 1e12)end
function Medical.new()
    return {version=1,revision=0,exposure=0,wellHours=0,episodes=0,hospitalVisits=0,
        injury=0,crashCount=0,lastCrashHours=0,debtCents=0,lastBillCents=0,remaining=0}
end
function Medical.valid(m)
    if m==nil then return true end
    if type(m)~='table' or m.version~=1 then return false end
    for _,key in ipairs({'revision','episodes','hospitalVisits','crashCount','debtCents','lastBillCents'}) do
        if not finite(m[key]) or m[key]%1~=0 then return false end
    end
    return finite(m.exposure,24) and finite(m.wellHours,24) and finite(m.injury,100)
        and finite(m.lastCrashHours,24000024) and finite(m.remaining,60)
        and (m.phase==nil or m.phase=='faint' or m.phase=='rescue' or m.phase=='hospital')
        and (m.notice==nil or m.notice=='grandpa' or m.notice=='hospital' or m.notice=='faint')
end
function Medical.ensure(resident)
    resident.medical=resident.medical or Medical.new();return resident.medical
end
function Medical.get(state,player)
    local r=require('src.home_residents').get(state,player)
    return r and Medical.ensure(r),r
end
function Medical.blocked(state,player)
    local m=Medical.get(state,player);return m and m.phase~=nil or false
end
function Medical.speed(state,player)
    local m=Medical.get(state,player)
    return m and ((m.phase or m.notice) and 0 or m.injury>=30 and .5 or 1) or 1
end
function Medical.crash(resident,now)
    local m=Medical.ensure(resident)
    if now-m.lastCrashHours>24 then m.crashCount=0 end
    m.crashCount=m.crashCount+1;m.lastCrashHours=now
    if m.crashCount>=2 then m.injury=math.min(100,m.injury+35) end
    m.revision=m.revision+1;resident.revision=resident.revision+1
    return m.injury>=30
end
function Medical.advance(resident,hours,canFaint)
    local m=Medical.ensure(resident)
    if m.phase or m.notice or hours<0 then return false end
    local critical=0
    for _,key in ipairs({'hunger','thirst','energy'}) do
        if resident[key]<=Medical.CRITICAL then critical=critical+1 end
    end
    -- Poor hygiene increases the burden of deprivation, but never causes an
    -- otherwise well-fed and rested player to suddenly lose consciousness.
    if critical>0 then
        m.wellHours=0
        m.exposure=math.min(24,m.exposure+hours*(1+(critical-1)*.5+(resident.hygiene<10 and .25 or 0)))
    else
        m.exposure=math.max(0,m.exposure-hours*2)
        if resident.hunger>=40 and resident.thirst>=40 and resident.energy>=40 and resident.hygiene>=25 then
            m.wellHours=math.min(24,m.wellHours+hours)
            if m.wellHours>=Medical.RECOVERY_HOURS then m.episodes=0 end
        else m.wellHours=0 end
    end
    -- Accumulate strain in vehicles, but leave the episode pending until the
    -- actor is back on foot. Caring for their needs can avert a pending faint.
    if critical==0 or canFaint==false or m.exposure<Medical.EXPOSURE_HOURS then return false end
    m.exposure=0;m.episodes=m.episodes+1;m.revision=m.revision+1
    m.phase=m.episodes<=2 and 'faint' or m.episodes==3 and 'rescue' or 'hospital'
    m.remaining=m.phase=='hospital' and Medical.HOSPITAL_SECONDS or Medical.FAINT_SECONDS
    m.notice=nil;resident.activity=nil;resident.revision=resident.revision+1
    return true
end
function Medical.bill(state,resident)
    local m=Medical.ensure(resident)
    m.hospitalVisits=m.hospitalVisits+1
    m.lastBillCents=20000*m.hospitalVisits
    local paid=math.min(state.home.balanceCents,m.lastBillCents)
    state.home.balanceCents=state.home.balanceCents-paid
    m.debtCents=m.debtCents+m.lastBillCents-paid
    m.revision=m.revision+1;state.home.revision=state.home.revision+1
end
function Medical.recover(resident,kind)
    local m=Medical.ensure(resident)
    if kind~='faint' then
        for _,key in ipairs({'hunger','thirst','energy','hygiene'}) do resident[key]=math.max(resident[key],kind=='hospital' and 75 or 55) end
        if kind=='hospital' then m.injury=0;m.crashCount=0 end
    end
    m.phase=nil;m.remaining=0;m.notice=kind=='rescue' and 'grandpa' or kind
    m.exposure=0;m.revision=m.revision+1;resident.revision=resident.revision+1
end
function Medical.quote(resident)
    local m=Medical.ensure(resident);local deficiency=0
    for _,key in ipairs({'hunger','thirst','energy','hygiene'}) do deficiency=deficiency+(100-resident[key]) end
    return 2500+math.ceil(m.injury)*150+math.ceil(deficiency)*25+m.debtCents
end
function Medical.treat(state,player,revision,world,quotedPrice)
    local m,r=Medical.get(state,player)
    local trip=state.home.commute;local part=trip and trip.participants[require('src.home_residents').key(player)]
    local site=world and world.sites.byId.clinic
    local rider=part and part.rider
    if not m or m.phase or not rider or part.interior or player.sceneId~='commute' or not site
        or rider.gear.mounted or rider.vehicle or rider.ped.crash
        or (rider.ped.x-site.door.x)^2+(rider.ped.z-site.door.z)^2>3.6^2 then
        return false,'Dismount and walk to the Critter Clinic entrance.'
    end
    if m.revision~=revision then return false,'Your condition changed. Review the clinic quote again.' end
    local price=Medical.quote(r)
    if quotedPrice and quotedPrice~=price then return false,'Your condition changed. Review the clinic quote again.' end
    if state.home.balanceCents<price then return false,'Not enough household money for this visit and outstanding medical bills.' end
    state.home.balanceCents=state.home.balanceCents-price
    for _,key in ipairs({'hunger','thirst','energy','hygiene'}) do r[key]=100 end
    m.injury=0;m.crashCount=0;m.episodes=0;m.exposure=0;m.debtCents=0;m.wellHours=0;m.notice=nil
    m.revision=m.revision+1;r.revision=r.revision+1;state.home.revision=state.home.revision+1
    return true,('Clinic treatment complete: $%.2f. Eat, drink, rest, and ride carefully.'):format(price/100)
end
return Medical
