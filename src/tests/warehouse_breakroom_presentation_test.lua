local Presentation=require("src.warehouse_breakroom_presentation")
local Layout=require("src.warehouse_layout")
local Test={}

function Test.run(_,check)
    local catalog=Presentation.reviewCatalog()
    local path="assets/source/warehouse-expansion-v1/rooms/breakroom-triangle-v6-perspective-candidate.png"
    check("breakroom_art_registered_for_both_bays",catalog.front_left and catalog.front_right
        and catalog.front_left.path==path and catalog.front_right.path==path)
    check("right_breakroom_uses_mirrored_art",catalog.front_left.mirrorX==false
        and catalog.front_right.mirrorX==true)
    local state={warehouse={bays={front_left={status="complete",optionId="breakroom"},
        front_right={status="complete",optionId="breakroom"}}}}
    local left,why=Presentation.plan(state,"front_left",{review=true})
    local right=Presentation.plan(state,"front_right",{review=true})
    check("breakroom_requires_finished_purchase",left and right and left.review and right.review)
    local cornersFit=left~=nil and right~=nil
    for _,plan in ipairs({left,right}) do
        local polygon=Layout.bay(plan.bayId).polygon
        for index,source in ipairs({{80,200},{1118,1000},{80,1000}}) do
            local x=plan.x+(source[1]-plan.originX)*plan.scaleX*(plan.mirrorX and -1 or 1)
            local y=plan.y+(source[2]-plan.originY)*plan.scaleY
            cornersFit=cornersFit and math.abs(x-polygon[index].x)<0.000001
                and math.abs(y-polygon[index].y)<0.000001
        end
    end
    check("both_breakrooms_map_measured_floor_vertices",cornersFit)
    check("right_room_mirrors_at_its_own_center",left and right and not left.mirrorX and right.mirrorX
        and right.x==960-left.x and right.y==left.y)
    local drawCalls={}
    local graphics={setColor=function()end,draw=function(...)drawCalls[#drawCalls+1]={...}end}
    local image={getDimensions=function()return 1254,1254 end}
    check("left_breakroom_sprite_draws",Presentation.draw(left,function()return image end,graphics))
    check("right_breakroom_sprite_draws_mirrored",Presentation.draw(right,function()return image end,graphics)
        and drawCalls[1][5]==left.scaleX and drawCalls[2][5]==-right.scaleX
        and drawCalls[1][6]==left.scaleY and drawCalls[2][6]==right.scaleY)
    local notReady={warehouse={bays={front_left={status="locked",optionId="breakroom"}}}}
    local blocked,code=Presentation.plan(notReady,"front_left",{review=true})
    check("locked_breakroom_never_renders",not blocked and code=="breakroom_not_complete")
    check("unreviewed_art_keeps_clear_release_gate",select(2,Presentation.plan(state,"front_left"))=="art_not_approved")
    check("wrong_image_dimensions_fail",not Presentation.draw(left,function()
        return {getDimensions=function()return 100,100 end}end,graphics))
end
return Test
