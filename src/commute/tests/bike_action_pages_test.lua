local Pages=require('src.commute.bike_action_pages')
local Test={}
function Test.run(check)
    local getInfo,newImage,newQuad=love.filesystem.getInfo,love.graphics.newImage,love.graphics.newQuad
    local live,peak,loads,quadReleases=0,0,0,0
    love.filesystem.getInfo=function()return {type='file'}end
    love.graphics.newImage=function(path)
        live=live+1;peak=math.max(peak,live);loads=loads+1
        local released=false
        return {path=path,getWidth=function()return 1280 end,getHeight=function()return 1280 end,
            setFilter=function()end,release=function()assert(not released,'Double texture release');released=true;live=live-1 end}
    end
    love.graphics.newQuad=function(x,y,w,h,tw,th)
        return {getViewport=function()return x,y,w,h end,getTextureDimensions=function()return tw,th end,
            release=function()quadReleases=quadReleases+1 end}
    end
    local okay,reason=xpcall(function()
        local pages=Pages.new()
        check('bike_action_pages_validate_all_art_without_eager_texture_uploads',loads==0 and pages.count==0)
        local all=true
        for _,state in ipairs(Pages.states) do for frame=1,64 do
            local image,quad,page=pages:get(state,frame);local info=pages:describe(image,quad)
            local x,y,w,h=quad:getViewport();local localFrame=(frame-1)%16
            all=all and info.state==state and info.frame==frame and page==math.floor((frame-1)/16)+1
                and x==localFrame%4*320 and y==math.floor(localFrame/4)*320 and w==320 and h==320
                and image.path==Pages.path(state,page)
        end end
        check('bike_action_pages_resolve_every_pose_and_all_64_views_including_page_boundaries',all)
        check('bike_action_pages_bound_peak_texture_memory_across_all_pose_families',peak==12 and pages.peakCount==12
            and live==12 and live*1280*1280*4<=79*1024*1024 and loads==#Pages.states*4)
        local image=pages:get('turnRight',64);local before=loads
        for _=1,120 do assert(pages:get('turnRight',64)==image) end
        check('bike_action_pages_steady_heading_reuses_current_texture',loads==before)
        pages:prepare('brake',17)
        check('bike_action_pages_prepare_both_stages_before_pose_transition',
            pages:describe(pages:get('brakeMid',17),pages.quads[1]).frame==17
            and pages:describe(pages:get('brake',32),pages.quads[16]).frame==32)
        check('bike_action_pages_reject_old_art_and_out_of_range_views',
            not pcall(function()pages:get('old16',1)end) and not pcall(function()pages:get('boost',65)end))
        pages:release();check('bike_action_pages_release_cached_textures_and_shared_quads',live==0 and quadReleases==16)
        love.filesystem.getInfo=function(path)return not path:find('brake%-4') and {type='file'} or nil end
        local prior=loads;check('bike_action_pages_missing_direction_fails_before_loading_art',not pcall(Pages.new) and loads==prior)
    end,debug.traceback)
    love.filesystem.getInfo,love.graphics.newImage,love.graphics.newQuad=getInfo,newImage,newQuad
    assert(okay,reason)
end
return Test
