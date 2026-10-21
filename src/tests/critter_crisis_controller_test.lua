local Crisis=require('src.critter_crisis')
local Screen=require('src.screens.critter_crisis_screen')
local Cabinet=require('src.screens.critter_kombat_screen')
local Input=require('src.critter_crisis_inputs')
local Games=require('src.breakroom_games')
local Test={}
local function controller()
    return {axes={},connected=true,isConnected=function(p)return p.connected end,
        getGamepadAxis=function(p,key)return p.axes[key] or 0 end}
end
function Test.run(_,check)
    Crisis.clear()
    local state={screen='critter_kombat',roomGameBay='front_left',breakroomGames=Games.defaultState()}
    state.breakroomGames.bays.front_left.critter_kombat=true
    local f=Games.CATALOG.critter_kombat
    local runtime={state=state,World={player={id=1,sceneId='front_left',x=f.interactionX,y=f.interactionY}},
        multiplayer={isClient=function()return false end},App={officeFitsScreen=function()return true end}}
    Cabinet.enter(runtime,'front_left');Cabinet.keypressed(runtime,'2');Screen.keypressed(runtime,'1')
    local pad=controller()
    Cabinet.gamepadaxis(runtime,pad,'rightx',0);Screen.update(.02,runtime)
    local x=Screen.aimX;pad.axes.rightx=1;Screen.update(.1,runtime);pad.axes.rightx=0
    check('crisis_controller_axis_only_connection_aims',Screen.aimX>x)
    pad.axes.triggerright=1;Screen.update(.02,runtime)
    local _,_,bits=Screen.controls(runtime);check('crisis_controller_solo_right_trigger_fires',bits==1)
    pad.axes.triggerright=0;pad.axes.triggerleft=1;Screen.update(.02,runtime)
    _,_,bits=Screen.controls(runtime);check('crisis_controller_solo_left_trigger_covers',bits==2)
    Screen.focus(false);Screen.focus(true);Screen.update(.02,runtime)
    _,_,bits=Screen.controls(runtime);check('crisis_controller_focus_requires_neutral_trigger',bits==0)
    pad.axes.triggerleft=0;Screen.update(.02,runtime);pad.axes.triggerright=1;Screen.update(.02,runtime)
    _,_,bits=Screen.controls(runtime);check('crisis_controller_trigger_rearms',bits==1)
    pad.connected=false;Screen.update(.02,runtime)
    _,_,bits=Screen.controls(runtime);check('crisis_controller_disconnect_clears_trigger',bits==0)
    pad=controller();Cabinet.gamepadaxis(runtime,pad,'rightx',0);Screen.update(.02,runtime)
    Cabinet.gamepadpressed(runtime,pad,'x');_,_,bits=Screen.controls(runtime)
    check('crisis_controller_reconnected_pad_reloads',bits==4);Cabinet.gamepadreleased(runtime,pad,'x')
    local session=Crisis.sessions.front_left;session.phase='finished'
    Cabinet.gamepadpressed(runtime,pad,'start')
    check('crisis_controller_solo_restarts',Crisis.sessions.front_left.roundId>session.roundId)
    for _,kind in ipairs({'mission'}) do
        Crisis.clear();Screen.enter();assert(Screen.command(runtime,'start_coop'))
        local pad=controller();Screen.gamepadaxis(runtime,pad,'rightx',0);Screen.update(.01,runtime)
        pad.axes.triggerright=1;Screen.update(.01,runtime)
        local p=Input.packet();check('crisis_controller_'..kind..'_LAN_trigger_uses_own_seat',p.buttons==1 and p.buttons2==0)
        pad.axes.triggerright=0;pad.axes.triggerleft=1;Screen.update(.01,runtime)
        check('crisis_controller_'..kind..'_left_trigger_action',Input.packet().buttons==2)
        pad.connected=false;Screen.update(.01,runtime)
        check('crisis_controller_'..kind..'_LAN_disconnect_releases',Input.packet().buttons==0)
    end
    check('crisis_controller_same_screen_action_removed',Crisis.startAction('start_mission_local')==nil)
    check('crisis_controller_2d_arcade_modes_removed',Crisis.startAction('start_range_coop')==nil
        and Crisis.startAction('start_stand_coop')==nil and Crisis.startAction('start_train_coop')==nil)
    Crisis.clear();Screen.enter()
end
return Test
