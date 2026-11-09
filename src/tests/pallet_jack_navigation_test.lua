local State=require("src.state")
local Config=require("src.config")
local Employees=require("src.employees")
local Jack=require("src.pallet_jack")
local Fleet=require("src.pallet_jack_fleet")
local Transport=require("src.employee_pallet_jack")
local Navigation=require("src.navigation")
local Navigator=require("src.npc_navigation")
local Jobs=require("src.jobs")
local Machines=require("src.machine_fleet")
local Staging=require("src.staging_areas")
local Pallets=require("src.pallet_state")
local Test={}

local function hire(state)
    local a=assert(Employees.createApplicant(state,0));a.shiftPreference="flexible"
    Employees.requestResume(state,a.id,0);Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=math.max(2400,a.requestedWage),days=31,startHour=9,endHour=17},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=state.employment.staff[#state.employment.staff]
    w.visible,w.clockedIn,w.phase=true,true,"idle";w.x,w.y=600,560
    w.cutterSkill,w.pressSkill,w.wrappingSkill=100,100,100
    return w
end

local function job(state,id,points)
    local counts={};for _=1,#points do counts[#counts+1]=500 end
    local j=assert(Jobs.createOffer({id=id,company="Jack route QA",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts=counts}))
    Jobs.accept(j);j.status,j.delivery="in_production",{status="received"}
    state.jobs.active[#state.jobs.active+1]=j
    for index,p in ipairs(j.pallets) do
        p.location,p.status="warehouse","raw"
        p.world={x=points[index].x,y=points[index].y,direction="northwest",spawnProgress=1}
    end
    return j
end

local function shelfAndParking(context,check)
    local s=State.new();local w=hire(s)
    local ctx=context.world.employeeContext(s,context.assets)
    assert(Jack.mountEmployee(s,Config.palletJack,w.id))
    local goal=assert(ctx.jackShelfPoint(w,"warehouse-rack",1))
    Fleet.add(s,"SHELF-BLOCKER",goal)
    local updated=ctx.jackShelfPoint(w,"warehouse-rack",1)
    local route=ctx.jackNavigation(w,nil,true)
    check("jack_navigation_replans_cached_shelf_access_when_another_jack_parks",
        updated and Navigation.isWalkable(route.assets,updated.x,updated.y,route.obstacles()),
        string.format("cached=%.1f,%.1f selected=%s",goal.x,goal.y,updated and updated.x..","..updated.y or "nil"))

    s=State.new();w=hire(s);ctx=context.world.employeeContext(s,context.assets)
    assert(Jack.mountEmployee(s,Config.palletJack,w.id))
    local zone=Staging.findById(s,"cutter-output")
    zone.x,zone.y=490,480
    local parking=ctx.jackParkingPoint(w)
    check("jack_navigation_parks_outside_pallet_staging_areas",parking
        and not (parking.x>=zone.x and parking.x<=zone.x+zone.width
            and parking.y>=zone.y and parking.y<=zone.y+zone.height),
        parking and parking.x..","..parking.y or "no parking")
end

local function staging(context,check)
    local passed,details=true,{}
    for index=1,6 do
        local s=State.new();local w=hire(s)
        local points=require("src.cutter_staging").slots(s)
        local j
        for slot,point in ipairs(points) do
            local offer=job(s,"JOB-CROWDED-"..index.."-"..slot,{point})
            if slot==index then j=offer end
        end
        local pallet=j.pallets[1]
        local machine=Machines.installedUnits(s,"polar_115")[1]
        w.assignment={jobId=j.id,palletId=pallet.id,machineId=machine.id,machineModel="polar_115"}
        w.reserved=true
        local ctx=context.world.employeeContext(s,context.assets)
        ctx.move=function(actor,goal,dt) return require("src.employee_ai").move(actor,goal,dt,ctx) end
        local lifted,delivered=false,false
        for _=1,1400 do
            Transport.update(s,w,machine,pallet,"cutter",.1,ctx)
            lifted=lifted or pallet.location=="on_pallet_jack"
            delivered=lifted and pallet.location=="warehouse"
            if delivered then break end
        end
        passed=passed and delivered and Pallets.validate(s)
        if not delivered then
            details[#details+1]=string.format("slot%d lifted=%s jack=%.1f,%.1f %s / %s",index,tostring(lifted),
                s.palletJack.x,s.palletJack.y,w.activity,Navigator.status(w._jackNavigator or {}))
        end
    end
    check("jack_navigation_retrieves_every_pallet_from_full_staging",passed,table.concat(details,"; "))
end

local function pickupExit(context,check)
    local s=State.new();local w=hire(s)
    s.palletJack.x,s.palletJack.y=700,542.82
    local target=job(s,"JOB-NARROW-EXIT",{{x=430,y=550}}).pallets[1]
    local points={}
    for _,x in ipairs({305,555}) do
        for _,y in ipairs({480,525,570,615}) do points[#points+1]={x=x,y=y} end
    end
    points[#points+1]={x=430,y=480};points[#points+1]={x=430,y=615}
    for index,point in ipairs(points) do job(s,"JOB-EXIT-BLOCK-"..index,{point}) end
    assert(Jack.mountEmployee(s,Config.palletJack,w.id))
    local ctx=context.world.employeeContext(s,context.assets)
    local pickup=ctx.jackPickupPoint(w,target)
    local exit=pickup and Navigator.findPath(pickup,{{x=700,y=550}},ctx.jackNavigation(w,target.id,true))
    check("jack_navigation_never_lifts_into_a_pocket_without_a_loaded_exit",not pickup or exit~=nil,
        pickup and string.format("unsafe pickup=%.2f,%.2f",pickup.x,pickup.y) or "blocked before loading")
end

local function manualShelf(context,check)
    local s=State.new()
    local j=job(s,"JOB-SHELF-RECOVERY",{{x=500,y=246}})
    s.palletJack.x,s.palletJack.y=500,246
    assert(Jack.mount(s,Config.palletJack,1));assert(Jack.lift(s,Config.palletJack,j.pallets[1].id))
    local assets=require("src.warehouse_gameplay").assets(context.assets,s)
    local function move(x,y)
        return Navigation.canMoveAreaFrom(assets,s.palletJack.x,s.palletJack.y,x,y,
            Config.palletJack.loadedCollisionHalfWidth,Config.palletJack.loadedCollisionHalfHeight,{})
    end
    local start=s.palletJack.y
    check("jack_navigation_shelf_recovery_cannot_drive_further_into_wall",not move(500,245)
        and not Navigation.canMoveAreaFrom(assets,500,246,500,247.5,
            Config.palletJack.loadedCollisionHalfWidth,Config.palletJack.loadedCollisionHalfHeight,
            {{x=500,y=249,halfWidth=80,halfHeight=3}}))
    for _=1,20 do Jack.move(s,0,1,.1,Config.palletJack,move) end
    check("jack_navigation_player_can_reverse_loaded_jack_away_from_shelf_edge",s.palletJack.y>start+40
        and Navigation.isAreaWalkable(assets,s.palletJack.x,s.palletJack.y,
            Config.palletJack.loadedCollisionHalfWidth,Config.palletJack.loadedCollisionHalfHeight),
        string.format("y=%.1f -> %.1f",start,s.palletJack.y))
end

local function stock(context,check)
    local s=State.new();s.money=5000
    local a,b=hire(s),hire(s)
    s.palletJack.x,s.palletJack.y=250,530
    Fleet.add(s,"STOCK-ROUTE-JACK",{x=720,y=530})
    a.x,a.y,b.x,b.y=250,590,720,590
    local Procurement=require("src.procurement")
    local pallets={}
    for index,point in ipairs({{x=300,y=550},{x=750,y=550}}) do
        local _,order=Procurement.buyRetail(s,1,1)
        assert(Procurement.unload(s,order.id,order.pallets[1].id,{point}))
        pallets[index]=order.pallets[1]
    end
    local ctx=context.world.employeeContext(s,context.assets)
    ctx.move=function(actor,goal,dt) return require("src.employee_ai").move(actor,goal,dt,ctx) end
    for _=1,2600 do
        for _,worker in ipairs({a,b}) do
            local stocking=Transport.storeSupplies(s,worker,.1,ctx)
            if not stocking then ctx.move(worker,ctx.idlePoint(worker),.1) end
        end
        if pallets[1].location=="rack" and pallets[2].location=="rack"
            and not Transport.owns(s,a) and not Transport.owns(s,b) then break end
    end
    check("jack_navigation_two_workers_stock_shelves_and_clear_the_aisle",pallets[1].location=="rack"
        and pallets[2].location=="rack" and not Transport.owns(s,a) and not Transport.owns(s,b) and Pallets.validate(s),
        string.format("%s / %s; %s / %s",pallets[1].location,pallets[2].location,a.activity,b.activity))
end

local function finishedStock(context,check)
    local s=State.new();local w=hire(s)
    assert(Jack.mountEmployee(s,Config.palletJack,w.id))
    local ctx=context.world.employeeContext(s,context.assets)
    for _=1,500 do
        Transport.storeSupplies(s,w,.1,ctx)
        if not Transport.owns(s,w) then break end
    end
    check("jack_navigation_releases_empty_jack_if_another_employee_takes_last_stock",not Transport.owns(s,w)
        and not s.palletJack.operating,w.activity)
end

function Test.run(context,check)
    local world=context.world
    local oldX,oldY,oldOptions=world.player.x,world.player.y,world._employeeOptions
    world.player.x,world.player.y=930,640
    world.configureEmployees({players=function() return {} end})
    manualShelf(context,check)
    shelfAndParking(context,check)
    pickupExit(context,check)
    staging(context,check)
    stock(context,check)
    finishedStock(context,check)
    world.player.x,world.player.y=oldX,oldY;world.configureEmployees(oldOptions)
end

return Test
