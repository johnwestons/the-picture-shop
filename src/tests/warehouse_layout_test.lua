local Test={}
local Layout=require("src.warehouse_layout")
local Renderer=require("src.warehouse_renderer")
local Config=require("src.config")
function Test.run(_,check)
    local function test(name,value) check("warehouse_layout_"..name,value) end
    local state={warehouse={bays={front_left={status="locked"},front_right={status="locked"}},projects={}}}
    test("locked_bay_is_not_walkable",not Layout.containsUnlocked(state,100,570))
    test("locked_bay_reserved",Layout.isReserved(state,100,570))
    state.warehouse.bays.front_left.status="building"
    test("construction_bay_is_not_walkable",not Layout.containsUnlocked(state,100,570))
    state.warehouse.bays.front_left.status="complete"
    state.warehouse.bays.front_left.optionId="storage"
    test("completed_bay_walkable",Layout.containsUnlocked(state,100,570))
    test("completed_bay_not_reserved",not Layout.isReserved(state,100,570))
    test("other_bay_stays_locked",not Layout.containsUnlocked(state,860,570))
    test("outside_world_rejected",not Layout.containsUnlocked(state,-1,700))
    test("core_not_replaced",not Layout.containsUnlocked(state,480,440))
    test("bad_coordinates_rejected",not Layout.containsUnlocked(state,"100",570))
    local definition=Layout.bay("front_left")
    definition.rackStart.x=-1000
    test("layout_is_detached",Layout.bay("front_left").rackStart.x==30)
    for column=1,5 do
        local lower=Layout.rackPoint("front_left-rack",1,column)
        local upper=Layout.rackPoint("front_left-rack",2,column)
        test("shelf_anchor_"..column,lower.x==upper.x and lower.groundY==upper.groundY
            and lower.y-upper.y==58 and Layout.containsUnlocked(state,lower.x,lower.groundY))
    end
    test("ten_slots_only",not Layout.rackPoint("front_left-rack",3,1)
        and not Layout.rackPoint("front_left-rack",1,6)
        and not Layout.rackPoint("bogus",1,1))
    local obstacles=Layout.obstacles(state)
    test("rack_blocks_footprint_only",#obstacles==5 and obstacles[1].halfWidth==26
        and obstacles[1].halfHeight==18)
    local approach=Layout.rackApproach("front_left-rack")
    local clear=true
    for _,obstacle in ipairs(obstacles) do
        if math.abs(approach.x-obstacle.x)<obstacle.halfWidth+48
            and math.abs(approach.y-obstacle.y)<obstacle.halfHeight+24 then clear=false end
    end
    test("forklift_approach_clear_of_rack",clear)
    state.warehouse.bays.front_left.optionId="floor"
    test("open_floor_has_no_rack_obstacles",#Layout.obstacles(state)==0)
    local original=Config.warehouse
    Config.warehouse={provisionalArt=false}
    local vehicle={owned=true,operating=true,x=460,y=515,direction="east",forkHeight=1}
    test("unapproved_art_not_silently_enabled",not Renderer.forkliftPlan(vehicle))
    Config.warehouse.provisionalArt=true
    local plan=Renderer.forkliftPlan(vehicle)
    test("draft_switch_explicitly_reviews_not_approves",plan and plan.review and not plan.approved)
    vehicle.operating=false
    local parkedPlan=Renderer.forkliftPlan(vehicle)
    test("parked_vehicle_uses_empty_raised_art",parkedPlan and parkedPlan.path:match("east%-raise%-empty%-v1%.png$")
        and parkedPlan.forkHeight==1 and not parkedPlan.driverMismatch)
    Config.warehouse=original
end
return Test
