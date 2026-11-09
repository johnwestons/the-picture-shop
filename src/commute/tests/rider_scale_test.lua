local Scale=require('src.commute.rider_scale')
local Config=require('src.config')
local GearArt=require('src.commute.gear_action_art')
local Test={}
local function near(a,b) return math.abs(a-b)<.000001 end

function Test.run(check)
    local graphics=love.graphics
    local originalFactory=GearArt.new
    local originalIndoorScale=Config.player.drawScale
    local draws,vectorScale={},nil
    local function noop() end
    local function record(image,quad,x,y,rotation,sx,sy,ax,ay)
        draws[#draws+1]={image=image,quad=quad,x=x,y=y,sx=sx,sy=sy,ax=ax,ay=ay}
    end
    love.graphics={draw=record,setColor=noop,push=noop,pop=noop,setShader=noop,
        translate=noop,scale=function(value)vectorScale=value end,
        ellipse=noop,rectangle=noop,line=noop,circle=noop,setLineWidth=noop}
    GearArt.new=function(options)
        return {registration=options.registration,draw=function(_,action,frame,x,y,scale)
            record('gear',action,x,y,0,scale,scale,128,238)
            return true
        end}
    end
    local okay,err=xpcall(function()
        -- Isolate the lazy gear cache so mocked strips cannot leak into gameplay.
        local P=assert(love.filesystem.load('src/commute/presentation.lua'))()
        local assets={hasAction=function()return true end,
            get=function(character,action,frame)return character,action,8 end,
            getAnchor=function()return 128,238 end,
            getNormalization=function(character)return 256/(character=='suited-rider' and 217 or 402) end}
        local camera={zoom=1,screen=function()return 123,456 end,
            headingDirection=function(_,heading)return heading end}
        local actor={x=1,z=2,h=3,heading='east',distance=.39,speed=0}
        local world={supportHeight=function()error('explicit actor height should be retained')end}
        local appearance={character='rabbit-worker',furColorway=1,overallsColorway=1}
        local directions={'north','northeast','east','southeast','south','southwest','west','northwest'}
        local mirror={west=true,northwest=true,southwest=true}
        local coverage,anchors=true,true
        for _,outfit in ipairs({'normal','geared'}) do
            for _,direction in ipairs(directions) do
                for _,speed in ipairs({0,1.7}) do
                    for _,zoom in ipairs({.55,1,1.8}) do
                        draws={};camera.zoom=zoom;actor.heading=direction;actor.speed=speed
                        coverage=P.world(assets,actor,camera,world,{outfit=outfit},appearance) and coverage
                        local draw=draws[#draws]
                        local height=outfit=='geared' and 217 or 402
                        coverage=coverage and draw and near(draw.sy*height,80*zoom)
                            and (draw.sx<0)==(mirror[direction] or false)
                            and draw.quad:find(speed==0 and 'idle' or 'walk',1,true)==1
                        anchors=anchors and draw and draw.ax==128 and draw.ay==238 and draw.x==123 and draw.y==456
                    end
                end
            end
        end
        check('commute_road_stature_matches_across_eight_views_outfits_motion_and_zoom',coverage)
        check('commute_road_resize_keeps_original_ground_anchors_and_actor_height',anchors)

        camera.zoom=1;actor.heading='southeast'
        local gearOkay=true
        for _,pose in ipairs({'suit_on','zip_up','boots_gloves','helmet_on','helmet_off','unzip','suit_off'}) do
            draws={}
            P.world(assets,actor,camera,world,{outfit='geared'},appearance,{pose=pose,progress=.5})
            local action=GearArt.actionFrameForPose(pose,.5)
            local height=GearArt.registration.actions[action].normalizationHeight
            gearOkay=gearOkay and draws[1] and draws[1].image=='gear' and near(draws[1].sy*height,80)
        end
        check('commute_dressing_and_removal_share_road_stature',gearOkay)

        Config.player.drawScale=.13;draws={}
        P.world(assets,actor,camera,world,{outfit='geared'},appearance)
        check('commute_road_stature_is_independent_of_indoor_draw_scale',near(draws[1].sy*217,80))
        Config.player.drawScale=originalIndoorScale

        local fallbacks=true
        for _,outfit in ipairs({'normal','geared'}) do
            for _,zoom in ipairs({.25,1,2}) do
                vectorScale=nil
                P.foot(0,0,zoom,{outfit=outfit},0,0,nil,appearance)
                local height=outfit=='geared' and 64 or 77
                fallbacks=fallbacks and vectorScale and near(vectorScale*height,80*zoom)
            end
        end
        check('commute_loading_and_first_person_remote_fallbacks_share_road_stature',fallbacks)

        local Residents=require('src.home_residents')
        local display=Residents.display
        Residents.display=function()return nil end
        draws={}
        local indoorOkay,indoorError=pcall(P.indoor,{x=5,y=6,character='rabbit-worker',
            intentX=1,intentY=0,moving=false}, {},assets,{outfit='geared'})
        Residents.display=display
        assert(indoorOkay,indoorError)
        check('commute_resize_does_not_change_apartment_character_scale',
            draws[1] and near(draws[1].sy*217,256*originalIndoorScale))

        local BikeArt=require('src.commute.bike_art')
        check('commute_resize_preserves_sixteen_bike_views_and_bike_scale',
            BikeArt.FRAME_COUNT==16 and #BikeArt.directions==16 and BikeArt.SCALE==.46)
    end,debug.traceback)
    love.graphics=graphics;GearArt.new=originalFactory;Config.player.drawScale=originalIndoorScale
    assert(okay,err)
end

return Test
