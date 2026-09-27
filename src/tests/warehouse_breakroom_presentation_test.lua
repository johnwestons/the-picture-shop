local Presentation=require("src.warehouse_breakroom_presentation")
local Test={}

function Test.run(_,check)
    local catalog=Presentation.reviewCatalog()
    local path="assets/source/warehouse-expansion-v1/rooms/breakroom-furnishings-v1.png"
    check("breakroom_art_registered_for_both_bays",catalog.front_left and catalog.front_right
        and catalog.front_left.path==path and catalog.front_right.path==path)
    check("right_breakroom_uses_mirrored_art",catalog.front_left.mirrorX==false
        and catalog.front_right.mirrorX==true)
    local state={warehouse={bays={front_left={status="complete",optionId="breakroom"},
        front_right={status="complete",optionId="breakroom"}}}}
    local left,why=Presentation.plan(state,"front_left",{review=true})
    local right=Presentation.plan(state,"front_right",{review=true})
    check("breakroom_requires_finished_purchase",left and right and left.review and right.review)
    check("both_breakrooms_keep_registered_native_scale",left and right and left.scale==0.24
        and right.scale==0.24 and left.textureWidth==1536 and left.textureHeight==1024)
    check("right_room_mirrors_at_its_own_center",left and right and not left.mirrorX and right.mirrorX
        and right.x==960-left.x and right.y==left.y)
    local drawCalls={}
    local graphics={setColor=function()end,draw=function(...)drawCalls[#drawCalls+1]={...}end}
    local image={getDimensions=function()return 1536,1024 end}
    check("left_breakroom_sprite_draws",Presentation.draw(left,function()return image end,graphics))
    check("right_breakroom_sprite_draws_mirrored",Presentation.draw(right,function()return image end,graphics)
        and drawCalls[1][5]==0.24 and drawCalls[2][5]==-0.24)
    local notReady={warehouse={bays={front_left={status="locked",optionId="breakroom"}}}}
    local blocked,code=Presentation.plan(notReady,"front_left",{review=true})
    check("locked_breakroom_never_renders",not blocked and code=="breakroom_not_complete")
    check("unreviewed_art_keeps_clear_release_gate",select(2,Presentation.plan(state,"front_left"))=="art_not_approved")
    check("wrong_image_dimensions_fail",not Presentation.draw(left,function()
        return {getDimensions=function()return 100,100 end}end,graphics))
end
return Test
