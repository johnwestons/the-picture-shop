local Navigator=require("src.npc_navigation")
local Navigation=require("src.navigation")
local Customer=require("src.customer")
local AI=require("src.employee_ai")
local Config=require("src.config")
local Test={}

local function map(predicate)
    local mask={}
    function mask:getDimensions() return Config.baseWidth,Config.baseHeight end
    function mask:getPixel(x,y)
        local v=predicate(x,y) and 1 or 0
        return v,v,v,1
    end
    return {getData=function() return mask end}
end
local function scene(obstacles,predicate)
    return {assets=map(predicate or function(x,y) return x>20 and x<920 and y>20 and y<650 end),
        obstacles=function(actor)
            local result={}
            for _,o in ipairs(obstacles) do if o.actor~=actor then result[#result+1]=o end end
            return result
        end}
end
local function drive(actor,goal,context,steps)
    local arrived=false
    for _=1,steps or 1500 do
        arrived=Navigator.travel(actor,goal,7.2,.1,context)
        if arrived then break end
        assert(Navigation.isWalkable(context.assets,actor.x,actor.y,context.obstacles(actor)),
            "Navigator crossed a collider or blocked floor pixel")
    end
    return arrived
end

function Test.run(context,check)
    local u={{x=420,y=270,halfWidth=100,halfHeight=8},
        {x=420,y=430,halfWidth=100,halfHeight=8},
        {x=520,y=350,halfWidth=8,halfHeight=88}}
    local ctx=scene(u)
    local actor={x=450,y=350}
    local goal={x=650,y=350}
    check("npc_astar_leaves_u_trap_by_initially_walking_away_from_goal",drive(actor,goal,ctx))

    local thin={{x=405,y=350,halfWidth=1,halfHeight=100}}
    ctx=scene(thin);actor={x=390,y=350};goal={x=420,y=350}
    local points=Navigator.findPath(actor,{goal},ctx)
    local previous=actor
    local safe=points and #points>1
    for _,point in ipairs(points or {}) do
        safe=safe and Navigation.canTraverse(ctx.assets,previous.x,previous.y,point.x,point.y,thin)
        previous=point
    end
    check("npc_path_edges_and_smoothing_do_not_tunnel_through_thin_obstacles",safe and drive(actor,goal,ctx))

    local dynamic={}
    ctx=scene(dynamic);actor={x=200,y=350};goal={x=700,y=350}
    Navigator.travel(actor,goal,40,.1,ctx)
    dynamic[1]={x=400,y=350,halfWidth=45,halfHeight=95}
    check("npc_replans_when_a_machine_is_parked_across_cached_route",drive(actor,goal,ctx))
    actor={x=200,y=350};Navigator.travel(actor,goal,7,.1,ctx)
    actor.x,actor.y=250,550
    check("npc_recovers_after_being_displaced_or_taking_a_wrong_turn",drive(actor,goal,ctx))

    local overlap={{x=400,y=350,halfWidth=40,halfHeight=25}}
    ctx=scene(overlap);actor={x=415,y=350};goal={x=650,y=350}
    local escaped=false
    for _=1,100 do
        escaped=Navigator.travel(actor,goal,7.2,.1,ctx)
        if escaped then break end
    end
    check("npc_walks_out_of_an_overlapping_saved_placement",escaped)
    ctx=scene({},function(x,y) return x>200 and x<900 and y>100 and y<600 end)
    actor={x=201,y=300};goal={x=400,y=300}
    check("npc_recovers_from_a_mask_edge_without_crossing_a_wall",drive(actor,goal,ctx))

    local wall={{x=400,y=335,halfWidth=10,halfHeight=335}}
    ctx=scene(wall);actor={x=200,y=350};goal={x=650,y=350}
    local blocked=false
    for _=1,30 do local _,_,_,b=Navigator.travel(actor,goal,7.2,.1,ctx);blocked=b end
    local status,failures=Navigator.status(actor)
    check("npc_unreachable_goal_waits_with_bounded_retries_without_false_arrival",
        blocked and status=="unreachable" and failures>=2 and failures<=5 and actor.x==200)
    wall[1]=nil
    check("npc_resumes_when_a_previously_unreachable_destination_opens",drive(actor,goal,ctx))
    actor={x=390,y=350};goal={x=411,y=350};wall[1]={x=400,y=335,halfWidth=10,halfHeight=335}
    local unreachable=Navigator.findPath(actor,{goal},ctx)
    check("npc_nearby_goal_across_a_wall_is_not_treated_as_reached",unreachable==nil)

    ctx=scene({{x=450,y=350,halfWidth=45,halfHeight=100}})
    local worker={x=200,y=350,distance=0,idleClock=0}
    local client=Customer.new({route={{x=200,y=350},{x=700,y=350}},speed=72,initialArrivalDelay=0})
    local workerArrived=false
    for _=1,1500 do
        workerArrived=AI.move(worker,{x=700,y=350},.1,ctx)
        client:update(.1,nil,false,.1,ctx)
        assert(Navigation.isWalkable(ctx.assets,worker.x,worker.y,ctx.obstacles(worker)))
        assert(Navigation.isWalkable(ctx.assets,client.x,client.y,ctx.obstacles(client)))
        if workerArrived and client.state=="waiting" then break end
    end
    check("npc_employees_and_clients_share_obstacle_aware_navigation",workerArrived and client.state=="waiting")
    check("npc_client_gait_measures_detour_distance",client.animationDistance>500)

    client=Customer.new({route={{x=200,y=350},{x=450,y=350},{x=700,y=350}},speed=72,initialArrivalDelay=0})
    for _=1,1500 do client:update(.1,nil,false,.1,ctx);if client.state=="waiting" then break end end
    check("npc_client_skips_an_unreachable_old_route_marker",client.state=="waiting" and client.x==700)

    local seats={
        {x=705,y=350,approach={{x=700,y=350}}},
        {x=705,y=500,approach={{x=700,y=500}}},
    }
    ctx=scene({{x=700,y=350,radius=20}})
    client=Customer.new({route={{x=200,y=350},{x=500,y=500}},seatSpots=seats,speed=72,initialArrivalDelay=0})
    for _=1,1500 do client:update(.1,nil,false,.1,ctx);if client.state=="waiting" then break end end
    check("npc_client_chooses_another_reachable_seat_if_its_chair_is_blocked",
        client.state=="waiting" and client.seatIndex==2)
    ctx=scene({{x=700,y=350,radius=20},{x=700,y=500,radius=20}})
    client=Customer.new({route={{x=200,y=350},{x=500,y=500}},seatSpots=seats,speed=72,initialArrivalDelay=0})
    local rejected=false
    for _=1,1500 do
        local event=client:update(.1,nil,false,.1,ctx)
        rejected=rejected or event=="route_blocked"
        if client.state=="finished" then break end
    end
    check("npc_client_leaves_safely_when_no_seat_is_accessible",rejected and client.state=="finished" and client.x==200)

    -- Real warehouse floor, furniture, machines and all four lounge approaches.
    local State=require("src.state")
    local state=State.new()
    local world=context.world
    local oldCustomer,oldVendor=world.customer,world.vendor
    local oldX,oldY=world.player.x,world.player.y
    local okay,reason=pcall(function()
        world.player.x,world.player.y=100,100
        world.vendor=Customer.new(Config.vendor)
        for seatIndex=1,#Config.customer.seatSpots do
            local visitor=Customer.new(Config.customer)
            for _=2,seatIndex do visitor:reset(false) end
            visitor.timer=0;world.customer=visitor
            local realContext=world.employeeContext(state,context.assets)
            for _=1,1000 do
                visitor:update(.1,nil,false,.1,realContext)
                if visitor.state=="waiting" then break end
            end
            check("npc_real_warehouse_client_reaches_lounge_seat_"..seatIndex,visitor.state=="waiting",
                visitor.state.." at "..visitor.x..","..visitor.y.." waypoint "..visitor.waypoint)
            assert(visitor:beginReview() and visitor:resolve("accepted"))
            for _=1,1000 do
                visitor:update(.1,nil,false,.1,realContext)
                if visitor.state=="finished" then break end
            end
            check("npc_real_warehouse_client_returns_to_entrance_"..seatIndex,visitor.state=="finished")
        end
        world.customer=Customer.new(Config.customer)
        local Technician=require("src.technician")
        for _,kind in ipairs({"cutter","windmill"}) do
            local serviceState=State.new()
            if kind=="windmill" then
                serviceState.money=20000
                assert(require("src.machine_fleet").buy(serviceState,"dealer",3))
            end
            assert(Technician.schedule(serviceState,kind,0,false))
            local serviceContext=world.employeeContext(serviceState,context.assets)
            local arrived=false
            for _=1,1000 do
                Technician.update(.1,serviceState,false,.1,serviceContext)
                if serviceState.technicianVisit.status=="servicing" then arrived=true;break end
            end
            local visit=serviceState.technicianVisit
            check("npc_real_warehouse_technician_reaches_"..kind,arrived,
                visit.status.." at "..visit.x..","..visit.y.." waypoint "..visit.waypoint)
            for _=1,1000 do
                Technician.update(.1,serviceState,false,.1,serviceContext)
                if not serviceState.technicianVisit then break end
            end
            check("npc_real_warehouse_technician_exits_after_"..kind,not serviceState.technicianVisit)
        end
    end)
    world.customer,world.vendor=oldCustomer,oldVendor
    world.player.x,world.player.y=oldX,oldY
    if not okay then error(reason) end
end
return Test
