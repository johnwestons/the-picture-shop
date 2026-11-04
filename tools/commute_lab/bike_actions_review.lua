local Review={}
local function save(canvas,path)
    local pixels=canvas:newImageData();local png=pixels:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();pixels:release()
end
local function samples()
    local Bike=require('src.commute.motorcycle');local durations=require('src.commute.riding_animation').durations
    return {
        {'upright',{speed=0}},
        {'boostMid',{speed=6,ridingAction='boost',ridingActionTime=durations.boost*5/6}},
        {'boost',{speed=6,ridingAction='boost',ridingActionTime=durations.boost/2}},
        {'brakeMid',{speed=8,brakingPose=.5}},{'brake',{speed=8,brakingPose=1}},
        {'turnLeftMid',{lean=.225}},{'turnLeft',{lean=.3}},
        {'turnRightMid',{lean=-.225}},{'turnRight',{lean=-.3}},
        {'aeroMid',{speed=(Bike.TUCK_START_SPEED+Bike.BOOST_MAX_SPEED)/2}},
        {'aero',{speed=Bike.BOOST_MAX_SPEED}},
        {'shiftMid',{ridingAction='shift',ridingActionTime=durations.shift*5/6}},
        {'shift',{ridingAction='shift',ridingActionTime=durations.shift/2}},
        {'impactMid',{impactPulse=Bike.IMPACT_DURATION*5/6,impactStrength=1}},
        {'impact',{impactPulse=Bike.IMPACT_DURATION/2,impactStrength=1}}
    }
end
local function capture(check)
    local Art=require('src.commute.bike_art');local Bike=require('src.commute.motorcycle')
    local Camera=require('src.commute.camera');local g=love.graphics
    local world={height=function()return 0 end,supportHeight=function()return 0 end}
    local actor=Bike.new(0,0,0);actor.h=0
    local camera=Camera.new(actor,world);camera.yaw=0;camera.zoom=1.35
    local art=Art.new();local output=assert(os.getenv('PICTURE_SHOP_BIKE_ACTION_OUTPUT'))
    local canvas=g.newCanvas(320,320);local records={};local calls={};local draw=g.draw
    g.draw=function(image,quad,...)
        local info=art:describe(image,quad)
        if info then
            local _,_,_,alpha=g.getColor();info.alpha=alpha;calls[#calls+1]=info
        end
        return draw(image,quad,...)
    end
    local okay,reason=xpcall(function()
        for _,sample in ipairs(samples()) do
            local state,visual=sample[1],sample[2]
            visual.ridingAction=visual.ridingAction or 'idle';visual.grounded=true
            local sheet=g.newCanvas(1600,1760)
            g.push('all');g.setCanvas(sheet);g.clear(.13,.19,.20,1);g.pop()
            local covered=true;records[state]={}
            for frame=1,64 do
                actor.heading=-math.pi/2+(frame-1)*math.pi/32;camera.screen=function()return 160,270 end
                calls={};g.push('all');g.setCanvas(canvas);g.clear(.13,.19,.20,1)
                art:draw(actor,camera,world,false,visual);g.pop()
                local call=calls[1]
                covered=covered and #calls==1 and call.state==state and call.frame==frame and call.alpha==1
                records[state][frame]=('{"frame":%d,"state":"%s","drawnFrame":%d,"count":%d,"alpha":%.3f}')
                    :format(frame,call and call.state or 'missing',call and call.frame or 0,#calls,call and call.alpha or 0)
                save(canvas,output..('/native-%s-%02d.png'):format(state,frame))
                local left,top=(frame-1)%8*200,math.floor((frame-1)/8)*220
                g.push('all');g.setCanvas(sheet);g.setColor(1,1,1,1)
                draw(canvas,left,top+10,0,200/320,200/320)
                g.setColor(.95,.92,.78);g.print(('%s %02d / %g'):format(state,frame,(frame-1)*5.625),left+7,top+7);g.pop()
            end
            check('bike_action_native_'..state..'_draws_all_64_authored_views_once_at_full_opacity',covered)
            save(sheet,output..'/native-'..state..'-64-contact.png');sheet:release()
        end
        local residentBytes=art.actionPages.count*1280*1280*4+2560*2560*4+1280*1280*4
        check('bike_action_native_full_pose_review_stays_inside_previous_art_texture_budget',
            art.actionPages.peakCount<=12 and residentBytes<=14*1280*1280*4+2560*2560*4)
        local stateRecords={}
        for _,sample in ipairs(samples()) do local state=sample[1]
            stateRecords[#stateRecords+1]='"'..state..'":['..table.concat(records[state],',')..']'
        end
        local file=assert(io.open(output..'/native-draw-coverage.json','wb'))
        file:write(('{"peakActionPages":%d,"residentArtBytes":%d,"poses":{%s}}\n')
            :format(art.actionPages.peakCount,residentBytes,table.concat(stateRecords,',')));file:close()
    end,debug.traceback)
    g.draw=draw;canvas:release();art:release();assert(okay,reason)
end
function Review.install()
    function love.load()
        local count=0
        local function check(name,okay)assert(okay,name);count=count+1;print('PASS '..name)end
        for _,name in ipairs({'bike_action_pages','bike_action_pose','bike_particles','bike_tire_motion','riding_animation','trip'}) do
            require('src.commute.tests.'..name..'_test').run(check)
        end
        if os.getenv('PICTURE_SHOP_BIKE_ACTION_UNITS')=='1' then
            print('BIKE_ACTION_UNITS_OK '..count..' checks; no saves accessed')
            love.event.quit(0);return
        end
        for _,name in ipairs({'camera','follow_camera','first_person','bike_art','direction',
            'bike_pitch','bike_pitch_visual','ride_smoothing','motorcycle','controls','bike_paint'}) do
            require('src.commute.tests.'..name..'_test').run(check)
        end
        capture(check)
        print('BIKE_ACTIONS_64_OK '..count..' checks; fifteen poses, all64 headings, native PNG frames and contacts')
        love.event.quit(0)
    end
end
return Review
