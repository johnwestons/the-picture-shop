local Layout=require("src.warehouse_layout")
local World=require("src.world")
local Test={}
function Test.run(context,check)
    local left,right=Layout.bay("front_left"),Layout.bay("front_right")
    check("breakroom_seat_points_are_mirrored",left.restPoint.x==82 and right.restPoint.x==878
        and left.restPoint.y==right.restPoint.y)
    local state=context.State.new()
    state.warehouse.bays.front_left={status="complete",optionId="breakroom"}
    state.warehouse.bays.front_right={status="complete",optionId="breakroom"}
    local obstacles=Layout.obstacles(state)
    check("completed_breakrooms_have_collision_for_furniture",#obstacles==6
        and obstacles[1].bayId=="front_left" and obstacles[4].bayId=="front_right")
    check("vending_collision_tracks_resized_inset_art",obstacles[3].x==198 and obstacles[3].y==610
        and obstacles[3].halfWidth==20 and obstacles[3].halfHeight==9)
    state.warehouse.bays.front_right.optionId="floor"
    check("open_floor_adds_no_breakroom_obstacles",#Layout.obstacles(state)==3)

    local playerFields={}
    for key,value in pairs(World.player) do playerFields[key]=value end
    local originalState,originalSelection=World._state,World.selectedInteraction
    World._state=state
    World.selectedInteraction={kind="breakroom",target={x=left.restPoint.x,y=left.restPoint.y,bayId="front_left"}}
    state.warehouse.bays.front_right.optionId="breakroom"
    local messageBefore=state.message
    local moneyBefore,creditBefore,needsBefore=state.money,state.credit,state.employeeNeeds
    local started=World.beginBreakroomRest(state)
    check("breakroom_use_sits_player_without_economy_or_needs",started and World.player.resting
        and World.player.x==left.restPoint.x and World.player.y==left.restPoint.y
        and state.message~=messageBefore)
    local noSaveNoNeedFields=state.money==moneyBefore
        and state.credit==creditBefore and state.employeeNeeds==needsBefore
    check("breakroom_rest_has_no_finance_or_employee_needs_side_effect",noSaveNoNeedFields)
    local stood=World.beginBreakroomRest(state)
    check("breakroom_use_toggles_back_to_work",stood and not World.player.resting and state.message=="Back to work.")
    state.warehouse.bays.front_left.status="locked"
    check("stale_room_target_cannot_start_break",not World.beginBreakroomRest(state)
        and not World.player.resting)
    for key in pairs(World.player) do World.player[key]=nil end
    for key,value in pairs(playerFields) do World.player[key]=value end
    World._state,World.selectedInteraction=originalState,originalSelection
end
return Test
