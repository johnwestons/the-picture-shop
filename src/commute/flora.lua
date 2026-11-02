-- Town-only lifecycle adapter. Rebuild each plant from its stable ID and the
-- business calendar; no wildlife feeding, per-plant saves or offscreen ticks.
local Catalog=require('src.commute.vendor.flora')
local Life=require('src.commute.vendor.lifecycle')
local Variants=require('src.commute.vendor.plant_variants')
local M=require('src.commute.vendor.mathx')
local Flora={catalog=Catalog}
Flora.scales={oak=.9,pine=.95,redbud=.9,dogwood=.9,persimmon=.9,
    blueberry=.42,milkweed=.18,['chickasaw-plum']=.38,['little-bluestem']=.15,['blue-phlox']=.18,
    bloodroot=.13,['virginia-bluebells']=.20,['wild-columbine']=.24,['purple-coneflower']=.23,
    ['wild-bergamot']=.19,['cardinal-flower']=.28,['new-england-aster']=.23,['common-goldenrod']=.20,
    bramble=.40,rock=.62,strawberry=.19,sumac=.42,grass=.14,log=.38,
    twig=.22,['leaf-litter']=.20,stone=.24}
Flora.canopy={oak=true,pine=true,redbud=true,dogwood=true,persimmon=true}
local tints={spring={.96,1.045,.94},summer={1,1,1},autumn={1.07,.98,.84},winter={.94,.98,1.04}}
local litter={spring=.25,summer=0,autumn=4,winter=1.7}
function Flora.season(calendar)
    local month=calendar and calendar.month or 5
    local season=(month==12 or month<=2) and 'winter' or month<=5 and 'spring' or month<=8 and 'summer' or 'autumn'
    return season,tints[season],litter[season]
end
function Flora.present(p,seed,calendar)
    local d=Catalog.types[p.kind]
    if not d then return p end
    local days=calendar and calendar.totalDays or 0
    local period=d.longevity+d.deadDays+d.decayDays+d.vacantDays
    local age=(Life.plantAge(seed,p.id,p.kind)+math.max(0,days))%period
    p.age=age;p.plantAge=math.min(age,d.longevity);p.lifePhase='live';p.phaseAge=0
    if age>=d.longevity+d.deadDays+d.decayDays then p.lifePhase='vacant';p.phaseAge=age-d.longevity-d.deadDays-d.decayDays
    elseif age>=d.longevity+d.deadDays then p.lifePhase='decay';p.phaseAge=age-d.longevity-d.deadDays
    elseif age>=d.longevity then p.lifePhase='dead';p.phaseAge=age-d.longevity end
    p.amount=1;p.biteAge=1000;p.edible=false;p.vigor=1
    p.drySite=M.hash(seed+419,p.id,29)<.25
    p.visualVariant=Variants.pick(seed,p.id,p.kind)
    return p
end
function Flora.scale(p)
    return (Flora.scales[p.kind] or 1)*Life.plantScale(p,0)
end
return Flora
