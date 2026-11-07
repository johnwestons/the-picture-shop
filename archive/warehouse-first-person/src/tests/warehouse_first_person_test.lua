local View=require("src.warehouse_first_person")
local MobileControls=require("src.mobile_controls")
local Test={}

function Test.run(context,check)
    local Runtime={
        state=require("src.state").new(),
        World={player={sceneId="warehouse",x=180,y=180}},
        Config=require("src.config"),
    }
    Runtime.state.screen="world"
    local button=View.cameraButton(Runtime)
    check("warehouse_camera_option_is_visible_in_the_isometric_scene",
        button and button.x>=0 and button.x+button.width<=Runtime.Config.baseWidth
            and View.cameraRow(Runtime,2).y+View.cameraRow(Runtime,2).height<=Runtime.Config.baseHeight)
    check("warehouse_camera_button_opens_mode_choices",
        View:cameraPointer(Runtime,button.x+button.width*.5,button.y+button.height*.5,1)
            and View.cameraRow(Runtime,2)~=nil)
    local first=View.cameraRow(Runtime,2)
    local opened=View:cameraPointer(Runtime,first.x+20,first.y+12,1)
    check("warehouse_first_person_mode_is_selectable_from_camera_menu",opened and View:isActive(Runtime))
    check("warehouse_camera_menu_can_open_and_return_to_isometric_on_pc",
        View:keypressed(Runtime,"c")
            and View:cameraPointer(Runtime,View.cameraRow(Runtime,1).x+20,View.cameraRow(Runtime,1).y+12,1)
            and not View:isActive(Runtime))
    local graphics=love.graphics
    local canvas=graphics.newCanvas(Runtime.Config.baseWidth,Runtime.Config.baseHeight)
    graphics.push("all");graphics.setCanvas(canvas);graphics.origin();graphics.clear(0,0,0,0)
    View:drawCameraOption(Runtime)
    graphics.pop();canvas:release()
    check("warehouse_camera_option_draws_in_the_hud",true)

    local turns,pointers={},{}
    local controls=MobileControls.new({enabled=true,
        toGame=function(x,y)return x,y end,
        pressKey=function()end,releaseKey=function()end,
        pressPointer=function(x,y)pointers[#pointers+1]={"down",x,y}end,
        movePointer=function()end,
        releasePointer=function(x,y)pointers[#pointers+1]={"up",x,y}end,
        gameplayActive=function()return true end,
        touchLookActive=function()return true end,
        updateTouchLook=function(dx,dy)turns[#turns+1]={dx,dy}end,
    })
    controls:setBounds({left=0,top=0,right=960,bottom=678,width=960,height=678,scale=1})
    controls:touchpressed("look",450,250)
    controls:touchmoved("look",490,280,40,30)
    controls:touchreleased("look",490,280)
    check("warehouse_mobile_drag_looks_without_interacting",
        #turns==1 and turns[1][1]==40 and turns[1][2]==30 and #pointers==0)
    controls:touchpressed("tap",500,250)
    controls:touchreleased("tap",500,250)
    check("warehouse_mobile_tap_remains_a_world_interaction",
        #pointers==2 and pointers[1][1]=="down" and pointers[2][1]=="up"
            and pointers[1][2]==500 and pointers[1][3]==250)
    View:keypressed(Runtime,"f1")
    View:keypressed(Runtime,"escape")
    check("warehouse_f1_camera_shortcut_still_enters_and_exits",not View:isActive(Runtime))

    local app=context and context.appRuntime
    if app and app.World and app.World.player then
        local oldScreen,oldScene=app.state.screen,app.World.player.sceneId
        app.state.screen="world";app.World.player.sceneId="warehouse"
        View:keypressed(app,"f1")
        local appCanvas=love.graphics.newCanvas(app.Config.baseWidth,app.Config.baseHeight)
        local g=love.graphics
        g.push("all");g.setCanvas(appCanvas);g.origin();g.clear(0,0,0,0)
        local okay,drawn=pcall(function()
            local result=View:draw(app)
            View:drawCameraOption(app)
            return result
        end)
        g.pop();appCanvas:release()
        if View:isActive(app) then View:keypressed(app,"f1") end
        app.state.screen,app.World.player.sceneId=oldScreen,oldScene
        check("warehouse_first_person_mobile_runtime_draws_with_camera_control",okay and drawn==true)
    end
end

return Test
