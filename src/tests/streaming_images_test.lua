local Test={}
local Loader=require("src.image_loader")
local function untilReady(step)
    local started=love.timer.getTime()
    repeat
        Loader.update()
        local ready=step()
        if ready then return ready end
        assert(love.timer.getTime()-started<15,"Streaming image timeout")
        love.timer.sleep(.001)
    until false
end
function Test.run(context,check)
    local characters,assets=context.characterAssets,context.assets
    local pack=assets.activePackName()
    Loader.shutdown();Loader.setEnabled(false)
    characters.retainCharacters({},false)
    assert(characters.get("rabbit-worker","idle_south",1))
    Loader.setEnabled(true)
    local originalDecode=love.image.newImageData
    local originalUpload=love.graphics.newImage
    local decodes,uploads,largestUpload=0,0,0
    local okay,reason=xpcall(function()
        love.image.newImageData=function(source,...)
            if type(source)=="string" then decodes=decodes+1 end
            return originalDecode(source,...)
        end
        love.graphics.newImage=function(source,...)
            if type(source)=="string" then decodes=decodes+1 end
            if type(source)~="string" then
                largestUpload=math.max(largestUpload,source:getWidth()*source:getHeight()*4)
            end
            uploads=uploads+1;return originalUpload(source,...)
        end
        local resolved=characters.resolveAction("rabbit-worker","walk_north")
        check("streaming_character_holds_loaded_pose_while_direction_decodes",resolved=="idle_south")
        untilReady(function()
            if characters.resolveAction("rabbit-worker","walk_north")=="walk_north" then
                return characters.get("rabbit-worker","walk_north",1)
            end
        end)
        check("streaming_png_decode_never_runs_on_game_thread",decodes==0 and uploads>0)
        local path=require("src.config").paths.cutterBlade
        local image,why=Loader.load(path)
        assert(not image and why=="pending")
        local previousUploads=uploads
        untilReady(function()
            local value,message=Loader.load(path)
            if not value and message~="pending" then error(message) end
            return value
        end):release()
        check("streaming_uploads_use_bounded_decoded_strips",decodes==0 and uploads>previousUploads
            and largestUpload<=2*1024*1024)
        local missing="assets/generated/does-not-exist-streaming-test.png"
        untilReady(function()
            local value,message=Loader.load(missing)
            return not value and message~="pending" and message
        end)
        check("streaming_missing_image_reports_failure_without_sync_retry",decodes==0)
    end,debug.traceback)
    love.image.newImageData,love.graphics.newImage=originalDecode,originalUpload
    Loader.shutdown();Loader.setEnabled(false)
    if not okay then error(reason) end
    assert(assets.activatePack("menu"))
    local previousBytes=assets.textureBytes()
    Loader.setEnabled(true)
    local ready=assets.activatePack("cutter")
    check("streaming_screen_retires_old_pack_before_large_new_uploads",ready==nil
        and assets.activePackName()==nil and assets.isLoading() and assets.textureBytes()<previousBytes)
    untilReady(function() return assets.activatePack("menu") end)
    check("streaming_cancel_restores_valid_shared_screen_textures",assets.get("polarOperatorConsole")~=nil
        and assets.get("polarOperatorConsole"):getWidth()>0 and not assets.isLoading())
    untilReady(function() return assets.activatePack("cutter") end)
    check("streaming_screen_finishes_with_required_textures",assets.activePackName()=="cutter"
        and assets.get("cutterBlade")~=nil and not assets.isLoading())
    Loader.shutdown();Loader.setEnabled(false)
    assert(assets.activatePack(pack))
    characters.retainCharacters({},false)
    local data=love.image.newImageData(1024,768)
    for _,y in ipairs({0,511,512,767}) do data:setPixel(50,y,.4,.7,.2,.5) end
    local upload=require("src.texture_upload").new(data)
    local texture=upload:step()
    check("streaming_large_atlas_requires_more_than_one_upload_step",texture==nil)
    texture=assert(upload:step())
    local pixels=texture:newImageData()
    local same=true
    for _,y in ipairs({0,511,512,767}) do
        local r,g,b,a=pixels:getPixel(50,y)
        same=same and math.abs(r-.4)<.01 and math.abs(g-.7)<.01
            and math.abs(b-.2)<.01 and math.abs(a-.5)<.01
    end
    check("streaming_strip_boundaries_preserve_source_alpha_and_colors",same)
    pixels:release()
    local target=love.graphics.newCanvas(1024,768)
    love.graphics.push("all");love.graphics.setCanvas(target);love.graphics.origin()
    love.graphics.setScissor();love.graphics.setStencilTest();love.graphics.setShader()
    love.graphics.clear(0,0,0,1);love.graphics.setColor(1,1,1,1)
    love.graphics.setBlendMode("alpha","alphamultiply");love.graphics.draw(texture)
    love.graphics.pop()
    pixels=target:newImageData()
    local r,g,b=pixels:getPixel(50,512)
    check("streaming_atlas_keeps_original_sprite_blending_contract",
        math.abs(r-.2)<.01 and math.abs(g-.35)<.01 and math.abs(b-.1)<.01)
    pixels:release();target:release();texture:release()
end
return Test
