local Interior=require('src.commute.mechanic_interior')
local Loader=require('src.image_loader')
local Fonts=require('src.screens.title_fonts')
local Test={}
local Presentation=require('src.commute.presentation')
function Test.run(check)
    local originalGraphics,originalLoad,originalCancel,originalFont,originalIndoor=love.graphics,Loader.load,Loader.cancel,Fonts.get,Presentation.indoor
    local calls,released,canceled,quads,borrowReleased=0,0,0,0,0
    local labels={};local graphics={}
    for _,name in ipairs({'push','pop','setShader','scale','setColor','rectangle','setFont','ellipse','draw'})do graphics[name]=function()end end
    local shader;local shaderStack={}
    graphics.getShader=function()return shader end
    graphics.setShader=function(value)shader=value end
    graphics.push=function()shaderStack[#shaderStack+1]={value=shader}end
    graphics.pop=function()shader=table.remove(shaderStack).value end
    graphics.printf=function(text)labels[#labels+1]=text end
    graphics.newQuad=function(x,y,w,h)return {getViewport=function()return x,y,w,h end,
        release=function()quads=quads+1 end}end
    local function image()return {setFilter=function()end,release=function()released=released+1 end}end
    love.graphics=graphics;Fonts.get=function()return {}end
    Loader.load=function()calls=calls+1;return image()end
    Loader.cancel=function()canceled=canceled+1 end
    local okay,reason=pcall(function()
        local original={id=2,homeResidentId='resident-fixture',character='mouse-worker',x=123,z=456,y=90,sceneId='commute'}
        local persisted={screen='world',home={commute={token=71,origin='warehouse',target='mechanic'}}}
        local inputX,inputY=0,0
        local borrowedQuads={}
        for index=1,16 do
            local x,y=(index-1)%4*320,math.floor((index-1)/4)*320
            borrowedQuads[index]={getViewport=function()return x,y,320,320 end,
                release=function()borrowReleased=borrowReleased+1 end}
        end
        local R={World={player=original},state=persisted,Config={baseWidth=960,baseHeight=678},
            Input={movement=function()return inputX,inputY end},_commute={mechanicOffer={page='lobby'},
                renderer={bikeArt={frameCount=64,parkedFrameCount=16,images={parked={getDimensions=function()return 1280,1280 end,release=function()borrowReleased=borrowReleased+1 end}},quads=borrowedQuads}}}}
        local view=Interior.new(R)
        Interior.update(view,R,.016)
        check('mechanic_interior_new_and_pre_draw_update_do_no_resource_work',calls==0 and not view.ready)
        Interior.draw(view,R)
        check('mechanic_interior_first_draw_presents_loading_without_decode',calls==0 and labels[1]=='OPENING MAJIC BLUE...')
        for i=1,3 do Interior.update(view,R,.016);check('mechanic_interior_upload_sequence_is_bounded_'..i,calls==i)end
        check('mechanic_interior_borrows_only_existing_parked_bike',view.ready and #view.requests==3 and borrowReleased==0)
        local gear={outfit='geared'};local seenGear,seenResident
        persisted.home.commute.participants={[require('src.home_residents').key(original)]={rider={gear=gear}}}
        R.CharacterAssets={}
        Presentation.indoor=function(p,state,assets,override)seenGear,seenResident=override,p.homeResidentId;return true end
        Interior.draw(view,R)
        check('mechanic_interior_preserves_guest_identity_and_live_trip_gear',seenGear==gear and seenResident=='resident-fixture'
            and view.pose.character=='mouse-worker')
        R.CharacterAssets=nil;Presentation.indoor=originalIndoor
        local callsBefore=calls;Interior.draw(view,R)
        check('mechanic_interior_ready_draw_has_no_asset_work',calls==callsBefore)
        for _,size in ipairs({{640,480},{960,678},{1280,880}})do
            R.Config.baseWidth,R.Config.baseHeight=size[1],size[2]
            local layout=Interior.layout(R);local b=layout.catalog
            check('mechanic_interior_touch_catalog_and_exit_'..size[1],
                Interior.pointer(view,R,(b.x+b.w/2)*size[1]/960,(b.y+b.h/2)*size[2]/678)=='catalog'
                and b.h*size[2]/678>=44
                and Interior.pointer(view,R,640*size[1]/960,248*size[2]/678)=='exit'
                and Interior.pointer(view,R,300*size[1]/960,337*size[2]/678)=='catalog')
        end
        R.Config.baseWidth,R.Config.baseHeight=960,678
        view.pose.x,view.pose.y=700,430
        check('mechanic_interior_counter_keyboard_interaction',Interior.keypressed(view,R,'e')=='catalog'
            and Interior.keypressed(view,R,'c')=='catalog' and Interior.keypressed(view,R,'escape')=='exit')
        view.pose.x,view.pose.y=620,280
        Interior.pointer(view,R,350,390)
        local pausedPath=view.path;local pausedDistance=view.pose.animationDistance
        local pausedClock=view.clock
        persisted.screen='options';inputX,inputY=1,0
        Interior.update(view,R,.1)
        check('mechanic_interior_options_pauses_keyboard_and_preserves_path',
            view.pose.x==620 and view.pose.y==280 and not view.pose.moving
            and view.path==pausedPath and view.pose.animationDistance==pausedDistance)
        inputX,inputY=0,0;Interior.update(view,R,.1)
        check('mechanic_interior_options_pauses_path_while_progress_clock_runs',
            view.pose.x==620 and view.pose.y==280 and view.path==pausedPath
            and view.clock>pausedClock and view.pose.animationDistance==pausedDistance)
        persisted.screen='world';Interior.update(view,R,.1)
        check('mechanic_interior_world_resumes_saved_walk_path',view.pose.moving
            and view.pose.animationDistance>pausedDistance and Interior.walkable(view.pose.x,view.pose.y))
        local resumedX=view.pose.x;inputX,inputY=1,0;Interior.update(view,R,.1)
        check('mechanic_interior_world_resumes_keyboard_walk',view.pose.x>resumedX
            and view.pose.moving and view.path==nil)
        inputX,inputY=0,0;view.pose.x,view.pose.y=620,280
        Interior.pointer(view,R,350,390)
        local safe=true
        for _=1,500 do Interior.update(view,R,1/60);safe=safe and Interior.walkable(view.pose.x,view.pose.y)end
        check('mechanic_interior_click_walks_around_furniture_to_service_bay',safe
            and math.abs(view.pose.x-350)<12 and math.abs(view.pose.y-390)<12 and view.pose.animationDistance>200)
        inputX,inputY=-1,-1
        for _=1,80 do Interior.update(view,R,.1);safe=safe and Interior.walkable(view.pose.x,view.pose.y)end
        check('mechanic_interior_keyboard_cannot_cross_mask_or_furniture',safe)
        check('mechanic_interior_never_changes_authoritative_exterior_pose_or_trip',original.x==123 and original.z==456
            and original.y==90 and original.sceneId=='commute' and persisted.home.commute.token==71
            and persisted.home.commute.origin=='warehouse' and persisted.home.commute.target=='mechanic')
        local x,y=view.pose.x,view.pose.y;R._commute.mechanicOffer.page='catalog';Interior.update(view,R,.1)
        check('mechanic_interior_catalog_pauses_local_walk',view.pose.x==x and view.pose.y==y and not view.pose.moving)
        Interior.release(view);Interior.release(view)
        check('mechanic_interior_release_is_idempotent_and_preserves_borrowed_bike',released==3 and quads==5 and borrowReleased==0)
        local before=calls;Interior.update(view,R,.1)
        check('mechanic_interior_closed_view_cannot_request_assets',calls==before)
        Loader.load=function()calls=calls+1;return nil,'pending'end
        local pending=Interior.new(R);Interior.draw(pending,R);Interior.update(pending,R,.1);Interior.release(pending)
        check('mechanic_interior_closing_loading_view_cancels_owned_request',canceled==1)
        local route=Interior.path(620,280,700,430);local exit=Interior.path(700,430,640,248)
        check('mechanic_interior_counter_and_exit_connected_by_approved_floor',route~=nil and #route>0 and exit~=nil and #exit>0)
    end)
    love.graphics,Loader.load,Loader.cancel,Fonts.get,Presentation.indoor=originalGraphics,originalLoad,originalCancel,originalFont,originalIndoor
    if not okay then error(reason)end
end
return Test
