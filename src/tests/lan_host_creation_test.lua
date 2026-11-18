local Test={}

function Test.run(check)
    local Title=require('src.screens.title_screen')
    local Lan=require('src.screens.lan_screen')
    local Save=require('src.save')
    local originalList,originalRevision=Save.listSlots,Save.revision
    local cancelled,started=0,0
    local okay,reason=xpcall(function()
        Save.listSlots=function()return {{empty=true},{empty=false},{empty=true}}end
        Save.revision=function()return -120 end
        Title.enter(function()started=started+1 end)
        Title.beginNew(1,function()cancelled=cancelled+1 end)
        check('lan_new_shop_offers_story_and_quick_play',Title.mode=='start-mode')
        Title.keypressed('s')
        check('lan_new_story_keeps_story_setup',Title.mode=='shop-setup' and Title.setup.startMode=='story')
        Title.keypressed('escape')
        check('lan_new_shop_cancel_returns_to_multiplayer',cancelled==1 and started==0)
        Title.enter(function()started=started+1 end)
        Title.beginNew(2,function()cancelled=cancelled+1 end)
        check('lan_new_shop_preserves_occupied_slot_confirmation',Title.mode=='overwrite-confirm')
        Title.keypressed('escape')
        check('lan_overwrite_cancel_returns_without_starting',cancelled==2 and started==0)
        local called
        Lan.enter({slot=3,settings={playerName='Casey'},newHost=function(slot,name)called={slot,name};return true end})
        Lan.mousepressed(280,321,1)
        check('lan_new_host_touch_passes_slot_and_name',called and called[1]==3 and called[2]=='Casey')
    end,debug.traceback)
    Save.listSlots,Save.revision=originalList,originalRevision
    Title.enter(function()end)
    assert(okay,reason)

    local noop=function()end
    local order={}
    local payload={slot=2,state={campaign={mode='story'}}}
    local runtime={App={settings={}},Config={player={character='rabbit-worker'}},state={},
        Save={preflightWritable=function()return true end,load=function()error('New payload must not reload old save')end},
        SaveSchema={validPayload=function(value)return value==payload end},
        multiplayer={startHost=function()order[#order+1]='listen';return true end},
        createWorkshopAuthority=function()return {}end,lanReconnect={cancel=noop},
        lanDiscovery={startHost=function()return true end},isAndroidPlatform=function()return false end,
        startGame=function(value,mode)order[#order+1]=mode;return value==payload end}
    require('src.runtime.lan_startup').install(runtime)
    check('lan_new_story_listens_before_starting_opening',runtime.startLanHost(2,'Host',payload)
        and order[1]=='listen' and order[2]=='new')
    check('lan_new_host_rejects_wrong_slot',not runtime.startLanHost(1,'Host',payload))

    local Opening=require('src.story_opening')
    local active,update=Opening.active,Opening.update
    local network,discovery,neutral=0,0,false
    local R={App={},World={player={}},privateServerMode=true,
        multiplayer={isActive=function()return true end},
        updateLanConvenience=function()discovery=discovery+1 end,
        updateMultiplayer=function(_,x,y,boost)network=network+1;neutral=x==0 and y==0 and not boost end}
    require('src.runtime.simulation').install(R)
    Opening.active=function()return true end;Opening.update=noop
    okay,reason=pcall(R.App.update,1/60)
    Opening.active,Opening.update=active,update
    assert(okay,reason)
    check('lan_story_opening_services_network_without_local_movement',network==1 and discovery==1 and neutral)

    local calls=0
    local panelOpen,pending=true,0
    local P={App={},state={screen='world'},World={player={sceneId='barn'}},
        MultiplayerHud={isOpen=function()return panelOpen end},
        multiplayer={hudInfo=function()return {pendingJoinCount=pending}end}}
    require('src.runtime.pointer_dispatch').install(P)
    P.multiplayerHudMousepressed=function()calls=calls+1;return true end
    for _,scene in ipairs({'barn','commute','grocery'}) do
        P.World.player.sceneId=scene
        check('lan_join_approval_reachable_in_'..scene,P.sceneMultiplayerHudPointer(1,1,1))
    end
    P.state.screen='title'
    check('lan_scene_approval_does_not_intercept_menus',not P.sceneMultiplayerHudPointer(1,1,1) and calls==3)
    P.state.screen='world';panelOpen=false
    check('lan_closed_scene_panel_does_not_block_navigation',not P.sceneMultiplayerHudPointer(1,1,1))
    pending=1
    check('lan_pending_join_keeps_scene_session_access_visible',P.sceneMultiplayerHudPointer(1,1,1))

    local message,mode
    local E={multiplayer={networkKind='lan',drainEvents=function()return {{type='approval_waiting'}}end},
        LanScreen={setMessage=function(text,value)message,mode=text,value end}}
    require('src.runtime.multiplayer_events').install(E)
    E.handleMultiplayerEvents()
    check('lan_join_screen_explains_host_profile_approval',mode=='connecting'
        and message:find('NEW CLIENT',1,true) and message:find('Players',1,true))

    local session=require('src.net.session').new()
    session.mode='host';session.networkKind='lan';session.localId=1
    session.players={[1]={name='Host'},[2]={name='Returning client'}}
    local info=session:hudInfo()
    check('lan_approval_panel_lists_already_connected_guests',#info.connectedGuests==1
        and info.connectedGuests[1].playerId==2 and info.connectedGuests[1].name=='Returning client')
end
return Test
