local Art=require('src.commute.bike_art')
local Camera=require('src.commute.camera')
local PaintArt=require('src.commute.bike_paint_art')
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
    local sixtyFour=true
    for i=1,64 do sixtyFour=sixtyFour and Art.frame(camera,-math.pi/2+(i-1)*math.pi/32,64)==i end
    check('commute_bike_art_sixty_four_upright_views_resolve',sixtyFour)
    camera:orbit(90,0)
    check('commute_bike_art_view_follows_camera_orbit',Art.frame(camera,0,8)==5 and Art.frame(camera,0,16)==9)
    local art=Art.new()
    local atlases=true;local count=0
    for _,image in pairs(art.images) do
        count=count+1
        if image==art.images.upright then
            atlases=atlases and image:getWidth()==2560 and image:getHeight()==2560
        else atlases=atlases and image:getWidth()==1280 and image:getHeight()==art.atlasHeight end
    end
    check('commute_bike_art_base_atlases_and_lazy_action_pages_match_layout',atlases and count==2
        and #art.quads==16 and #art.uprightQuads==64 and art.frameCount==64 and art.parkedFrameCount==16
        and #art.actionPages.quads==16 and art.actionPages.count==0 and art.atlasHeight==1280)
    local actions=true
    for _,state in ipairs(Art.ACTION_STATES) do for frame=1,64 do
        local image,quad=art:resolve(state,frame);local info=art:describe(image,quad)
        actions=actions and info.state==state and info.frame==frame and info.page==math.floor((frame-1)/16)+1
    end end
    check('commute_bike_art_all_896_action_views_resolve_without_legacy_atlases',actions and art.actionPages.peakCount==12)
    local cells=true
    for i,quad in ipairs(art.quads) do
        local x,y,w,h=quad:getViewport()
        local tw,th=quad:getTextureDimensions()
        cells=cells and x==(i-1)%4*320 and y==math.floor((i-1)/4)*320 and w==320 and h==320
            and tw==1280 and th==art.atlasHeight
    end
    check('commute_bike_art_quads_match_installed_atlas_rows',cells)
    local denseCells=true
    for i,quad in ipairs(art.uprightQuads) do
        local x,y,w,h=quad:getViewport();local tw,th=quad:getTextureDimensions()
        denseCells=denseCells and x==(i-1)%8*320 and y==math.floor((i-1)/8)*320
            and w==320 and h==320 and tw==2560 and th==2560
    end
    check('commute_bike_art_sixty_four_quads_cover_every_row_including_final_cell',denseCells)
    -- Read actual packaged pixels: a valid layout alone cannot catch the
    -- alternating head-size pulse that affected the previous 64-view set.
    local previous=love.image.newImageData('assets/commute/bike/mounted-upright-64.png')
    local regenerated=love.image.newImageData(Art.UPRIGHT_PATH)
    local oldCell,newCell=love.image.newImageData(320,320),love.image.newImageData(320,320)
    local hashes,widths={},{};local unique,changed,registered=true,true,true
    for i=0,63 do
        local x,y=i%8*320,math.floor(i/8)*320
        oldCell:paste(previous,0,0,x,y,320,320)
        newCell:paste(regenerated,0,0,x,y,320,320)
        local hash=love.data.hash('sha256',newCell:getString())
        unique=unique and not hashes[hash];hashes[hash]=true
        changed=changed and hash~=love.data.hash('sha256',oldCell:getString())
        local left,right,top=320,-1,320
        for py=65,105 do for px=0,319 do
            local _,_,_,a=newCell:getPixel(px,py)
            if a>=16/255 then left=math.min(left,px);right=math.max(right,px);top=math.min(top,py) end
        end end
        widths[i+1]=right-left+1
        registered=registered and top>=69 and top<=71 and widths[i+1]>=47 and widths[i+1]<=60
    end
    check('commute_bike_art_all_64_views_are_independently_regenerated_and_unique',unique and changed)
    check('commute_bike_art_regenerated_helmet_height_and_scale_stay_registered',registered)
    local maximum,total=0,0
    for i=1,64 do
        local delta=math.abs(widths[i]-widths[i%64+1]);maximum=math.max(maximum,delta);total=total+delta
    end
    check('commute_bike_art_adjacent_sizes_and_wrap_avoid_previous_alternating_pulse',maximum<=3 and total/64<=1.15)
    previous:release();regenerated:release();oldCell:release();newCell:release()
    art:release()

    -- Validate every action page before uploading any texture.
    local getInfo,newImage=love.filesystem.getInfo,love.graphics.newImage
    local okay,err=xpcall(function()
        for _,scenario in ipairs({'absent','partial','uprightAbsent','complete'}) do
            love.filesystem.getInfo=function(path)
                if scenario=='absent' or (scenario=='partial' and path:find('actions%-64/brake%-4%.png')) then return nil end
                if scenario=='uprightAbsent' and path==Art.UPRIGHT_PATH then return nil end
                return {type='file'}
            end
            local loaded=0
            love.graphics.newImage=function(path)
                assert(path=='assets/commute/bike/parked-16.png' or path==Art.UPRIGHT_PATH,'Legacy action must not load: '..path)
                loaded=loaded+1
                return {getWidth=function()return path==Art.UPRIGHT_PATH and 2560 or 1280 end,
                    getHeight=function()return path==Art.UPRIGHT_PATH and 2560 or 1280 end,
                    setFilter=function()end,release=function()end}
            end
            local created,fixture=pcall(Art.new)
            if scenario=='complete' then
                local lastX,lastY=fixture.quads[16]:getViewport()
                check('commute_bike_art_complete_install_loads_two_base_textures_and_validates_64_view_actions',created and loaded==2
                    and fixture.frameCount==64 and #fixture.quads==16 and #fixture.uprightQuads==64 and lastX==960 and lastY==960)
                fixture:release()
            else
                check('commute_bike_art_'..scenario..'_install_fails_before_image_load',not created and loaded==0
                    and tostring(fixture):find('Missing',1,true)~=nil)
            end
        end
    end,debug.traceback)
    love.filesystem.getInfo,love.graphics.newImage=getInfo,newImage
    assert(okay,err)
    require('src.commute.tests.bike_view_test').run(check)

    -- Reproduce the small first-person lean blend reached around a wall hit.
    -- The cache warmer needs the rider's lean even while the selected atlas
    -- state is still upright.
    local prepared={}
    local drawArt=setmetatable({images={upright={}},uprightQuads={[1]={}},actionPages={
        prepare=function(_,state,frame) prepared[#prepared+1]={state=state,frame=frame} end,
        get=function() return {},{} end,
    }},Art)
    local draw, setColor, previousLean=PaintArt.draw,love.graphics.setColor,rawget(_G,'lean')
    PaintArt.draw=function() end
    love.graphics.setColor=function() end
    _G.lean=nil
    local okay=pcall(function()
        drawArt:draw({x=100,z=100,heading=0,lean=.18,speed=0,grounded=true,paintId='bronze'},
            {firstPerson=true,viewHeading=0,zoom=1,screen=function() return 640,440,.5 end},
            {supportHeight=function() return 0 end},false)
    end)
    PaintArt.draw,love.graphics.setColor, _G.lean=draw,setColor,previousLean
    check('commute_bike_art_first_person_turn_cache_uses_actor_lean_during_wall_crash',
        okay and prepared[1] and prepared[1].state=='turnLeft')
end
return Test
