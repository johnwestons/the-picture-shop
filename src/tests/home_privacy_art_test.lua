local PixelCanvas=require('src.tests.support.pixel_canvas')
local Routine=require("src.home_routine_pose")
local Residents=require("src.home_residents")
local Layout=require("src.home_layouts")
local Fixtures=require("src.tests.home_dining_test")
local Schema=require("src.save_schema")

local Test={}
local function capture(canvas,name)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if not folder then return end
    local data=canvas:newImageData();local bytes=data:encode("png")
    local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
    bytes:release();data:release()
end

function Test.run(context,check)
    for _,kind in ipairs({"bathe","toilet"}) do
        local target=kind=="bathe" and "bath" or "toilet"
        local state,player=Fixtures.fresh()
        player.character="rabbit-worker"
        player.x,player.y=Layout.toWorld(unpack(Layout.get(state).fixtures[target].approach))
        local startX,startY=player.x,player.y
        assert(Residents.command(state,player,kind..":"..target))
        local pose=assert(Routine.get(state,player))
        check("home_privacy_"..kind.."_is_marked",pose.privacy and pose.privacyKind==kind)
        check("home_privacy_"..kind.."_keeps_physics",pose.x==startX and pose.y==startY
            and player.x==startX and player.y==startY)
        local snapshot=Schema.snapshot(state)
        local replay=require("src.state").new()
        assert(require("src.state").applySharedSnapshot(replay,snapshot))
        local remote=assert(Routine.get(replay,player))
        check("home_privacy_"..kind.."_snapshot_same_pose",remote.privacy
            and remote.privacyKind==kind and remote.direction==pose.direction
            and remote.x==pose.x and remote.y==pose.y and Schema.validState(snapshot))

        local canvas=PixelCanvas(240,180)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.05,.06,.08,1)
        love.graphics.translate(120-pose.x,90-pose.y)
        check("home_privacy_"..kind.."_draws",Routine.draw(pose,player,context.characterAssets)==true)
        love.graphics.pop()
        local data=canvas:newImageData();local visible=false
        for x=0,239,8 do for y=0,179,8 do
            local r,g,b,a=data:getPixel(x,y)
            if a>.4 and (r>.08 or g>.09 or b>.1) then visible=true end
        end end
        capture(canvas,"home-privacy-"..kind)
        data:release();canvas:release()
        check("home_privacy_"..kind.."_draw_has_coverage",visible)

        player.x=startX+3
        check("home_privacy_"..kind.."_movement_clears",Routine.get(state,player)==nil)
        player.x=startX
        assert(Residents.command(state,player,"cancel"))
        check("home_privacy_"..kind.."_cancel_clears",Routine.get(state,player)==nil)
    end
    local guestState,guest=Fixtures.fresh()
    guest.character="business-cat"
    local toilet=Layout.get(guestState).fixtures.toilet
    guest.x,guest.y=Layout.toWorld(unpack(toilet.approach))
    assert(Residents.command(guestState,guest,"toilet:toilet"))
    local guestPose=assert(Routine.get(guestState,guest))
    check("home_privacy_non_rabbit_guest_is_marked",guestPose.privacy and guestPose.privacyKind=="toilet")
    check("home_privacy_non_rabbit_guest_draws",Routine.draw(guestPose,guest,context.characterAssets)==true)
    Routine.release()
end

return Test
