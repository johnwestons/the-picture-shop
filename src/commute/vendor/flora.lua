local M=require('src.commute.vendor.mathx')
local Life=require('src.commute.vendor.lifecycle')
local Flora={VERSION=1}
Flora.order={'strawberry','sumac','grass','bramble','oak','pine','redbud','blueberry','milkweed',
    'dogwood','persimmon','chickasaw-plum','little-bluestem','blue-phlox','bloodroot',
    'virginia-bluebells','wild-columbine','purple-coneflower','wild-bergamot','cardinal-flower',
    'new-england-aster','common-goldenrod'}
Flora.states={'seed','sprout','young','mature','flower','fruit','browsed','depleted','regrowth','dormant','dead','decay'}
Flora.phases={'live','dead','decay','vacant'}
Flora.types={
    strawberry={name='Wild strawberry',part='leaves',seed=2,sprout=8,
        regrow=.075,delay=.5,stress=.22,deadDays=3,decayDays=18,vacantDays=9,
        flowers={[4]=true,[5]=true},fruits={[6]=true},heatRest=true},
    sumac={name='Winged sumac',part='bark browse',seed=9,sprout=45,
        regrow=.018,delay=1,stress=.28,deadDays=30,decayDays=180,vacantDays=30,leafDrop=true,
        flowers={[7]=true,[8]=true},fruits={[9]=true,[10]=true,[11]=true}},
    grass={name='Virginia wildrye',part='grass',seed=3,sprout=12,
        regrow=.13,delay=.3,stress=.12,deadDays=4,decayDays=24,vacantDays=8,
        flowers={[6]=true,[7]=true},fruits={[8]=true,[9]=true,[10]=true},heatRest=true},
    bramble={name='Blackberry bramble',seed=9,sprout=60,
        regrow=.035,delay=1,stress=.2,deadDays=30,decayDays=150,vacantDays=24,leafDrop=true,
        flowers={[5]=true,[6]=true},fruits={[7]=true,[8]=true}},
    oak={name='White oak',seed=18,sprout=180,
        regrow=.005,delay=2,stress=.2,deadDays=365,decayDays=3650,vacantDays=75,leafDrop=true,
        flowers={[4]=true},fruits={[9]=true,[10]=true}},
    pine={name='Loblolly pine',seed=18,sprout=120,
        regrow=.005,delay=2,stress=.2,deadDays=270,decayDays=2555,vacantDays=60,evergreen=true,
        flowers={[3]=true,[4]=true},fruits={[10]=true,[11]=true}},
    redbud={name='Eastern redbud',seed=14,sprout=65,
        regrow=.006,delay=2,stress=.2,deadDays=365,decayDays=3650,vacantDays=90,leafDrop=true,
        flowers={[3]=true,[4]=true},fruits={[6]=true,[7]=true,[8]=true,[9]=true}},
    blueberry={name='Highbush blueberry',seed=5,sprout=35,
        regrow=.025,delay=.7,stress=.24,deadDays=60,decayDays=365,vacantDays=45,leafDrop=true,
        flowers={[4]=true,[5]=true},fruits={[6]=true,[7]=true,[8]=true,[9]=true}},
    milkweed={name='Butterfly milkweed',seed=3,sprout=14,
        regrow=.05,delay=.5,stress=.22,deadDays=90,decayDays=180,vacantDays=60,leafDrop=true,
        flowers={[5]=true,[6]=true,[7]=true},fruits={[8]=true,[9]=true}},
    dogwood={name='Flowering dogwood',part='bark browse',seed=14,sprout=70,
        regrow=.006,delay=2,stress=.2,deadDays=365,decayDays=3650,vacantDays=90,leafDrop=true,
        winterBrowse=true,foodMonths={[12]=true,[1]=true,[2]=true},authoredMotion=false,
        flowers={[4]=true,[5]=true},fruits={[8]=true,[9]=true,[10]=true}},
    persimmon={name='American persimmon',seed=16,sprout=180,
        regrow=.005,delay=2,stress=.2,deadDays=365,decayDays=3650,vacantDays=90,leafDrop=true,
        authoredMotion=false,winterFruit=true,flowers={[5]=true,[6]=true},fruits={[9]=true,[10]=true,[11]=true,[12]=true}},
    ['chickasaw-plum']={name='Chickasaw plum',part='plums and winter twigs',seed=6,sprout=35,
        regrow=.022,delay=.8,stress=.24,deadDays=30,decayDays=365,vacantDays=45,leafDrop=true,
        winterBrowse=true,authoredMotion=false,foodMonths={[5]=true,[6]=true,[7]=true},
        flowers={[3]=true,[4]=true},fruits={[5]=true,[6]=true,[7]=true}},
    ['little-bluestem']={name='Little bluestem',seed=3,sprout=20,
        regrow=.10,delay=.35,stress=.14,deadDays=8,decayDays=60,vacantDays=18,leafDrop=true,
        authoredMotion=false,
        flowers={[8]=true,[9]=true},fruits={[10]=true,[11]=true}},
    ['blue-phlox']={name='Blue phlox',part='leaves',seed=2,sprout=10,
        regrow=.085,delay=.4,stress=.15,deadDays=8,decayDays=60,vacantDays=14,leafDrop=true,
        authoredMotion=false,
        flowers={[4]=true,[5]=true},fruits={[6]=true,[7]=true,[8]=true,[9]=true}},
    bloodroot={name='Bloodroot',seed=1,sprout=12,
        regrow=.04,delay=.8,stress=.18,deadDays=12,decayDays=75,vacantDays=28,leafDrop=true,
        dormantMonths={[7]=true,[8]=true,[9]=true,[10]=true,[11]=true},authoredMotion=false,
        flowers={[3]=true,[4]=true},fruits={[4]=true,[5]=true}},
    ['virginia-bluebells']={name='Virginia bluebells',seed=2,sprout=18,
        regrow=.04,delay=.8,stress=.18,deadDays=12,decayDays=80,vacantDays=30,leafDrop=true,
        dormantMonths={[7]=true,[8]=true,[9]=true,[10]=true,[11]=true},authoredMotion=false,
        flowers={[3]=true,[4]=true,[5]=true},fruits={[5]=true,[6]=true}},
    ['wild-columbine']={name='Eastern wild columbine',seed=2,sprout=24,
        regrow=.045,delay=.8,stress=.18,deadDays=14,decayDays=90,vacantDays=30,leafDrop=true,
        authoredMotion=false,flowers={[3]=true,[4]=true,[5]=true},fruits={[6]=true,[7]=true,[8]=true}},
    ['purple-coneflower']={name='Purple coneflower',seed=3,sprout=28,
        regrow=.05,delay=.8,stress=.18,deadDays=16,decayDays=110,vacantDays=36,leafDrop=true,
        authoredMotion=false,flowers={[6]=true,[7]=true,[8]=true},fruits={[9]=true,[10]=true,[11]=true}},
    ['wild-bergamot']={name='Wild bergamot',seed=3,sprout=28,
        regrow=.05,delay=.8,stress=.18,deadDays=16,decayDays=100,vacantDays=32,leafDrop=true,
        authoredMotion=false,flowers={[6]=true,[7]=true,[8]=true,[9]=true},fruits={[9]=true,[10]=true}},
    ['cardinal-flower']={name='Cardinal flower',seed=3,sprout=30,
        regrow=.045,delay=.9,stress=.20,deadDays=18,decayDays=110,vacantDays=36,leafDrop=true,
        authoredMotion=false,flowers={[7]=true,[8]=true,[9]=true,[10]=true},fruits={[10]=true,[11]=true}},
    ['new-england-aster']={name='New England aster',seed=3,sprout=32,
        regrow=.05,delay=.8,stress=.18,deadDays=18,decayDays=120,vacantDays=38,leafDrop=true,
        authoredMotion=false,flowers={[8]=true,[9]=true,[10]=true},fruits={[11]=true,[12]=true}},
    ['common-goldenrod']={name='Common goldenrod',seed=3,sprout=32,
        regrow=.05,delay=.8,stress=.18,deadDays=18,decayDays=120,vacantDays=38,leafDrop=true,
        authoredMotion=false,flowers={[8]=true,[9]=true,[10]=true,[11]=true},fruits={[12]=true}},
}
-- Contact radii follow the authored plant sprite footprint used for foliage
-- response. Only woody, cover-forming plants resist animal movement.
Flora.spriteReach={grass=.36,strawberry=.36,sumac=.7,bramble=.8,oak=.28,pine=.28,
    redbud=.28,blueberry=.7,milkweed=.42,dogwood=.28,persimmon=.28,
    ['chickasaw-plum']=.72,['little-bluestem']=.62,['blue-phlox']=.42,
    bloodroot=.32,['virginia-bluebells']=.62,['wild-columbine']=.48,
    ['purple-coneflower']=.42,['wild-bergamot']=.58,['cardinal-flower']=.72,
    ['new-england-aster']=.55,['common-goldenrod']=.58}
