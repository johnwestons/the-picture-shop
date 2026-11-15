local Characters=require('src.commute.town_characters')
local Employees=require('src.commute.employee_commute')
local Company=require('src.company_delivery_driver')
local Truck=require('src.commute.delivery_truck')
local Test={}

local function actor(entries,id)
    for _,entry in ipairs(entries) do if entry.id==id then return entry.actor end end
end

function Test.run(check,town,world)
    local state={home={town=town,townCharacters=Characters.defaultState(town)},employment={}}
    Characters.advance(state,7.06)
    local first=actor(Characters.actors(state.home,town,7.055001,world),'town-npc-mechanic')
    local later=actor(Characters.actors(state.home,town,7.15,world),'town-npc-mechanic')
    check('scheduled_shop_attendant_uses_driving_speed_profile',first and later
        and first.speed<.05 and later.speed>first.speed and later.speed<=6.8)

    local profile={residenceKind='town',residenceId='brick-walkup',workSiteId='warehouse',paintId='red',rosterId='cat'}
    local journey={phase='commuting_to_work',fromId='brick-walkup',toId='warehouse',departAtHours=7,arriveAtHours=8}
    state.employment.staff={{id='driver-test',name='Driver',status='employed',character='cat-worker',
        commuteProfile=profile,commuteState=journey}}
    state.employment.applications={{id='applicant-test',name='Applicant',status='interview',character='cat-worker',
        commuteProfile=profile,commuteState=journey}}
    for _,id in ipairs({'employee-driver-test','applicant-applicant-test'}) do
        local first=actor(Employees.actors(state,town,7.055001,world),id)
        local later=actor(Employees.actors(state,town,7.15,world),id)
        check('scheduled_'..id..'_uses_driving_speed_profile',first and later
            and first.speed<.05 and later.speed>first.speed and later.speed<=6.8)
    end

    local site=world.sites.byId.warehouse
    state.home.commute={truck=Truck.new(site.truckParking.x,site.truckParking.z,site.yaw)}
    local company=Company.defaultState()
    state.employment.companyTruck=company
    company.departureStage='truck_departure';company.departureStartedAtEpoch=1000
    Company.updateExterior(state,world,1000,7,0)
    local start=actor(Company.actors(state,world,1000),'company-delivery-truck')
    local x,z=start.x,start.z
    local later=actor(Company.actors(state,world,2000),'company-delivery-truck')
    Company.updateExterior(state,world,2000,7,0)
    check('company_truck_render_and_wall_clock_never_advance_physics',start and later
        and later.x==x and later.z==z and later.speed==0 and company.departureStage=='truck_departure')
end

return Test
