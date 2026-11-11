local Profile=require('src.player_profile')
local Settings=require('src.settings')
local Residents=require('src.home_residents')
local Session=require('src.net.session')
local Protocol=require('src.net.protocol')
local Harness=require('src.tests.support.network_impairment_harness')
local Test={}
local function player(id,name)
    return {id=id,name=name,x=720,y=202,sceneId='warehouse',character='rabbit-worker',
        velocityX=0,velocityY=0,intentX=1,intentY=0,moving=false,facing=1,animationDistance=0}
end
function Test.run(_,check)
    check('profile_names_bound_text_without_splitting_unicode',Profile.cleanName('  Mira  Worker\n')=='Mira Worker'
        and Profile.backspace('René')=='Ren' and #Profile.cleanName(string.rep('é',20))==24
        and not Profile.validName('   ') and not Profile.validName('Bad\nName'))
    local previous=Settings.load()
    local settings=Settings.normalize({playerName='Mira Worker',furColorway=3,overallsColorway=2})
    assert(Settings.save(settings))
    local loaded=Settings.load()
    check('device_profile_name_and_colors_survive_reload',loaded.playerName=='Mira Worker'
        and loaded.furColorway==3 and loaded.overallsColorway==2)
    local Options=require('src.screens.options_screen')
    local applied=0
    Options.enter({settings=loaded,save={SLOT_COUNT=3},applyPlayerProfile=function()applied=applied+1 end})
    local playerTab=Options.tabRect('character')
    Options.mousepressed(playerTab.x+playerTab.width/2,114,1);Options.mousepressed(300,195,1)
    Options.textinput('Rowan Worker');Options.mousepressed(700,195,1)
    check('profile_editor_saves_custom_names_with_touch_controls',Settings.load().playerName=='Rowan Worker'
        and applied==1 and not Options.wantsTextInput())
    Options.keypressed('n');Options.keypressed('backspace');Options.keypressed('return')
    check('profile_editor_rejects_blank_name',Options.wantsTextInput() and loaded.playerName=='Rowan Worker')
    Options.keypressed('escape')
    local submitted
    local Lan=require('src.screens.lan_screen')
    Lan.enter({settings=loaded,host=function(_,name)submitted=name;return true end})
    Lan.mousepressed(300,320,1);Lan.mousereleased(300,320,1)
    check('local_play_uses_saved_profile_name',submitted=='Rowan Worker')
    local Direct=require('src.screens.direct_screen')
    Direct.enter({settings=loaded,allowIpv4Host=true,hostIpv4=function(_,name)submitted=name;return true end})
    submitted=nil;Direct.mousepressed(480,300,1);Direct.mousereleased(480,300,1)
    check('direct_play_uses_saved_profile_name',submitted=='Rowan Worker')
    Direct.leave()
    local State=require('src.state')
    local state=State.new();local hp=player(1,'Rowan Worker')
    local now=0
    local network=Harness.new({maxClients=2})
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local hc={localPlayer=hp,moveRemote=function()end,
        bindResident=function(p,token,players)return Residents.bind(state,p,token,players)end,
        updatePlayerProfile=function(p)Residents.setName(state,p,p.name);host:markShopDirty(true)end,
        getShopSnapshot=function()return {state=assert(require('src.save_schema').snapshot(state)),
            player={x=hp.x,y=hp.y,sceneId=hp.sceneId,character=hp.character}}end}
    assert(host:startHost({name='Rowan Worker',furColorway=3,overallsColorway=2,
        addressOptions={socket={dns={gethostname=function()return 'profile-test'end,
            getaddrinfo=function()return {{addr='192.168.1.93'}}end}}}}))
    local clients,locals,contexts={},{},{}
    local function pump(count)
        for _=1,count or 10 do
            now=now+.1;network:advanceSteps(1)
            for i,c in ipairs(clients)do c:update(.1,contexts[i]) end
            host:update(.1,hc)
            for i,c in ipairs(clients)do c:update(0,contexts[i]);c:drainEvents()end
            host:drainEvents()
        end
    end
    for i=1,2 do
        local c=Session.new({transportFactory=network.factory,clock=function()return now end})
        clients[i]=c;locals[i]=player(i+1,'Guest '..i)
        contexts[i]={localPlayer=locals[i],inputX=0,inputY=0}
        assert(c:startClient('192.168.1.93:22122',{name='Guest '..i,furColorway=i+1,
            overallsColorway=i+2,residentToken=string.rep(tostring(i),64)}))
        pump(10);assert(c.ready,'profile guest could not join')
    end
    check('profile_handshake_preserves_names_and_individual_colors',clients[2].players[1].name=='Rowan Worker'
        and host.players[2].name=='Guest 1' and host.players[3].name=='Guest 2'
        and host.players[2].furColorway==2 and host.players[3].overallsColorway==4)
    local residentId=clients[1].residentId
    local credential=state.home.residents[residentId].credentialHash
    local hostRuntime={App={settings=loaded},World={player=hp},state=state,Settings=Settings,multiplayer=host}
    require('src.runtime.player_preferences').install(hostRuntime)
    loaded.playerName='River Worker';hostRuntime.App.syncPlayerProfile()
    local guestRuntime={App={settings=Settings.normalize({playerName='Aspen',furColorway=4,overallsColorway=5})},
        World={player=locals[1]},state={home=State.new().home},Settings=Settings,multiplayer=clients[1]}
    require('src.runtime.player_preferences').install(guestRuntime)
    guestRuntime.App.syncPlayerProfile();pump(15)
    check('profile_live_names_reach_other_clients_and_household_records',clients[2].players[1].name=='River Worker'
        and clients[2].players[2].name=='Aspen' and state.home.residents.owner.name=='River Worker'
        and state.home.residents[residentId].name=='Aspen'
        and state.home.residents[residentId].credentialHash==credential)
    check('profile_guest_colors_and_host_role_stay_independent',clients[2].players[2].furColorway==4
        and clients[2].players[2].overallsColorway==5 and Profile.isHost(clients[2].players[1])
        and not Profile.isHost(clients[2].players[2]))
    local invalid=Protocol.encode('input',{sessionId=host.sessionId,sequence=999,moveX=0,moveY=0,name='\n'})
    check('profile_wire_rejects_invalid_names',not invalid)
    local returning=player(4,'Aspen New')
    host.players[2]=nil
    assert(Residents.bind(state,returning,string.rep('1',64),host.players))
    check('profile_rename_keeps_private_resident_identity_on_rejoin',returning.homeResidentId==residentId
        and state.home.residents[residentId].name=='Aspen New')
    local another=State.new();hostRuntime.state=another;hostRuntime.App.syncPlayerProfile()
    check('profile_applies_to_another_save',another.home.residents.owner.name=='River Worker' and hp.name=='River Worker')
    local Speech=require('src.employee_speech')
    check('profile_npc_greetings_use_selected_name',Speech.message(1,'Aspen')=='Hello, Aspen!'
        and Speech.message(Speech.EMPLOYEE_HIGH_FIVE_REQUEST,'Aspen'):find('Aspen',1,true)~=nil)
    for _,c in ipairs(clients)do c:stop('profile test complete')end
    host:stop('profile test complete');assert(Settings.save(previous))
    Options.leave()
end
return Test
