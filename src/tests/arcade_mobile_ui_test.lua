local Hockey=require("src.air_hockey")
local Wheel=require("src.screens.air_hockey_screen")
local Arcade=require("src.screens.critter_kombat_screen")
local Viewport=require("src.viewport")
local Test={}
local function capture(runtime,screen,name)
    local dir=os.getenv("PICTURE_SHOP_ARCADE_CAPTURE_DIR")
    if not dir then return end
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.clear()
    love.graphics.setFont(love.graphics.newFont("assets/fonts/VT323-Regular.ttf",20))
    screen.draw(runtime);love.graphics.setCanvas();love.graphics.pop()
    local data=canvas:newImageData();local encoded=data:encode("png")
    local file=assert(io.open(dir.."/"..name..".png","wb"));file:write(encoded:getString());file:close()
    data:release();encoded:release();canvas:release()
end
function Test.run(_,check)
    local oldMatches=Hockey.matches
    local oldDimensions,oldSafeArea=love.graphics.getDimensions,love.window.getSafeArea
    local runtime={state={},World={player={id=1}},Config={baseWidth=960,baseHeight=678},Viewport=Viewport,
        App={officeUsesSafeArea=function()return false end},multiplayer={
            isClient=function()return false end,isHost=function()return false end,
            isActive=function()return false end,sendNeutralInput=function()end},
        Assets={clearCache=function()end},CharacterAssets={clearCache=function()end},
        WorldRenderer={clearCache=function()end},saveCurrent=function()end}
    local match={bayId="front_left",leftId=1,rightId=2,leftX=200,leftY=200,rightX=600,rightY=200,
        leftScore=0,rightScore=0,puckX=400,puckY=200,puckVX=0,puckVY=0,
        mode="versus",phase="playing",accumulator=0,faceoff=1,elapsed=0}
    Hockey.matches={front_left=match}
    local px,py=121,328
    runtime.pointerPosition=function()return px,py end
    runtime.toPointerCoordinates=function(x,y)return Viewport.toGame(x,y,960,678,false)end
    local function neutral()
        local x,y=Wheel.controls(runtime,0,0);return x==0 and y==0
    end
    local ok,err=xpcall(function()
        for _,size in ipairs({{2340,1080},{1280,800},{960,678}}) do
            local w,h=size[1],size[2]
            love.graphics.getDimensions=function()return w,h end
            love.window.getSafeArea=function()return 85,0,w-120,h-24 end
            local ox,oy,s=Viewport.transform(960,678,false)
            local function point(x,y)return ox+x*s,oy+y*s end
            local tag=w.."x"..h
            Wheel.enter(runtime,"front_left")
            check("hockey_wheel_captures_"..tag,Wheel.touchpressed(runtime,"owner",point(121,328)))
            check("hockey_wheel_deadzone_"..tag,neutral())
            Wheel.touchmoved(runtime,"owner",point(181,328))
            local x,y=Wheel.controls(runtime,0,0)
            check("hockey_wheel_android_coordinates_"..tag,math.abs(x-1)<.001 and math.abs(y)<.001)
            Wheel.touchpressed(runtime,"other",point(121,328));Wheel.touchmoved(runtime,"other",point(60,328))
            Wheel.touchreleased("other");Wheel.mousereleased()
            x,y=Wheel.controls(runtime,0,0)
            check("hockey_other_finger_and_mouse_release_keep_owner_"..tag,x>.99 and math.abs(y)<.001)
            Wheel.touchmoved(runtime,"owner",point(500,700))
            x,y=Wheel.controls(runtime,0,0)
            check("hockey_wheel_diagonal_clamped_"..tag,x>0 and y>0 and math.abs(x*x+y*y-1)<.001)
            Wheel.touchmoved(runtime,"owner",point(121,268))
            local before=match.leftY
            Hockey.update(1/60,function(id)
                if id~=1 then return {x=0,y=0} end
                local ix,iy=Wheel.controls(runtime,0,0);return {x=ix,y=iy}
            end)
            check("hockey_wheel_moves_authoritative_paddle_"..tag,match.leftY<before and match.rightY==200)
            Wheel.touchreleased("owner")
            check("hockey_wheel_release_stops_"..tag,neutral())
            local yStopped=match.leftY
            Hockey.update(1/60,function()local ix,iy=Wheel.controls(runtime,0,0);return {x=ix,y=iy}end)
            check("hockey_paddle_stays_stopped_"..tag,match.leftY==yStopped)
            Arcade.enter(runtime,"front_right")
            Arcade.touchpressed(runtime,"game1",point(270,400))
            check("arcade_first_touch_choice_"..tag,Arcade.view=="title")
            Arcade.enter(runtime,"front_right")
            Arcade.touchpressed(runtime,"game2",point(690,400))
            check("arcade_second_touch_choice_"..tag,Arcade.view=="crisis")
        end
        Wheel.enter(runtime,"front_left")
        runtime.multiplayer.isClient=function()return true end
        runtime.multiplayer.gameSnapshot=function()return {match}end
        runtime.World.player.id=2
        Wheel.touchpressed(runtime,"guest",121,328);Wheel.touchmoved(runtime,"guest",61,328)
        local x=Wheel.controls(runtime,0,0)
        check("hockey_guest_wheel_uses_snapshot",x==-1)
        runtime.World.player.id=3
        check("hockey_spectator_cannot_move_paddle",neutral())
        runtime.World.player.id=1;runtime.multiplayer.isClient=function()return false end
        Wheel.cancelInputs(false)
        px,py=205+(match.leftX+70)*.86,150+match.leftY*.86
        Wheel.mousepressed(runtime,px,py,1)
        x=Wheel.controls(runtime,0,0)
        check("hockey_mouse_drag_tracks_resized_rink",math.abs(x-1)<.001)
        Wheel.mousereleased();x=Wheel.controls(runtime,-1,0)
        check("hockey_keyboard_still_moves_paddle",x==-1)
        Wheel.touchpressed(runtime,"focus",121,328);Wheel.touchmoved(runtime,"focus",181,328)
        runtime.App.multiplayerFocusGrace=require("src.net.focus_grace").new({clock=function()return 0 end})
        require("src.runtime.lifecycle").install(runtime)
        runtime.airHockeyInputX=1;runtime.App.focus(false)
        check("hockey_focus_loss_neutralizes_input",neutral() and not Wheel.touchId and runtime.airHockeyInputX==0)
        check("hockey_background_touch_ignored",not Wheel.touchpressed(runtime,"background",121,328))
        runtime.App.focus(true)
        check("hockey_focus_resume_does_not_retain_touch",neutral())
        capture(runtime,Wheel,"air-hockey-wheel")
        Arcade.enter(runtime,"front_right")
        Arcade.keypressed(runtime,"right");Arcade.keypressed(runtime,"return")
        check("arcade_keyboard_selects_second_game",Arcade.view=="crisis")
        Arcade.enter(runtime,"front_right")
        Arcade.gamepadpressed(runtime,{},"dpright");Arcade.gamepadpressed(runtime,{},"a")
        check("arcade_controller_selects_second_game",Arcade.view=="crisis")
        Arcade.enter(runtime,"front_right")
        Arcade.gamepadpressed(runtime,{},"dpright");Arcade.gamepadpressed(runtime,{},"dpleft")
        Arcade.gamepadpressed(runtime,{},"a")
        check("arcade_controller_selects_first_game",Arcade.view=="title")
        Arcade.enter(runtime,"front_right");capture(runtime,Arcade,"arcade-retro-menu")
        Arcade.touchpressed(runtime,"exit",880,45)
        check("arcade_exit_still_returns_to_world",runtime.state.screen=="world")
    end,debug.traceback)
    Hockey.matches=oldMatches;Wheel.cancelInputs(false)
    love.graphics.getDimensions,love.window.getSafeArea=oldDimensions,oldSafeArea
    if not ok then error(err) end
end
return Test
