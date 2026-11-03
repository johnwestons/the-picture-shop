local Art=require('src.commute.bike_art')
local Camera=require('src.commute.camera')
local Test={}
function Test.run(check)
    local world=require('src.commute.roads').new():attach(require('src.commute.terrain').new())
    local camera=Camera.new({x=100,z=380},world);camera.yaw=0
    local headings={-math.pi/2,-math.pi/4,0,math.pi/4,math.pi/2,math.pi*.75,math.pi,math.pi*1.25}
    local directions=true
    for i,angle in ipairs(headings) do directions=directions and Art.frame(camera,angle,8)==i end
    check('commute_bike_art_eight_independent_views_resolve',directions)
    local sixteen=true
    for i=1,16 do sixteen=sixteen and Art.frame(camera,-math.pi/2+(i-1)*math.pi/8,16)==i end
    check('commute_bike_art_sixteen_independent_views_resolve',sixteen)
    local first,second,blend=Art.frameBlend(camera,-math.pi/2+math.pi/16,16)
    local wrapFirst,wrapSecond,wrapBlend=Art.frameBlend(camera,-math.pi/2-math.pi/16,16)
    check('commute_bike_art_blends_adjacent_heading_views_without_sector_pop',first==1 and second==2
        and math.abs(blend-.5)<1e-8 and wrapFirst==16 and wrapSecond==1 and math.abs(wrapBlend-.5)<1e-8)
    camera:orbit(90,0)
    check('commute_bike_art_view_follows_camera_orbit',Art.frame(camera,0,8)==5 and Art.frame(camera,0,16)==9)
    local art=Art.new()
    local atlases=true;local count=0
    for _,image in pairs(art.images) do
        count=count+1
        atlases=atlases and image:getWidth()==1280 and image:getHeight()==art.atlasHeight
    end
    check('commute_bike_art_all_pose_atlases_match_selected_layout',atlases and count==14
        and #art.quads==16 and art.frameCount==16 and art.atlasHeight==1280)
    local cells=true
    for i,quad in ipairs(art.quads) do
        local x,y,w,h=quad:getViewport()
        local tw,th=quad:getTextureDimensions()
        cells=cells and x==(i-1)%4*320 and y==math.floor((i-1)/4)*320 and w==320 and h==320
            and tw==1280 and th==art.atlasHeight
    end
    check('commute_bike_art_quads_match_installed_atlas_rows',cells)
    art:release()

    -- Missing sixteen-view art is an explicit packaging error. Legacy eight
    -- atlases must never silently reduce the number of displayed directions.
    local getInfo,newImage=love.filesystem.getInfo,love.graphics.newImage
    local okay,err=xpcall(function()
        for _,scenario in ipairs({'absent','partial','complete'}) do
            love.filesystem.getInfo=function(path)
                if scenario=='absent' or (scenario=='partial' and path:find('mounted%-aero%-tuck%-16')) then return nil end
                return {type='file'}
            end
            local loaded=0
            love.graphics.newImage=function(path)
                assert(path:match('%-16%.png$'),'Eight-view fallback must not load: '..path)
                loaded=loaded+1
                return {getWidth=function()return 1280 end,getHeight=function()return 1280 end,
                    setFilter=function()end,release=function()end}
            end
            local created,fixture=pcall(Art.new)
            if scenario=='complete' then
                local lastX,lastY=fixture.quads[16]:getViewport()
                check('commute_bike_art_complete_sixteen_view_install_loads_all_poses',created and loaded==14
                    and fixture.frameCount==16 and #fixture.quads==16 and lastX==960 and lastY==960)
                fixture:release()
            else
                check('commute_bike_art_'..scenario..'_sixteen_view_install_fails_before_image_load',not created and loaded==0
                    and tostring(fixture):find('Missing sixteen-view motorcycle atlas',1,true)~=nil)
            end
        end
    end,debug.traceback)
    love.filesystem.getInfo,love.graphics.newImage=getInfo,newImage
    assert(okay,err)
end
return Test
