local Test={}
local Layout=require("src.warehouse_layout")
local Renderer=require("src.warehouse_renderer")
local RackPresentation=require("src.warehouse_rack_presentation")
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
    test("layout_is_detached",Layout.bay("front_left").rackStart.x==25)
    for column=1,5 do
        local lower=Layout.rackPoint("front_left-rack",1,column)
        local upper=Layout.rackPoint("front_left-rack",2,column)
        test("shelf_anchor_"..column,lower.x==upper.x and lower.groundY==upper.groundY
            and lower.y-upper.y==70 and Layout.containsUnlocked(state,lower.x,lower.groundY))
    end
    test("ten_slots_only",not Layout.rackPoint("front_left-rack",3,1)
        and not Layout.rackPoint("front_left-rack",1,6)
        and not Layout.rackPoint("bogus",1,1))
    local obstacles=Layout.obstacles(state)
    test("rack_registers_six_structural_posts",#obstacles==6 and obstacles[1].kind=="pallet_rack_post"
        and obstacles[1].halfWidth==2 and obstacles[1].halfHeight==3)
    local approach=Layout.rackApproach("front_left-rack")
    local clear=true
    for _,obstacle in ipairs(obstacles) do
        if math.abs(approach.x-obstacle.x)<obstacle.halfWidth+48
            and math.abs(approach.y-obstacle.y)<obstacle.halfHeight+24 then clear=false end
    end
    test("forklift_approach_clear_of_rack",clear)
    local breakroomState={warehouse={bays={
        front_left={status="complete",optionId="breakroom"},
        front_right={status="complete",optionId="breakroom"}},projects={}}}
    local breakroomObstacles=Layout.obstacles(breakroomState)
    local furnitureFits=true
    for _,obstacle in ipairs(breakroomObstacles) do
        local bay=Layout.bay(obstacle.bayId)
        for _,dx in ipairs({-obstacle.halfWidth,obstacle.halfWidth}) do
            for _,dy in ipairs({-obstacle.halfHeight,obstacle.halfHeight}) do
                if not Layout.containsPolygon(bay.polygon,obstacle.x+dx,obstacle.y+dy) then
                    furnitureFits=false
                end
            end
        end
    end
    test("breakroom_furniture_footprints_fit_both_triangles",#breakroomObstacles==6 and furnitureFits)
    local rackState={warehouse={bays={
        front_left={status="complete",optionId="storage"},
        front_right={status="complete",optionId="storage"}},projects={}}}
    local rackObstacles=Layout.obstacles(rackState)
    for _,bayId in ipairs(Layout.BAY_IDS) do
        local plan=RackPresentation.plan(rackState,bayId,{review=true})
        local bay=Layout.bay(bayId)
        local seamSlope=(bay.rackEnd.y-bay.rackStart.y)/(bay.rackEnd.x-bay.rackStart.x)
        local railsStraight=plan~=nil
        if plan then
            for _,index in ipairs({1,2}) do
                local beam=plan.frontPolygons[index]
                local x1,y1=RackPresentation.sourceToWorld(plan,beam[1],beam[2])
                local x2,y2=RackPresentation.sourceToWorld(plan,beam[3],beam[4])
                railsStraight=railsStraight and math.abs((y2-y1)/(x2-x1)-seamSlope)<0.012
            end
        end
        test("rack_rails_straight_and_seam_aligned_"..bayId,railsStraight)
        local postsVertical=plan~=nil
        if plan then
            for index=3,8 do
                local post=plan.frontPolygons[index]
                local topX=RackPresentation.sourceToWorld(plan,post[1],post[2])
                local bottomX=RackPresentation.sourceToWorld(plan,post[7],post[8])
                postsVertical=postsVertical and math.abs(topX-bottomX)<0.000001
            end
        end
        test("rack_supports_stay_vertical_"..bayId,postsVertical)
        -- Compare collision positions with the actual raster base plates,
        -- independently of the raised shelf/pallet contact coordinates.
        local imageData=love.image.newImageData(plan.path)
        local feetAligned,feetInside=true,true
        for _,obstacle in ipairs(rackObstacles) do
            if obstacle.rackId==bay.rackId then
                local direction=plan.mirrorX and -1 or 1
                local sourceX=math.floor(plan.originX+(obstacle.x-plan.x)/(plan.scaleX*direction)+0.5)
                local sourceY=plan.originY+(obstacle.y-plan.y)/plan.scaleY
                local bottom=-1
                for y=imageData:getHeight()-1,0,-1 do
                    local _,_,_,alpha=imageData:getPixel(sourceX,y)
                    if alpha>200/255 then bottom=y;break end
                end
                feetAligned=feetAligned and bottom>=0 and sourceY>=bottom-18 and sourceY<=bottom
                for _,dx in ipairs({-obstacle.halfWidth,obstacle.halfWidth}) do
                    for _,dy in ipairs({-obstacle.halfHeight,obstacle.halfHeight}) do
                        feetInside=feetInside and Layout.containsPolygon(bay.polygon,
                            obstacle.x+dx,obstacle.y+dy)
                    end
                end
            end
        end
        imageData:release()
        test("rack_collision_posts_match_visible_feet_"..bayId,feetAligned)
        test("rack_post_footprints_fit_triangle_"..bayId,feetInside)
    end
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
