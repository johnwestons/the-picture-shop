-- Exercise the real draw path: headless physics cannot catch a renderer that
-- writes into the live private prediction between fixed command steps.
local C=require('src.commute.runtime')
local P=require('src.commute.prediction')
local Rider=require('src.commute.rider')
local Truck=require('src.commute.delivery_truck')
local Bike=require('src.commute.motorcycle')
local Copy=require('src.net.shop_replication').copy
local Test={}
function Test.run(R,check)
    local part=C.localPart(R);local trip=R.state.home.commute;local player=R.World.player
    local oldRider,oldPresentation=part.rider,part.presentation
    local oldPrediction,oldPredicted=player._predictedCommute,player._movementPredicted
    local oldIsClient,oldAi=R.multiplayer.isClient,trip.aiMotorcycles
    local view=R._commute;local oldFeedback,oldTraffic=view.controlFeedback,view.trafficPresentation
    local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    local function draw()
        local g=love.graphics;g.push('all');g.setCanvas({canvas,stencil=true})
        local okay,err=xpcall(function()C.draw(R)end,debug.traceback)
        g.setCanvas();g.pop();if not okay then error(err,0)end
    end
    local okay,err=xpcall(function()
        R.multiplayer.isClient=function()return true end
        for _,mode in ipairs({'bike','box','kei','ped'})do
            local source=oldRider.bike
            local rider=Rider.new(source.x,source.z,source.heading,
                {version=1,outfit=mode=='bike' and 'geared' or 'normal',mounted=mode=='bike',
                    engine=mode=='bike',revision=13})
            rider.bike.h=C.world(R):supportHeight(source.x,source.z)
            if mode=='box' or mode=='kei' then
                rider.vehicle='truck';rider.truck=Truck.new(source.x,source.z,source.heading,nil,mode)
                rider.truck.h=rider.bike.h;rider.truck.speed=5;rider.truck.steering=.6
            else rider.bike.speed=5;rider.bike.steering=.6 end
            part.rider=rider;part.presentation={pose=mode=='bike' and 'riding' or 'normal_idle',
                steer=-.4,speed=5,heading=source.heading,brake=0}
            player._predictedCommute=nil;player._movementPredicted=true
            local prediction=assert(P.ensure(player,part,trip.token))
            local before=P.captureLocal(player);local bikeHeading=prediction.rider.bike.heading
            view.controlFeedback=P.presentation(prediction)
            -- Feedback can outlive an input/update; it must remain visual even
            -- when its value differs from the currently simulated controls.
            if mode~='ped'then view.controlFeedback.steer=.9 end
            for _=1,3 do draw()end
            local after=P.captureLocal(player);local exact=true
            for i,value in ipairs(before.values)do exact=exact and value==after.values[i] end
            check('commute_draw_never_changes_private_prediction_'..mode,exact
                and prediction.rider.bike.heading==bikeHeading,
                'bike heading before='..bikeHeading..' after='..prediction.rider.bike.heading)
        end
        local ai=Bike.new(oldRider.bike.x+8,oldRider.bike.z,oldRider.bike.heading)
        ai.h=C.world(R):supportHeight(ai.x,ai.z)
        trip.aiMotorcycles={{id=123,bike=ai}}
        view.trafficPresentation={['ai-123']={x=ai.x-2,z=ai.z-1,h=ai.h,heading=ai.heading-.2,
            targetX=ai.x-2,targetZ=ai.z-1,targetH=ai.h,targetHeading=ai.heading-.2,startedAt=love.timer.getTime()}}
        local before=Copy(ai)
        draw()
        check('commute_client_traffic_interpolation_keeps_authoritative_ai_pose',
            ai.x==before.x and ai.z==before.z and ai.h==before.h and ai.heading==before.heading)
        local shown
        for _,entry in ipairs(view.mapTraffic or {})do if entry.id=='ai-123'then shown=entry.actor end end
        check('commute_client_traffic_interpolation_uses_independent_visual_actor',shown and shown~=ai
            and math.abs(shown.x-ai.x)>.1)
    end,debug.traceback)
    part.rider,part.presentation=oldRider,oldPresentation
    player._predictedCommute,player._movementPredicted=oldPrediction,oldPredicted
    R.multiplayer.isClient,trip.aiMotorcycles=oldIsClient,oldAi
    view.controlFeedback,view.trafficPresentation=oldFeedback,oldTraffic
    canvas:release()
    if not okay then error(err,0)end
end
return Test