for kind,d in pairs(Flora.types) do d.mature=Life.plants[kind][1];d.longevity=Life.plants[kind][2] end
local function winter(month) return month==12 or month<=2 end
local function monthOf(calendar) return calendar and calendar.month or 5 end
function Flora.isDormant(p,calendar)
    local d=Flora.types[p.kind];if not d then return false end
    local month=monthOf(calendar)
    return (d.leafDrop and winter(month)) or (d.dormantMonths and d.dormantMonths[month])
        or (d.heatRest and p.drySite and (month==7 or month==8)) or false
end
function Flora.appearance(p,calendar)
    local d=Flora.types[p.kind];if not d then return nil end
    if p.lifePhase=='vacant' then return nil end
    if p.lifePhase=='dead' or p.lifePhase=='decay' then return p.lifePhase end
    if p.edible and p.amount==0 then return nil end
    if p.plantAge<d.seed then return 'seed' end
    if p.plantAge<d.sprout then return 'sprout' end
    if p.biteAge<1000 and p.amount<=.08 then return 'depleted' end
    if p.biteAge<1000 and p.amount<.995 then return p.biteAge>=.5 and 'regrowth' or 'browsed' end
    if p.plantAge<d.mature then return 'young' end
    local month=monthOf(calendar)
    if d.winterFruit and d.fruits[month] then return 'fruit' end
    if Flora.isDormant(p,calendar) or d.evergreen and winter(month) then return 'dormant' end
    if p.plantAge>=d.longevity*.85 then return 'senescent' end
    if d.flowers[month] then return 'flower' end
    if d.fruits[month] then return 'fruit' end
    if month==10 or month==11 then return 'autumn' end
    return 'mature'
end
function Flora.visual(p,calendar,realTime)
    local state=Flora.appearance(p,calendar)
    if not state then return nil end
    local d=Flora.types[p.kind]
    if p.lifePhase=='decay' then
        return state,'collapse-decay',math.min(4,math.floor(p.phaseAge/d.decayDays*4)+1)
    end
    if p.lifePhase~='live' then return state end
    if state=='young' or state=='sprout' then
        local progress=M.clamp((p.plantAge-d.seed)/(d.mature-d.seed),0,.999999)
        return state,'establish-grow',math.floor(progress*4)+1
    end
    if state=='browsed' then return state,'browse-impact',math.min(4,math.floor((1-p.amount)*4)+1) end
    if state=='regrowth' then return state,'regrow',math.min(4,math.floor(p.amount*4)+1) end
    if state=='senescent' and p.plantAge>=d.longevity*.98 then
        local progress=M.clamp((p.plantAge/d.longevity-.98)/.02,0,.999999)
        return state,'senesce-wilt',math.floor(progress*4)+1
    end
    -- Real-time passage alone never animates foliage. External forces are
    -- applied by plant_motion to this otherwise stable lifecycle pose.
    return state
end
return Flora
