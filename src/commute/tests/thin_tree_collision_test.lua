local Flora=require('src.commute.flora')
local Obstacles=require('src.commute.obstacles')
local Vegetation=require('src.commute.vegetation')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local Test={}
local seed=4261
local function plant(kind,variant,age,scale)
    local p={kind=kind,x=16.2,z=24,h=5,scale=scale or 1}
    for id=1,200 do
        p.id=id;Flora.present(p,seed,{totalDays=0})
        if p.visualVariant==variant then break end
    end
    assert(p.visualVariant==variant,'Missing tree variant fixture')
    local d=Flora.catalog.types[kind]
    local period=d.longevity+d.deadDays+d.decayDays+d.vacantDays
    local calendar={month=5,totalDays=(age-p.age)%period}
    Flora.present(p,seed,calendar)
    return p,calendar
end
local function fixture(p,calendar)
    local world={size=128,seed=seed,calendar=calendar,
        height=function()return 5 end,supportHeight=function()return 5 end,
        roads={nearest=function()return 0,{width=8}end,blocked=function()return false end}}
    local vegetation=Vegetation.new(world)
    function vegetation:_makePatch(px,pz)
        if p and math.floor(p.x/16)==px and math.floor(p.z/16)==pz then return {p} end
        return {}
    end
    function world:sweepObstacles(x,z,nx,nz,radius,bottom,top)
        return vegetation:sweepObstacles(x,z,nx,nz,radius,bottom,top,self.calendar)
    end
    return world,vegetation
end
local function ride(world)
    local r=Rider.new(10,24,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
    r.bike.speed=10;r.bike.gear=3
    Bike.resetContact(r.bike,world);Bike.resetHorizontal(r.bike)
    for _=1,180 do Rider.update(r,{drive=-1},1/120,world) end
    return r
end
function Test.run(check)
    for _,kind in ipairs({'oak','pine','redbud','dogwood','persimmon'}) do
        local d=Flora.catalog.types[kind]
        local p,calendar=plant(kind,nil,d.mature*.6,1.62)
        local world=fixture(p,calendar)
        check('thin_tree_young_'..kind..'_does_not_block_bike_even_at_large_candidate_scale',
            Flora.catalog.appearance(p,calendar)=='young' and not Obstacles.shape(p,seed,calendar)
            and not world:sweepObstacles(10,24,25,24,Bike.RADIUS,5,6.2))
    end
    for _,case in ipairs({{'oak','understory'},{'pine','open'},{'redbud','understory'},{'dogwood','understory'}}) do
        local kind,variant=case[1],case[2]
        local p,calendar=plant(kind,variant,Flora.catalog.types[kind].mature+1)
        check('thin_tree_mature_'..kind..'_'..variant..'_is_passable',not Obstacles.shape(p,seed,calendar))
    end
    local mature=Flora.catalog.types.oak.mature+1
    local small,calendar=plant('oak',nil,mature,.45)
    check('thin_tree_small_scaled_mature_oak_is_passable',not Obstacles.shape(small,seed,calendar))
    local thick,thickCalendar=plant('oak',nil,mature)
    check('thin_tree_full_mature_oak_keeps_solid_trunk',Obstacles.shape(thick,seed,thickCalendar)>Obstacles.MIN_TREE_RADIUS)
    local enlarged,largeCalendar=plant('pine','open',Flora.catalog.types.pine.mature+1,2)
    check('thin_tree_visibly_large_variant_can_still_be_solid',Obstacles.shape(enlarged,seed,largeCalendar)>Obstacles.MIN_TREE_RADIUS)
    local young,youngCalendar=plant('oak',nil,Flora.catalog.types.oak.mature*.6)
    local _,growing=fixture(young,youngCalendar)
    local before=growing:sweepObstacles(10,24,25,24,Bike.RADIUS,5,6.2,youngCalendar)
    local older={month=5,totalDays=youngCalendar.totalDays+Flora.catalog.types.oak.mature*.4+2}
    check('thin_tree_cached_sapling_becomes_solid_only_after_growing',not before
        and growing:sweepObstacles(10,24,25,24,Bike.RADIUS,5,6.2,older)~=nil)
    local empty=ride(fixture(nil,thickCalendar))
    local smallRide=ride(fixture(small,calendar))
    local variant,variantCalendar=plant('pine','open',Flora.catalog.types.pine.mature+1)
    local thinRide=ride(fixture(variant,variantCalendar))
    for _,case in ipairs({{'small_tree',smallRide},{'thin_variant',thinRide}}) do
        local r=case[2]
        check('thin_tree_real_motorcycle_passes_'..case[1]..'_without_speed_loss_damage_or_crash',
            r.bike.x>20 and math.abs(r.bike.x-empty.bike.x)<1e-6
            and math.abs(r.bike.speed-empty.bike.speed)<1e-6 and r.bike.damage==0 and r.gear.mounted and not r.ped.crash)
    end
    local collision=ride(fixture(thick,thickCalendar))
    check('thin_tree_real_motorcycle_still_hits_thick_trunk',collision.bike.x<thick.x
        and collision.bike.damage>0 and collision.bike.collisionKind=='oak')
end
return Test
