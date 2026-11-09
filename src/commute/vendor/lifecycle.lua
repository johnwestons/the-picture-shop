-- Age is in biological days. Thresholds/scales are prototype tuning, not
-- precise biological growth curves.
local M=require('src.commute.vendor.mathx')
local Life={START_AGE=21}
Life.stages={
    {id='newborn',label='NEWBORN',age=0,ageLabel='BIRTH',sprite='newborn',size=.24,
        description='Highly dependent on care, while free to explore.'},
    {id='nestling',label='NESTLING',age=21,ageLabel='21 DAYS',sprite='nestling',sizeAge=21,
        description='Small and vulnerable, with frequent needs.'},
    {id='juvenile',label='JUVENILE',age=35,ageLabel='35 DAYS',sprite='juvenile',sizeAge=90,
        description='Growing independence and stronger movement.'},
    {id='adult',label='ADULT',age=180,ageLabel='180 DAYS',sprite='adult',sizeAge=180,
        description='Full-grown with balanced survival abilities.'},
    {id='elder',label='ELDER',age=1095,ageLabel='3+ YEARS',sprite='elder',sizeAge=1095,
        description='Experienced, though movement begins to slow.'},
}
function Life.animalStage(age)
    if age<21 then return 'Newborn',1 elseif age<35 then return 'Nestling',2 elseif age<180 then return 'Juvenile',3
    elseif age<1095 then return 'Adult',4 else return 'Older adult',5 end
end
function Life.animalScale(age)
    if age<21 then return .24+.33*M.smooth(age/21) end
    return .57+.43*M.smooth((age-21)/159)
end
function Life.art(age) return age<90 and 'baby_' or '' end
local function curve(age,values)
    if age<=Life.stages[1].age then return values[1] end
    for i=2,#Life.stages do
        local left,right=Life.stages[i-1],Life.stages[i]
        if age<=right.age then
            local t=M.smooth((age-left.age)/(right.age-left.age))
            return M.lerp(values[i-1],values[i],t)
        end
    end
    return values[#values]
end
function Life.movementFactor(age) return curve(age or Life.START_AGE,{.42,.58,.78,1,.86}) end
function Life.needFactor(age) return curve(age or Life.START_AGE,{1.45,1.24,1.10,1,1.12}) end
function Life.biteIntervalFactor(age) return curve(age or Life.START_AGE,{1.35,1,1,.90,1.02}) end
function Life.staminaCostFactor(age) return curve(age or Life.START_AGE,{1.4,1.2,1.1,1,1.22}) end
function Life.staminaRecoveryFactor(age) return curve(age or Life.START_AGE,{.68,.82,.92,1,.78}) end
function Life.randomAge(seed,id)
    local band=math.min(3,math.floor(M.hash(seed+5151,id,11)*4))
    local ranges={{21,34},{35,179},{180,1094},{1095,1825}}
    return math.floor(M.lerp(ranges[band+1][1],ranges[band+1][2],M.hash(seed+6161,id,31)))
end
Life.plants={oak={365*15,365*90},pine={365*8,365*60},bramble={180,365*6},
    sumac={365,365*12},strawberry={60,365*3},grass={45,365*2},
    redbud={365*4,365*65},blueberry={365*3,365*18},milkweed={365*2,365*12},
    dogwood={365*5,365*55},persimmon={365*8,365*70},['chickasaw-plum']={365*3,365*18},
    ['little-bluestem']={60,365*8},['blue-phlox']={120,365*5},
    bloodroot={365*2,365*20},['virginia-bluebells']={365,365*12},
    ['wild-columbine']={365,365*8},['purple-coneflower']={365*2,365*12},
    ['wild-bergamot']={365*2,365*10},['cardinal-flower']={365*2,365*8},
    ['new-england-aster']={365*2,365*12},['common-goldenrod']={365*2,365*12}}
function Life.plantAge(seed,id,kind)
    local profile=Life.plants[kind];if not profile then return nil end
    return math.floor(M.hash(seed+719,id,23)*profile[2])
end
function Life.plantStage(kind,age)
    local p=Life.plants[kind];if not p then return nil,1 end
    if age<p[1]*.3 then return 'Seedling',.38
    elseif age<p[1] then return 'Growing',.65
    elseif age<p[2]*.75 then return 'Mature',1
    else return 'Established',1.08 end
end
function Life.plantScale(prop,days)
    if not prop.age then return 1 end
    local _,scale=Life.plantStage(prop.kind,prop.plantAge or prop.age+(days or 0));return scale
end
function Life.visible(prop)
    if prop.lifePhase=='vacant' then return false end
    if prop.lifePhase=='dead' or prop.lifePhase=='decay' then return true end
    return not prop.edible or prop.amount>0
end
return Life
